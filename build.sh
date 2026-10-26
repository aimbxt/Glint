#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache Glint.app/Contents/MacOS Glint.app/Contents/Resources
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
swiftc -D GLINT_CLI_BUILD -parse-as-library -swift-version 5 -O \
    -target "$ARCH-apple-macosx15.0" -sdk "$SDK_PATH" \
    -module-cache-path "$PWD/build/module-cache" \
    -module-name Glint Sources/*.swift \
    -o Glint.app/Contents/MacOS/Glint
cp Info.plist Glint.app/Contents/Info.plist
cp -R Resources/Fonts Glint.app/Contents/Resources/
if [ -f Resources/Glint.icns ]; then cp Resources/Glint.icns Glint.app/Contents/Resources/; fi
codesign --force --sign - Glint.app
echo "Built: $PWD/Glint.app"
