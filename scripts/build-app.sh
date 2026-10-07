#!/usr/bin/env bash
# Собирает CatIsNotHelper.app из Swift-пакета.
# Использование: scripts/build-app.sh [debug|release]
#   ARCHS="arm64 x86_64" — универсальный бинарник (по умолчанию только текущая архитектура)
#   CODESIGN_IDENTITY="…"  — чем подписывать (иначе первый «Apple Development», иначе ad-hoc)
#   VERSION="1.2.3"        — версия в Info.plist (CI берёт из тега)
#   RELEASE_BUILD=1        — пометить сборку релизной: включает автопроверку обновлений
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
ARCH_FLAGS=()
for arch in ${ARCHS:-}; do
  ARCH_FLAGS+=(--arch "$arch")
done

# Если DEVELOPER_DIR указывает в никуда — берём обычный Xcode.
if [ ! -d "${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo /nonexistent)}" ]; then
  if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)/CatIsNotHelper"

APP="build/CatIsNotHelper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CatIsNotHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
PLIST="$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
fi
if [ "${RELEASE_BUILD:-0}" = "1" ]; then
  /usr/libexec/PlistBuddy -c "Set :CatReleaseBuild true" "$PLIST"
fi
echo "Версия: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")$([ "${RELEASE_BUILD:-0}" = "1" ] && echo ' (релиз)')"

if [ ! -f Resources/AppIcon.icns ] && command -v swift >/dev/null; then
  swift scripts/make-icon.swift Resources/AppIcon.icns || true
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Подпись. Разрешение «Универсальный доступ» привязано к подписи приложения:
# у ad-hoc подписи она меняется при каждой сборке, и доступ слетает.
# Поэтому берём стабильный сертификат: из CODESIGN_IDENTITY или первый «Apple Development».
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -oE '"Apple Development: [^"]+"' | tr -d '"' || true)"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP" 2>/dev/null \
    || codesign --force --sign "$IDENTITY" "$APP"
  echo "Подписано: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Внимание: ad-hoc подпись. После каждой пересборки придётся заново выдавать доступ в «Универсальном доступе»."
fi
echo "Архитектуры: $(lipo -archs "$APP/Contents/MacOS/CatIsNotHelper")"
echo "Готово: $APP"
