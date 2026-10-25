#!/usr/bin/env bash
# Builds, signs and publishes a ReplayArcade release (all on this machine).
#   scripts/release.sh <version>             build, sign, publish (gh-pages Flatpak repository + GitHub release)
#   NO_PUBLISH=1 scripts/release.sh <version> build and sign into dist/ only
# Outputs (dist/):
#   ReplayArcade-<v>-windows-x64.zip           ReplayArcade.exe, WinSparkle.dll, README.txt, licences
#   appcast-windows.xml                        WinSparkle feed, the zip signed with the EdDSA key
#   io.github.kathoc.ReplayArcade-<v>-x86_64.flatpak   bundle that registers the update repository
# and the signed Flatpak repository on gh-pages (https://kathoc.github.io/ReplayArcade/flatpak/).
# Keys (never printed or copied): ED_KEY (~/.config/replayarcade/sparkle-ed25519.pem, OpenSSL ed25519),
# GPG_HOME (~/.config/replayarcade/gnupg) with GPG_KEY. The public halves: RN_PRODUCT_UPDATE_PUBLIC_KEY in
# cmake/product.cmake and packaging/linux/replayarcade-repo.gpg.
# Game data never ships: every artefact's file list is checked (.githooks/check-no-roms.sh rules).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: scripts/release.sh <version>}"
REPO=kathoc/ReplayArcade
APP_ID=io.github.kathoc.ReplayArcade
ED_KEY="${ED_KEY:-$HOME/.config/replayarcade/sparkle-ed25519.pem}"
GPG_HOME="${GPG_HOME:-$HOME/.config/replayarcade/gnupg}"
GPG_KEY="${GPG_KEY:-968E487DC2C059FD6CAB167787E76CBC7CBAEFFE}"
DIST="$ROOT/dist"
WORK="$ROOT/build/release"
PAGES_URL="https://kathoc.github.io/ReplayArcade/flatpak/"
TAG="v$VERSION"
export PATH="$HOME/.local/bin:$PATH"
git_gh() { git -c credential.helper= -c credential.helper='!gh auth git-credential' "$@"; }
ostree() { flatpak run --filesystem=home --command=ostree org.flatpak.Builder "$@"; }

# ---- checks
PROFILE_VERSION="$(sed -n 's/^set(RN_PRODUCT_VERSION "\(.*\)")/\1/p' "$ROOT/cmake/product.cmake")"
[ "$VERSION" = "$PROFILE_VERSION" ] || { echo "version $VERSION != RN_PRODUCT_VERSION $PROFILE_VERSION"; exit 1; }
grep -q "<release version=\"$VERSION\"" "$ROOT/packaging/linux/$APP_ID.metainfo.xml" ||
  { echo "metainfo has no <release version=\"$VERSION\">"; exit 1; }
[ -z "$(git -C "$ROOT" status --porcelain --ignore-submodules=dirty)" ] || { echo "uncommitted changes"; exit 1; }
"$ROOT/scripts/fbneo-patches.sh" --check >/dev/null || { echo "FBNeo patch not applied"; exit 1; }
[ -f "$ED_KEY" ] && [ -d "$GPG_HOME" ] || { echo "signing keys missing ($ED_KEY, $GPG_HOME)"; exit 1; }
PUB="$(sed -n 's/^set(RN_PRODUCT_UPDATE_PUBLIC_KEY "\(.*\)")/\1/p' "$ROOT/cmake/product.cmake")"
[ "$(openssl pkey -in "$ED_KEY" -pubout -outform DER | tail -c 32 | base64)" = "$PUB" ] ||
  { echo "ED_KEY does not match RN_PRODUCT_UPDATE_PUBLIC_KEY"; exit 1; }
