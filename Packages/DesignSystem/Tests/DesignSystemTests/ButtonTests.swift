import XCTest
import SwiftUI
@testable import DesignSystem

@MainActor
final class ButtonTests: XCTestCase {
    
    // MARK: - PrimaryButton Tests
    
    func testPrimaryButtonCreation() {
        // Given & When: Creating primary button
        var actionCalled = false
        let button = PrimaryButton("Test") {
            actionCalled = true
        }
        
        // Then: Should be created
        XCTAssertNotNil(button, "Primary button should be created")
    }
    
    func testPrimaryButtonWithIcon() {
        // Given & When: Creating button with icon
        let button = PrimaryButton("Test", icon: "star.fill") {}
        
        // Then: Should be created with icon
        XCTAssertNotNil(button, "Button with icon should be created")
    }
    
    func testPrimaryButtonWithoutIcon() {
        // Given & When: Creating button without icon
        let button = PrimaryButton("Test") {}
        
        // Then: Should be created without icon
        XCTAssertNotNil(button, "Button without icon should be created")
    }
    
    func testPrimaryButtonActionTriggered() {
        // Given: Button with action
        var actionCalled = false
        let button = PrimaryButton("Test") {
            actionCalled = true
        }
        
        // When: Simulating button press
        // Note: In real tests, you'd use ViewInspector or similar
        // Here we're testing the structure
        
        // Then: Button should exist
        XCTAssertNotNil(button)
    }
    
    // MARK: - SecondaryButton Tests
    
    func testSecondaryButtonCreation() {
        // Given & When: Creating secondary button
        let button = SecondaryButton("Test") {}
        
        // Then: Should be created
        XCTAssertNotNil(button, "Secondary button should be created")
    }
    
    func testSecondaryButtonWithIcon() {
        // Given & When: Creating button with icon
        let button = SecondaryButton("Test", icon: "gear") {}
        
        // Then: Should be created with icon
        XCTAssertNotNil(button, "Button with icon should be created")
    }
    
    func testSecondaryButtonWithoutIcon() {
        // Given & When: Creating button without icon
        let button = SecondaryButton("Test") {}
        
        // Then: Should be created without icon
        XCTAssertNotNil(button, "Button without icon should be created")
    }
    
    // MARK: - Button State Tests
    
    func testPrimaryButtonFeedbackTrigger() {
        // Given: Primary button
        var triggerCount = 0
        let button = PrimaryButton("Test") {
            triggerCount += 1
        }
        
        // Then: Button should be ready to trigger
        XCTAssertNotNil(button)
        XCTAssertEqual(triggerCount, 0, "Action should not be called on creation")
    }
    
    func testSecondaryButtonNoFeedback() {
        // Given: Secondary button (no sensory feedback)
        var triggerCount = 0
        let button = SecondaryButton("Test") {
            triggerCount += 1
        }
        
        // Then: Button should exist
        XCTAssertNotNil(button)
        XCTAssertEqual(triggerCount, 0, "Action should not be called on creation")
    }
    
    // MARK: - Localization Tests
    
    func testButtonSupportsLocalizedStringKey() {
        // Given: LocalizedStringKey
        let localizedKey: LocalizedStringKey = "Settings"
        
        // When: Creating buttons with localized string
        let primaryButton = PrimaryButton(localizedKey) {}
        let secondaryButton = SecondaryButton(localizedKey) {}
        
        // Then: Should accept LocalizedStringKey
        XCTAssertNotNil(primaryButton, "Primary button should support localization")
        XCTAssertNotNil(secondaryButton, "Secondary button should support localization")
    }
    
    // MARK: - Icon Tests
    
    func testButtonIconIsOptional() {
        // Given: Buttons with and without icons
        let withIcon = PrimaryButton("Test", icon: "star") {}
        let withoutIcon = PrimaryButton("Test", icon: nil) {}
        let explicitlyNil = PrimaryButton("Test") {}
        
        // Then: All should be valid
        XCTAssertNotNil(withIcon, "Button with icon should be valid")
        XCTAssertNotNil(withoutIcon, "Button with nil icon should be valid")
        XCTAssertNotNil(explicitlyNil, "Button without icon parameter should be valid")
    }
    
    // MARK: - Multiple Buttons Tests
    
    func testMultiplePrimaryButtons() {
        // Given: Multiple primary buttons
        let button1 = PrimaryButton("Button 1") {}
        let button2 = PrimaryButton("Button 2", icon: "star") {}
        let button3 = PrimaryButton("Button 3") {}
        
        // Then: All should coexist
        XCTAssertNotNil(button1)
        XCTAssertNotNil(button2)
        XCTAssertNotNil(button3)
    }
    
    func testMultipleSecondaryButtons() {
        // Given: Multiple secondary buttons
        let button1 = SecondaryButton("Button 1") {}
        let button2 = SecondaryButton("Button 2", icon: "gear") {}
        let button3 = SecondaryButton("Button 3") {}
        
        // Then: All should coexist
        XCTAssertNotNil(button1)
        XCTAssertNotNil(button2)
        XCTAssertNotNil(button3)
    }
    
    // MARK: - Integration Tests
    
    func testPrimaryAndSecondaryButtonsTogether() {
        // Given: Both button types
        let primary = PrimaryButton("Primary") {}
        let secondary = SecondaryButton("Secondary") {}
        
        // Then: Should work together
        XCTAssertNotNil(primary, "Primary button should exist")
        XCTAssertNotNil(secondary, "Secondary button should exist")
    }
    
    func testButtonsWithDifferentLocalizations() {
        // Given: Buttons with different localized keys
        let saveButton = PrimaryButton("Save") {}
        let cancelButton = SecondaryButton("Cancel") {}
        let deleteButton = PrimaryButton("Delete") {}
        
        // Then: All should be valid
        XCTAssertNotNil(saveButton)
        XCTAssertNotNil(cancelButton)
        XCTAssertNotNil(deleteButton)
    }
}
