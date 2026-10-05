#!/usr/bin/env bash
# Native focus, window-order and hover regressions. Never loads a vault or user settings.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f Editor/dist/index.html ]]; then
    (cd Editor && node build.mjs >/dev/null)
fi

swift build --target PaneKit
BIN="$(swift build --show-bin-path)"
mkdir -p .build/window-probe
pane_test_sources=()
for pane_source in Sources/Pane/*.swift Sources/Pane/Settings/*.swift; do
    if [[ "$pane_source" != */main.swift ]]; then pane_test_sources+=("$pane_source"); fi
done
swiftc -swift-version 6 -parse-as-library -I "$BIN/Modules" \
    "${pane_test_sources[@]}" Scripts/window-probe.swift Scripts/focus-probe.swift \
    "$BIN"/PaneKit.build/*.o \
    -o .build/window-probe/window-probe
export PANE_EDITOR_HTML="$PWD/Editor/dist/index.html"
exec .build/window-probe/window-probe
