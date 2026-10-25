#!/bin/bash
# Builds the installer disk image: a window with Tuckr and the Applications folder side by side
# on a picture, the app's icon on the disk, and the whole thing compressed.
#
#   scripts/make-dmg.sh /Applications/Tuckr.app Tuckr-1.0.3.dmg
#
# It uses Finder (through AppleScript) to lay the window out, so it needs a logged-in Mac; the first
# time, macOS may ask to let your terminal control Finder: allow it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?path to Tuckr.app}"
OUT="${2:?output .dmg}"
VOL="Tuckr"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift scripts/make-dmg-background.swift "$WORK/background.png"

# A fresh, writable disk big enough for the app.
SIZE=$(( $(du -sm "$APP" | cut -f1) + 30 ))
[ -d "/Volumes/$VOL" ] && hdiutil detach "/Volumes/$VOL" -quiet -force || true
hdiutil create -quiet -size "${SIZE}m" -fs HFS+ -volname "$VOL" -ov "$WORK/rw.dmg"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ {print $1}')
MOUNT="/Volumes/$VOL"

cp -R "$APP" "$MOUNT/"
ln -s /Applications "$MOUNT/Applications"
mkdir "$MOUNT/.background"
cp "$WORK/background.png" "$MOUNT/.background/background.png"
# The icon of the disk itself.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a C "$MOUNT" 2>/dev/null || true

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 100, 860, 596}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 120
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Tuckr.app" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    update without registering applications
    delay 2
    set the bounds of container window to {200, 100, 860, 596}
    delay 2
    close
    delay 2
  end tell
end tell
APPLESCRIPT

# Finder writes the window's layout (.DS_Store) a moment later: wait for it.
for _ in $(seq 1 20); do [ -s "$MOUNT/.DS_Store" ] && break; sleep 1; done
[ -s "$MOUNT/.DS_Store" ] || { echo "Finder did not save the window layout." >&2; exit 1; }
sleep 3

sync
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force -quiet
rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Made $OUT"
