import SwiftUI
import Core
import Purchases
import DesignSystem

public struct PremiumLockedAccessory: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Spacing.xxSmall) {
            Image(systemName: "lock.fill")
                .accessibilityHidden(true)
            Text(PurchasesL10n.PremiumComponents.pro)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.accent)
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall)
        .background(Color.accent.opacity(ColorOpacity.statusBackground), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(PurchasesL10n.PremiumComponents.requiresAlikePro))
    }
}

public struct PremiumStatusCard: View {
    public enum Status: Equatable, Sendable {
        case loading
        case free
        case active(planName: String?, expirationDate: Date?)
        case unavailable
    }

    private let status: Status
    private let onViewPlans: () -> Void
    private let onRestore: () -> Void
    private let isRestoring: Bool

    public init(
        status: Status,
        isRestoring: Bool = false,
        onViewPlans: @escaping () -> Void,
        onRestore: @escaping () -> Void
    ) {
        self.status = status
        self.isRestoring = isRestoring
        self.onViewPlans = onViewPlans
        self.onRestore = onRestore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .top, spacing: Spacing.small) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accent)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(title)
                        .font(.appHeadline)
                    Text(detail)
                        .font(.appSubheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.small)

                if status == .loading {
                    ProgressView()
                        .accessibilityLabel(Text(PurchasesL10n.PremiumComponents.checkingSubscriptionStatus))
                }
            }

            switch status {
            case .free, .unavailable:
                Button(PurchasesL10n.PremiumComponents.viewPlans, action: onViewPlans)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button(action: onRestore) {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Label(PurchasesL10n.Common.restorePurchases, systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRestoring)
            case .loading, .active:
                EmptyView()
            }
        }
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch status {
        case .active:
            "checkmark.seal.fill"
        case .loading:
            "crown"
        case .free, .unavailable:
            "crown.fill"
        }
    }

    private var title: String {
        switch status {
        case .active:
            PurchasesL10n.Common.alikeProIsActive
        case .loading:
            PurchasesL10n.PremiumComponents.checkingAlikePro
        case .free:
            PurchasesL10n.PremiumComponents.upgradeToAlikePro
        case .unavailable:
            PurchasesL10n.PremiumComponents.alikeProStatusUnavailable
        }
    }

    private var detail: String {
        switch status {
        case .loading:
            return PurchasesL10n.PremiumComponents.confirmingAppStoreSubscriptionStatus
        case .free:
            return PurchasesL10n.PremiumComponents.unlockUnlimitedScansSmartCleanup
        case .unavailable:
            return PurchasesL10n.PremiumComponents.currentAccessPreservedOpenPlans
        case .active(let planName, let expirationDate):
            let plan = planName ?? PurchasesL10n.Common.alikePro
            guard let expirationDate else { return plan }
            return String(
                format: PurchasesL10n.PremiumComponents.activeThrough,
                plan,
                expirationDate.formatted(date: .abbreviated, time: .omitted)
            )
        }
    }
}

public struct BatchCleanupUpsellCard: View {
    private let selectedCount: Int
    private let estimatedSavings: String
    private let onUpgrade: () -> Void
    private let onContinueFree: () -> Void

    public init(
        selectedCount: Int,
        estimatedSavings: String,
        onUpgrade: @escaping () -> Void,
        onContinueFree: @escaping () -> Void
    ) {
        self.selectedCount = selectedCount
        self.estimatedSavings = estimatedSavings
        self.onUpgrade = onUpgrade
        self.onContinueFree = onContinueFree
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label(PurchasesL10n.Common.cleanUpAllSelectedPhotos, systemImage: "checkmark.circle.badge.xmark")
                .font(.appHeadline)
                .foregroundStyle(Color.accent)

            Text(
                String(
                    format: PurchasesL10n.PremiumComponents.selectedEstimatedReclaimable,
                    selectedCount,
                    estimatedSavings
                )
            )
            .font(.appSubheadline)
            .foregroundStyle(.secondary)

            Button(PurchasesL10n.PremiumComponents.viewAlikePro, action: onUpgrade)
                .buttonStyle(.borderedProminent)

            Button(PurchasesL10n.PremiumComponents.continueWithOnePhoto, action: onContinueFree)
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Color.accent.opacity(ColorOpacity.cardBorder), lineWidth: 1)
        }
    }
}

#Preview("Premium states") {
    List {
        PremiumStatusCard(status: .loading, onViewPlans: {}, onRestore: {})
        PremiumStatusCard(status: .free, onViewPlans: {}, onRestore: {})
        PremiumStatusCard(
            status: .active(planName: "Alike Pro Yearly", expirationDate: .now),
            onViewPlans: {},
            onRestore: {}
        )
        BatchCleanupUpsellCard(
            selectedCount: 12,
            estimatedSavings: "240 MB",
            onUpgrade: {},
            onContinueFree: {}
        )
    }
}
