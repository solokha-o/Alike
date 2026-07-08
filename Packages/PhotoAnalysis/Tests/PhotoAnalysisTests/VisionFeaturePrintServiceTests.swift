import XCTest
import Vision
import Photos
#if canImport(UIKit)
import UIKit
#endif
@testable import PhotoAnalysis

@MainActor
final class VisionFeaturePrintServiceTests: XCTestCase {
    var service: VisionFeaturePrintService!
    
    override func setUp() async throws {
        service = VisionFeaturePrintService()
    }
    
    override func tearDown() async throws {
        service = nil
    }
    
    // MARK: - Feature Print Generation Tests
    
    func testGenerateFeaturePrintFromCGImage() async throws {
        // Given: A simple test image
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create CGImage")
            return
        }
        
        // When: Generating feature print
        let featurePrint = try await generateFeaturePrintOrSkip(from: cgImage)
        
        // Then: Feature print should be generated
        XCTAssertNotNil(featurePrint, "Feature print should not be nil")
        XCTAssertGreaterThan(featurePrint.data.count, 0, "Feature print should have data")
    }
    
    func testComputeDistanceBetweenIdenticalImages() async throws {
        // Given: Two identical feature prints from the same image
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create CGImage")
            return
        }
        
        let print1 = try await generateFeaturePrintOrSkip(from: cgImage)
        let print2 = try await generateFeaturePrintOrSkip(from: cgImage)
        
        // When: Computing distance
        let distance = try service.computeDistance(between: print1, and: print2)
        
        // Then: Distance should be non-negative
        XCTAssertGreaterThanOrEqual(distance, 0.0, "Distance should be non-negative")
    }
    
    func testComputeDistanceBetweenDifferentImages() async throws {
        // Given: Two different images
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let redImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        let blueImage = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        guard let redCGImage = redImage.cgImage,
              let blueCGImage = blueImage.cgImage else {
            XCTFail("Failed to create CGImages")
            return
        }
        
        let print1 = try await generateFeaturePrintOrSkip(from: redCGImage)
        let print2 = try await generateFeaturePrintOrSkip(from: blueCGImage)
        let printSame = try await generateFeaturePrintOrSkip(from: redCGImage)
        
        // When: Computing distance
        let distance = try service.computeDistance(between: print1, and: print2)
        let distanceSame = try service.computeDistance(between: print1, and: printSame)
        
        // Then: Distance should be non-negative
        XCTAssertGreaterThanOrEqual(distance, 0.0, "Distance should be non-negative")
        XCTAssertGreaterThanOrEqual(
            distance,
            distanceSame,
            "Different images should not be closer than identical ones"
        )
    }
    
    func testDistanceIsSymmetric() async throws {
        // Given: Two images
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image1 = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        let image2 = renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        guard let cgImage1 = image1.cgImage,
              let cgImage2 = image2.cgImage else {
            XCTFail("Failed to create CGImages")
            return
        }
        
        let print1 = try await generateFeaturePrintOrSkip(from: cgImage1)
        let print2 = try await generateFeaturePrintOrSkip(from: cgImage2)
        
        // When: Computing distance both ways
        let distance1to2 = try service.computeDistance(between: print1, and: print2)
        let distance2to1 = try service.computeDistance(between: print2, and: print1)
        
        // Then: Distance should be the same in both directions
        XCTAssertEqual(distance1to2, distance2to1, accuracy: 0.001, "Distance should be symmetric")
    }

    func testShouldSkipImageDataRequestForPhotosError() {
        let error = NSError(domain: PHPhotosErrorDomain, code: 3164)

        XCTAssertTrue(VisionFeaturePrintService.shouldSkipImageDataRequest(for: error))
    }

    func testShouldSkipImageDataRequestForAccountsError() {
        let error = NSError(domain: "com.apple.accounts", code: 7)

        XCTAssertTrue(VisionFeaturePrintService.shouldSkipImageDataRequest(for: error))
    }

    func testShouldNotSkipUnrelatedError() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 4)

        XCTAssertFalse(VisionFeaturePrintService.shouldSkipImageDataRequest(for: error))
    }

    func testShouldSkipUnderlyingPhotosError() {
        let underlying = NSError(domain: PHPhotosErrorDomain, code: 3164)
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: 0,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        XCTAssertTrue(VisionFeaturePrintService.shouldSkipImageDataRequest(for: wrapped))
    }

    private func generateFeaturePrintOrSkip(from cgImage: CGImage) async throws -> VNFeaturePrintObservation {
        do {
            let featurePrint = try await service.generateFeaturePrint(from: cgImage)
            return try XCTUnwrap(featurePrint)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSOSStatusErrorDomain {
                throw XCTSkip("Vision feature print unavailable: \(nsError.localizedDescription)")
            }
            throw error
        }
    }
}
