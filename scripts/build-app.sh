#!/bin/zsh
# Builds a release binary and wraps it in build/MenuStats.app (menu bar agent, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MenuStats
swift build -c release --product MenuStatsHelper
APP=build/MenuStats.app
# Version: VERSION=… or the latest git tag (v1.2.3 → 1.2.3), so local installs show the real version.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
# Optional: SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh (default: ad hoc).
IDENTITY="${SIGN_IDENTITY:--}"
# The app itself can be signed with a stable certificate (APP_SIGN_IDENTITY, its SHA-1, and APP_SIGN_KEYCHAIN):
# macOS then keeps the permissions granted to MenuStats (Full Disk Access for the Focus filters) across updates.
# Ad hoc, every build is a new app to macOS and the permission is lost at each update.
APP_IDENTITY="${APP_SIGN_IDENTITY:-$IDENTITY}"
APP_KEYCHAIN_ARGS=()
[[ -n "${APP_SIGN_KEYCHAIN:-}" ]] && APP_KEYCHAIN_ARGS=(--keychain "$APP_SIGN_KEYCHAIN")
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Resources"
cp .build/release/MenuStats "$APP/Contents/MacOS/MenuStats"
cp .build/release/MenuStatsHelper "$APP/Contents/MacOS/MenuStatsHelper"

# Desktop widgets: WidgetKit extension, sandboxed, reading only ~/Library/Application Support/MenuStats/.
APPEX="$APP/Contents/PlugIns/MenuStatsWidgets.appex"
# Built with swiftc rather than SwiftPM: widgets need macOS 14 (the app supports 13) and the extension entry point.
# One module: the shared widget sources and the extension.
mkdir -p "$APPEX/Contents/MacOS"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -O -target arm64-apple-macos14.0 -sdk "$SDK_PATH" -parse-as-library -application-extension \
    -module-name MenuStatsWidgets Sources/MenuStatsWidgetUI/*.swift Sources/MenuStatsWidgets/*.swift \
    -framework WidgetKit -framework SwiftUI -framework IOKit \
    -Xlinker -e -Xlinker _NSExtensionMain -o "$APPEX/Contents/MacOS/MenuStatsWidgets"
cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MenuStatsWidgets</string>
    <key>CFBundleDisplayName</key><string>MenuStats</string>
    <key>CFBundleIdentifier</key><string>local.menustats.widgets</string>
    <key>CFBundleExecutable</key><string>MenuStatsWidgets</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>DTPlatformName</key><string>macosx</string>
    <key>DTPlatformVersion</key><string>${SDK_VERSION}</string>
    <key>DTSDKName</key><string>macosx${SDK_VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

# Liquid Glass app icon (Icon Composer): Assets.car for macOS 26+, AppIcon.icns for older systems.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 13.0 --app-icon AppIcon \
    --output-partial-info-plist build/AppIcon-partial.plist >/dev/null

# Privileged helper (fans, lid closed), registered from the app with SMAppService.daemon (macOS 13+).
# Its name changes with its contents: macOS ties an ad hoc signed daemon to the code hash it had when first
# registered and never updates it, so a changed helper under the old name would be refused (Launch Constraint
# Violation). A new name gets a fresh registration; the app moves an installed helper to it by itself.
HELPER_LABEL="local.menustats.helper.$(shasum -a 256 .build/release/MenuStatsHelper | cut -c1-10)"
cat > "$APP/Contents/Library/LaunchDaemons/$HELPER_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$HELPER_LABEL</string>
    <key>BundleProgram</key><string>Contents/MacOS/MenuStatsHelper</string>
    <key>MachServices</key><dict><key>$HELPER_LABEL</key><true/></dict>
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
    <key>NSCalendarsFullAccessUsageDescription</key><string>MenuStats mostra i tuoi impegni nella scheda Data e li annuncia nella barra dei menu poco prima che inizino. I dati restano sul Mac.</string>
    <key>NSCalendarsUsageDescription</key><string>MenuStats mostra i tuoi impegni nella scheda Data e li annuncia nella barra dei menu poco prima che inizino. I dati restano sul Mac.</string>
    <key>NSLocationUsageDescription</key><string>MenuStats usa la tua posizione, solo se scegli la modalità automatica, per mostrare il meteo della tua città.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>MenuStats usa la tua posizione, solo se scegli la modalità automatica, per mostrare il meteo della tua città.</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Thomas Addamo</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>MSHelperLabel</key><string>${HELPER_LABEL}</string>
</dict>
</plist>
PLIST

# SwiftPM (Xcode 27) records the deployment target (13.0) as the SDK the binaries were built with. macOS then treats
# MenuStats as an old app and draws its windows in compatibility mode (old buttons, lists and sidebar), so the
# settings looked different depending on where the app was built. Record the real SDK, and refuse to ship otherwise.
for BIN in "$APP/Contents/MacOS/MenuStats" "$APP/Contents/MacOS/MenuStatsHelper"; do
    xcrun vtool -set-build-version macos 13.0 "$SDK_VERSION" -replace -output "$BIN.sdk" "$BIN" && mv -f "$BIN.sdk" "$BIN"
done
for BIN in "$APP/Contents/MacOS/MenuStats" "$APP/Contents/MacOS/MenuStatsHelper" "$APPEX/Contents/MacOS/MenuStatsWidgets"; do
    RECORDED=$(xcrun vtool -show-build "$BIN" | awk '/ sdk /{print $2; exit}')
    if [[ "${RECORDED%%.*}" -lt 26 ]]; then
        echo "Errore: $BIN risulta compilato con l'SDK $RECORDED (atteso $SDK_VERSION)" >&2
        exit 1
    fi
done

# Inner code first: the helper and the widgets, then the app (whose signature seals them and the plist).
codesign --force --options runtime --sign "$IDENTITY" --identifier local.menustats.helper "$APP/Contents/MacOS/MenuStatsHelper"
codesign --force --options runtime --sign "$IDENTITY" --entitlements scripts/widgets.entitlements "$APPEX"
codesign --force "${APP_KEYCHAIN_ARGS[@]}" --sign "$APP_IDENTITY" "$APP"
echo "Creato $APP"
