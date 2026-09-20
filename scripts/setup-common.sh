#!/bin/bash
# Idempotent setup steps may be retried only after the user explicitly requests it.
setup_step() {
  local label="$1" result answer
  shift
  while true; do
    printf '\nSTEP: %s\n' "$label"
    if "$@"; then return 0; else result=$?; fi
    printf '\n%s did not finish (exit %s). Setup is not complete.\n' "$label" "$result" >&2
    printf 'If macOS blocked Recordi or whisper-cli, approve that item in System Settings → Privacy & Security → Open Anyway. If Documents access was denied, allow it for the requesting app. Otherwise check the error above.\n' >&2
    printf 'After resolving the error, press Return here to retry this step, or type q to stop: ' >&2
    if ! IFS= read -r answer || [[ -n "$answer" ]]; then return "$result"; fi
  done
}
verify_setup_files() {
  local support="$1" name
  /usr/bin/plutil -extract whisper raw "$support/config.json" >/dev/null || return 1
  for name in 'Transcribe Finished Recording.js' start.ahcommand stop.ahcommand status.ahcommand; do
    if [[ ! -s "$support/commands/$name" ]]; then
      printf 'Missing setup file: %s\n' "$support/commands/$name" >&2
      return 1
    fi
  done
}
