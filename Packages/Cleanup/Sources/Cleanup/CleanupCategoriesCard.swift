import SwiftUI
import Core
import DesignSystem

struct CleanupCategoriesCard: View {
    let categories: [CleanupCategorySummary]
    let isLocked: (CleanupCategoryKind) -> Bool
    let onTap: (CleanupCategorySummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(CleanupL10n.Main.smartCleanup)
                .font(.appHeadline)

            ForEach(categories) { category in
                Button {
                    onTap(category)
                } label: {
                    HStack {
                        Image(systemName: category.kind.presentation.systemImageName)
                            .foregroundStyle(Color.accent)
                        VStack(alignment: .leading) {
                            Text(category.kind.presentation.title)
                                .font(.appHeadline)
                            Text(CleanupPresentation.categoryDetail(category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isLocked(category.kind) ? "lock.fill" : "chevron.forward")
                            .foregroundStyle(.secondary)
                    }
                    .padding(Spacing.small)
                    .background(
                        Color.secondary.opacity(ColorOpacity.statusBackground),
                        in: RoundedRectangle(cornerRadius: CornerRadius.small)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(CleanupPresentation.categoryAccessibilityLabel(category, isLocked: isLocked(category.kind)))
                )
                .accessibilityHint(
                    Text(
                        isLocked(category.kind)
                            ? CleanupL10n.Main.opensTheUpgradeOptions
                            : CleanupL10n.Main.openThisCleanupCategory
                    )
                )
            }
        }
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }
}
