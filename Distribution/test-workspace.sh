#!/bin/bash
set -euo pipefail
qa_root="$(cd "$(dirname "$0")/.." && pwd)"
qa_build="$(mktemp -d /tmp/notepadplus-workspace-tests.XXXXXX)"
trap 'rm -rf "$qa_build"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
    -module-cache-path /tmp/notepadplus-workspace-module-cache \
    "$qa_root/NotepadPlus/SharedCore/EditorCore.swift" \
    "$qa_root/NotepadPlus/SharedCore/GroupHierarchy.swift" \
    "$qa_root/NotepadPlus/Models/EditorDocument.swift" \
    "$qa_root/NotepadPlus/Services/WorkspaceStore.swift" \
    "$qa_root/Tests/WorkspaceIntegration/UIStubs.swift" \
    "$qa_root/Tests/WorkspaceIntegration/WorkspaceRegression.swift" \
    -o "$qa_build/workspace-tests"
"$qa_build/workspace-tests"
