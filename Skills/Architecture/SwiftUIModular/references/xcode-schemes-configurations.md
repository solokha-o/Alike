# Xcode Schemes & Build Configurations

## Intent

Provide guidelines for organizing Xcode schemes and build configurations to support multiple deployment targets (production, staging, testing) and enable testing with test data without affecting production builds.

## Core Concepts

### Build Configuration

A **build configuration** defines compiler settings, optimization levels, and build-time constants.

**Default configurations:**
- **Debug** — Fast compilation, no optimizations, debug symbols included
- **Release** — Optimized code, symbols stripped, smaller binary size

**Custom configurations** (optional):
- **Staging** — Production-like optimizations with staging endpoints
- **Testing** — Debug-like with test data injection enabled

### Scheme

A **scheme** bundles:
- Build configuration to use
- Run arguments and environment variables
- Test configuration
- Archive configuration

**Best practice:** One scheme per deployment target.

## Standard Setup

### Minimal Configuration (Small Projects)

For small projects with single production environment:

```
Configurations:
├── Debug
└── Release

Schemes:
└── MyApp (default)
    ├── Run → Debug
    ├── Test → Debug
    └── Archive → Release
```

**When to use:** Single-target apps, side projects, MVPs.

### Production Setup (Multi-Environment)

For apps with staging/production separation:

```
Configurations:
├── Debug
├── Staging
└── Release

Schemes:
├── MyApp (Debug)
│   ├── Run → Debug
│   └── Test → Debug
├── MyApp (Staging)
│   ├── Run → Staging
│   ├── Test → Staging
│   └── Archive → Staging
└── MyApp (Production)
    ├── Run → Release
    ├── Test → Release
    └── Archive → Release
```

**When to use:** Production apps with multiple environments.

## Creating Build Configurations

### Step 1: Duplicate Configuration

1. Project Navigator → Select Project
2. Info tab → Configurations
3. Click `+` → Duplicate "Release" Configuration
4. Rename to `Staging`

### Step 2: Configure Build Settings

Set configuration-specific values:

```
Base SDK: iOS
Optimization Level:
  - Debug: None [-O0]
  - Staging: Optimize for Speed [-O]
  - Release: Optimize for Speed [-O]

Swift Compilation Mode:
  - Debug: Incremental
  - Staging: Whole Module
  - Release: Whole Module

Generate Debug Symbols:
  - Debug: Yes
  - Staging: Yes
  - Release: Yes (stripped during archive)

Active Compilation Conditions:
  - Debug: DEBUG
  - Staging: STAGING DEBUG_MENU
  - Release: RELEASE
```

## Conditional Compilation

Use `#if` directives to compile code based on configuration:

```swift
// MARK: - Configuration Detection

#if DEBUG
let isDebugBuild = true
#else
let isDebugBuild = false
#endif

// MARK: - Environment-Specific Values

struct AppConfig {
    static let apiBaseURL: String = {
        #if RELEASE
        return "https://api.production.com"
        #elseif STAGING
        return "https://api.staging.com"
        #else
        return "http://localhost:3000"
        #endif
    }()
    
    static let enableDebugMenu: Bool = {
        #if DEBUG_MENU
        return true
        #else
        return false
        #endif
    }()
}

// MARK: - Feature Flags

extension FeatureFlags {
    static let useMockData: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("USE_MOCK_DATA")
        #else
        return false
        #endif
    }()
}
```

## Scheme Configuration

### Creating a New Scheme

1. Product → Scheme → Manage Schemes
2. Click `+` to create new scheme
3. Name: `MyApp (Staging)`
4. Target: Select your app target
5. Check "Shared" if used by team/CI

### Configuring Scheme Actions

#### Run Action

```
Build Configuration: Staging
Executable: MyApp.app

Arguments Passed On Launch:
  -USE_MOCK_DATA
  -UITestingEnabled

Environment Variables:
  API_ENDPOINT: https://api.staging.com
  LOG_LEVEL: verbose
```

#### Test Action

```
Build Configuration: Debug

Arguments:
  -USE_TEST_DATA
  -InMemoryPersistence

Environment Variables:
  DISABLE_ANIMATIONS: 1
  RESET_APP_STATE: 1
```

#### Archive Action

```
Build Configuration: Release (or Staging for staging builds)

Pre-actions:
  - Run Script: Scripts/increment_build_number.sh
  
Post-actions:
  - Run Script: Scripts/upload_dsym.sh
```

