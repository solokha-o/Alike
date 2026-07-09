import SwiftUI
import StoreKit
import Core
import DesignSystem
import NavigationKit
#if canImport(UIKit)
import UIKit
#endif

private enum SettingsRoute: Hashable {
    case userGuide
}

/// Settings screen
public struct SettingsView: View {
    @Environment(\.requestReview) private var requestReview
    @Binding var gridColumns: Int
    @Binding var sensitivity: SensitivityLevel
    @Binding var needsRescan: Bool
    @State private var viewModel: SettingsViewModel
#if DEBUG
    @AppStorage(PremiumFeature.screenshotCleanup.debugOverrideDefaultsKey)
    private var debugUnlockScreenshotCleanup = false
    @AppStorage(PremiumFeature.blurredPhotoCleanup.debugOverrideDefaultsKey)
    private var debugUnlockBlurredPhotoCleanup = false
#endif
    
    public init(
        gridColumns: Binding<Int>,
        sensitivity: Binding<SensitivityLevel>,
        needsRescan: Binding<Bool>
    ) {
        self._gridColumns = gridColumns
        self._sensitivity = sensitivity
        self._needsRescan = needsRescan
        self._viewModel = State(initialValue: SettingsViewModel())
    }
    
    public var body: some View {
        RoutedNavigationStack { router in
            formContent(router: router)
        } destination: { route, _ in
            destination(for: route)
        }
        .task {
            await viewModel.loadCleanupInsights()
        }
    }

    private func formContent(router: StackRouter<SettingsRoute>) -> some View {
        Form {
            appearanceSection
            languageSection
            analysisSection
            cleanupHistorySection
#if DEBUG
            debugSection
#endif
            supportSection(router: router)
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
            UserGuideView()
        }
    }

    private var cleanupHistorySection: some View {
        Section {
            if viewModel.cleanupInsights.hasHistory {
                historyMetricRow(
                    title: appLocalized("Saved So Far"),
                    value: ByteCountFormatter.string(
                        fromByteCount: viewModel.cleanupInsights.totalSavedBytes,
                        countStyle: .file
                    )
                )
                historyMetricRow(
                    title: appLocalized("Photos Deleted"),
                    value: "\(viewModel.cleanupInsights.totalDeletedItems)"
                )
                historyMetricRow(
                    title: appLocalized("Cleanup Sessions"),
                    value: "\(viewModel.cleanupInsights.cleanupSessionCount)"
                )

                if let latestCleanup = viewModel.cleanupInsights.latestCleanup {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(appLocalized("Latest Cleanup"))
                            .font(.appSubheadline)
                        Text(latestCleanupSummary(for: latestCleanup))
                            .font(.appBody)
                        Text(relativeDateText(for: latestCleanup.completedAt))
                            .font(.appCaption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, Spacing.xxxSmall)
                }
            } else {
                Text(appLocalized("No cleanup history yet. Your completed cleanups will appear here."))
                    .foregroundColor(.secondary)
            }
        } header: {
            Text(appLocalized("Cleanup History"))
        }
    }
    
    // MARK: - Appearance Section
    private var appearanceSection: some View {
        Section {
            Stepper(value: $gridColumns, in: viewModel.gridConfig.minColumns...viewModel.gridConfig.maxColumns) {
                HStack {
                    Label {
                        Text(appLocalized("Grid Columns"))
                    } icon: {
                        Image(systemName: "square.grid.3x3")
                    }
                    Spacer()
                    Text("\(gridColumns)")
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityLabel(Text(appLocalized("Grid Columns")))
            .accessibilityValue(Text("\(gridColumns)"))
            .accessibilityHint(Text(appLocalized("Adjust how many columns are used in photo grids")))
        } header: {
            Text(appLocalized("Appearance"))
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
                appLocalized("Unlock Screenshot Cleanup Premium Feature"),
                isOn: $debugUnlockScreenshotCleanup
            )
            .accessibilityHint(Text(appLocalized("Enable premium screenshot cleanup access in debug builds")))

            Toggle(
                appLocalized("Unlock Blurred Photo Cleanup Premium Feature"),
                isOn: $debugUnlockBlurredPhotoCleanup
            )
            .accessibilityHint(Text(appLocalized("Enable premium blurred photo cleanup access in debug builds")))
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
            
            ShareLink(item: URL(string: "https://apps.apple.com/app/idXXXXXXXX")!) {
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
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
        #endif
    }

    private func historyMetricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private func latestCleanupSummary(for record: CleanupCompletionRecord) -> String {
        let savingsText = ByteCountFormatter.string(fromByteCount: record.estimatedSavingsBytes, countStyle: .file)
        return "\(record.deletedCount) \(appLocalized("photos deleted")) • \(savingsText) \(appLocalized("saved"))"
    }

    private func relativeDateText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - User Guide View
struct UserGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                guideStep(
                    number: 1,
                    icon: "photo.on.rectangle",
                    title: appLocalized("Grant Access"),
                    description: appLocalized("Allow Alike to access your photo library")
                )
                
                guideStep(
                    number: 2,
                    icon: "sparkles",
                    title: appLocalized("Start Scanning"),
                    description: appLocalized("Tap 'Start Scanning' to analyze your photos using advanced computer vision")
                )
                
                guideStep(
                    number: 3,
                    icon: "square.grid.3x3",
                    title: appLocalized("View Results"),
                    description: appLocalized("Browse similar-photo clusters and start with the ones that need your attention first")
                )
                
                guideStep(
                    number: 4,
                    icon: "checklist",
                    title: appLocalized("Review the Needs Review Section"),
                    description: appLocalized("After a rescan, check the Needs review section to see new or changed clusters that should be reviewed again")
                )
                
                guideStep(
                    number: 5,
                    icon: "photo",
                    title: appLocalized("Open a Cluster and Pick the Best Shot"),
                    description: appLocalized("Open any cluster to compare photos, keep the best shot, and mark the rest for cleanup")
                )
                
                guideStep(
                    number: 6,
                    icon: "slider.horizontal.3",
                    title: appLocalized("Adjust Settings"),
                    description: appLocalized("Fine-tune sensitivity and switch between one- and two-column grid layouts for your preferred review style")
                )

                guideStep(
                    number: 7,
                    icon: "arrow.clockwise",
                    title: appLocalized("Rescan After Library Changes"),
                    description: appLocalized("If your gallery changes, use the rescan prompt or refresh button to rebuild clusters and refresh your cleanup progress")
                )
            }
            .padding(Spacing.large)
        }
        .navigationTitle(Text(appLocalized("How to Use")))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
    
    private func guideStep(number: Int, icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(ColorOpacity.guideStepBackground))
                    .frame(width: 50, height: 50)
                
                Text("\(number)")
                    .font(.appHeadline)
                    .foregroundColor(.accent)
            }
            
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: icon)
                }
                .font(.appHeadline)
                
                Text(description)
                    .font(.appBody)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    SettingsView(
        gridColumns: .constant(2),
        sensitivity: .constant(.medium),
        needsRescan: .constant(false)
    )
}

#Preview("User Guide") {
    RoutedNavigationStack {
        UserGuideView()
    }
}
