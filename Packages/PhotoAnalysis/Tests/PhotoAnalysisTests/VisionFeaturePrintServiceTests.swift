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
        let cgImage = try XCTUnwrap(makeSolidImage(red: 255, green: 0, blue: 0))
        
        // When: Generating feature print
        let featurePrint = try await generateFeaturePrintOrSkip(from: cgImage)
        
        // Then: Feature print should be generated
        XCTAssertNotNil(featurePrint, "Feature print should not be nil")
        XCTAssertGreaterThan(featurePrint.data.count, 0, "Feature print should have data")
    }
    
    func testComputeDistanceBetweenIdenticalImages() async throws {
        let cgImage = try XCTUnwrap(makeSolidImage(red: 0, green: 0, blue: 255))
        
        let print1 = try await generateFeaturePrintOrSkip(from: cgImage)
        let print2 = try await generateFeaturePrintOrSkip(from: cgImage)
        
        // When: Computing distance
        let distance = try service.computeDistance(between: print1, and: print2)
        
        // Then: Distance should be non-negative
        XCTAssertGreaterThanOrEqual(distance, 0.0, "Distance should be non-negative")
    }
    
    func testComputeDistanceBetweenDifferentImages() async throws {
        let redCGImage = try XCTUnwrap(makeSolidImage(red: 255, green: 0, blue: 0))
        let blueCGImage = try XCTUnwrap(makeSolidImage(red: 0, green: 0, blue: 255))
        
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
        let cgImage1 = try XCTUnwrap(makeSolidImage(red: 255, green: 0, blue: 0))
        let cgImage2 = try XCTUnwrap(makeSolidImage(red: 0, green: 255, blue: 0))
        
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

    private func makeSolidImage(red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        let width = 100
        let height = 100
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 255, count: width * height * bytesPerPixel)

        for offset in stride(from: 0, to: data.count, by: bytesPerPixel) {
            data[offset] = red
            data[offset + 1] = green
            data[offset + 2] = blue
        }

        guard let provider = CGDataProvider(data: Data(data) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
