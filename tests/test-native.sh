#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$project_dir"
work_dir="$project_dir/work/accentbar"
mkdir -p "$work_dir"
flags=(-swift-version 5 -module-cache-path "$work_dir/module-cache")
/usr/bin/xcrun swiftc "${flags[@]}" src/AccentBar/TargetSelection.swift tests/TargetSelectionTests.swift -o "$work_dir/target-selection-tests"
"$work_dir/target-selection-tests"
/usr/bin/xcrun swiftc "${flags[@]}" src/AccentBar/ChromeAutomation.swift tests/ChromeColorTests.swift -o "$work_dir/chrome-color-tests"
"$work_dir/chrome-color-tests"
/usr/bin/xcrun swiftc "${flags[@]}" src/AccentBar/Models.swift src/AccentBar/SettingsDocuments.swift \
    src/AccentBar/NativeSettings.swift src/AccentBar/ChromeAutomation.swift tests/NativeSettingsTests.swift -o "$work_dir/native-settings-tests"
"$work_dir/native-settings-tests" "$project_dir/src/AccentBar/Presets"
