#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_HOME="${RECORDI_HOME:-$HOME}"
TEST_MODE="${RECORDI_SETUP_TEST:-0}"
source "$ROOT/scripts/setup-common.sh"
if [[ "$TEST_MODE" != 0 ]]; then
  [[ -n "${RECORDI_HOME:-}" && "$LOCAL_HOME" != "$HOME" ]] || { echo 'Tests require an isolated RECORDI_HOME.' >&2; exit 1; }
fi
[[ "$(uname -s)" == Darwin ]] || { echo 'Recordi requires macOS.' >&2; exit 1; }
[[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || { echo 'This download is for Apple Silicon Macs (M1 or later). Intel Macs need the source installation.' >&2; exit 1; }
[[ "$(/usr/bin/sw_vers -productVersion | cut -d. -f1)" -ge 13 ]] || { echo 'Recordi requires macOS 13 or later.' >&2; exit 1; }
BUNDLE="$ROOT/Recordi.app"
APP="$LOCAL_HOME/Applications/Recordi.app"
SUPPORT="$LOCAL_HOME/Library/Application Support/Recordi"
mkdir -p "$SUPPORT"
LOG="$SUPPORT/setup.log"
# Append each attempt; preserve the original error even if the Terminal window is closed.
exec > >(/usr/bin/tee -a "$LOG") 2>&1
printf '\n=== Recordi setup %s ===\nLog: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$LOG"
MODEL="$SUPPORT/models/ggml-large-v3-turbo.bin"
EXPECTED=1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69
check_model() { [[ -f "$MODEL" ]] && [[ "$(/usr/bin/shasum -a 256 "$MODEL" | cut -d' ' -f1)" == "$EXPECTED" ]]; }
[[ -x "$BUNDLE/Contents/Helpers/whisper-cli" ]] || { echo 'The setup folder is incomplete. Extract the whole ZIP and try again.' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$BUNDLE"
AH="${RECORDI_AUDIO_HIJACK:-}"
if [[ -z "$AH" ]]; then
  for candidate in '/Applications/Audio Hijack.app' "$HOME/Applications/Audio Hijack.app" "$HOME/Downloads/Audio Hijack.app"; do
    if [[ -d "$candidate" ]]; then AH="$candidate"; break; fi
  done
fi
if [[ ! -d "$AH" ]]; then
  echo 'Install Audio Hijack in Applications, then run Set Up Recordi again.'
  if [[ "$TEST_MODE" == 0 ]]; then /usr/bin/open 'https://rogueamoeba.com/audiohijack/'; fi
  exit 1
fi
printf 'Setting up Recordi. No Homebrew, developer tools, or signing certificate is needed.\n'
if ! check_model; then
  SOURCE="${RECORDI_MODEL_SOURCE:-}"
  if [[ -z "$SOURCE" && -f "$ROOT/ggml-large-v3-turbo.bin" ]]; then SOURCE="$ROOT/ggml-large-v3-turbo.bin"; fi
  if [[ -z "$SOURCE" && "$TEST_MODE" == 0 ]]; then
    CHOICE="$(/usr/bin/osascript <<'APPLESCRIPT'
button returned of (display dialog "Recordi needs a 1.6 GB speech model. Download it once, or choose ggml-large-v3-turbo.bin copied from your other Mac." with title "Set Up Recordi" buttons {"Cancel", "Use Existing File", "Download"} default button "Download" cancel button "Cancel")
APPLESCRIPT
)"
    if [[ "$CHOICE" == 'Use Existing File' ]]; then
      SOURCE="$(/usr/bin/osascript -e 'POSIX path of (choose file with prompt "Choose ggml-large-v3-turbo.bin from your other Mac")')"
    fi
  fi
  if [[ -n "$SOURCE" ]]; then
    echo 'Checking the copied model…'
    [[ -f "$SOURCE" && "$(/usr/bin/shasum -a 256 "$SOURCE" | cut -d' ' -f1)" == "$EXPECTED" ]] || { echo 'That is not the expected model. Choose ggml-large-v3-turbo.bin, or select Download on the next attempt.' >&2; exit 1; }
    mkdir -p "$(dirname "$MODEL")"
    /bin/cp "$SOURCE" "$MODEL.part"
  elif [[ "$TEST_MODE" != 0 ]]; then
    echo 'An isolated test needs RECORDI_MODEL_SOURCE; downloads are disabled in test mode.' >&2; exit 1
  else
    echo 'Downloading the model (about 1.6 GB). Interrupted downloads can resume on the next attempt.'
  fi
  "$ROOT/scripts/model.sh" "$MODEL"
else
  echo 'Using the model already installed on this Mac.'
fi
mkdir -p "$LOCAL_HOME/Applications"
if [[ -e "$APP" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == local.recordi.app ]] || { echo 'An unrelated app occupies the install location. Nothing was replaced.' >&2; exit 1; }
fi
# Test homes must never quit the real user's app.
if [[ "$TEST_MODE" == 0 && -x "$APP/Contents/MacOS/Recordi" ]]; then
  setup_step 'Close the installed Recordi app' "$APP/Contents/MacOS/Recordi" --quit-app
fi
/usr/bin/ditto "$BUNDLE" "$APP"
EXE="$APP/Contents/MacOS/Recordi"
WHISPER="$APP/Contents/Helpers/whisper-cli"
configure_and_verify() {
  "$EXE" --configure "$WHISPER" "$AH" "$MODEL" || return $?
  verify_setup_files "$SUPPORT"
}
setup_step 'Configure Recordi and generate Audio Hijack scripts' configure_and_verify
echo 'Checking transcription using public sample audio (no microphone recording)…'
setup_step 'Verify sample transcription' "$ROOT/scripts/smoke-transcription.sh" "$EXE" "$WHISPER" "$MODEL" "$AH"
verify_setup_files "$SUPPORT"
printf 'Setup verified. Audio Hijack scripts are ready in:\n%s/commands/\n' "$SUPPORT"
echo 'Recordi is installed. Follow the included Audio Hijack setup guide to finish.'
if [[ "$TEST_MODE" == 0 ]]; then
  setup_step 'Open Recordi' /usr/bin/open "$APP"
  /usr/bin/open "$ROOT/Start Here.html" || echo 'Open Start Here.html in the setup folder for the remaining Audio Hijack instructions.'
fi
