#!/bin/bash
# Builds Tuckr in Release and installs it in /Applications.
#
#   scripts/install.sh              build, install, launch
#   scripts/install.sh --no-launch  build and install only
#
# Signing: with a certificate named "TheBoringCoucouify Local Signing" in the
# login keychain (see docs/SIGNING.md) macOS keeps the app's permissions
# (Accessibility, Input Monitoring) across rebuilds. Without one the build is
# signed ad hoc and those permissions have to be granted again after each
# install. SIGN_IDENTITY overrides the choice.
#
# The hardened runtime is off for these local builds: it makes macOS refuse the
# vendored MediaRemoteAdapter framework, which is signed by Boring Notch's team.
# It is only needed for notarized releases.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Tuckr"
BUNDLE_ID="com.serjdmitri.Tuckr"
CERT_NAME="TheBoringCoucouify Local Signing"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    IDENTITY="$CERT_NAME"
  else
    IDENTITY="-"
    echo "No \"$CERT_NAME\" certificate found: signing ad hoc (permissions reset on each install)."
  fi
fi

# Built ad hoc: a named identity passed as a build setting also reaches the
# Swift packages' own targets, which then demand a development team.
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES ENABLE_HARDENED_RUNTIME=NO build | tail -3

BUILT="build/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT" ] || { echo "Build did not produce $BUILT" >&2; exit 1; }

if [ "$IDENTITY" != "-" ]; then
  # Re-sign inside out with the certificate, keeping each piece's entitlements.
  echo "Signing with $IDENTITY"
  while IFS= read -r nested; do
    codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements,requirements,flags "$nested"
  done < <(find "$BUILT/Contents" \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \) -print \
            | awk '{ print length($0) " " $0 }' | sort -rn | cut -d' ' -f2-)
  codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements,requirements,flags "$BUILT"
  codesign --verify --deep --strict "$BUILT"
fi

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 2
pkill -f "/Applications/$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1 || true

rm -rf "/Applications/$APP_NAME.app"
cp -R "$BUILT" /Applications/
xattr -cr "/Applications/$APP_NAME.app"
echo "Installed /Applications/$APP_NAME.app (signed with: $IDENTITY)"

if [ "${1:-}" != "--no-launch" ]; then
  open "/Applications/$APP_NAME.app"
fi