## Testing with Test Data

### Approach 1: Launch Arguments

Detect test mode via launch arguments:

```swift
// MARK: - Test Mode Detection

extension ProcessInfo {
    var isRunningTests: Bool {
        arguments.contains("USE_TEST_DATA")
    }
    
    var isUITesting: Bool {
        arguments.contains("UITestingEnabled")
    }
}

// MARK: - Data Source Selection

protocol DataProvider {
    func fetchUsers() async throws -> [User]
}

class AppDataProvider: DataProvider {
    private let useTestData: Bool
    
    init(useTestData: Bool = ProcessInfo.processInfo.isRunningTests) {
        self.useTestData = useTestData
    }
    
    func fetchUsers() async throws -> [User] {
        if useTestData {
            return TestData.sampleUsers
        }
        return try await APIClient.shared.fetchUsers()
    }
}
```

**Configure in scheme:**
- Edit Scheme → Test → Arguments
- Add: `-USE_TEST_DATA`

### Approach 2: Build Configuration

Use compilation conditions for permanent test builds:

```swift
// MARK: - Configuration-Based Switching

struct DataSourceFactory {
    static func makeUserRepository() -> UserRepository {
        #if TESTING_CONFIG
        return MockUserRepository(data: TestData.users)
        #else
        return RemoteUserRepository(apiClient: APIClient.shared)
        #endif
    }
}
```

**Build Settings:**
- Create `Testing` configuration (duplicate Debug)
- Add `TESTING_CONFIG` to Active Compilation Conditions
- Create scheme `MyApp (Testing)` using this configuration

### Approach 3: Environment Variables

Pass configuration at runtime:

```swift
// MARK: - Environment-Based Config

struct AppEnvironment {
    static var dataMode: DataMode {
        if let mode = ProcessInfo.processInfo.environment["DATA_MODE"] {
            return DataMode(rawValue: mode) ?? .production
        }
        return .production
    }
}

enum DataMode: String {
    case production
    case staging
    case mock
}

// MARK: - Usage

class DataService {
    func loadUsers() async throws -> [User] {
        switch AppEnvironment.dataMode {
        case .production:
            return try await loadProductionUsers()
        case .staging:
            return try await loadStagingUsers()
        case .mock:
            return MockData.users
        }
    }
}
```

**Configure in scheme:**
- Edit Scheme → Run → Arguments → Environment Variables
- Add: `DATA_MODE = mock`

## Testing Strategy

### Unit Tests

Always use test configuration:

```swift
// MARK: - Test Setup

class UserServiceTests: XCTestCase {
    var sut: UserService!
    
    override func setUp() {
        super.setUp()
        // Tests automatically use test data via dependency injection
        sut = UserService(repository: MockUserRepository())
    }
    
    func testFetchUsers() async throws {
        let users = try await sut.fetchUsers()
        XCTAssertEqual(users.count, 3)
    }
}
```

**Scheme settings:**
- Test action → Build Configuration: Debug
- No launch arguments needed (tests use mocks directly)

### UI Tests

Use dedicated scheme with test data:

```swift
// MARK: - UI Test Setup

class AppUITests: XCTestCase {
    let app = XCUIApplication()
    
    override func setUp() {
        super.setUp()
        app.launchArguments = [
            "-UITestingEnabled",
            "-USE_MOCK_DATA",
            "-DISABLE_ANIMATIONS"
        ]
        app.launch()
    }
    
    func testUserListLoadsTestData() {
        // App uses mock data, assertions are predictable
        XCTAssertTrue(app.staticTexts["John Doe"].exists)
    }
}
```

**Scheme settings:**
- Create `MyApp (UI Testing)` scheme
- Test action → Arguments: `-UITestingEnabled -USE_MOCK_DATA`

### Integration Tests (Staging Environment)

Test against staging backend:

```swift
// MARK: - Integration Test Setup

@available(*, deprecated, message: "Use unit tests with mocks instead")
class StagingIntegrationTests: XCTestCase {
    func testRealAPIFetch() async throws {
        // Only run when explicitly enabled
        try XCTSkipUnless(
            ProcessInfo.processInfo.arguments.contains("RUN_INTEGRATION_TESTS"),
            "Integration tests disabled"
        )
        
        let service = UserService(baseURL: "https://api.staging.com")
        let users = try await service.fetchUsers()
        XCTAssertFalse(users.isEmpty)
    }
}
```

