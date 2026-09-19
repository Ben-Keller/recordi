#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" swift run --disable-sandbox --cache-path "$ROOT/.build/cache" RecordiTests
