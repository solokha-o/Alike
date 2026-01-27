import XCTest
@testable import Core

final class SensitivityLevelTests: XCTestCase {
    
    // MARK: - Enum Cases Tests
    
    func testAllCasesCount() {
        // Given & When: All sensitivity levels
        let allCases = SensitivityLevel.allCases
        
        // Then: Should have exactly 3 levels
        XCTAssertEqual(allCases.count, 3, "Should have 3 sensitivity levels")
    }
    
    func testAllCasesContainsExpectedValues() {
        // Given & When: All sensitivity levels
        let allCases = SensitivityLevel.allCases
        
        // Then: Should contain low, medium, high
        XCTAssertTrue(allCases.contains(.low), "Should contain low")
        XCTAssertTrue(allCases.contains(.medium), "Should contain medium")
        XCTAssertTrue(allCases.contains(.high), "Should contain high")
    }
    
    // MARK: - Threshold Tests
    
    func testLowSensitivityThreshold() {
        // Given: Low sensitivity
        let level = SensitivityLevel.low
        
        // When: Getting threshold
        let threshold = level.threshold
        
        // Then: Should be 0.8
        XCTAssertEqual(threshold, 0.8, accuracy: 0.001, "Low sensitivity threshold should be 0.8")
    }
    
    func testMediumSensitivityThreshold() {
        // Given: Medium sensitivity
        let level = SensitivityLevel.medium
        
        // When: Getting threshold
        let threshold = level.threshold
        
        // Then: Should be 0.9
        XCTAssertEqual(threshold, 0.9, accuracy: 0.001, "Medium sensitivity threshold should be 0.9")
    }
    
    func testHighSensitivityThreshold() {
        // Given: High sensitivity
        let level = SensitivityLevel.high
        
        // When: Getting threshold
        let threshold = level.threshold
        
        // Then: Should be 0.95
        XCTAssertEqual(threshold, 0.95, accuracy: 0.001, "High sensitivity threshold should be 0.95")
    }
    
    func testThresholdsAreOrdered() {
        // Given: All sensitivity levels
        let low = SensitivityLevel.low
        let medium = SensitivityLevel.medium
        let high = SensitivityLevel.high
        
        // When: Comparing thresholds
        // Then: Should be in ascending order
        XCTAssertLessThan(low.threshold, medium.threshold, "Low < Medium")
        XCTAssertLessThan(medium.threshold, high.threshold, "Medium < High")
        XCTAssertLessThan(low.threshold, high.threshold, "Low < High")
    }
    
    // MARK: - Display Name Tests
    
    func testLowDisplayName() {
        // Given: Low sensitivity
        let level = SensitivityLevel.low
        
        // When: Getting display name
        let displayName = level.displayName
        
        // Then: Should be "Low"
        XCTAssertEqual(displayName, "Low", "Low level display name should be 'Low'")
    }
    
    func testMediumDisplayName() {
        // Given: Medium sensitivity
        let level = SensitivityLevel.medium
        
        // When: Getting display name
        let displayName = level.displayName
        
        // Then: Should be "Medium"
        XCTAssertEqual(displayName, "Medium", "Medium level display name should be 'Medium'")
    }
    
    func testHighDisplayName() {
        // Given: High sensitivity
        let level = SensitivityLevel.high
        
        // When: Getting display name
        let displayName = level.displayName
        
        // Then: Should be "High"
        XCTAssertEqual(displayName, "High", "High level display name should be 'High'")
    }
    
    // MARK: - Raw Value Tests
    
    func testRawValues() {
        // Given: All sensitivity levels
        let low = SensitivityLevel.low
        let medium = SensitivityLevel.medium
        let high = SensitivityLevel.high
        
        // Then: Raw values should be unique and valid
        XCTAssertEqual(low.rawValue, "low")
        XCTAssertEqual(medium.rawValue, "medium")
        XCTAssertEqual(high.rawValue, "high")
    }
    
    func testInitFromRawValue() {
        // Given: Raw value strings
        // When: Creating from raw values
        let low = SensitivityLevel(rawValue: "low")
        let medium = SensitivityLevel(rawValue: "medium")
        let high = SensitivityLevel(rawValue: "high")
        let invalid = SensitivityLevel(rawValue: "invalid")
        
        // Then: Should create correct instances
        XCTAssertEqual(low, .low)
        XCTAssertEqual(medium, .medium)
        XCTAssertEqual(high, .high)
        XCTAssertNil(invalid, "Invalid raw value should return nil")
    }
    
    // MARK: - Sendable Conformance Tests
    
    func testSendableConformance() async {
        // Given: Sensitivity level
        let level = SensitivityLevel.medium
        
        // When: Using in async context
        let result = await Task {
            level.threshold
        }.value
        
        // Then: Should work correctly (Sendable conformance)
        XCTAssertEqual(result, 0.9, accuracy: 0.001)
    }
    
    // MARK: - Comparison Tests
    
    func testEqualityComparison() {
        // Given: Same sensitivity levels
        let level1 = SensitivityLevel.medium
        let level2 = SensitivityLevel.medium
        let level3 = SensitivityLevel.high
        
        // Then: Should compare correctly
        XCTAssertEqual(level1, level2, "Same levels should be equal")
        XCTAssertNotEqual(level1, level3, "Different levels should not be equal")
    }
    
    // MARK: - Default Value Tests
    
    func testMediumIsReasonableDefault() {
        // Given: Medium sensitivity as default
        let defaultLevel = SensitivityLevel.medium
        
        // Then: Threshold should balance between too strict and too lenient
        XCTAssertGreaterThan(defaultLevel.threshold, 0.85, "Should be strict enough")
        XCTAssertLessThan(defaultLevel.threshold, 0.95, "Should not be too strict")
    }
}
