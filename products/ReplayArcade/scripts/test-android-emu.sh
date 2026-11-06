#!/bin/bash
# ReplayArcade on an Android emulator (pixel_9 profile: 1080x2424, portrait), any Android version the app runs on
# (10 and later): getting ROMs in by every route, the picker, Files, coming back from other apps.
# One PASS / FAIL line per check, "failures: N" at the end.
#   scripts/test-android-emu.sh <test ROM zip> [apk]
# The test ROM is a real arcade set (1942.zip): it is copied around the device's storage only. The app's own
# screen is ImGui (no accessibility nodes): its rows are tapped by position; the system's screens (picker,
# Files, share sheet, permission pages) by their text through uiautomator, as they differ between versions.
#
# It always ends, in bounded time (2026-11-05: a run waited all night for an emulator that had died): every adb
# call names its device (SERIAL, else the only one attached) and has a time limit; a wait notices a device
# that is gone and ends the run there ("FAIL device lost"); the whole run stops itself after EMU_TEST_MAX_S
# (default 1800 s), its children with it.
ADB_BIN=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}
if [ -z "${SERIAL:-}" ]; then
  SERIAL=$(timeout 10 "$ADB_BIN" devices | awk 'NR>1 && $2=="device" {print $1}')
  [ "$(echo "$SERIAL" | grep -c .)" = 1 ] || { echo "FAIL no single device attached (set SERIAL): [$SERIAL]"; echo "failures: 1"; exit 2; }
