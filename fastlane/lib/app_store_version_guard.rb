# The guard that keeps a submission from touching the wrong App Store version.
#
# `deliver` runs `Deliver::Runner#verify_version`, which calls
# `App#ensure_version!` *before* it looks for the build. A wrong `version:`
# argument therefore renames the version already prepared in App Store Connect,
# and the rename survives the `Build number: … does not exist` failure that
# follows. Submitting is the one irreversible step of a release, so the lane
# reads the editable version first and refuses to go on unless it is exactly the
# one the caller named.
#
# Kept out of the Fastfile so it can be tested without a Fastfile, a network or
# an App Store Connect account: every collaborator is passed in.
module AppStoreVersionGuard
  Mismatch = Class.new(StandardError)

  # Returns the editable version when it matches, raises `Mismatch` otherwise.
  # Nothing here writes: the app object is only ever asked for its editable
  # version, so a mismatch cannot leave a trace in App Store Connect.
  def self.verify!(app:, requested_version:)
    raise Mismatch, "App Store Connect has no app to submit" if app.nil?

    version = app.get_edit_app_store_version

    if version.nil?
      raise Mismatch, "App Store Connect has no editable version; nothing is prepared to submit as #{requested_version}"
    end

    prepared = version.version_string.to_s
    if prepared != requested_version.to_s
      raise Mismatch, "App Store Connect has #{prepared} prepared, not #{requested_version}. " \
                      "Submitting would have renamed #{prepared} to #{requested_version} before it ever checked the build. " \
                      "Pass version:#{prepared}, or prepare #{requested_version} in App Store Connect first."
    end

    version
  end
end
