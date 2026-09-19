#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/recordi-launch.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
export RECORDI_HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/Documents/Recordi/recordings"
cp "$ROOT/tests/fixtures/jfk.flac" "$TEST_HOME/Documents/Recordi/recordings/Recovery fixture.flac"
touch -t 202601010000 "$TEST_HOME/Documents/Recordi/recordings/Recovery fixture.flac"
# The app executes its actual AppKit lifecycle and Diagnostics panel, but does not invoke Audio Hijack.
RECORDI_SMOKE_TEST=1 "$ROOT/.build/Recordi.app/Contents/MacOS/Recordi"
STATE="$TEST_HOME/Library/Application Support/Recordi/state"
/usr/bin/grep -q 'Open Recordi Folder' "$STATE/launch-smoke.json"
/usr/bin/grep -q 'Open Latest Transcript' "$STATE/launch-smoke.json"
[[ "$(/usr/bin/plutil -extract windowCreated raw "$STATE/diagnostics-smoke.json")" == true ]]
[[ "$(/usr/bin/plutil -extract textMatches raw "$STATE/diagnostics-smoke.json")" == true ]]
[[ "$(/usr/bin/plutil -extract recoveredOnStatusTick raw "$STATE/recovery-smoke.json")" == true ]]
printf 'PASS native AppKit launch, menu, Diagnostics, recovery/status timer regression and clean quit\n'
