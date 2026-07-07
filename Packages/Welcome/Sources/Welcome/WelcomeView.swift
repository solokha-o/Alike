import SwiftUI
import Photos
import DesignSystem

/// Welcome screen with permission handling
public struct WelcomeView: View {
    @State private var viewModel: WelcomeViewModel
    @Binding var isCompleted: Bool
    @State private var isSymbolAnimating = false
    
    public init(isCompleted: Binding<Bool>, viewModel: WelcomeViewModel? = nil) {
        self._isCompleted = isCompleted
        if let viewModel {
            self._viewModel = State(initialValue: viewModel)
        } else {
            self._viewModel = State(initialValue: WelcomeViewModel())
        }
    }
    
    public var body: some View {
        Group {
            switch viewModel.authorizationStatus {
            case .notDetermined:
                initialState
            case .denied, .restricted:
                deniedState
            case .authorized, .limited:
                authorizedState
            @unknown default:
                initialState
            }
        }
        .onAppear {
            viewModel.checkStatus()
            isSymbolAnimating = true
        }
    }
    
    // MARK: - Initial State
    private var initialState: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                heroSection(
                    title: appLocalized("Clean up your library with confidence"),
                    subtitle: appLocalized("Review similar photos, free up storage, and stay in control of every deletion.")
                )

                VStack(spacing: Spacing.medium) {
                    BenefitCard(
                        icon: "internaldrive.fill",
                        title: appLocalized("Free up storage faster"),
                        message: appLocalized("Find duplicate and near-duplicate photos worth reviewing first.")
                    )
                    BenefitCard(
                        icon: "lock.shield.fill",
                        title: appLocalized("Private on-device analysis"),
                        message: appLocalized("Your photo analysis stays on this device and gives you guided cleanup suggestions.")
                    )
                    BenefitCard(
                        icon: "checkmark.shield.fill",
                        title: appLocalized("Nothing is deleted automatically"),
                        message: appLocalized("You review suggestions first and confirm every cleanup action yourself.")
                    )
                }

                PermissionRationaleCard(
                    title: appLocalized("Why Alike asks for photo access"),
                    message: appLocalized("Photo access lets Alike scan your library, group similar photos, and prepare cleanup suggestions for you to review."),
                    footnote: appLocalized("You can change access later in Settings, and Alike never deletes anything without your confirmation.")
                )

                PrimaryButton(appLocalized("Grant Access"), icon: "photo.on.rectangle") {
                    Task {
                        await viewModel.requestPermission()
                    }
                }
                .padding(.top, Spacing.small)
            }
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.xLarge)
        }
        .sensoryFeedback(.success, trigger: viewModel.isAuthorized)
    }
    
    // MARK: - Denied State
    private var deniedState: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                heroSection(
                    icon: "photo.on.rectangle.slash",
                    title: appLocalized("Photo Access Required"),
                    subtitle: appLocalized("Alike needs photo access to scan your library and prepare cleanup suggestions.")
                )

                PermissionRationaleCard(
                    title: appLocalized("Your library stays under your control"),
                    message: appLocalized("Alike never deletes photos automatically. You review the suggestions first and confirm every cleanup action."),
                    footnote: appLocalized("Enable photo access in Settings when you're ready to continue.")
                )

                VStack(spacing: Spacing.medium) {
                    BenefitCard(
                        icon: "internaldrive.fill",
                        title: appLocalized("Storage savings"),
                        message: appLocalized("Spot similar photos that can free up space once you decide what to remove.")
                    )
                    BenefitCard(
                        icon: "hand.raised.fill",
                        title: appLocalized("Safe cleanup flow"),
                        message: appLocalized("Every deletion stays confirmed, visible, and fully in your hands.")
                    )
                }

                Text(appLocalized("You can grant access now and return to cleanup whenever you're ready."))
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                PrimaryButton(appLocalized("Open Settings"), icon: "gear") {
                    viewModel.openSettings()
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.xLarge)
        }
    }

    private func heroSection(
        icon: String = "camera.viewfinder",
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 80, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.accent, Color.heroGold, Color.heroCoral)
                .symbolEffect(.bounce, options: .repeating, value: isSymbolAnimating)

            Text(appLocalized("Alike"))
                .font(.appLargeTitle)
                .foregroundColor(.accent)

            Text(title)
                .font(.appTitle2)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.appCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Authorized State
    private var authorizedState: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.statusReviewed, Color.statusSavings, .white)
                .symbolEffect(.pulse, options: .repeating, value: isSymbolAnimating)
            
            Text(appLocalized("Access Granted"))
                .font(.appTitle)
                .foregroundColor(.accent)

            Text(appLocalized("Your photos stay private, and you'll confirm every cleanup before anything is removed."))
                .font(.appCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xLarge)
        }
        .task {
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation {
                isCompleted = true
            }
        }
    }
}

private struct BenefitCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            Image(systemName: icon)
                .font(.appTitle3)
                .foregroundStyle(Color.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .font(.appHeadline)

                Text(message)
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.medium)
        .background(Color.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
    }
}

private struct PermissionRationaleCard: View {
    let title: String
    let message: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label(title, systemImage: "photo.badge.checkmark")
                .font(.appHeadline)
                .foregroundStyle(Color.accent)

            Text(message)
                .font(.appBody)

            Text(footnote)
                .font(.appFootnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                .stroke(Color.accent.opacity(ColorOpacity.cardBorder), lineWidth: 1)
        }
    }
}

// MARK: - Preview
#Preview("Initial") {
    WelcomeView(isCompleted: .constant(false))
}

#Preview("Denied") {
    @Previewable @State var isCompleted = false
    let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .denied)
    let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
    
    return WelcomeView(isCompleted: $isCompleted, viewModel: viewModel)
}

#Preview("Authorized") {
    @Previewable @State var isCompleted = false
    let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .authorized)
    let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
    
    return WelcomeView(isCompleted: $isCompleted, viewModel: viewModel)
}
