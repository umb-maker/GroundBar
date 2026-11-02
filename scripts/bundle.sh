#!/bin/sh
# Builds OmniBar with SwiftPM and wraps it in build/OmniBar.app.
#
#   ./scripts/bundle.sh            release build for this Mac's architecture
#   ./scripts/bundle.sh universal  release build for Apple silicon + Intel
#
# Signing: ad-hoc by default. To keep macOS privacy permissions across rebuilds, sign with a stable
# identity: set OMNIBAR_SIGN_IDENTITY, or put OMNIBAR_SIGN_IDENTITY="Your Identity" in
# scripts/signing.local (ignored by git).
set -e
cd "$(dirname "$0")/.."

[ -f scripts/signing.local ] && . scripts/signing.local

if [ "$1" = "universal" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/OmniBar"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/OmniBar"
fi

APP=build/OmniBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OmniBar"
cp Resources/StartIcon.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.omnibar.OmniBar</string>
  <key>CFBundleName</key><string>OmniBar</string>
  <key>CFBundleExecutable</key><string>OmniBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>OmniBar usa System Events per Sospendi, Riavvia, Arresta e Logout dal menu Start.</string>
</dict>
</plist>
PLIST

if [ -n "$OMNIBAR_SIGN_IDENTITY" ] && security find-certificate -c "$OMNIBAR_SIGN_IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$OMNIBAR_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
  echo "Firma ad-hoc: macOS chiederà di nuovo i permessi dopo ogni build (vedi OMNIBAR_SIGN_IDENTITY)."
fi
echo "Creato $APP"
