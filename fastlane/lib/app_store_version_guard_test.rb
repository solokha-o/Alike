# Offline test for the submission guard. No network, no App Store Connect, no
# fastlane runner: the stubs below stand in for Spaceship objects and record
# every call, so "a mismatch writes nothing" is an assertion and not a claim.
#
#   ruby fastlane/lib/app_store_version_guard_test.rb
require "minitest/autorun"
require_relative "app_store_version_guard"

class StubVersion
  attr_reader :version_string

  def initialize(version_string)
    @version_string = version_string
  end
end

# Records everything asked of it. `get_edit_app_store_version` is the only read
# the guard is allowed; anything else — a rename, a build selection, a submit —
# shows up in `calls` and fails the test.
class StubApp
  attr_reader :calls

  def initialize(version)
    @version = version
    @calls = []
  end

  def get_edit_app_store_version
    @calls << :get_edit_app_store_version
    @version
  end

  def method_missing(name, *args)
    @calls << name
    nil
  end

  def respond_to_missing?(_name, _include_private = false)
    true
  end
end

class AppStoreVersionGuardTest < Minitest::Test
  def test_matching_version_passes_through
    app = StubApp.new(StubVersion.new("1.5.0"))

    version = AppStoreVersionGuard.verify!(app: app, requested_version: "1.5.0")

    assert_equal "1.5.0", version.version_string
    assert_equal [:get_edit_app_store_version], app.calls
  end

  # The regression this guard exists for: `version:1.6.0` against a prepared
  # 1.5.0 used to rename 1.5.0 and only then fail on the build.
  def test_mismatched_version_raises_and_writes_nothing
    app = StubApp.new(StubVersion.new("1.5.0"))

    error = assert_raises(AppStoreVersionGuard::Mismatch) do
      AppStoreVersionGuard.verify!(app: app, requested_version: "1.6.0")
    end

    assert_includes error.message, "1.5.0"
    assert_includes error.message, "1.6.0"
    assert_equal [:get_edit_app_store_version], app.calls
  end

  def test_no_editable_version_raises_and_writes_nothing
    app = StubApp.new(nil)

    assert_raises(AppStoreVersionGuard::Mismatch) do
      AppStoreVersionGuard.verify!(app: app, requested_version: "1.5.0")
    end

    assert_equal [:get_edit_app_store_version], app.calls
  end

  def test_missing_app_raises
    assert_raises(AppStoreVersionGuard::Mismatch) do
      AppStoreVersionGuard.verify!(app: nil, requested_version: "1.5.0")
    end
  end
end
