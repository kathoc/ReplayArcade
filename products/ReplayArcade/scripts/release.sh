#!/usr/bin/env bash
# Builds, signs and publishes a ReplayArcade release. The Flatpak is made for x86_64 (Steam Deck) and aarch64
# (ARM handhelds: AYN Thor on Armada), each built natively: this machine's own architecture with flatpak-builder,
# x86_64 on another machine taken unsigned from the GitHub Actions run of HEAD (FLATPAK_FROM=actions forces that,
# FLATPAK_RUN=<id> picks the run). aarch64 needs an aarch64 machine: run it in macsrv's Lima VM "build".
#   ARCHES="x86_64 aarch64" (default): the Flatpak architectures; one left out keeps its last build in the repository
#   scripts/release.sh <version>             build, sign, publish (gh-pages Flatpak repository + GitHub release)
#   NO_PUBLISH=1 scripts/release.sh <version> build and sign into dist/ only
#   CHANGES=<file.md>: what is new, at the top of the release notes
#   RELEASE_ONLY=1: only the GitHub release, from the files already in dist/ and the existing tag (a run that
#   stopped after publishing gh-pages: 2026-11-03, 0.3.10)
#   ANDROID_APK=<file.apk>: the signed Android APK of this version (scripts/build-android.sh release, on a
#   machine with the Android SDK), attached as ReplayArcade-<v>-android-arm64.apk
# Outputs (dist/):
#   ReplayArcade-<v>-windows-x64.zip           ReplayArcade.exe, WinSparkle.dll, README.txt, licences
#   appcast-windows.xml                        WinSparkle feed, the zip signed with the EdDSA key
#   io.github.kathoc.ReplayArcade-<v>-<arch>.flatpak   bundles (x86_64, aarch64) that register the update repository
# and the signed Flatpak repository on gh-pages (https://kathoc.github.io/ReplayArcade/flatpak/).
# Keys (never printed or copied): ED_KEY (~/.config/replayarcade/sparkle-ed25519.pem, OpenSSL ed25519),
# GPG_HOME (~/.config/replayarcade/gnupg) with GPG_KEY. The public halves: RN_PRODUCT_UPDATE_PUBLIC_KEY in
# cmake/product.cmake and packaging/linux/replayarcade-repo.gpg.
# Game data never ships: every artefact's file list is checked (.githooks/check-no-roms.sh rules).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MONO="$(cd "$ROOT/../.." && pwd)"  # the monorepo's root: ReplayNES's sources (ReplayArcade is products/ReplayArcade)
VERSION="${1:?usage: scripts/release.sh <version>}"
REPO=kathoc/ReplayArcade  # the release, gh-pages and the v* tag: where installed copies look for updates
SRC_REPO=kathoc/ReplayNES  # the monorepo: the sources and the Flatpak workflow's runs
APP_ID=io.github.kathoc.ReplayArcade
ED_KEY="${ED_KEY:-$HOME/.config/replayarcade/sparkle-ed25519.pem}"
GPG_HOME="${GPG_HOME:-$HOME/.config/replayarcade/gnupg}"
GPG_KEY="${GPG_KEY:-968E487DC2C059FD6CAB167787E76CBC7CBAEFFE}"
DIST="$ROOT/dist"
WORK="$ROOT/build/release"
PAGES_URL="https://kathoc.github.io/ReplayArcade/flatpak/"
TAG="v$VERSION"                    # in $REPO
MONO_TAG="replayarcade-v$VERSION"  # in the monorepo (ReplayNES's own tags are v*)
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
# A new Flatpak permission stops the in-app update (the portal installs no update that asks for one): the
# users must update once by hand (Discover / flatpak update). Say so in CHANGES, then NEW_PERMISSIONS=1.
MANIFEST="packaging/linux/$APP_ID.yml"
PREV_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'replayarcade-v*' 2>/dev/null || true)"
if [ -n "$PREV_TAG" ]; then
  perms() { sed -n '/^finish-args:/,/^[a-z]/p' | grep -E '^ *- --' | sed 's/^ *- //' | sort; }
  ADDED="$(comm -13 <(git -C "$ROOT" show "$PREV_TAG:./$MANIFEST" 2>/dev/null | perms) <(perms < "$ROOT/$MANIFEST"))"
  if [ -n "$ADDED" ] && [ "${NEW_PERMISSIONS:-}" != 1 ]; then
    echo "new Flatpak permissions since $PREV_TAG (the in-app update will refuse this version):"
    echo "$ADDED" | sed 's/^/  /'
    echo "tell the users to update once with Discover / flatpak update (CHANGES), then rerun with NEW_PERMISSIONS=1"
    exit 1
  fi
