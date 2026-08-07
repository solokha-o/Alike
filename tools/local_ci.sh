#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
REPORT_ROOT="${ALIKE_LOCAL_CI_REPORT_ROOT:-$ROOT_DIR/build/reports/local-ci}"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
RUN_ID="${TIMESTAMP}-$$"
REPORT_DIR="$REPORT_ROOT/$RUN_ID"
LATEST_REPORT="$REPORT_ROOT/latest.json"
PROJECT_PATH="Alike/Alike.xcodeproj"
APP_SCHEME="Alike"
RELEASE_SCHEME="Alike"
DERIVED_DATA_ROOT="${ALIKE_DERIVED_DATA_ROOT:-/private/tmp/alike-local-ci-derived-data}"
CACHE_ROOT="${ALIKE_LOCAL_CI_CACHE_ROOT:-/private/tmp/alike-local-ci-swiftpm}"
SWIFTPM_SHARED_CACHE="$CACHE_ROOT/shared-cache"
SWIFTPM_SCRATCH_ROOT="$CACHE_ROOT/scratch"
BUILD_DESTINATION="${ALIKE_BUILD_DESTINATION:-}"
RELEASE_ARCHIVE_PATH="$REPORT_DIR/Alike.xcarchive"
RELEASE_EXPORT_PATH="$REPORT_DIR/export"
RELEASE_EXPORT_OPTIONS="$REPORT_DIR/ExportOptions.plist"

QUICK_PACKAGES=(
  "Packages/Cleanup"
  "Packages/Scanner"
  "Packages/Settings"
  "Packages/UserGuide"
)

# Packages whose tests cannot run under a plain `swift test` on macOS. They are
# still compiled and tested by the app compile gate and in Xcode.
# Storage: SwiftPM does not compile the `.xcdatamodeld`, so
# `PersistenceController` traps with "Failed to load Core Data model".
SWIFTPM_UNSUPPORTED_PACKAGES=(
  "Storage"
)

usage() {
  cat <<'USAGE'
Usage:
  tools/local_ci.sh quick
  tools/local_ci.sh full
  tools/local_ci.sh release-check --version X.Y.Z --build N

Modes:
  quick          Fast local checks for day-to-day agent or solo development.
  full           All package tests, App Store metadata bundle validation, and the full app compile gate.
  release-check  Version/build check plus Release archive/export validation.

Environment:
  ALIKE_DERIVED_DATA_ROOT        Override DerivedData root. Default: /private/tmp/alike-local-ci-derived-data
  ALIKE_LOCAL_CI_CACHE_ROOT      Override SwiftPM scratch/cache root. Default: /private/tmp/alike-local-ci-swiftpm
  ALIKE_BUILD_DESTINATION        Override the xcodebuild destination for the full-mode app compile.
                                  By default, the newest available iPhone simulator is used.
  ALIKE_CI_BASE_REF              Override committed diff base. Default: origin/develop
  CLANG_MODULE_CACHE_PATH        In a sandbox, set this at command launch to a writable /private/tmp path.
  DEVELOPER_DIR                  Xcode toolchain to use. When unset and `xcode-select` points at the
                                  Command Line Tools, the newest installed Xcode is selected automatically.
  ALIKE_SKIP_APP_BUILD=1         Skip the full app compile in full mode.
  ALIKE_SKIP_ARCHIVE=1           Records archive as skipped; release-check fails because archive validation is required.
  ALIKE_XCODE_ALLOW_PROVISIONING_UPDATES=1
                                  Pass -allowProvisioningUpdates to release archive/export.
  ALIKE_XCODE_AUTHENTICATION_KEY_PATH
                                  Optional override for xcodebuild App Store Connect auth key path.
  ALIKE_UPLOAD_SYMBOLS=1         Include App Store symbols during Release export. Default: 0.
  ALIKE_PRIVACY_URL              Enables strict metadata generation when set with ALIKE_SUPPORT_URL.
  ALIKE_SUPPORT_URL              Enables strict metadata generation when set with ALIKE_PRIVACY_URL.

Safety:
  This script never uploads metadata or binaries to Apple.
USAGE
}

fail_usage() {
  usage >&2
  exit 64
}

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

record_step() {
  local name="$1"
  local status="$2"
  local exit_code="$3"
  local log_path="$4"
  local escaped_name escaped_log

  escaped_name="$(printf "%s" "$name" | json_escape)"
  escaped_log="$(printf "%s" "$log_path" | json_escape)"
  printf '    {"name":"%s","status":"%s","exitCode":%s,"log":"%s"}' \
    "$escaped_name" "$status" "$exit_code" "$escaped_log" >> "$REPORT_DIR/steps.tmp"
}

