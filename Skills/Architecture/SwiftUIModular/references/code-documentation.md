# Code Documentation Standards

## Intent

Establish clear documentation practices for Swift code using inline comments (`//`), doc comments (`///`), and code organization markers (`// MARK:`). The goal is to make code intent explicit, improve Quick Help integration in Xcode, and maintain navigability in large codebases.

## When to document

### Always document with `///`:
- Public APIs (classes, structs, enums, protocols, public methods)
- Complex algorithms or non-obvious logic
- Functions with multiple parameters or return values
- Protocol requirements that need context
- Throwing functions (document what errors are thrown)
- Closure parameters with non-obvious behavior

### Use `//` inline comments for:
- Explaining **why** a decision was made (not what the code does)
- Clarifying non-obvious business logic
- Warning about edge cases or gotchas
- Temporary workarounds with ticket references

### Skip documentation when:
- The code is self-explanatory (e.g., `getName()` returning a name)
- It's a simple property with an obvious purpose
- The method is private and trivial
- Tests already serve as documentation

## Doc comment format (`///`)

Use Swift's markup syntax for structured documentation that appears in Quick Help.

### Basic structure

```swift
/// Brief one-line summary.
///
/// Extended description providing context, usage notes, or implementation details.
/// Keep this section optional—only add it when the brief summary is insufficient.
///
/// - Parameters:
///   - parameterName: Description of the parameter.
///   - anotherParam: Another parameter description.
/// - Returns: Description of the return value.
/// - Throws: Description of errors that may be thrown.
/// - Note: Additional information or caveats.
/// - Warning: Important warnings about usage.
/// - Important: Critical information that must be understood.
/// - SeeAlso: Related types or methods.
func exampleMethod(parameterName: String, anotherParam: Int) throws -> Bool {
    // Implementation
}
```

### Keywords

- `- Parameter name:` — Describe a single parameter
- `- Parameters:` — List multiple parameters
- `- Returns:` — Describe the return value
- `- Throws:` — Document possible errors
- `- Note:` — Supplementary information
- `- Warning:` — Critical warnings
- `- Important:` — Essential information
- `- SeeAlso:` — Link to related code
- `- Precondition:` — Conditions that must be true before calling
- `- Postcondition:` — Conditions guaranteed after execution
- `- Complexity:` — Algorithm complexity (O-notation)

## Examples

### Function documentation

```swift
/// Fetches user profile data from the remote API.
///
/// This method attempts to load cached data first, then falls back to a network request
/// if the cache is stale or unavailable.
///
/// - Parameter userID: The unique identifier for the user.
/// - Returns: A `User` object containing profile information.
/// - Throws: `NetworkError.notFound` if the user doesn't exist,
///           `NetworkError.timeout` if the request times out.
/// - Note: Results are cached for 5 minutes.
func fetchUserProfile(userID: String) async throws -> User {
    // Implementation
}
```

### Protocol documentation

```swift
/// Defines a repository for managing place data with caching and refresh capabilities.
///
/// Implementations should handle cache invalidation and provide offline-first behavior.
public protocol PlaceRepository {
    /// Loads places from the cache or remote source.
    ///
    /// - Returns: An array of `Place` objects.
    /// - Throws: `RepositoryError` if data cannot be loaded.
    func list() async throws -> [Place]
    
    /// Forces a refresh from the remote source and updates the cache.
    ///
    /// - Returns: An updated array of `Place` objects.
    /// - Throws: `NetworkError` if the remote fetch fails.
    func refresh() async throws -> [Place]
}
```

### Property documentation

```swift
/// The user's display name, or "Unknown User" if not set.
///
/// - Note: This value is updated asynchronously after profile fetch.
var displayName: String { get }

/// Maximum number of retry attempts for failed network requests.
///
/// - Warning: Setting this too high may cause long delays on poor connections.
var maxRetries: Int { get set }
```

### Enum documentation