fi
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
# Every input checked before anything is published (0.3.10: a missing APK stopped the run after gh-pages).
if [ -n "${ANDROID_APK:-}" ]; then
  [ -f "$ANDROID_APK" ] || { echo "no $ANDROID_APK"; exit 1; }
  unzip -Z1 "$ANDROID_APK" | no_game_data || exit 1
fi
NAME="ReplayArcade-$VERSION-windows-x64"
ARCHES="${ARCHES:-x86_64 aarch64}"
BUNDLES=()
for a in $ARCHES; do
  case "$a" in x86_64|aarch64) ;; *) echo "ARCHES: x86_64 and/or aarch64 (got $a)"; exit 1 ;; esac
  # x86_64 also comes from GitHub Actions; any other architecture only from this machine.
  [ "${RELEASE_ONLY:-0}" = 1 ] || [ "$a" = x86_64 ] || [ "$a" = "$(uname -m)" ] ||
    { echo "the $a Flatpak is built on an $a machine (this is $(uname -m)): macsrv's Lima VM \"build\""; exit 1; }
  BUNDLES+=("$DIST/$APP_ID-$VERSION-$a.flatpak")
done
if [ "${RELEASE_ONLY:-0}" = 1 ]; then
  for f in "$DIST/$NAME.zip" "$DIST/appcast-windows.xml" "${BUNDLES[@]}" "$DIST/$APP_ID.flatpakref"; do
    [ -f "$f" ] || { echo "RELEASE_ONLY: no $f"; exit 1; }
  done
  git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "RELEASE_ONLY: no tag $TAG"; exit 1; }
fi
if [ "${RELEASE_ONLY:-0}" != 1 ]; then

# ---- Windows
echo "==> Windows x64"
"$ROOT/scripts/build-windows.sh" x86_64 >"$WORK/windows.log" 2>&1 || { tail -20 "$WORK/windows.log"; exit 1; }
B="$ROOT/build/windows/windows-x86_64/apps/windows"
STAGE="$WORK/$NAME"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$B/ReplayArcade.exe" "$STAGE/"
[ -f "$B/WinSparkle.dll" ] || { echo "no WinSparkle.dll next to ReplayArcade.exe (RN_PRODUCT_UPDATES?)"; exit 1; }
cp "$B/WinSparkle.dll" "$STAGE/"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
cp "$ROOT/COPYING.md" "$ROOT/LICENSE-FBNeo.txt" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"
cp "$MONO/THIRD_PARTY_NOTICES.md" "$STAGE/ReplayNES-THIRD_PARTY_NOTICES.md"
cat > "$STAGE/README.txt" <<EOF
ReplayArcade $VERSION for Windows (x64)
https://github.com/$REPO

ReplayNES for arcade games, with FinalBurn Neo as its core.

No ROMs are included. Put the ROM zips you are entitled to use (FinalBurn Neo set names, non-merged,
e.g. gradius.zip) in Documents\\ReplayArcade\\ROM, then start ReplayArcade.exe. The build is not
code-signed: if SmartScreen warns, choose "More info" and "Run anyway". Updates are checked in the app
(signed feed).

Source: https://github.com/$SRC_REPO/tree/$MONO_TAG (\`products/ReplayArcade\`, with ReplayNES's sources around it).
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