fi
A="timeout ${ADB_TIMEOUT:-60} $ADB_BIN -s $SERIAL"
alive() { [ "$(timeout 10 "$ADB_BIN" -s "$SERIAL" get-state 2>/dev/null)" = device ]; }
lost() { echo "FAIL device lost: $SERIAL is gone ($*)"; echo "failures: $((fails + 1))"; exit 3; }
MAX=${EMU_TEST_MAX_S:-1800}
on_exit() { [ -n "${WD:-}" ] && kill "$WD" 2>/dev/null; pkill -P $$ 2>/dev/null; }
trap on_exit EXIT
trap 'echo "FAIL the run passed ${MAX} s and stopped itself"; echo "failures: $((fails + 1))"; exit 4' TERM
( sleep "$MAX"; kill -TERM $$ ) & WD=$!
P=io.github.kathoc.replayarcade
ACT=$P/io.github.replaynes.android.MainActivity
ZIP=${1:?usage: scripts/test-android-emu.sh <1942.zip> [apk]}; APK=${2:-}
OUT=${EMU_SHOTS:-$(dirname "$0")/../build/emu-shots}; rm -rf "$OUT"; mkdir -p "$OUT"
SDK=$($A shell getprop ro.build.version.sdk | tr -d '\r')
echo "Android SDK $SDK ($($A shell getprop ro.build.version.release | tr -d '\r'))"
fails=0
# The checks count the app's log lines before and after (logcat): a ring buffer that drops its oldest lines
# mid-run made the counts go down (2026-11-06, a long-used emulator: F1 and G failed with the releases and the
# copies in the log). A buffer large enough for a run, emptied at its start.
$A logcat -G 16M >/dev/null 2>&1; $A logcat -c >/dev/null 2>&1
# Taps come from the device's own touchscreen (sendevent, as root) when it can: Android 11's picker ignores
# `input tap` (an event with no input device, deviceId -1) on its files and folders, while a finger works
# (found 2026-11-05: the same tap through the emulator's touchscreen picks the file). Else `input`.
$A root >/dev/null 2>&1; sleep 2; timeout 60 "$ADB_BIN" -s "$SERIAL" wait-for-device
TS=$($A shell getevent -p 2>/dev/null | tr -d '\r' | awk '/^add device/ {d=$4} /0035 .*max/ && d && !seen[d]++ {for (i=1;i<=NF;i++) if ($i=="max") {sub(",","",$(i+1)); print d, $(i+1)}}' | sort -V | head -1)   # the lowest: the main display's (the emulator has one per display)
# A wiped emulator's Google services may open their sign-in page over the app mid-run (seen 2026-11-05 on a
# loaded host: a black page on top, every check after it failed): off on this test device (root).
$A shell pm disable com.google.android.gms/.auth.uiflows.minutemaid.MinuteMaidActivity >/dev/null 2>&1
WH=$($A shell wm size | tr -d '\r' | grep -oE '[0-9]+x[0-9]+' | tail -1)
if [ -n "$TS" ] && [ "$($A shell id -u | tr -d '\r')" = 0 ]; then set -- $TS; TSDEV=$1; TSMAX=$2; echo "taps through $TSDEV (0..$TSMAX on ${WH})"; else TSDEV=""; echo "taps through input (no root)"; fi
# hold X Y MS: a finger down at X,Y for MS milliseconds (a tap: about 80). The press and the release are
# one write each (input_event records made here, 64-bit layout): a sendevent per field started a process
# each, and on a loaded machine the release came late enough to be a long press (the picker selected the
# file instead of picking it).
ev() { python3 -c 'import struct,sys; a=list(map(int,sys.argv[1:])); sys.stdout.buffer.write(b"".join(struct.pack("<qqHHi",0,0,a[i],a[i+1],a[i+2]) for i in range(0,len(a),3)))' "$@"; }
hold() {
  if [ -z "$TSDEV" ]; then $A shell input swipe $1 $2 $1 $2 $3; return; fi
  local w=${WH%x*} h=${WH#*x}; local x=$(( $1 * TSMAX / w )) y=$(( $2 * TSMAX / h ))
  ev 3 57 9  3 53 $x  3 54 $y  3 58 50  1 330 1  0 0 0 > "$OUT/.down"
  $A push "$OUT/.down" /data/local/tmp/rn-down >/dev/null 2>&1
  $A shell "cat /data/local/tmp/rn-down > $TSDEV; sleep $(awk "BEGIN{print $3/1000}"); cat /data/local/tmp/rn-up > $TSDEV"
}
tap() { hold $1 $2 80; }
[ -n "$TSDEV" ] && { ev 3 57 -1  1 330 0  0 0 0 > "$OUT/.up"; $A push "$OUT/.up" /data/local/tmp/rn-up >/dev/null 2>&1; }
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; $A exec-out screencap -p > "$OUT/fail-$(echo "$*" | cut -c1-2 | tr -d ' ').png"; fails=$((fails+1)); }
check() { local name=$1; shift; alive || lost "before $name"; if "$@"; then pass "$name"; else fail "$name"; fi; }
top() { $A shell dumpsys activity activities | grep -m1 -E "topResumedActivity|mResumedActivity"; }
app_top() { top | grep -q "$P/"; }
picker_top() { top | grep -qE "documentsui.*(picker|Pick)"; }
files_top() { top | grep -qE "documentsui.*(files\.FilesActivity|FilesActivity)"; }
wait_for() {
  for i in $(seq 1 ${2:-20}); do eval "$1" && return 0; alive || lost "waiting for: $1"; sleep 0.5; done
  return 1
}
# The app's log through logcat (its Java side: tag ReplayNES; native: the product): Android 11+ keeps adb out of
# Android/data, where the log file and the ROM folder are.
applog() { $A logcat -d -s ReplayNES:I ReplayArcade:I 2>/dev/null; }
log_lines() { applog | grep -c -- "$1"; }
ui_dump() { $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; $A shell cat /sdcard/ui.xml | tr '>' '\n'; }
# A node of a system screen whose text (or content-desc) matches an extended regex: tap / long press its centre.
node_xy() {
  local b; b=$(ui_dump | grep -m1 -E "(text|content-desc)=\"($1)\"" | grep -o 'bounds="[^"]*"' | grep -oE '[0-9]+' | tr '\n' ' ')
  [ -z "$b" ] && return 1; set -- $b; echo "$(( ($1+$3)/2 )) $(( ($2+$4)/2 ))"
}
tap_text() { local xy; xy=$(node_xy "$1") || return 1; tap $xy; }
press_text() { local xy; xy=$(node_xy "$1") || return 1; set -- $xy; hold $1 $2 900; }
# tap_until TEXT CONDITION: tap the node with TEXT until CONDITION holds (3 tries): a list still being laid
# out takes a tap at a place its node is about to leave.
tap_until() { for t in 1 2 3; do tap_text "$1" && wait_for "$2" 10 && return 0; done; return 1; }
# share_to_app LABEL: in an open share sheet, LABEL (the app, or its Direct Share entry); if it is not shown, the
# sheet is pulled up for its whole app list (Android 10 shows one row at first, and "Direct share not available"
# at times), then LABEL or the app.
# The sheet is gone when the activity in front is no longer the system's chooser (its text cannot tell: "Share"
# is also the Files app's button).
sheet_gone='! top | grep -qiE "ChooserActivity|intentresolver|ResolverActivity"'
share_to_app() {
  tap_until "$1" "$sheet_gone" && return 0
  $A shell input swipe 540 1900 540 600 400; sleep 2
  tap_until "$1|ReplayArcade" "$sheet_gone"
}
screen_has() { ui_dump | grep -qE "(text|content-desc)=\"($1)\""; }
close_system() { for i in $(seq 1 10); do app_top && return 0; $A shell input keyevent KEYCODE_BACK; sleep 1.2; done; }
# In front and drawing upright since this start: a line after the log's length at the start says the swapchain
# is 1080x2424 (a cold start makes a landscape surface first and turns it).
UPRIGHT='swapchain 1080x2424\|surface: changed 1080x2424'
mark() { UP0=$(log_lines "$UPRIGHT"); }
upright() { [ "$(log_lines "$UPRIGHT")" -gt "$UP0" ]; }
# Back from a system screen (marked before leaving): the app's surface is made again before the next tap on
# it. A tap while it is being made is lost (2026-11-05: the Settings taps after B's pick went nowhere, and the
# dialog's keys that followed started the game in the library).
settle() { wait_for upright 20 || echo "  (no new surface: $*)"; sleep 1; }
front() { mark; $A shell am start -n $ACT > /dev/null 2>&1; wait_for app_top 30; wait_for upright 40; sleep 2.5; }
cold() { $A shell am force-stop $P; front; }
# The app runs in the system's language (pm clear: Language = Auto); the emulator's is English. Rows and the
# empty library's buttons sit where they sit in any language; the tabs do not (App: x 745 in English); the
# app's dialogs are driven by keys (Enter on the focused first button, Right to the next), in any language.
key() { $A shell input keyevent "$@"; }
folders_page() { tap 930 55; sleep 1.5; tap 745 146; sleep 1.2; tap 540 532; sleep 1.5; }
ROW_ADD=170; ROW_ROMS=266
empty_add_button() { tap 230 1172; }   # the empty library's first button
# The app's dialogs (ImGui: not seen by uiautomator) log "dialog: <title>" when they appear and
# "dialog: <title> -> <button>" when answered: keys are sent once one is up (a fixed wait sent them early
# on a slow start, and the dialog stayed open with the picker's run after it failed in a chain).
dialog_up() { applog | grep -- "dialog: " | tail -1 | grep -qv -- " -> "; }   # the last one appeared, not answered
# Keys go to the focused window only (a tap does not need it): back from a system screen the app may have its
# surface again before the input focus (2026-11-05, Android 13: a dialog up, its keys gone).
focused() { $A shell dumpsys window | grep -m1 mCurrentFocus | grep -q "$P/"; }
dialog_wait() { wait_for dialog_up 30; focused || echo "  (a dialog up, the focus elsewhere: $($A shell dumpsys window | grep -m1 mCurrentFocus | tr -d '\r'))"; wait_for focused 20 || echo "  (keys sent without the focus: $(applog | grep 'dialog: ' | tail -1 | sed 's/.*dialog: //'))"; sleep 0.5; }
dialog_first() { dialog_wait; key KEYCODE_ENTER; }                          # Add ROMs: Search the Device
dialog_second() { dialog_wait; key KEYCODE_DPAD_RIGHT; sleep 0.4; key KEYCODE_ENTER; }  # Add ROMs: Choose Files
# Add ROMs' "Choose Files" by touch, as a phone is used (A keeps the keys: the keyboard / gamepad route).
# The button: measured on the 1080x2424 screen, English.
# Open (2026-11-05): on a wiped Android 13 emulator (2 GB) early in its life, right after a ROM was added,
# the app sometimes ignored taps and keys for 20 s and more while it drew (the input reached its focused
# window; the system sent trim-memory 5..15). Not seen on the same emulator later, nor in 30 rounds outside
# the matrix. C1 saves the app log, dumpsys input and the focus when it fails.
dialog_choose() { dialog_wait; tap 409 1260; }
results_add_all() { dialog_wait; key KEYCODE_ENTER; }                       # the search's result: Add All
# The device's own storage in the picker (its name is the model's: "sdk_gphone64_arm64", "Android SDK built for arm64" ...).
STORAGE='sdk_gphone[^"]*|Android SDK[^"]*|Internal storage|内部ストレージ'
# On the system's page / dialog the app opened: allow. Waited for (a slow device showed the page after the 2 s
# that were waited, the tap found nothing, Back refused: the app fell back to the picker), and on Android 11+
# checked in the app ops before going back.
ALL_FILES='Allow access to manage all files|すべてのファイルの管理権を付与|Permit access to manage all files'
files_allowed() { $A shell appops get $P MANAGE_EXTERNAL_STORAGE | grep -q "allow"; }
grant_all_files() {
  if [ "$SDK" -ge 30 ]; then
    wait_for "screen_has '$ALL_FILES'" 30
    tap_until "$ALL_FILES" files_allowed
    sleep 1; $A shell input keyevent KEYCODE_BACK
  else
    wait_for 'screen_has "Allow|ALLOW|許可"' 30
    tap_text "Allow|ALLOW|許可"
  fi
}
revoke_all_files() {
  if [ "$SDK" -ge 30 ]; then
    $A shell appops set --uid $P MANAGE_EXTERNAL_STORAGE default; $A shell appops set $P MANAGE_EXTERNAL_STORAGE default
  else
    $A shell pm revoke $P android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null; $A shell pm revoke $P android.permission.READ_EXTERNAL_STORAGE 2>/dev/null
  fi
}

