#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
app_path="$project_dir/outputs/TinkLink.app"
if [[ ! -d "$app_path" ]]; then
    printf '%s\n' 'Build the app first: bash src/AccentBar/build.sh' >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_path"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
archive="TinkLink-$version-macos-arm64.zip"
stage_dir="$(/usr/bin/mktemp -d "$project_dir/outputs/.release-XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$app_path" "$stage_dir/$archive"
/usr/bin/unzip -t "$stage_dir/$archive" >/dev/null
(cd "$stage_dir" && /usr/bin/shasum -a 256 "$archive" > "$archive.sha256")
/bin/mv "$stage_dir/$archive" "$project_dir/outputs/$archive"
/bin/mv "$stage_dir/$archive.sha256" "$project_dir/outputs/$archive.sha256"
printf '%s\n' "$project_dir/outputs/$archive" "$project_dir/outputs/$archive.sha256"
