#!/bin/sh
# Builds Groundbar with SwiftPM and wraps it in build/Groundbar.app.
#
#   ./scripts/bundle.sh            release build for this Mac's architecture
#   ./scripts/bundle.sh universal  release build for Apple silicon + Intel
#
# Signing: ad-hoc by default. To keep macOS privacy permissions across rebuilds, sign with a stable
# identity: set GROUNDBAR_SIGN_IDENTITY, or put GROUNDBAR_SIGN_IDENTITY="Your Identity" in
# scripts/signing.local (ignored by git).
set -e
cd "$(dirname "$0")/.."

[ -f scripts/signing.local ] && . scripts/signing.local

if [ "$1" = "universal" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Groundbar"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Groundbar"
fi

APP=build/Groundbar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Groundbar"
cp Resources/StartIcon.png Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>it</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>app.groundbar.Groundbar</string>
  <key>CFBundleName</key><string>Groundbar</string>
  <key>CFBundleExecutable</key><string>Groundbar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.1</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Groundbar uses System Events for Sleep, Restart, Shut Down and Log Out in the Start menu.</string>
</dict>
</plist>
PLIST

if [ -n "$GROUNDBAR_SIGN_IDENTITY" ] && security find-certificate -c "$GROUNDBAR_SIGN_IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$GROUNDBAR_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
  echo "Ad-hoc signature: macOS will ask for permissions again after every build (see GROUNDBAR_SIGN_IDENTITY)."
fi
echo "Built $APP"
