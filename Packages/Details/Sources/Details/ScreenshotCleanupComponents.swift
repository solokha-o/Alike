import SwiftUI
import Photos
import Core
import DesignSystem

struct ScreenshotCleanupSummaryCard: View {
    let category: CleanupCategoryKind
    let assetCount: Int
    let selectedCount: Int
    let estimatedSavingsText: String

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
        if assetCount == 1 {
            return category.presentation.summarySingular
        }
        return String(format: category.presentation.summaryPluralFormat, assetCount)
    }

    private var savingsText: String {
        if selectedCount == 1 {
            return String(format: category.presentation.selectionSingularFormat, estimatedSavingsText)
        }
        return String(
            format: category.presentation.selectionPluralFormat,
            selectedCount,
            estimatedSavingsText
        )
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
