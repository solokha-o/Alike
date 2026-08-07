#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
REPORT_ROOT="${ALIKE_LOCAL_CD_REPORT_ROOT:-$ROOT_DIR/build/reports/local-cd}"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
RUN_ID="${TIMESTAMP}-$$"
REPORT_DIR="$REPORT_ROOT/$RUN_ID"

usage() {
  cat <<'USAGE'
Usage:
  ALIKE_CONFIRM_UPLOAD=metadata tools/local_cd.sh upload-metadata
  ALIKE_CONFIRM_UPLOAD=metadata tools/local_cd.sh upload-text-metadata
  ALIKE_CONFIRM_UPLOAD=metadata tools/local_cd.sh upload-screenshots
  ALIKE_CONFIRM_UPLOAD=testflight tools/local_cd.sh upload-testflight --version X.Y.Z --build N

Shortcuts:
  tools/upload
  tools/text
  tools/upload-screenshots
  tools/upload-build [X.Y.Z] [N]

Modes:
  upload-metadata      Upload localized App Store metadata and screenshots via Fastlane deliver.
  upload-text-metadata Upload localized App Store text metadata and App Review info only.
  upload-screenshots   Upload localized App Store screenshots only.
  upload-testflight    Archive Alike Release and upload the binary to TestFlight via Fastlane pilot.

Required App Store Connect environment:
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_API_KEY_CONTENT
    or APP_STORE_CONNECT_API_KEY_PATH

Required for metadata upload modes:
  ALIKE_PRIVACY_URL
  ALIKE_SUPPORT_URL

Safety:
  Uploads require ALIKE_CONFIRM_UPLOAD=metadata or ALIKE_CONFIRM_UPLOAD=testflight.
  TestFlight upload also requires --version X.Y.Z --build N, runs release-check first,
  and uploads the IPA exported by that release-check.
  This script does not bump versions or commit changes.
USAGE
}

fail_usage() {
  usage >&2
  exit 64
}

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    printf "Missing required environment variable: %s\n" "$key" >&2
    exit 65
  fi
}

require_app_store_connect_env() {
  require_env APP_STORE_CONNECT_KEY_ID
  require_env APP_STORE_CONNECT_ISSUER_ID
  if [[ -z "${APP_STORE_CONNECT_API_KEY_CONTENT:-}" && -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
    printf "Missing APP_STORE_CONNECT_API_KEY_CONTENT or APP_STORE_CONNECT_API_KEY_PATH\n" >&2
    exit 65
  fi
}

require_public_https_url() {
  local key="$1"
  local value="${!key:-}"

  require_env "$key"
  case "$value" in
    https://*ALIKE*|*__ALIKE_*|https://example.com/*|http://*)
      printf "%s must be the exact public https URL, not a placeholder or http URL\n" "$key" >&2
      exit 65
      ;;
    https://*)
      ;;
    *)
      printf "%s must be an https URL\n" "$key" >&2
      exit 65
      ;;
  esac
}

require_confirmation() {
  local expected="$1"
  if [[ "${ALIKE_CONFIRM_UPLOAD:-}" != "$expected" ]]; then
    printf "Refusing upload. Set ALIKE_CONFIRM_UPLOAD=%s to continue.\n" "$expected" >&2
    exit 66
  fi
}

require_no_args() {
  if [[ "$#" -ne 0 ]]; then
    printf "Unexpected arguments for %s: %s\n" "$MODE" "$*" >&2
    fail_usage
  fi
}

require_testflight_args() {
  TESTFLIGHT_VERSION=""
  TESTFLIGHT_BUILD=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --version)
        [[ "$#" -ge 2 && -n "$2" ]] || fail_usage
        TESTFLIGHT_VERSION="$2"
        shift 2
        ;;
      --build)
        [[ "$#" -ge 2 && -n "$2" ]] || fail_usage
        TESTFLIGHT_BUILD="$2"
        shift 2
        ;;
      *)
        printf "Unknown upload-testflight argument: %s\n" "$1" >&2
        fail_usage
        ;;
    esac
  done

  if [[ -z "$TESTFLIGHT_VERSION" || -z "$TESTFLIGHT_BUILD" ]]; then
    printf "upload-testflight requires --version X.Y.Z --build N\n" >&2
    fail_usage
  fi

  if [[ ! "$TESTFLIGHT_VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
    printf "Invalid --version %s. Expected X.Y.Z\n" "$TESTFLIGHT_VERSION" >&2
    exit 64
  fi

  if [[ ! "$TESTFLIGHT_BUILD" =~ ^[1-9][0-9]*$ ]]; then
    printf "Invalid --build %s. Expected a positive integer\n" "$TESTFLIGHT_BUILD" >&2
    exit 64
  fi
}

run_logged() {
  local name="$1"
  shift
  local log_file="$REPORT_DIR/$name.log"
  mkdir -p "$REPORT_DIR"
  printf '$' > "$log_file"
  printf ' %q' "$@" >> "$log_file"
  printf '\n\n' >> "$log_file"
  printf "==> %s\n" "$name"
  "$@" 2>&1 | tee -a "$log_file"
}

latest_release_check_ipa_path() {
  python3 - "$ROOT_DIR/build/reports/local-ci/latest.json" <<'PY'
import json
import pathlib
import sys

latest_report = pathlib.Path(sys.argv[1])
report = json.loads(latest_report.read_text())
print(pathlib.Path(report["reportDirectory"]) / "export" / "Alike.ipa")
PY
}

main() {
  [[ -n "$MODE" ]] || fail_usage
  shift
  cd "$ROOT_DIR"

  case "$MODE" in
    upload-metadata)
      require_no_args "$@"
      require_confirmation metadata
      require_app_store_connect_env
      require_public_https_url ALIKE_PRIVACY_URL
      require_public_https_url ALIKE_SUPPORT_URL
      run_logged "metadata_upload" bundle exec fastlane ios metadata_upload
      ;;
    upload-text-metadata)
      require_no_args "$@"
      require_confirmation metadata
      require_app_store_connect_env
      require_public_https_url ALIKE_PRIVACY_URL
      require_public_https_url ALIKE_SUPPORT_URL
      run_logged "metadata_text_upload" bundle exec fastlane ios metadata_text_upload
      ;;
    upload-screenshots)
      require_no_args "$@"
      require_confirmation metadata
      require_app_store_connect_env
      require_public_https_url ALIKE_PRIVACY_URL
      require_public_https_url ALIKE_SUPPORT_URL
      run_logged "screenshots_upload" bundle exec fastlane ios screenshots_upload
      ;;
    upload-testflight)
      require_testflight_args "$@"
      require_confirmation testflight
      require_app_store_connect_env
      run_logged "release_check" "$ROOT_DIR/tools/local_ci.sh" release-check --version "$TESTFLIGHT_VERSION" --build "$TESTFLIGHT_BUILD"
      TESTFLIGHT_IPA_PATH="$(latest_release_check_ipa_path)"
      if [[ ! -f "$TESTFLIGHT_IPA_PATH" ]]; then
        printf "Expected release-check IPA not found: %s\n" "$TESTFLIGHT_IPA_PATH" >&2
        exit 65
      fi
      export ALIKE_TESTFLIGHT_IPA_PATH="$TESTFLIGHT_IPA_PATH"
      run_logged "testflight_upload" bundle exec fastlane ios testflight_upload
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

  printf "\nLocal CD command finished. Logs: %s\n" "$REPORT_DIR"
}

main "$@"
