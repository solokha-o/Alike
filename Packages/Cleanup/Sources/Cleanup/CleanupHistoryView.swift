import Core
import DesignSystem
import Foundation
import SwiftUI

@MainActor
struct CleanupHistoryView: View {
    let repository: any CleanupHistoryRepository

    @State private var state = HistoryState.loading

    var body: some View {
        List {
            historyContent
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.secondaryBackground.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 1)
        .navigationTitle(Text(appLocalized("History")))
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .task {
            guard state.isLoading else { return }
            await loadHistory()
        }
        .refreshable {
            await loadHistory()
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        switch state {
        case .loading:
            loadingContent
        case .empty:
            unavailableRow {
                ContentUnavailableView(
                    appLocalized("No Cleanup History"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(appLocalized("Completed cleanups will appear here."))
                )
            }
        case .loaded(let snapshot):
            summaryRow(snapshot.insights)
            activityHeader
            ForEach(snapshot.sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        CleanupHistoryTimelineRow(entry: entry)
                            .listRowInsets(
                                EdgeInsets(
                                    top: Spacing.xSmall,
                                    leading: Spacing.medium,
                                    bottom: Spacing.xSmall,
                                    trailing: Spacing.medium
                                )
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(section.month.formatted(.dateTime.month(.wide).year()))
                        .font(.appHeadline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        case .failed:
            unavailableRow {
                ContentUnavailableView {
                    Label(appLocalized("History Unavailable"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(appLocalized("Unable to load cleanup history."))
                } actions: {
                    Button(appLocalized("Retry")) {
                        state = .loading
                        Task { await loadHistory() }
                    }
                    .cleanupGlassButton()
                }
            }
        }
    }

    @ViewBuilder
    private var loadingContent: some View {
        summaryRow(.placeholder)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)

        Section(appLocalized("Recent Activity")) {
            ForEach(0..<3, id: \.self) { index in
                CleanupHistoryTimelineRow(entry: .placeholder(index: index))
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
                    .listRowInsets(
                        EdgeInsets(
                            top: Spacing.xSmall,
                            leading: Spacing.medium,
                            bottom: Spacing.xSmall,
                            trailing: Spacing.medium
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func summaryRow(_ insights: CleanupInsights) -> some View {
        CleanupHistorySummaryCard(insights: insights)
            .listRowInsets(
                EdgeInsets(
                    top: Spacing.medium,
                    leading: Spacing.medium,
                    bottom: Spacing.large,
                    trailing: Spacing.medium
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var activityHeader: some View {
        Text(appLocalized("Recent Activity"))
            .font(.appTitle3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: Spacing.medium,
                    bottom: Spacing.xSmall,
                    trailing: Spacing.medium
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func unavailableRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 360)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func loadHistory() async {
        do {
            let entries = try await repository.loadEntries()
            let snapshot = CleanupHistorySnapshot(entries: entries)
            state = snapshot.isEmpty ? .empty : .loaded(snapshot)
        } catch is CancellationError {
            return
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to present cleanup history: \(error.localizedDescription)"))"
            )
            state = .failed
        }
    }

    private enum HistoryState: Equatable {
        case loading
        case empty
        case loaded(CleanupHistorySnapshot)
        case failed

        var isLoading: Bool {
            self == .loading
        }
    }
}

private struct CleanupHistorySummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let insights: CleanupInsights

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Label(appLocalized("All-Time Impact"), systemImage: "sparkles")
                .font(.appHeadline)
                .foregroundStyle(Color.accent)

            VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
                Text(byteCount(insights.totalSavedBytes))
                    .font(.appTitle)
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                Text(appLocalized("Estimated Reclaimable"))
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
            }

            metrics

            Label(
                appLocalized("Storage may not be freed until items are permanently deleted from Recently Deleted."),
                systemImage: "info.circle"
            )
            .font(.appFootnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }

    @ViewBuilder
    private var metrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.small) {
                metric("\(insights.totalDeletedItems)", appLocalized("Photos Moved to Recently Deleted"))
                metric("\(insights.cleanupSessionCount)", appLocalized("Cleanup Sessions"))
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.medium) {
                metric("\(insights.totalDeletedItems)", appLocalized("Photos Moved to Recently Deleted"))
                Divider()
                metric("\(insights.cleanupSessionCount)", appLocalized("Cleanup Sessions"))
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
            Text(value)
                .font(.appHeadline)
                .monospacedDigit()
            Text(label)
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupHistoryTimelineRow: View {
    let entry: CleanupCompletionRecord

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(
                    Color.accent.opacity(ColorOpacity.statusBackground),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
                Text(photoCountText)
                    .font(.appHeadline)
                Text(appLocalized("Moved to Recently Deleted"))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text(entry.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.small)

            Text(byteCount(entry.estimatedSavingsBytes))
                .font(.appHeadline)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .cleanupGlassSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(
            Text(entry.completedAt.formatted(date: .complete, time: .shortened))
        )
    }

    private var photoCountText: String {
        switch CleanupHistoryPhotoCount(entry.deletedCount) {
        case .one:
            return appLocalized("1 photo")
        case .other(let count):
            return String(format: appLocalized("%d photos"), count)
        }
    }

    private var accessibilityLabel: String {
        switch CleanupHistoryPhotoCount(entry.deletedCount) {
        case .one:
            return String(
                format: appLocalized("%@ estimated reclaimable, 1 photo moved to Recently Deleted"),
                byteCount(entry.estimatedSavingsBytes)
            )
        case .other(let count):
            return String(
                format: appLocalized("%@ estimated reclaimable, %d photos moved to Recently Deleted"),
                byteCount(entry.estimatedSavingsBytes),
                count
            )
        }
    }
}

private func byteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private extension CleanupInsights {
    static let placeholder = CleanupInsights(
        totalDeletedItems: 42,
        totalSavedBytes: 42_000_000,
        cleanupSessionCount: 4,
        latestCleanup: nil
    )
}

private extension CleanupCompletionRecord {
    static func placeholder(index: Int) -> CleanupCompletionRecord {
        CleanupCompletionRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)") ?? UUID(),
            sourceClusterID: UUID(),
            deletedCount: 8,
            estimatedSavingsBytes: 8_000_000,
            completedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }
}
