#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/Recordi.app"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/recordi-signing-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SIGNING_ID="$(cat "$HOME/Library/Application Support/Recordi/signing/identity.txt")"
/usr/bin/codesign -d -r- "$APP" > "$WORK/before.txt" 2>&1
/usr/bin/codesign -d --verbose=4 "$APP" 2> "$WORK/before-details.txt"
/usr/bin/ditto "$APP" "$WORK/Recordi.app"
printf 'Different build contents\n' > "$WORK/Recordi.app/Contents/Resources/signing-probe.txt"
/usr/bin/codesign --force --sign "$SIGNING_ID" --keychain "$HOME/Library/Keychains/login.keychain-db" \
  --timestamp=none --identifier local.recordi.app "$WORK/Recordi.app"
/usr/bin/codesign --verify --strict "$WORK/Recordi.app"
/usr/bin/codesign -d -r- "$WORK/Recordi.app" > "$WORK/after.txt" 2>&1
/usr/bin/codesign -d --verbose=4 "$WORK/Recordi.app" 2> "$WORK/after-details.txt"
grep '^designated =>' "$WORK/before.txt" > "$WORK/before-dr.txt"
grep '^designated =>' "$WORK/after.txt" > "$WORK/after-dr.txt"
cmp "$WORK/before-dr.txt" "$WORK/after-dr.txt"
grep -q 'certificate leaf' "$WORK/after-dr.txt"
! grep -q 'cdhash' "$WORK/after-dr.txt"
[[ "$(grep '^CDHash=' "$WORK/before-details.txt")" != "$(grep '^CDHash=' "$WORK/after-details.txt")" ]]
echo 'PASS changed build has a different code hash but the same certificate-based app identity'
