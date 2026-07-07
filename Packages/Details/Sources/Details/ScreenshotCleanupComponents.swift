import SwiftUI
import Photos
import Core
import DesignSystem

struct ScreenshotCleanupSummaryCard: View {
    let screenshotCount: Int
    let selectedCount: Int
    let estimatedSavingsText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(appLocalized("Screenshot Cleanup"))
                .font(.headline)

            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if selectedCount > 0 {
                Text(savingsText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.secondary.opacity(ColorOpacity.placeholderFill), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private var summaryText: String {
        if screenshotCount == 1 {
            return appLocalized("1 screenshot available for review.")
        }
        return "\(screenshotCount) screenshots available for review."
    }

    private var savingsText: String {
        if selectedCount == 1 {
            return "1 selected, about \(estimatedSavingsText) to free."
        }
        return "\(selectedCount) selected, about \(estimatedSavingsText) to free."
    }
}

struct ScreenshotCleanupActionBar: View {
    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onDeleteSelected: () -> Void
    let isDeleteActionVisible: Bool
    let isDeleting: Bool

    var body: some View {
        HStack(spacing: Spacing.small) {
            Button(appLocalized("Select All"), action: onSelectAll)
                .buttonStyle(.bordered)

            Button(appLocalized("Clear"), action: onClearSelection)
                .buttonStyle(.bordered)

            Spacer(minLength: Spacing.small)

            if isDeleteActionVisible {
                Button(role: .destructive, action: onDeleteSelected) {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Text(appLocalized("Delete Selected"))
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct PresentedScreenshotAsset: Identifiable {
    let asset: PHAsset
    let index: Int

    var id: String { asset.localIdentifier }
}
