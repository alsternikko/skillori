#!/bin/zsh
# Skillori's release in one command. It bumps the version, builds a Release Skillori.app signed
# with Developer ID, has Apple notarize the app and a .dmg around it, puts the version on the
# launch page and the line on what is new on top of the changelog (site/changelog/), copies the
# .dmg to Dropbox/Skillori under a fixed name and waits until Dropbox serves it. Review, commit,
# tag and push yourself afterwards: the push publishes the site on Vercel.
#
#   sh scripts/release.sh 0.1.0 "One or two sentences in English on what is new."
#
# The download buttons point at skillori.app/download, which counts the download and sends it
# on to Skillori.dmg in Dropbox. That link can only be made once the file exists, so the first
# release stops after copying. Right-click Skillori.dmg in Finder, choose Copy Dropbox link, and:
#
#   sh scripts/release.sh --link "<the link>"
#
# Later releases replace the file under the same name and keep its link.
#
#   sh scripts/release.sh --check     # does skillori.app/download lead to the file in Dropbox?
#
# Needs Config/Signing.local.xcconfig and scripts/notarize.conf.local (see scripts/notarize.sh),
# and Xcode's Metal toolchain.
set -euo pipefail

root="${0:A:h:h}"
conf="$root/scripts/release.conf"
local_conf="$root/scripts/notarize.conf.local"
source "$conf"

page="$root/site/index.html"
changelog="$root/site/changelog/index.html"
counter="$root/site/api/download.mjs"
dropbox_file="$DROPBOX_DIR/$DMG_NAME"

say() { print "\n== $1"; }
fail() { print -u2 "release: $1"; exit 1; }

# What Dropbox serves at a link: the file's total size, from a one-byte range request.
served_size() {
  curl -sL -r 0-0 -D - -o /dev/null "$1" | tr -d '\r' | sed -n 's#^[Cc]ontent-[Rr]ange: bytes 0-0/##p' | tail -1
}

# Waits until Dropbox serves the file just copied, so nobody downloads the old one by mistake.
wait_for_dropbox() {
  local want tries=0
  want="$(stat -f %z "$dropbox_file")"
  while [[ "$(served_size "$DMG_URL")" != "$want" ]]; do
    tries=$((tries + 1))
    (( tries > 120 )) && fail "Dropbox doesn't serve the new $DMG_NAME after 10 minutes."
    sleep 5
  done
  print "Dropbox serves the new $DMG_NAME ($want bytes)."
}

# Where skillori.app/download sends a download. A HEAD request, which the counter doesn't count.
check_link() {
  local to
  to="$(curl -sI "$DMG_LINK" | tr -d '\r' | sed -n 's#^[Ll]ocation: ##p' | tail -1)"
  if [[ "$to" == "$DMG_URL" ]]; then
    print "$DMG_LINK leads to the file in Dropbox."
  else
    print -u2 "$DMG_LINK leads to '${to:-nothing}', not to DMG_URL. Push site/api/download.mjs, or check the Vercel project."
    return 1
  fi
}

# ---------- --link: store the Dropbox link in release.conf and the counter ----------
if [[ "${1:-}" == "--link" ]]; then
  given="${2:?Usage: sh scripts/release.sh --link \"<Dropbox link to $DMG_NAME>\"}"
  [[ "$given" == *"/scl/fo/"* ]] && fail "That is a link to a folder. Copy the link to $DMG_NAME itself."
  [[ "$given" == *"/scl/fi/"* ]] || fail "That doesn't look like a Dropbox file link (…/scl/fi/…)."
  url="$(python3 -I - "$given" <<'PY'
import sys, urllib.parse as u
p = u.urlsplit(sys.argv[1])
q = [(k, v) for k, v in u.parse_qsl(p.query) if k == "rlkey"] + [("dl", "1")]
print(u.urlunsplit(("https", "dl.dropboxusercontent.com", p.path, u.urlencode(q), "")))
PY
)"
  python3 -I - "$conf" "$counter" "$url" <<'PY'