```swift
/// Represents possible authentication states in the app.
enum AuthState {
    /// User is not authenticated and must log in.
    case unauthenticated
    
    /// User is authenticated with an active session.
    ///
    /// - Parameter token: The current access token.
    case authenticated(token: String)
    
    /// Authentication is in progress.
    case loading
}
```

### Class/Struct documentation

```swift
/// Manages user session state and authentication flow.
///
/// This class handles login, logout, token refresh, and session persistence.
/// Use a single shared instance via dependency injection.
///
/// - Important: Always call `configure()` during app launch.
@MainActor
final class SessionManager {
    // Implementation
}
```

## Inline comments (`//`)

Use sparingly to explain **why**, not **what**.

### Good examples

```swift
// Use debounce to avoid excessive API calls during rapid typing
let debouncedSearch = searchText
    .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)

// FIXME: Temporary workaround for iOS 16 NavigationStack crash (PROJ-456)
if #available(iOS 17, *) {
    // Use new navigation API
} else {
    // Use legacy navigation
}

// TODO: Replace with async/await when iOS 15 support is dropped (Q2 2025)
URLSession.shared.dataTask(with: request) { data, response, error in
    // ...
}
```

### Bad examples (avoid)

```swift
// Loop through users
for user in users {
    // Print user name
    print(user.name)
}

// Set the title
title = "Home"
```

## Code organization with `// MARK:`

Use `// MARK:` to divide code into logical sections. Add a dash (`-`) to create a visual separator in Xcode's navigation.

### Standard structure for views

```swift
struct ProfileView: View {
    // MARK: - Properties
    
    @State private var isEditing = false
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Body
    
    var body: some View {
        // View hierarchy
    }
}

// MARK: - Actions

private extension ProfileView {
    func saveChanges() {
        // Implementation
    }
    
    func cancelEditing() {
        // Implementation
    }
}

// MARK: - Subviews

private extension ProfileView {
    var headerView: some View {
        // Implementation
    }
    
    var editButton: some View {
        // Implementation
    }
}

// MARK: - Helpers

private extension ProfileView {
    func formatDate(_ date: Date) -> String {
        // Implementation
    }
}
```

### Standard structure for view models

```swift
@MainActor
@Observable
final class PlacesViewModel {
    // MARK: - Properties
    
    private let repository: PlaceRepository
    private(set) var places: [Place] = []
    private(set) var isLoading = false
    
    // MARK: - Initialization
    
    init(repository: PlaceRepository) {
        self.repository = repository
    }
    
    // MARK: - Public API
    
    func loadPlaces() async {
        // Implementation
    }
    
    func refresh() async {
        // Implementation
    }
}

// MARK: - Private Helpers

private extension PlacesViewModel {
    func fetchFromRepository() async throws -> [Place] {
        // Implementation
    }
}
```

### Common section names

- `// MARK: - Properties` — Stored properties, dependencies
- `// MARK: - Initialization` — Init methods
- `// MARK: - Lifecycle` — viewDidLoad, onAppear, deinit
- `// MARK: - Body` — SwiftUI body property
- `// MARK: - Actions` — User-triggered actions
- `// MARK: - Public API` — Public interface methods
- `// MARK: - Subviews` — ViewBuilder properties
- `// MARK: - Helpers` — Private utility methods
- `// MARK: - Protocol Conformance` — Protocol implementations
- `// MARK: - Types` — Nested types

## Special comment markers

### TODO, FIXME, WARNING

Use these for code health tracking. Include context and ticket references.

```swift
// TODO: Add pagination support (PROJ-789)
func loadMorePlaces() async {
    // Not yet implemented
}

// FIXME: Memory leak when rapid navigation occurs (PROJ-890)
func navigateToDetail(_ id: String) {
    // Temporary workaround
}

// WARNING: This method is not thread-safe
func unsafeUpdate() {
    // Implementation
}
```

