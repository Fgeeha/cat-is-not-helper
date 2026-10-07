#!/usr/bin/env bash
# Собирает CatIsNotHelper.app из Swift-пакета.
# Использование: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"

# Если DEVELOPER_DIR указывает в никуда — берём обычный Xcode.
if [ ! -d "${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo /nonexistent)}" ]; then
  if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/CatIsNotHelper"

APP="build/CatIsNotHelper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CatIsNotHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ] && command -v swift >/dev/null; then
  swift scripts/make-icon.swift Resources/AppIcon.icns || true
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "Готово: $APP"
