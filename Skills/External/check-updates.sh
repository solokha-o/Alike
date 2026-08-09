#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT_DIR/Skills/External/external-skills.tsv"
STATE_FILE="${ALIKE_EXTERNAL_SKILL_STATE:-$ROOT_DIR/.codex/external-skill-update-state}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing manifest: $MANIFEST" >&2
  exit 1
fi

mkdir -p "$(dirname "$STATE_FILE")"

printf "%-24s %-42s %-12s %s\n" "skill" "repo" "status" "remote_sha"
printf "%-24s %-42s %-12s %s\n" "------------------------" "------------------------------------------" "------------" "----------------------------------------"

has_update=0

while IFS=$'\t' read -r name repo upstream_path branch pinned_sha; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue

  remote_sha="$(git ls-remote "https://github.com/${repo}.git" "refs/heads/${branch}" | awk '{print $1}')"

  if [[ -z "$remote_sha" ]]; then
    printf "%-24s %-42s %-12s %s\n" "$name" "$repo" "missing" "-"
    has_update=1
    continue
  fi

  if [[ "$remote_sha" == "$pinned_sha" ]]; then
    printf "%-24s %-42s %-12s %s\n" "$name" "$repo" "current" "$remote_sha"
  else
    printf "%-24s %-42s %-12s %s\n" "$name" "$repo" "update" "$remote_sha"
    has_update=1
  fi
done < "$MANIFEST"

date -u +"last_checked_at=%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

exit "$has_update"
