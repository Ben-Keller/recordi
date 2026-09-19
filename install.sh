#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCAL_HOME="${RECORDI_HOME:-$HOME}"
[[ "$(uname -s)" == Darwin ]] || { echo 'Recordi requires macOS.' >&2; exit 1; }
TEST_MODE=0
if [[ "${1:-}" == --test-install ]]; then
  [[ -n "${RECORDI_HOME:-}" && "$RECORDI_HOME" != "$HOME" ]] || { echo 'Test installation needs an isolated RECORDI_HOME.' >&2; exit 1; }
  TEST_MODE=1
elif [[ $# -gt 0 ]]; then echo 'Usage: ./install.sh [--test-install]' >&2; exit 1; fi
APP="$LOCAL_HOME/Applications/Recordi.app"
SUPPORT="$LOCAL_HOME/Library/Application Support/Recordi"
AH="${RECORDI_AUDIO_HIJACK:-}"
if [[ -z "$AH" ]]; then
  for CANDIDATE in '/Applications/Audio Hijack.app' "$HOME/Applications/Audio Hijack.app" "$HOME/Downloads/Audio Hijack.app"; do
    if [[ -d "$CANDIDATE" ]]; then AH="$CANDIDATE"; break; fi
  done
fi
if [[ "$TEST_MODE" == 0 && ! -d "$AH" ]]; then echo 'Install Audio Hijack, or run with RECORDI_AUDIO_HIJACK pointing to its .app.' >&2; exit 1; fi
WHISPER="$(command -v whisper-cli || true)"
if [[ -z "$WHISPER" ]]; then
  BREW="$(command -v brew || true)"
  if [[ -z "$BREW" ]]; then echo 'Install Homebrew from https://brew.sh, then rerun ./install.sh.' >&2; exit 1; fi
  HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" install whisper.cpp
  WHISPER="$(command -v whisper-cli || true)"
  [[ -n "$WHISPER" ]] || WHISPER="$($BREW --prefix)/bin/whisper-cli"
fi
HELP="$("$WHISPER" --help 2>&1)"
if ! /usr/bin/grep -q 'supported audio formats: flac' <<< "$HELP"; then
  if ! command -v ffmpeg >/dev/null; then
    command -v brew >/dev/null || { echo 'This Whisper build needs ffmpeg. Install Homebrew, then rerun.' >&2; exit 1; }
    HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg
  fi
fi
if [[ "$TEST_MODE" == 0 ]]; then "$ROOT/scripts/build.sh"; fi
[[ -x "$ROOT/.build/Recordi.app/Contents/MacOS/Recordi" ]] || { echo 'Run scripts/build.sh first.' >&2; exit 1; }
if [[ "$TEST_MODE" == 0 ]]; then "$ROOT/.build/Recordi.app/Contents/MacOS/Recordi" --quit-app; fi
mkdir -p "$LOCAL_HOME/Applications" "$SUPPORT"
# Replace only the app owned by this project; preserve data and model.
if [[ -e "$APP" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == local.recordi.app ]] || { echo 'Refusing to replace an unrelated app.' >&2; exit 1; }
fi
/usr/bin/ditto "$ROOT/.build/Recordi.app" "$APP"
EXE="$APP/Contents/MacOS/Recordi"
MODEL="${RECORDI_MODEL:-$SUPPORT/models/ggml-large-v3-turbo.bin}"
if [[ "$TEST_MODE" == 0 ]]; then "$ROOT/scripts/model.sh" "$MODEL"; fi
"$EXE" --configure "$WHISPER" "${AH:-/nonexistent/Audio Hijack.app}" "$MODEL"
if [[ "$TEST_MODE" == 0 ]]; then
  "$ROOT/scripts/smoke-transcription.sh" "$EXE" "$WHISPER" "$MODEL" "$AH"
  "$EXE" --diagnose
  "$EXE" --enable-login || echo 'Enable Launch at Login from the Recordi menu if desired.'
  if ! "$EXE" --status; then echo 'Audio Hijack control needs one-time setup; see README.md.'; fi
  /usr/bin/open "$APP"
  printf '\nRemaining setup: configure Meeting Recorder audio routing, enable external scripts, attach Recording Stop script, and approve requested macOS permissions. See README.md.\n'
fi
