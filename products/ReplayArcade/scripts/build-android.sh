#!/usr/bin/env bash
# Builds ReplayArcade for Android (arm64-v8a APK): ReplayNES's apps/android with ReplayArcade's product
# profile (cmake/product.cmake: FinalBurn Neo and its startup registration), as build-windows.sh does.
#   scripts/build-android.sh [debug|release]   (default debug) -> build/android/ReplayArcade-<variant>.apk
#   release: signed with the key in ~/.config/replayarcade/android-signing.env (RN_ANDROID_KEYSTORE ...;
#   never printed or copied) -> also build/android/ReplayArcade-<version>-android-arm64.apk
# Env: REPLAYNES_DIR (default: the submodule third_party/replaynes). Needs the Android SDK / NDK 30
# (ANDROID_HOME), Java 21 and Gradle 9.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RN="${REPLAYNES_DIR:-$ROOT/third_party/replaynes}"
VARIANT="${1:-debug}"
"$ROOT/scripts/fbneo-patches.sh" --check >/dev/null || "$ROOT/scripts/fbneo-patches.sh"
TASK="assemble$(tr '[:lower:]' '[:upper:]' <<< "${VARIANT:0:1}")${VARIANT:1}"
VERSION="$(sed -n 's/^set(RN_PRODUCT_VERSION "\(.*\)")/\1/p' "$ROOT/cmake/product.cmake")"
if [ "$VARIANT" = release ]; then
  SIGNING="${ANDROID_SIGNING:-$HOME/.config/replayarcade/android-signing.env}"
  [ -f "$SIGNING" ] || { echo "no signing key ($SIGNING)"; exit 1; }
  set -a; . "$SIGNING"; set +a
fi
# A build directory of its own: the ReplayNES APK and this one do not share CMake caches.
(cd "$RN/apps/android" && gradle --no-daemon "$TASK" -PrnProductFile="$ROOT/cmake/product.cmake" \
  -PrnApplicationId=io.github.kathoc.replayarcade -PrnAppName=ReplayArcade \
  -PrnIcon="$ROOT/packaging/linux/artwork/png/hicolor/512.png" -PrnVersion="$VERSION" \
  -Dorg.gradle.project.buildDir="$ROOT/build/android/gradle")
mkdir -p "$ROOT/build/android"
cp "$(ls "$ROOT/build/android/gradle"/outputs/apk/"$VARIANT"/*.apk | head -1)" "$ROOT/build/android/ReplayArcade-$VARIANT.apk"
if [ "$VARIANT" = release ]; then
  cp "$ROOT/build/android/ReplayArcade-release.apk" "$ROOT/build/android/ReplayArcade-$VERSION-android-arm64.apk"
  ls -la "$ROOT/build/android/ReplayArcade-$VERSION-android-arm64.apk"
else
  ls -la "$ROOT/build/android/ReplayArcade-$VARIANT.apk"
fi