import re, sys
conf, counter, url = sys.argv[1:4]
for path, pattern, repl in [
    (conf, r'^DMG_URL=".*"$', f'DMG_URL="{url}"'),
    (counter, r'^const DMG_URL = ".*";$', f'const DMG_URL = "{url}";'),
]:
    s, n = re.subn(pattern, lambda m: repl, open(path, encoding="utf-8").read(), count=1, flags=re.M)
    if n == 0:
        sys.exit(f"Found no DMG_URL in {path}")
    open(path, "w", encoding="utf-8").write(s)
PY
  DMG_URL="$url"
  print "DMG_URL is $url"
  if [[ -f "$dropbox_file" ]]; then
    wait_for_dropbox
  fi
  print "\nCommit and push scripts/release.conf and site/api/download.mjs. Then the buttons lead to Dropbox."
  exit 0
fi

# ---------- --check ----------
if [[ "${1:-}" == "--check" ]]; then
  [[ -n "$DMG_URL" ]] || fail "No DMG_URL yet. See the top of this script."
  [[ -f "$dropbox_file" ]] && wait_for_dropbox
  check_link
  exit $?
fi

# ---------- The release ----------
usage='Usage: sh scripts/release.sh <version> "<what is new, in English>"'
version="${1:?$usage}"
notes="${2:?$usage}"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "The version should look like 0.1.0."

say "Checking"
[[ -f "$local_conf" ]] || fail "Missing $local_conf. See scripts/notarize.sh."
[[ -f "$root/Config/Signing.local.xcconfig" ]] \
  || fail "Missing Config/Signing.local.xcconfig. Copy Config/Signing.local.xcconfig.example and fill it in."
source "$local_conf"
: "${NOTARY_APPLE_ID:?}" "${NOTARY_KEYCHAIN_SERVICE:?}" "${TEAM_ID:?}"
security find-generic-password -s "$NOTARY_KEYCHAIN_SERVICE" -a "$NOTARY_APPLE_ID" >/dev/null 2>&1 \
  || fail "The keychain has no app-specific password under $NOTARY_KEYCHAIN_SERVICE."
identity="$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\"/\1/p" | head -1)"
[[ -n "$identity" ]] || fail "The keychain has no Developer ID Application certificate for team $TEAM_ID."
[[ -d "$DROPBOX_DIR" ]] || fail "No Dropbox folder at $DROPBOX_DIR."
command -v xcodegen >/dev/null || fail "xcodegen is missing (brew install xcodegen)."
print "Signing as $identity."

say "Version $version"
python3 -I - "$root" "$version" <<'PY'
import pathlib, re, sys
root, v = pathlib.Path(sys.argv[1]), sys.argv[2]
p = root / "project.yml"
s = p.read_text(encoding="utf-8")
s, n1 = re.subn(r'^(\s*MARKETING_VERSION: )"[^"]*"', rf'\g<1>"{v}"', s, count=1, flags=re.M)
build = re.search(r'^\s*CURRENT_PROJECT_VERSION: "(\d+)"', s, flags=re.M)
if n1 == 0 or not build:
    sys.exit("Found no MARKETING_VERSION or CURRENT_PROJECT_VERSION in project.yml")
nxt = int(build.group(1)) + 1
s = re.sub(r'^(\s*CURRENT_PROJECT_VERSION: )"\d+"', rf'\g<1>"{nxt}"', s, count=1, flags=re.M)
p.write_text(s, encoding="utf-8")
print(f"project.yml: {v} (build {nxt})")
PY

say "Building"
cd "$root"
xcodegen generate --quiet
xcodebuild -project Skillori.xcodeproj -scheme Skillori -configuration Release \
  -derivedDataPath build/DerivedData clean build -quiet
app="build/DerivedData/Build/Products/Release/Skillori.app"
codesign --verify --strict --deep "$app" || fail "Signature check failed."
codesign -dv "$app" 2>&1 | grep -qF "TeamIdentifier=$TEAM_ID" || fail "Not signed by team $TEAM_ID."
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$built" == "$version" ]] || fail "The app says $built, not $version."

# The password only lives in this process's environment while notarytool runs.
NOTARY_PASSWORD="$(security find-generic-password -s "$NOTARY_KEYCHAIN_SERVICE" -a "$NOTARY_APPLE_ID" -w)"
notarize() {
  xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --team-id "$TEAM_ID" \
    --password "$NOTARY_PASSWORD" --wait | tee /dev/stderr | grep -q "status: Accepted" \
    || fail "Apple didn't accept $(basename "$1")."
}

