#!/bin/zsh
# Builds ScreenClip.app. Run ./build.sh --dmg to also create ScreenClip-<version>.dmg.
set -e
cd "$(dirname "$0")"
VERSION="1.2.2"
APP=ScreenClip.app
BUILD=build

rm -rf $APP $BUILD
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources $BUILD

# Universal binary (Apple Silicon + Intel).
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13.0 *.swift \
    -o $BUILD/ScreenClip-$arch -framework Cocoa -framework ServiceManagement
done
lipo -create $BUILD/ScreenClip-arm64 $BUILD/ScreenClip-x86_64 -output $APP/Contents/MacOS/ScreenClip

# App icon.
swift scripts/make_icon.swift $BUILD/icon.png
ICONSET=$BUILD/AppIcon.iconset
mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s $BUILD/icon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) $BUILD/icon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns

cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ScreenClip</string>
  <key>CFBundleDisplayName</key><string>ScreenClip</string>
  <key>CFBundleIdentifier</key><string>local.screenclip</string>
  <key>CFBundleExecutable</key><string>ScreenClip</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSDesktopFolderUsageDescription</key><string>ScreenClip watches your Desktop to copy new screenshots to the clipboard.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>ScreenClip watches this folder to copy new screenshots to the clipboard.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>ScreenClip watches this folder to copy new screenshots to the clipboard.</string>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $APP ($VERSION)"

if [[ "$1" == "--dmg" ]]; then
  DMG=ScreenClip-$VERSION.dmg
  STAGE=$BUILD/dmg
  rm -rf $STAGE $DMG
  mkdir -p $STAGE
  cp -R $APP $STAGE/
  ln -s /Applications $STAGE/Applications
  hdiutil create -volname "ScreenClip" -srcfolder $STAGE -ov -format UDZO $DMG >/dev/null
  echo "Built $DMG"
fi
