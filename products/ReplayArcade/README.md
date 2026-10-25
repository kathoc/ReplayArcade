# ReplayArcade

ReplayArcade is [ReplayNES](https://github.com/kathoc/ReplayNES) for arcade games: the same
record-everything player, with [FinalBurn Neo](https://github.com/finalburnneo/FBNeo) as its core.

- Every session is recorded: rewind (L2), retry from any point, takes, bookmarks.
- Practice sections with a countdown (3, 1 or none), autosave and resume: on the paused seek bar the
  north button puts a marker (two make a section, on a marker it deletes it), west starts and stops
  practice, L / R switch the section, L + START goes back to the first marker.
- Make Video: MP4 export of any range.
- Per-game button assignment and turbo, remembered separately for pads and arcade sticks
  (detected automatically, changeable on the Controller page).
- Controller-only operation, Japanese and English UI.
- Keyboard: arrows, buttons 1-6 on Z X C / A S D, coin 5 (player 2: 6), start 1 or Return (player 2: 2),
  as in MAME.
- Mouse (Settings > Controls > More > Mouse, off by default), for games with analog controls: a trackball, dial or paddle follows the mouse's motion
  (Arkanoid, Syvalion, Cameltry); a flight stick follows its position, the wheel moves a throttle or
  presses the accelerator / brake, and the left / right / middle buttons are buttons 1-3 (After Burner II:
  Vulcan, missile, speed; Galaxy Force II). The game keeps the pointer while it runs; Esc gives it back.
  Pressing a pad or game key puts the mouse's stick and lever back in the middle.
- Replays: a recording played straight through is identical on Linux and Windows. FinalBurn Neo is patched
  to save the machine state its save states left out (`patches/fbneo/`); after a seek, a rewind or an export
  some games still differ, and that work goes on.

Platforms: Steam Deck / Linux (Flatpak) and Windows x64.

## Install and updates

- **Steam Deck / Linux**: `flatpak install --user https://kathoc.github.io/ReplayArcade/flatpak/io.github.kathoc.ReplayArcade.flatpakref`
  (GPG-signed repository). The app finds new versions itself (Settings > System > ReplayArcade Version)
  and installs them through the Flatpak portal; `flatpak update` works too. Gaming Mode has no dialog
  for the portal's one-time "allow updates" question: answer it once in Desktop Mode, or run
  `flatpak permission-set flatpak updates io.github.kathoc.ReplayArcade yes`.
- **Windows x64**: unzip `ReplayArcade-<version>-windows-x64.zip` from the
  [releases](https://github.com/kathoc/ReplayArcade/releases) and run `ReplayArcade.exe`. In-app updates
  read the release's `appcast-windows.xml` and verify its EdDSA signature.

**No ROMs are included.** Put the ROM zips you are entitled to use (FinalBurn Neo set names,
non-merged; e.g. `gradius.zip`) in `Documents/ReplayArcade/ROM`.

## Building

```bash
git clone --recursive https://github.com/kathoc/ReplayArcade.git
cd ReplayArcade
scripts/fbneo-patches.sh            # applies the FinalBurn Neo patch

# Linux app and tests (engine tests need ROMs: REPLAYARCADE_ROMS=<dir>)
cmake -S . -B build && cmake --build build -j
# Flatpak (Steam Deck): packaging/linux/io.github.kathoc.ReplayArcade.yml
# Windows x64 (cross build with llvm-mingw, see ReplayNES's docs/WINDOWS.md)
scripts/build-windows.sh x86_64
```

## License

GPL-2.0-or-later with an additional permission to combine with FinalBurn Neo, which is under its own
non-commercial licence. See `COPYING.md`, `LICENSE`, `LICENSE-FBNeo.txt` and
`THIRD_PARTY_NOTICES.md`. ReplayArcade is free and asks for no donations.