Xcode recognizes these markers and highlights them in the jump bar.

## Design choices to keep

1. **Favor clarity over brevity** — Documentation should help future readers (including you).
2. **Keep doc comments up to date** — Stale docs are worse than no docs.
3. **Document public APIs thoroughly** — These are your module's contract.
4. **Use `// MARK:` liberally** — It costs nothing and improves navigability.
5. **Explain the "why", not the "what"** — Code shows what; comments explain why.
6. **Link related code** — Use `- SeeAlso:` to connect related types.
7. **Warn about non-obvious behavior** — Use `- Warning:` and `- Important:`.

## Pitfalls

1. **Commenting obvious code** — Don't document `getName() -> String` with "Returns the name".
2. **Outdated comments** — Update comments when refactoring code.
3. **Over-commenting simple code** — Self-explanatory code doesn't need comments.
4. **Vague descriptions** — "Does stuff" is not helpful.
5. **Missing `Throws` documentation** — Always document what errors can occur.
6. **No parameter descriptions** — Explain non-obvious parameters.
7. **Forgetting to update `// MARK:` sections** — Keep them aligned with code structure.

## Quick Help preview

To preview your documentation in Xcode:
- **Option-click** a symbol to see Quick Help
- Use **⌘ Shift Y** to open the Quick Help Inspector

Ensure your `///` comments render correctly with proper formatting and structure.

## Example: Complete documented class

```swift
/// Manages the lifecycle and state of user sessions.
///
/// This class handles authentication, token refresh, and session persistence.
/// It provides a single source of truth for the current user's authentication state.
///
/// - Important: Must be initialized during app launch before any API calls.
/// - SeeAlso: `AuthService`, `TokenStorage`
@MainActor
final class SessionManager {
    // MARK: - Properties
    
    /// The current authentication state.
    ///
    /// Observers can react to state changes to update UI or trigger side effects.
    @Published private(set) var authState: AuthState = .unauthenticated
    
    private let authService: AuthService
    private let tokenStorage: TokenStorage
    
    // MARK: - Initialization
    
    /// Creates a new session manager.
    ///
    /// - Parameters:
    ///   - authService: Service for authentication operations.
    ///   - tokenStorage: Secure storage for access tokens.
    init(authService: AuthService, tokenStorage: TokenStorage) {
        self.authService = authService
        self.tokenStorage = tokenStorage
    }
    
    // MARK: - Public API
    
    /// Authenticates the user with provided credentials.
    ///
    /// - Parameters:
    ///   - username: The user's username or email.
    ///   - password: The user's password.
    /// - Throws: `AuthError.invalidCredentials` if login fails,
    ///           `NetworkError.timeout` if the request times out.
    /// - Note: Token is automatically stored on successful authentication.
    func login(username: String, password: String) async throws {
        authState = .loading
        
        do {
            let token = try await authService.authenticate(username: username, password: password)
            try await tokenStorage.save(token)
            authState = .authenticated(token: token)
        } catch {
            authState = .unauthenticated
            throw error
        }
    }
    
    /// Logs out the current user and clears stored credentials.
    ///
    /// - Note: This method always succeeds and resets to `.unauthenticated` state.
    func logout() async {
        await tokenStorage.clear()
        authState = .unauthenticated
    }
}

// MARK: - Private Helpers

private extension SessionManager {
    /// Refreshes the authentication token if it's about to expire.
    ///
    /// - Throws: `AuthError.refreshFailed` if the refresh request fails.
    func refreshTokenIfNeeded() async throws {
        // Implementation
    }
}
```

## When to create separate documentation files

For complex features or architectural patterns, consider creating dedicated reference docs (like this file) instead of cramming everything into code comments. Reference docs should cover:
- High-level architecture decisions
- Cross-cutting concerns
- Integration patterns
- Migration guides

Keep code comments focused on **implementation details** and reference docs focused on **conceptual understanding**.
