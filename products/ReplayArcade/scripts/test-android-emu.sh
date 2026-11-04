#!/bin/bash
# ReplayArcade on the Android emulator (1080x2424, portrait): getting ROMs in, the picker, Files, coming back
# from other apps. One PASS / FAIL line per check. Usage: emu-import-test.sh [apk]
# The app's own screen is ImGui (no accessibility nodes): its rows are tapped by position; the system's screens
# (picker, Files, share sheet) by their text through uiautomator.
A=~/Library/Android/sdk/platform-tools/adb
P=io.github.kathoc.replayarcade
ACT=$P/io.github.replaynes.android.MainActivity
LOG=/sdcard/Android/data/$P/files/Logs/ReplayArcade.log
ROMDIR=/sdcard/Android/data/$P/files/ReplayArcade/ROM
OUT=${EMU_SHOTS:-$(dirname "$0")/../build/emu-shots}; rm -rf "$OUT"; mkdir -p "$OUT"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; $A exec-out screencap -p > "$OUT/fail-$(echo "$*" | cut -c1-2 | tr -d ' ').png"; fails=$((fails+1)); }
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
top() { $A shell dumpsys activity activities | grep -m1 topResumedActivity; }
app_top() { top | grep -q "$P/"; }
picker_top() { top | grep -q "documentsui.picker.PickActivity"; }
files_top() { top | grep -q "documentsui.files.FilesActivity"; }
wait_for() { for i in $(seq 1 ${2:-20}); do eval "$1" && return 0; sleep 0.5; done; return 1; }
# Upright since this start: a line after the log's length at the start says the swapchain is 1080x2424 (a cold
# start makes a landscape surface first and turns it; an older line of the log must not count).
mark() { START_LINE=$($A shell "wc -l < $LOG" | tr -d '\r '); }
upright() { $A shell "tail -n +$((START_LINE+1)) $LOG" | grep -q "swapchain 1080x2424\|surface: changed 1080x2424"; }
log_lines() { $A shell "grep -c '$1' $LOG" | tr -d '\r'; }
# Tap a node of a system screen by its text (the first one; the centre of its bounds).
tap_text() {
  $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  local b; b=$($A shell cat /sdcard/ui.xml | tr '>' '\n' | grep -m1 "text=\"$1\"" | grep -o 'bounds="[^"]*"' | grep -oE '[0-9]+' | tr '\n' ' ')
  [ -z "$b" ] && return 1
  set -- $b; $A shell input tap $(( ($1+$3)/2 )) $(( ($2+$4)/2 )); return 0
}
# Long press a node by its text (selects a file in Files).
press_text() {
  $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  local b; b=$($A shell cat /sdcard/ui.xml | tr '>' '\n' | grep -m1 "text=\"$1\"" | grep -o 'bounds="[^"]*"' | grep -oE '[0-9]+' | tr '\n' ' ')
  [ -z "$b" ] && return 1
  set -- $b; local x=$(( ($1+$3)/2 )) y=$(( ($2+$4)/2 )); $A shell input swipe $x $y $x $y 900; return 0
}
screen_has() { $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; $A shell cat /sdcard/ui.xml | grep -q "text=\"$1\""; }
close_system() { for i in $(seq 1 10); do app_top && return 0; $A shell input keyevent KEYCODE_BACK; sleep 1.2; done; }
front() { mark; $A shell am start -n $ACT > /dev/null 2>&1; wait_for app_top; wait_for upright 30; sleep 2.5; }
cold() { $A shell am force-stop $P; front; }
folders_page() { $A shell input tap 930 55; sleep 1.5; $A shell input tap 699 157; sleep 1.2; $A shell input tap 540 532; sleep 1.5; }
ROW_ADD=170; ROW_ROMS=266
empty_add_button() { $A shell input tap 230 1172; }   # the empty library's first button

