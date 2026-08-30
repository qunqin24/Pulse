#!/bin/bash
#
# Builds build/Pulse-<version>.dmg: the app, a shortcut to Applications, and a
# backdrop telling you what to do with them.
#
# The disk image is the install guide. Pulse is not signed with an Apple
# Developer ID, so macOS blocks the first launch and the user has to go and
# allow it by hand — instructions that live only in a README are instructions
# nobody downloading a zip ever sees, so they are printed on the window itself.
#
#   ./Scripts/dmg.sh
#
# Replace Scripts/dmg-background.tiff to change how the window looks. It must
# stay 660x420 points (the file carries a 1x and a 2x representation); the icon
# positions below are measured against that.
#
# The window's layout — its size, its backdrop, where the two icons sit — is
# stored by Finder in a `.DS_Store`, and the only way to *write* one is to ask
# Finder, which needs a logged-in desktop session and permission to control it.
# Neither exists on a CI runner. So the layout is captured once on a real Mac
# and committed as Scripts/dmg-DS_Store; this reuses it when it is there and
# falls back to driving Finder when it isn't. Re-capture it with --relayout
# after changing the backdrop or the icon positions.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
VOLUME="Pulse"
STAGING="build/dmg"
WRITABLE="build/pulse-rw.dmg"
FINAL="build/Pulse-$VERSION.dmg"

./Scripts/bundle.sh

echo "Staging the disk image…"
rm -rf "$STAGING" "$WRITABLE" "$FINAL"
mkdir -p "$STAGING/.background"
cp -R "build/Pulse.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp Scripts/dmg-background.tiff "$STAGING/.background/background.tiff"

# The captured layout goes in before the image is created, so a headless build
# needs Finder for nothing at all.
RELAYOUT="${1:-}"
if [ -f "Scripts/dmg-DS_Store" ] && [ "$RELAYOUT" != "--relayout" ]; then
    cp "Scripts/dmg-DS_Store" "$STAGING/.DS_Store"
fi

hdiutil create -srcfolder "$STAGING" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -ov "$WRITABLE" -quiet

MOUNT="/Volumes/$VOLUME"
hdiutil attach "$WRITABLE" -mountpoint "$MOUNT" -nobrowse -quiet

if [ -f "$STAGING/.DS_Store" ]; then
    echo "Using the captured window layout."
elif ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 420 of content plus the title bar, which Finder counts in the
        -- bounds: sized to 570 the backdrop's bottom 28 points — the line
        -- about the first launch — is cut off by the window's edge.
        set the bounds of container window to {200, 150, 860, 598}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 96
        set background picture of options to file ".background:background.tiff"
        set position of item "Pulse.app" of container window to {170, 205}
        set position of item "Applications" of container window to {490, 205}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT
then
    echo "  (Finder wouldn't take the layout — the image is still usable)"
fi

# Capturing it back out is what makes the next build — and every CI build —
# able to skip Finder entirely.
if [ "$RELAYOUT" = "--relayout" ] && [ -f "$MOUNT/.DS_Store" ]; then
    cp "$MOUNT/.DS_Store" "Scripts/dmg-DS_Store"
    echo "→ Scripts/dmg-DS_Store (commit this)"
fi

sync
hdiutil detach "$MOUNT" -quiet

echo "Compressing…"
hdiutil convert "$WRITABLE" -format UDZO -imagekey zlib-level=9 -o "$FINAL" -quiet
rm -rf "$WRITABLE" "$STAGING"

echo "→ $FINAL"
