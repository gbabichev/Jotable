#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$(mktemp -d /tmp/jotable-legacy-tests.XXXXXX)"
trap 'rm -rf "$task_build"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor -module-name Jotable \
    -module-cache-path "$task_build/ModuleCache" \
    "$task_root/Tests/Fixtures/PreDocumentSplit/Item.swift" \
    "$task_root/Tests/Fixtures/PreDocumentSplit/Category.swift" \
    "$task_root/Tests/Fixtures/PreDocumentSplit/TodoItem.swift" \
    "$task_root/Tests/LegacyDatabaseFixtureSeed.swift" \
    -o "$task_build/seed-old-database"
"$task_build/seed-old-database" "$task_build/old-database"
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -module-name Jotable \
    -module-cache-path "$task_build/ModuleCache" \
    "$task_root/Jotable/Models/Item.swift" \
    "$task_root/Jotable/Models/Category.swift" \
    "$task_root/Jotable/Models/TodoItem.swift" \
    "$task_root/Jotable/Models/NoteDocument.swift" \
    "$task_root/Jotable/Utilities/NoteDocumentStore.swift" \
    "$task_root/Tests/LegacyNotePersistenceTests.swift" \
    -o "$task_build/legacy-note-tests"
"$task_build/legacy-note-tests" "$task_build/old-database"
