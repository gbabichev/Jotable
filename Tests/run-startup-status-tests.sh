#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$(mktemp -d /tmp/jotable-startup-tests.XXXXXX)"
trap 'rm -rf "$task_build"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -module-cache-path "$task_build/ModuleCache" \
    "$task_root/Jotable/Utilities/CloudSyncStatus.swift" \
    "$task_root/Tests/CloudSyncStatusTests.swift" \
    -o "$task_build/startup-status-tests"
"$task_build/startup-status-tests"
