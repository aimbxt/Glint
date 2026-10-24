#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
swiftc -D GLINT_CLI_BUILD -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx15.0" \
    -module-cache-path "$PWD/build/module-cache" \
    Sources/TaskStore.swift Sources/WindowGeometry.swift Tests/TaskStoreTests.swift \
    -o build/GlintTests
build/GlintTests
