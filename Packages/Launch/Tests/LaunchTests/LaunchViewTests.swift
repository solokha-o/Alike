import XCTest
import SwiftUI
@testable import Launch

@MainActor
final class LaunchViewTests: XCTestCase {
    func testLaunchViewInitialization() {
        let view = LaunchView(isCompleted: .constant(false))
        XCTAssertNotNil(view)
    }
}
