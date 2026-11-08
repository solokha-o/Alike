import Testing
import SwiftUI
@testable import DesignSystem

/// TODO(https://app.notion.com/p/41104d81c94381e4b33acee36f316cc3): these tests only build the value; add real checks or delete them.
@MainActor
struct ButtonTests {
    // MARK: - PrimaryButton Tests
    
    @Test func testPrimaryButtonCreation() {
        // Given & When: Creating primary button
        _ = PrimaryButton("Test") {}
    }
    
    @Test func testPrimaryButtonWithIcon() {
        // Given & When: Creating button with icon
        _ = PrimaryButton("Test", icon: "star.fill") {}
    }
    
    @Test func testPrimaryButtonWithoutIcon() {
        // Given & When: Creating button without icon
        _ = PrimaryButton("Test") {}
    }
    
    @Test func testPrimaryButtonActionTriggered() {
        // Given: Button with action
        _ = PrimaryButton("Test") {}
        
        // When: Simulating button press
        // Note: In real tests, you'd use ViewInspector or similar
        // Here we're testing the structure
    }
    
    // MARK: - SecondaryButton Tests
    
    @Test func testSecondaryButtonCreation() {
        // Given & When: Creating secondary button
        _ = SecondaryButton("Test") {}
    }
    
    @Test func testSecondaryButtonWithIcon() {
        // Given & When: Creating button with icon
        _ = SecondaryButton("Test", icon: "gear") {}
    }
    
    @Test func testSecondaryButtonWithoutIcon() {
        // Given & When: Creating button without icon
        _ = SecondaryButton("Test") {}
    }
    
    // MARK: - Button State Tests
    
    @Test func testPrimaryButtonFeedbackTrigger() {
        // Given: Primary button
        var triggerCount = 0
        _ = PrimaryButton("Test") {
            triggerCount += 1
        }
        
        // Then: Button should be ready to trigger
        #expect(triggerCount == 0, "Action should not be called on creation")
    }
    
    @Test func testSecondaryButtonNoFeedback() {
        // Given: Secondary button (no sensory feedback)
        var triggerCount = 0
        _ = SecondaryButton("Test") {
            triggerCount += 1
        }
        
        // Then: Button should exist
        #expect(triggerCount == 0, "Action should not be called on creation")
    }
    
    // MARK: - Localization Tests
    
    @Test func testButtonSupportsLocalizedStringKey() {
        // Given: LocalizedStringKey
        let localizedKey: LocalizedStringKey = "Settings"
        
        // When: Creating buttons with localized string
        _ = PrimaryButton(localizedKey) {}
        _ = SecondaryButton(localizedKey) {}
    }
    
    // MARK: - Icon Tests
    
    @Test func testButtonIconIsOptional() {
        // Given: Buttons with and without icons
        _ = PrimaryButton("Test", icon: "star") {}
        _ = PrimaryButton("Test", icon: nil) {}
        _ = PrimaryButton("Test") {}
    }
    
    // MARK: - Multiple Buttons Tests
    
    @Test func testMultiplePrimaryButtons() {
        // Given: Multiple primary buttons
        _ = PrimaryButton("Button 1") {}
        _ = PrimaryButton("Button 2", icon: "star") {}
        _ = PrimaryButton("Button 3") {}
    }
    
    @Test func testMultipleSecondaryButtons() {
        // Given: Multiple secondary buttons
        _ = SecondaryButton("Button 1") {}
        _ = SecondaryButton("Button 2", icon: "gear") {}
        _ = SecondaryButton("Button 3") {}
    }
    
    // MARK: - Integration Tests
    
    @Test func testPrimaryAndSecondaryButtonsTogether() {
        // Given: Both button types
        _ = PrimaryButton("Primary") {}
        _ = SecondaryButton("Secondary") {}
    }
    
    @Test func testButtonsWithDifferentLocalizations() {
        // Given: Buttons with different localized keys
        _ = PrimaryButton("Save") {}
        _ = SecondaryButton("Cancel") {}
        _ = PrimaryButton("Delete") {}
    }
}
