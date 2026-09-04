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
#if DEBUG
    case bestShotCalibration
#endif
}

private enum RestorePurchasesFeedback: String, Identifiable {
    case restored
    case noActiveSubscription
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restored:
            SettingsL10n.Main.alikeProIsActive
        case .noActiveSubscription:
            SettingsL10n.Main.noActiveAlikeProSubscription
        case .failed:
            SettingsL10n.Main.couldntRestorePurchases
        }
    }

    var message: String {
        switch self {
        case .restored:
            SettingsL10n.Main.alikeProSubscriptionWasRestored
        case .noActiveSubscription:
            SettingsL10n.Main.canContinueUsingAlikeFree
        case .failed:
            SettingsL10n.Main.pleaseCheckConnectionTryRestoring
        }
    }
}

/// Settings screen
public struct SettingsView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.subscriptionLegalLinks) private var legalLinks
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
            SettingsL10n.Main.couldntUpdateReminder,
            isPresented: isCleanupReminderErrorPresented
        ) {
            Button(SettingsL10n.Main.ok, role: .cancel) {
                viewModel.dismissCleanupReminderError()
            }
        } message: {
            Text(viewModel.cleanupReminderErrorMessage ?? "")
        }
        .alert(item: $restorePurchasesFeedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text(SettingsL10n.Main.ok))
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
            debugSection(router: router)
#endif
            supportSection(router: router)
            dataPrivacySection(router: router)
            legalSection
            aboutSection
        }
        .navigationTitle(Text(SettingsL10n.Main.settings))
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
#if DEBUG
        case .bestShotCalibration:
            BestShotCalibrationLabelingView()
