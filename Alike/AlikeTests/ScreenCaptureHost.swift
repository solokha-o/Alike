import SwiftUI
import Testing
import UIKit

/// Shows a SwiftUI screen in a real window of the test host and saves it as a PNG.
///
/// Package tests run without `UIApplication`, so a window there draws a blank image.
/// `AlikeTests` runs inside `Alike.app`, which has a window scene, so PhotoKit
/// thumbnails, materials and navigation bars draw as they do for a user.
///
/// `TEST_RUNNER_ALIKE_SCREENSHOT_DIR`, exported in the shell before `xcodebuild`,
/// names the output folder. The capture suite runs only when it is set.
/// The blank check catches an empty window, not a photo that loaded late.
@MainActor
final class ScreenCaptureHost {
    private let window: UIWindow

    init(@ViewBuilder content: () -> some View) throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "The test host has no window scene"
        )
        window = UIWindow(windowScene: scene)
        // The scene, not the screen: on iPad an iPhone-only app gets an iPhone-shaped window.
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        if Self.style == "dark" {
            window.overrideUserInterfaceStyle = .dark
        }
        window.rootViewController = UIHostingController(rootView: content())
        window.makeKeyAndVisible()
    }

    /// Turns the scene to landscape when `TEST_RUNNER_ALIKE_SCREENSHOT_ORIENTATION`
    /// is `landscape`. Call it before `init`, which sizes the window from the scene.
    /// It works only in a build that allows landscape: the native iPad audit build.
    static func prepareScene() async throws {
        guard orientation == "landscape",
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              !scene.interfaceOrientation.isLandscape
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        try await Task.sleep(for: .seconds(1))
        try #require(scene.interfaceOrientation.isLandscape, "The build does not allow landscape")
    }

    /// Lets `.task` loads, PhotoKit thumbnails and entry animations finish.
    func settle(for duration: Duration = .seconds(2)) async throws {
        try await Task.sleep(for: duration)
    }

    /// Draws the window once without keeping the image. The first draw starts
    /// PhotoKit loads that a later draw then shows.
    @discardableResult
    func draw() -> UIImage {
        let bounds = window.bounds
        return UIGraphicsImageRenderer(bounds: bounds).image { _ in
            _ = window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    /// Draws the window, checks it is not blank, and saves it when a folder is set.
    @discardableResult
    func capture(_ name: String) throws -> UIImage {
        let image = draw()
        #expect(Self.distinctColorCount(in: image) >= 4, "\(name) looks blank")
        if let folder = Self.outputFolder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try #require(image.pngData())
            try data.write(to: folder.appendingPathComponent("\(name).png"))
        }
        return image
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: - Output

    /// `<dir>/<device>/`, where `<device>` is `ipad-11`, `ipad-13` or `iphone`.
    nonisolated static var outputFolder: URL? {
        guard let path = ProcessInfo.processInfo.environment["ALIKE_SCREENSHOT_DIR"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).appendingPathComponent(folderName, isDirectory: true)
    }

    /// `ipad-11` for the baseline; `ipad-11-landscape-dark` when an orientation or
    /// a style is set.
    nonisolated static var folderName: String {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ALIKE_SCREENSHOT_ORIENTATION"] != nil || environment["ALIKE_SCREENSHOT_STYLE"] != nil
        else { return deviceSlug }
        return "\(deviceSlug)-\(orientation)-\(style)"
    }

    /// `portrait` (default) or `landscape`.
    nonisolated static var orientation: String {
        ProcessInfo.processInfo.environment["ALIKE_SCREENSHOT_ORIENTATION"] ?? "portrait"
    }

    /// `light` (default) or `dark`.
    nonisolated static var style: String {
        ProcessInfo.processInfo.environment["ALIKE_SCREENSHOT_STYLE"] ?? "light"
    }

    nonisolated static var deviceSlug: String {
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        if name.contains("(A16)") { return "ipad-a16" }
        if name.contains("Air 13-inch") { return "ipad-air-13" }
        if name.contains("13-inch") { return "ipad-13" }
        if name.contains("11-inch") { return "ipad-11" }
        return name.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone"
    }

    /// Distinct colours in a 24 x 24 thumbnail. A blank draw has 1 or 2.
    nonisolated static func distinctColorCount(in image: UIImage) -> Int {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let cgImage = image.cgImage,
              let context = CGContext(
                  data: &pixels,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var colors = Set<UInt32>()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            colors.insert(
                UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2])
            )
        }
        return colors.count
    }
}
