import SwiftUI
import StoreKit
import Core
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

/// Settings screen
public struct SettingsView: View {
    @Environment(\.requestReview) private var requestReview
    @Binding var gridColumns: Int
    @Binding var sensitivity: SensitivityLevel
    @Binding var needsRescan: Bool
    @State private var viewModel: SettingsViewModel
    
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
        NavigationStack {
            Form {
                appearanceSection
                languageSection
                analysisSection
                supportSection
                aboutSection
            }
            .navigationTitle(Text(appLocalized("Settings")))
            .navigationBarTitleDisplayMode(.large)
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
            .onChange(of: sensitivity) { _, _ in
                needsRescan = viewModel.rescanRequiredAfterSensitivityChange()
            }
        } header: {
            Text(appLocalized("Analysis"))
        } footer: {
            Text(appLocalized("Higher sensitivity finds more similar photos but may include less alike images"))
        }
    }
    
    // MARK: - Support Section
    private var supportSection: some View {
        Section {
            NavigationLink {
                UserGuideView()
            } label: {
                Label {
                    Text(appLocalized("How to Use"))
                } icon: {
                    Image(systemName: "book")
                }
            }
            
            ShareLink(item: URL(string: "https://apps.apple.com/app/idXXXXXXXX")!) {
                Label {
                    Text(appLocalized("Share App"))
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            
            Button {
                viewModel.handleRateTapped(requestReview: requestReview)
            } label: {
                Label {
                    Text(appLocalized("Rate on App Store"))
                } icon: {
                    Image(systemName: "star")
                }
            }
            .sensoryFeedback(.selection, trigger: viewModel.reviewTrigger)
            
            Link(destination: URL(string: "mailto:oleksandr.solokha@gmail.com?subject=Alike Feedback")!) {
                Label {
                    Text(appLocalized("Contact Developer"))
                } icon: {
                    Image(systemName: "envelope")
                }
            }
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
                    description: appLocalized("Browse groups of similar photos in a grid layout")
                )
                
                guideStep(
                    number: 4,
                    icon: "photo",
                    title: appLocalized("Open Photo Details"),
                    description: appLocalized("Long-press a photo and choose 'Open Original' to view it full-screen")
                )
                
                guideStep(
                    number: 5,
                    icon: "slider.horizontal.3",
                    title: appLocalized("Adjust Settings"),
                    description: appLocalized("Fine-tune sensitivity and grid columns for your preference")
                )
                
                guideStep(
                    number: 6,
                    icon: "arrow.clockwise",
                    title: appLocalized("Rescan Anytime"),
                    description: appLocalized("Tap the refresh button to rescan after adding new photos")
                )
            }
            .padding(Spacing.large)
        }
        .navigationTitle(Text(appLocalized("How to Use")))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func guideStep(number: Int, icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.1))
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
        gridColumns: .constant(3),
        sensitivity: .constant(.medium),
        needsRescan: .constant(false)
    )
}

#Preview("User Guide") {
    NavigationStack {
        UserGuideView()
    }
}
