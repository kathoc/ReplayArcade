#!/usr/bin/env bash
# Builds ReplayArcade for Android (arm64-v8a APK): ReplayNES's apps/android with ReplayArcade's product
# profile (cmake/product.cmake: FinalBurn Neo and its startup registration), as build-windows.sh does.
#   scripts/build-android.sh [debug|release]   (default debug) -> build/android/ReplayArcade-<variant>.apk
#   release: signed with the key in ~/.config/replayarcade/android-signing.env (RN_ANDROID_KEYSTORE ...;
#   never printed or copied) -> also build/android/ReplayArcade-<version>-android-arm64.apk
# Env: REPLAYNES_DIR (default: the monorepo's root). Needs the Android SDK / NDK 30
# (ANDROID_HOME), Java 21 and Gradle 9.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RN="$(cd "${REPLAYNES_DIR:-$ROOT/../..}" && pwd)"  # the monorepo's root
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
# Gradle's work folder per ReplayNES tree: two trees (the submodule, a worktree via REPLAYNES_DIR) in one folder
# left the other tree's intermediates behind (2026-11-03: compressReleaseAssets "already contains entry
# assets/fonts/NotoSansJP-Regular.otf" after a worktree build).
GBUILD="$ROOT/build/android/gradle-$(printf '%s' "$(cd "$RN" && pwd)" | shasum | cut -c1-8)"
(cd "$RN/apps/android" && gradle --no-daemon "$TASK" -PrnProductFile="$ROOT/cmake/product.cmake" \
  -PrnApplicationId=io.github.kathoc.replayarcade -PrnAppName=ReplayArcade \
  -PrnIcon="$ROOT/packaging/linux/artwork/png/hicolor/512.png" -PrnVersion="$VERSION" \
  -Dorg.gradle.project.buildDir="$GBUILD")
mkdir -p "$ROOT/build/android"
cp "$(ls "$GBUILD"/outputs/apk/"$VARIANT"/*.apk | head -1)" "$ROOT/build/android/ReplayArcade-$VARIANT.apk"
if [ "$VARIANT" = release ]; then
  cp "$ROOT/build/android/ReplayArcade-release.apk" "$ROOT/build/android/ReplayArcade-$VERSION-android-arm64.apk"
  ls -la "$ROOT/build/android/ReplayArcade-$VERSION-android-arm64.apk"
else
  ls -la "$ROOT/build/android/ReplayArcade-$VARIANT.apk"
fi
