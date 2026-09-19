#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" swift build -c release --product Recordi --disable-sandbox --cache-path "$ROOT/.build/cache"
APP="$ROOT/.build/Recordi.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Recordi" "$APP/Contents/MacOS/Recordi"
cp "$ROOT/assets/Recordi.icns" "$APP/Contents/Resources/Recordi.icns"
cp "$ROOT/assets/MenuRecorder.png" "$APP/Contents/Resources/MenuRecorder.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.recordi.app</string>
<key>CFBundleName</key><string>Recordi</string>
<key>CFBundleDisplayName</key><string>Recordi</string>
<key>CFBundleExecutable</key><string>Recordi</string>
<key>CFBundleIconFile</key><string>Recordi</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
SIGNING_FILE="$HOME/Library/Application Support/Recordi/signing/identity.txt"
if [[ ! -s "$SIGNING_FILE" ]]; then
  echo 'Run ./scripts/setup-signing.sh once to create Recordi’s persistent local signing identity.' >&2
  exit 1
fi
SIGNING_ID="$(cat "$SIGNING_FILE")"
[[ "$SIGNING_ID" =~ ^[[:xdigit:]]{40}$ ]] || { echo 'Invalid Recordi signing fingerprint.' >&2; exit 1; }
# Never fall back to ad-hoc signing: doing so changes the app identity and resets privacy consent.
if [[ -n "${RECORDI_BUNDLED_WHISPER:-}" ]]; then
  mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/Licenses"
  cp "$RECORDI_BUNDLED_WHISPER" "$APP/Contents/Helpers/whisper-cli"
  cp "${RECORDI_WHISPER_SOURCE:?}/LICENSE" "$APP/Contents/Resources/Licenses/whisper.cpp.txt"
  /usr/bin/sed -n '/^This software is available as a choice of the following licenses\./,$p' \
    "$RECORDI_WHISPER_SOURCE/examples/miniaudio.h" > "$APP/Contents/Resources/Licenses/miniaudio.txt"
  /usr/bin/codesign --force --sign "$SIGNING_ID" --keychain "$HOME/Library/Keychains/login.keychain-db" \
    --timestamp=none "$APP/Contents/Helpers/whisper-cli"
else
  # A source build must not accidentally ship a helper left from an earlier package build.
  rm -rf "$APP/Contents/Helpers" "$APP/Contents/Resources/Licenses"
fi
/usr/bin/codesign --force --sign "$SIGNING_ID" --keychain "$HOME/Library/Keychains/login.keychain-db" \
  --timestamp=none --identifier local.recordi.app "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
