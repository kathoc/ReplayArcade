#!/usr/bin/env bash
# End-to-end test of the Steam Deck update path without publishing anything: builds the current tree
# as a newer version (TEST_VERSION, default 0.1.1), adds it as a signed commit to a copy of the
# published Flatpak repository, serves that copy over HTTP from this machine, points the Deck's
# remote at it, lets the app find and install the update, then restores the remote URL and the
# installed commit.
#   scripts/test-update-deck.sh            (needs build/gh-pages from scripts/release.sh)
# Env: DECK (deck@steamdeck.local), TEST_VERSION, PORT (8766), HOST_IP (this machine's LAN address).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DECK="${DECK:-deck@steamdeck.local}"
TEST_VERSION="${TEST_VERSION:-0.1.1}"
PORT="${PORT:-8766}"
HOST_IP="${HOST_IP:-$(hostname -I | awk '{print $1}')}"
APP_ID=io.github.kathoc.ReplayArcade
GPG_HOME="${GPG_HOME:-$HOME/.config/replayarcade/gnupg}"
GPG_KEY="${GPG_KEY:-968E487DC2C059FD6CAB167787E76CBC7CBAEFFE}"
PAGES_URL="https://kathoc.github.io/ReplayArcade/flatpak/"
W="$ROOT/build/update-test"
ostree() { flatpak run --filesystem=home --command=ostree org.flatpak.Builder "$@"; }
[ -f "$ROOT/build/gh-pages/flatpak/config" ] || { echo "no build/gh-pages (run scripts/release.sh first)"; exit 1; }

echo "==> build $TEST_VERSION from the current tree"
mkdir -p "$W"
rm -rf "$W/src" "$W/repo"
rsync -a --exclude='.git' --exclude='/build/' --exclude='/build-*' --exclude='/dist/' --exclude='/.flatpak-builder/' \
  --exclude='/third_party/replaynes/build/' --exclude='/third_party/fbneo/src/dep/mingw/' \
  --exclude='*.o' --exclude='*.a' --exclude='*.d' "$ROOT/" "$W/src/"
sed -i "s/^set(RN_PRODUCT_VERSION \".*\")/set(RN_PRODUCT_VERSION \"$TEST_VERSION\")/" "$W/src/cmake/product.cmake"
sed -i "s|<releases>|<releases>\n    <release version=\"$TEST_VERSION\" date=\"$(date -u +%F)\"/>|" "$W/src/packaging/linux/$APP_ID.metainfo.xml"
flatpak run org.flatpak.Builder --user --force-clean --disable-updates --state-dir="$W/state" \
  --repo="$W/build-repo" "$W/build" "$W/src/packaging/linux/$APP_ID.yml" >"$W/flatpak.log" 2>&1 || { tail -30 "$W/flatpak.log"; exit 1; }
cp -a "$ROOT/build/gh-pages/flatpak" "$W/repo"
flatpak build-commit-from --src-repo="$W/build-repo" --gpg-sign="$GPG_KEY" --gpg-homedir="$GPG_HOME" \
  --no-update-summary --subject="ReplayArcade $TEST_VERSION (update test)" "$W/repo" "app/$APP_ID/x86_64/master"
flatpak build-update-repo --gpg-sign="$GPG_KEY" --gpg-homedir="$GPG_HOME" "$W/repo" >/dev/null
NEW="$(ostree --repo="$W/repo" rev-parse "app/$APP_ID/x86_64/master")"

echo "==> serve $W/repo at http://$HOST_IP:$PORT/"
python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$W/repo" >"$W/http.log" 2>&1 &
SERVER=$!
OLD="$(ssh "$DECK" "flatpak info --user $APP_ID | sed -n 's/^ *Commit: //p'")"
restore() {
  echo "==> restore the Deck (remote URL, commit $OLD) and stop the server"
  ssh "$DECK" "flatpak remote-modify --user --url=$PAGES_URL replayarcade-origin; \
    flatpak update --user -y --noninteractive --commit=$OLD $APP_ID >/dev/null 2>&1; flatpak info --user $APP_ID | grep -E 'Version|Commit'" || true
  kill "$SERVER" 2>/dev/null || true
}
trap restore EXIT
sleep 1
ssh "$DECK" "flatpak remote-modify --user --url=http://$HOST_IP:$PORT/ replayarcade-origin && flatpak info --user $APP_ID | grep -E 'Version|Commit'"

echo "==> the app finds and installs the update"
R=/home/deck/Documents/ReplayArcade
ssh "$DECK" "mkdir -p $R/shots; DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 timeout 400 flatpak run $APP_ID --script \
  'wait 6;shotdir $R/shots;page system.about;updatewait available 120;shot update-1-available.png;update apply;updatewait installed 300;shot update-2-installed.png;quit' 2>&1 | grep -E 'script: (updatewait|update|shot)|screenshot|updates:'" || true
ssh "$DECK" "flatpak info --user $APP_ID | grep -E 'Version|Commit'; flatpak run $APP_ID --version"
INSTALLED="$(ssh "$DECK" "flatpak info --user $APP_ID | sed -n 's/^ *Commit: //p'")"
if [ "$INSTALLED" = "$NEW" ]; then echo "PASS: the app installed $TEST_VERSION ($NEW)"; else echo "FAIL: installed $INSTALLED, expected $NEW"; fi
rsync -a "$DECK:$R/shots/update-*.png" "$W/" 2>/dev/null || true
