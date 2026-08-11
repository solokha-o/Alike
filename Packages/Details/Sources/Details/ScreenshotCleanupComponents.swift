import SwiftUI
import Photos
import Core
import DesignSystem

struct ScreenshotCleanupSummaryCard: View {
    let category: CleanupCategoryKind
    let assetCount: Int
    let selectedCount: Int
    let estimatedSavingsText: String
    let maximumEstimatedSavingsText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(category.presentation.reviewTitle)
                .font(.headline)

            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let helperText = category.presentation.helperText {
                Text(helperText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            selectionSummary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .modifier(ScreenshotCleanupGlassSurfaceModifier())
    }

    private var summaryText: String {
        category.summary(count: assetCount)
    }

    private var selectionSummary: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.reservedSelectionCounts(assetCount: assetCount), id: \.self) { count in
                selectionSummaryText(
                    savingsText(
                        selectedCount: count,
                        estimatedSavingsText: maximumEstimatedSavingsText
                    )
                )
                .hidden()
                .accessibilityHidden(true)
            }

            if selectedCount > 0 {
                selectionSummaryText(
                    savingsText(
                        selectedCount: selectedCount,
                        estimatedSavingsText: estimatedSavingsText
                    )
                )
                .foregroundStyle(Color.accentColor)
            }
        }
        .animation(nil, value: selectedCount)
    }

    private func selectionSummaryText(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func savingsText(selectedCount: Int, estimatedSavingsText: String) -> String {
        category.selectionSummary(count: selectedCount, estimatedSize: estimatedSavingsText)
    }

    static func reservedSelectionCounts(assetCount: Int) -> [Int] {
        guard assetCount > 0 else { return [0] }
        guard assetCount > 1 else { return [0, 1] }
        return [0, 1, assetCount]
    }
}

struct ScreenshotCleanupActionBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onDeleteSelected: () -> Void
    let isDeleteActionVisible: Bool
    let isDeleting: Bool

    var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: Spacing.small) {
                    controls(usesGlass: true)
                }
            } else {
                controls(usesGlass: false)
                    .padding(Spacing.xSmall)
                    .background(.regularMaterial, in: actionBarShape)
            }
        }
        .controlSize(.large)
        .animation(actionVisibilityAnimation, value: isDeleteActionVisible)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controls(usesGlass: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalControls(usesGlass: usesGlass)
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalControls(usesGlass: usesGlass)
                verticalControls(usesGlass: usesGlass)
            }
        }
    }

    private func horizontalControls(usesGlass: Bool) -> some View {
        ZStack {
            HStack(spacing: Spacing.small) {
                selectionButton(usesGlass: usesGlass, allowsWrapping: false)
                deleteActionButton(usesGlass: usesGlass, allowsWrapping: false)
            }
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            HStack(spacing: Spacing.small) {
                selectionButton(usesGlass: usesGlass, allowsWrapping: false)
                deleteButton(usesGlass: usesGlass, allowsWrapping: false)
            }
        }
    }

    private func verticalControls(usesGlass: Bool) -> some View {
        VStack(spacing: Spacing.small) {
            selectionButton(usesGlass: usesGlass, allowsWrapping: true)
            deleteButton(usesGlass: usesGlass, allowsWrapping: true)
        }
    }

    private func selectionButton(usesGlass: Bool, allowsWrapping: Bool) -> some View {
        Button(action: isDeleteActionVisible ? onClearSelection : onSelectAll) {
            ZStack {
                selectionButtonLabel(
                    title: DetailsL10n.ScreenshotCleanupComponents.selectAll,
                    systemImage: "checkmark.circle",
                    allowsWrapping: allowsWrapping
                )
                .hidden()
                .accessibilityHidden(true)

                selectionButtonLabel(
                    title: DetailsL10n.Common.clearSelection,
                    systemImage: "xmark.circle",
                    allowsWrapping: allowsWrapping
                )
                .hidden()
                .accessibilityHidden(true)

                selectionButtonLabel(
                    title: isDeleteActionVisible
                        ? DetailsL10n.Common.clearSelection
                        : DetailsL10n.ScreenshotCleanupComponents.selectAll,
                    systemImage: isDeleteActionVisible ? "xmark.circle" : "checkmark.circle",
                    allowsWrapping: allowsWrapping
                )
            }
            .frame(maxWidth: .infinity)
        }
        .modifier(ScreenshotCleanupButtonStyle(usesGlass: usesGlass))
        .accessibilityHint(Text(DetailsL10n.ScreenshotCleanupComponents.chooseWhichPhotosSelectedCleanup))
    }

    private func selectionButtonLabel(
        title: String,
        systemImage: String,
        allowsWrapping: Bool
    ) -> some View {
        Label {
            Text(title)
                .lineLimit(allowsWrapping ? 2 : 1)
                .fixedSize(horizontal: !allowsWrapping, vertical: allowsWrapping)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.appHeadline)
    }

    @ViewBuilder
    private func deleteButton(usesGlass: Bool, allowsWrapping: Bool) -> some View {
        if isDeleteActionVisible {
            deleteActionButton(usesGlass: usesGlass, allowsWrapping: allowsWrapping)
                .transition(actionVisibilityTransition)
        }
    }

    private func deleteActionButton(usesGlass: Bool, allowsWrapping: Bool) -> some View {
        Button(role: .destructive, action: onDeleteSelected) {
            HStack(spacing: Spacing.small) {
                if isDeleting {
                    ProgressView()
                } else {
                    Image(systemName: "trash")
                }

                Text(isDeleting ? DetailsL10n.ScreenshotCleanupComponents.deleting : DetailsL10n.ScreenshotCleanupComponents.deleteSelected)
                    .font(.appHeadline)
                    .lineLimit(allowsWrapping ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: !allowsWrapping, vertical: allowsWrapping)
            }
            .frame(maxWidth: .infinity)
        }
        .modifier(ScreenshotCleanupButtonStyle(usesGlass: usesGlass))
        .disabled(isDeleting)
        .accessibilityHint(Text(DetailsL10n.Common.moveCurrentlySelectedPhotosRecently))
    }

    private var actionVisibilityAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .appInteractiveFast
    }

    private var actionVisibilityTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .scale(scale: 0.9, anchor: .bottom))
                .combined(with: .opacity),
            removal: .scale(scale: 0.96, anchor: .bottom)
                .combined(with: .opacity)
        )
    }

    private var actionBarShape: Capsule {
        Capsule(style: .continuous)
    }
}

private struct ScreenshotCleanupGlassSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.medium))
        } else {
            content.background(.regularMaterial, in: surfaceShape)
        }
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
    }
}

private struct ScreenshotCleanupButtonStyle: ViewModifier {
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), usesGlass {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct PresentedScreenshotAsset: Identifiable {
    let asset: PHAsset
    let index: Int

    var id: String { asset.localIdentifier }
}