append_step_record() {
  local name="$1"
  local status="$2"
  local exit_code="$3"
  local log_path="$4"

  if [[ -s "$REPORT_DIR/steps.tmp" ]]; then
    printf ',\n' >> "$REPORT_DIR/steps.tmp"
  fi
  record_step "$name" "$status" "$exit_code" "$log_path"
}

skip_step() {
  local name="$1"
  local reason="$2"
  local slug log_file

  slug="$(printf "%s" "$name" | tr '[:upper:] /:' '[:lower:]---' | tr -cd '[:alnum:]_.-')"
  log_file="$REPORT_DIR/${slug}.log"

  printf "\n==> %s\n" "$name"
  printf "Skipped: %s\n" "$reason"
  printf "Skipped: %s\n" "$reason" > "$log_file"
  append_step_record "$name" "skipped" 0 "$log_file"
}

run_step() {
  local name="$1"
  shift
  local slug log_file status exit_code

  slug="$(printf "%s" "$name" | tr '[:upper:] /:' '[:lower:]---' | tr -cd '[:alnum:]_.-')"
  log_file="$REPORT_DIR/${slug}.log"

  printf "\n==> %s\n" "$name"
  printf '$' > "$log_file"
  printf ' %q' "$@" >> "$log_file"
  printf '\n\n' >> "$log_file"

  set +e
  "$@" >> "$log_file" 2>&1
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    status="passed"
    printf "[pass] %s\n" "$name"
  else
    status="failed"
    printf "[fail] %s (exit %s)\n" "$name" "$exit_code"
    printf "Log: %s\n" "$log_file"
  fi

  append_step_record "$name" "$status" "$exit_code" "$log_file"

  if [[ "$exit_code" -ne 0 ]]; then
    write_report "failed"
    exit "$exit_code"
  fi
}

ensure_developer_dir() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  local selected
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$selected" == *"/Xcode"*".app/Contents/Developer" ]]; then
    return
  fi

  # xcode-select points at the Command Line Tools, where `swift test` cannot
  # load the PreviewsMacros plugin and `xcodebuild` refuses to run. Fall back to
  # the newest installed Xcode so the wrappers work without a manual export.
  # Prefer the newest release build; only fall back to a beta if that is all
  # that is installed.
  local candidate
  candidate="$(ls -d /Applications/Xcode*.app 2>/dev/null | grep -vi beta | sort -V | tail -1)"
  if [[ -z "$candidate" ]]; then
    candidate="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)"
  fi
  if [[ -n "$candidate" && -d "$candidate/Contents/Developer" ]]; then
    export DEVELOPER_DIR="$candidate/Contents/Developer"
    printf "Using DEVELOPER_DIR=%s\n" "$DEVELOPER_DIR"
  fi
}

run_whitespace_validation() {
  local base_ref="${ALIKE_CI_BASE_REF:-origin/develop}"

  run_step "git diff whitespace committed ${base_ref}...HEAD" git diff --check "${base_ref}...HEAD"
  run_step "git diff whitespace staged" git diff --cached --check
  run_step "git diff whitespace unstaged" git diff --check
}

write_report() {
  local status="$1"
  mkdir -p "$REPORT_ROOT"
  {
    printf '{\n'
    printf '  "mode":"%s",\n' "$MODE"
    printf '  "status":"%s",\n' "$status"
    printf '  "startedAt":"%s",\n' "$TIMESTAMP"
    printf '  "runId":"%s",\n' "$RUN_ID"
    printf '  "reportDirectory":"%s",\n' "$REPORT_DIR"
    printf '  "steps":[\n'
    if [[ -f "$REPORT_DIR/steps.tmp" ]]; then
      cat "$REPORT_DIR/steps.tmp"
      printf '\n'
    fi
    printf '  ]\n'
    printf '}\n'
  } > "$REPORT_DIR/report.json"
  cp "$REPORT_DIR/report.json" "$LATEST_REPORT"
}

all_package_paths() {
  find "$ROOT_DIR/Packages" -maxdepth 2 -name Package.swift -print \
    | sed "s#/Package.swift##" \
    | sort
}

package_slug() {
  local package_path="$1"
  printf "%s" "${package_path#$ROOT_DIR/}" | tr '/:' '--' | tr -cd '[:alnum:]_.-'
}

# Populates SWIFTPM_COMMON_ARGS instead of printing, so paths containing
# spaces survive the expansion at the call site.
SWIFTPM_COMMON_ARGS=()

set_swiftpm_common_args() {
  local package_path="$1"
  local slug
  slug="$(package_slug "$package_path")"

  SWIFTPM_COMMON_ARGS=(
    --package-path "$package_path"
    --scratch-path "$SWIFTPM_SCRATCH_ROOT/$slug"
    --cache-path "$SWIFTPM_SHARED_CACHE"
  )
}

