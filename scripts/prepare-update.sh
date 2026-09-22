#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$project_dir/config/release.env"
source "$project_dir/scripts/sparkle.sh"
ensure_sparkle
app="$project_dir/outputs/TintLink.app"
archive="TintLink-$TINTLINK_VERSION-macos-arm64.zip"
notes="$project_dir/docs/releases/v$TINTLINK_VERSION.md"
[[ -f "$notes" ]] || { printf 'Missing release notes: %s\n' "$notes" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$TINTLINK_BUILD_NUMBER" ]] || { printf '%s\n' 'Build the current version first.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$TINTLINK_VERSION" ]] || { printf '%s\n' 'The built app version does not match release.env.' >&2; exit 1; }
[[ "$("$sparkle_dir/bin/generate_keys" --account "$TINTLINK_KEY_ACCOUNT" -p)" == "$TINTLINK_PUBLIC_ED_KEY" ]] || { printf '%s\n' 'The signing key does not match the app public key.' >&2; exit 1; }
bash "$project_dir/scripts/package-release.sh"
staging="$(mktemp -d "$project_dir/outputs/.appcast-XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp "$project_dir/outputs/$archive" "$staging/$archive"
cp "$notes" "$staging/${archive%.zip}.md"
mkdir -p "$project_dir/updates"
if [[ -f "$project_dir/updates/appcast.xml" ]]; then cp "$project_dir/updates/appcast.xml" "$staging/appcast.xml"; fi
"$sparkle_dir/bin/generate_appcast" --account "$TINTLINK_KEY_ACCOUNT" \
    --download-url-prefix "https://github.com/youngchan2/tintlink/releases/download/v$TINTLINK_VERSION/" \
    --full-release-notes-url "https://github.com/youngchan2/tintlink/releases/tag/v$TINTLINK_VERSION" \
    --link https://github.com/youngchan2/tintlink --embed-release-notes --maximum-deltas 0 "$staging"
/usr/bin/xcrun swift -module-cache-path "$project_dir/work/accentbar/module-cache" \
    "$project_dir/scripts/verify-update.swift" "$staging/appcast.xml" "$staging/$archive" "$TINTLINK_PUBLIC_ED_KEY"
cp "$staging/appcast.xml" "$project_dir/updates/appcast.xml"
printf '%s\n' 'Upload the ZIP to its release before publishing updates/appcast.xml.'
