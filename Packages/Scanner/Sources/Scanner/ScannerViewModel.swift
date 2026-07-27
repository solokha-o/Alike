import Cleanup
import Core
import DesignSystem
import Foundation
import Observation
import Purchases

/// Scanner-only state. Cleanup content and reconciliation belong to the shared
/// ``CleanupWorkspaceModel`` so they survive navigation between tabs.
@MainActor
@Observable
public final class ScannerViewModel {
    public enum State: Equatable {
        case idle
        case scanning(progress: Double)
        case completed(ScanSummary)
        case error(String)
    }

    public var gridColumns: Int
    public var sensitivity: SensitivityLevel
    public private(set) var state: State = .idle
    public private(set) var monthlyScanUsage: MonthlyScanUsage?
    public private(set) var pendingPostScanPremiumOffer: PostScanPremiumOffer?

    public let workspace: CleanupWorkspaceModel
    public let premiumAccess: any PremiumAccessControlling

    private let scanUsageRepository: any ScanUsageRepository
    private let premiumPromptHistoryRepository: any PremiumPromptHistoryRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var scanOperation: Task<PremiumAccessDecision, Never>?
    private var workspaceObservationTask: Task<Void, Never>?

    public var remainingFreeScans: Int {
        monthlyScanUsage?.remainingFreeScans ?? PremiumAccessPolicy.monthlyFreeScanLimit
    }

    public var nextFreeScanResetDate: Date? { monthlyScanUsage?.nextResetDate }
    public var hasUnlimitedScanAccess: Bool { premiumAccess.access(to: .unlimitedScans).isAllowed }
    public var hasCompletedScanBaseline: Bool { workspace.hasCompletedScanBaseline }

