#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Alike/Alike.xcodeproj/project.pbxproj"
DEFAULT_ENV_FILE="$ROOT_DIR/.env"
DEFAULT_CLANG_CACHE="/private/tmp/alike-local-ci-clang-cache"
SHORTCUT="${1:-}"

usage() {
  cat <<'USAGE'
Usage:
  tools/quick
  tools/full
  tools/release-check [X.Y.Z] [N]
  tools/meta
  tools/upload
  tools/text
  tools/upload-build [X.Y.Z] [N]
  tools/upload-screenshots

Behavior:
  - Loads .env automatically when present. Disable with ALIKE_NO_ENV=1.
  - Uses CLANG_MODULE_CACHE_PATH=/private/tmp/alike-local-ci-clang-cache by default.
  - Upload shortcuts ask for interactive confirmation unless ALIKE_ASSUME_YES=1.
  - release-check and upload-build infer version/build from project.pbxproj when omitted.
USAGE
}

load_env_if_present() {
  if [[ "${ALIKE_NO_ENV:-0}" == "1" ]]; then
    return
  fi

  if [[ -f "$DEFAULT_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$DEFAULT_ENV_FILE"
    set +a
  fi
}

ensure_clang_cache() {
  export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$DEFAULT_CLANG_CACHE}"
}

project_value() {
  local key="$1"

  python3 - "$PROJECT_FILE" "$key" <<'PY'
import pathlib
import re
import sys

project = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
key = re.escape(sys.argv[2])
values = {
    value.strip().strip('"')
    for value in re.findall(rf"{key}\s*=\s*([^;]+);", project)
}
if len(values) != 1:
    found = ", ".join(sorted(values)) if values else "none"
    raise SystemExit(f"Expected exactly one {sys.argv[2]} value in {sys.argv[1]}, found {found}")
print(next(iter(values)))
PY
}

resolve_version_build() {
  RESOLVED_VERSION="${1:-}"
  RESOLVED_BUILD="${2:-}"

  if [[ -z "$RESOLVED_VERSION" ]]; then
    RESOLVED_VERSION="$(project_value MARKETING_VERSION)"
  fi

  if [[ -z "$RESOLVED_BUILD" ]]; then
    RESOLVED_BUILD="$(project_value CURRENT_PROJECT_VERSION)"
  fi
}

confirm_upload() {
  local action="$1"

  if [[ "${ALIKE_ASSUME_YES:-0}" == "1" ]]; then
    return
  fi

  printf "%s\n" "$action"
  printf "Type yes to continue: "

  local answer=""
  read -r answer
  if [[ "$answer" != "yes" ]]; then
    printf "Cancelled.\n" >&2
    exit 1
  fi
}

run_quick() {
  ensure_clang_cache
  exec "$ROOT_DIR/tools/local_ci.sh" quick
}

run_full() {
  ensure_clang_cache
  exec "$ROOT_DIR/tools/local_ci.sh" full
}

run_release_check() {
  ensure_clang_cache
  resolve_version_build "${1:-}" "${2:-}"
  exec "$ROOT_DIR/tools/local_ci.sh" release-check --version "$RESOLVED_VERSION" --build "$RESOLVED_BUILD"
}

run_meta() {
  load_env_if_present

  if [[ -n "${ALIKE_PRIVACY_URL:-}" && -n "${ALIKE_SUPPORT_URL:-}" ]]; then
    exec bundle exec fastlane ios metadata_validate
  fi

  exec python3 "$ROOT_DIR/tools/prepare_app_store_upload_bundle.py" --allow-placeholder-urls
}

run_upload() {
  load_env_if_present
  confirm_upload "Upload metadata and screenshots to App Store Connect."
  export ALIKE_CONFIRM_UPLOAD=metadata
  exec "$ROOT_DIR/tools/local_cd.sh" upload-metadata
}

run_text() {
  load_env_if_present
  confirm_upload "Upload text metadata and App Review information to App Store Connect."
  export ALIKE_CONFIRM_UPLOAD=metadata
  exec "$ROOT_DIR/tools/local_cd.sh" upload-text-metadata
}

run_upload_build() {
  load_env_if_present
  ensure_clang_cache
  resolve_version_build "${1:-}" "${2:-}"
  confirm_upload "Upload TestFlight build version $RESOLVED_VERSION ($RESOLVED_BUILD)."
  export ALIKE_CONFIRM_UPLOAD=testflight
  exec "$ROOT_DIR/tools/local_cd.sh" upload-testflight --version "$RESOLVED_VERSION" --build "$RESOLVED_BUILD"
}

run_upload_screenshots() {
  load_env_if_present
  confirm_upload "Upload screenshots to App Store Connect."
  export ALIKE_CONFIRM_UPLOAD=metadata
  exec "$ROOT_DIR/tools/local_cd.sh" upload-screenshots
}

main() {
  cd "$ROOT_DIR"

  case "$SHORTCUT" in
    quick)
      run_quick
      ;;
    full)
      run_full
      ;;
    release-check)
      shift
      run_release_check "${1:-}" "${2:-}"
      ;;
    meta)
      run_meta
      ;;
    upload)
      run_upload
      ;;
    text)
      run_text
      ;;
    upload-build)
      shift
      run_upload_build "${1:-}" "${2:-}"
      ;;
    upload-screenshots)
      run_upload_screenshots
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      printf "Unknown shortcut: %s\n" "$SHORTCUT" >&2
      usage >&2
      exit 64
      ;;
  esac
}

main "$@"
