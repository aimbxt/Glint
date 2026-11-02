#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUNDLE="$PWD/build/GlintFeedbackChecks.app"
mkdir -p "$BUNDLE/Contents/MacOS" build/module-cache
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.glint.feedback-checks</string>
<key>CFBundleExecutable</key><string>GlintFeedbackChecks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -D GLINT_CLI_BUILD -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx15.0" -module-cache-path "$PWD/build/module-cache" \
    Sources/TaskStore.swift Sources/WindowGeometry.swift Sources/PanelState.swift Sources/Snapping.swift \
    Sources/PixelTheme.swift Sources/CompletionFeedback.swift Sources/Preferences.swift \
    Sources/SettingsView.swift Sources/PanelController.swift Sources/TodoView.swift Tests/CompletionFeedbackTests.swift \
    -o "$BUNDLE/Contents/MacOS/GlintFeedbackChecks"
codesign --force --sign - "$BUNDLE"
if [[ "${1:-}" == "--build-only" ]]; then echo "Built feedback checks: $BUNDLE"; exit 0; fi
rm -f build/completion-feedback-result.txt
open -W "$BUNDLE"
cat build/completion-feedback-result.txt
grep -q '^Passed ' build/completion-feedback-result.txt
