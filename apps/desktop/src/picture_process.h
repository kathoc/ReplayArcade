// The library's picture process (picture_process.cpp; docs/plans/2026-11-22-library-pictures-robust.md).
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "library_thumbs.h"

namespace rnl {
/// `--rom-picture <rom> <out>`: makes one picture and ends (no window). True when the arguments asked for it;
/// `*code` is the exit code (0 made, 3 no picture).
bool runPictureProcessArgs(int argc, char** argv, int* code);
#ifndef __ANDROID__
/// The app's own executable as the picture process (Linux, Windows).
LibraryThumbs::PictureProcessRunner selfPictureProcess();
#endif
}  // namespace rnl
