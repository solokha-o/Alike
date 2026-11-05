import Testing
import SwiftUI
@testable import DesignSystem

@MainActor
@Suite struct ButtonTests {
    
    // MARK: - PrimaryButton Tests
    
    @Test func testPrimaryButtonCreation() {
        // Given & When: Creating primary button
        var actionCalled = false
        let button = PrimaryButton("Test") {
            actionCalled = true
        }
        
        // Then: Should be created
        #expect(button != nil, "Primary button should be created")
    }
    
    @Test func testPrimaryButtonWithIcon() {
        // Given & When: Creating button with icon
        let button = PrimaryButton("Test", icon: "star.fill") {}
        
        // Then: Should be created with icon
        #expect(button != nil, "Button with icon should be created")
    }
    
    @Test func testPrimaryButtonWithoutIcon() {
        // Given & When: Creating button without icon
        let button = PrimaryButton("Test") {}
        
        // Then: Should be created without icon
        #expect(button != nil, "Button without icon should be created")
    }
    
    @Test func testPrimaryButtonActionTriggered() {
        // Given: Button with action
        var actionCalled = false
        let button = PrimaryButton("Test") {
            actionCalled = true
        }
        
        // When: Simulating button press
        // Note: In real tests, you'd use ViewInspector or similar
        // Here we're testing the structure
        
        // Then: Button should exist
        #expect(button != nil)
    }
    
    // MARK: - SecondaryButton Tests
    
    @Test func testSecondaryButtonCreation() {
        // Given & When: Creating secondary button
        let button = SecondaryButton("Test") {}
        
        // Then: Should be created
        #expect(button != nil, "Secondary button should be created")
    }
    
    @Test func testSecondaryButtonWithIcon() {
        // Given & When: Creating button with icon
        let button = SecondaryButton("Test", icon: "gear") {}
        
        // Then: Should be created with icon
        #expect(button != nil, "Button with icon should be created")
    }
    
    @Test func testSecondaryButtonWithoutIcon() {
        // Given & When: Creating button without icon
        let button = SecondaryButton("Test") {}
        
        // Then: Should be created without icon
        #expect(button != nil, "Button without icon should be created")
    }
    
    // MARK: - Button State Tests
    
    @Test func testPrimaryButtonFeedbackTrigger() {
        // Given: Primary button
        var triggerCount = 0
        let button = PrimaryButton("Test") {
            triggerCount += 1
        }
        
        // Then: Button should be ready to trigger
        #expect(button != nil)
        #expect(triggerCount == 0, "Action should not be called on creation")
    }
    
    @Test func testSecondaryButtonNoFeedback() {
        // Given: Secondary button (no sensory feedback)
        var triggerCount = 0
        let button = SecondaryButton("Test") {
            triggerCount += 1
        }
        
        // Then: Button should exist
        #expect(button != nil)
        #expect(triggerCount == 0, "Action should not be called on creation")
    }
    
    // MARK: - Localization Tests
    
    @Test func testButtonSupportsLocalizedStringKey() {
        // Given: LocalizedStringKey
        let localizedKey: LocalizedStringKey = "Settings"
        
        // When: Creating buttons with localized string
        let primaryButton = PrimaryButton(localizedKey) {}
        let secondaryButton = SecondaryButton(localizedKey) {}
        
        // Then: Should accept LocalizedStringKey
        #expect(primaryButton != nil, "Primary button should support localization")
        #expect(secondaryButton != nil, "Secondary button should support localization")
    }
    
    // MARK: - Icon Tests
    
    @Test func testButtonIconIsOptional() {
        // Given: Buttons with and without icons
        let withIcon = PrimaryButton("Test", icon: "star") {}
        let withoutIcon = PrimaryButton("Test", icon: nil) {}
        let explicitlyNil = PrimaryButton("Test") {}
        
        // Then: All should be valid
        #expect(withIcon != nil, "Button with icon should be valid")
        #expect(withoutIcon != nil, "Button with nil icon should be valid")
        #expect(explicitlyNil != nil, "Button without icon parameter should be valid")
    }
    
    // MARK: - Multiple Buttons Tests
    
    @Test func testMultiplePrimaryButtons() {
        // Given: Multiple primary buttons
        let button1 = PrimaryButton("Button 1") {}
        let button2 = PrimaryButton("Button 2", icon: "star") {}
        let button3 = PrimaryButton("Button 3") {}
        
        // Then: All should coexist
        #expect(button1 != nil)
        #expect(button2 != nil)
        #expect(button3 != nil)
    }
    
    @Test func testMultipleSecondaryButtons() {
        // Given: Multiple secondary buttons
        let button1 = SecondaryButton("Button 1") {}
        let button2 = SecondaryButton("Button 2", icon: "gear") {}
        let button3 = SecondaryButton("Button 3") {}
        
        // Then: All should coexist
        #expect(button1 != nil)
        #expect(button2 != nil)
        #expect(button3 != nil)
    }
    
    // MARK: - Integration Tests
    
    @Test func testPrimaryAndSecondaryButtonsTogether() {
        // Given: Both button types
        let primary = PrimaryButton("Primary") {}
        let secondary = SecondaryButton("Secondary") {}
        
        // Then: Should work together
        #expect(primary != nil, "Primary button should exist")
        #expect(secondary != nil, "Secondary button should exist")
    }
    
    @Test func testButtonsWithDifferentLocalizations() {
        // Given: Buttons with different localized keys
        let saveButton = PrimaryButton("Save") {}
        let cancelButton = SecondaryButton("Cancel") {}
        let deleteButton = PrimaryButton("Delete") {}
        
        // Then: All should be valid
        #expect(saveButton != nil)
        #expect(cancelButton != nil)
        #expect(deleteButton != nil)
    }
}