# ---- Flatpak (Linux: Steam Deck x86_64, ARM handhelds aarch64)
echo "==> Flatpak"
# Each architecture's unsigned repository, signed below as one. The GitHub Actions run is x86_64
# (.github/workflows/flatpak.yml, the same flatpak-builder call).
flatpak_from_actions() {  # <repository dir>
  local R="$1" HEAD_SHA RUN
  HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
  RUN="${FLATPAK_RUN:-$(gh run list --repo "$SRC_REPO" --workflow replayarcade-flatpak.yml --commit "$HEAD_SHA" --status success \
    --limit 1 --json databaseId -q '.[0].databaseId')}"
  [ -n "$RUN" ] || { echo "no successful Flatpak run on GitHub Actions for $HEAD_SHA (push it, wait for the run)"; exit 1; }
  echo "    x86_64 from GitHub Actions run $RUN"
  rm -rf "$WORK/flatpak-ci" "$R" && mkdir -p "$WORK/flatpak-ci"
  gh run download "$RUN" --repo "$SRC_REPO" -n flatpak-repo-x86_64 -D "$WORK/flatpak-ci"
  tar -C "$WORK/flatpak-ci" -xf "$WORK/flatpak-ci/flatpak-repo.tar"
  mv "$WORK/flatpak-ci/repo" "$R"
  [ "$(cat "$R/replayarcade-commit")" = "$HEAD_SHA" ] || { echo "run $RUN built $(cat "$R/replayarcade-commit"), not HEAD"; exit 1; }
  # One monorepo commit holds both ReplayArcade and ReplayNES's sources: replayarcade-commit names it.
  no_game_data < "$R/replayarcade-files"
}
flatpak_local() {  # <arch> <repository dir>: this machine's architecture
  local a="$1" R="$2" SRC="$WORK/flatpak-src"
  echo "    $a built here"
  rm -rf "$SRC" "$R" && mkdir -p "$SRC"
  # The monorepo's root (the manifest builds from it). Not copied: build output (also ReplayNES's download
  # cache in build/, and the Android build's CMake / Gradle trees: .cxx/ holds a copy of FBNeo with its Windows
  # SDK archive) and FBNeo's Windows SDK archive (src/dep/mingw), which the Flatpak does not use; nor ReplayNES's
  # Nestopia (third_party/nestopia: only a NES product builds it, CMakeLists.txt RN_PRODUCT_NES; its sources carry
  # test .nes files and a zip that no_game_data rightly refuses, 2026-11-14 0.3.17).
  rsync -a --exclude='.git' --exclude='/.claude/' --exclude='/build/' --exclude='/build-*' --exclude='/dist/' \
    --exclude='/third_party/nestopia/' \
    --exclude='/.flatpak-builder/' --exclude='/products/ReplayArcade/build/' --exclude='/products/ReplayArcade/build-*' \
    --exclude='/products/ReplayArcade/dist/' --exclude='/products/ReplayArcade/third_party/fbneo/src/dep/mingw/' \
    --exclude='.cxx/' --exclude='.gradle/' --exclude='/apps/android/app/build/' \
    --exclude='*.o' --exclude='*.a' --exclude='*.d' "$MONO/" "$SRC/"
  (cd "$SRC" && find . -type f) | no_game_data
  flatpak run org.flatpak.Builder --user --force-clean --disable-updates --state-dir="$WORK/flatpak-state" \
    --repo="$R" "$WORK/flatpak-build-$a" "$SRC/products/ReplayArcade/packaging/linux/$APP_ID.yml" >"$WORK/flatpak-$a.log" 2>&1 ||
    { tail -30 "$WORK/flatpak-$a.log"; exit 1; }
  (cd "$WORK/flatpak-build-$a/files" && find . -type f) | no_game_data
}
for a in $ARCHES; do
  if [ "$a" = "$(uname -m)" ] && ! { [ "$a" = x86_64 ] && [ "${FLATPAK_FROM:-}" = actions ]; }; then
    flatpak_local "$a" "$WORK/flatpak-build-repo-$a"
  else
    flatpak_from_actions "$WORK/flatpak-build-repo-$a"
  fi
done
gpg --homedir "$GPG_HOME" --export "$GPG_KEY" > "$ROOT/packaging/linux/replayarcade-repo.gpg.new"
cmp -s "$ROOT/packaging/linux/replayarcade-repo.gpg.new" "$ROOT/packaging/linux/replayarcade-repo.gpg" 2>/dev/null ||
  { echo "packaging/linux/replayarcade-repo.gpg is not the signing key's public key: commit it first"; rm -f "$ROOT/packaging/linux/replayarcade-repo.gpg.new"; exit 1; }
rm -f "$ROOT/packaging/linux/replayarcade-repo.gpg.new"
GPGKEY_B64="$(base64 -w0 "$ROOT/packaging/linux/replayarcade-repo.gpg")"

# The published repository: a standalone clone of gh-pages (the last release's OSTree repository is
# kept for deltas and pruning), or a new repository for the first release.
PAGES="$ROOT/build/gh-pages"
if [ ! -d "$PAGES/.git" ]; then
  if git ls-remote --exit-code "https://github.com/$REPO.git" refs/heads/gh-pages >/dev/null 2>&1; then
    git_gh clone -q --depth 1 --branch gh-pages "https://github.com/$REPO.git" "$PAGES"
  else
    git init -q "$PAGES"
  fi
fi
DEST="$PAGES/flatpak"
mkdir -p "$DEST"
[ -f "$DEST/config" ] || ostree init --mode=archive-z2 --repo="$DEST"
mkdir -p "$DEST/refs/heads" "$DEST/refs/remotes" "$DEST/refs/mirrors"
for a in $ARCHES; do
  flatpak build-commit-from --src-repo="$WORK/flatpak-build-repo-$a" --gpg-sign="$GPG_KEY" --gpg-homedir="$GPG_HOME" \
    --no-update-summary --subject="ReplayArcade $VERSION" "$DEST" "app/$APP_ID/$a/master"
