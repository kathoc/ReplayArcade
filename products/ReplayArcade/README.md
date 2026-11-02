# ReplayArcade

[日本語](README.ja.md)

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
- Controllers and players: a controller connected while the Steam Deck's own controls are player 1 takes
  player 1, and gives it back when disconnected; players 2-4 keep their controllers. While paused, squares
  top left show which players have a controller and light up at a press.
- Arcade games only: FinalBurn Neo's home-system sets (Mega Drive, PC Engine, NES ...) are not opened or listed.
- Keyboard: arrows, buttons 1-6 on Z X C / A S D, coin 5 (player 2: 6), start 1 or Return (player 2: 2),
  as in MAME.
- Mouse (Settings > Controls > More > Mouse, off by default), for games with analog controls: a trackball, dial or paddle follows the mouse's motion
  (Arkanoid, Syvalion, Cameltry); a flight stick follows its position, the wheel moves a throttle or
  presses the accelerator / brake, and the left / right / middle buttons are buttons 1-3 (After Burner II:
  Vulcan, missile, speed; Galaxy Force II). The game keeps the pointer while it runs; Esc gives it back.
  Pressing a pad or game key puts the mouse's stick and lever back in the middle.
- Replays: a recording played straight through is identical on Linux and Windows. FinalBurn Neo is patched
  to save the machine state its save states left out (`patches/fbneo/`); in a per-game test of 256 games,
  a seek, a rewind, an export or a reopened project replays identically in every one.

Platforms: Steam Deck / Linux (Flatpak), Windows x64 and Android (64-bit).

## Download

**[Latest release](https://github.com/kathoc/ReplayArcade/releases/latest)** - pick the file for your system:

| System | File |
|---|---|
| Steam Deck / Linux | [io.github.kathoc.ReplayArcade.flatpakref](https://github.com/kathoc/ReplayArcade/releases/latest/download/io.github.kathoc.ReplayArcade.flatpakref) (or `io.github.kathoc.ReplayArcade-<version>-x86_64.flatpak`) |
| Windows x64 | `ReplayArcade-<version>-windows-x64.zip` |
| Android (64-bit, Android 10 or later, Vulkan) | `ReplayArcade-<version>-android-arm64.apk` |

## Install and updates

### Steam Deck / Linux

1. In Desktop Mode, open Konsole and run:
   ```bash
   flatpak install --user https://kathoc.github.io/ReplayArcade/flatpak/io.github.kathoc.ReplayArcade.flatpakref
   ```
   (or open the downloaded `.flatpakref` with Discover). The repository is GPG-signed.
2. Start it from the application menu. To play it in Gaming Mode, add it to Steam with
   "Add a Non-Steam Game".
3. Updates: the app finds new versions itself (Settings > System > ReplayArcade Version) and installs
   them through the Flatpak portal; `flatpak update --user` and Discover work too. Gaming Mode has no
   dialog for the portal's one-time "allow updates" question: answer it once in Desktop Mode, or run
   `flatpak permission-set flatpak updates io.github.kathoc.ReplayArcade yes`. A version that asks for
   new Flatpak permissions (the release notes say so) is installed with Discover or `flatpak update`.

### Windows x64

1. Download `ReplayArcade-<version>-windows-x64.zip` from the latest release and unzip it to a folder
   of your choice.
2. Run `ReplayArcade.exe`. Windows may warn about an unknown publisher: "More info" > "Run anyway".
3. Updates: the app checks the latest release (Settings > System > ReplayArcade Version), verifies the
   download's EdDSA signature and installs it.

### Android

1. Download `ReplayArcade-<version>-android-arm64.apk` on the device and open it. Allow your browser
   or file manager to install apps when Android asks.
2. Start ReplayArcade once (it creates its folders), then copy ROM zips into
   `Android/data/io.github.kathoc.replayarcade/files/ReplayArcade/ROM` (USB file transfer from a
   computer, or a file manager that can open `Android/data`).
3. Updates: install the newer APK over the installed one; recordings and settings stay.
   Controllers are needed for now (touch controls are coming).

### ROMs

**No ROMs are included.** Put the ROM zips you are entitled to use (FinalBurn Neo set names,
non-merged; e.g. `gradius.zip`) in `Documents/ReplayArcade/ROM` (Steam Deck / Linux / Windows; Android:
see above), then start ReplayArcade again: the library lists them.

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
