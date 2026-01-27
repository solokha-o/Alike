import SwiftUI
import StoreKit
import Core
import DesignSystem

/// Settings screen
public struct SettingsView: View {
    @Binding var gridColumns: Int
    @Binding var sensitivity: SensitivityLevel
    @Binding var needsRescan: Bool
    @Environment(\.requestReview) private var requestReview
    @State private var reviewTrigger = 0
    
    private var gridConfig: GridConfiguration { GridConfiguration.current }
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    
    public init(
        gridColumns: Binding<Int>,
        sensitivity: Binding<SensitivityLevel>,
        needsRescan: Binding<Bool>
    ) {
        self._gridColumns = gridColumns
        self._sensitivity = sensitivity
        self._needsRescan = needsRescan
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                analysisSection
                supportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // MARK: - Appearance Section
    private var appearanceSection: some View {
        Section("Appearance") {
            Stepper(value: $gridColumns, in: gridConfig.minColumns...gridConfig.maxColumns) {
                HStack {
                    Label("Grid Columns", systemImage: "square.grid.3x3")
                    Spacer()
                    Text("\(gridColumns)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Analysis Section
    private var analysisSection: some View {
        Section {
            Picker("Sensitivity", selection: $sensitivity) {
                ForEach(SensitivityLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .onChange(of: sensitivity) { _, _ in
                showRescanAlert()
            }
        } header: {
            Text("Analysis")
        } footer: {
            Text("Higher sensitivity finds more similar photos but may include less alike images")
        }
    }
    
    // MARK: - Support Section
    private var supportSection: some View {
        Section("Support") {
            NavigationLink {
                UserGuideView()
            } label: {
                Label("How to Use", systemImage: "book")
            }
            
            ShareLink(item: URL(string: "https://apps.apple.com/app/idXXXXXXXX")!) {
                Label("Share App", systemImage: "square.and.arrow.up")
            }
            
            Button {
                reviewTrigger += 1
                requestReview()
            } label: {
                Label("Rate on App Store", systemImage: "star")
            }
            .sensoryFeedback(.selection, trigger: reviewTrigger)
            
            Link(destination: URL(string: "mailto:oleksandr.solokha@gmail.com?subject=Alike Feedback")!) {
                Label("Contact Developer", systemImage: "envelope")
            }
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helper Methods
    private func showRescanAlert() {
        needsRescan = true
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
                    title: "Grant Access",
                    description: "Allow Alike to access your photo library"
                )
                
                guideStep(
                    number: 2,
                    icon: "sparkles",
                    title: "Start Scanning",
                    description: "Tap 'Start Scanning' to analyze your photos using advanced computer vision"
                )
                
                guideStep(
                    number: 3,
                    icon: "square.grid.3x3",
                    title: "View Results",
                    description: "Browse groups of similar photos in a grid layout"
                )
                
                guideStep(
                    number: 4,
                    icon: "slider.horizontal.3",
                    title: "Adjust Settings",
                    description: "Fine-tune sensitivity and grid columns for your preference"
                )
                
                guideStep(
                    number: 5,
                    icon: "arrow.clockwise",
                    title: "Rescan Anytime",
                    description: "Tap the refresh button to rescan after adding new photos"
                )
            }
            .padding(Spacing.large)
        }
        .navigationTitle("How to Use")
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
                Label(title, systemImage: icon)
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
