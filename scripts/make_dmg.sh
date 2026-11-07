#!/bin/bash
# 配布用 DMG を build/ に作る
#   使い方: scripts/make_dmg.sh <Shiori.app>
set -euo pipefail

APP="${1:?Shiori.app のパスを指定してください}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="build/Shiori-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "Shiori $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "$OUT"
