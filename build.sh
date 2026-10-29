#!/bin/bash
# Baut DeskTOP.app neu: kompilieren, Icon, signieren. Ausgabe landet auch in build.log
cd "$(dirname "$0")"
exec > >(tee build.log) 2>&1
set -e
APP=DeskTOP.app
pkill -x DeskTOP 2>/dev/null || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O DeskTOP.swift -o "$APP/Contents/MacOS/DeskTOP" -framework Cocoa -framework ApplicationServices
iconutil -c icns DeskTOP.iconset -o "$APP/Contents/Resources/DeskTOP.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
touch "$APP"
echo "Fertig. Starte mit: open $APP"
