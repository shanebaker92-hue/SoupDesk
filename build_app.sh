#!/bin/sh
# Build SoupDesk.app (release), bundle the stocks, sign with the Apple Development identity.
set -e
cd "$(dirname "$0")"
swift build -c release --product SoupDesk
APP=build/SoupDesk.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SoupDesk "$APP/Contents/MacOS/"
cp -R Resources/Stocks "$APP/Contents/Resources/Stocks"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SoupDesk</string>
<key>CFBundleIdentifier</key><string>com.shanebaker.soupdesk</string>
<key>CFBundleExecutable</key><string>SoupDesk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
IDENT="${SIGN_IDENTITY:-Apple Development}"
codesign --force --deep --options runtime --timestamp=none -s "$IDENT" "$APP"
codesign --verify --verbose "$APP"
echo "built $APP"
