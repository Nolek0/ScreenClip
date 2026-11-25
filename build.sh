#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=ScreenClip.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O main.swift History.swift -o $APP/Contents/MacOS/ScreenClip -framework Cocoa -framework ServiceManagement
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ScreenClip</string>
  <key>CFBundleDisplayName</key><string>ScreenClip</string>
  <key>CFBundleIdentifier</key><string>local.screenclip</string>
  <key>CFBundleExecutable</key><string>ScreenClip</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>ScreenClip surveille le Bureau pour copier tes captures d'écran dans le presse-papier.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>ScreenClip surveille ce dossier pour copier tes captures d'écran.</string>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "OK -> $(pwd)/$APP"