run_package_tests() {
  local package_path
  for package_path in "$@"; do
    set_swiftpm_common_args "$package_path"
    run_step "swift test ${package_path#$ROOT_DIR/}" swift test "${SWIFTPM_COMMON_ARGS[@]}"
  done
}

swiftpm_unsupported() {
  local name="$1"
  local unsupported
  for unsupported in "${SWIFTPM_UNSUPPORTED_PACKAGES[@]}"; do
    if [[ "$name" == "$unsupported" ]]; then
      return 0
    fi
  done
  return 1
}

run_package_validation() {
  local package_path relative_path
  for package_path in "$@"; do
    relative_path="${package_path#$ROOT_DIR/}"
    if swiftpm_unsupported "$(basename "$package_path")"; then
      skip_step "swift test $relative_path" "not runnable under plain swift test on macOS; covered by the app compile gate"
      continue
    fi
    set_swiftpm_common_args "$package_path"
    if [[ -d "$package_path/Tests" ]]; then
      run_step "swift test $relative_path" swift test "${SWIFTPM_COMMON_ARGS[@]}"
    else
      run_step "swift build $relative_path" swift build "${SWIFTPM_COMMON_ARGS[@]}"
    fi
  done
}

run_metadata_validation() {
  if [[ -n "${ALIKE_PRIVACY_URL:-}" && -n "${ALIKE_SUPPORT_URL:-}" ]]; then
    run_step "metadata bundle generate strict URLs" python3 tools/prepare_app_store_upload_bundle.py
  else
    run_step "metadata bundle generate placeholders" python3 tools/prepare_app_store_upload_bundle.py --allow-placeholder-urls
  fi
}

resolve_build_destination() {
  if [[ -n "$BUILD_DESTINATION" ]]; then
    printf '%s\n' "$BUILD_DESTINATION"
    return
  fi

  local device_id
  device_id="$(xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

payload = json.load(sys.stdin)
candidates = []
for runtime, devices in payload.get("devices", {}).items():
    version = tuple(int(part) for part in re.findall(r"\d+", runtime))
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            candidates.append((version, device.get("name", ""), device.get("udid", "")))

if candidates:
    print(max(candidates)[2])
')"

  if [[ -z "$device_id" ]]; then
    printf 'No available iPhone simulator was found. Set ALIKE_BUILD_DESTINATION explicitly.\n' >&2
    return 1
  fi

  printf 'id=%s\n' "$device_id"
}

run_app_build() {
  if [[ "${ALIKE_SKIP_APP_BUILD:-0}" == "1" ]]; then
    skip_step "xcodebuild ${APP_SCHEME} build" "ALIKE_SKIP_APP_BUILD=1"
    return
  fi

  local build_destination
  build_destination="$(resolve_build_destination)"

  run_step "xcodebuild ${APP_SCHEME} build" \
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$APP_SCHEME" \
      -destination "$build_destination" \
      -derivedDataPath "$DERIVED_DATA_ROOT/app" \
      build
}