done
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
for a in $ARCHES; do
  flatpak build-bundle --arch="$a" --repo-url="$PAGES_URL" --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
    --gpg-keys="$ROOT/packaging/linux/replayarcade-repo.gpg" "$DEST" "$DIST/$APP_ID-$VERSION-$a.flatpak" "$APP_ID" master
done
cp "$DEST/$APP_ID.flatpakref" "$DIST/"
touch "$PAGES/.nojekyll"
cat > "$PAGES/index.html" <<EOF
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>ReplayArcade Flatpak repository</title>
<p><a href="https://github.com/$REPO">ReplayArcade</a> $VERSION: Flatpak repository for Linux / Steam Deck (x86_64) and ARM Linux handhelds (aarch64). No ROMs are included.</p>
<ul><li><a href="flatpak/$APP_ID.flatpakref">$APP_ID.flatpakref</a>: <code>flatpak install --user ${PAGES_URL}$APP_ID.flatpakref</code></li>
<li><a href="flatpak/ReplayArcade.flatpakrepo">ReplayArcade.flatpakrepo</a>: <code>flatpak remote-add --user replayarcade ${PAGES_URL}ReplayArcade.flatpakrepo</code></li></ul>
EOF
for b in "${BUNDLES[@]}"; do echo "    dist/$(basename "$b") ($(du -h "$b" | cut -f1))"; done
echo "    repository $(du -sh "$DEST" | cut -f1)"

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
# GitHub may enable Pages by itself for a new gh-pages branch (the POST then answers 409).
gh api "repos/$REPO/pages" >/dev/null 2>&1 ||
  gh api -X POST "repos/$REPO/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null 2>&1 ||
  gh api "repos/$REPO/pages" >/dev/null
cd "$ROOT"
fi  # RELEASE_ONLY
echo "==> GitHub release $TAG"
if [ "${RELEASE_ONLY:-0}" != 1 ]; then
  git -C "$ROOT" tag -f "$MONO_TAG" HEAD
  git_gh -C "$ROOT" push -f "https://github.com/$SRC_REPO.git" "refs/tags/$MONO_TAG"
  git_gh -C "$ROOT" push -f "https://github.com/$REPO.git" "refs/tags/$MONO_TAG:refs/tags/$TAG"
fi
ANDROID_ASSET=()
if [ -n "${ANDROID_APK:-}" ]; then
  cp "$ANDROID_APK" "$DIST/ReplayArcade-$VERSION-android-arm64.apk"
  ANDROID_ASSET=("$DIST/ReplayArcade-$VERSION-android-arm64.apk")
fi
NOTES="$WORK/notes.md"
{ echo "ReplayArcade $VERSION. **No ROMs are included.**"; echo
  if [ -n "${CHANGES:-}" ]; then cat "$CHANGES"; echo; fi; } > "$NOTES"
cat >> "$NOTES" <<EOF
- **Windows x64**: \`$NAME.zip\` (unzip, run \`ReplayArcade.exe\`; in-app updates use the signed \`appcast-windows.xml\`).
- **Steam Deck / Linux (x86_64), ARM Linux handhelds (aarch64)**: \`flatpak install --user ${PAGES_URL}$APP_ID.flatpakref\`
  (signed repository, updates with \`flatpak update\`), or the bundle for the machine
  (\`$APP_ID-$VERSION-x86_64.flatpak\` / \`-aarch64.flatpak\`).
EOF
if [ ${#ANDROID_ASSET[@]} -gt 0 ]; then cat >> "$NOTES" <<EOF
- **Android (arm64, Android 10 or later with Vulkan)**: \`ReplayArcade-$VERSION-android-arm64.apk\` (install the APK; the
  ROM folder is \`Android/data/io.github.kathoc.replayarcade/files/ReplayArcade/ROM\`). Touch controls or a
  controller.
EOF
fi
cat >> "$NOTES" <<EOF

Put the ROM zips you are entitled to use (FinalBurn Neo set names, non-merged) in \`Documents/ReplayArcade/ROM\`.
Licences: GPL-2.0-or-later with an additional permission for FinalBurn Neo, which is under its own non-commercial
licence (COPYING.md, LICENSE-FBNeo.txt).
EOF
gh release create "$TAG" --repo "$REPO" --title "ReplayArcade $VERSION" --notes-file "$NOTES" --latest \
  "$DIST/$NAME.zip" "$DIST/appcast-windows.xml" "${BUNDLES[@]}" "$DIST/$APP_ID.flatpakref" "${ANDROID_ASSET[@]}"
echo "==> done: https://github.com/$REPO/releases/tag/$TAG"
