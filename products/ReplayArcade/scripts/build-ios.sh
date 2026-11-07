#!/bin/sh
# ReplayArcade's iPhone app (PLAN A3): generates packaging/ios/ReplayArcade.xcodeproj from
# packaging/ios/project.yml + ReplayNES's apps/ios/common.yml, builds it and optionally installs and
# starts it.
#   scripts/build-ios.sh device [--install]      the connected iPhone (automatic signing)
#   scripts/build-ios.sh sim [--install]         the newest iPhone simulator (unsigned)
#   scripts/build-ios.sh generate                only the Xcode project
# REPLAYNES_DIR: the ReplayNES tree with apps/ios (branch ios; default: the submodule).
# Signing: packaging/ios/Config/Signing.local.xcconfig (DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$ROOT/packaging/ios"
REPLAYNES_DIR="$(cd "${REPLAYNES_DIR:-$ROOT/third_party/replaynes}" && pwd)"
export REPLAYNES_IOS_DIR="$REPLAYNES_DIR/apps/ios"
[ -f "$REPLAYNES_IOS_DIR/common.yml" ] || { echo "error: $REPLAYNES_IOS_DIR/common.yml not found (REPLAYNES_DIR: a ReplayNES tree with the iPhone app)"; exit 1; }
WHAT="${1:-sim}"; shift || true
INSTALL=0
for a in "$@"; do [ "$a" = "--install" ] && INSTALL=1; done

XCODEGEN="$(command -v xcodegen || echo "$HOME/.local/bin/xcodegen")"
[ -x "$XCODEGEN" ] || XCODEGEN=/opt/homebrew/bin/xcodegen
[ -x "$XCODEGEN" ] || { echo "error: xcodegen not found"; exit 1; }
(cd "$HERE" && "$XCODEGEN" generate --quiet)
echo "==> project: $HERE/ReplayArcade.xcodeproj (ReplayNES: $REPLAYNES_DIR)"
[ "$WHAT" = generate ] && exit 0

# The version is ReplayArcade's (cmake/product.cmake), the build number the commit count: project.yml's
# MARKETING_VERSION had stayed 0.3.4 through every release (2026-11-07: 0.3.16's code installed as 0.3.4).
VERSION="$(sed -n 's/^set(RN_PRODUCT_VERSION "\(.*\)")/\1/p' "$ROOT/cmake/product.cmake")"
BUILD="$(git -C "$ROOT" rev-list --count HEAD)"
VERSION_ARGS="MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD"
echo "==> version $VERSION ($BUILD)"

BID="$(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *//p' "$HERE/Config/Signing.local.xcconfig" 2>/dev/null | tail -1)"
[ -n "$BID" ] || BID="$(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *//p' "$HERE/Config/Signing.xcconfig" | tail -1)"

case "$WHAT" in
  device)
    DERIVED="$ROOT/build-ios/dd-device"
    xcodebuild -project "$HERE/ReplayArcade.xcodeproj" -scheme ReplayNES -configuration Release \
      -destination generic/platform=iOS -derivedDataPath "$DERIVED" -allowProvisioningUpdates $VERSION_ARGS build
    APP="$DERIVED/Build/Products/Release-iphoneos/ReplayArcade.app"
    echo "==> built $APP"
    [ "$INSTALL" = 1 ] || exit 0
    DEVJSON="$(mktemp)"
    xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null
    DEVICE="$(python3 -I - "$DEVJSON" <<'PY'
import json, sys
for dev in json.load(open(sys.argv[1])).get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality", "physical") == "physical" \
            and dev.get("connectionProperties", {}).get("pairingState") == "paired":
        print(hw.get("udid", "")); break
PY
)"
    rm -f "$DEVJSON"
    [ -n "$DEVICE" ] || { echo "error: no paired iPhone"; exit 1; }
    xcrun devicectl device install app --device "$DEVICE" "$APP"
    xcrun devicectl device process launch --device "$DEVICE" "$BID" ;;
  sim)
    DERIVED="$ROOT/build-ios/dd-sim"
    SIM="$(xcrun simctl list devices available -j | python3 -I -c '
import json, re, sys
d = json.load(sys.stdin)["devices"]
c = [(int(m.group(1)), x["udid"]) for k, v in d.items() if "iOS" in k for x in v
     for m in [re.match(r"iPhone (\d+)", x["name"])] if m]
print(max(c)[1])')"
    xcodebuild -project "$HERE/ReplayArcade.xcodeproj" -scheme ReplayNES -configuration Release \
      -sdk iphonesimulator -destination "id=$SIM" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO $VERSION_ARGS build
    APP="$DERIVED/Build/Products/Release-iphonesimulator/ReplayArcade.app"
    echo "==> built $APP (simulator $SIM)"
    [ "$INSTALL" = 1 ] || exit 0
    xcrun simctl boot "$SIM" 2>/dev/null || true
    xcrun simctl install "$SIM" "$APP"
    xcrun simctl launch --terminate-running-process "$SIM" "$BID" ;;
  *) echo "usage: $0 device|sim|generate [--install]"; exit 2 ;;
esac
