#!/bin/bash
# Run on an Apple Silicon Mac with an existing model; never touch the real installation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:-$ROOT/.build/download/Recordi-Apple-Silicon.zip}"
MODEL="${2:-$HOME/Library/Application Support/Recordi/models/ggml-large-v3-turbo.bin}"
AH="${RECORDI_AUDIO_HIJACK:-/Applications/Audio Hijack.app}"
if [[ ! -d "$AH" && -d "$HOME/Downloads/Audio Hijack.app" ]]; then AH="$HOME/Downloads/Audio Hijack.app"; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/recordi-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
/usr/bin/ditto -x -k "$ZIP" "$WORK/Unpacked elsewhere"
PACKAGE="$WORK/Unpacked elsewhere/Recordi Setup"
APP="$PACKAGE/Recordi.app"
/usr/bin/codesign --verify --deep --strict "$APP"
[[ -s "$APP/Contents/Resources/Licenses/miniaudio.txt" ]]
[[ -s "$APP/Contents/Resources/Licenses/whisper.cpp.txt" ]]
[[ -x "$PACKAGE/Set Up Recordi.command" ]]
[[ ! -e "$PACKAGE/ggml-large-v3-turbo.bin" ]]
if /usr/bin/otool -L "$APP/Contents/Helpers/whisper-cli" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' ; then exit 1; fi
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export RECORDI_HOME="$WORK/Test home ü"
export RECORDI_SETUP_TEST=1
export RECORDI_AUDIO_HIJACK="$AH"
export RECORDI_MODEL_SOURCE="$MODEL"
/bin/bash "$PACKAGE/scripts/setup-packaged.sh"
DATA="$RECORDI_HOME/Documents/Recordi"
printf 'preserve audio' > "$DATA/recordings/keep.mp3"
printf 'preserve transcript' > "$DATA/transcripts/keep.txt"
BEFORE="$(shasum -a 256 "$RECORDI_HOME/Library/Application Support/Recordi/models/ggml-large-v3-turbo.bin")"
# A verified installed model must be reused even if the supplied copy is unavailable.
export RECORDI_MODEL_SOURCE="$WORK/not-a-model"
/bin/bash "$PACKAGE/scripts/setup-packaged.sh"
[[ "$(cat "$DATA/recordings/keep.mp3")" == 'preserve audio' ]]
[[ "$(cat "$DATA/transcripts/keep.txt")" == 'preserve transcript' ]]
[[ "$BEFORE" == "$(shasum -a 256 "$RECORDI_HOME/Library/Application Support/Recordi/models/ggml-large-v3-turbo.bin")" ]]
CONFIG="$RECORDI_HOME/Library/Application Support/Recordi/config.json"
[[ "$(plutil -extract whisper raw "$CONFIG")" == "$RECORDI_HOME/Applications/Recordi.app/Contents/Helpers/whisper-cli" ]]
# Invalid model input must fail before installing anything or downloading in tests.
export RECORDI_HOME="$WORK/Invalid model home"
printf 'bad model' > "$WORK/bad.bin"
export RECORDI_MODEL_SOURCE="$WORK/bad.bin"
if /bin/bash "$PACKAGE/scripts/setup-packaged.sh" > "$WORK/invalid.log" 2>&1; then echo 'Accepted invalid model' >&2; exit 1; fi
[[ ! -e "$RECORDI_HOME/Applications/Recordi.app" ]]
grep -q 'not the expected model' "$WORK/invalid.log"
printf 'PASS relocated ZIP, bundled dependencies, real MP3/FLAC transcription, model import/reuse, repeat setup, data preservation and invalid-model rejection.\n'
