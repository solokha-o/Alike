import Photos
import Vision
import Core

protocol VisionFeaturePrintServicing: Sendable {
    func generateFeaturePrint(for asset: PHAsset) async throws -> VNFeaturePrintObservation?
    func generateFeaturePrints(
        for assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)]
    func computeDistance(
        between observation1: VNFeaturePrintObservation,
        and observation2: VNFeaturePrintObservation
    ) throws -> Float
}

protocol PhotoClusteringServicing: Sendable {
    func clusterPhotos(
        _ photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)],
        threshold: Float
    ) throws -> [PhotoCluster]
}

extension VisionFeaturePrintService: VisionFeaturePrintServicing {}
extension PhotoClusteringService: PhotoClusteringServicing {}
