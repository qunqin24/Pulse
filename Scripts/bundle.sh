#!/bin/bash
#
# Assembles Pulse.app from the SwiftPM build.
#
# Pulse has no Xcode project on purpose — it is a plain package, and this is
# what turns the package's bare executable into something macOS treats as an
# app. That matters for more than tidiness: without a bundle there is no
# version number to compare against (so no update check), `SMAppService` cannot
# register a login item, and there is nothing to hand anyone but a build folder.
#
#   ./Scripts/bundle.sh            → build/Pulse.app
#   ./Scripts/bundle.sh --zip      → and build/Pulse-<version>.zip to attach
#                                    to the release
#   ./Scripts/bundle.sh --open     → and reveal it in Finder
#
# The version comes from the VERSION file, which is the single source of truth:
# tag the release `v$(cat VERSION)` so the update check — which reads GitHub's
# latest release tag — is comparing like with like.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/Pulse.app"
BUNDLE_ID="io.github.qunqin24.Pulse"
FEED_URL="https://raw.githubusercontent.com/qunqin24/Pulse/main/appcast.xml"
# Public half of the EdDSA key updates are signed with. Safe to commit — it is
# what *verifies* an update, and Sparkle refuses anything not signed by its
# private half. See Scripts/appcast.py.
PUBLIC_KEY="$(tr -d '[:space:]' < Scripts/sparkle-public-key.txt)"

echo "Building Pulse $VERSION (universal)…"

# Both architectures, so the same download runs on Apple Silicon and Intel.
swift build -c release --arch arm64 --arch x86_64

BUILT="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Spotlight indexes an .app wherever it finds one, so a build sitting in the
# project folder turns up in Launchpad and search beside the installed copy —
# two identical Pulses, and no way to tell which is which. This marker keeps
# the whole build directory out of the index.
touch "build/.metadata_never_index"

cp "$BUILT/Pulse" "$APP/Contents/MacOS/Pulse"

# The package's resource bundle carries the provider marks and both .lproj
# folders. `Bundle.module` looks in the main bundle's Resources, so this is
# where it has to land — the app is silently English with no icons without it.
cp -R "$BUILT/Pulse_Pulse.bundle" "$APP/Contents/Resources/"
cp AppIcon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle has to travel inside the app. SwiftPM links the executable against
# the framework but has no app to put it in, which is why a `swift run` build
# cannot update itself and `AppUpdate` doesn't start the updater there.
FRAMEWORK="$(find .build/artifacts -maxdepth 6 -type d -name 'Sparkle.framework' | head -1)"
if [ -z "$FRAMEWORK" ]; then
    echo "Sparkle.framework not found — run 'swift build' so SwiftPM fetches it." >&2
    exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"

# The executable looks for it at @rpath; SwiftPM only ever pointed that at the
# build directory, so without this the app launches into a dyld failure.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Pulse" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Pulse</string>
    <key>CFBundleDisplayName</key><string>Pulse</string>
    <key>CFBundleExecutable</key><string>Pulse</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- A menu bar app: no Dock icon, and no flash of one at launch. The code
         also sets .accessory, but that runs after the Dock has already been
         told what to show. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>github.com/qunqin24/Pulse</string>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
    <!-- Checked on a schedule without asking first. Sparkle would normally put
         up a permission prompt, but Pulse is an .accessory app whose panel
         never becomes key, so that window can open behind everything and go
         unanswered. The toggle is in Settings instead, where it can be found. -->
    <key>SUEnableAutomaticChecks</key><true/>
    <!-- Downloading and installing on its own stays off: an update is offered,
         not applied behind the user's back. -->
    <key>SUAutomaticallyUpdate</key><false/>
</dict>
</plist>
PLIST

# Unsigned builds are quarantined on download and refused by Gatekeeper. An
# ad-hoc signature does not fix that — only a Developer ID and notarisation do
# — but it does keep macOS from complaining about a *damaged* bundle when the
# app is moved or the binary is touched.
# Inside out: a nested bundle signed after its container invalidates the
# container's signature, and Sparkle brings several of them (XPC services and
# its own updater app).
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (ad-hoc signing skipped)"

echo "→ $APP"

# `ditto`, not `zip`: an app bundle carries symlinks and resource forks that a
# plain zip quietly flattens, and the unzipped copy then refuses to launch.
if [ "${1:-}" = "--zip" ]; then
    ZIP="build/Pulse-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "→ $ZIP"
fi

[ "${1:-}" = "--open" ] && open -R "$APP"
exit 0
