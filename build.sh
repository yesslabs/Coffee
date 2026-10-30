#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="$PWD/dist/Coffee.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/.build/module-cache"
xcrun swiftc Sources/main.swift -o "$APP/Contents/MacOS/Coffee" -framework Cocoa -framework IOKit -module-cache-path "$PWD/.build/module-cache"
xcrun swiftc scripts/generate-icon.swift -o "$PWD/.build/generate-icon" -framework AppKit -module-cache-path "$PWD/.build/module-cache"
"$PWD/.build/generate-icon" "$PWD/.build/Coffee.iconset"
/usr/bin/iconutil -c icns "$PWD/.build/Coffee.iconset" -o "$APP/Contents/Resources/Coffee.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Coffee</string><key>CFBundleIdentifier</key><string>local.coffee.mac</string><key>CFBundleName</key><string>Coffee</string><key>CFBundleIconFile</key><string>Coffee</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.23.0</string><key>LSMinimumSystemVersion</key><string>13.0</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
