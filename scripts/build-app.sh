#!/bin/zsh
# Builds a release binary and wraps it in build/MenuStats.app (menu bar agent, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MenuStats
swift build -c release --product MenuStatsHelper
APP=build/MenuStats.app
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
# Optional: SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh (default: ad hoc).
IDENTITY="${SIGN_IDENTITY:--}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Resources"
cp .build/release/MenuStats "$APP/Contents/MacOS/MenuStats"
cp .build/release/MenuStatsHelper "$APP/Contents/MacOS/MenuStatsHelper"

# Liquid Glass app icon (Icon Composer): Assets.car for macOS 26+, AppIcon.icns for older systems.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 13.0 --app-icon AppIcon \
    --output-partial-info-plist build/AppIcon-partial.plist >/dev/null

# Privileged helper for fan control, registered from the app with SMAppService.daemon (macOS 13+).
cat > "$APP/Contents/Library/LaunchDaemons/local.menustats.helper.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.menustats.helper</string>
    <key>BundleProgram</key><string>Contents/MacOS/MenuStatsHelper</string>
    <key>MachServices</key><dict><key>local.menustats.helper</key><true/></dict>
    <key>AssociatedBundleIdentifiers</key><array><string>local.menustats</string></array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MenuStats</string>
    <key>CFBundleIdentifier</key><string>local.menustats</string>
    <key>CFBundleExecutable</key><string>MenuStats</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>NSLocationUsageDescription</key><string>MenuStats usa la tua posizione, solo se scegli la modalità automatica, per mostrare il meteo della tua città.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>MenuStats usa la tua posizione, solo se scegli la modalità automatica, per mostrare il meteo della tua città.</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Thomas Addamo</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Inner code first: the helper, then the app (whose signature seals the helper and the plist).
codesign --force --options runtime --sign "$IDENTITY" --identifier local.menustats.helper "$APP/Contents/MacOS/MenuStatsHelper"
codesign --force --sign "$IDENTITY" "$APP"
echo "Creato $APP"
