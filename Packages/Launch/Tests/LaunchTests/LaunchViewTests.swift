import Testing
import SwiftUI
@testable import Launch

@MainActor
struct LaunchViewTests {
    @Test func testLaunchViewInitialization() {
        let view = LaunchView(isCompleted: .constant(false))
        #expect((view as LaunchView?) != nil)
    }
}
