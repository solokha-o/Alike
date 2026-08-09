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

    private let context: PremiumSurfaceContext
    private let store: SubscriptionStore?
    private let legalLinksOverride: SubscriptionLegalLinks?
    @State private var selectedPlan: SubscriptionPlan
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
        self.context = context
        self.store = store
        self.legalLinksOverride = legalLinks
        self._selectedPlan = State(initialValue: .yearly)
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
            .navigationTitle(Text(PurchasesL10n.Common.alikePro))
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
                    .accessibilityLabel(Text(PurchasesL10n.SubscriptionPaywall.close))
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

            Text(context.title)
                .font(.appTitle2)
                .multilineTextAlignment(.center)

            Text(context.message)
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
            benefit(PurchasesL10n.SubscriptionPaywall.unlimitedLibraryScans, icon: "arrow.triangle.2.circlepath")
            benefit(PurchasesL10n.SubscriptionPaywall.smartScreenshotBlurredPhotoCategories, icon: "wand.and.stars")
            benefit(PurchasesL10n.SubscriptionPaywall.advancedFiltersAndBatchCleanup, icon: "line.3.horizontal.decrease.circle")
            benefit(PurchasesL10n.SubscriptionPaywall.cleanupReminderSchedule, icon: "calendar.badge.clock")
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
                Text(PurchasesL10n.SubscriptionPaywall.loadingAppStorePlans)
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.large)
        case .failed(let message):
            ContentUnavailableView {
                Label(PurchasesL10n.SubscriptionPaywall.plansCouldntBeLoaded, systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(PurchasesL10n.SubscriptionPaywall.checkConnectionTryLoadingSubscription)
            } actions: {
                Button(PurchasesL10n.SubscriptionPaywall.retry) {
                    Task { await store?.loadProducts() }
                }
                .buttonStyle(.bordered)
            }
            .onAppear {
                logFailure(operation: "product loading", details: message)
            }
        case .unconfigured, .none:
            ContentUnavailableView {
                Label(PurchasesL10n.SubscriptionPaywall.plansArentAvailableYet, systemImage: "exclamationmark.triangle")
            } description: {
                Text(PurchasesL10n.SubscriptionPaywall.canContinueUsingAlikeFree)
            }
        case .loaded:
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: Spacing.small) {
                    planCardLayout(usesGlass: true)
                }
            } else {
                planCardLayout(usesGlass: false)
            }
        }
    }

    @ViewBuilder
    private func planCardLayout(usesGlass: Bool) -> some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: Spacing.small) {
                planCards(usesGlass: usesGlass)
            }
        } else {
            VStack(spacing: Spacing.small) {
                planCards(usesGlass: usesGlass)
            }
        }
    }

    @ViewBuilder
    private func planCards(usesGlass: Bool) -> some View {
        ForEach(SubscriptionPlan.presentationOrder) { plan in
            if let product = store?.products[plan] {
                planCard(product, usesGlass: usesGlass)
            }
        }
    }

    private func planCard(_ product: SubscriptionProduct, usesGlass: Bool) -> some View {
        let isSelected = selectedPlan == product.plan
        return Button {
            withAnimation(interactionAnimation) {
                selectedPlan = product.plan
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

                Text(product.plan == .yearly ? PurchasesL10n.SubscriptionPaywall.billedYearly : PurchasesL10n.SubscriptionPaywall.billedMonthly)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)

                Text(planValueDescription(for: product))
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)

                if product.plan.isPrimary {
                    Text(PurchasesL10n.SubscriptionPaywall.recommended)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, Spacing.xSmall)
                        .padding(.vertical, Spacing.xxSmall)
                        .background(Color.accent.opacity(ColorOpacity.statusBackground), in: Capsule())
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: horizontalSizeClass == .regular ? 124 : nil,
                alignment: .topLeading
            )
            .padding(Spacing.medium)
            .modifier(PaywallPlanCardSurface(usesGlass: usesGlass))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(isSelected ? Color.accent : Color.secondary.opacity(ColorOpacity.cardBorder), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text(PurchasesL10n.SubscriptionPaywall.selectThisSubscriptionPlan))
    }

    private func planValueDescription(for product: SubscriptionProduct) -> String {
        guard product.plan == .yearly else {
            return PurchasesL10n.SubscriptionPaywall.payOneMonthAtTime
        }
        guard
            let monthlyPrice = store?.products[.monthly]?.price,
            monthlyPrice > 0
        else {
            return PurchasesL10n.SubscriptionPaywall.saveWithAnnualBilling
        }

        let monthlyAnnualCost = monthlyPrice * 12
        guard monthlyAnnualCost > product.price else {
            return PurchasesL10n.SubscriptionPaywall.saveWithAnnualBilling
        }

        var savingsPercentage = (1 - product.price / monthlyAnnualCost) * 100
        var roundedSavingsPercentage = Decimal()
        NSDecimalRound(&roundedSavingsPercentage, &savingsPercentage, 0, .plain)
        let percentage = NSDecimalNumber(decimal: roundedSavingsPercentage).intValue
        return String(
            format: PurchasesL10n.SubscriptionPaywall.saveComparedWithMonthly,
            percentage
        )
    }

    private var purchaseActions: some View {
        VStack(spacing: Spacing.xSmall) {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: Spacing.xSmall) {
                    purchaseControls(usesGlass: true)
                }
            } else {
                purchaseControls(usesGlass: false)
            }

            Text(PurchasesL10n.SubscriptionPaywall.alikeFreeStillIncludesThree)
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.large)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.xxSmall)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func purchaseControls(usesGlass: Bool) -> some View {
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
            .modifier(PaywallPurchaseButtonStyle(usesGlass: usesGlass, isProminent: true))
            .controlSize(.large)
            .disabled(!canPurchase || isPurchasing || isRestoring)

            Button(action: restorePurchases) {
                if isRestoring {
                    ProgressView()
                        .transition(.opacity)
                } else {
                    Label(PurchasesL10n.Common.restorePurchases, systemImage: "arrow.clockwise")
                        .transition(.opacity)
                }
            }
            .modifier(PaywallPurchaseButtonStyle(usesGlass: usesGlass, isProminent: false))
            .disabled(store == nil || isPurchasing || isRestoring)
            .animation(stateAnimation, value: isRestoring)
        }
    }

    private var disclosure: some View {
        VStack(spacing: Spacing.xSmall) {
            Text(PurchasesL10n.SubscriptionPaywall.subscriptionsRenewAutomaticallyUnlessCancelled)
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(PurchasesL10n.SubscriptionPaywall.yearlyPlanIncludes7Day)
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.medium) {
                if let privacyPolicy = legalLinks.privacyPolicy {
                    Link(PurchasesL10n.SubscriptionPaywall.privacyPolicy, destination: privacyPolicy)
                }
                if let termsOfUse = legalLinks.termsOfUse {
                    Link(PurchasesL10n.SubscriptionPaywall.termsOfUse, destination: termsOfUse)
                }
            }
            .font(.appCaption)
        }
    }

    private var activeStatus: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(PurchasesL10n.Common.alikeProIsActive)
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
        let image = Image(systemName: context.systemImage)
            .font(.system(size: 52, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.accent, Color.heroGold, Color.heroCoral)
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
        return store?.products[selectedPlan] != nil
    }

    private var purchaseButtonTitle: String {
        if isPurchasing { return PurchasesL10n.SubscriptionPaywall.purchasing }
        guard store?.productLoadState == .loaded else {
            return PurchasesL10n.SubscriptionPaywall.subscriptionPlansUnavailable
        }
        guard let product = store?.products[selectedPlan] else {
            return PurchasesL10n.SubscriptionPaywall.selectASubscriptionPlan
        }
        return String(format: PurchasesL10n.SubscriptionPaywall.continueWith, product.displayPrice)
    }

    private var activePlanDescription: String {
        guard
            let productID = store?.entitlementState.productID,
            let product = store?.products.values.first(where: { $0.id == productID })
        else {
            return PurchasesL10n.SubscriptionPaywall.unlimitedScansAllProCleanup
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
                switch try await store.purchase(plan: selectedPlan) {
                case .purchased:
                    purchaseFeedback = .success(PurchasesL10n.SubscriptionPaywall.alikeProIsNowActive)
                    activationEffectTrigger += 1
                case .pending:
                    purchaseFeedback = .pending(PurchasesL10n.SubscriptionPaywall.purchasePendingAppStoreApproval)
                case .cancelled:
                    purchaseFeedback = nil
                }
            } catch {
                logFailure(operation: "purchase", details: error.localizedDescription)
                purchaseFeedback = .failure(
                    PurchasesL10n.SubscriptionPaywall.weCouldntCompletePurchaseCheck
                )
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
                    ? .success(PurchasesL10n.SubscriptionPaywall.alikeProSubscriptionWasRestored)
                    : .pending(PurchasesL10n.SubscriptionPaywall.noActiveAlikeProSubscription)
            } catch {
                logFailure(operation: "restore", details: error.localizedDescription)
                purchaseFeedback = .failure(
                    PurchasesL10n.SubscriptionPaywall.weCouldntRestorePurchasesCheck
                )
            }
        }
    }

    private func logFailure(operation: String, details: String) {
        let message = AppLog.tag(.error, "Subscription \(operation) failed: \(details)")
        AppLog.ui.error("\(message, privacy: .public)")
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

private struct PaywallPlanCardSurface: ViewModifier {
    let usesGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), usesGlass {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: CornerRadius.large)
                )
        } else {
            content
                .background(
                    Color.secondaryBackground,
                    in: RoundedRectangle(cornerRadius: CornerRadius.large)
                )
        }
    }
}

private struct PaywallPurchaseButtonStyle: ViewModifier {
    let usesGlass: Bool
    let isProminent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), usesGlass {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.borderless)
        }
    }
}