[ -n "$APK" ] && $A install -r "$APK" | tail -1
$A shell am force-stop com.google.android.documentsui
$A shell settings put secure immersive_mode_confirmations confirmed   # Android's one-time "Viewing full screen"
$A push "$ZIP" /sdcard/Download/1942.zip >/dev/null
$A shell "mkdir -p /sdcard/ROMs && cp /sdcard/Download/1942.zip /sdcard/ROMs/1942.zip"
$A logcat -G 16M >/dev/null 2>&1; $A logcat -c
$A shell pm clear $P >/dev/null   # as just installed: no ROMs, no settings, no access

if [ "${ONLY:-}" != G ] && [ "${ONLY:-}" != H ]; then
# A. The empty library: Add ROMs > Choose Files opens the picker; it starts where zips are listed.
cold
empty_add_button; sleep 1.5; dialog_second
check "A1 empty library: Add ROMs > Choose Files opens the picker" wait_for picker_top
# The picker may show Recent first and go to its start folder once its places are loaded (slow on a busy host).
check "A2 the picker starts with 1942.zip listed" wait_for 'screen_has "1942.zip"' 40
# The picker asks for ROM types (RomImport.ROM_TYPES): no Images / Videos / Audio / Documents views, where no zip
# ever appears (a person who went there saw no ROMs at all).
check "A3 the picker offers no Images / Audio / Videos views" eval '! screen_has "Images|Audio|Videos|画像|音声|動画"'
# B. Pick it: copied, the library shows it (a scan result applied without slack).
lib0=$(log_lines "library: 1 ROMs")
mark; tap_text "1942.zip"; wait_for app_top 30; settle B
check "B1 the zip is copied into the ROM folder" wait_for "applog | grep -q 'import: 1942.zip ->'" 20
check "B2 the library lists it" wait_for "[ \$(log_lines 'library: 1 ROMs') -gt $lib0 ]" 20
# C. Settings > Add ROMs > Choose Files, cancel, again at the same spot, five times.
folders_page
# Back from the picker, the tap waits for the app's surface to be made again (what a user sees) - and is not
# repeated: a tap that does nothing after coming back is the fault this check is for.
ok=1; for n in 1 2 3 4 5; do tap 540 $ROW_ADD; sleep 1.2; dialog_choose; wait_for picker_top 60 || { ok=0; echo "  C1: no picker at round $n: $(applog | grep 'dialog: .* -> ' | tail -1 | sed 's/.*dialog: //') / $(applog | grep 'import:' | tail -1 | sed 's/.*import: //')"
    applog > "$OUT/C1-applog.txt"; $A shell dumpsys input > "$OUT/C1-input.txt"; $A shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" > "$OUT/C1-focus.txt"; break; }
  mark; close_system; settle "C1 round $n"; done
check "C1 Choose Files opens the picker again after each cancel (5x)" [ $ok = 1 ]
# D. The picker remembers the folder of the last pick: pick from /sdcard/ROMs, then it starts there.
tap 540 $ROW_ADD; sleep 1.2; dialog_choose; wait_for picker_top; sleep 2
# The picker starts in Download (B's pick): its path bar's first part is the device's storage; Android 10
# has no path bar (a drop-down title), there the storage is in the roots drawer.
rem0=$(log_lines "import: remembered .*ROMs")
wait_for 'screen_has "1942.zip"' 20
in_roms='! screen_has "Download" && screen_has "1942.zip"'
tap_until "$STORAGE" 'screen_has "ROMs"' || { tap_until "Show roots|ルートを表示" 'screen_has "$STORAGE"'; tap_until "$STORAGE" 'screen_has "ROMs"'; }
tap_until "ROMs" "$in_roms"; sleep 1; mark; tap_text "1942.zip"
wait_for app_top 30 && wait_for "[ \$(log_lines 'import: remembered .*ROMs') -gt $rem0 ]" 10 \
  || { fail "D0 picked 1942.zip in /sdcard/ROMs"; close_system; }
settle D0
tap 540 $ROW_ADD; sleep 1.2; dialog_choose; wait_for picker_top; sleep 2
check "D1 the next picker starts in /sdcard/ROMs" screen_has "ROMs"
mark; close_system; settle D1
# E. Open Folder (ROM Folder > Open Folder): Files shows the ROM folder; back in the app.
back0=$(log_lines "back from the Files app")
tap 540 $ROW_ROMS; sleep 1.5; dialog_first   # ROM Folder: Open Folder
check "E1 Files opens" wait_for files_top
sleep 2; check "E2 Files shows the ROM folder with the zip" screen_has "1942.zip"
mark; close_system; check "E3 back in the app" wait_for app_top; settle E3
sleep 3; check "E4 no search offered with ROMs in the folder" [ "$(log_lines "back from the Files app")" = "$back0" ]
# F. Home and back three times: the surface is released before it goes, no acquire on a lost surface.
before=$(log_lines "vkAcquireNextImageKHR failed"); rel0=$(log_lines "Vulkan surface released")
for n in 1 2 3; do $A shell input keyevent KEYCODE_HOME; sleep 2; front; done
# When the frame loop was paused before a frame saw the surface go, the first frame back releases it (the gate
# keeps it from drawing meanwhile: docs/design/ANDROID.md "Black screen"): the count is waited for.
check "F1 the surface released each time" wait_for "[ \$(( \$(log_lines 'Vulkan surface released') - $rel0 )) -ge 3 ]" 20
check "F2 no frame on a lost surface" [ "$(log_lines "vkAcquireNextImageKHR failed")" = "$before" ]
tap 540 $ROW_ADD; sleep 1.2; dialog_choose
check "F3 Add ROMs works after home and back" wait_for picker_top
close_system
fi

if [ "${ONLY:-}" != H ]; then
# G. Share from Files, the app stopped (the ROM waits for the ROM folder) and running.
for state in stopped running direct; do
  imp0=$(log_lines "import: 1942.zip ->")
  [ $state = stopped ] && $A shell am force-stop $P
  [ $state = running ] && { app_top || front; }
  $A shell am force-stop com.google.android.documentsui
  $A shell "am start -a android.intent.action.VIEW -t vnd.android.document/root -d content://com.android.providers.downloads.documents/root/downloads" >/dev/null
  wait_for files_top; sleep 2.5
  press_text "1942.zip"; sleep 1.5
  tap_text "Share|共有"; sleep 2.5
  # direct: the share sheet's top row (Direct Share, res/xml/shortcuts.xml); else the app in its app list.
  # The share sheet may still be settling: tapped until it is gone.
  if [ $state = direct ]; then share_to_app "Add to the ROM folder|ROM フォルダへ追加"; else share_to_app "ReplayArcade"; fi
  check "G $state: Share copies the zip" wait_for "[ \$(log_lines 'import: 1942.zip ->') -gt $imp0 ]" 30
  close_system
done
fi

# I. A share of any type of file lists the app (a sending app names a zip as it likes: the app was left out for
#    application/x-compressed and others), and only ROMs go in.
missing=""
for t in application/zip application/x-zip-compressed application/x-compressed application/x-zip-archive multipart/x-zip \
         application/x-7z-compressed application/octet-stream text/plain image/jpeg; do
  for act in SEND SEND_MULTIPLE; do
    $A shell "cmd package query-activities --brief -a android.intent.action.$act -t '$t'" | grep -q "$P/" || missing="$missing $act:$t"
  done
done
[ -z "$missing" ] || echo "   not listed:$missing"
check "I1 the share sheet lists the app for any type" [ -z "$missing" ]
$A shell 'echo note > /sdcard/Download/notes.txt'
nr0=$(log_lines "notes.txt: not a ROM")
$A shell am force-stop com.google.android.documentsui
$A shell "am start -a android.intent.action.VIEW -t vnd.android.document/root -d content://com.android.providers.downloads.documents/root/downloads" >/dev/null
wait_for files_top; sleep 2.5
press_text "notes.txt"; sleep 1.5
tap_text "Share|共有"; sleep 2.5
share_to_app "Add to the ROM folder|ROM フォルダへ追加"
check "I2 a shared file that is not a ROM is not added" wait_for "[ \$(log_lines 'notes.txt: not a ROM') -gt $nr0 ]" 30
close_system

if [ "${ONLY:-}" != G ]; then
# H. Search the Device: ROMs scattered in any folder, in any state; all-files access asked on the way.
#    (The copies are 1942's bytes under other set names: the search and the copy go by name; such a "wrong"
#    set must not crash the app when the library tries it - FBNeo's missing-files list overflowed.)
$A shell "cd /sdcard && rm -rf .hidden 'ROMs フォルダ 日本語' Download/deep Documents/arcade && mkdir -p Documents/arcade/sets Download/deep/a/b/c/d/e .hidden 'ROMs フォルダ 日本語' DCIM \
  && cp Download/1942.zip Documents/1943.zip && cp Download/1942.zip Download/deep/a/b/c/d/e/gng.zip && cp Download/1942.zip .hidden/sf2.zip \
  && cp Download/1942.zip 'ROMs フォルダ 日本語/DDONPACH.ZIP' && cp Download/1942.zip mslug.zip && cp Download/1942.zip DCIM/xmcota.zip \
  && cp Download/1942.zip Documents/arcade/sets/1943.zip && echo junk > Documents/photos.zip"
$A shell pm clear $P >/dev/null   # an empty ROM folder, no access
revoke_all_files
cold
folders_page; tap 540 $ROW_ADD; sleep 1.5
found0=$(log_lines "find: .* folders")
dialog_first
grant_all_files
check "H1 access granted on the way" wait_for "applog | grep -q 'storage: all-files access granted'" 20
check "H2 the search ran" wait_for "[ \$(log_lines 'find: .* folders') -gt $found0 ]" 40
res=$(applog | grep 'find: .* folders' | tail -1)
echo "   $res"
echo "$res" | grep -q "7 ROMs to add" && pass "H3 all 7 scattered ROMs found" || fail "H3 all 7 scattered ROMs found"
echo "$res" | grep -q "1 unknown" && pass "H4 the unknown zip is not offered" || fail "H4 the unknown zip is not offered"
cp0=$(log_lines "find: .* -> ")   # before Add All: the copy can be done before the next look at the log
sleep 1; results_add_all
check "H5 all 7 copied" wait_for "[ \$(( \$(log_lines 'find: .* -> ') - cp0 )) -ge 7 ]" 30
sleep 25
check "H6 the app is still running (the library tried the wrong sets)" app_top
cold; sleep 15
check "H7 a cold start with the wrong sets in the library" app_top
# L. A swipe on the library turns the page and opens no card (it begins on the first row's last card).
sw0=$(log_lines "library: swipe"); pl0=$(log_lines "library: play ")
$A shell input swipe 940 200 150 220 250; sleep 3
check "L1 a swipe on the library turns the page" [ "$(log_lines "library: swipe")" -gt "$sw0" ]
check "L2 the swipe opened no game" [ "$(log_lines "library: play ")" = "$pl0" ]
fi

# K. Open Folder with an empty ROM folder: back from the Files app, Search the Device is offered (the Files app's
#    Documents, Images ... list no zip: a person found no ROMs there).
$A shell pm clear $P >/dev/null
cold
folders_page
off0=$(log_lines "dialog: No ROMs in the ROM folder yet")
tap 540 $ROW_ROMS; sleep 1.5; dialog_first   # ROM Folder: Open Folder
wait_for files_top
mark; close_system; settle K1
check "K1 back with the ROM folder empty: Search the Device offered" wait_for "[ \$(log_lines 'dialog: No ROMs in the ROM folder yet') -gt $off0 ]" 30
sleep 1; key KEYCODE_ESCAPE; sleep 1   # Close
# O. Settings > App > Screen Orientation: Landscape turns the screen, Portrait back, Automatic follows the device
#    (the run keeps the device upright: user_rotation 0). Each choice is the row's right arrow (its place
#    measured on the 1080x2424 screen: x 994 upright, 1749 on its side; y 616 both).
cur_size() { $A shell dumpsys window displays | grep -m1 -oE "cur=[0-9]+x[0-9]+" | cut -d= -f2; }
cold; tap 930 55; sleep 1.5; tap 745 146; sleep 1.5   # from the library (K left Settings open)
# input tap, not the touchscreen: its coordinates are the panel's and do not turn with the screen (a tap meant
# for the landscape row landed elsewhere). The app takes injected events.
itap() { $A shell input tap "$@"; }
itap 994 616
check "O1 Landscape turns the screen" wait_for '[ "$(cur_size)" = 2424x1080 ]' 20
sleep 2; itap 1749 616
check "O2 Portrait turns it back" wait_for '[ "$(cur_size)" = 1080x2424 ]' 20
sleep 2; itap 994 616
check "O3 Automatic: the device's (upright here)" wait_for '[ "$(applog | grep "screen: orientation" | tail -1 | grep -c auto)" = 1 ] && [ "$(cur_size)" = 1080x2424 ]' 20
# The whole run: no crash of the app (the crash buffer keeps native aborts and Java exceptions).
crashes=$($A logcat -d -b crash 2>/dev/null | grep -c "$P\|SDLActivity")
check "Z no crash of the app in the whole run" [ "$crashes" = 0 ]
# A failed run keeps its logs (the emulator is wiped with the next version): the app's, and the device's around it.
if [ "$fails" -gt 0 ]; then applog > "$OUT/applog.txt"; $A logcat -d -v time > "$OUT/logcat.txt" 2>/dev/null; fi
echo "failures: $fails"
