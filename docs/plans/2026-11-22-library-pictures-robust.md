# Library pictures: an unknown ROM that crashes or never finishes cannot stop the library

2026-11-22, user request (after ReplayArcade 0.3.20 still closed on a Lenovo Legion Tab):
「特定のタイトルの修正ではなく、未知のタイトルで問題がおこったときにも問題なく動くように。また、なんども
リトライして先に進まない、ということもないようにして。」

## Today

The library makes a card picture for each ROM by running it from power-on in the app's own process
(desktop / Android: `rnl::LibraryThumbs::pictureWorker`; iPhone / Mac: `ThumbnailStore`), up to
`RN_PRODUCT_LIBRARY_PICTURE_FRAME` frames (more while blank, 6x at most). A core bug in any set
(FinalBurn Neo: DonPachi wrote its first frame over the heap, Momoko read past its video RAM) kills the
app; the next launch runs the same ROM again, so the app closes at every start (Legion Tab, 0.3.19 / 0.3.20).
Both drivers are fixed (4bcee20, patches/fbneo); this plan is about the next unknown one.

## Adopted

1. **A ledger of ROMs without a picture** (all platforms, frontend core `rnf_picture_ledger`, used by the C++
   and the Swift library): `<thumbnail dir>/pictures-in-progress` names the ROM being run (written before it
   starts, removed when it ends or is put back); `<thumbnail dir>/pictures-failed.json` lists failed ROMs by
   file name and size with a reason and a count. At start-up a leftover in-progress record is a crash in that
   ROM: its count goes up. A ROM is skipped (its card keeps the name tile) once it **crashed twice** (one kill
   by the OS while in the background must not mark a good ROM) or failed **once** for a reason the worker saw
   itself (could not open, a frame error). A ROM whose file size changed is tried again.
2. **The picture is made in another process where the OS allows it** (Windows, Linux / Steam Deck, Android,
   Mac): a crash or a hang of the core ends that process only; the library carries on, records the failure and
   takes the next ROM. A run longer than a time limit (60 s) is a failure too. iPhone cannot start processes:
   1. alone (the app closes at most twice for one bad ROM, then never for it).
   - Desktop (Windows, Linux): the app's own executable with `--rom-picture <rom> <out file>`.
   - Android: a service in its own process (`android:process=":pictures"`), the same libmain.so.
   - Mac: the app's executable with the same argument.
3. Progress: the worker never takes a skipped ROM again in a run or after a restart; a paused run (a game
   opened) is put back without counting as a failure.

## Rejected

- Catching the crash in-process (signal handler + longjmp): the heap may already be corrupt (DonPachi); the app
  could misbehave later instead of closing. A separate process is the only clean boundary.
- Skipping after one crash: an app killed by the OS while a picture was being made would lose a good ROM's
  picture for ever.
- A list of known bad sets: does not help the next unknown one (the user's point).

## Done when

- Unit tests of the ledger: in-progress left over -> count 1, then 2 -> skipped; explicit failure -> skipped;
  size change -> tried again; abandon (pause) -> no count.
- A ROM that crashes (test hook / a crash set) on Android (the Legion Tab) and the desktop: the library keeps
  running, the card stays a name tile, the next ROMs get pictures, a restart does not run it again.
- The 256 sets of the user's selection still all get pictures.

## Result (2026-11-22)

- Two more core bugs found on the way, fixed in patches/fbneo: Momoko 120% read past its 0x400 bytes of video RAM
  in the scrolling text layer (MAME skips rows past 0x400); found by symbolising the Legion Tab's tombstone
  (d_momoko.cpp DrvDraw) and Guard Malloc on the Mac (line 573). All 256 sets of the user's selection then ran
  1800 frames under Guard Malloc (reads and writes, exact sizes) without a finding.
- Ledger: frontend/src/picture_ledger.cpp, tests/test_picture_ledger.cpp (2 cases).
- Picture process: Linux / Windows `--rom-picture` (apps/desktop/src/picture_process.cpp), Android
  PictureService (`:pictures`) + PictureClient, LibraryThumbs runs it and falls back to its own process when it
  is unavailable. iPhone / Mac (ThumbnailStore): the ledger only (the Mac ReplayArcade is a development build).
- Legion Tab (Android 15), a test ROM `rn-picture-crash-test-1942.zip` (the test hook aborts the picture process
  for such names): the picture process died (SIGABRT), the app kept running and logged it, a new picture process
  started for the next ROM; after one restart the ROM was tried once more (second crash, app still running); after
  the next it was not run again. The test file was removed afterwards.
