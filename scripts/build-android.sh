#!/usr/bin/env bash
# Build the ReplayNES Android app (apps/android) as a release APK, signed with the dedicated ReplayNES
# Android release key so that it updates an installed v0.6.5 (or later) in place.
#
# Identity (fixed here, never the Gradle default io.github.replaynes.android):
#   applicationId = io.github.replaynes   (the same id as the v0.6.5 Kotlin release: an update, not a new app)
#   appName       = ReplayNES
#   version       = the root CMake project version (override with RN_VERSION)
# The debug build (gradle assembleDebug, no -PrnApplicationId) keeps the Gradle default id and is a separate
# install; ReplayArcade passes its own profile and id and is untouched by this script.
#
# Signing (never in the repository): the keystore and its passwords come from a Java properties file,
# $REPLAYNES_ANDROID_SIGNING or ~/.config/replaynes/android-signing.properties, with
#   storeFile= storePassword= keyAlias= keyPassword=
# mapped to the environment the Gradle build reads (RN_ANDROID_KEYSTORE, RN_ANDROID_KEYSTORE_PASSWORD,
# RN_ANDROID_KEY_ALIAS, RN_ANDROID_KEY_PASSWORD). Without the file the APK builds but is unsigned
# (and cannot be installed / cannot update an install).
#
# Env: RN_VERSION (default from CMakeLists.txt), REPLAYNES_ANDROID_SIGNING (the properties file),
#      GRADLE (default: gradle), JAVA_HOME (default: JDK 21), GRADLE_TASK (default: assembleRelease).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

APP_ID="io.github.replaynes"
APP_NAME="ReplayNES"
VERSION="${RN_VERSION:-$(sed -n 's/.*project(ReplayNES VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)}"
[ -n "$VERSION" ] || { echo "could not read the version from CMakeLists.txt (set RN_VERSION)" >&2; exit 2; }

: "${JAVA_HOME:=$(/usr/libexec/java_home -v 21 2>/dev/null || true)}"
export JAVA_HOME
GRADLE="${GRADLE:-gradle}"
TASK="${GRADLE_TASK:-assembleRelease}"

# Signing: read the properties file into the environment the build expects. Values never printed.
SIGNING="${REPLAYNES_ANDROID_SIGNING:-$HOME/.config/replaynes/android-signing.properties}"
if [ -f "$SIGNING" ]; then
  prop() { sed -n "s/^$1=//p" "$SIGNING" | head -n1; }
  export RN_ANDROID_KEYSTORE="$(prop storeFile)"
  export RN_ANDROID_KEYSTORE_PASSWORD="$(prop storePassword)"
  export RN_ANDROID_KEY_ALIAS="$(prop keyAlias)"
  export RN_ANDROID_KEY_PASSWORD="$(prop keyPassword)"
  if [ -n "${RN_ANDROID_KEYSTORE:-}" ] && [ -f "$RN_ANDROID_KEYSTORE" ]; then
    echo "signing with the keystore named in $SIGNING (alias ${RN_ANDROID_KEY_ALIAS:-?})"
  else
    echo "WARNING: $SIGNING names no readable keystore; the APK will be unsigned" >&2
  fi
else
  echo "WARNING: no signing properties at $SIGNING; the APK will be unsigned and cannot update an install" >&2
fi

echo "building $APP_NAME $VERSION ($APP_ID) with $GRADLE $TASK"
cd apps/android
"$GRADLE" "$TASK" \
  -PrnApplicationId="$APP_ID" \
  -PrnAppName="$APP_NAME" \
  -PrnVersion="$VERSION"

apk=$(ls -t app/build/outputs/apk/release/*.apk 2>/dev/null | head -n1 || true)
if [ -n "$apk" ]; then
  echo "APK: apps/android/$apk"
  if command -v apksigner >/dev/null 2>&1; then
    echo "--- certificate ---"; apksigner verify --print-certs "$apk" | sed -n '1,4p' || true
  fi
else
  echo "no release APK produced (check the build output)" >&2
  exit 1
fi
