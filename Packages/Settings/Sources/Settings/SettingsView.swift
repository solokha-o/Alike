import SwiftUI
import StoreKit
import Core
import DesignSystem
import NavigationKit
import Purchases
import PurchasesUI
import UserGuide
#if canImport(UIKit)
import UIKit
#endif

enum SettingsRoute: Hashable {
    case userGuide
    case userGuideTopic(GuideTopicID)
    case deleteAllData
}

private enum RestorePurchasesFeedback: String, Identifiable {
    case restored
    case noActiveSubscription
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restored:
            appLocalized("Alike Pro is active")
        case .noActiveSubscription:
            appLocalized("No active Alike Pro subscription was found.")
        case .failed:
            appLocalized("Couldn't Restore Purchases")
        }
    }

    var message: String {
        switch self {
        case .restored:
            appLocalized("Your Alike Pro subscription was restored.")
        case .noActiveSubscription:
            appLocalized("You can continue using Alike Free.")
        case .failed:
            appLocalized("Please check your connection and try restoring again.")
        }
    }
}

/// Settings screen
public struct SettingsView: View {
    @Environment(\.requestReview) private var requestReview
    @Binding var sensitivity: SensitivityLevel
    @Binding var needsRescan: Bool
    @State private var viewModel: SettingsViewModel
    @State private var deleteAllDataModel: DeleteAllDataModel
    @State private var presentedPremiumFeature: PremiumFeature?
    @State private var isRestoringPurchases = false
    @State private var restorePurchasesFeedback: RestorePurchasesFeedback?
    private let premiumAccess: any PremiumAccessControlling
    private let subscriptionStore: SubscriptionStore?
#if DEBUG
    @AppStorage(PremiumFeature.unlimitedScans.debugOverrideDefaultsKey)
    private var debugUnlockUnlimitedRescans = false
    @AppStorage(PremiumFeature.screenshotCleanup.debugOverrideDefaultsKey)
    private var debugUnlockScreenshotCleanup = false
    @AppStorage(PremiumFeature.blurredPhotoCleanup.debugOverrideDefaultsKey)
    private var debugUnlockBlurredPhotoCleanup = false
    @AppStorage(PremiumFeature.advancedFilters.debugOverrideDefaultsKey)
    private var debugUnlockAdvancedFilters = false
    @AppStorage(PremiumFeature.batchCleanup.debugOverrideDefaultsKey)
    private var debugUnlockBatchCleanup = false
    @AppStorage(PremiumFeature.cleanupReminderCustomization.debugOverrideDefaultsKey)
    private var debugUnlockCleanupReminders = false
#endif
    
    public init(
        sensitivity: Binding<SensitivityLevel>,
        needsRescan: Binding<Bool>,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        subscriptionStore: SubscriptionStore? = nil,
        onDeleteAllData: @escaping @MainActor @Sendable () async throws -> Void = {},
        viewModel: SettingsViewModel = SettingsViewModel()
    ) {
        self._sensitivity = sensitivity
        self._needsRescan = needsRescan
        self.premiumAccess = premiumAccess
        self.subscriptionStore = subscriptionStore
        self._viewModel = State(initialValue: viewModel)
        self._deleteAllDataModel = State(
            initialValue: DeleteAllDataModel(operation: onDeleteAllData)
        )
    }
    
