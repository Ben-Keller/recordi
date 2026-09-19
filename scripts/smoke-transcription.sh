#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="${1:?Pass Recordi executable}"
WHISPER="${2:?Pass whisper-cli}"
MODEL="${3:?Pass model}"
AH="${4:-/Applications/Audio Hijack.app}"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/recordi-transcription.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
export RECORDI_HOME="$TEST_HOME"
"$EXE" --configure "$WHISPER" "$AH" "$MODEL"
SOURCE="$TEST_HOME/Documents/Recordi/recordings/Sample ' İstanbul.flac"
cp "$ROOT/tests/fixtures/jfk.flac" "$SOURCE"
BEFORE="$(shasum -a 256 "$SOURCE")"
"$EXE" --enqueue "$SOURCE"
"$EXE" --work-one
BASE="$TEST_HOME/Documents/Recordi/transcripts/Sample ' İstanbul"
test -s "$BASE.txt"
[[ "$(find "$TEST_HOME/Documents/Recordi/transcripts" -type f | wc -l | tr -d ' ')" == 1 ]]
/usr/bin/grep -qi 'country' "$BASE.txt"
[[ "$BEFORE" == "$(shasum -a 256 "$SOURCE")" ]]
"$EXE" --enqueue "$SOURCE"
COUNT="$(find "$TEST_HOME/Library/Application Support/Recordi/queue" -name '*.json' | wc -l | tr -d ' ')"
[[ "$COUNT" == 1 ]]
printf 'Real transcription passed: model, FLAC decoding, TXT-only output, deduplication, source preservation.\n'
if [[ -n "${RECORDI_TEST_REPORT_DIR:-}" ]]; then
  mkdir -p "$RECORDI_TEST_REPORT_DIR"
  cp "$BASE.txt" "$RECORDI_TEST_REPORT_DIR/sample.txt"
  cp "$TEST_HOME/Documents/Recordi/logs/Sample ' İstanbul.log" "$RECORDI_TEST_REPORT_DIR/whisper.log"
fi
