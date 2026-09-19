#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/recordi-install.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
export RECORDI_HOME="$TEST_HOME"
# Exercise the production installer/remover paths without downloads, login registration or app launch.
"$ROOT/install.sh" --test-install
AUDIO="$TEST_HOME/Documents/Recordi/recordings/Keep me.flac"
MODEL="$TEST_HOME/Library/Application Support/Recordi/models/ggml-large-v3-turbo.bin"
printf 'keep audio' > "$AUDIO"
printf 'keep model' > "$MODEL"
"$ROOT/install.sh" --test-install
[[ "$(cat "$AUDIO")" == 'keep audio' ]]
"$ROOT/uninstall.sh" --dry-run
[[ -d "$TEST_HOME/Applications/Recordi.app" ]]
"$ROOT/uninstall.sh"
[[ ! -e "$TEST_HOME/Applications/Recordi.app" ]]
[[ "$(cat "$AUDIO")" == 'keep audio' ]]
[[ "$(cat "$MODEL")" == 'keep model' ]]
printf 'PASS installer twice, uninstall dry-run, uninstall preservation\n'
