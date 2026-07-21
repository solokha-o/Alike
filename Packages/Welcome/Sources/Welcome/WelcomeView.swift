import SwiftUI
import Photos
import DesignSystem

/// Welcome screen with permission handling
public struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: WelcomeViewModel
    @Binding var isCompleted: Bool
    @State private var isSymbolAnimating = false
    @State private var isALIWelcomeHeroVisible = false
    @State private var selectedWelcomePage = WelcomePage.welcome
    
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
        VStack(spacing: Spacing.small) {
            welcomePager
            pageIndicator
            welcomeNavigation
        }
        .padding(.bottom, Spacing.medium)
        .sensoryFeedback(.success, trigger: viewModel.isAuthorized)
    }

    @ViewBuilder
    private var welcomePager: some View {
        #if os(iOS)
        TabView(selection: $selectedWelcomePage) {
            ForEach(WelcomePage.allCases, id: \.self) { page in
                welcomePage(page)
                    .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        welcomePage(selectedWelcomePage)
        #endif
    }

    @ViewBuilder
    private func welcomePage(_ page: WelcomePage) -> some View {
        ScrollView {
            Group {
                switch page {
                case .welcome:
                    welcomeOverviewPage
                case .howItWorks:
                    howAlikeHelpsPage
                case .privacy:
                    privacyPage
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.medium)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var welcomeOverviewPage: some View {
        heroSection(
            showsALIWelcomeHero: true,
            title: appLocalized("Clean up your library with confidence"),
            subtitle: appLocalized("Review similar photos, free up storage, and stay in control of every deletion.")
        )
    }

    private var howAlikeHelpsPage: some View {
        VStack(spacing: Spacing.large) {
            onboardingHeader(
                icon: "sparkles.rectangle.stack.fill",
                title: appLocalized("How Alike helps"),
                subtitle: appLocalized("Turn a crowded library into a guided cleanup.")
            )

            VStack(spacing: Spacing.medium) {
                BenefitCard(
                    icon: "photo.stack",
                    title: appLocalized("Find cleanup opportunities"),
                    message: appLocalized("Group visually similar photos and other items worth reviewing.")
                )
                BenefitCard(
                    icon: "eye.fill",
                    title: appLocalized("Review every suggestion"),
                    message: appLocalized("Compare photos and keep the shots that matter to you.")
                )
                BenefitCard(
                    icon: "internaldrive.fill",
                    title: appLocalized("See potential savings"),
                    message: appLocalized("Know how much space you could reclaim before you clean up.")
                )
            }
        }
    }

    private var privacyPage: some View {
        VStack(spacing: Spacing.large) {
            onboardingHeader(
                icon: "lock.shield.fill",
                title: appLocalized("Private and always in your control"),
                subtitle: appLocalized("Analysis stays on your device, and nothing is deleted automatically.")
            )

            VStack(spacing: Spacing.medium) {
                BenefitCard(
                    icon: "iphone.gen3",
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
        }
    }

    private func onboardingHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.accent, Color.heroGold, Color.heroCoral)

            Text(title)
                .font(.appTitle)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.appCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: Spacing.xSmall) {
            ForEach(WelcomePage.allCases, id: \.self) { page in
                Capsule(style: .continuous)
                    .fill(page == selectedWelcomePage ? Color.accent : Color.secondary.opacity(0.3))
                    .frame(width: page == selectedWelcomePage ? 20 : 8, height: 8)
            }
        }
        .animation(accessibilityReduceMotion ? nil : .appSmooth, value: selectedWelcomePage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pageIndicatorAccessibilityLabel)
    }

    private var pageIndicatorAccessibilityLabel: String {
        String(
            format: appLocalized("Page %lld of %lld"),
            Int64(selectedWelcomePage.rawValue + 1),
            Int64(WelcomePage.allCases.count)
        )
    }

    private var welcomeNavigation: some View {
        HStack(spacing: Spacing.medium) {
            if let previousPage = selectedWelcomePage.previous {
                SecondaryButton(appLocalized("Back"), icon: "chevron.left") {
                    selectWelcomePage(previousPage)
                }
            }

            if let nextPage = selectedWelcomePage.next {
                PrimaryButton(appLocalized("Next"), icon: "chevron.right") {
                    selectWelcomePage(nextPage)
                }
            } else {
                PrimaryButton(appLocalized("Grant Access"), icon: "photo.on.rectangle") {
                    Task {
                        await viewModel.requestPermission()
                    }
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Spacing.large)
    }

    private func selectWelcomePage(_ page: WelcomePage) {
        if accessibilityReduceMotion {
            selectedWelcomePage = page
        } else {
            withAnimation(.appSmooth) {
                selectedWelcomePage = page
            }
        }
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
        showsALIWelcomeHero: Bool = false,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: Spacing.medium) {
            if showsALIWelcomeHero {
                aliWelcomeHero
            } else {
                Image(systemName: icon)
                    .font(.system(size: 80, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.accent, Color.heroGold, Color.heroCoral)
                    .symbolEffect(.bounce, options: .repeating, value: isSymbolAnimating)
            }

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

    private var aliWelcomeHero: some View {
        AnimatedImageOverlay(
            animationURL: playsALIWelcomeOverlay ? ALIAssets.welcomeHeroOverlayURL : nil,
            aspectRatio: 1080.0 / 912.0,
            maximumWidth: 420,
            playback: .loop,
            ambientMotion: playsALIWelcomeOverlay ? .breathe : .none
        ) {
            welcomeImage
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appLocalized("ALI, Alike's photo detective"))
        .onAppear {
            isALIWelcomeHeroVisible = true
        }
        .onDisappear {
            isALIWelcomeHeroVisible = false
        }
    }

    private var playsALIWelcomeOverlay: Bool {
        isALIWelcomeHeroVisible
            && selectedWelcomePage == .welcome
            && scenePhase == .active
    }

    private var welcomeImage: Image {
        let imageURL = ALIAssets.welcomeHeroURL(for: welcomeHeroScale)

        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            return Image(systemName: "camera.viewfinder")
        }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: imageURL) else {
            return Image(systemName: "camera.viewfinder")
        }
        return Image(nsImage: image)
        #endif
    }

    private var welcomeHeroScale: ALIAssets.WelcomeHeroScale {
        switch displayScale {
        case ..<1.5:
            .oneX
        case ..<2.5:
            .twoX
        default:
            .threeX
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

private enum WelcomePage: Int, CaseIterable {
    case welcome
    case howItWorks
    case privacy

    var previous: WelcomePage? {
        WelcomePage(rawValue: rawValue - 1)
    }

    var next: WelcomePage? {
        WelcomePage(rawValue: rawValue + 1)
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
