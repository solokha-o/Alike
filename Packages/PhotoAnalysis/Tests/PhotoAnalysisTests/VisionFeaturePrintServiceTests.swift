import Foundation
import Testing
import Vision
import Photos
#if canImport(UIKit)
import UIKit
#endif
@testable import PhotoAnalysis

@MainActor
@Suite struct VisionFeaturePrintServiceTests {
    var service: VisionFeaturePrintService!
    
    override func setUp() async throws {
        service = VisionFeaturePrintService()
    }
    
    override func tearDown() async throws {
        service = nil
    }
    
    // MARK: - Feature Print Generation Tests
    
    @Test(.enabled("Vision feature print unavailable") { await visionFeaturePrintIsAvailable() })
    func testGenerateFeaturePrintFromCGImage() async throws {
        let cgImage = try #require(makeSolidImage(red: 255, green: 0, blue: 0))
        
        // When: Generating feature print
        let featurePrint = try await requireFeaturePrint(from: cgImage)
        
        // Then: Feature print should be generated
        #expect(featurePrint != nil, "Feature print should not be nil")
        #expect(featurePrint.data.count > 0, "Feature print should have data")
    }
    
    @Test(.enabled("Vision feature print unavailable") { await visionFeaturePrintIsAvailable() })
    func testComputeDistanceBetweenIdenticalImages() async throws {
        let cgImage = try #require(makeSolidImage(red: 0, green: 0, blue: 255))
        
        let print1 = try await requireFeaturePrint(from: cgImage)
        let print2 = try await requireFeaturePrint(from: cgImage)
        
        // When: Computing distance
        let distance = try service.computeDistance(between: print1, and: print2)
        
        // Then: Distance should be non-negative
        #expect(distance >= 0.0, "Distance should be non-negative")
    }
    
    @Test(.enabled("Vision feature print unavailable") { await visionFeaturePrintIsAvailable() })
    func testComputeDistanceBetweenDifferentImages() async throws {
        let redCGImage = try #require(makeSolidImage(red: 255, green: 0, blue: 0))
        let blueCGImage = try #require(makeSolidImage(red: 0, green: 0, blue: 255))
        
        let print1 = try await requireFeaturePrint(from: redCGImage)
        let print2 = try await requireFeaturePrint(from: blueCGImage)
        let printSame = try await requireFeaturePrint(from: redCGImage)
        
        // When: Computing distance
        let distance = try service.computeDistance(between: print1, and: print2)
        let distanceSame = try service.computeDistance(between: print1, and: printSame)
        
        // Then: Distance should be non-negative
        #expect(distance >= 0.0, "Distance should be non-negative")
        #expect(
            distance >= distanceSame,
            "Different images should not be closer than identical ones"
        )
    }
    
    @Test(.enabled("Vision feature print unavailable") { await visionFeaturePrintIsAvailable() })
    func testDistanceIsSymmetric() async throws {
        let cgImage1 = try #require(makeSolidImage(red: 255, green: 0, blue: 0))
        let cgImage2 = try #require(makeSolidImage(red: 0, green: 255, blue: 0))
        
        let print1 = try await requireFeaturePrint(from: cgImage1)
        let print2 = try await requireFeaturePrint(from: cgImage2)
        
        // When: Computing distance both ways
        let distance1to2 = try service.computeDistance(between: print1, and: print2)
        let distance2to1 = try service.computeDistance(between: print2, and: print1)
        
        // Then: Distance should be the same in both directions
        #expect(abs(distance1to2 - distance2to1) <= 0.001, "Distance should be symmetric")
    }

    @Test func testShouldSkipImageDataRequestForPhotosError() {
        let error = NSError(domain: PHPhotosErrorDomain, code: 3164)

        #expect(VisionFeaturePrintService.shouldSkipImageDataRequest(for: error))
    }

    @Test func testShouldSkipImageDataRequestForAccountsError() {
        let error = NSError(domain: "com.apple.accounts", code: 7)

        #expect(VisionFeaturePrintService.shouldSkipImageDataRequest(for: error))
    }

    @Test func testShouldNotSkipUnrelatedError() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 4)

        #expect(!(VisionFeaturePrintService.shouldSkipImageDataRequest(for: error)))
    }

    @Test func testShouldSkipUnderlyingPhotosError() {
        let underlying = NSError(domain: PHPhotosErrorDomain, code: 3164)
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: 0,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        #expect(VisionFeaturePrintService.shouldSkipImageDataRequest(for: wrapped))
    }

    #if canImport(UIKit)
    @Test func testThumbnailRequestStateCancellationBeforeInstallResumesExactlyOnce() async {
        let state = FeaturePrintThumbnailRequestState()
        state.cancel()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                #expect(!(state.install(continuation)))
                state.timeout()
            } as ThumbnailCGImage?
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testThumbnailRequestStateTimeoutReturnsNilExactlyOnce() async throws {
        let state = FeaturePrintThumbnailRequestState()

        let thumbnail = try await withCheckedThrowingContinuation { continuation in
            #expect(state.install(continuation))
            state.timeout()
            state.finish(.success(nil))
        } as ThumbnailCGImage?

        #expect(thumbnail == nil)
    }

    @Test func testThumbnailRequestStateCancellationBeforeQueueStartPreventsRequestExecution() {
        let state = FeaturePrintThumbnailRequestState()

        state.cancel()

        #expect(!state.beginRequest())
    }

    @Test func testThumbnailRequestStateTimeoutBeforeQueueStartPreventsRequestExecution() async throws {
        let state = FeaturePrintThumbnailRequestState()

        let thumbnail = try await withCheckedThrowingContinuation { continuation in
            #expect(state.install(continuation))
            state.timeout()
        } as ThumbnailCGImage?

        #expect(thumbnail == nil)
        #expect(!state.beginRequest())
    }
    #endif

    private func requireFeaturePrint(from cgImage: CGImage) async throws -> VNFeaturePrintObservation {
        try #require(await service.generateFeaturePrint(from: cgImage))
    }
}

/// The skip trait makes the same Vision request as `requireFeaturePrint`
/// before the test runs. An `NSOSStatusErrorDomain` error means Vision cannot
/// make feature prints here; any other result lets the test run and report it.
private func visionFeaturePrintIsAvailable() async -> Bool {
    guard let cgImage = makeSolidImage(red: 255, green: 0, blue: 0) else { return true }
    do {
        _ = try await VisionFeaturePrintService().generateFeaturePrint(from: cgImage)
        return true
    } catch {
        return (error as NSError).domain != NSOSStatusErrorDomain
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
