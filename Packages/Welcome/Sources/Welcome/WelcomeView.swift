import SwiftUI
import Photos
import DesignSystem

public enum WelcomeMode: Equatable, Sendable {
    case permissionRequest
    case dataDeletionReplay

    var replaysOnboarding: Bool {
        self == .dataDeletionReplay
    }

    var requestsPhotoPermission: Bool {
        self == .permissionRequest
    }
}

/// Welcome screen with permission handling
public struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: WelcomeViewModel
    @Binding var isCompleted: Bool
    @State private var isSymbolAnimating = false
    @State private var isAlikeWelcomeHeroVisible = false
    @State private var selectedWelcomePage = WelcomePage.welcome
    @State private var glassFinalActionFeedbackTrigger = 0
    private let mode: WelcomeMode
    
    public init(
        isCompleted: Binding<Bool>,
        mode: WelcomeMode = .permissionRequest,
        viewModel: WelcomeViewModel? = nil
    ) {
        self._isCompleted = isCompleted
        self.mode = mode
        if let viewModel {
            self._viewModel = State(initialValue: viewModel)
        } else {
            self._viewModel = State(initialValue: WelcomeViewModel())
        }
    }
    
    public var body: some View {
        Group {
            if mode.replaysOnboarding {
                initialState
            } else {
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
        }
        #if os(iOS)
        .sensoryFeedback(.success, trigger: viewModel.isAuthorized) { wasAuthorized, isAuthorized in
            !wasAuthorized && isAuthorized
        }
        #endif
        .onAppear {
            if mode.requestsPhotoPermission {
                viewModel.checkStatus()
            }
            isSymbolAnimating = true
        }
    }
    
    // MARK: - Initial State
    private var initialState: some View {
        VStack(spacing: Spacing.small) {
            if mode.replaysOnboarding {
                Label(
                    WelcomeL10n.Main.alikeDataDeleted,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.appHeadline)
                .foregroundStyle(Color.statusReviewed)
                .accessibilityAddTraits(.isHeader)

                Text(WelcomeL10n.Main.localAlikeDataWasDeleted)
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.large)
            }
            welcomePager
            pageIndicator
            welcomeNavigation
        }
        .padding(.bottom, Spacing.medium)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: selectedWelcomePage)
        #endif
    }

    @ViewBuilder
    private var welcomePager: some View {
        #if os(iOS)
        TabView(
            selection: $selectedWelcomePage.animation(
                accessibilityReduceMotion ? nil : .appQuick
            )
        ) {
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
            showsAlikeWelcomeHero: true,
            title: WelcomeL10n.Main.cleanUpLibraryWithConfidence,
            subtitle: WelcomeL10n.Main.reviewSimilarPhotosFreeUp
        )
    }

    private var howAlikeHelpsPage: some View {
        VStack(spacing: Spacing.large) {
            onboardingHeader(
                icon: "sparkles.rectangle.stack.fill",
                title: WelcomeL10n.Main.howAlikeHelps,
                subtitle: WelcomeL10n.Main.turnCrowdedLibraryIntoGuided
            )

            VStack(spacing: Spacing.medium) {
                BenefitCard(
                    icon: "photo.stack",
                    title: WelcomeL10n.Main.findCleanupOpportunities,
                    message: WelcomeL10n.Main.groupVisuallySimilarPhotosOther
                )
                BenefitCard(
                    icon: "eye.fill",
                    title: WelcomeL10n.Main.reviewEverySuggestion,
                    message: WelcomeL10n.Main.comparePhotosKeepShotsThat
                )
                BenefitCard(
                    icon: "internaldrive.fill",
                    title: WelcomeL10n.Main.seePotentialSavings,
                    message: WelcomeL10n.Main.knowHowMuchSpaceCould
                )
            }
        }
    }

    private var privacyPage: some View {
        VStack(spacing: Spacing.large) {
            onboardingHeader(
                icon: "lock.shield.fill",
                title: WelcomeL10n.Main.privateAlwaysControl,
                subtitle: WelcomeL10n.Main.analysisStaysDeviceNothingDeleted
            )

            VStack(spacing: Spacing.medium) {
                BenefitCard(
                    icon: "iphone.gen3",
                    title: WelcomeL10n.Main.privateOnDeviceAnalysis,
                    message: WelcomeL10n.Main.photoAnalysisStaysThisDevice
                )
                BenefitCard(
                    icon: "checkmark.shield.fill",
                    title: WelcomeL10n.Main.nothingIsDeletedAutomatically,
                    message: WelcomeL10n.Main.reviewSuggestionsFirstConfirmEvery
                )
            }

            PermissionRationaleCard(
                title: WelcomeL10n.Main.whyAlikeAsksPhotoAccess,
                message: WelcomeL10n.Main.photoAccessLetsAlikeScan,
                footnote: WelcomeL10n.Main.canChangeAccessLaterSettings
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
        .animation(accessibilityReduceMotion ? nil : .appQuick, value: selectedWelcomePage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pageIndicatorAccessibilityLabel)
    }

    private var pageIndicatorAccessibilityLabel: String {
        String(
            format: WelcomeL10n.Main.pageOf,
            Int64(selectedWelcomePage.rawValue + 1),
            Int64(WelcomePage.allCases.count)
        )
    }

    private var welcomeNavigation: some View {
        Group {
            #if os(iOS)
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: Spacing.medium) {
                    glassWelcomeNavigation
                }
                .tint(.accent)
            } else {
                standardWelcomeNavigation
            }
            #else
            standardWelcomeNavigation
            #endif
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Spacing.large)
        .lineLimit(1)
        .allowsTightening(true)
        .minimumScaleFactor(0.85)
    }

    private var standardWelcomeNavigation: some View {
        HStack(spacing: Spacing.medium) {
            if let previousPage = selectedWelcomePage.previous {
                SecondaryButton(WelcomeL10n.Main.back, icon: "chevron.backward") {
                    selectWelcomePage(previousPage)
                }
            }

            if let nextPage = selectedWelcomePage.next {
                standardNextButton(nextPage)
            } else {
                PrimaryButton(finalActionTitle) {
                    performFinalAction()
                }
            }
        }
    }

    private func standardNextButton(_ nextPage: WelcomePage) -> some View {
        Button {
            selectWelcomePage(nextPage)
        } label: {
            HStack(spacing: Spacing.small) {
                Text(WelcomeL10n.Main.next)
                Image(systemName: "chevron.forward")
            }
            .font(.appHeadline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accent)
            .foregroundColor(.white)
            .cornerRadius(CornerRadius.medium)
        }
        .scaleOnPress()
        .accessibilityLabel(WelcomeL10n.Main.next)
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    private var glassWelcomeNavigation: some View {
        HStack(spacing: Spacing.medium) {
            if let previousPage = selectedWelcomePage.previous {
                Button {
                    selectWelcomePage(previousPage)
                } label: {
                    Label(WelcomeL10n.Main.back, systemImage: "chevron.backward")
                        .font(.appHeadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            if let nextPage = selectedWelcomePage.next {
                Button {
                    selectWelcomePage(nextPage)
                } label: {
                    HStack(spacing: Spacing.small) {
                        Text(WelcomeL10n.Main.next)
                        Image(systemName: "chevron.forward")
                    }
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityLabel(WelcomeL10n.Main.next)
            } else {
                Button {
                    glassFinalActionFeedbackTrigger += 1
                    performFinalAction()
                } label: {
                    Text(finalActionTitle)
                        .font(.appHeadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .sensoryFeedback(
                    .impact(flexibility: .soft),
                    trigger: glassFinalActionFeedbackTrigger
                )
            }
        }
    }
    #endif

    private func selectWelcomePage(_ page: WelcomePage) {
        if accessibilityReduceMotion {
            selectedWelcomePage = page
        } else {
            withAnimation(.appQuick) {
                selectedWelcomePage = page
            }
        }
    }

    /// Neutral wording on purpose: App Review 5.1.1(iv) reads a "Grant Access" button in front
    /// of the system prompt as steering the answer.
    private var finalActionTitle: String {
        WelcomeL10n.Main.`continue`
    }

    private func performFinalAction() {
        if !mode.requestsPhotoPermission {
            isCompleted = true
        } else {
            Task {
                await viewModel.requestPermission()
            }
        }
    }
    
    // MARK: - Denied State
    private var deniedState: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                heroSection(
                    icon: "photo.on.rectangle.slash",
                    title: WelcomeL10n.Main.photoAccessRequired,
                    subtitle: WelcomeL10n.Main.alikeNeedsPhotoAccessScan
                )

                PermissionRationaleCard(
                    title: WelcomeL10n.Main.yourLibraryStaysUnderControl,
                    message: WelcomeL10n.Main.alikeNeverDeletesPhotosAutomatically,
                    footnote: WelcomeL10n.Main.enablePhotoAccessSettingsWhen
                )

                VStack(spacing: Spacing.medium) {
                    BenefitCard(
                        icon: "internaldrive.fill",
                        title: WelcomeL10n.Main.storageSavings,
                        message: WelcomeL10n.Main.spotSimilarPhotosThatCan
                    )
                    BenefitCard(
                        icon: "hand.raised.fill",
                        title: WelcomeL10n.Main.safeCleanupFlow,
                        message: WelcomeL10n.Main.everyDeletionStaysConfirmedVisible
                    )
                }

                Text(WelcomeL10n.Main.canGrantAccessNowReturn)
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                PrimaryButton(WelcomeL10n.Main.openSettings, icon: "gear") {
                    viewModel.openSettings()
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.xLarge)
        }
    }

    private func heroSection(
        icon: String = "camera.viewfinder",
        showsAlikeWelcomeHero: Bool = false,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: Spacing.medium) {
            if showsAlikeWelcomeHero {
                alikeWelcomeHero
            } else {
                Image(systemName: icon)
                    .font(.system(size: 80, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.accent, Color.heroGold, Color.heroCoral)
                    .symbolEffect(.bounce, options: .repeating, value: isSymbolAnimating)
            }

            Text(WelcomeL10n.Main.alike)
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

    private var alikeWelcomeHero: some View {
        AnimatedImageOverlay(
            animationURL: playsAlikeWelcomeOverlay ? AlikeAssets.welcomeHeroOverlayURL : nil,
            aspectRatio: 1080.0 / 912.0,
            maximumWidth: 420,
            playback: .loop,
            ambientMotion: playsAlikeWelcomeOverlay ? .breathe : .none
        ) {
            welcomeImage
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WelcomeL10n.Main.alikeYourPhotoDetective)
        .onAppear {
            isAlikeWelcomeHeroVisible = true
        }
        .onDisappear {
            isAlikeWelcomeHeroVisible = false
        }
    }

    private var playsAlikeWelcomeOverlay: Bool {
        isAlikeWelcomeHeroVisible
            && selectedWelcomePage == .welcome
            && scenePhase == .active
    }

    private var welcomeImage: Image {
        let imageURL = AlikeAssets.welcomeHeroURL(for: welcomeHeroScale)

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

    private var welcomeHeroScale: AlikeAssets.WelcomeHeroScale {
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
                .foregroundStyle(Color.statusReviewed, Color.statusSavings, .foreground)
                .symbolEffect(.pulse, options: .repeating, value: isSymbolAnimating)
            
            Text(WelcomeL10n.Main.accessGranted)
                .font(.appTitle)
                .foregroundColor(.accent)

            Text(WelcomeL10n.Main.photosStayPrivateYoullConfirm)
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

// MockPhotoPermissionManager only exists in DEBUG, and #Preview is expanded in
// every configuration, so these two previews have to be gated or the Release
// build of Welcome fails to compile.
#if DEBUG
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
#endif
