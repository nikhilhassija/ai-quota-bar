#!/bin/zsh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$DIR/build/AIQuotaBar.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -d "$DIR/Resources" ]; then
  cp -R "$DIR/Resources/"* "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi

swiftc -O \
  -framework Cocoa \
  -framework SwiftUI \
  -framework Security \
  -framework ServiceManagement \
  "$DIR/Sources/main.swift" \
  -o "$APP_DIR/Contents/MacOS/AIQuotaBar"

codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR successfully"
