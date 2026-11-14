// CRT display parameters and the tube rectangle (no graphics API): shared by the settings UI, the
// display post-process interface (post_process.h) and the CRT renderers (Vulkan:
// apps/linux/src/render; Direct3D 11: apps/windows/src/crt_d3d11.h).
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "replaynes/frontend.h"  // RNF_CRT_ACTIVE_WIDTH

namespace rnl {

/// physical-worker.mjs `effects` + `lines` (defaults as shipped in nesterm's web UI).
struct CrtSettings {
  int lines = 240;           // 240 native, or 110...220 (reduced-line experiment)
  bool beamGrowth = true;    // scanlines thicker where brighter (M4a vertical + M4C-SPOT-H)
  bool persistence = true;   // phosphor persistence (M4b)
  bool supply = true;        // bright screens widen and dim the picture (M4c)
  double antennaDbuv = 65.0; // signal strength 20...90 dBuV (M3-NOISE)
  double ambientLux = 40.0;  // fixed in nesterm's UI
  // Picture geometry: the fraction of the 4:3 face width the 256 active dots span (centred).
  // RNF_CRT_ACTIVE_WIDTH (32/35): the NTSC raster, 8:7 dots like the plain display's "8:7 Pixels";
  // 1: nesterm's mapping (the dots fill the face, 1.25:1) - the conformance fixtures' geometry.
  double activeWidth = RNF_CRT_ACTIVE_WIDTH;

  static bool validLines(int l) { return l == 240 || (l >= 110 && l <= 220); }
  CrtSettings sanitized() const;
  bool operator==(const CrtSettings& o) const;
  bool operator!=(const CrtSettings& o) const { return !(*this == o); }
};

struct CrtRect { float x = 0, y = 0, w = 0, h = 0; };

/// The part of the 4:3 tube face shown on screen: the columns the drive spans (`activeWidth` of the
/// face width, centred), the face's full height. Beside the drive the beam draws black (the line's
/// border and blanking); a TV's overscan hides that, and so does the live display (user decision
/// 2026-11-14: no black bands between the picture and the blurred backdrop). The tube itself keeps
/// the whole face (its glow, scatter and geometry are unchanged); only the show pass is clipped.
/// docs/CRT_PORT.md "Picture geometry". macOS: CRTRenderer.shownRect (the same formula).
inline CrtRect crtShownRect(const CrtRect& face, double activeWidth) {
  const double a = activeWidth > 0 && activeWidth < 1 ? activeWidth : 1;
  const float w = float(double(face.w) * a);
  return CrtRect{face.x + (face.w - w) / 2, face.y, w, face.h};
}

}  // namespace rnl
