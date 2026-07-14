import SwiftUI
import Core
import Purchases
import DesignSystem
import NavigationKit

private enum HeroIconAnimationPhase: CaseIterable, Equatable {
    case idle
    case zoomed
    case settled
    case rotated

    var scale: CGFloat {
        self == .zoomed ? 1.14 : 1
    }

    var rotation: Double {
        self == .rotated ? 360 : 0
    }
}

public struct SubscriptionPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.subscriptionLegalLinks) private var environmentLegalLinks

    private let store: SubscriptionStore?
    private let legalLinksOverride: SubscriptionLegalLinks?
    @State private var presentation: PaywallPresentationState
    @State private var purchaseFeedback: PurchaseFeedback?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var heroEffectTrigger = 0
    @State private var activationEffectTrigger = 0

    public init(
        context: PremiumSurfaceContext,
        store: SubscriptionStore? = nil,
        legalLinks: SubscriptionLegalLinks? = nil
    ) {
        self.store = store
        self.legalLinksOverride = legalLinks
        self._presentation = State(initialValue: PaywallPresentationState(context: context))
    }

    private var legalLinks: SubscriptionLegalLinks {
        legalLinksOverride ?? environmentLegalLinks
    }

    public var body: some View {
        RoutedNavigationStack {
            ScrollView {
                VStack(spacing: Spacing.large) {
                    hero

                    benefits

                    if isPremium {
                        activeStatus
                            .transition(activeStatusTransition)
                    } else {
                        plans
                            .transition(.opacity)

                        if let purchaseFeedback {
                            feedbackView(purchaseFeedback)
                                .transition(feedbackTransition)
                        }
                    }

                    disclosure
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.large)
                .padding(.top, Spacing.medium)
                .padding(.bottom, isPremium ? Spacing.large : 140)
                .animation(stateAnimation, value: store?.productLoadState)
                .animation(stateAnimation, value: purchaseFeedback)
                .animation(stateAnimation, value: isPremium)
            }
            .safeAreaInset(edge: .bottom) {
                if !isPremium {
                    purchaseActions
                        .transition(.opacity)
                }
            }
            .animation(stateAnimation, value: isPremium)
            .navigationTitle(Text(appLocalized("Alike Pro")))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(appLocalized("Close")))
                    .disabled(isPurchasing)
                }
            }
        }