no_game_data() {  # file names on stdin; the same rules as the git hooks, without the size limit
  local bad=0 f
  while IFS= read -r f; do
    case "${f,,}" in
      *.zip|*.7z|*.rar|*.chd|*.nes|*.fds|*.unf|*.rom|*.fs|*.nv|*.arcrec|*.arcrec/*|*/roms/*|roms/*|*/rom/*|rom/*)
        echo "refused (game data): $f" >&2; bad=1 ;;
    esac
  done
  return $bad
}
mkdir -p "$DIST" "$WORK"

# ---- Windows
echo "==> Windows x64"
"$ROOT/scripts/build-windows.sh" x86_64 >"$WORK/windows.log" 2>&1 || { tail -20 "$WORK/windows.log"; exit 1; }
B="$ROOT/build/windows/windows-x86_64/apps/windows"
NAME="ReplayArcade-$VERSION-windows-x64"
STAGE="$WORK/$NAME"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$B/ReplayArcade.exe" "$STAGE/"
[ -f "$B/WinSparkle.dll" ] || { echo "no WinSparkle.dll next to ReplayArcade.exe (RN_PRODUCT_UPDATES?)"; exit 1; }
cp "$B/WinSparkle.dll" "$STAGE/"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
cp "$ROOT/COPYING.md" "$ROOT/LICENSE-FBNeo.txt" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"
cp "$ROOT/third_party/replaynes/THIRD_PARTY_NOTICES.md" "$STAGE/ReplayNES-THIRD_PARTY_NOTICES.md"
cat > "$STAGE/README.txt" <<EOF
ReplayArcade $VERSION for Windows (x64)
https://github.com/$REPO

ReplayNES for arcade games, with FinalBurn Neo as its core.

No ROMs are included. Put the ROM zips you are entitled to use (FinalBurn Neo set names, non-merged,
e.g. gradius.zip) in Documents\\ReplayArcade\\ROM, then start ReplayArcade.exe. The build is not
code-signed: if SmartScreen warns, choose "More info" and "Run anyway". Updates are checked in the app
(signed feed).

Licences: GPL-2.0-or-later with an additional permission for FinalBurn Neo (COPYING.md, LICENSE.txt);
FinalBurn Neo under its own non-commercial licence (LICENSE-FBNeo.txt); THIRD_PARTY_NOTICES.md.
EOF
sed -i 's/$/\r/' "$STAGE/README.txt"
(cd "$STAGE/.." && find "$NAME" -type f) | no_game_data
rm -f "$DIST/$NAME.zip" && (cd "$WORK" && zip -qr -X "$DIST/$NAME.zip" "$NAME")
SIG="$(openssl pkeyutl -sign -inkey "$ED_KEY" -rawin -in "$DIST/$NAME.zip" | base64 -w0)"
# Check the signature against the public key the app embeds.
printf '%s' "$PUB" | base64 -d | cat <(printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00') - > "$WORK/pub.der"
openssl pkeyutl -verify -pubin -keyform DER -inkey "$WORK/pub.der" -rawin -in "$DIST/$NAME.zip" \
  -sigfile <(printf '%s' "$SIG" | base64 -d) >/dev/null || { echo "EdDSA signature does not verify"; exit 1; }
LEN="$(stat -c %s "$DIST/$NAME.zip")"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > "$DIST/appcast-windows.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>ReplayArcade for Windows</title>
    <link>https://github.com/$REPO</link>
    <description>ReplayArcade updates (Windows)</description>
    <language>ja</language>
    <item>
      <title>ReplayArcade $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$NAME.zip" sparkle:os="windows-x64" length="$LEN" type="application/octet-stream" sparkle:edSignature="$SIG"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$DIST/appcast-windows.xml"
echo "    dist/$NAME.zip ($(du -h "$DIST/$NAME.zip" | cut -f1)), dist/appcast-windows.xml"

# ---- Flatpak (Linux / Steam Deck)
echo "==> Flatpak"
SRC="$WORK/flatpak-src"
rm -rf "$SRC" && mkdir -p "$SRC"
rsync -a --exclude='.git' --exclude='/build/' --exclude='/build-*' --exclude='/dist/' --exclude='/.flatpak-builder/' \
  --exclude='*.o' --exclude='*.a' --exclude='*.d' "$ROOT/" "$SRC/"
(cd "$SRC" && find . -type f) | no_game_data
flatpak run org.flatpak.Builder --user --force-clean --disable-updates --state-dir="$WORK/flatpak-state" \
  --repo="$WORK/flatpak-build-repo" "$WORK/flatpak-build" "$SRC/packaging/linux/$APP_ID.yml" >"$WORK/flatpak.log" 2>&1 ||
  { tail -30 "$WORK/flatpak.log"; exit 1; }
(cd "$WORK/flatpak-build/files" && find . -type f) | no_game_data
gpg --homedir "$GPG_HOME" --export "$GPG_KEY" > "$ROOT/packaging/linux/replayarcade-repo.gpg.new"
cmp -s "$ROOT/packaging/linux/replayarcade-repo.gpg.new" "$ROOT/packaging/linux/replayarcade-repo.gpg" 2>/dev/null ||
  { echo "packaging/linux/replayarcade-repo.gpg is not the signing key's public key: commit it first"; rm -f "$ROOT/packaging/linux/replayarcade-repo.gpg.new"; exit 1; }
rm -f "$ROOT/packaging/linux/replayarcade-repo.gpg.new"
GPGKEY_B64="$(base64 -w0 "$ROOT/packaging/linux/replayarcade-repo.gpg")"

PAGES="$ROOT/build/gh-pages"
git -C "$ROOT" fetch -q origin gh-pages 2>/dev/null || true
if [ ! -d "$PAGES/.git" ] && [ ! -f "$PAGES/.git" ]; then
  if git -C "$ROOT" rev-parse -q --verify origin/gh-pages >/dev/null; then
    git -C "$ROOT" worktree add -q --detach "$PAGES" origin/gh-pages
  else
    git -C "$ROOT" worktree add -q --orphan -b gh-pages-publish "$PAGES"
  fi
fi
DEST="$PAGES/flatpak"
mkdir -p "$DEST"
[ -f "$DEST/config" ] || ostree init --mode=archive-z2 --repo="$DEST"
mkdir -p "$DEST/refs/heads" "$DEST/refs/remotes" "$DEST/refs/mirrors"
flatpak build-commit-from --src-repo="$WORK/flatpak-build-repo" --gpg-sign="$GPG_KEY" --gpg-homedir="$GPG_HOME" \
  --no-update-summary --subject="ReplayArcade $VERSION" "$DEST" "app/$APP_ID/x86_64/master"
flatpak build-update-repo --title=ReplayArcade --homepage="https://github.com/$REPO" --default-branch=master \
  --gpg-sign="$GPG_KEY" --gpg-homedir="$GPG_HOME" --generate-static-deltas --static-delta-ignore-ref='*.Debug' \
  --prune --prune-depth=2 "$DEST"
cat > "$DEST/ReplayArcade.flatpakrepo" <<EOF
[Flatpak Repo]
Title=ReplayArcade
Url=$PAGES_URL
Homepage=https://github.com/$REPO
Comment=Record, rewind and replay arcade play (FinalBurn Neo). No ROMs included.
GPGKey=$GPGKEY_B64
EOF
cat > "$DEST/$APP_ID.flatpakref" <<EOF
[Flatpak Ref]
Name=$APP_ID
Branch=master
Title=ReplayArcade
Url=$PAGES_URL
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
SuggestRemoteName=replayarcade
Homepage=https://github.com/$REPO
GPGKey=$GPGKEY_B64
EOF
BUNDLE="$APP_ID-$VERSION-x86_64.flatpak"
flatpak build-bundle --repo-url="$PAGES_URL" --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  --gpg-keys="$ROOT/packaging/linux/replayarcade-repo.gpg" "$DEST" "$DIST/$BUNDLE" "$APP_ID" master
cp "$DEST/$APP_ID.flatpakref" "$DIST/"
touch "$PAGES/.nojekyll"
cat > "$PAGES/index.html" <<EOF
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>ReplayArcade Flatpak repository</title>
<p><a href="https://github.com/$REPO">ReplayArcade</a> $VERSION: Flatpak repository for Linux / Steam Deck. No ROMs are included.</p>
<ul><li><a href="flatpak/$APP_ID.flatpakref">$APP_ID.flatpakref</a>: <code>flatpak install --user ${PAGES_URL}$APP_ID.flatpakref</code></li>
<li><a href="flatpak/ReplayArcade.flatpakrepo">ReplayArcade.flatpakrepo</a>: <code>flatpak remote-add --user replayarcade ${PAGES_URL}ReplayArcade.flatpakrepo</code></li></ul>
EOF
echo "    dist/$BUNDLE ($(du -h "$DIST/$BUNDLE" | cut -f1)), repository $(du -sh "$DEST" | cut -f1)"

if [ "${NO_PUBLISH:-0}" = "1" ]; then
  echo "==> NO_PUBLISH=1: not published (dist/, build/gh-pages)"
  exit 0
fi

# ---- publish: gh-pages (one orphan commit, force-pushed) and the GitHub release
echo "==> gh-pages"
cd "$PAGES"
git checkout -q --orphan gh-pages-publish-new
git add -A
git commit -q -m "Flatpak repository: ReplayArcade $VERSION" -m "Signed OSTree repository (key $GPG_KEY). Generated by scripts/release.sh."
git branch -D gh-pages-publish >/dev/null 2>&1 || true
git branch -m gh-pages-publish
git_gh push -f "https://github.com/$REPO.git" gh-pages-publish:gh-pages
gh api "repos/$REPO/pages" >/dev/null 2>&1 ||
  gh api -X POST "repos/$REPO/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null
cd "$ROOT"
echo "==> GitHub release $TAG"
git -C "$ROOT" tag -f "$TAG" HEAD
git_gh -C "$ROOT" push -f "https://github.com/$REPO.git" "refs/tags/$TAG"
NOTES="$WORK/notes.md"
cat > "$NOTES" <<EOF
ReplayArcade $VERSION. **No ROMs are included.**

- **Windows x64**: \`$NAME.zip\` (unzip, run \`ReplayArcade.exe\`; in-app updates use the signed \`appcast-windows.xml\`).
- **Steam Deck / Linux**: \`flatpak install --user ${PAGES_URL}$APP_ID.flatpakref\` (signed repository, updates with
  \`flatpak update\`), or the bundle \`$BUNDLE\`.

Put the ROM zips you are entitled to use (FinalBurn Neo set names, non-merged) in \`Documents/ReplayArcade/ROM\`.
Licences: GPL-2.0-or-later with an additional permission for FinalBurn Neo, which is under its own non-commercial
licence (COPYING.md, LICENSE-FBNeo.txt).
EOF
gh release create "$TAG" --repo "$REPO" --title "ReplayArcade $VERSION" --notes-file "$NOTES" --latest \
  "$DIST/$NAME.zip" "$DIST/appcast-windows.xml" "$DIST/$BUNDLE" "$DIST/$APP_ID.flatpakref"
echo "==> done: https://github.com/$REPO/releases/tag/$TAG"
