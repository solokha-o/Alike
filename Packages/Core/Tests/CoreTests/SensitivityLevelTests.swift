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
    
    /// `displayName` used to return English literals, which is what the Settings picker showed in
    /// every language — found rendering as "Medium" in a Polish build during the task 43 walk. It
    /// now resolves through the catalog, so the assertion is against a bundle compiled from the
    /// shipped catalog rather than against the literal (`swift test` alone would return the key —
    /// see `CompiledCatalogFixture`).
    func testDisplayNamesResolveFromTheCatalog() throws {
        let en = try CompiledCatalogFixture.bundle(language: "en")
        let english = Locale(identifier: "en")

        XCTAssertEqual(SensitivityLevel.low.displayName(bundle: en, locale: english), "Low")
        XCTAssertEqual(SensitivityLevel.medium.displayName(bundle: en, locale: english), "Medium")
        XCTAssertEqual(SensitivityLevel.high.displayName(bundle: en, locale: english), "High")
    }

    func testDisplayNamesAreTranslated() throws {
        let pl = try CompiledCatalogFixture.bundle(language: "pl")
        let polish = Locale(identifier: "pl")

        XCTAssertEqual(SensitivityLevel.low.displayName(bundle: pl, locale: polish), "Niska")
        XCTAssertEqual(SensitivityLevel.medium.displayName(bundle: pl, locale: polish), "Średnia")
        XCTAssertEqual(SensitivityLevel.high.displayName(bundle: pl, locale: polish), "Wysoka")
    }

    /// Every level has to reach a catalog key. A level added later without one would fall back to
    /// its key, which is what this catches.
    func testEveryLevelHasACatalogKey() throws {
        let catalog = try LocalizationCatalog.load()

        for level in SensitivityLevel.allCases {
            let key = "core.sensitivityLevel.\(level.rawValue)"
            XCTAssertNotNil(catalog.strings[key], "no catalog key for \(level.rawValue)")
            for language in LocalizationCatalog.shippedLanguages {
                XCTAssertNotNil(
                    try catalog.localizations(of: key)[language],
                    "\(key) is missing \(language)"
                )
            }
        }
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
