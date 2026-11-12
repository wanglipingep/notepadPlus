#!/bin/bash
set -euo pipefail
preview_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_build="$(mktemp -d /tmp/notepadplus-preview-tests.XXXXXX)"
trap 'rm -rf "$preview_build"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path /tmp/notepadplus-preview-module-cache \
    "$preview_root/NotepadPlus/SharedCore/MarkdownPreviewCore.swift" \
    "$preview_root/Tests/PreviewIntegration/MarkdownWebKitRegression.swift" \
    -o "$preview_build/preview-tests"
"$preview_build/preview-tests"
