#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bump-ios-version.sh --version X.Y.Z --build N --project path/to/project.pbxproj --check
  bump-ios-version.sh --version X.Y.Z --build N --project path/to/project.pbxproj --apply

Options:
  --version X.Y.Z   Product version for MARKETING_VERSION.
  --build N         Positive integer build number for CURRENT_PROJECT_VERSION.
  --project PATH    Xcode project.pbxproj path. Defaults to Alike/Alike.xcodeproj/project.pbxproj.
  --check           Validate that all version settings already match the requested values.
  --apply           Rewrite all matching settings, then validate.
EOF
}

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

version=""
build=""
project="Alike/Alike.xcodeproj/project.pbxproj"
mode=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || fail "--version requires a value"
      version="$2"
      shift 2
      ;;
    --build)
      [[ $# -ge 2 ]] || fail "--build requires a value"
      build="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || fail "--project requires a value"
      project="$2"
      shift 2
      ;;
    --check|--apply)
      [[ -z "$mode" ]] || fail "choose exactly one of --check or --apply"
      mode="$1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$version" ]] || fail "--version is required"
[[ -n "$build" ]] || fail "--build is required"
[[ -n "$mode" ]] || fail "choose exactly one of --check or --apply"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--version must use X.Y.Z numeric format"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "--build must be a positive integer"
[[ -f "$project" ]] || fail "project file not found: $project"

count_key() {
  local key="$1"
  awk -v key="$key" '$1 == key && $2 == "=" { count += 1 } END { print count + 0 }' "$project"
}

unique_values() {
  local key="$1"
  awk -v key="$key" '$1 == key && $2 == "=" { value = $3; sub(/;$/, "", value); print value }' "$project" | sort -u
}

assert_key_present() {
  local key="$1"
  local count
  count="$(count_key "$key")"
  [[ "$count" -gt 0 ]] || fail "no $key settings found in $project"
}

assert_value() {
  local key="$1"
  local expected="$2"
  local values
  local count
  local current

  values="$(unique_values "$key")"
  count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$count" -eq 1 ]] || fail "$key has inconsistent values: $(printf '%s' "$values" | tr '\n' ' ')"

  current="$(printf '%s\n' "$values" | sed -n '1p')"
  [[ "$current" == "$expected" ]] || fail "$key is $current, expected $expected"
}

validate_expected_values() {
  assert_key_present "MARKETING_VERSION"
  assert_key_present "CURRENT_PROJECT_VERSION"
  assert_value "MARKETING_VERSION" "$version"
  assert_value "CURRENT_PROJECT_VERSION" "$build"
}

assert_key_present "MARKETING_VERSION"
assert_key_present "CURRENT_PROJECT_VERSION"

if [[ "$mode" == "--apply" ]]; then
  perl -0pi -e 's/(MARKETING_VERSION = )[^;]+(;)/${1}'"$version"'${2}/g; s/(CURRENT_PROJECT_VERSION = )[^;]+(;)/${1}'"$build"'${2}/g' "$project"
fi

validate_expected_values

printf 'OK: MARKETING_VERSION=%s CURRENT_PROJECT_VERSION=%s in %s\n' "$version" "$build" "$project"
