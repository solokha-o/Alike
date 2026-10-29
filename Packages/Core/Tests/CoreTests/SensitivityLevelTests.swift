import Foundation
import Testing
@testable import Core

@Suite struct SensitivityLevelTests {
    
    // MARK: - Enum Cases Tests
    
    @Test func testAllCasesCount() {
        // Given & When: All sensitivity levels
        let allCases = SensitivityLevel.allCases
        
        // Then: Should have exactly 3 levels
        #expect(allCases.count == 3, "Should have 3 sensitivity levels")
    }
    
    @Test func testAllCasesContainsExpectedValues() {
        // Given & When: All sensitivity levels
        let allCases = SensitivityLevel.allCases
        
        // Then: Should contain low, medium, high
        #expect(allCases.contains(.low), "Should contain low")
        #expect(allCases.contains(.medium), "Should contain medium")
        #expect(allCases.contains(.high), "Should contain high")
    }
    
    // MARK: - Threshold Tests
    
    @Test func testLowSensitivityThreshold() {
        // Given: Low sensitivity
        let level = SensitivityLevel.low
        
        // When: Getting threshold
        let threshold = level.threshold
        
        // Then: Should be 0.8
        let eps: Float = 0.001
        #expect(abs(threshold - 0.8) <= eps, "Low sensitivity threshold should be 0.8")
    }
    
    @Test func testMediumSensitivityThreshold() {
        // Given: Medium sensitivity
        let level = SensitivityLevel.medium
        
        // When: Getting threshold
        let threshold = level.threshold
        
        // Then: Should be 0.9
        let eps: Float = 0.001
        #expect(abs(threshold - 0.9) <= eps, "Medium sensitivity threshold should be 0.9")
    }
    
    @Test func testHighSensitivityThreshold() {
        // Given: High sensitivity
        let level = SensitivityLevel.high
        
        // When: Getting threshold
        let threshold = level.threshold
        
        // Then: Should be 0.95
        let eps: Float = 0.001
        #expect(abs(threshold - 0.95) <= eps, "High sensitivity threshold should be 0.95")
    }
    
    @Test func testThresholdsAreOrdered() {
        // Given: All sensitivity levels
        let low = SensitivityLevel.low
        let medium = SensitivityLevel.medium
        let high = SensitivityLevel.high
        
        // When: Comparing thresholds
        // Then: Should be in ascending order
        #expect(low.threshold < medium.threshold, "Low < Medium")
        #expect(medium.threshold < high.threshold, "Medium < High")
        #expect(low.threshold < high.threshold, "Low < High")
    }
    
    // MARK: - Display Name Tests
    
    /// `displayName` used to return English literals, which is what the Settings picker showed in
    /// every language — found rendering as "Medium" in a Polish build during the task 43 walk. It
    /// now resolves through the catalog, so the assertion is against a bundle compiled from the
    /// shipped catalog rather than against the literal (`swift test` alone would return the key —
    /// see `CompiledCatalogFixture`).
    @Test func testDisplayNamesResolveFromTheCatalog() throws {
        let en = try CompiledCatalogFixture.bundle(language: "en")
        let english = Locale(identifier: "en")

        #expect(SensitivityLevel.low.displayName(bundle: en, locale: english) == "Low")
        #expect(SensitivityLevel.medium.displayName(bundle: en, locale: english) == "Medium")
        #expect(SensitivityLevel.high.displayName(bundle: en, locale: english) == "High")
    }

    @Test func testDisplayNamesAreTranslated() throws {
        let pl = try CompiledCatalogFixture.bundle(language: "pl")
        let polish = Locale(identifier: "pl")

        #expect(SensitivityLevel.low.displayName(bundle: pl, locale: polish) == "Niska")
        #expect(SensitivityLevel.medium.displayName(bundle: pl, locale: polish) == "Średnia")
        #expect(SensitivityLevel.high.displayName(bundle: pl, locale: polish) == "Wysoka")
    }

    /// Every level has to reach a catalog key. A level added later without one would fall back to
    /// its key, which is what this catches.
    @Test func testEveryLevelHasACatalogKey() throws {
        let catalog = try LocalizationCatalog.load()

        for level in SensitivityLevel.allCases {
            let key = "core.sensitivityLevel.\(level.rawValue)"
            #expect(catalog.strings[key] != nil, "no catalog key for \(level.rawValue)")
            for language in LocalizationCatalog.shippedLanguages {
                #expect(
                    try catalog.localizations(of: key)[language] != nil,
                    "\(key) is missing \(language)"
                )
            }
        }
    }

    // MARK: - Raw Value Tests
    
    @Test func testRawValues() {
        // Given: All sensitivity levels
        let low = SensitivityLevel.low
        let medium = SensitivityLevel.medium
        let high = SensitivityLevel.high
        
        // Then: Raw values should be unique and valid
        #expect(low.rawValue == "low")
        #expect(medium.rawValue == "medium")
        #expect(high.rawValue == "high")
    }
    
    @Test func testInitFromRawValue() {
        // Given: Raw value strings
        // When: Creating from raw values
        let low = SensitivityLevel(rawValue: "low")
        let medium = SensitivityLevel(rawValue: "medium")
        let high = SensitivityLevel(rawValue: "high")
        let invalid = SensitivityLevel(rawValue: "invalid")
        
        // Then: Should create correct instances
        #expect(low == .low)
        #expect(medium == .medium)
        #expect(high == .high)
        #expect(invalid == nil, "Invalid raw value should return nil")
    }
    
    // MARK: - Sendable Conformance Tests
    
    @Test func testSendableConformance() async {
        // Given: Sensitivity level
        let level = SensitivityLevel.medium
        
        // When: Using in async context
        let result = await Task {
            level.threshold
        }.value
        
        // Then: Should work correctly (Sendable conformance)
        let eps: Float = 0.001
        #expect(abs(result - 0.9) <= eps)
    }
    
    // MARK: - Comparison Tests
    
    @Test func testEqualityComparison() {
        // Given: Same sensitivity levels
        let level1 = SensitivityLevel.medium
        let level2 = SensitivityLevel.medium
        let level3 = SensitivityLevel.high
        
        // Then: Should compare correctly
        #expect(level1 == level2, "Same levels should be equal")
        #expect(level1 != level3, "Different levels should not be equal")
    }
    
    // MARK: - Default Value Tests
    
    @Test func testMediumIsReasonableDefault() {
        // Given: Medium sensitivity as default
        let defaultLevel = SensitivityLevel.medium
        
        // Then: Threshold should balance between too strict and too lenient
        #expect(defaultLevel.threshold > 0.85, "Should be strict enough")
        #expect(defaultLevel.threshold < 0.95, "Should not be too strict")
    }
}
