#!/bin/bash
# Сборка котика внутри RedOS 8: бинарник в каталог $1 (по умолчанию desktop/redos/out).
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-$ROOT/desktop/redos/out}
mkdir -p "$OUT"
docker volume create cat-target >/dev/null; docker volume create cat-cargo >/dev/null
docker run --rm -v "$ROOT":/src -v cat-target:/target -v cat-cargo:/cargo -v "$OUT":/out \
  -e CARGO_TARGET_DIR=/target -w /src/desktop/src-tauri cat-redos8 \
  bash -c 'cargo build --release 2>&1 | grep -E "^(warning|error)|-->|Finished" ; cp /target/release/cat-is-not-helper /out/.new && mv -f /out/.new /out/cat-is-not-helper'
