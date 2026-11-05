# Offline test for the altool false-failure handling. It uploads nothing: altool
# is replaced by a shell script that prints the output captured from the
# 2026-11-05 upload of 1.7.0 (16).
#
#   ruby fastlane/lib/altool_upload_false_failure_test.rb
#   LC_ALL=en_US.UTF-8 GEM_PATH="$PWD/vendor/bundle/ruby/2.6.0" /usr/bin/ruby fastlane/lib/altool_upload_false_failure_test.rb
#
# The first form needs no gems and tests the decision against a stub. The second
# also runs the replay through the real fastlane executor and a real PTY. It does
# not use `bundle exec`, which hides minitest because the Gemfile does not list it.
require "minitest/autorun"
require "shellwords"
require "tempfile"
require_relative "altool_upload_false_failure"

begin
  require "fastlane_core"
  REAL_FASTLANE = true
rescue LoadError
  REAL_FASTLANE = false
  module FastlaneCore
    module UI
      def self.important(_message); end
    end
  end
end

FALSE_ERROR_LINE = "2026-11-05 16:53:12.318 \e[1m\e[31mERROR: [ContentDelivery.Uploader.7548C55580] " \
                   "Failed to create URL for 'CDUploaderStateInfoResumeFilePath'. The file doesn’t exist. " \
                   "(4) The file doesn’t exist.\e[0m".freeze
SUCCESS_LINES = [
  "==========================================",
  "UPLOAD SUCCEEDED with no errors",
  "Delivery UUID: 00000000-0000-0000-0000-000000000000",
  "=========================================="
].freeze
OTHER_ERROR_LINE = "2026-11-05 16:53:12.318 ERROR: [ContentDelivery.Uploader] Asset validation failed".freeze
FAILED_LINE = "UPLOAD FAILED with 1 error".freeze

class AltoolUploadFalseFailureDecisionTest < Minitest::Test
  FALSE_ERROR = "[ContentDelivery.Uploader.7548C55580] #{AltoolUploadFalseFailure::FALSE_ERROR}. The file doesn’t exist.".freeze

  def test_known_error_with_success_line_is_a_false_failure
    assert AltoolUploadFalseFailure.false_failure?([FALSE_ERROR], SUCCESS_LINES)
  end

  def test_known_error_without_success_line_stays_a_failure
    refute AltoolUploadFalseFailure.false_failure?([FALSE_ERROR], [FAILED_LINE])
  end

  def test_other_error_with_success_line_stays_a_failure
    refute AltoolUploadFalseFailure.false_failure?(["Asset validation failed"], SUCCESS_LINES)
  end

  def test_known_error_beside_another_error_stays_a_failure
    refute AltoolUploadFalseFailure.false_failure?([FALSE_ERROR, "Asset validation failed"], SUCCESS_LINES)
  end

  def test_no_errors_or_no_output_changes_nothing
    refute AltoolUploadFalseFailure.false_failure?([], SUCCESS_LINES)
    refute AltoolUploadFalseFailure.false_failure?([FALSE_ERROR], nil)
  end

  def test_output_with_invalid_utf8_does_not_raise
    assert AltoolUploadFalseFailure.false_failure?([FALSE_ERROR], ["\xFF", *SUCCESS_LINES])
  end
end

# Has the contract of the executor in fastlane 2.230.0: it yields the output
# after it collected the errors, then returns whether any are left.
class StubExecutor
  attr_reader :errors

  def initialize(errors, lines)
    @errors = errors
    @lines = lines
  end

  def execute(_command, _hide_output)
    yield(@lines) if block_given?
    @errors.empty?
  end
end

class AltoolUploadFalseFailurePatchTest < Minitest::Test
  def patched
    Class.new(StubExecutor) { AltoolUploadFalseFailure.install(self) }
  end

  def test_clears_the_known_error_and_returns_success
    executor = patched.new([AltoolUploadFalseFailure::FALSE_ERROR], SUCCESS_LINES)
    assert executor.execute("altool", true)
    assert_empty executor.errors
  end

  def test_keeps_other_errors_and_returns_failure
    executor = patched.new(["Asset validation failed"], SUCCESS_LINES)
    refute executor.execute("altool", true)
    assert_equal ["Asset validation failed"], executor.errors
  end

  def test_passes_the_output_to_the_callers_block
    received = nil
    patched.new([], SUCCESS_LINES).execute("altool", true) { |lines| received = lines }
    assert_equal SUCCESS_LINES, received
  end

  def test_second_install_does_not_patch_twice
    executor_class = patched
    AltoolUploadFalseFailure.install(executor_class)
    assert_equal 1, executor_class.ancestors.count(AltoolUploadFalseFailure::ExecutorPatch)
  end
end

class FastfileWiringTest < Minitest::Test
  def test_testflight_lane_installs_the_patch_before_it_uploads
    fastfile = File.read(File.expand_path("../Fastfile", __dir__), encoding: "UTF-8")
    lane = fastfile[/lane :testflight_upload do.*?^  end$/m]
    refute_nil lane
    install = lane.index("AltoolUploadFalseFailure.install(FastlaneCore::AltoolTransporterExecutor)")
    refute_nil install
    assert_operator install, :<, lane.index("upload_to_testflight(")
  end
end

if REAL_FASTLANE
  class RealExecutorReplayTest < Minitest::Test
    def replay(executor_class, lines, exit_status: 0)
      script = Tempfile.new("fake-altool")
      lines.each { |line| script.puts("printf '%s\\n' #{line.shellescape}") }
      script.puts("exit #{exit_status}")
      script.close
      executor = executor_class.new
      [executor.execute("/bin/sh #{script.path.shellescape}", true), executor]
    ensure
      script.unlink
    end

    def plain
      FastlaneCore::AltoolTransporterExecutor
    end

    def patched
      Class.new(plain) { AltoolUploadFalseFailure.install(self) }
    end

    # Without this test the others could pass against a gem that no longer has the bug.
    def test_unpatched_executor_reproduces_the_false_failure
      result, = replay(plain, [FALSE_ERROR_LINE, *SUCCESS_LINES])
      refute result
    end

    def test_false_failure_becomes_a_success
      result, executor = replay(patched, [FALSE_ERROR_LINE, *SUCCESS_LINES])
      assert result
      assert_empty executor.instance_variable_get(:@errors)
    end

    def test_known_error_without_success_line_stays_a_failure
      result, executor = replay(patched, [FALSE_ERROR_LINE, FAILED_LINE])
      refute result
      assert_includes executor.displayable_errors, "CDUploaderStateInfoResumeFilePath"
    end

    def test_another_error_beside_the_success_line_stays_a_failure
      result, = replay(patched, [FALSE_ERROR_LINE, OTHER_ERROR_LINE, *SUCCESS_LINES])
      refute result
    end

    def test_non_zero_exit_status_stays_a_failure
      result, = replay(patched, [FALSE_ERROR_LINE, *SUCCESS_LINES], exit_status: 1)
      refute result
    end

    def test_clean_upload_stays_a_success
      result, = replay(patched, SUCCESS_LINES)
      assert result
    end
  end
else
  puts "fastlane is not loaded: skipped the real executor replay. Set GEM_PATH to run it (see the top of this file)."
end
