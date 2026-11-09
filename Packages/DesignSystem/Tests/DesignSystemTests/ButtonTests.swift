import SwiftUI
import Testing
@testable import DesignSystem

@MainActor
struct ButtonTests {
    // MARK: - PrimaryButton

    @Test func testPrimaryButtonWithIcon() {
        let button = PrimaryButton("Test", icon: "star.fill") {}

        #expect(button.icon == "star.fill")
    }

    @Test func testPrimaryButtonWithoutIcon() {
        #expect(PrimaryButton("Test") {}.icon == nil)
        #expect(PrimaryButton("Test", icon: nil) {}.icon == nil)
    }

    /// Checks that init stores the action. A tap needs a UI test; a package unit test cannot press the button.
    @Test func testPrimaryButtonStoresAction() {
        var triggerCount = 0
        let button = PrimaryButton("Test") { triggerCount += 1 }
        #expect(triggerCount == 0, "Action should not be called on creation")

        button.action()

        #expect(triggerCount == 1)
    }

    // MARK: - SecondaryButton

    @Test func testSecondaryButtonWithIcon() {
        let button = SecondaryButton("Test", icon: "gear") {}

        #expect(button.icon == "gear")
    }

    @Test func testSecondaryButtonWithoutIcon() {
        #expect(SecondaryButton("Test") {}.icon == nil)
        #expect(SecondaryButton("Test", icon: nil) {}.icon == nil)
    }

    /// Checks that init stores the action. A tap needs a UI test; a package unit test cannot press the button.
    @Test func testSecondaryButtonStoresAction() {
        var triggerCount = 0
        let button = SecondaryButton("Test") { triggerCount += 1 }
        #expect(triggerCount == 0, "Action should not be called on creation")

        button.action()

        #expect(triggerCount == 1)
    }

    // MARK: - Titles

    @Test func testStringTitleIsVerbatim() {
        #expect(PrimaryButton("Settings") {}.title == Text(verbatim: "Settings"))
        #expect(SecondaryButton("Settings") {}.title == Text(verbatim: "Settings"))
    }

    @Test func testLocalizedStringKeyTitleIsLocalized() {
        let localizedKey: LocalizedStringKey = "Settings"

        #expect(PrimaryButton(localizedKey) {}.title == Text(localizedKey))
        #expect(SecondaryButton(localizedKey) {}.title == Text(localizedKey))
        #expect(PrimaryButton(localizedKey) {}.title != Text(verbatim: "Settings"))
    }
}
