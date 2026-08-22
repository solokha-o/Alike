#!/usr/bin/env bash
# Shared Xcode toolchain selection for the local CI and CD wrappers.
#
# Source this file; it defines ensure_developer_dir and runs nothing on its own.

# Print every /Applications/Xcode*.app that is really a toolchain, newest last.
#
# The glob also matches things that merely start with "Xcode" — Xcodes.app, the
# version manager, is the common one — so a name match is not enough: only a
# bundle carrying Contents/Developer/usr/bin/xcodebuild can back xcrun and
# xcodebuild. Filtering here keeps an impostor from crowding out the real Xcode
# in the release/beta preference below.
_xcode_toolchain_candidates() {
  local app
  for app in /Applications/Xcode*.app; do
    [[ -x "$app/Contents/Developer/usr/bin/xcodebuild" ]] || continue
    printf "%s\n" "$app"
  done | sort -V
}

# Point DEVELOPER_DIR at a real Xcode when the caller has not, so every child
# process — xcodebuild, swift, and the Java transporter Fastlane shells out to —
# sees the same toolchain.
#
# An explicit DEVELOPER_DIR always wins, and a machine whose `xcode-select`
# already points at an Xcode is left alone.
ensure_developer_dir() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  local selected
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$selected" == *".app/Contents/Developer" && -x "$selected/usr/bin/xcodebuild" ]]; then
    return
  fi

  # xcode-select points at the Command Line Tools, where `swift test` cannot
  # load the PreviewsMacros plugin and `xcodebuild` refuses to run. Fastlane
  # fails less obviously: `Helper.xcode_version` shells out to
  # `xcodebuild -version`, gets nothing, returns nil, and iTunesTransporter
  # crashes on `nil.start_with?`. Fall back to the newest installed Xcode so the
  # wrappers work without a manual export.
  # Prefer the newest release build; only fall back to a beta if that is all
  # that is installed.
  # Both pipelines are expected to come up empty — no Xcode at all, or nothing
  # but betas, which makes `grep -vi beta` exit 1. The callers run with
  # `set -o pipefail`, so without `|| true` that empty result aborts the whole
  # script here instead of falling through to the beta fallback below.
  local candidate
  candidate="$(_xcode_toolchain_candidates | grep -vi beta | tail -1 || true)"
  if [[ -z "$candidate" ]]; then
    candidate="$(_xcode_toolchain_candidates | tail -1 || true)"
  fi
  # A bare `if` that falls through returns 1, which would abort the callers'
  # `set -e` with no message at all. Say what happened and return cleanly: the
  # fallback is best-effort, and the tool that actually needs Xcode reports a
  # far better error than a silent exit.
  if [[ -n "$candidate" ]]; then
    export DEVELOPER_DIR="$candidate/Contents/Developer"
    printf "Using DEVELOPER_DIR=%s\n" "$DEVELOPER_DIR"
  else
    printf "warning: no Xcode.app under /Applications; leaving DEVELOPER_DIR unset\n" >&2
  fi
}
