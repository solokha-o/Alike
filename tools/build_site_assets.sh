#!/usr/bin/env bash
# Regenerate the landing page image assets from the app's own artwork.
#
# The mascot illustrations shipped in DesignSystem are 400KB-1MB PNGs sized for
# @3x Retina displays. The site needs much smaller renditions, so this script
# downscales each one to its display size and emits an AVIF (roughly a tenth of
# the size) alongside a PNG fallback.
#
# Requires only macOS `sips`. Run from the repository root:
#   tools/build_site_assets.sh
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT_DIR/Packages/DesignSystem/Sources/DesignSystem/Resources"
APP_ICON="$ROOT_DIR/Alike/Alike/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
OUT="$ROOT_DIR/site/assets/img"

if ! command -v sips >/dev/null 2>&1; then
  printf 'sips is required (macOS only).\n' >&2
  exit 65
fi

mkdir -p "$OUT"

# name|source png|1x display width
ILLUSTRATIONS=(
  "hero|$RESOURCES/WelcomeHero/AlikeWelcomeHero@3x.png|420"
  "step-scan|$RESOURCES/ScannerSearching/AlikeScannerSearching@3x.png|240"
  "step-review|$RESOURCES/BestShot/AlikeBestShot@3x.png|240"
  "step-clean|$RESOURCES/CleanupSuccess/AlikeCleanupSuccess@3x.png|240"
  "privacy|$RESOURCES/ScannerIdleAllCaughtUp/AlikeScannerIdleAllCaughtUp@3x.png|300"
  "progress|$RESOURCES/CleanupProgress/AlikeCleanupProgress@3x.png|240"
)

# AVIF is the primary format at both densities. The PNG fallback is emitted at
# 1x only: `<picture>` downloads exactly one source, so the fallback is served
# solely to browsers without AVIF support, and a 470KB @2x PNG is not worth
# shipping for that minority.
avif_at() {
  local source="$1" target="$2" width="$3" scratch
  scratch="$(mktemp -t alike-site-asset).png"
  sips -Z "$width" "$source" --out "$scratch" >/dev/null
  sips -s format avif "$scratch" --out "$OUT/$target.avif" >/dev/null
  rm -f "$scratch"
}

for entry in "${ILLUSTRATIONS[@]}"; do
  IFS='|' read -r name source width <<< "$entry"

  if [[ ! -f "$source" ]]; then
    printf 'Missing source artwork: %s\n' "$source" >&2
    exit 66
  fi

  avif_at "$source" "$name" "$width"
  avif_at "$source" "$name@2x" "$((width * 2))"
  sips -Z "$width" "$source" --out "$OUT/$name.png" >/dev/null
  printf 'built %-14s avif %sw/%sw + png %sw\n' "$name" "$width" "$((width * 2))" "$width"
done

# App icon: site mark, apple-touch-icon, favicon, and social card.
avif_at "$APP_ICON" "icon" 96
avif_at "$APP_ICON" "icon@2x" 192
sips -Z 96 "$APP_ICON" --out "$OUT/icon.png" >/dev/null
sips -Z 180 "$APP_ICON" --out "$OUT/apple-touch-icon.png" >/dev/null
sips -Z 32 "$APP_ICON" --out "$OUT/favicon-32.png" >/dev/null
# JPEG for the social card: no transparency needed and every scraper reads it.
sips -Z 1024 -s format jpeg -s formatOptions 80 "$APP_ICON" --out "$OUT/og-image.jpg" >/dev/null
printf 'built %-14s icon, apple-touch-icon, favicon, og-image\n' "app icon"

printf '\nTotal: %s\n' "$(du -sh "$OUT" | cut -f1)"
