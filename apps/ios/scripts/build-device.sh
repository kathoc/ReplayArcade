#!/bin/sh
# Builds ReplayNES for a real iPhone (signed with your team; a free "Personal Team" works) and,
# with --install, installs and starts it on the connected iPhone.
#
#   apps/ios/scripts/build-device.sh --team ABCDE12345 --bundle-id io.github.<you>.replaynes.dev
#   apps/ios/scripts/build-device.sh --install          # later runs (values are remembered)
#
# The team id and bundle id are written to apps/ios/Config/Signing.local.xcconfig (not committed);
# Xcode uses the same file. Requirements: Xcode with your Apple ID added (Xcode › Settings ›
# Accounts), XcodeGen, CMake (+ Ninja), the iPhone connected by cable (or paired over Wi-Fi) with
# Developer Mode on. See apps/ios/README.md.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
LOCAL="$HERE/Config/Signing.local.xcconfig"
TEAM="${TEAM_ID:-}"
BUNDLE="${BUNDLE_ID:-}"
INSTALL=0
CONFIG=Release

while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --bundle-id) BUNDLE="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --debug) CONFIG=Debug; shift ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
done

value() { [ -f "$LOCAL" ] && sed -n "s/^$1 *= *//p" "$LOCAL" | tail -1 || true; }
[ -n "$TEAM" ] || TEAM="$(value DEVELOPMENT_TEAM)"
[ -n "$BUNDLE" ] || BUNDLE="$(value PRODUCT_BUNDLE_IDENTIFIER)"

if [ -z "$TEAM" ]; then
  cat <<'MSG'
error: no team id yet.
  1. Xcode › Settings › Accounts: add your Apple ID (a free account gives a "Personal Team").
  2. Find the team id (10 characters):
       security find-certificate -a -c "Apple Development" -p | openssl x509 -noout -subject
     (the OU= value), or open apps/ios/ReplayNES.xcodeproj › ReplayNES target › Signing &
     Capabilities, choose your team, and read it from the build settings (DEVELOPMENT_TEAM).
  3. Run again with  --team <TEAMID> --bundle-id io.github.<you>.replaynes.dev
MSG
  exit 1
fi
if [ -z "$BUNDLE" ] || [ "$BUNDLE" = "io.github.replaynes.dev" ]; then
  echo "error: choose a bundle id that is unique to you, e.g. --bundle-id io.github.<you>.replaynes.dev"
  exit 1
fi

cat > "$LOCAL" <<EOF
// Written by scripts/build-device.sh (not committed).
DEVELOPMENT_TEAM = $TEAM
PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE
EOF
echo "==> signing: team $TEAM, bundle id $BUNDLE"

XCODEGEN="$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)"
[ -x "$XCODEGEN" ] || { echo "error: xcodegen not found (brew install xcodegen)"; exit 1; }
(cd "$HERE" && "$XCODEGEN" generate --quiet)

# The connected iPhone (devicectl, Xcode 15+): a free team can only sign for registered devices,
# and Xcode registers the one it builds for.
DEVICE=""
DEVJSON="$(mktemp)"
if xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1; then
  DEVICE="$(python3 -I - "$DEVJSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for dev in d.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and dev.get("connectionProperties", {}).get("pairingState") == "paired":
        print(hw.get("udid", "")); break
PY
)"
fi
rm -f "$DEVJSON"
if [ -n "$DEVICE" ]; then DEST="id=$DEVICE"; echo "==> iPhone: $DEVICE"; else DEST="generic/platform=iOS"; echo "==> no paired iPhone found: generic build"; fi

DERIVED="$REPO/build/ios-device"
xcodebuild -project "$HERE/ReplayNES.xcodeproj" -scheme ReplayNES -configuration "$CONFIG" \
  -destination "$DEST" -derivedDataPath "$DERIVED" -allowProvisioningUpdates build
APP="$DERIVED/Build/Products/$CONFIG-iphoneos/ReplayNES.app"
echo "==> built $APP"

if [ "$INSTALL" = 1 ]; then
  [ -n "$DEVICE" ] || { echo "error: connect and unlock the iPhone (Developer Mode on), then run again"; exit 1; }
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" || \
    echo "note: if iOS says the developer is not trusted: Settings › General › VPN & Device Management › your Apple ID › Trust"
fi
