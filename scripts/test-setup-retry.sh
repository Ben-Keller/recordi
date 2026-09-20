#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/setup-common.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/recordi-retry.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/commands"
# Match a first-run failure: folders exist, but a blocked command cannot configure.
configure() {
  if [[ ! -e "$WORK/first-attempt" ]]; then
    touch "$WORK/first-attempt"
    echo 'Simulated first-run execution denial' >&2
    return 126
  fi
  printf '{"whisper":"example"}' > "$WORK/config.json"
  for name in 'Transcribe Finished Recording.js' start.ahcommand stop.ahcommand status.ahcommand; do
    printf 'generated' > "$WORK/commands/$name"
  done
  verify_setup_files "$WORK"
}
if verify_setup_files "$WORK" 2>/dev/null; then exit 1; fi
setup_step 'Configure' configure <<< ''
verify_setup_files "$WORK"
rm "$WORK/commands/Transcribe Finished Recording.js"
if verify_setup_files "$WORK" 2>/dev/null; then echo 'Accepted missing JS' >&2; exit 1; fi
always_fails() { return 42; }
if setup_step 'User cancellation' always_fails <<< q; then exit 1; else [[ $? == 42 ]]; fi
if setup_step 'Closed input' always_fails </dev/null; then exit 1; else [[ $? == 42 ]]; fi
echo 'PASS first-run failure resumes in place, scripts required for success, cancellation and EOF preserve failure.'
