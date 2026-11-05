# On Xcode 27.2 altool can print an ERROR line about its resume-state file and
# then finish the upload: it prints `UPLOAD SUCCEEDED with no errors` and a
# Delivery UUID, and the build reaches App Store Connect. fastlane 2.230.0 fails
# on any ERROR line, so the lane exits with an error and invites a retry of a
# build number that Apple already holds.
#
# fastlane 2.240.0 fixes this (fastlane#30196), but it needs Ruby 3.1 and uploads
# run on the system Ruby 2.6. Its fix also forgives every error once the success
# line appears. This one forgives exactly one error: anything else in the output,
# including a non-zero altool exit status, stays a failure.
module AltoolUploadFalseFailure
  SUCCESS_LINE = "UPLOAD SUCCEEDED with no errors".freeze
  FALSE_ERROR = "Failed to create URL for 'CDUploaderStateInfoResumeFilePath'".freeze

  def self.false_failure?(errors, lines)
    return false if errors.nil? || errors.empty? || lines.nil?

    errors.all? { |error| error.include?(FALSE_ERROR) } &&
      lines.any? { |line| line.include?(SUCCESS_LINE) }
  end

  # The executor yields the output after it has collected every error and before
  # it returns `@errors.empty?`, so this is the one place to judge the whole run.
  # altool's output still reaches the log unchanged.
  module ExecutorPatch
    def execute(command, hide_output)
      super(command, hide_output) do |lines|
        if AltoolUploadFalseFailure.false_failure?(@errors, lines)
          FastlaneCore::UI.important(
            "altool reported success after the known #{AltoolUploadFalseFailure::FALSE_ERROR} error; treating the upload as successful."
          )
          @errors.clear
        end
        yield(lines) if block_given?
      end
    end
  end

  def self.install(executor_class)
    return if executor_class.ancestors.include?(ExecutorPatch)

    executor_class.prepend(ExecutorPatch)
  end
end
