#!/bin/bash
# Makes a Tuckr release: builds it, makes the DMG, signs the update and the update feed with
# Tuckr's own key (Sparkle's, kept in the login keychain), publishes the GitHub release and then the
# feed, so that running copies of the app offer the update.
#
#   scripts/release.sh 1.0.1 "What is new, in a few lines"
#
# The feed (updater/appcast.xml) is read by the app from this repository's main branch. It is
# signed: an app built with SURequireSignedFeed refuses a feed or a download that was not
# signed with the private key, so someone who only gets into the GitHub account cannot push an
# update. Keep that key safe (see docs/UPDATES.md).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version, e.g. 1.0.1}"
NOTES="${2:-Bug fixes and improvements.}"
REPO="serjdmitri/Tuckr"
BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
PBX="boringNotch.xcodeproj/project.pbxproj"

[ -z "$(git status --porcelain -- boringNotch Packages scripts)" ] || { echo "Commit your changes first." >&2; exit 1; }
git rev-parse --verify "v$VERSION" >/dev/null 2>&1 && { echo "v$VERSION already exists." >&2; exit 1; }
# Sparkle only offers an update with a higher build number than the one running.
BUILD=$(( $(grep -m1 'CURRENT_PROJECT_VERSION' "$PBX" | tr -dc '0-9') + 1 ))
sed -i '' -e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/" -e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD;/" "$PBX"

scripts/install.sh --no-launch

WORK="dist/release-$VERSION"
rm -rf "$WORK"; mkdir -p "$WORK"
DMG="Tuckr-$VERSION.dmg"
scripts/make-dmg.sh /Applications/Tuckr.app "$WORK/$DMG"

# The feed: the earlier entries are kept, the new one is added and the whole thing signed.
FEED="$WORK/feed"; mkdir -p "$FEED"
cp updater/appcast.xml "$FEED/appcast.xml"
cp "$WORK/$DMG" "$FEED/"
printf '%s\n' "$NOTES" > "$FEED/Tuckr-$VERSION.md"
"$BIN/generate_appcast" --embed-release-notes --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" "$FEED"
grep -q "sparkle-signatures" "$FEED/appcast.xml" || { echo "The feed was not signed: stopping." >&2; exit 1; }

# The GitHub release first, so the feed never points at a file that is not there yet.
git add "$PBX"; git commit -q -m "Version $VERSION"; git push -q origin main
gh release create "v$VERSION" "$WORK/$DMG" --repo "$REPO" --target main --title "v$VERSION" --notes "$NOTES"
cp "$FEED/appcast.xml" updater/appcast.xml
git add updater/appcast.xml; git commit -q -m "Update feed: $VERSION"; git push -q origin main
echo "Released $VERSION (build $BUILD)."