    public var body: some View {
        RoutedNavigationStack { router in
            formContent(router: router)
        } destination: { route, _ in
            destination(for: route)
        }
        .task(id: hasCleanupReminderAccess) {
            await viewModel.loadCleanupReminderState(
                isPremiumUnlocked: hasCleanupReminderAccess
            )
        }
        .sheet(item: $presentedPremiumFeature) { feature in
            premiumFeatureSheet(for: feature)
        }
        .alert(
            appLocalized("Couldn't Update Reminder"),
            isPresented: isCleanupReminderErrorPresented
        ) {
            Button(appLocalized("OK"), role: .cancel) {
                viewModel.dismissCleanupReminderError()
            }
        } message: {
            Text(viewModel.cleanupReminderErrorMessage ?? "")
        }
        .alert(item: $restorePurchasesFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text(appLocalized("OK")))
            )
        }
    }

    private func formContent(router: StackRouter<SettingsRoute>) -> some View {
        Form {
            subscriptionSection
            languageSection
            analysisSection
            cleanupReminderSection
#if DEBUG
            debugSection
#endif
            supportSection(router: router)
            dataPrivacySection(router: router)
            aboutSection
        }
        .navigationTitle(Text(appLocalized("Settings")))
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .userGuide:
            UserGuideHubView { SettingsRoute.userGuideTopic($0) }
        case .userGuideTopic(let topicID):
            UserGuideTopicView(topicID: topicID)
        case .deleteAllData:
            DeleteAllDataView(model: deleteAllDataModel)
        }
    }

    @ViewBuilder
    private func premiumFeatureSheet(for feature: PremiumFeature) -> some View {
        SubscriptionPaywallView(
            context: .feature(feature),
            store: subscriptionStore
        )
    }

    private var subscriptionSection: some View {
        Section {
            PremiumStatusCard(
                status: subscriptionStatus,
                isRestoring: isRestoringPurchases,
                onViewPlans: {
                    presentedPremiumFeature = .unlimitedScans
                },
                onRestore: restorePurchases
            )
        } header: {
            Text(appLocalized("Subscription"))
        }
    }

    private var subscriptionStatus: PremiumStatusCard.Status {
        guard let subscriptionStore else {
            return premiumAccess.entitlementState.isPremium
                ? .active(planName: nil, expirationDate: premiumAccess.entitlementState.expirationDate)
                : .free
        }

        let entitlement = subscriptionStore.entitlementState
        if entitlement.source == .unknown {
            switch subscriptionStore.productLoadState {
            case .idle, .loading:
                return .loading
            case .loaded, .failed, .unconfigured:
                return .unavailable
            }
        }
        if entitlement.isPremium {
            let planName = entitlement.productID.flatMap { productID in
                subscriptionStore.products.values.first(where: { $0.id == productID })?.displayName
            }
            return .active(planName: planName, expirationDate: entitlement.expirationDate)
        }
        if case .failed = subscriptionStore.productLoadState {
            return .unavailable
        }
        return .free
    }

    private func restorePurchases() {
        guard let subscriptionStore else { return }
        isRestoringPurchases = true
        Task {
            defer { isRestoringPurchases = false }
            do {
                try await subscriptionStore.restorePurchases()
                restorePurchasesFeedback = subscriptionStore.entitlementState.isPremium
                    ? .restored
                    : .noActiveSubscription
            } catch {
                AppLog.ui.error(
                    "\(AppLog.tag(.error, "Failed to restore purchases: \(error.localizedDescription)"))"
                )
                restorePurchasesFeedback = .failed
            }
        }
    }

    private var cleanupReminderSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { viewModel.cleanupReminderState.isEnabled },
                    set: { isEnabled in
                        viewModel.setCleanupReminderEnabled(
                            isEnabled,
                            isPremiumUnlocked: hasCleanupReminderAccess
                        )
                    }
                )
            ) {
                Label {
                    Text(appLocalized("Weekly cleanup reminder"))
                } icon: {
                    Image(systemName: "bell.badge")
                }
            }
            .disabled(viewModel.isUpdatingCleanupReminder)
            .accessibilityHint(Text(appLocalized("Enable a weekly reminder to come back and continue cleanup")))

            if viewModel.cleanupReminderState.authorizationStatus == .denied {
                Text(appLocalized("Notifications are turned off for Alike. Enable them in Settings to receive your weekly cleanup reminder."))
                    .foregroundColor(.secondary)

#if canImport(UIKit)
                Button(appLocalized("Open Settings")) {
                    openAppSettings()
                }
#endif
            }

            if viewModel.cleanupReminderState.isScheduleCustomizationLocked {
                HStack {
                    Label {
                        Text(appLocalized("Reminder schedule"))
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    Spacer()
                    Text(scheduleDescription(viewModel.cleanupReminderState.schedule))
                        .foregroundStyle(.secondary)
                }

                Button {
                    presentedPremiumFeature = .cleanupReminderCustomization
                } label: {
                    HStack(spacing: Spacing.small) {
                        Image(systemName: "lock.badge.clock")
                            .foregroundStyle(Color.accent)
                        Text(appLocalized("Customize day & time"))
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(appLocalized("Open premium details for custom cleanup reminder scheduling")))
            } else {
                HStack {
                    Label {
                        Text(appLocalized("Reminder schedule"))
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    Spacer()
                    Text(scheduleDescription(viewModel.cleanupReminderState.schedule))
                        .foregroundStyle(.secondary)
                }

                Picker(
                    appLocalized("Reminder day"),
                    selection: Binding(
                        get: { viewModel.cleanupReminderState.schedule.weekday },
                        set: { weekday in
                            viewModel.setCleanupReminderSchedule(
                                CleanupReminderSchedule(
                                    weekday: weekday,
                                    hour: viewModel.cleanupReminderState.schedule.hour,
                                    minute: viewModel.cleanupReminderState.schedule.minute
                                ),
                                isPremiumUnlocked: hasCleanupReminderAccess
                            )
                        }
                    )
                ) {
                    ForEach(weekdayOptions, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .disabled(viewModel.isUpdatingCleanupReminder)

                DatePicker(
                    appLocalized("Reminder time"),
                    selection: Binding(
                        get: { reminderTimeDate(for: viewModel.cleanupReminderState.schedule) },
                        set: { date in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                            viewModel.setCleanupReminderSchedule(
                                CleanupReminderSchedule(
                                    weekday: viewModel.cleanupReminderState.schedule.weekday,
                                    hour: components.hour ?? viewModel.cleanupReminderState.schedule.hour,
                                    minute: components.minute ?? viewModel.cleanupReminderState.schedule.minute
                                ),
                                isPremiumUnlocked: hasCleanupReminderAccess
                            )
                        }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .disabled(viewModel.isUpdatingCleanupReminder)
            }
        } header: {
            Text(appLocalized("Cleanup Reminder"))
        } footer: {
            Text(cleanupReminderFooterText)
        }
    }
    
    // MARK: - Analysis Section
    private var analysisSection: some View {
        Section {
            Picker(selection: $sensitivity) {
                ForEach(SensitivityLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            } label: {
                Text(appLocalized("Sensitivity"))
            }
            .accessibilityHint(Text(appLocalized("Higher sensitivity finds more similar photos but may include less alike images")))
            .onChange(of: sensitivity) { _, _ in
                needsRescan = viewModel.rescanRequiredAfterSensitivityChange()
            }
        } header: {
            Text(appLocalized("Analysis"))
        } footer: {
            Text(appLocalized("Higher sensitivity finds more similar photos but may include less alike images"))
        }
    }

#if DEBUG
    private var debugSection: some View {
        Section {
            Toggle(
                appLocalized("Unlock Unlimited Scans Premium Feature"),
                isOn: $debugUnlockUnlimitedRescans
            )

            Toggle(
                appLocalized("Unlock Screenshot Cleanup Premium Feature"),
                isOn: $debugUnlockScreenshotCleanup
            )
            .accessibilityHint(Text(appLocalized("Enable premium screenshot cleanup access in debug builds")))

            Toggle(
                appLocalized("Unlock Blurred Photo Cleanup Premium Feature"),
                isOn: $debugUnlockBlurredPhotoCleanup
            )
            .accessibilityHint(Text(appLocalized("Enable premium blurred photo cleanup access in debug builds")))

            Toggle(
                appLocalized("Unlock Advanced Filters Premium Feature"),
                isOn: $debugUnlockAdvancedFilters
            )

            Toggle(
                appLocalized("Unlock Batch Cleanup Premium Feature"),
                isOn: $debugUnlockBatchCleanup
            )

            Toggle(
                appLocalized("Unlock Custom Reminder Schedule Premium Feature"),
                isOn: $debugUnlockCleanupReminders
            )
            .accessibilityHint(Text(appLocalized("Enable premium reminder schedule customization in debug builds")))
        } header: {
            Text(appLocalized("Debug"))
        } footer: {
            Text(appLocalized("This override is available only in debug builds and affects local premium gating."))
        }
    }
#endif
    
    // MARK: - Support Section
    private func supportSection(router: StackRouter<SettingsRoute>) -> some View {
        Section {
            Button {
                router.push(.userGuide)
            } label: {
                Label {
                    Text(appLocalized("How to Use"))
                } icon: {
                    Image(systemName: "book")
                }
            }
            .accessibilityHint(Text(appLocalized("Open usage instructions and cleanup workflow tips")))
            
            ShareLink(item: AppStoreLinks.product) {
                Label {
                    Text(appLocalized("Share App"))
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .accessibilityHint(Text(appLocalized("Share the app using available sharing options")))
            
            Button {
                viewModel.handleRateTapped(requestReview: requestReview)
            } label: {
                Label {
                    Text(appLocalized("Rate on App Store"))
                } icon: {
                    Image(systemName: "star")
                }
            }
            .accessibilityHint(Text(appLocalized("Request the App Store rating prompt")))
            .sensoryFeedback(.selection, trigger: viewModel.reviewTrigger)
            
            Link(destination: URL(string: "mailto:oleksandr.solokha@gmail.com?subject=Alike Feedback")!) {
                Label {
                    Text(appLocalized("Contact Developer"))
                } icon: {
                    Image(systemName: "envelope")
                }
            }
            .accessibilityHint(Text(appLocalized("Open email composer to contact the developer")))
        } header: {
            Text(appLocalized("Support"))
        }
    }

    // MARK: - Data & Privacy Section
    private func dataPrivacySection(router: StackRouter<SettingsRoute>) -> some View {
        Section {
            Button {
                router.push(.deleteAllData)
            } label: {
                Label {
                    Text(appLocalized("Delete Alike Data"))
                } icon: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red)
            }
            .accessibilityHint(
                Text(appLocalized("Review and permanently delete data stored by Alike on this device"))
            )
        } header: {
            Text(appLocalized("Data & Privacy"))
        } footer: {
            Text(appLocalized("Your photo library is never deleted by this action."))
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        Section {
            HStack {
                Text(appLocalized("Version"))
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Language Section
    private var languageSection: some View {
        Section {
            Button {
                openLanguageSettings()
            } label: {
                Label {
                    Text(appLocalized("Change Language"))
                } icon: {
                    Image(systemName: "globe")
                }
            }
            .accessibilityHint(Text(appLocalized("Open system settings to change app language")))
        } header: {
            Text(appLocalized("Language"))
        }
    }

    private func openLanguageSettings() {
        #if os(iOS)
        openAppSettings()
        #endif
    }

    private var hasCleanupReminderAccess: Bool {
        premiumAccess.hasAccess(to: .cleanupReminderCustomization)
    }

    private var isCleanupReminderErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.cleanupReminderErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissCleanupReminderError()
                }
            }
        )
    }

    private var weekdayOptions: [(value: Int, title: String)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = .current
        let weekdaySymbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        let firstWeekdayIndex = max(1, min(calendar.firstWeekday, weekdaySymbols.count)) - 1

        return (0..<weekdaySymbols.count).map { offset in
            let index = (firstWeekdayIndex + offset) % weekdaySymbols.count
            return (value: index + 1, title: weekdaySymbols[index])
        }
    }

    private var cleanupReminderFooterText: String {
        if hasCleanupReminderAccess {
            return appLocalized("Premium lets you choose a custom weekly reminder schedule.")
        }

        return appLocalized(
            "Free reminders use Sunday at 6:00 PM. Unlock premium to choose your own day and time."
        )
    }

    private func reminderTimeDate(for schedule: CleanupReminderSchedule) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = schedule.hour
        components.minute = schedule.minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func scheduleDescription(_ schedule: CleanupReminderSchedule) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        let weekdaySymbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        let weekdayIndex = max(1, min(schedule.weekday, weekdaySymbols.count)) - 1
        let weekday = weekdaySymbols.isEmpty ? "" : weekdaySymbols[weekdayIndex]
        let timeDate = reminderTimeDate(for: schedule)

        formatter.timeStyle = .short
        formatter.dateStyle = .none

        return "\(weekday) at \(formatter.string(from: timeDate))"
    }

    #if canImport(UIKit)
    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
    }
    #endif
}

private struct DeleteAllDataView: View {
    let model: DeleteAllDataModel

    @State private var isConfirmationPresented = false

    var body: some View {
        Form {
            Section {
                dataRow(
                    appLocalized("Scan results and analysis caches"),
                    systemImage: "sparkles.rectangle.stack"
                )
                dataRow(
                    appLocalized("Cleanup progress, sessions, and history"),
                    systemImage: "clock.arrow.circlepath"
                )
                dataRow(
                    appLocalized("Grid, sensitivity, and reminder preferences"),
                    systemImage: "slider.horizontal.3"
                )
            } header: {
                Text(appLocalized("What will be deleted"))
            }

            Section {
                dataRow(
                    appLocalized("Your photos and Recently Deleted items"),
                    systemImage: "photo.on.rectangle"
                )
                dataRow(
                    appLocalized("Photo access and Alike Pro subscription"),
                    systemImage: "checkmark.shield"
                )
                dataRow(
                    appLocalized("Monthly free-scan allowance"),
                    systemImage: "calendar"
                )
            } header: {
                Text(appLocalized("What will stay"))
            }

            Section {
                Button(role: .destructive) {
                    isConfirmationPresented = true
                } label: {
                    HStack {
                        if model.isDeleting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(
                            appLocalized(
                                model.isDeleting
                                    ? "Deleting..."
                                    : "Delete Alike Data"
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(model.isDeleting)
                .accessibilityHint(
                    Text(appLocalized("Permanently delete Alike data after confirmation"))
                )
            } footer: {
                Text(appLocalized("This action can't be undone. Alike will replay onboarding when deletion finishes."))
            }
        }
        .navigationTitle(Text(appLocalized("Delete Alike Data")))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationBarBackButtonHidden(model.isDeleting)
        .confirmationDialog(
            appLocalized("Delete all Alike data?"),
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(appLocalized("Delete Alike Data"), role: .destructive) {
                startDeletion()
            }
            Button(appLocalized("Cancel"), role: .cancel) {}
        } message: {
            Text(appLocalized("This permanently deletes Alike's local results, cleanup history, and preferences. Your photos and subscription will stay."))
        }
        .alert(
            appLocalized("Couldn't Delete Alike Data"),
            isPresented: isDeletionErrorPresented
        ) {
            Button(appLocalized("Try Again")) {
                startDeletion()
            }
            Button(appLocalized("Cancel"), role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var isDeletionErrorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissError()
                }
            }
        )
    }

    private func startDeletion() {
        Task {
            await model.deleteAllData()
        }
    }

    private func dataRow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }
}

// MARK: - Preview
#Preview {
    SettingsView(
        sensitivity: .constant(.medium),
        needsRescan: .constant(false)
    )
}