say "Notarizing the app"
zip="build/Skillori-notarize.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
notarize "$zip"
xcrun stapler staple "$app"

say "Making the .dmg"
# The app and a shortcut to Applications, so the window says where to drag it.
staging="build/dmg"
dmg="build/$DMG_NAME"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Skillori.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Skillori" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" -quiet
codesign --sign "$identity" --timestamp "$dmg"

say "Notarizing the .dmg"
notarize "$dmg"
unset NOTARY_PASSWORD
xcrun stapler staple "$dmg"
# Gatekeeper's own verdict, the one a downloaded copy gets.
spctl -a -vv -t exec "$app" || fail "Gatekeeper doesn't accept Skillori.app."
spctl -a -vv -t open --context context:primary-signature "$dmg" || fail "Gatekeeper doesn't accept the .dmg."
xcrun stapler validate -q "$app" || fail "Skillori.app has no stapled ticket."
xcrun stapler validate -q "$dmg" || fail "The .dmg has no stapled ticket."
print "Apple has notarized Skillori.app and $DMG_NAME."

say "The site"
python3 -I - "$page" "$changelog" "$version" "$notes" <<'PY'
import datetime, html, re, sys
page, changelog, version, notes = sys.argv[1:5]

# Every version on the launch page (the line under the buttons, the closing block, the action bar).
s = open(page, encoding="utf-8").read()
s, n = re.subn(r'\bv\d+\.\d+\.\d+\b', f'v{version}', s)
if n == 0:
    sys.exit("Found no version on the launch page")
open(page, "w", encoding="utf-8").write(s)
print(f"The launch page says v{version} in {n} places.")

# The changelog: the newest on top, marked Latest. Running again for the same version replaces
# its row, so the page never lists a version twice.
day = datetime.date.today()
row = (
    f'      <article class="rel is-latest" id="v{version}">\n'
    f'        <div><h2><a href="#v{version}">v{version}</a></h2>'
    f'<time class="mono" datetime="{day.isoformat()}">{day.day} {day:%b} {day.year}</time></div>\n'
    f'        <p>{html.escape(notes, quote=False)}</p>\n'
    f'      </article>\n'
)
mark = "      <!-- scripts/release.sh adds each version here, newest first. -->\n"
s = open(changelog, encoding="utf-8").read()
s = re.sub(r'      <article class="rel none" id="none">\n.*?      </article>\n', "", s, count=1, flags=re.S)
s, n = re.subn(rf'      <article class="rel[^"]*" id="v{re.escape(version)}">\n.*?      </article>\n', lambda m: row, s, count=1, flags=re.S)
if n == 0:
    if mark not in s:
        sys.exit("Found no place for the version on the changelog")
    s = s.replace('class="rel is-latest"', 'class="rel"')
    s = s.replace(mark, mark + row, 1)
open(changelog, "w", encoding="utf-8").write(s)
print(f"The changelog {'replaces' if n else 'adds'} v{version}.")
PY

say "Copying to Dropbox"
# cp writes into the existing file, so Dropbox keeps its link.
cp "$dmg" "$dropbox_file"
print "$dropbox_file"

if [[ -z "$DMG_URL" ]]; then
  cat >&2 <<EOF

$DMG_NAME is in Dropbox, but there is no link to it yet. Right-click it in Finder
(Dropbox/Skillori), choose Copy Dropbox link, and run:

  sh scripts/release.sh --link "<the link>"

Then commit and push as below.
EOF
else
  say "Waiting for Dropbox"
  wait_for_dropbox
fi

say "Done"
cat <<EOF
Skillori $version is in Dropbox, and the launch page and the changelog say so. Left for you:

  git add project.yml site/index.html site/changelog/index.html scripts/release.conf site/api/download.mjs
  git commit -m "Release $version"
  git tag v$version
  git push origin main --tags

The push publishes the site. Afterwards, sh scripts/release.sh --check confirms that
$DMG_LINK leads to the new file.
EOF
