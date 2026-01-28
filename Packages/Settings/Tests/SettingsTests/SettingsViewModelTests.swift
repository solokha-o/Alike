import XCTest
import Core
@testable import Settings

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testHandleRateTappedTriggersReview() {
        let viewModel = SettingsViewModel(gridConfig: .iPhone, appVersion: "1.2.3")
        var didCall = false

        XCTAssertEqual(viewModel.reviewTrigger, 0)
        viewModel.handleRateTapped(requestReview: {
            didCall = true
        })

        XCTAssertTrue(didCall)
        XCTAssertEqual(viewModel.reviewTrigger, 1)
    }

    func testRescanRequiredAfterSensitivityChangeIsTrue() {
        let viewModel = SettingsViewModel(gridConfig: .iPhone, appVersion: "1.2.3")
        XCTAssertTrue(viewModel.rescanRequiredAfterSensitivityChange())
    }

    func testInitUsesProvidedValues() {
        let viewModel = SettingsViewModel(gridConfig: .iPad, appVersion: "9.9.9")

        XCTAssertEqual(viewModel.gridConfig.defaultColumns, GridConfiguration.iPad.defaultColumns)
        XCTAssertEqual(viewModel.gridConfig.spacing, GridConfiguration.iPad.spacing)
        XCTAssertEqual(viewModel.appVersion, "9.9.9")
    }

    func testDefaultAppVersionIsNonEmpty() {
        let version = SettingsViewModel.defaultAppVersion()
        XCTAssertFalse(version.isEmpty)
    }
}