    public init(
        workspace: CleanupWorkspaceModel,
        gridColumns: Int = 3,
        sensitivity: SensitivityLevel = .medium,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        scanUsageRepository: any ScanUsageRepository = UserDefaultsScanUsageRepository(),
        premiumPromptHistoryRepository: any PremiumPromptHistoryRepository = UserDefaultsPremiumPromptHistoryRepository(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workspace = workspace
        self.gridColumns = gridColumns
        self.sensitivity = sensitivity
        self.premiumAccess = premiumAccess
        self.scanUsageRepository = scanUsageRepository
        self.premiumPromptHistoryRepository = premiumPromptHistoryRepository
        self.calendar = calendar
        self.now = now
    }

    public func load() async {
        await workspace.loadCachedContent()
        monthlyScanUsage = await resolveMonthlyScanUsage(at: now())
        await workspace.checkForGalleryChanges()
        synchronizeStateWithWorkspace()
    }

    /// Admission and allowance are Scanner responsibilities; the workspace
    /// executes and retains the actual scan for both top-level tabs.
    @discardableResult
    public func startScanning() async -> PremiumAccessDecision {
        if let scanOperation { return await scanOperation.value }

        let task = Task { @MainActor [weak self] in
            guard let self else { return PremiumAccessDecision.requiresPremium }
            return await self.performUserInitiatedScan()
        }
        scanOperation = task
        let decision = await task.value
        scanOperation = nil
        return decision
    }

    public func consumePostScanPremiumOffer() { pendingPostScanPremiumOffer = nil }

    private func performUserInitiatedScan() async -> PremiumAccessDecision {
        let usage = await resolveMonthlyScanUsage(at: now())
        monthlyScanUsage = usage
        let decision = premiumAccess.access(
            to: .unlimitedScans,
            context: .scan(completedThisMonth: usage.completedScanCount)
        )
        guard decision.isAllowed else { return decision }

        let joinsReconciliation: Bool
        if case .scanning(_, .reconciliation) = workspace.scanOperation {
            joinsReconciliation = true
        } else {
            joinsReconciliation = false
        }

        state = .scanning(progress: workspace.scanOperation.progress ?? 0)
        observeWorkspaceScan()
        do {
            let summary = try await workspace.scan(sensitivity: sensitivity)
            state = .completed(summary)
            if !joinsReconciliation {
                monthlyScanUsage = await scanUsageRepository.recordCompletedScan(at: now())
                await publishPostScanPremiumOfferIfEligible(summary)
            }
        } catch is CancellationError {
            synchronizeStateWithWorkspace()
        } catch {
            state = .error(error.localizedDescription)
        }
        workspaceObservationTask?.cancel()
        workspaceObservationTask = nil
        return .allowed
    }

    private func observeWorkspaceScan() {
        workspaceObservationTask?.cancel()
        workspaceObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let operation = self?.workspace.scanOperation else { return }
                if case .scanning(let progress, _) = operation {
                    self?.state = .scanning(progress: progress)
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func synchronizeStateWithWorkspace() {
        switch workspace.scanOperation {
        case .scanning(let progress, .userInitiated): state = .scanning(progress: progress)
        case .failed(let message, .userInitiated): state = .error(message)
        default:
            if let summary = workspace.lastScanSummary {
                state = .completed(summary)
            } else if workspace.hasCompletedScanBaseline {
                state = .completed(ScanSummary(
                    clusterCount: workspace.clusters.count,
                    cleanupCategoryCandidateCount: workspace.cleanupCategories.reduce(0) { $0 + max($1.assetCount, 0) },
                    estimatedSavingsBytes: estimatedSavings(),
                    completedAt: workspace.lastCompletedScanDate ?? now()
                ))
            } else {
                state = .idle
            }
        }
    }

    private func estimatedSavings() -> Int64 {
        let clusterSavings = workspace.clusters.flatMap(\.assets).reduce(Int64(0)) { $0 + $1.estimatedCleanupBytes }
        return clusterSavings + workspace.cleanupCategories.reduce(Int64(0)) { $0 + $1.estimatedSavingsBytes }
    }

    private func publishPostScanPremiumOfferIfEligible(_ summary: ScanSummary) async {
        let entitlement = premiumAccess.entitlementState
        guard entitlement.source != .unknown,
              !entitlement.isPremium,
              summary.clusterCount + summary.cleanupCategoryCandidateCount > 0,
              await premiumPromptHistoryRepository.claimPostFirstUsefulScanPrompt() else { return }

        let currentEntitlement = premiumAccess.entitlementState
        guard currentEntitlement.source != .unknown else {
            await premiumPromptHistoryRepository.releasePostFirstUsefulScanPromptClaim()
            return
        }
        guard !currentEntitlement.isPremium else { return }
        pendingPostScanPremiumOffer = PostScanPremiumOffer(
            similarClusterCount: summary.clusterCount,
            cleanupCategoryCandidateCount: summary.cleanupCategoryCandidateCount,
            estimatedSavingsBytes: summary.estimatedSavingsBytes
        )
    }

    private func resolveMonthlyScanUsage(at date: Date) async -> MonthlyScanUsage {
        if let usage = await scanUsageRepository.loadMonthlyUsage(at: date) { return usage }
        let lastScanDate = workspace.lastCompletedScanDate
        let completedCount = lastScanDate.map { calendar.isDate($0, equalTo: date, toGranularity: .month) ? 1 : 0 } ?? 0
        let periodStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let usage = MonthlyScanUsage(
            periodStart: periodStart,
            nextResetDate: calendar.date(byAdding: .month, value: 1, to: periodStart) ?? date,
            completedScanCount: completedCount
        )
        await scanUsageRepository.initializeMonthlyUsage(usage)
        return usage
    }
}

public struct PostScanPremiumOffer: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let similarClusterCount: Int
    public let cleanupCategoryCandidateCount: Int
    public let estimatedSavingsBytes: Int64

    public init(id: UUID = UUID(), similarClusterCount: Int, cleanupCategoryCandidateCount: Int, estimatedSavingsBytes: Int64) {
        self.id = id
        self.similarClusterCount = similarClusterCount
        self.cleanupCategoryCandidateCount = cleanupCategoryCandidateCount
        self.estimatedSavingsBytes = estimatedSavingsBytes
    }
}
