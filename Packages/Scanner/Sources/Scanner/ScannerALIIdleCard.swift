import SwiftUI
import DesignSystem

struct ScannerALIIdleCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let presentation: ScannerALIIdlePresentation
    let action: () -> Void

    var body: some View {
        VStack(spacing: Spacing.medium) {
            ALIReactionView(cue: presentation.cue, maximumWidth: heroSize)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xSmall) {
                Text(presentation.message)
                    .font(.appTitle2)
                    .foregroundStyle(.primary)

                Text(presentation.supportingMessage)
                    .font(.appBody)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(presentation.accessibilityLabel))

            if let ctaLabel = presentation.ctaLabel, presentation.cta != nil {
                if isLowEmphasisAction {
                    SecondaryButton(ctaLabel, icon: "arrow.clockwise", action: action)
                } else {
                    PrimaryButton(ctaLabel, icon: ctaIcon, action: action)
                }
            }
        }
        .frame(maxWidth: 520)
        .padding(Spacing.large)
        .background(
            Color.secondary.opacity(ColorOpacity.placeholderFill),
            in: RoundedRectangle(cornerRadius: CornerRadius.large)
        )
    }

    private var heroSize: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 112 }
        return horizontalSizeClass == .regular ? 160 : 136
    }

    private var isLowEmphasisAction: Bool {
        presentation.cue.state == .idle(.allCaughtUp)
    }

    private var ctaIcon: String {
        switch presentation.cta {
        case .review: "rectangle.stack.badge.play"
        case .startScanning, .none: "sparkles"
        }
    }
}