run_release_archive() {
  if [[ "${ALIKE_SKIP_ARCHIVE:-0}" == "1" ]]; then
    skip_step "xcodebuild ${RELEASE_SCHEME} archive" "ALIKE_SKIP_ARCHIVE=1 is not valid for release-check"
    write_report "failed"
    printf "release-check requires archive validation; unset ALIKE_SKIP_ARCHIVE or use a clearly named non-release dry-run mode.\n" >&2
    exit 65
  fi

  local provisioning_args=()
  if [[ "${ALIKE_XCODE_ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
    provisioning_args=(-allowProvisioningUpdates)
    local auth_key_path="${ALIKE_XCODE_AUTHENTICATION_KEY_PATH:-${APP_STORE_CONNECT_API_KEY_PATH:-}}"
    local auth_key_id="${ALIKE_XCODE_AUTHENTICATION_KEY_ID:-${APP_STORE_CONNECT_KEY_ID:-}}"
    local auth_key_issuer_id="${ALIKE_XCODE_AUTHENTICATION_KEY_ISSUER_ID:-${APP_STORE_CONNECT_ISSUER_ID:-}}"

    if [[ "$auth_key_path" == "~/"* ]]; then
      auth_key_path="$HOME/${auth_key_path#"~/"}"
    fi

    if [[ -n "$auth_key_path" && -n "$auth_key_id" && -n "$auth_key_issuer_id" ]]; then
      provisioning_args+=(
        -authenticationKeyPath "$auth_key_path"
        -authenticationKeyID "$auth_key_id"
        -authenticationKeyIssuerID "$auth_key_issuer_id"
      )
    fi
  fi

  if [[ "${#provisioning_args[@]}" -gt 0 ]]; then
    run_step "xcodebuild ${RELEASE_SCHEME} archive" \
      xcodebuild \
        "${provisioning_args[@]}" \
        -project "$PROJECT_PATH" \
        -scheme "$RELEASE_SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$DERIVED_DATA_ROOT/release" \
        -archivePath "$RELEASE_ARCHIVE_PATH" \
        archive
  else
    run_step "xcodebuild ${RELEASE_SCHEME} archive" \
      xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$RELEASE_SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$DERIVED_DATA_ROOT/release" \
        -archivePath "$RELEASE_ARCHIVE_PATH" \
        archive
  fi
}

write_release_export_options() {
  local upload_symbols="false"
  if [[ "${ALIKE_UPLOAD_SYMBOLS:-0}" == "1" ]]; then
    upload_symbols="true"
  fi

  cat > "$RELEASE_EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>app-store-connect</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>uploadSymbols</key>
  <$upload_symbols/>
</dict>
</plist>
PLIST
}

run_release_export() {
  write_release_export_options
  local provisioning_args=()
  if [[ "${ALIKE_XCODE_ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
    provisioning_args=(-allowProvisioningUpdates)
    local auth_key_path="${ALIKE_XCODE_AUTHENTICATION_KEY_PATH:-${APP_STORE_CONNECT_API_KEY_PATH:-}}"
    local auth_key_id="${ALIKE_XCODE_AUTHENTICATION_KEY_ID:-${APP_STORE_CONNECT_KEY_ID:-}}"
    local auth_key_issuer_id="${ALIKE_XCODE_AUTHENTICATION_KEY_ISSUER_ID:-${APP_STORE_CONNECT_ISSUER_ID:-}}"

    if [[ "$auth_key_path" == "~/"* ]]; then
      auth_key_path="$HOME/${auth_key_path#"~/"}"
    fi

    if [[ -n "$auth_key_path" && -n "$auth_key_id" && -n "$auth_key_issuer_id" ]]; then
      provisioning_args+=(
        -authenticationKeyPath "$auth_key_path"
        -authenticationKeyID "$auth_key_id"
        -authenticationKeyIssuerID "$auth_key_issuer_id"
      )
    fi
  fi

  if [[ "${#provisioning_args[@]}" -gt 0 ]]; then
    run_step "xcodebuild ${RELEASE_SCHEME} export" \
      xcodebuild \
        "${provisioning_args[@]}" \
        -exportArchive \
        -archivePath "$RELEASE_ARCHIVE_PATH" \
        -exportPath "$RELEASE_EXPORT_PATH" \
        -exportOptionsPlist "$RELEASE_EXPORT_OPTIONS"
  else
    run_step "xcodebuild ${RELEASE_SCHEME} export" \
      xcodebuild \
        -exportArchive \
        -archivePath "$RELEASE_ARCHIVE_PATH" \
        -exportPath "$RELEASE_EXPORT_PATH" \
        -exportOptionsPlist "$RELEASE_EXPORT_OPTIONS"
  fi
}

parse_release_args() {
  RELEASE_VERSION=""
  RELEASE_BUILD=""
  shift
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --version)
        RELEASE_VERSION="${2:-}"
        shift 2
        ;;
      --build)
        RELEASE_BUILD="${2:-}"
        shift 2
        ;;
      *)
        printf "Unknown release-check argument: %s\n" "$1" >&2
        fail_usage
        ;;
    esac
  done

  if [[ -z "$RELEASE_VERSION" || -z "$RELEASE_BUILD" ]]; then
    printf "release-check requires --version X.Y.Z --build N\n" >&2
    fail_usage
  fi
}

main() {
  [[ -n "$MODE" ]] || fail_usage
  mkdir -p "$REPORT_DIR"
  mkdir -p "$SWIFTPM_SHARED_CACHE" "$SWIFTPM_SCRATCH_ROOT"
  cd "$ROOT_DIR"
  ensure_developer_dir

  case "$MODE" in
    quick)
      run_whitespace_validation
      run_package_tests "${QUICK_PACKAGES[@]}"
      run_metadata_validation
      ;;
    full)
      run_whitespace_validation
      packages=()
      while IFS= read -r package_path; do
        packages+=("$package_path")
      done < <(all_package_paths)
      run_package_validation "${packages[@]}"
      run_metadata_validation
      run_app_build
      ;;
    release-check)
      parse_release_args "$@"
      run_step "version build check" \
        Skills/GitFlow/ios-git-flow/scripts/bump-ios-version.sh \
          --version "$RELEASE_VERSION" \
          --build "$RELEASE_BUILD" \
          --project Alike/Alike.xcodeproj/project.pbxproj \
          --check
      run_metadata_validation
      run_release_archive
      run_release_export
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      printf "Unknown mode: %s\n" "$MODE" >&2
      fail_usage
      ;;
  esac

  write_report "passed"
  printf "\nLocal CI passed. Report: %s\n" "$REPORT_DIR/report.json"
}

main "$@"
