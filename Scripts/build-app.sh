#!/bin/bash
# Compile ConvertDock et assemble build/ConvertDock.app (signature ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/ConvertDock.app"

echo "▸ Compilation (${CONFIG})…"
swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/ConvertDock"

echo "▸ Assemblage de ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ConvertDock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signature ad hoc…"
codesign --force --deep --sign - "$APP"

echo "✓ $APP"