#if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
#endif
    }

    private var hero: some View {
        VStack(spacing: Spacing.small) {
            heroIcon

            Text(presentation.context.title)
                .font(.appTitle2)
                .multilineTextAlignment(.center)

            Text(presentation.context.message)
                .font(.appBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .task {
            guard !reduceMotion else { return }
            await Task.yield()
            heroEffectTrigger += 1
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            benefit(appLocalized("Unlimited library scans"), icon: "arrow.triangle.2.circlepath")
            benefit(appLocalized("Smart screenshot and blurred-photo categories"), icon: "wand.and.stars")
            benefit(appLocalized("Advanced filters and batch cleanup"), icon: "line.3.horizontal.decrease.circle")
            benefit(appLocalized("A cleanup reminder on your schedule"), icon: "calendar.badge.clock")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    private func benefit(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .font(.appSubheadline)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accent)
        }
    }

    @ViewBuilder
    private var plans: some View {
        switch store?.productLoadState {
        case .loading, .idle:
            VStack(spacing: Spacing.small) {
                ProgressView()
                Text(appLocalized("Loading App Store plans…"))
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.large)
        case .failed(let message):
            ContentUnavailableView {
                Label(appLocalized("Plans couldn't be loaded"), systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
            } actions: {
                Button(appLocalized("Retry")) {
                    Task { await store?.loadProducts() }
                }
                .buttonStyle(.bordered)
            }
        case .unconfigured, .none:
            ContentUnavailableView {
                Label(appLocalized("Plans aren't available yet"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(appLocalized("You can continue using Alike Free while subscription plans are unavailable."))
            }
        case .loaded:
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: Spacing.small) {
                    planCards
                }
            } else {
                VStack(spacing: Spacing.small) {
                    planCards
                }
            }
        }
    }

    @ViewBuilder
    private var planCards: some View {
        ForEach(presentation.orderedPlans) { plan in
            if let product = store?.products[plan] {
                planCard(product)
            }
        }
    }

    private func planCard(_ product: SubscriptionProduct) -> some View {
        let isSelected = presentation.selectedPlan == product.plan
        return Button {
            withAnimation(interactionAnimation) {
                presentation.selectedPlan = product.plan
                purchaseFeedback = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                HStack {
                    Text(product.displayName)
                        .font(.appHeadline)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    selectionIndicator(isSelected: isSelected)
                }

                Text(product.displayPrice)
                    .font(.appTitle3)
                    .monospacedDigit()

                Text(product.plan == .yearly ? appLocalized("Billed yearly") : appLocalized("Billed monthly"))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)

                if product.plan.isPrimary {
                    Text(appLocalized("Recommended"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, Spacing.xSmall)
                        .padding(.vertical, Spacing.xxSmall)
                        .background(Color.accent.opacity(ColorOpacity.statusBackground), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .padding(Spacing.medium)
            .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: CornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(isSelected ? Color.accent : Color.secondary.opacity(ColorOpacity.cardBorder), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text(appLocalized("Select this subscription plan")))
    }

    private var purchaseActions: some View {
        VStack(spacing: Spacing.xSmall) {
            Button(action: purchaseSelectedPlan) {
                HStack(spacing: Spacing.small) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                            .transition(.opacity)
                    }
                    Text(purchaseButtonTitle)
                        .font(.appHeadline)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .animation(stateAnimation, value: isPurchasing)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canPurchase || isPurchasing || isRestoring)

            Button(action: restorePurchases) {
                if isRestoring {
                    ProgressView()
                        .transition(.opacity)
                } else {
                    Label(appLocalized("Restore Purchases"), systemImage: "arrow.clockwise")
                        .transition(.opacity)
                }
            }
            .buttonStyle(.borderless)
            .disabled(store == nil || isPurchasing || isRestoring)
            .animation(stateAnimation, value: isRestoring)

            Text(appLocalized("Alike Free still includes three scans each calendar month, review of existing results, and one-photo cleanup."))
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.small)
        .background(.regularMaterial)
    }

    private var disclosure: some View {
        VStack(spacing: Spacing.xSmall) {
            Text(appLocalized("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple Account."))
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.medium) {
                if let privacyPolicy = legalLinks.privacyPolicy {
                    Link(appLocalized("Privacy Policy"), destination: privacyPolicy)
                }
                if let termsOfUse = legalLinks.termsOfUse {
                    Link(appLocalized("Terms of Use"), destination: termsOfUse)
                }
            }
            .font(.appCaption)
        }
    }

    private var activeStatus: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(appLocalized("Alike Pro is active"))
                    .font(.appHeadline)
                Text(activePlanDescription)
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            activeStatusIcon
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    private func feedbackView(_ feedback: PurchaseFeedback) -> some View {
        Label(feedback.message, systemImage: feedback.icon)
            .font(.appSubheadline)
            .foregroundStyle(feedback.isError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.small)
            .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private var isPremium: Bool {
        store?.entitlementState.isPremium == true
    }

    private var stateAnimation: Animation? {
        reduceMotion ? nil : .appSmooth
    }

    private var interactionAnimation: Animation? {
        reduceMotion ? nil : .appInteractive
    }

    private var feedbackTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var activeStatusTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    @ViewBuilder
    private var heroIcon: some View {
        let image = Image(systemName: presentation.context.systemImage)
            .font(.system(size: 52, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accent)
            .frame(width: Spacing.xxxLarge, height: Spacing.xxxLarge)
            .accessibilityHidden(true)

        if reduceMotion {
            image
        } else {
            image.phaseAnimator(
                HeroIconAnimationPhase.allCases,
                trigger: heroEffectTrigger
            ) { content, phase in
                content
                    .scaleEffect(phase.scale)
                    .rotationEffect(.degrees(phase.rotation))
            } animation: { phase in
                switch phase {
                case .idle:
                    .appQuick
                case .zoomed:
                    .appBouncy
                case .settled:
                    .appQuick
                case .rotated:
                    .easeInOut(duration: 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        let image = Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accent : Color.secondary)

        if reduceMotion {
            image
        } else {
            image.contentTransition(.symbolEffect(.replace))
        }
    }

    @ViewBuilder
    private var activeStatusIcon: some View {
        let image = Image(systemName: "checkmark.seal.fill")
            .font(.title2)
            .foregroundStyle(Color.accent)

        if reduceMotion {
            image
        } else {
            image.symbolEffect(.bounce, value: activationEffectTrigger)
        }
    }

    private var canPurchase: Bool {
        guard store?.productLoadState == .loaded else { return false }
        return store?.products[presentation.selectedPlan] != nil
    }

    private var purchaseButtonTitle: String {
        if isPurchasing { return appLocalized("Purchasing…") }
        guard let product = store?.products[presentation.selectedPlan] else {
            return appLocalized("Continue with Alike Free")
        }
        return String(format: appLocalized("Continue with %@"), product.displayPrice)
    }

    private var activePlanDescription: String {
        guard
            let productID = store?.entitlementState.productID,
            let product = store?.products.values.first(where: { $0.id == productID })
        else {
            return appLocalized("Unlimited scans and all Pro cleanup tools are unlocked.")
        }
        return product.displayName
    }

    private func purchaseSelectedPlan() {
        guard let store else { return }
        isPurchasing = true
        purchaseFeedback = nil
        Task {
            defer { isPurchasing = false }
            do {
                switch try await store.purchase(plan: presentation.selectedPlan) {
                case .purchased:
                    purchaseFeedback = .success(appLocalized("Alike Pro is now active."))
                    activationEffectTrigger += 1
                case .pending:
                    purchaseFeedback = .pending(appLocalized("Your purchase is pending App Store approval."))
                case .cancelled:
                    purchaseFeedback = nil
                }
            } catch {
                purchaseFeedback = .failure(error.localizedDescription)
            }
        }
    }

    private func restorePurchases() {
        guard let store else { return }
        isRestoring = true
        purchaseFeedback = nil
        Task {
            defer { isRestoring = false }
            do {
                try await store.restorePurchases()
                purchaseFeedback = store.entitlementState.isPremium
                    ? .success(appLocalized("Your Alike Pro subscription was restored."))
                    : .pending(appLocalized("No active Alike Pro subscription was found."))
            } catch {
                purchaseFeedback = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview("General paywall") {
    SubscriptionPaywallView(context: .general)
}

#Preview("Batch cleanup paywall") {
    SubscriptionPaywallView(
        context: .batchCleanup(
            selectedCount: 24,
            estimatedSavings: "480 MB"
        )
    )
}

private struct PurchaseFeedback: Equatable {
    let message: String
    let icon: String
    let isError: Bool

    static func success(_ message: String) -> PurchaseFeedback {
        PurchaseFeedback(message: message, icon: "checkmark.seal.fill", isError: false)
    }

    static func pending(_ message: String) -> PurchaseFeedback {
        PurchaseFeedback(message: message, icon: "clock.badge.questionmark", isError: false)
    }

    static func failure(_ message: String) -> PurchaseFeedback {
        PurchaseFeedback(message: message, icon: "exclamationmark.triangle.fill", isError: true)
    }
}
