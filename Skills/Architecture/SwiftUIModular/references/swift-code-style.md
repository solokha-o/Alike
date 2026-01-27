# Swift Code Style Guide

## Intent

Provide consistent Swift code formatting and style conventions based on [Google Swift Style Guide](https://google.github.io/swift/). These rules ensure readability, maintainability, and consistency across the codebase.

## Core Principles

1. **Clarity over brevity** — Code should be self-explanatory
2. **Consistency** — Follow established patterns throughout the project
3. **Readability** — Optimize for human understanding, not character count
4. **Type safety** — Leverage Swift's type system to prevent errors

## File Organization

### File Naming

- Swift files end with `.swift`
- Primary type name: `MyType.swift`
- Protocol conformance: `MyType+MyProtocol.swift`
- Multiple extensions: `MyType+Additions.swift`

### Import Statements

Group imports in this order (lexicographically within each group):

1. Module/submodule imports
2. Individual declarations (`class`, `enum`, `func`, `struct`, `var`)
3. `@testable` imports (test files only)

```swift
import CoreLocation
import UIKit

import func Darwin.C.isatty

@testable import MyModuleUnderTest
```

### Source File Structure

```swift
// Optional file-level comment (only if multiple abstractions)

import statements

// MARK: - Main Type

struct MainType {
    // MARK: - Properties
    
    // MARK: - Initialization
    
    // MARK: - Public API
}

// MARK: - Protocol Conformance

extension MainType: SomeProtocol {
    // ...
}

// MARK: - Private Helpers

private extension MainType {
    // ...
}
```

## Formatting

### Column Limit

**100 characters** per line

Exceptions:
- URLs in comments
- Import statements
- Generated code

### Braces

K&R style with Swift-specific rules:

```swift
// ✅ GOOD
if condition {
    doSomething()
}

guard let value = optional else {
    return
}

// Closure signature on same line as opening brace
numbers.map { value in
    return value * 2
}

// ⛔️ AVOID
if condition
{
    doSomething()
}
```

### Semicolons

**Never use semicolons** to terminate or separate statements.

```swift
// ✅ GOOD
let sum = a + b
print(sum)

// ⛔️ AVOID
let sum = a + b;
print(sum);
```

### One Statement Per Line

Single-statement blocks can stay on one line:

```swift
// ✅ GOOD
guard let value = value else { return 0 }

switch state {
case .ready: return true
case .loading: return false
}

var isEnabled: Bool { return flags.contains(.enabled) }
```

### Whitespace

#### Horizontal Whitespace

- Space after `if`, `guard`, `while`, `switch` if followed by `(`
- Spaces around binary/ternary operators
- Space after `:` in types, never before
- Space after `,` in lists
- **No** space around `.` member access
- **No** space around range operators (`...`, `..<`)

```swift
// ✅ GOOD
if (x == 0 && y == 0) || z == 0 {
    // ...
}

let numbers = [1, 2, 3]
let dict: [String: Int] = ["a": 1]
let range = 1...5

// ⛔️ AVOID
if(x == 0) {  // Missing space
    // ...
}

let numbers = [1,2,3]  // Missing spaces
let dict: [String:Int]  // Missing space after :
let range = 1 ... 5  // Unnecessary spaces
```

#### Vertical Whitespace

- Single blank line between type members (properties, methods, nested types)
- Optional blank lines between closely related properties
- No blank lines required before first or after last member

```swift
struct User {
    let id: String
    let name: String
    
    var displayName: String {
        return name.isEmpty ? "Anonymous" : name
    }
    
    func greet() -> String {
        return "Hello, \(displayName)"
    }
}
```

### Parentheses

**Never** use unnecessary parentheses around top-level conditionals:

```swift
// ✅ GOOD
if x == 0 {
    // ...
}

if (x == 0 || y == 1) && z == 2 {  // Inner grouping is fine
    // ...
}

// ⛔️ AVOID
if (x == 0) {
    // ...
}
```

## Line Wrapping

### Function Declarations

```swift
// ✅ GOOD
public func index<Elements: Collection, Element>(
    of element: Element,
    in collection: Elements
) -> Elements.Index? where Elements.Element == Element, Element: Equatable {
    // ...
}
```

### Function Calls

```swift
// ✅ GOOD
let index = search(
    for: targetValue,
    in: largeCollection,
    using: customComparator
)

// Trailing closure
someAsyncAction.execute(withDelay: delay, context: context) { result in
    handleResult(result)
}
```

### Control Flow

```swift
// ✅ GOOD
if someLongBooleanCondition &&
   anotherLongCondition &&
   yetAnotherCondition {
    doSomething()
}

guard let value = someLongOptionalExpression,
      let otherValue = anotherOptionalExpression else {
    return
}
```

## Specific Constructs

### Properties

Omit `get` for read-only computed properties:

```swift
// ✅ GOOD
var totalCost: Int {
    return items.sum { $0.cost }
}

// ⛔️ AVOID
var totalCost: Int {
    get {
        return items.sum { $0.cost }
    }
}
```

Declare one variable per statement:

```swift
// ✅ GOOD
var a = 5
var b = 10

// ⛔️ AVOID
var a = 5, b = 10
```

### Switch Statements

Cases at same level as `switch`:

```swift
// ✅ GOOD
switch order {
case .ascending:
    print("Ascending")
case .descending:
    print("Descending")
default:
    break
}
```

### Enum Cases

One case per line (unless simple and comma-separated fits):

```swift
// ✅ GOOD
enum Token {
    case comma
    case semicolon
    case identifier
}

// Also acceptable for simple enums
enum Token {
    case comma, semicolon, identifier
}

// With associated values - one per line
enum Result {
    case success(value: Int)
    case failure(error: Error)
}
```

### Trailing Closures

- Single closure argument at end → use trailing closure
- Multiple closures → label all inside parentheses

```swift
// ✅ GOOD
let squares = [1, 2, 3].map { $0 * $0 }

Timer.scheduledTimer(timeInterval: 30, repeats: false) { timer in
    print("Done")
}

UIView.animate(
    withDuration: 0.5,
    animations: {
        view.alpha = 0
    },
    completion: { finished in
        view.removeFromSuperview()
    }
)

// ⛔️ AVOID - multiple closures with trailing syntax
UIView.animate(
    withDuration: 0.5,
    animations: {
        view.alpha = 0
    }
) { finished in
    view.removeFromSuperview()
}
```

### Trailing Commas

**Required** for multi-line array/dictionary literals:

```swift
// ✅ GOOD
let keys = [
    "bufferSize",
    "compression",
    "encoding",  // ← Trailing comma
]

// ⛔️ AVOID
let keys = [
    "bufferSize",
    "compression",
    "encoding"  // ← Missing trailing comma
]
```

### Attributes

Parameterized attributes on separate lines:

```swift
// ✅ GOOD
@available(iOS 15.0, *)
public func newFeature() {
    // ...
}

// Simple attributes can be on same line if it fits
class MyViewController: UIViewController {
    @IBOutlet private var tableView: UITableView!
}
```

## Naming Conventions

### Follow Apple's Guidelines

Refer to [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) as the foundation.

### Identifiers

Use 7-bit ASCII unless Unicode has clear domain meaning:

```swift
// ✅ GOOD
let smile = "😊"
let deltaX = newX - oldX
let Δx = newX - oldX  // Acceptable in math contexts

// ⛔️ AVOID
let 😊 = "smile"
```

### Initializers

Parameter names match property names:

```swift
// ✅ GOOD
struct Person {
    let name: String
    let age: Int
    
    init(name: String, age: Int) {
        self.name = name
        self.age = age
    }
}

// ⛔️ AVOID
init(personName: String, personAge: Int) {
    name = personName
    age = personAge
}
```

### Static/Class Properties

No redundant type suffix:

```swift
// ✅ GOOD
class UIColor {
    static var red: UIColor { /* ... */ }
}

class URLSession {
    static var shared: URLSession { /* ... */ }
}

// ⛔️ AVOID
static var redColor: UIColor { /* ... */ }
static var sharedSession: URLSession { /* ... */ }
```

### Global Constants

Use `lowerCamelCase`, no Hungarian notation:

```swift
// ✅ GOOD
let secondsPerMinute = 60

// ⛔️ AVOID
let SecondsPerMinute = 60
let kSecondsPerMinute = 60
let SECONDS_PER_MINUTE = 60
```

## Programming Practices

### Type Shortcuts

Use shorthand for arrays, dictionaries, optionals:

```swift
// ✅ GOOD
var items: [String] = []
var map: [String: Int] = [:]
var name: String?

// ⛔️ AVOID
var items: Array<String> = []
var map: Dictionary<String, Int> = [:]
var name: Optional<String>
```

### Void vs ()

- Function return types: omit `Void` entirely
- Closure types: use `Void`
- Arguments: always `()`

```swift
// ✅ GOOD
func doSomething() {
    // ...
}

let callback: () -> Void

// ⛔️ AVOID
func doSomething() -> Void {
    // ...
}

let callback: () -> ()
```

### Optionals vs Sentinel Values

Use `Optional` instead of sentinel values like `-1`:

```swift
// ✅ GOOD
func index(of element: Element) -> Int? {
    // ...
}

if let index = array.index(of: item) {
    // Found
} else {
    // Not found
}

// ⛔️ AVOID
func index(of element: Element) -> Int {
    // Returns -1 if not found
}

if index != -1 {
    // Found
}
```

### Error Handling

Use `throws` for multiple error states:

```swift
// ✅ GOOD
enum DocumentError: Error {
    case notFound
    case permissionDenied
    case malformedHeader
}

func loadDocument(path: String) throws -> Document {
    // ...
}

do {
    let doc = try loadDocument(path: "file.txt")
} catch DocumentError.notFound {
    // Handle not found
} catch {
    // Handle other errors
}
```

### Force Unwrap/Cast

**Avoid** unless safety is guaranteed and documented:

```swift
// ✅ GOOD with comment
let value = getSomeInteger()
// This is safe because value is guaranteed to be a valid enum case
return SomeEnum(rawValue: value)!

// ⛔️ AVOID without clear reasoning
let value = someOptional!
```

Exception: Unit tests can use force-unwrap without documentation.

### Guard for Early Exits

Prefer `guard` over inverted `if` conditions:

```swift
// ✅ GOOD
func process(_ values: [Int]) throws {
    guard !values.isEmpty else {
        throw ProcessError.emptyArray
    }
    guard values.first! >= 0 else {
        throw ProcessError.negativeValue
    }
    
    // Main logic at base indentation level
    performProcessing(values)
}

// ⛔️ AVOID - pyramid of doom
func process(_ values: [Int]) throws {
    if !values.isEmpty {
        if values.first! >= 0 {
            performProcessing(values)
        } else {
            throw ProcessError.negativeValue
        }
    } else {
        throw ProcessError.emptyArray
    }
}
```

### for-where Loops

Use `where` instead of `if` wrapping entire loop body:

```swift
// ✅ GOOD
for item in collection where item.isActive {
    process(item)
}

// ⛔️ AVOID
for item in collection {
    if item.isActive {
        process(item)
    }
}
```

### Access Levels

- Omit access level when default is appropriate
- Never use file-level access on extensions

```swift
// ✅ GOOD
extension String {
    public var isUppercase: Bool {
        // ...
    }
}

// ⛔️ AVOID
public extension String {
    var isUppercase: Bool {
        // ...
    }
}
```

### Nesting for Namespacing

Prefer nesting over naming conventions:

```swift
// ✅ GOOD
class Parser {
    enum Error: Swift.Error {
        case invalidToken(String)
        case unexpectedEOF
    }
}

// Use caseless enum for pure namespaces
enum Constants {
    static let timeout: TimeInterval = 30
    static let maxRetries = 3
}

// ⛔️ AVOID
enum ParseError: Error {
    // Separate from Parser
}

struct Constants {
    private init() {}  // Boilerplate to prevent init
    static let timeout: TimeInterval = 30
}
```

## Comments

### Non-Documentation Comments

Use `//` only, never `/* */`:

```swift
// ✅ GOOD
// This is a comment
let value = 42

// ⛔️ AVOID
/* This is a comment */
let value = 42
```

### End-of-Line Comments

Two spaces before `//`, one space after:

```swift
// ✅ GOOD
let factor = 2  // Warm up the modulator

// ⛔️ AVOID
let factor = 2 //Warm up the modulator
let factor = 2//Warm up the modulator
```

## Documentation Comments

Use `///` for documentation (see [code-documentation.md](code-documentation.md) for details):

```swift
/// Fetches user data from the remote server.
///
/// - Parameter userID: The unique user identifier.
/// - Returns: A `User` object with profile data.
/// - Throws: `NetworkError` if the request fails.
func fetchUser(userID: String) async throws -> User {
    // ...
}
```

## Code Organization Markers

Use `// MARK:` liberally with `-` for visual separators:

```swift
// MARK: - Properties

@State private var isLoading = false

// MARK: - Lifecycle

override func viewDidLoad() {
    super.viewDidLoad()
}

// MARK: - Actions

@objc private func buttonTapped() {
    // ...
}

// MARK: - Helpers

private func formatDate(_ date: Date) -> String {
    // ...
}
```

## Checklist for Code Reviews

- [ ] 100 character line limit respected
- [ ] No semicolons
- [ ] Proper use of `// MARK:` for organization
- [ ] Trailing commas in multi-line collections
- [ ] Shorthand types (`[T]`, `[K: V]`, `T?`)
- [ ] One statement per line (unless single-statement block)
- [ ] `guard` for early exits
- [ ] Documentation comments on public APIs
- [ ] No force-unwrap without clear justification
- [ ] Consistent naming following Apple's guidelines
- [ ] Proper whitespace (spaces after `:`, around operators)

## Additional Resources

- [Google Swift Style Guide](https://google.github.io/swift/) (full reference)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [Code Documentation Standards](code-documentation.md) (this project)
- **Apple Official Documentation** — Available locally in Xcode at:
  ```
  /Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation
  ```
  This includes comprehensive Swift language guides, framework documentation, and best practices directly from Apple.

## When to Deviate

These guidelines represent best practices, but exceptions are allowed when:

1. **Existing code patterns** — Match surrounding code style in existing files
2. **Third-party integration** — When integrating libraries with different conventions
3. **Performance** — When profiling shows measurable improvement from deviation
4. **Clarity** — When following the rule would reduce readability in a specific case

**Always document intentional deviations** with inline comments explaining why.
