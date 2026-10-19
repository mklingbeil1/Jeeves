#!/bin/bash
set -e
cd "$(dirname "$0")"
rm -rf build; mkdir -p build
if swift build -c release --arch arm64 --arch x86_64; then
  BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
else
  echo "Universal build failed, building for this Mac only"
  swift build -c release
  BIN=$(swift build -c release --show-bin-path)
fi
if [ ! -f "$BIN/Jeeves" ]; then
  FOUND=$(find .build -type f -name Jeeves -perm -u+x | head -1)
  [ -n "$FOUND" ] || { echo "Could not find the built program"; exit 1; }
  BIN=$(dirname "$FOUND")
fi
echo "Using $BIN/Jeeves"
APP=build/Jeeves.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Jeeves" "$APP/Contents/MacOS/Jeeves"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/icon.icns "$APP/Contents/Resources/icon.icns"
codesign --force --deep -s - "$APP"
mkdir -p build/dmg && cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname Jeeves -srcfolder build/dmg -ov -format UDZO build/Jeeves.dmg
rm -rf build/dmg
echo "Done: build/Jeeves.app and build/Jeeves.dmg"
