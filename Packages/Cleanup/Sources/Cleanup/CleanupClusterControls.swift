import SwiftUI
import Photos
import Core

public enum CleanupClusterSort: String, CaseIterable, Sendable {
    case newest
    case largestCleanupOpportunity
    case largestCluster
    case similarity
    case reviewStatus

    var title: String {
        switch self {
        case .newest:
            CleanupL10n.Main.newest
        case .largestCleanupOpportunity:
            CleanupL10n.Main.mostSpaceToSave
        case .largestCluster:
            CleanupL10n.Main.largestCluster
        case .similarity:
            CleanupL10n.Main.highestSimilarity
        case .reviewStatus:
            CleanupL10n.Main.reviewStatus
        }
    }
}

public enum CleanupReviewFilter: String, CaseIterable, Sendable {
    case all
    case needsReview
    case inReview
    case reviewed

    /// `needsReview` covers everything the user has not finished reviewing: clusters
    /// never opened (`notReviewed`) as well as clusters a rescan changed (`needsReReview`).
    public func matches(_ status: ClusterReviewStatus) -> Bool {
        switch self {
        case .all: true
        case .needsReview: status == .notReviewed || status == .needsReReview
        case .inReview: status == .inReview
        case .reviewed: status == .reviewed
        }
    }

    var title: String {
        switch self {
        case .all:
            CleanupL10n.Main.allReviewStates
        case .needsReview:
            CleanupL10n.Main.needsReview
        case .inReview:
            CleanupL10n.Main.inReview
        case .reviewed:
            CleanupL10n.Main.reviewed
        }
    }
}

public enum CleanupMinimumClusterSize: Int, CaseIterable, Sendable {
    case any = 0
    case two = 2
    case three = 3
    case five = 5
    case ten = 10
    case twenty = 20

    var title: String {
        self == .any
            ? CleanupL10n.Main.anySize
            : String(format: CleanupL10n.Main.orMorePhotos, rawValue)
    }
}
public struct CleanupClusterControls: Equatable, Sendable {
    public var sort: CleanupClusterSort = .newest
    public var reviewFilter: CleanupReviewFilter = .all
    public var minimumClusterSize: CleanupMinimumClusterSize = .any
    public var favoritesOnly = false
    public var isDefault: Bool { self == Self() }

    public init() {}

    public func matches(_ cluster: PhotoCluster, reviewStatus: ClusterReviewStatus) -> Bool {
        reviewFilter.matches(reviewStatus)
            && cluster.count >= minimumClusterSize.rawValue
            && (!favoritesOnly || cluster.assets.contains(where: \.isFavorite))
    }
}

struct CleanupClusterControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var controls: CleanupClusterControls
    let isAdvancedFilteringLocked: Bool
    let onRequestAdvancedFilters: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(CleanupL10n.Main.sortBy) {
                    Picker(CleanupL10n.Main.sortOrder, selection: $controls.sort) {
                        ForEach(CleanupClusterSort.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }

                Section(CleanupL10n.Main.filterBy) {
                    if isAdvancedFilteringLocked {
                        Button(action: onRequestAdvancedFilters) {
                            Label(CleanupL10n.Main.unlockAdvancedFilters, systemImage: "lock.fill")
                        }
                    } else {
                        Picker(CleanupL10n.Main.reviewStatus, selection: $controls.reviewFilter) {
                            ForEach(CleanupReviewFilter.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        Picker(CleanupL10n.Main.minimumClusterSize, selection: $controls.minimumClusterSize) {
                            ForEach(CleanupMinimumClusterSize.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        Toggle(CleanupL10n.Main.favoritesOnly, isOn: $controls.favoritesOnly)
                    }
                }

                Section {
                    Button(CleanupL10n.Main.resetControls, role: .destructive) {
                        controls = CleanupClusterControls()
                    }
                    .disabled(controls.isDefault)
                }
            }
            .navigationTitle(Text(CleanupL10n.Main.filterAndSort))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CleanupL10n.Main.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Controls Sheet") {
    CleanupClusterControlsSheet(
        controls: .constant(CleanupClusterControls()),
        isAdvancedFilteringLocked: false,
        onRequestAdvancedFilters: {}
    )
}
