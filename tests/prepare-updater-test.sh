#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$project_dir/config/release.env"
source "$project_dir/scripts/sparkle.sh"
ensure_sparkle
test_root="$(mktemp -d "$project_dir/work/updater-test-XXXXXX")"
test_id="local.chan.tintlink.updater-test.$(basename "$test_root" | tr '[:upper:]' '[:lower:]')"
test_port="${TINTLINK_TEST_PORT:-8123}"
mkdir -p "$test_root/installed" "$test_root/new" "$test_root/server"
app_name='TintLink Update Test.app'
new_app="$test_root/new/$app_name"
old_app="$test_root/installed/$app_name"
ditto "$project_dir/outputs/TintLink.app" "$new_app"
plist="$new_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $test_id" "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName TintLink Update Test' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName TintLink Update Test' "$plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL http://localhost:$test_port/appcast.xml" "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool false' "$plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity dict' "$plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$plist"
if [[ "${1:-}" == '--headless' ]]; then
    /usr/bin/xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$project_dir/work/accentbar/module-cache" \
        -F "$sparkle_dir" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        "$project_dir/tests/SparkleIntegrationHost.swift" -o "$new_app/Contents/MacOS/TintLink"
    /usr/libexec/PlistBuddy -c "Add :TintLinkTestLog string $test_root/result.log" "$plist"
    /usr/libexec/PlistBuddy -c "Add :TintLinkTestBuild string $TINTLINK_BUILD_NUMBER" "$plist"
fi
codesign --force --sign - "$new_app"
codesign --verify --deep --strict "$new_app"
ditto "$new_app" "$old_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0.99' "$old_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((TINTLINK_BUILD_NUMBER - 1))" "$old_app/Contents/Info.plist"
codesign --force --sign - "$old_app"
# Simulate two separately published builds, not two plist edits in one second.
# Launch Services otherwise reuses metadata for the identical binary/timestamp.
touch -t 202501010000 "$old_app/Contents/Info.plist" "$old_app/Contents" "$old_app"
ditto -c -k --keepParent --norsrc --noextattr "$new_app" "$test_root/server/update.zip"
"$sparkle_dir/bin/generate_appcast" --account "$TINTLINK_KEY_ACCOUNT" \
    --download-url-prefix "http://localhost:$test_port/" --maximum-deltas 0 "$test_root/server"
/usr/bin/xcrun swift -module-cache-path "$project_dir/work/accentbar/module-cache" \
    "$project_dir/scripts/verify-update.swift" "$test_root/server/appcast.xml" "$test_root/server/update.zip" "$TINTLINK_PUBLIC_ED_KEY"
cat > "$test_root/README.txt" <<EOF
1. Serve the server folder at http://localhost:$test_port (for example, python3 -m http.server $test_port --bind 127.0.0.1 --directory "$test_root/server"). Python is only a development test tool, not an app dependency.
2. Open "$old_app".
3. Add/remove targets and select an enabled state.
4. Choose Check for Updates in the top-right menu, install 1.1.0, and verify relaunch and saved targets.
5. Check again: the installed version should be current.
6. Quit the test app and stop the local server.
EOF
printf 'Test folder: %s\n' "$test_root"
