#!/bin/bash
# Maintainer-only: build a relocatable Apple Silicon download. No build tools on the target Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v cmake >/dev/null || { echo 'Packaging requires CMake on the build Mac: brew install cmake' >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo 'Build this package on an Apple Silicon Mac.' >&2; exit 1; }
VERSION=1.9.4
SHA=57e280cee375ab02425b806ad5146b99f6eb9357e3c2b31357c8a6af2e2e44ae
CACHE="$ROOT/.build/distribution-source"
ARCHIVE="$CACHE/whisper-v$VERSION.tar.gz"
mkdir -p "$CACHE"
if [[ ! -f "$ARCHIVE" ]]; then curl --fail --location --output "$ARCHIVE" "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v$VERSION.tar.gz"; fi
[[ "$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)" == "$SHA" ]] || { echo 'Whisper source checksum mismatch.' >&2; exit 1; }
tar -xzf "$ARCHIVE" -C "$CACHE"
SOURCE="$CACHE/whisper.cpp-$VERSION"
BUILD="$ROOT/.build/whisper-portable"
cmake -S "$SOURCE" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_OPENMP=OFF \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DWHISPER_BUILD_IS_DEV=OFF \
  -DWHISPER_USE_SYSTEM_GGML=OFF
cmake --build "$BUILD" --target whisper-cli --parallel 4
# Reject non-system dynamic dependencies, including Homebrew and build-directory libraries.
if otool -L "$BUILD/bin/whisper-cli" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' ; then
  echo 'Whisper is not self-contained.' >&2; exit 1
fi
RECORDI_BUNDLED_WHISPER="$BUILD/bin/whisper-cli" RECORDI_WHISPER_SOURCE="$SOURCE" "$ROOT/scripts/build.sh"
DEST="$ROOT/.build/download/Recordi Setup"
# Only remove the disposable generated package directory.
rm -rf "$DEST"
mkdir -p "$DEST/scripts" "$DEST/tests/fixtures" "$DEST/docs"
ditto "$ROOT/.build/Recordi.app" "$DEST/Recordi.app"
cp "$ROOT/distribution/Set Up Recordi.command" "$ROOT/distribution/Start Here.html" "$DEST/"
cp "$ROOT/scripts/"{setup-packaged,model,smoke-transcription}.sh "$DEST/scripts/"
cp "$ROOT/tests/fixtures/"{jfk.mp3,jfk.flac,README.md} "$DEST/tests/fixtures/"
cp "$ROOT/docs/audio-hijack-setup.png" "$DEST/docs/"
ZIP="$ROOT/.build/download/Recordi-Apple-Silicon.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$DEST" "$ZIP"
(cd "$ROOT/.build/download" && shasum -a 256 Recordi-Apple-Silicon.zip > SHA256SUMS.txt)
printf '\nPackage: %s\n' "$ZIP"