[ -n "$1" ] && $A install -r "$1" | tail -1
$A shell am force-stop com.google.android.documentsui
$A shell "mkdir -p /sdcard/ROMs; cp /sdcard/Download/1942.zip /sdcard/ROMs/1942.zip"
$A shell rm -f $ROMDIR/1942.zip

if [ "${ONLY:-}" != G ]; then
# A. The empty library: Add ROMs opens the picker; it starts where zips are listed.
cold
empty_add_button
check "A1 empty library: Add ROMs opens the picker" wait_for picker_top
sleep 2; check "A2 the picker starts with 1942.zip listed" screen_has "1942.zip"
# B. Pick it: copied, the library shows it (a scan result applied without slack).
lib0=$(log_lines "library: 1 ROMs")
tap_text "1942.zip"; wait_for app_top 30
check "B1 the zip is copied into the ROM folder" wait_for "$A shell ls $ROMDIR/1942.zip >/dev/null 2>&1" 20
check "B2 the library lists it" wait_for "[ \$(log_lines 'library: 1 ROMs') -gt $lib0 ]" 20
# C. Settings > Add ROMs, cancel, again at the same spot, five times (the press's position after the picker).
folders_page
ok=1; for n in 1 2 3 4 5; do $A shell input tap 540 $ROW_ADD; wait_for picker_top 10 || { ok=0; break; }; close_system; sleep 1.5; done
check "C1 Add ROMs opens the picker again after each cancel (5x)" [ $ok = 1 ]
# D. The picker remembers the folder of the last pick: pick from /sdcard/ROMs, then it starts there.
$A shell input tap 540 $ROW_ADD; wait_for picker_top; sleep 2
$A shell input tap 245 331; sleep 2      # the breadcrumb's first part: the device's storage
tap_text "ROMs"; sleep 2; tap_text "1942.zip"; wait_for app_top 30; sleep 2
$A shell input tap 540 $ROW_ADD; wait_for picker_top; sleep 2
check "D1 the next picker starts in /sdcard/ROMs" screen_has "ROMs"
close_system; sleep 1.5
# E. Open Folder (ROM Folder > Open Folder): Files shows the ROM folder; back in the app.
$A shell input tap 540 $ROW_ROMS; sleep 1.5; $A shell input tap 285 1262
check "E1 Files opens" wait_for files_top
sleep 2; check "E2 Files shows the ROM folder with the zip" screen_has "1942.zip"
close_system; check "E3 back in the app" wait_for app_top
# F. Home and back three times: the surface is released before it goes, no acquire on a lost surface.
before=$(log_lines "vkAcquireNextImageKHR failed"); rel0=$(log_lines "Vulkan surface released")
for n in 1 2 3; do $A shell input keyevent KEYCODE_HOME; sleep 2; front; done
check "F1 the surface released each time" [ $(( $(log_lines "Vulkan surface released") - rel0 )) -ge 3 ]
check "F2 no frame on a lost surface" [ "$(log_lines "vkAcquireNextImageKHR failed")" = "$before" ]
$A shell input tap 540 $ROW_ADD
check "F3 Add ROMs works after home and back" wait_for picker_top
close_system
fi
# G. Share from Files, the app stopped (the ROM waits for the ROM folder) and running.
for state in stopped running; do
  $A shell rm -f $ROMDIR/1942.zip
  [ $state = stopped ] && $A shell am force-stop $P
  $A shell am force-stop com.google.android.documentsui
  $A shell "am start -a android.intent.action.VIEW -t vnd.android.document/root -d content://com.android.providers.downloads.documents/root/downloads" >/dev/null
  wait_for files_top; sleep 2
  press_text "1942.zip"; sleep 1.5
  $A shell input tap 761 205; sleep 2.5                 # Share (the selection bar)
  tap_text "ReplayArcade"
  check "G $state: Share copies the zip" wait_for "$A shell ls $ROMDIR/1942.zip >/dev/null 2>&1" 30
  close_system
done
echo "failures: $fails"
