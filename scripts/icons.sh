#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/module-cache assets
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" swiftc app/Recordi/IconArt.swift scripts/GenerateIcons.swift -o .build/generate-icons
.build/generate-icons "$ROOT/assets"
iconutil -c icns assets/Recordi.iconset -o assets/Recordi.icns
