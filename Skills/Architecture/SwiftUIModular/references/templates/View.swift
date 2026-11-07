// Template: the main view of one screen and one extracted section.
// File: Packages/FeatureName/Sources/FeatureName/FeatureNameView.swift.
// Based on: Packages/Details/Sources/Details/ScreenshotCleanupView.swift (the
// view owns its `@Observable` view model through `@State`, made in `init`),
// Packages/Cleanup/Sources/Cleanup/CleanupCategoriesCard.swift and
// Packages/Details/Sources/Details/ClusterDetailsToolbarItems.swift (a section
// with narrow inputs: values and closures, and a minimal preview).
// Do not copy the default service arguments of `ScreenshotCleanupView.init`:
// the composition root (Alike/Alike/Router/RootView.swift) passes them.
// Rules: ../swiftui-view-rules.md.

import Core
import DesignSystem
import SwiftUI

/// Shows the saved FeatureName entries.
public struct FeatureNameView: View {
    // MARK: - Properties

    @State private var viewModel: FeatureNameViewModel

    // MARK: - Init

    public init(repository: any FeatureNameRepository) {
        _viewModel = State(initialValue: FeatureNameViewModel(repository: repository))
    }

    // MARK: - Body

    public var body: some View {
        List {
            FeatureNameEntriesSection(
                entries: viewModel.entries,
                isLoading: viewModel.isLoading,
                errorMessage: viewModel.errorMessage,
                onRetry: retry
            )
        }
        .navigationTitle(Text(FeatureNameL10n.Main.title))
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Private Methods

    private func retry() {
        Task {
            await viewModel.load()
        }
    }
}

// MARK: - FeatureNameEntriesSection

/// Gets values and a closure, not the view model, so a preview needs no
/// service. Move it to `FeatureNameEntriesSection.swift` when another file
/// uses it or when this file gets near the `file_length` limit.
private struct FeatureNameEntriesSection: View {
    let entries: [FeatureNameEntry]
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        Section {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(errorMessage)
                    Button(FeatureNameL10n.Main.tryAgain, action: onRetry)
                }
            } else {
                ForEach(entries) { entry in
                    Text(entry.title)
                        .font(.appHeadline)
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("FeatureName") {
    NavigationStack {
        FeatureNameView(
            repository: MockFeatureNameRepository(entries: [
                FeatureNameEntry(title: "First"),
                FeatureNameEntry(title: "Second")
            ])
        )
    }
}

#Preview("Entries section, failed") {
    List {
        FeatureNameEntriesSection(
            entries: [],
            isLoading: false,
            errorMessage: "The entries could not load.",
            onRetry: {}
        )
    }
}
#endif
