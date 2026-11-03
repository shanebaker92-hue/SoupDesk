#!/bin/sh
# Build SoupDesk.app (release), bundle the stocks, sign with the Apple Development identity.
# ./build_app.sh dist — sign with Developer ID, notarize and staple, for running on other Macs.
set -e
cd "$(dirname "$0")"
swift build -c release --product SoupDesk
APP=build/SoupDesk.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SoupDesk "$APP/Contents/MacOS/"
cp -R Resources/Stocks "$APP/Contents/Resources/Stocks"
# Icon Composer bundle → Assets.car (Liquid Glass icon) + SoupDesk.icns (older macOS)
xcrun actool Design/SoupDesk.icon --compile "$APP/Contents/Resources" --app-icon SoupDesk \
    --platform macosx --minimum-deployment-target 14.0 --output-partial-info-plist build/icon.plist >/dev/null
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SoupDesk</string>
<key>CFBundleIdentifier</key><string>com.shanebaker.soupdesk</string>
<key>CFBundleExecutable</key><string>SoupDesk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>SoupDesk</string>
<key>CFBundleIconName</key><string>SoupDesk</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
if [ "$1" != dist ]; then
    IDENT="${SIGN_IDENTITY:-Apple Development: Shane Baker (M7H8Y883KF)}"
    codesign --force --deep --options runtime --timestamp=none -s "$IDENT" "$APP"
    codesign --verify --verbose "$APP"
    echo "built $APP"
    exit 0
fi

# dist: Developer ID sign, notarize, staple, zip for sharing.
# Needs the notarytool keychain profile (default soupdesk-notary, NOTARY_PROFILE= to override).
IDENT="${SIGN_IDENTITY:-Developer ID Application: Shane Baker (A27T7KN725)}"
PROFILE="${NOTARY_PROFILE:-soupdesk-notary}"
ZIP=build/SoupDesk.zip
codesign --force --options runtime --timestamp -s "$IDENT" "$APP"
codesign --verify --strict --verbose "$APP"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -vv "$APP"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
echo "built $APP, notarized; share $ZIP"
