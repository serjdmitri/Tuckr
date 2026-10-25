#!/bin/bash
# Signs a release DMG with Tuckr's own Sparkle key (kept in the login keychain by
# Sparkle's generate_keys) and adds it to updater/appcast.xml, newest first.
#
#   scripts/release-appcast.sh 1.0.1 /path/to/Tuckr-1.0.1.dmg
#
# Then commit and push updater/appcast.xml: the app reads it from the repository's main
# branch (SUFeedURL in boringNotch/Info.plist), which works once the repository is public.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version, e.g. 1.0.1}"
DMG="${2:?path to the DMG}"
BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' /Applications/Tuckr.app/Contents/Info.plist)"
URL="https://github.com/serjdmitri/Tuckr/releases/download/v$VERSION/$(basename "$DMG")"
SIGNATURE="$("$BIN/sign_update" "$DMG")"   # prints: sparkle:edSignature="..." length="..."

python3 - "$VERSION" "$BUILD" "$URL" "$SIGNATURE" <<'PY'
import sys, datetime, email.utils
version, build, url, signature = sys.argv[1:5]
item = f"""        <item>
            <title>{version}</title>
            <pubDate>{email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure url="{url}" type="application/octet-stream" {signature}/>
        </item>
"""
path = "updater/appcast.xml"
text = open(path).read()
marker = "-->\n"
i = text.index(marker) + len(marker)
open(path, "w").write(text[:i] + item + text[i:])
PY
echo "Added $VERSION to updater/appcast.xml"
