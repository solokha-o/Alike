import Vision
import CoreImage
import Photos
#if canImport(UIKit)
import UIKit
#endif

/// Service that processes photo feature prints using Vision framework
public struct VisionFeaturePrintService: Sendable {
    
    public init() {}
    
    /// Generate feature print for a single asset
    public func generateFeaturePrint(for asset: PHAsset) async throws -> VNFeaturePrintObservation? {
        // Load full resolution image data
        guard let imageData = try await asset.loadFullResolutionImageData() else {
            return nil
        }
        
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }
        
        return try await generateFeaturePrint(from: cgImage)
    }
    
    /// Generate feature print from CGImage
    private func generateFeaturePrint(from cgImage: CGImage) async throws -> VNFeaturePrintObservation? {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        
        try requestHandler.perform([request])
        
        return request.results?.first
    }
    
    /// Calculate distance between two feature prints (lower = more similar)
    public func computeDistance(
        between observation1: VNFeaturePrintObservation,
        and observation2: VNFeaturePrintObservation
    ) throws -> Float {
        var distance: Float = 0.0
        try observation1.computeDistance(&distance, to: observation2)
        return distance
    }
    
    /// Batch process multiple assets
    public func generateFeaturePrints(
        for assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] {
        var results: [(PHAsset, VNFeaturePrintObservation?)] = []
        let total = Double(assets.count)
        
        for (index, asset) in assets.enumerated() {
            let featurePrint = try await generateFeaturePrint(for: asset)
            results.append((asset, featurePrint))
            
            let currentProgress = Double(index + 1) / total
            await MainActor.run {
                progress(currentProgress)
            }
        }
        
        return results
    }
}
