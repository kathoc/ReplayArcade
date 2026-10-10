# Touch controller: port of NESTERM's Brickboy controller

The iPhone on-screen controller is NESTERM's touch controller (Brickboy's `TouchGamepad`, with
NESTERM's roll-tap changes) translated from JavaScript / CSS to Swift / UIKit, function by
function. Source read: NESTERM `web/brickboy/input.mjs` (1774 lines), `buttons.mjs`,
`desktop-input.mjs`, `PROVENANCE.md`, `web/input-router.mjs`, `web/controller.mjs`,
`web/styles.css`, `web/index.html`, `web/app.mjs`, plus `scripts/controller-check.mjs` and
`docs/controller-port-spec.md` from the NESTERM repository. Licence and provenance:
`../ThirdParty/brickboy/` (Apache-2.0, © 2026 Katsuya Hokamura), `../NOTICE`, and in the app
under Quick Menu › Settings › System › About › Touch Controller.

Files: `Sources/Play/Brickboy/TouchGamepad.swift` (logic), `TouchLayout.swift` (geometry from the
CSS), `TouchControlsView.swift` (drawing + UITouch), `TouchExtrasView.swift` (ReplayNES's extra
buttons), wired in `Sources/Play/GameView.swift` (`PlaySurfaceView`).

## JS → Swift

