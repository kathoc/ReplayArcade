#!/usr/bin/env bash
# End-to-end test of the Windows in-app update in the rtxsrv Windows 11 VM (~/vm/replaynes-win11/vm.sh),
# without publishing anything and without the release key: a throw-away EdDSA key signs a feed served
# from this machine (the guest reaches it as 10.0.2.2); the old build (OLD_VERSION) runs in the VM's
# desktop session with REPLAYARCADE_APPCAST_URL pointing at that feed and "update apply" (check and
# install without asking). Passes when the installed ReplayArcade.exe reports NEW_VERSION.
#   scripts/test-update-windows.sh
# Env: OLD_VERSION (0.0.9), NEW_VERSION (0.1.1), PORT (8767), VM (~/vm/replaynes-win11/vm.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD_VERSION="${OLD_VERSION:-0.0.9}"
NEW_VERSION="${NEW_VERSION:-0.1.1}"
PORT="${PORT:-8767}"
VM="${VM:-$HOME/vm/replaynes-win11/vm.sh}"
W="$ROOT/build/update-test/windows"
mkdir -p "$W/feed"

echo "==> throw-away EdDSA key"
openssl genpkey -algorithm ed25519 -out "$W/test-key.pem" 2>/dev/null
PUB="$(openssl pkey -in "$W/test-key.pem" -pubout -outform DER | tail -c 32 | base64)"

for v in "$OLD_VERSION" "$NEW_VERSION"; do
  echo "==> build $v"
  VERSION_OVERRIDE="$v" WIN_BUILD_BASE="$W/build-$v" EXTRA_CMAKE_ARGS="-DRNW_UPDATE_PUBLIC_KEY=$PUB" \
    "$ROOT/scripts/build-windows.sh" x86_64 >"$W/build-$v.log" 2>&1 || { tail -20 "$W/build-$v.log"; exit 1; }
done
pkg() {  # pkg <version> <dir>: the release layout (exe + WinSparkle.dll)
  local b="$W/build-$1/windows-x86_64/apps/windows"
  rm -rf "$2" && mkdir -p "$2" && cp "$b/ReplayArcade.exe" "$b/WinSparkle.dll" "$2/"
}
OLD="$W/ReplayArcade-$OLD_VERSION-windows-x64"; pkg "$OLD_VERSION" "$OLD"
NAME="ReplayArcade-$NEW_VERSION-windows-x64"; pkg "$NEW_VERSION" "$W/$NAME"
rm -f "$W/feed/$NAME.zip" && (cd "$W" && zip -qr -X "$W/feed/$NAME.zip" "$NAME")
SIG="$(openssl pkeyutl -sign -inkey "$W/test-key.pem" -rawin -in "$W/feed/$NAME.zip" | base64 -w0)"
cat > "$W/feed/appcast-windows.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel><title>ReplayArcade update test</title>
    <item><title>ReplayArcade $NEW_VERSION</title>
      <sparkle:version>$NEW_VERSION</sparkle:version><sparkle:shortVersionString>$NEW_VERSION</sparkle:shortVersionString>
      <enclosure url="http://10.0.2.2:$PORT/$NAME.zip" sparkle:os="windows-x64" length="$(stat -c %s "$W/feed/$NAME.zip")" type="application/octet-stream" sparkle:edSignature="$SIG"/>
    </item></channel></rss>
EOF
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$W/feed" >"$W/http.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT

echo "==> copy $OLD_VERSION into the VM and run it in the desktop session"
"$VM" ssh 'Remove-Item -Recurse -Force C:\ratest -ErrorAction SilentlyContinue; New-Item -ItemType Directory C:\ratest | Out-Null'
scp -q -P 2222 -i "$HOME/.ssh/replaynes_winvm" -o UserKnownHostsFile="$(dirname "$VM")/known_hosts" -r "$OLD" tester@127.0.0.1:C:/ratest/
"$VM" ssh "C:\\ratest\\$(basename "$OLD")\\ReplayArcade.exe --version"
cat > "$W/run.cmd" <<EOF
set REPLAYARCADE_APPCAST_URL=http://10.0.2.2:$PORT/appcast-windows.xml
cd /d C:\\ratest\\$(basename "$OLD")
ReplayArcade.exe --windowed --log C:\\ratest\\app.log --script "wait 8; update apply"
EOF
sed -i 's/$/\r/' "$W/run.cmd"
scp -q -P 2222 -i "$HOME/.ssh/replaynes_winvm" -o UserKnownHostsFile="$(dirname "$VM")/known_hosts" "$W/run.cmd" tester@127.0.0.1:C:/ratest/run.cmd
"$VM" ssh 'schtasks /create /tn ratest /tr C:\ratest\run.cmd /sc once /st 23:59 /it /ru tester /f | Out-Null; schtasks /run /tn ratest | Out-Null'
for i in $(seq 1 60); do
  sleep 5
  v="$("$VM" ssh "C:\\ratest\\$(basename "$OLD")\\ReplayArcade.exe --version" 2>/dev/null | tr -d '\r' || true)"
  echo "    $((i * 5)) s: $v"
  [ "$v" = "ReplayArcade $NEW_VERSION" ] && break
done
"$VM" shot "$W/vm-after.png" >/dev/null || true
"$VM" ssh 'Get-Content -ErrorAction SilentlyContinue $env:LOCALAPPDATA\ReplayArcade\Update\update.log | Select-Object -Last 15; Get-Content -ErrorAction SilentlyContinue C:\ratest\app.log | Select-String -Pattern "update" | Select-Object -Last 10' || true
if [ "${v:-}" = "ReplayArcade $NEW_VERSION" ]; then echo "PASS: updated to $NEW_VERSION"; else echo "FAIL: still '${v:-?}'"; exit 1; fi
