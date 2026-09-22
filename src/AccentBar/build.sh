#!/bin/bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
project_dir="$(cd -- "$source_dir/../.." && pwd)"
source "$project_dir/config/release.env"
source "$project_dir/scripts/sparkle.sh"
ensure_sparkle
work_dir="$project_dir/work/accentbar"
app_path="$project_dir/outputs/TintLink.app"
mkdir -p "$work_dir" "$project_dir/outputs"
stage_dir="$(mktemp -d "$work_dir/build-XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
stage_app="$stage_dir/TintLink.app"
mkdir -p "$stage_app/Contents/MacOS" "$stage_app/Contents/Resources"
cat > "$stage_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.chan.accentbar</string>
<key>CFBundleName</key><string>TintLink</string>
<key>CFBundleDisplayName</key><string>TintLink</string>
<key>CFBundleExecutable</key><string>TintLink</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>TintLink</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $TINTLINK_VERSION" "$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $TINTLINK_BUILD_NUMBER" "$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $TINTLINK_FEED_URL" "$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $TINTLINK_PUBLIC_ED_KEY" "$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUVerifyUpdateBeforeExtraction bool true' "$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SURequireSignedFeed bool true' "$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUAllowsAutomaticUpdates bool false' "$stage_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUSendProfileInfo bool false' "$stage_app/Contents/Info.plist"
mkdir -p "$stage_app/Contents/Frameworks"
/usr/bin/ditto "$sparkle_dir/Sparkle.framework" "$stage_app/Contents/Frameworks/Sparkle.framework"
/bin/cp "$sparkle_dir/LICENSE" "$stage_app/Contents/Resources/Sparkle-LICENSE.txt"
for color in blue lavender pink red orange yellow green; do
    cp "$source_dir/Presets/preset-$color.json" "$stage_app/Contents/Resources/"
done
swift_flags=(-O -swift-version 5 -target arm64-apple-macosx13.0 -module-cache-path "$work_dir/module-cache")
/usr/bin/xcrun swiftc "${swift_flags[@]}" -F "$sparkle_dir" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks -parse-as-library \
    "$source_dir/AccentBar.swift" "$source_dir/Models.swift" "$source_dir/TargetSelection.swift" "$source_dir/AppUpdater.swift" \
    "$source_dir/SettingsDocuments.swift" "$source_dir/NativeSettings.swift" \
    "$source_dir/ChromeAutomation.swift" -o "$stage_app/Contents/MacOS/TintLink"
/usr/bin/xcrun swiftc "${swift_flags[@]}" "$source_dir/make_icon.swift" -o "$work_dir/make_icon"
"$work_dir/make_icon" "$work_dir/AppIcon.iconset" "$stage_app/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$stage_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$stage_app"
/usr/bin/codesign --verify --deep --strict "$stage_app"
if [[ -e "$app_path" ]]; then mv "$app_path" "$stage_dir/previous.app"; fi
if ! mv "$stage_app" "$app_path"; then
    if [[ -e "$stage_dir/previous.app" ]]; then mv "$stage_dir/previous.app" "$app_path"; fi
    exit 1
fi
printf '%s\n' "$app_path"