| NESTERM (file: function / rule) | Swift (type: member) |
|---|---|
| `buttons.mjs: Button` | `BBButton` |
| `input.mjs`: every constant (`R_COMMIT_OF_REACH` … `ROLL_WINDOW_MS`, `HAPTIC_MS`) | same names, module-level `let` in `TouchGamepad.swift` |
| `input.mjs: clamp, lerp, norm360, angularDist, sectorRaw, halfOf, DIR8, DIR8_ORDER, DIR8_SETS, NO_DIRS` | same names (`DIR8` → `enum Dir8`) |
| `input.mjs: DpadPtr` (the `st` object) | `DpadPtr` (class: mutated in place) |
| `input.mjs: rollTap`'s `roll` object | `FaceRoll` |
| `input.mjs: TouchGamepad` | `TouchGamepad` |
| `constructor(root, press, feedback)` | `init(press:feedback:)`; markup → `TouchControlsView.rebuild()` |
| `relayout`, `releasePointer`, `setWays`, `wayCount`, `setHomeGain`, `releaseAll` | same names |
| `setBtn`, `haptic` | `setBtn`, `haptic` (→ `onHaptic`) |
| `setHome`, `resetHome`, `stopHomeReturn`, `startHomeReturn` (+ its `tick`) | same names; the tick is `homeReturnTick` |
| `toElem`, `padBox`, `elemRect`, `visibleLeftOffset`, `frameRect`, `elemViewport` | `toElem`, `padBox`, `elemRect`, `visibleLeftOffset`; `geometry.frame`, `geometry.viewport` |
| `resolveDirs`, `applyDpad`, `foldTouchdown`, `engageDeadzone`, `commitRadius`, `restEstimate`, `calibrateFromTaps` | same names |
| `onDpadDown`, `onDpadMove`, `readDirs`, `startCalib` (+ `tick`), `padRadiusForCalib`, `calibrate`, `onDpadUp` | same names; the tick is `calibTick` |
| `systemButtonsAt`, `applySystem`, `onSysDown/Move/Up` | same names |
| `faceGeometry`, `faceSoloHeldByOther`, `faceButtonsAt`, `rollTap`, `applyFace`, `onFaceDown/Move/Up` | same names |
| `input-router.mjs: BUTTON_NAME` (Brickboy id → NES name) | `TouchButton.init(_: BBButton)` → `touch:<name>` ids → `TouchBindings` → `p1.*` |
| `controller.mjs: applySize` (`--bb-dpad` 130…210, CSS 144) | `AppModel.touchDpadSize` → `TouchLayout.Options.dpadSize` (Quick Menu › Touch Controls › D-pad Size) |
| `controller.mjs: applyGain` (追従 ↔ 0.3 / ↕ 1, 0…2) | `AppModel.touchFollowX/Y` → `setHomeGain` (D-pad Follow ↔ / ↕) |
| `controller.mjs: syncWays`, `setGame` (ways per ROM) | `AppModel.touchWays` / `toggleTouchWays()` (per ROM SHA-256), the `8-WAY` pill and the D-pad Directions setting |
| `controller.mjs: releaseAll` on blur / visibility / sheet | `TouchControlsView.releaseAll()` when the controls hide (Quick Menu, controller connected) and on dismantle; UIKit cancels touches on backgrounding |
| `controller.mjs: syncViewport` (`bb-side` = width > height) | `TouchLayout.make` (landscape when width > height) |
| `styles.css` portrait rules (`#app:not(.bb-side) …`) | `TouchLayout.portrait` |
| `styles.css` landscape grid (`.bb-side > .bb-root …`) | `TouchLayout.landscape` |
| `styles.css` `.gp-dpad`, `::before/::after`, `.gp-hub`, `.gp-arrow`, `.gp-edge`, `.gp-key`, `.gp-round`, `.gp-pill`, `gp-onset` | `TouchControlsView.rebuild()` / `restyle()`, `BBColor` (the `:root` colours), `BBDraw.onset` |
| `styles.css` `.bb-mode-switch` / `.bb-turbo-switch` | `TouchExtrasView` (the extras row's look) |

## Browser concepts → iOS

| Browser | iOS | Notes |
|---|---|---|
| `pointerdown/move/up/cancel`, `lostpointercapture` | `touchesBegan/Moved/Ended/Cancelled` → `TouchGamepad.pointerDown/Move/Up` | one `PointerEvent` per `UITouch` per callback, its latest location (pointer events carry no coalesced samples to the handlers either) |
| `e.pointerId` | an `Int` per `UITouch` (assigned at touchdown) | |
| `e.clientX/Y` | `UITouch.location(in:)` of the full-window play surface | the surface covers the whole screen, like the web viewport |
| `e.timeStamp`, `performance.now()` | `UITouch.timestamp × 1000`, `CADisplayLink.timestamp × 1000` | same clock (system uptime) |
| `setPointerCapture` | UIKit keeps a touch with the view it began in; `TouchGamepad.captured` remembers the element (D-pad / face / system) | |
| window `pointerup` backstop | `pointerUp` always ends with `releasePointer(id)` | |
| element hit test (z-index, `pointer-events: none`, `.gp-ext`, `clip-path: inset(0)`, `transform`) | `TouchGamepad.regionAt`: face and system (z-index 3) before the D-pad; the D-pad box moves with `(ox, oy)` and reaches 34 % of its height above / below (`.gp-ext`); in portrait it is clipped to `.bb-gamepad`; in landscape `.gp-system` is `display: contents`, so only the pills take touches | `point(inside:)` lets every other touch through to the views below |
| `getBoundingClientRect` | `TouchGamepad.Geometry` from `TouchLayout` (`face`/`a`/`b`: with `translateY(∓--gp-off)`; a pressed round moves `-3px` with the 60 ms `ease` transform transition, as the rect does in the browser) | |
| `requestAnimationFrame` / `cancelAnimationFrame` | same API inside `TouchGamepad`, run by a `CADisplayLink` fixed at 60 Hz | Safari's rAF rate; `SHARE_RAMP_TICKS` (~300 ms) and the per-tick speed decay assume it |
| `env(safe-area-inset-*)`, `.bb-root` padding (frameRect) | `safeAreaInsets` of the play surface → `TouchLayout` and `Geometry.frame` | `--bb-edge-gap-*` evaluate to 0; the PWA `bb-chromeless` fixed insets do not apply to an app |
| `vw`, `vmin`, `--bb-el-h`, `--bb-vh` | the surface's width / height in points | CSS px = points |
| `navigator.vibrate(HAPTIC_MS)` / iOS `<input switch>` Taptic | `UIImpactFeedbackGenerator(style: .light)`, once per gesture batch (`hapticArmed`), Settings › Vibration | |
| `classList gp-active`, `style.transform` | `isActive(_:)`, `ox` / `oy` → `TouchControlsView.restyle()` | |
| `system-ui` 11 px / 20 px, `letter-spacing` | `UIFont.systemFont` + kerning; widths measured at run time | |
| `filter: brightness()` in `gp-onset` | colour animation from the brightened colour, 130 ms ease-out | |

## Deviations (and why)

- **Not ported** (diagnostics of the web build): the debug overlay canvas, gesture / face-event
  recording and JSON export, `probe()`, `setTag` / frame samples, the optional button sound
  (`feedback` hook exists, unwired). The CSS **rotation** option (`setRotation`, `toElem` for ±90°):
  iOS rotates the interface itself, so `toElem` is the identity. **`handleKey` / `desktop-input.mjs`**:
  keyboard and game controllers keep using ReplayNES's shared `InputManager` (GameController).
- **`input-router.mjs` frame queue** (one edge per NES frame, up to four queued): not ported. The
  engine's shared input layer already guarantees frame-safe taps (`rn_input_sample_game`: "taps
  shorter than a frame are latched once") and is what gets recorded; two complete taps inside one
  16.7 ms frame reach the game as one press there, not two.
- **A/B autofire** (`setAutofire`, 500 ms then 33 ms, `gp-ring`): ReplayNES has turbo buttons bound
  to the core's `p1.turbo_a/b` instead: **AA / BB** (below).
- **Extras row** (`TouchExtrasView`): L2 (rewind), L (slow / paused: step back), MENU, R (pause /
  step), R2 (fast-forward) and the frame steps have no NESTERM equivalent; they sit where NESTERM
  has its sub bar (portrait, between the picture and the pad) and its top-bar / switch rows
  (landscape, rows 1–2 of the side columns), in the `.bb-mode-switch` style. The `8-WAY` switch is
  NESTERM's.

### Changes after testing on an iPhone 17 (deliberate, ReplayNES)

| Change | Rule (`TouchLayout` / views) | Why |
|---|---|---|
| D-pad 10 % larger | `dpadScale = 1.1` × NESTERM's size (`--bb-dpad`, portrait `min(--bb-dpad, max(112, el-h × .24))`), rounded; the left edge stays (`margin-left` / `--bb-ctl-inset`) | thumb target on the device |
| D-pad centred on the A/B midpoint | `dpad.midY == (a.y + b.y) / 2` in both orientations (NESTERM: both `align-self: center` in the row, which is the same unless AA / BB move the face down) | the layout rule the user asked for; the pad's *home* still follows the thumb (追従 ↕ / ↔, as NESTERM), so after a few taps it may sit lower than this natural place |
| AA / BB up-left of A / B | `.gp-round` look, diameter `0.72 × --gp-btn`, label 15 pt bold; BB up-left of B and AA up-left of A by the same offset, perpendicular to the B → A axis (`turboDirection`; a row parallel to A / B, like a Pro Controller's Y / X over B / A), at distance (btn + s) / 2 + 8 (`turboMetrics`, discs 8 pt apart). Portrait: the offset turns toward straight up (same distance) only as far as needed to keep BB 8 pt clear of the D-pad (SE class). Landscape: the face first moves right into its own 16 px padding (A stays ≥ 8 pt from the screen edge; the face box is clipped to the screen), then the offset turns up as needed so BB never reaches past B's CSS place - the picture keeps its width (`turboOffset`). Bound to `touch:turboA/B` → `p1.turbo_a/b`; Quick Menu › Touch Controls › Turbo Buttons (on by default, key `touchAABB`) | the user found AA / BB straight above A / B unnatural; up-left is where a Pro Controller has X / Y |
| AA / BB touches | drawn and hit-tested by `TouchExtrasView` (above the gamepad): disc + 4 pt; the zones never reach the A / B discs (≥ 4 pt clear), they only take the part of `.gp-face`'s padding they cover. A touch that begins on the face stays with the face, so `faceButtonsAt` / `rollTap` are unchanged; a touch on AA / BB is held until lifted (no sliding between AA / BB / A / B) | keep the ported A/B logic intact |
| Face position | the A/B midpoint is the row's middle, moved down only as far as needed for AA / BB to stay inside the row (`faceMid`; SE portrait) | SE-class heights |
| L2 / R2 | larger pills (46 × 30) with SF Symbols `backward.fill` / `forward.fill` instead of text | the user's request |
| Frame step ◀︎| / |▶︎ | `backward.frame` / `forward.frame` pills (32 wide) just inside L2 / R2 (portrait: `8-WAY · ⏪ ◀︎| L MENU R |▶︎ ⏩`; landscape row 1: `⏪ ◀︎| L` and `R |▶︎ ⏩`, MENU moves to row 2 right, NESTERM's repeat-switch place). One frame back / forward per press, also while playing: the press pauses, then steps - the desktop's Step Back / Frame Advance keys (`EmulationController.stepFrame`); handled by the app (`TouchButton.stepBack/.stepForward`, no input id). Narrow screens: the row's gaps shrink to 2 pt, then the icon pills narrow (≥ 60 %) | step without the pause-first dance |
| Landscape picture | the game view is the space between the control columns: symmetric about the screen's centre, 8 pt clear of the nearest visible control (D-pad, A / B / AA / BB discs, pills); the renderer scales the picture into it (NESTERM draws the controls over a full-screen picture). The pad's frame (`Geometry.frame`, used by `setHome`'s clamp) ends at the picture, so the home cannot follow the thumb over it. The side columns show `--bb-bg` | no control over the picture on iPhone 17 / 17 Pro Max / SE (`testLandscapePictureBetweenTheControls`) |
| Rotation | the play screen is sized from the screen (GeometryReader), never from the published layout (it made the SwiftUI stack the union of both orientations, 874 × 874, which the surface then kept); the D-pad layer's transform is reset before its frame is set; on an orientation change the held controls are released and the learned home restarts at the natural place (NESTERM re-clamps it: `relayout`) | layout broke after turning the iPhone |
| Orientation setting | Settings › Display › Picture Shape › Orientation: Auto / Portrait / Landscape (`OrientationLock`: app delegate `supportedInterfaceOrientationsFor` + `requestGeometryUpdate`, key `orientationLock`); Picture Shape is now linked from Display on iPhone too (8:7, Hide Edges moved there as on the Mac) | iPhone only |
- **Top bar / sub bar caption** are not drawn (ReplayNES has the Quick Menu); in portrait the picture
  starts at the safe area and the sub bar row holds the extras.
- **Picture**: ReplayNES's renderer (integer / fill scale, 8:7, CRT) instead of NESTERM's ASCII view;
  in landscape it sits between the control columns (above), not under them.
- **Opacity** setting kept (default 100 %; NESTERM draws opaque).
- **`releaseAll`** also clears the D-pad edge glows (the JS leaves `.gp-edge.gp-active` set until the
  next edge of that direction).
- **Ways key**: per ROM by SHA-256 (`touchWays:<sha>`) instead of CRC32 (`ways:<crc32>`).
- Visual simplifications: the inset shadows of `.gp-key` and the arrow colour transition (60 ms) are
  not drawn; everything else follows the CSS values (sizes, radii, colours, glows, press scale and
  offset, onset flash).

## Tests

- `Tests/BrickboyGoldenTests.swift`: replays 2 × 8 scenarios recorded from the **unmodified**
  `input.mjs` in a browser (Fixtures `golden-portrait.json`, `golden-landscape.json`; generator
  `docs/nesterm-golden/`) and requires the same held buttons, touchdown region and home offset after
  every step (±1e-4 px: Chrome's single-precision rects of the translated pad).
- `Tests/TouchControlsTests.swift`: layout vs the CSS measured in the browser (portrait 390 × 844,
  landscape 844 × 390, safe areas; AA / BB off, D-pad × 1.1), the deliberate changes above on
  iPhone 17 / 17 Pro Max / SE in both orientations (D-pad size and A/B-midpoint centre, AA / BB
  up-left position and zones, no picture width lost to them, L2 / R2 / step zones, landscape picture clear of every control, everything on screen and
  apart), the pure helpers, NESTERM's `controller-check.mjs` expectations on the iPhone layout,
  bindings. The goldens are unaffected (they carry their own recorded geometry).
- `UITests/TouchGestureUITests.swift` (scheme `ReplayNESTouchUI`): synthesised multi-touch paths on
  the running app (D-pad slide + diagonal, B→A slide, two-finger latch, roll tap, START+SELECT) in
  portrait and landscape, checked through the `-logTouch` accessibility probe.

Regenerating the goldens: serve a folder with `docs/nesterm-golden/index.html`, `golden.mjs` and
NESTERM's `web/styles.css`, `web/brickboy/input.mjs`, `web/brickboy/buttons.mjs` under `web/`
(plus a POST endpoint for `/save/<name>`), open it at 390 × 844 and at 844 × 390, and run
`await import('/golden.mjs'); await runGolden('portrait' | 'landscape')`.
