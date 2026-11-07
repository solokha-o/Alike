import Core
import Foundation
import Storage

extension CleanupWorkspaceModel {
    /// Joins an in-flight scan only when it is analyzing at the same
    /// sensitivity the caller asked for; a request at a different sensitivity
    /// would otherwise silently report a summary computed at the wrong
    /// sensitivity. A mismatched request instead waits for the in-flight scan
    /// to finish and then runs its own, so the caller's chosen sensitivity is
    /// always honored.
    func startScan(
        sensitivity: SensitivityLevel,
        purpose: ScanOperationPurpose
    ) async throws -> ScanOutcome {
        try Task.checkCancellation()

        // Loops rather than checking once: two mismatched requests can both be
        // waiting on the same in-flight scan, and the one that resumes second
        // must wait for the scan the first one started instead of racing it.
        // Awaiting a task that is already finished returns immediately, so the
        // identity check below is what guarantees the loop terminates.
        while let inFlight = scanTask {
            if activeScan?.sensitivity == sensitivity {
                if purpose == .userInitiated, activeScan?.purpose == .reconciliation {
                    reflectUserInitiatedJoin()
                }
                let summary = try await inFlight.value
                return ScanOutcome(summary: summary, joinedInFlightOperation: true)
            }
            _ = try? await inFlight.value
            if scanTask == inFlight { break }
        }

        scanMutationGeneration &+= 1
        let scanID = UUID()
        activeScan = (scanID, sensitivity, purpose)
        scanOperation = .scanning(progress: 0, purpose: purpose)
        // A scan whose owner has not finished its own cleanup yet leaves its
        // relay behind; cancel it so it stops forwarding into a scan that is
        // no longer the active one.
        await progressRelay?.cancel()
        progressRelay = ScanProgressRelay { [weak self] progress in
            self?.publishScanProgress(progress, scanID: scanID)
        }

        let task = Task { @MainActor [weak self] () throws -> ScanSummary in
            guard let self else { throw CancellationError() }
            return try await self.performScan(
                sensitivity: sensitivity,
                purpose: purpose,
                scanID: scanID
            )
        }
        scanTask = task

        // Each branch settles the workspace state before its only suspension
        // point. Awaiting the relay first would let `prepareForDataDeletion`
        // reset the workspace in that gap, and this scan would then write its
        // stale outcome over the reset.
        do {
            let summary = try await task.value
            if activeScan?.id == scanID {
                let finishedRelay = progressRelay
                progressRelay = nil
                scanTask = nil
                activeScan = nil
                scanOperation = .idle
                await finishedRelay?.cancel()
            }
            return ScanOutcome(summary: summary, joinedInFlightOperation: false)
        } catch {
            if activeScan?.id == scanID {
                let finishedRelay = progressRelay
                progressRelay = nil
                scanTask = nil
                let failurePurpose = activeScan?.purpose ?? purpose
                activeScan = nil
                scanOperation = .failed(message: error.localizedDescription, purpose: failurePurpose)
                await finishedRelay?.cancel()
            }
            throw error
        }
    }

    /// Flips the currently active scan's displayed purpose to `.userInitiated`
    /// when a user scan joins a still-running reconciliation, so the UI shows
    /// scanning rather than refreshing for the rest of that operation.
    private func reflectUserInitiatedJoin() {
        guard var current = activeScan, current.purpose == .reconciliation else { return }
        current.purpose = .userInitiated
        activeScan = current
        if case .scanning(let progress, _) = scanOperation {
            scanOperation = .scanning(progress: progress, purpose: .userInitiated)
        }
    }

