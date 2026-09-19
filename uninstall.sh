#!/bin/bash
set -euo pipefail
LOCAL_HOME="${RECORDI_HOME:-$HOME}"
APP="$LOCAL_HOME/Applications/Recordi.app"
SUPPORT="$LOCAL_HOME/Library/Application Support/Recordi"
if [[ "${1:-}" == --dry-run ]]; then
  printf 'Would remove %s and Recordi commands/queue/state/config. Recordings, transcripts, logs, completion records and model are kept.\n' "$APP"
  exit 0
fi
[[ $# == 0 ]] || { echo 'Usage: ./uninstall.sh [--dry-run]' >&2; exit 1; }
if /usr/bin/pgrep -f "^$APP/Contents/MacOS/Recordi" >/dev/null; then
  echo 'Quit Recordi and wait for its worker to stop, then rerun uninstall.sh.' >&2; exit 1
fi
if [[ -d "$APP" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == local.recordi.app ]] || { echo 'Refusing to remove an unrelated app.' >&2; exit 1; }
  if [[ "$LOCAL_HOME" == "$HOME" ]]; then "$APP/Contents/MacOS/Recordi" --unregister-login; fi
  rm -rf "$APP"
fi
rm -rf "$SUPPORT/commands" "$SUPPORT/queue" "$SUPPORT/state"
rm -f "$SUPPORT/config.json"
echo 'Recordi removed. Recordings, transcripts, logs and the model were kept. Remove its Recording Stop automation in Audio Hijack manually.'