#endif
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
            Text(SettingsL10n.Main.subscription)
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
                    Text(SettingsL10n.Main.weeklyCleanupReminder)
                } icon: {
                    Image(systemName: "bell.badge")
                }
            }
            .disabled(viewModel.isUpdatingCleanupReminder)
            .accessibilityHint(Text(SettingsL10n.Main.enableWeeklyReminderComeBack))

            if viewModel.cleanupReminderState.authorizationStatus == .denied {
                Text(SettingsL10n.Main.notificationsTurnedOffAlikeEnable)
                    .foregroundColor(.secondary)

#if canImport(UIKit)
                Button(SettingsL10n.Main.openSettings) {
                    openAppSettings()
                }
#endif
            }

            if viewModel.cleanupReminderState.isScheduleCustomizationLocked {
                HStack {
                    Label {
                        Text(SettingsL10n.Main.reminderSchedule)
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
                        Text(SettingsL10n.Main.customizeDayTime)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(SettingsL10n.Main.openPremiumDetailsCustomCleanup))
            } else {
                HStack {
                    Label {
                        Text(SettingsL10n.Main.reminderSchedule)
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    Spacer()
                    Text(scheduleDescription(viewModel.cleanupReminderState.schedule))
                        .foregroundStyle(.secondary)
                }

                Picker(
                    SettingsL10n.Main.reminderDay,
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
                    SettingsL10n.Main.reminderTime,
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
            Text(SettingsL10n.Main.cleanupReminder)
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
                Text(SettingsL10n.Main.sensitivity)
            }
            .accessibilityHint(Text(SettingsL10n.Main.higherSensitivityFindsMoreSimilar))
            .onChange(of: sensitivity) { _, _ in
                needsRescan = viewModel.rescanRequiredAfterSensitivityChange()
            }
        } header: {
            Text(SettingsL10n.Main.analysis)
        } footer: {
            Text(SettingsL10n.Main.higherSensitivityFindsMoreSimilar)
        }
    }

#if DEBUG
    private func debugSection(router: StackRouter<SettingsRoute>) -> some View {
        Section {
            Button {
                router.push(.bestShotCalibration)
            } label: {
                Label {
                    // Developer tooling only, never shipped, so the label is
                    // a plain literal instead of a localized entry.
                    Text("Best Shot Calibration")
                } icon: {
                    Image(systemName: "star.square.on.square")
                }
            }

            Toggle(
                SettingsL10n.Main.unlockUnlimitedScansPremiumFeature,
                isOn: $debugUnlockUnlimitedRescans
            )

            Toggle(
                SettingsL10n.Main.unlockScreenshotCleanupPremiumFeature,
                isOn: $debugUnlockScreenshotCleanup
            )
            .accessibilityHint(Text(SettingsL10n.Main.enablePremiumScreenshotCleanupAccess))

            Toggle(
                SettingsL10n.Main.unlockBlurredPhotoCleanupPremium,
                isOn: $debugUnlockBlurredPhotoCleanup
            )
            .accessibilityHint(Text(SettingsL10n.Main.enablePremiumBlurredPhotoCleanup))

            Toggle(
                SettingsL10n.Main.unlockAdvancedFiltersPremiumFeature,
                isOn: $debugUnlockAdvancedFilters
            )

            Toggle(
                SettingsL10n.Main.unlockBatchCleanupPremiumFeature,
                isOn: $debugUnlockBatchCleanup
            )

            Toggle(
                SettingsL10n.Main.unlockCustomReminderSchedulePremium,
                isOn: $debugUnlockCleanupReminders
            )
            .accessibilityHint(Text(SettingsL10n.Main.enablePremiumReminderScheduleCustomization))
        } header: {
            Text(SettingsL10n.Main.debug)
        } footer: {
            Text(SettingsL10n.Main.thisOverrideAvailableOnlyDebug)
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
                    Text(SettingsL10n.Main.howToUse)
                } icon: {
                    Image(systemName: "book")
                }
            }
            .accessibilityHint(Text(SettingsL10n.Main.openUsageInstructionsCleanupWorkflow))
            
            ShareLink(item: AppStoreLinks.product) {
                Label {
                    Text(SettingsL10n.Main.shareApp)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .accessibilityHint(Text(SettingsL10n.Main.shareAppUsingAvailableSharing))
            
            Button {
                viewModel.handleRateTapped(requestReview: requestReview)
            } label: {
                Label {
                    Text(SettingsL10n.Main.rateOnAppStore)
                } icon: {
                    Image(systemName: "star")
                }
            }
            .accessibilityHint(Text(SettingsL10n.Main.requestAppStoreRatingPrompt))
            .sensoryFeedback(.selection, trigger: viewModel.reviewTrigger)
            
            // The subject is percent-encoded in the literal rather than left to
            // URL(string:), which only accepts the raw space because it defaults to
            // encodingInvalidCharacters: true. Encoding it here keeps the force
            // unwrap valid under strict RFC 3986 parsing too.
            Link(destination: URL(string: "mailto:oleksandr.solokha@gmail.com?subject=Alike%20Feedback")!) {
                Label {
                    Text(SettingsL10n.Main.contactDeveloper)
                } icon: {
                    Image(systemName: "envelope")
                }
            }
            .accessibilityHint(Text(SettingsL10n.Main.openEmailComposerContactDeveloper))
        } header: {
            Text(SettingsL10n.Main.support)
        }
    }

    // MARK: - Data & Privacy Section
    private func dataPrivacySection(router: StackRouter<SettingsRoute>) -> some View {
        Section {
            Button {
                router.push(.deleteAllData)
            } label: {
                Label {
                    Text(SettingsL10n.Main.deleteAlikeData)
                } icon: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red)
            }
            .accessibilityHint(
                Text(SettingsL10n.Main.reviewPermanentlyDeleteDataStored)
            )
        } header: {
            Text(SettingsL10n.Main.dataPrivacy)
        } footer: {
            Text(SettingsL10n.Main.photoLibraryNeverDeletedBy)
        }
    }

    // MARK: - Legal Section
    private var legalSection: some View {
        Section {
            if let privacyPolicy = legalLinks.privacyPolicy {
                Link(destination: privacyPolicy) {
                    Label {
                        Text(SettingsL10n.Main.privacyPolicy)
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                }
                .accessibilityHint(Text(SettingsL10n.Main.openAlikePrivacyPolicyBrowser))
            }

            if let termsOfUse = legalLinks.termsOfUse {
                Link(destination: termsOfUse) {
                    Label {
                        Text(SettingsL10n.Main.termsOfUse)
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                }
                .accessibilityHint(Text(SettingsL10n.Main.openAlikeTermsUseBrowser))
            }
        } header: {
            Text(SettingsL10n.Main.legal)
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        Section {
            HStack {
                Text(SettingsL10n.Main.version)
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
                    Text(SettingsL10n.Main.changeLanguage)
                } icon: {
                    Image(systemName: "globe")
                }
            }
            .accessibilityHint(Text(SettingsL10n.Main.openSystemSettingsChangeApp))
        } header: {
            Text(SettingsL10n.Main.language)
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
        let calendar = Calendar.alikeFormattingCalendar
        let formatter = DateFormatter()
        formatter.locale = .alikeFormatting
        let weekdaySymbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        let firstWeekdayIndex = max(1, min(calendar.firstWeekday, weekdaySymbols.count)) - 1

        return (0..<weekdaySymbols.count).map { offset in
            let index = (firstWeekdayIndex + offset) % weekdaySymbols.count
            return (value: index + 1, title: weekdaySymbols[index])
        }
    }

    private var cleanupReminderFooterText: String {
        CleanupReminderCopy.footerText(
            hasPremiumAccess: hasCleanupReminderAccess,
            calendar: .alikeFormattingCalendar,
            locale: .alikeFormatting
        )
    }

    private func reminderTimeDate(for schedule: CleanupReminderSchedule) -> Date {
        CleanupReminderCopy.reminderTimeDate(for: schedule, calendar: .alikeFormattingCalendar)
    }

    private func scheduleDescription(_ schedule: CleanupReminderSchedule) -> String {
        CleanupReminderCopy.scheduleDescription(
            schedule,
            calendar: .alikeFormattingCalendar,
            locale: .alikeFormatting
        )
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
                    SettingsL10n.Main.scanResultsAndAnalysisCaches,
                    systemImage: "sparkles.rectangle.stack"
                )
                dataRow(
                    SettingsL10n.Main.cleanupProgressSessionsAndHistory,
                    systemImage: "clock.arrow.circlepath"
                )
                dataRow(
                    SettingsL10n.Main.gridSensitivityAndReminderPreferences,
                    systemImage: "slider.horizontal.3"
                )
            } header: {
                Text(SettingsL10n.Main.whatWillBeDeleted)
            }

            Section {
                dataRow(
                    SettingsL10n.Main.photosRecentlyDeletedItems,
                    systemImage: "photo.on.rectangle"
                )
                dataRow(
                    SettingsL10n.Main.photoAccessAlikeProSubscription,
                    systemImage: "checkmark.shield"
                )
                dataRow(
                    SettingsL10n.Main.monthlyFreeScanAllowance,
                    systemImage: "calendar"
                )
            } header: {
                Text(SettingsL10n.Main.whatWillStay)
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
                            (model.isDeleting
                                    ? SettingsL10n.Main.deleting
                                    : SettingsL10n.Main.deleteAlikeData)
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(model.isDeleting)
                .accessibilityHint(
                    Text(SettingsL10n.Main.permanentlyDeleteAlikeDataAfter)
                )
            } footer: {
                Text(SettingsL10n.Main.thisActionCantBeUndone)
            }
        }
        .navigationTitle(Text(SettingsL10n.Main.deleteAlikeData))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationBarBackButtonHidden(model.isDeleting)
        .confirmationDialog(
            SettingsL10n.Main.deleteAllAlikeData,
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(SettingsL10n.Main.deleteAlikeData, role: .destructive) {
                startDeletion()
            }
            Button(SettingsL10n.Main.cancel, role: .cancel) {}
        } message: {
            Text(SettingsL10n.Main.thisPermanentlyDeletesAlikesLocal)
        }
        .alert(
            SettingsL10n.Main.couldntDeleteAlikeData,
            isPresented: isDeletionErrorPresented
        ) {
            Button(SettingsL10n.Main.tryAgain) {
                startDeletion()
            }
            Button(SettingsL10n.Main.cancel, role: .cancel) {
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