**Manual execution only:**
- Do not include in CI
- Use `MyApp (Staging)` scheme with `-RUN_INTEGRATION_TESTS`

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build & Test

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      
      - name: Run Tests
        run: |
          xcodebuild test \
            -scheme "MyApp (Debug)" \
            -destination "platform=iOS Simulator,name=iPhone 15" \
            -configuration Debug
      
      - name: Build Staging
        if: github.ref == 'refs/heads/develop'
        run: |
          xcodebuild archive \
            -scheme "MyApp (Staging)" \
            -configuration Staging \
            -archivePath build/MyApp-Staging.xcarchive
      
      - name: Build Production
        if: github.ref == 'refs/heads/main'
        run: |
          xcodebuild archive \
            -scheme "MyApp (Production)" \
            -configuration Release \
            -archivePath build/MyApp.xcarchive
```

### Fastlane Integration

```ruby
# fastlane/Fastfile

lane :test do
  run_tests(
    scheme: "MyApp (Debug)",
    devices: ["iPhone 15"],
    configuration: "Debug"
  )
end

lane :staging do
  build_app(
    scheme: "MyApp (Staging)",
    configuration: "Staging",
    export_method: "ad-hoc"
  )
end

lane :release do
  build_app(
    scheme: "MyApp (Production)",
    configuration: "Release",
    export_method: "app-store"
  )
end
```

## Bundle Identifier Strategy

### Separate Bundle IDs per Environment

Use different bundle identifiers to install multiple builds simultaneously:

```
Debug:      com.company.myapp.debug
Staging:    com.company.myapp.staging
Release:    com.company.myapp
```

**Configuration:**

1. Build Settings → Packaging → Product Bundle Identifier
2. Set per-configuration values:

```
Debug:      $(PRODUCT_BUNDLE_IDENTIFIER_BASE).debug
Staging:    $(PRODUCT_BUNDLE_IDENTIFIER_BASE).staging
Release:    $(PRODUCT_BUNDLE_IDENTIFIER_BASE)
```

3. User-Defined Settings:
   - `PRODUCT_BUNDLE_IDENTIFIER_BASE = com.company.myapp`

### App Icon Badges

Visually distinguish non-production builds:

```swift
// MARK: - Icon Badge Script (Run Script Build Phase)

// Scripts/badge_icon.sh
#!/bin/bash
if [ "$CONFIGURATION" != "Release" ]; then
    # Add badge to app icon indicating build type
    # (requires ImageMagick or similar)
    echo "Badging icon for $CONFIGURATION"
fi
```

**Build Phases:**
- Add Run Script phase before "Copy Bundle Resources"
- Script: `${SRCROOT}/Scripts/badge_icon.sh`
- Run only for: Debug, Staging configurations

## Common Patterns

### Debug Menu

Show debug tools only in non-production builds:

```swift
// MARK: - Debug Menu View

#if DEBUG_MENU
struct DebugMenuView: View {
    @Environment(\.dataMode) private var dataMode
    
    var body: some View {
        List {
            Section("Environment") {
                Text("API: \(AppConfig.apiBaseURL)")
                Text("Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
                Text("Build: \(AppConfig.buildNumber)")
            }
            
            Section("Data Source") {
                Picker("Data Mode", selection: $dataMode) {
                    Text("Production").tag(DataMode.production)
                    Text("Staging").tag(DataMode.staging)
                    Text("Mock").tag(DataMode.mock)
                }
            }
            
            Section("Actions") {
                Button("Clear Cache") { clearCache() }
                Button("Reset Onboarding") { resetOnboarding() }
                Button("Crash App") { fatalError("Test crash") }
            }
        }
        .navigationTitle("Debug Menu")
    }
}
#endif

// MARK: - Conditional Inclusion

struct SettingsView: View {
    var body: some View {
        List {
            // Standard settings...
            
            #if DEBUG_MENU
            Section {
                NavigationLink("Debug Menu") {
                    DebugMenuView()
                }
            }
            #endif
        }
    }
}
```

### Feature Flags

Control features per configuration:

```swift
// MARK: - Feature Flags

enum FeatureFlags {
    static let enableNewDashboard: Bool = {
        #if RELEASE
        return false  // Not ready for production
        #else
        return true  // Available in staging/debug
        #endif
    }()
    
