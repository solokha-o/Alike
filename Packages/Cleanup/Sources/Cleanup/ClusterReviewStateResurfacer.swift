import Core
import Foundation

struct ClusterReviewResurfacingResult: Equatable {
    let migratedReviewStates: [UUID: ClusterReviewState]
    let resurfacingStates: [UUID: ClusterResurfacingState]
}

enum ClusterReviewStateResurfacer {
    static func resurface(
        previousSnapshots: [PhotoClusterSnapshot],
        newClusters: [PhotoCluster],
        existingReviewStates: [UUID: ClusterReviewState]
    ) -> ClusterReviewResurfacingResult {
        resurface(
            previousSnapshots: previousSnapshots,
            newSnapshots: newClusters.map(PhotoClusterSnapshot.init),
            existingReviewStates: existingReviewStates
        )
    }

    static func resurface(
        previousSnapshots: [PhotoClusterSnapshot],
        newSnapshots: [PhotoClusterSnapshot],
        existingReviewStates: [UUID: ClusterReviewState]
    ) -> ClusterReviewResurfacingResult {
        let exactMatches = Dictionary(grouping: previousSnapshots, by: \.assetIdentifiers)
        let now = Date()

        var migratedReviewStates: [UUID: ClusterReviewState] = [:]
        var resurfacingStates: [UUID: ClusterResurfacingState] = [:]
        var remainingExactMatches = exactMatches

        for newSnapshot in newSnapshots {
            if var matchingSnapshots = remainingExactMatches[newSnapshot.assetIdentifiers],
               let matchedSnapshot = matchingSnapshots.first {
                matchingSnapshots.removeFirst()
                remainingExactMatches[newSnapshot.assetIdentifiers] = matchingSnapshots

                if matchedSnapshot.bestShotLocalIdentifier == newSnapshot.bestShotLocalIdentifier {
                    resurfacingStates[newSnapshot.id] = .unchanged
                    if let existingState = existingReviewStates[matchedSnapshot.id] {
                        migratedReviewStates[newSnapshot.id] = existingState.remapped(
                            clusterID: newSnapshot.id,
                            bestShotLocalIdentifier: newSnapshot.bestShotLocalIdentifier
                                ?? existingState.bestShotLocalIdentifier,
                            selectedLocalIdentifiers: existingState.selectedLocalIdentifiers,
                            updatedAt: existingState.updatedAt,
                            resurfacingState: existingState.resurfacingState
                        )
                    }
                    continue
                }

                resurfacingStates[newSnapshot.id] = .changed
                migratedReviewStates[newSnapshot.id] = needsReviewState(
                    for: newSnapshot,
                    resurfacingState: .changed,
                    updatedAt: now
                )
                continue
            }

            let resurfacingState: ClusterResurfacingState = previousSnapshots.contains {
                !$0.assetIdentifiers.isDisjoint(with: newSnapshot.assetIdentifiers)
            } ? .changed : .new

            resurfacingStates[newSnapshot.id] = resurfacingState
            migratedReviewStates[newSnapshot.id] = needsReviewState(
                for: newSnapshot,
                resurfacingState: resurfacingState,
                updatedAt: now
            )
        }

        return ClusterReviewResurfacingResult(
            migratedReviewStates: migratedReviewStates,
            resurfacingStates: resurfacingStates
        )
    }
}

private extension ClusterReviewStateResurfacer {
    static func needsReviewState(
        for snapshot: PhotoClusterSnapshot,
        resurfacingState: ClusterResurfacingState,
        updatedAt: Date
    ) -> ClusterReviewState {
        ClusterReviewState(
            clusterID: snapshot.id,
            bestShotLocalIdentifier: snapshot.bestShotLocalIdentifier
                ?? snapshot.assets.first?.localIdentifier
                ?? "",
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .needsReReview,
            estimatedSavingsBytes: 0,
            updatedAt: updatedAt,
            resurfacingState: resurfacingState
        )
    }
}
