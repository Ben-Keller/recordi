#!/bin/bash
set -euo pipefail
MODEL="${1:?Pass model destination}"
EXPECTED=1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69
check() { [[ -f "$1" ]] && [[ "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/cut -d ' ' -f 1)" == "$EXPECTED" ]]; }
if check "$MODEL"; then exit 0; fi
mkdir -p "$(dirname "$MODEL")"
PART="$MODEL.part"
if ! check "$PART"; then
  # Resume interrupted downloads; nothing becomes the model until the checksum passes.
  for attempt in 1 2 3 4 5 6 7 8; do
    /usr/bin/curl --fail --location --continue-at - --connect-timeout 30 --retry 3 --retry-all-errors \
      --output "$PART" 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin' || true
    if check "$PART"; then break; fi
    # A complete-sized bad file cannot be repaired by resuming it.
    if [[ -f "$PART" ]] && [[ "$(/usr/bin/stat -f %z "$PART")" -ge 1624555275 ]]; then
      rm -f "$PART"
    fi
  done
fi
if ! check "$PART"; then printf 'Model checksum failed; rerun install.sh to resume the download.\n' >&2; exit 1; fi
mv -f "$PART" "$MODEL"