    func runReconciliationQueue(
        initial: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)
    ) async {
        var next: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)? = initial

        while let request = next {
            guard !Task.isCancelled else { break }
            activeReconciliation = request
            queuedReconciliation = nil
            reconciliationState = .refreshing(request.record)

            do {
                _ = try await startScan(sensitivity: request.sensitivity, purpose: .reconciliation)
                reconciliationState = .success(request.record)
            } catch {
                guard !Task.isCancelled else { break }
                let refreshedInsights = await fetchCleanupInsights()
                publish(replacing(lastGoodContent, insights: refreshedInsights))
                reconciliationState = .failed(
                    request.record,
                    message: "The photos were deleted, but the library refresh failed. Run a new scan to refresh your results."
                )
            }

            next = queuedReconciliation
        }

        activeReconciliation = nil
        queuedReconciliation = nil
    }

    func performScan(
        sensitivity: SensitivityLevel,
        purpose: ScanOperationPurpose,
        scanID: UUID
    ) async throws -> ScanSummary {
        let clustersBeforeScan = try await repository.loadClusters()
        let categorySnapshotsBeforeScan = try? await cleanupCategoryRepository.loadAllSnapshots()
        let scanMetadataBeforeScan = await repository.loadScanMetadata()
        let previousSnapshots = try await repository.loadClusterSnapshots()
        let previousReviewStates = try await reviewRepository.loadAllReviewStates()
        // Analysis warms sizes for every cluster photo; reuse what a launch measured.
        await seedByteSizesIfNeeded()

        guard let progressRelay else { throw CancellationError() }
        // Captured now, immediately before analysis takes its own snapshot of
        // the library's assets. A photo added or removed while Vision/category
        // work is running would otherwise be included in a late token/count
        // while remaining absent from the clusters that work produces, so the
        // next change check would see no delta and never prompt for the rescan
        // that photo actually requires.
        let capturedFingerprint = await repository.captureScanMetadata(completedAt: now())
        let analyzedClusters = try await analysisService.analyzePhotoLibrary(
            sensitivity: sensitivity.threshold
        ) { progress in
            Task { await progressRelay.submit(ScanProgressStages.analysis(progress)) }
        }
        try Task.checkCancellation()
        await progressRelay.submit(ScanProgressStages.analysis(1), force: true)
        let refreshedCategories = try await analysisService.refreshCleanupCategories { progress in
            Task { await progressRelay.submit(ScanProgressStages.categories(progress)) }
        }
        try Task.checkCancellation()
        await progressRelay.submit(ScanProgressStages.persistenceStart, force: true)

        let completedAt: Date
        do {
            try await repository.saveClusters(analyzedClusters)
            // The fingerprint itself was captured before analysis started, so it
            // matches the asset input the persisted clusters were derived from.
            // Only the completion timestamp is stamped now, and the pairing is
            // persisted only after a successful scan — a failed scan below must
            // not advance the baseline past clusters that were never saved.
            completedAt = now()
            try await repository.updateScanMetadata(
                ScanMetadataSnapshot(
                    lastScanDate: completedAt,
                    libraryChangeToken: capturedFingerprint.libraryChangeToken,
                    imageAssetCount: capturedFingerprint.imageAssetCount
                )
            )
            try Task.checkCancellation()
        } catch {
            await restorePersistedContent(
                clusters: clustersBeforeScan,
                categorySnapshots: categorySnapshotsBeforeScan,
                scanMetadata: scanMetadataBeforeScan
            )
            throw error
        }

        let sortedClusters = await postProcessor.canonicalSortedClusters(analyzedClusters)
        try Task.checkCancellation()
        let migratedStates = await postProcessor.migratedReviewStates(
            previousSnapshots: previousSnapshots,
            previousReviewStates: previousReviewStates,
            newClusters: sortedClusters
        )
        let reviewData = await persistMigratedReviewData(migratedStates, clusters: sortedClusters)
        let session = await cleanupManager.syncSession(
            for: sortedClusters,
            reviewStates: reviewData.states
        )
        let insights = await fetchCleanupInsights()
        // The refresh above persisted the categories with their identifiers; the
        // estimate needs those identifiers to count a screenshot inside a cluster once.
        // A category the refresh reported but the repository cannot hand back keeps
        // its summary figure, so the estimate never silently drops a category.
        let categorySnapshots = await postProcessor.categorySnapshots(
            persisted: fetchCleanupCategorySnapshots(),
            refreshed: refreshedCategories,
            refreshedAt: completedAt
        )
        let content = CleanupWorkspaceContent(
            clusters: sortedClusters,
            categories: refreshedCategories,
            reviewStates: reviewData.states,
            resurfacingStates: reviewData.resurfacingStates,
            activeSession: session,
            insights: insights,
            hasCompletedScanBaseline: true,
            shouldShowRescanPrompt: false,
            categorySnapshots: categorySnapshots
        )
        publish(content)
        await persistByteSizesIfNeeded(for: content)

        let summary = ScanSummary(
            clusterCount: sortedClusters.count,
            cleanupCategoryCandidateCount: refreshedCategories.reduce(0) { $0 + max($1.assetCount, 0) },
            // The same figure `reclaimableEstimate` now holds for this content, so the
            // scanner card and a later cold launch cannot disagree.
            estimatedSavingsBytes: reclaimableEstimate.totalBytes,
            completedAt: completedAt
        )
        lastScanSummary = summary
        lastCompletedScanDate = summary.completedAt
        await adoptLibraryTotalBytes(await analysisService.libraryTotalBytes())
        await progressRelay.submit(ScanProgressStages.completed, force: true)
        return summary
    }

    private func publishScanProgress(_ progress: Double, scanID: UUID) {
        guard activeScan?.id == scanID,
              case .scanning(let current, let purpose) = scanOperation else {
            return
        }
        let next = max(current, min(max(progress, 0), 1))
        scanOperation = .scanning(progress: next, purpose: purpose)
    }

    private func restorePersistedContent(
        clusters: [PhotoCluster],
        categorySnapshots: [CleanupCategoryKind: CleanupCategorySnapshot]?,
        scanMetadata: ScanMetadataSnapshot?
    ) async {
        do {
            try await repository.saveClusters(clusters)
        } catch {
            AppLog.storage.error("Failed to restore clusters after scan failure: \(error.localizedDescription)")
        }

        // The baseline may already have advanced before the failure; leaving it
        // there would pair a new scan date with the previous scan's clusters.
        do {
            try await repository.updateScanMetadata(scanMetadata)
        } catch {
            AppLog.storage.error("Failed to restore scan metadata after scan failure: \(error.localizedDescription)")
        }

        guard let categorySnapshots else { return }
        do {
            try await cleanupCategoryRepository.replaceAllSnapshots(Array(categorySnapshots.values))
        } catch {
            AppLog.storage.error("Failed to restore cleanup categories after scan failure: \(error.localizedDescription)")
        }
    }

    /// A scan that could not measure the library keeps the previous total.
    private func adoptLibraryTotalBytes(_ bytes: Int64?) async {
        guard let bytes else { return }
        libraryTotalBytes = bytes
        guard bytes != persistedLibraryTotalBytes else { return }
        do {
            try await assetByteSizeRepository.saveLibraryTotalBytes(bytes)
            persistedLibraryTotalBytes = bytes
        } catch {
            AppLog.storage.error("Failed to persist library total bytes: \(error.localizedDescription)")
        }
    }
}