    static let enableAnalytics: Bool = {
        #if DEBUG
        return false  // Don't pollute analytics in dev
        #else
        return true
        #endif
    }()
}

// MARK: - Usage

struct ContentView: View {
    var body: some View {
        if FeatureFlags.enableNewDashboard {
            NewDashboardView()
        } else {
            LegacyDashboardView()
        }
    }
}
```

## Troubleshooting

### Scheme Not Building Correct Configuration

**Symptom:** Archive uses Debug instead of Release.

**Fix:**
1. Edit Scheme → Archive → Build Configuration
2. Set to `Release`
3. Ensure "Shared" is checked for team consistency

### Test Data Leaking to Production

**Symptom:** Production app shows test users.

**Prevention:**
```swift
// MARK: - Production Safety Check

struct DataSourceFactory {
    static func makeRepository() -> UserRepository {
        #if RELEASE
        // Fail compilation if test repository is referenced
        return RemoteUserRepository()
        #else
        if ProcessInfo.processInfo.isRunningTests {
            return MockUserRepository()
        }
        return RemoteUserRepository()
        #endif
    }
}
```

### Multiple App Installs Conflict

**Symptom:** Installing staging build replaces production build.

**Fix:** Use separate bundle identifiers (see Bundle Identifier Strategy).

### CI Builds Wrong Scheme

**Symptom:** CI archives debug build instead of release.

**Fix:**
```yaml
# Explicit scheme selection in CI
xcodebuild archive \
  -scheme "MyApp (Production)" \
  -configuration Release
```

## Checklist

### Creating New Configuration

- [ ] Duplicate appropriate base configuration (Debug/Release)
- [ ] Set optimization level and compilation mode
- [ ] Add configuration-specific compilation conditions
- [ ] Configure bundle identifier (if different per environment)
- [ ] Update Info.plist with configuration-specific values
- [ ] Add to version control (`.xcodeproj` changes)

### Creating New Scheme

- [ ] Create scheme via Product → Scheme → Manage Schemes
- [ ] Check "Shared" to commit to repo
- [ ] Configure Run action (build config, arguments, environment)
- [ ] Configure Test action (build config, test arguments)
- [ ] Configure Archive action (build config, pre/post scripts)
- [ ] Document scheme purpose in project README
- [ ] Update CI/CD workflows if needed

### Testing Setup

- [ ] Test scheme uses Debug configuration
- [ ] Launch arguments enable test data mode
- [ ] Environment variables disable external services
- [ ] Mock repositories injected via DI
- [ ] No network calls in unit tests
- [ ] UI tests use predictable test data
- [ ] Integration tests clearly separated and optional

## Best Practices

1. **Keep It Simple** — Start with Debug/Release, add configurations only when needed
2. **Shared Schemes** — Always share schemes in version control for team consistency
3. **Explicit Over Implicit** — Use clear names (`MyApp (Production)` not `MyApp`)
4. **Separate Bundle IDs** — Allow installing multiple environments side-by-side
5. **Guard Production** — Use `#if RELEASE` to prevent test code in production
6. **Document Schemes** — Add README section explaining each scheme's purpose
7. **Automate Switching** — Use Fastlane lanes, not manual scheme selection
8. **Test Early** — Verify configuration switching in CI, not just locally

## Additional Resources

- [Xcode Schemes Documentation](https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project)
- [Build Configuration Reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
- [Fastlane Documentation](https://docs.fastlane.tools/)
- [swift-code-style.md](swift-code-style.md) — Code style conventions
- [code-documentation.md](code-documentation.md) — Documentation standards

## When to Use Each Approach

| Scenario | Recommended Approach |
|----------|---------------------|
| Small project, single environment | Default Debug/Release only |
| Multi-environment app (staging/prod) | Custom configurations + schemes |
| Testing with mock data | Launch arguments + DI |
| Permanent test build | Custom Testing configuration |
| CI/CD with multiple targets | Fastlane lanes + named schemes |
| Feature flagging | Compilation conditions per config |
| Different API endpoints | Environment variables in schemes |
| Team development | Shared schemes in Git |
| Solo project | Local schemes OK |

---

**Remember:** Schemes and configurations are tools for organization. Start simple and add complexity only when clear benefits emerge. Over-engineering build setups creates maintenance burden without user-facing value.
