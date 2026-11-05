#!/bin/bash
# scripts/test-android-emu.sh on every Android version the app supports, one emulator at a time (headless,
# wiped: as a new device), each stopped before the next. AVDs: api29 api30 api33 api36 (pixel_9 profile,
# google_apis arm64; avdmanager create avd -n apiNN -k "system-images;android-NN;google_apis;arm64-v8a" -d pixel_9).
#   scripts/test-android-matrix.sh <test ROM zip> <apk> [avd ...]
#
# It always ends, in bounded time (2026-11-05: an emulator that died left `adb logcat` waiting all night, and
# that run, once a new emulator appeared, killed it with an unnamed `adb emu kill`): one run at a time (a lock);
# every emulator on its own port, every adb call naming it (-s emulator-<port>) with a time limit; the boot
# waited for at most EMU_BOOT_MAX_S, giving up when the emulator process is gone; each version's test bounded
# by its own limit (test-android-emu.sh); this script's emulators stopped on any exit.
set -u
ZIP=${1:?usage: scripts/test-android-matrix.sh <1942.zip> <apk> [avd ...]}; APK=${2:?apk}; shift 2
AVDS=${*:-api29 api30 api33 api36}
SDK=${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}
ADB=$SDK/platform-tools/adb; E=$SDK/emulator/emulator
here=$(cd "$(dirname "$0")" && pwd); out=${EMU_OUT:-$here/../build/emu-matrix}; mkdir -p "$out"
BOOT_MAX=${EMU_BOOT_MAX_S:-300}
LOCK=${TMPDIR:-/tmp}/replayarcade-emu-matrix.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  holder=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then echo "another run (pid $holder) is on: $LOCK"; exit 2; fi
  rm -rf "$LOCK"; mkdir "$LOCK"   # a stale lock: its run is gone
fi
echo $$ > "$LOCK/pid"
EP=""; SERIAL=""; TP=""
stop_emulator() {
  [ -n "$TP" ] && { pkill -P "$TP" 2>/dev/null; kill "$TP" 2>/dev/null; }; TP=""
  [ -n "$SERIAL" ] && timeout 30 "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1
  if [ -n "$EP" ]; then
    for i in $(seq 1 40); do kill -0 "$EP" 2>/dev/null || break; sleep 1; done
    kill -9 "$EP" 2>/dev/null
  fi
  EP=""; SERIAL=""
}
trap 'stop_emulator; rm -rf "$LOCK"' EXIT
trap 'exit 130' INT TERM
total=0; port=5580
for avd in $AVDS; do
  echo "===== $avd"
  SERIAL=emulator-$port
  "$E" -avd "$avd" -port "$port" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -no-snapshot -wipe-data \
    > "$out/$avd-emulator.log" 2>&1 &
  EP=$!
  booted=0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$BOOT_MAX" ]; do
    kill -0 "$EP" 2>/dev/null || { echo "FAIL $avd: the emulator exited while booting ($out/$avd-emulator.log)"; break; }
    [ "$(timeout 10 "$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && { booted=1; break; }
    sleep 3
  done
  if [ $booted != 1 ]; then
    [ $(( $(date +%s) - t0 )) -ge "$BOOT_MAX" ] && echo "FAIL $avd: not booted in ${BOOT_MAX} s"
    total=$((total + 1)); stop_emulator; port=$((port + 2)); continue
  fi
  sleep 20
  a="timeout 30 $ADB -s $SERIAL"
  $a shell settings put system accelerometer_rotation 0; $a shell settings put system user_rotation 0
  $a shell input keyevent KEYCODE_WAKEUP; $a shell wm dismiss-keyguard >/dev/null 2>&1
  # In the background and waited for: a stop (TERM, INT) is handled at once - bash runs a trap only after a
  # foreground child ends, so a stopped run went on with its test and emulator (2026-11-05).
  SERIAL=$SERIAL EMU_SHOTS="$out/$avd" bash "$here/test-android-emu.sh" "$ZIP" "$APK" > "$out/$avd.txt" 2>&1 &
  TP=$!; wait "$TP"; TP=""
  grep -E "Android SDK|FAIL|failures" "$out/$avd.txt"
  n=$(grep -oE "failures: [0-9]+" "$out/$avd.txt" | tail -1 | grep -oE "[0-9]+"); total=$((total + ${n:-1}))
  grep -q "aborting" "$out/$avd-emulator.log" && echo "  (the emulator logged an abort: $out/$avd-emulator.log)"
  stop_emulator; port=$((port + 2))
done
echo "all versions: failures $total"
