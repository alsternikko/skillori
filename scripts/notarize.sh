#!/bin/zsh
# Builds a Release Skillwatch.app, signs it with Developer ID, notarizes it with Apple and
# staples the ticket. Spike version: no DMG and no Sparkle yet.
#
# Needs scripts/notarize.conf.local (not committed) with:
#   NOTARY_APPLE_ID="you@example.com"
#   NOTARY_KEYCHAIN_SERVICE="name-of-keychain-item-holding-an-app-specific-password"
#   TEAM_ID="XXXXXXXXXX"
set -euo pipefail

root="${0:A:h:h}"
conf="$root/scripts/notarize.conf.local"
fail() { print -u2 "notarize: $1"; exit 1; }

[[ -f "$conf" ]] || fail "Missing $conf. See the header of this script."
source "$conf"
: "${NOTARY_APPLE_ID:?}" "${NOTARY_KEYCHAIN_SERVICE:?}" "${TEAM_ID:?}"

security find-generic-password -s "$NOTARY_KEYCHAIN_SERVICE" -a "$NOTARY_APPLE_ID" >/dev/null 2>&1 \
  || fail "The keychain has no app-specific password under $NOTARY_KEYCHAIN_SERVICE."

cd "$root"
xcodegen generate --quiet
xcodebuild -project Skillwatch.xcodeproj -scheme Skillwatch -configuration Release \
  -derivedDataPath build/DerivedData build -quiet

app="build/DerivedData/Build/Products/Release/Skillwatch.app"
codesign --verify --strict --deep "$app" || fail "Signature check failed."
codesign -dv "$app" 2>&1 | grep -qF "TeamIdentifier=$TEAM_ID" || fail "Not signed by team $TEAM_ID."

zip="build/Skillwatch-notarize.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

# The password only lives in this process's environment while notarytool runs.
NOTARY_PASSWORD="$(security find-generic-password -s "$NOTARY_KEYCHAIN_SERVICE" -a "$NOTARY_APPLE_ID" -w)"
xcrun notarytool submit "$zip" --apple-id "$NOTARY_APPLE_ID" --team-id "$TEAM_ID" \
  --password "$NOTARY_PASSWORD" --wait
unset NOTARY_PASSWORD

xcrun stapler staple "$app"
xcrun stapler validate -q "$app" || fail "No stapled ticket."
spctl -a -vv -t exec "$app" || fail "Gatekeeper doesn't accept the app."
print "Notarized and stapled: $app"
