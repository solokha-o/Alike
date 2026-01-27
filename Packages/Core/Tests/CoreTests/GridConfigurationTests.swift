import XCTest
@testable import Core

final class GridConfigurationTests: XCTestCase {
    
    // MARK: - Current Configuration Tests
    
    func testCurrentConfigurationExists() {
        // Given & When: Getting current configuration
        let config = GridConfiguration.current
        
        // Then: Should not be nil and have valid values
        XCTAssertNotNil(config, "Current configuration should exist")
        XCTAssertGreaterThan(config.minColumns, 0, "Min columns should be positive")
        XCTAssertGreaterThan(config.maxColumns, 0, "Max columns should be positive")
        XCTAssertGreaterThan(config.defaultColumns, 0, "Default columns should be positive")
    }
    
    // MARK: - Column Range Tests
    
    func testMinColumnsValue() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // When: Getting min columns
        let minColumns = config.minColumns
        
        // Then: Should be 2 (reasonable minimum for grid)
        XCTAssertEqual(minColumns, 2, "Minimum columns should be 2")
    }
    
    func testMaxColumnsValue() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // When: Getting max columns
        let maxColumns = config.maxColumns
        
        // Then: Should be 6 (reasonable maximum for mobile)
        XCTAssertEqual(maxColumns, 6, "Maximum columns should be 6")
    }
    
    func testDefaultColumnsValue() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // When: Getting default columns
        let defaultColumns = config.defaultColumns
        
        // Then: Should be 3 (good balance)
        XCTAssertEqual(defaultColumns, 3, "Default columns should be 3")
    }
    
    func testColumnRangeIsValid() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // Then: Min should be less than or equal to default, default less than or equal to max
        XCTAssertLessThanOrEqual(config.minColumns, config.defaultColumns, "Min <= Default")
        XCTAssertLessThanOrEqual(config.defaultColumns, config.maxColumns, "Default <= Max")
        XCTAssertLessThanOrEqual(config.minColumns, config.maxColumns, "Min <= Max")
    }
    
    // MARK: - Practical Usage Tests
    
    func testDefaultColumnsIsInRange() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // Then: Default should be within allowed range
        XCTAssertTrue(
            (config.minColumns...config.maxColumns).contains(config.defaultColumns),
            "Default columns should be within min-max range"
        )
    }
    
    func testMinimumColumnCountIsUsable() {
        // Given: Minimum columns
        let minColumns = GridConfiguration.current.minColumns
        
        // Then: Should allow at least 2 columns (for comparison)
        XCTAssertGreaterThanOrEqual(minColumns, 2, "Should allow at least 2 columns for grid layout")
    }
    
    func testMaximumColumnCountIsReasonable() {
        // Given: Maximum columns
        let maxColumns = GridConfiguration.current.maxColumns
        
        // Then: Should not exceed 8 (practical limit on mobile)
        XCTAssertLessThanOrEqual(maxColumns, 8, "Maximum columns should be reasonable for mobile screens")
    }
    
    // MARK: - Sendable Conformance Tests
    
    func testSendableConformance() async {
        // Given: Grid configuration
        let config = GridConfiguration.current
        
        // When: Using in async context
        let result = await Task {
            config.defaultColumns
        }.value
        
        // Then: Should work correctly (Sendable conformance)
        XCTAssertEqual(result, 3)
    }
    
    // MARK: - Spacing Tests
    
    func testSpacingValue() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // When: Getting spacing
        let spacing = config.spacing
        
        // Then: Should be 2 (tight but visible gap)
        XCTAssertEqual(spacing, 2.0, "Spacing should be 2.0")
        XCTAssertGreaterThan(spacing, 0, "Spacing should be positive")
    }
    
    func testSpacingIsReasonable() {
        // Given: Configuration spacing
        let spacing = GridConfiguration.current.spacing
        
        // Then: Should be small but visible (between 1 and 8 points)
        XCTAssertTrue((1.0...8.0).contains(spacing), "Spacing should be reasonable for photo grid")
    }
    
    // MARK: - Integration Tests
    
    func testConfigurationValuesAreConsistent() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // Then: All values should be consistent with each other
        XCTAssertTrue(config.minColumns > 0, "Min columns positive")
        XCTAssertTrue(config.maxColumns > config.minColumns, "Max > Min")
        XCTAssertTrue(config.defaultColumns >= config.minColumns, "Default >= Min")
        XCTAssertTrue(config.defaultColumns <= config.maxColumns, "Default <= Max")
        XCTAssertTrue(config.spacing >= 0, "Spacing non-negative")
    }
    
    func testConfigurationSuitableForPhotoGrid() {
        // Given: Current configuration
        let config = GridConfiguration.current
        
        // Then: Values should be suitable for photo grid layout
        // 2-6 columns is good range for mobile photo grid
        XCTAssertTrue(config.minColumns >= 2, "At least 2 columns for comparison")
        XCTAssertTrue(config.maxColumns <= 6, "Not too many columns on mobile")
        
        // Default 3 is standard for photo apps
        XCTAssertEqual(config.defaultColumns, 3, "Standard photo grid is 3 columns")
        
        // Tight spacing for photo grid
        XCTAssertLessThanOrEqual(config.spacing, 4.0, "Photo grids use tight spacing")
    }
}
