# ReplayNES for iPhone (prototype)

> Branch `ios` only, local only. A personal test build for your own iPhone: it uses the same
> Nestopia core as the other platforms (GPL-2.0-or-later; the licensing of an App Store release
> is an open question) and must not be distributed.

[日本語は下にあります](#日本語)

## Run it on your iPhone (free Apple ID, "Personal Team")

You need a Mac with Xcode (16 or later), Homebrew `xcodegen`, `cmake` and `ninja`
(`brew install xcodegen cmake ninja`), this repository with its submodules
(`git submodule update --init`) and an iPhone with iOS 17 or later.

1. Generate the Xcode project: `cd apps/ios && xcodegen generate`, then open
   `apps/ios/ReplayNES.xcodeproj`.
2. Xcode › Settings › Accounts › **+** › Apple ID: sign in. A free account appears as
   "Your Name (Personal Team)".
3. Select the **ReplayNES** target › **Signing & Capabilities**: Team = your Personal Team,
   Bundle Identifier = something only you use, e.g. `io.github.<you>.replaynes.dev`
   (the default `io.github.replaynes.dev` is taken by whoever registered it first).
   To keep these when the project is regenerated, put them into
   `apps/ios/Config/Signing.local.xcconfig` instead (not committed):
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   PRODUCT_BUNDLE_IDENTIFIER = io.github.<you>.replaynes.dev
   ```
4. Connect the iPhone with a cable, unlock it and tap **Trust**. Turn on
   **Settings › Privacy & Security › Developer Mode** (the iPhone restarts; confirm afterwards).
   The option appears after the iPhone has been connected to Xcode once.
5. Choose your iPhone as the run destination (toolbar) and press **Run** (⌘R). The first build
   also builds the emulator core for iOS (CMake, about a minute).
6. The first launch is blocked until you trust yourself as developer:
   **Settings › General › VPN & Device Management › (your Apple ID) › Trust**.

From the terminal instead (writes `Signing.local.xcconfig`, builds Release, installs, launches):

```sh
apps/ios/scripts/build-device.sh --team ABCDE12345 --bundle-id io.github.<you>.replaynes.dev --install
apps/ios/scripts/build-device.sh --install        # later runs remember the values
```

The team id is the `OU=` value of
`security find-certificate -a -c "Apple Development" -p | openssl x509 -noout -subject`.

**Free account limits:** the app's provisioning profile expires after **7 days**; then the app
no longer opens. Connect the iPhone and run again (Xcode or the script) - your games,
recordings and settings stay. A free team can have 3 apps installed this way, and register
10 app ids per 7 days.

## Add ROMs

The app's Documents folder is visible in the Files app as **On My iPhone › ReplayNES**:

- `ROM/` - your `.nes` files (sub-folders one level deep are fine)
- `Projects/` - kept recordings (`.nesrec`, the same format as on the Mac: copy them either way)
- `Exports/` - MP4 videos, `Backups/` - copies made before "Start Over"

Ways to get ROMs there:

- **Mac Finder:** select the iPhone in the sidebar › **Files** tab › drag the `.nes` files onto
  **ReplayNES**. Files dropped at the top level are moved into `ROM/` automatically.
- **Files app** on the iPhone: copy / move into On My iPhone › ReplayNES › ROM (also from iCloud
  Drive, AirDrop to Files, a USB stick).
- In the app: **+** in the library (document picker, several files at once), or share from
  another app (Share Extension, below). Imports run in the background: each file is checked (`.nes`
  with an iNES header), skipped if the same ROM (SHA-256) is already in the library, and copied
  under a free name (`Name 2.nes`); a toast says how many were added / already there / skipped.
  An import never starts a game (also not for one file) and never touches the running session.
  Many files from the Files app (Select › Share) or another app: the **Share Extension** ("Add to
  ReplayNES"; the only ReplayNES entry in the share sheet: the app declares no
  document type for `.nes`, so there is no "Open in ReplayNES" for `.nes` (the app's own entry would
  get only the first file); `.nesrec` projects can still be opened in place) asks "Add N file(s) to ReplayNES" and
  copies every file into the App Group's `ShareInbox`; the app imports them as above as soon as it
  is active (at once when it is running). A shared `.nesrec` goes into `Projects/` (one alone is
  opened). The extension needs the App Group `group.<your bundle id>` (automatic signing registers
  it and the extension's id `<your bundle id>.share`).
- No ROM at hand: **Add Test Cartridge** in the empty library writes the ReplayNES Test Cartridge (a small CC0 test program built into the engine; `tools/testcart`).

## Using it

- **Library:** Continue card (the last session, where you left it), game cards with titles from
  the game database, sort (title, recently played, publisher, year, genre) and show (all, favourites, recent) menus, search,
  long-press a card for favourites and its kept recordings.
- **Playing:** the on-screen controller is NESTERM's (Brickboy's) touch gamepad, ported line by
  line (docs/TOUCH_PORT.md): portrait = picture on top, controls below; landscape = picture
  centred between the control columns (never under them). Adaptive D-pad (it follows your thumb; 8-way or 4-way per game:
  the 8-WAY pill), A / B as one pad (between them = both; holding one and rolling the thumb onto
  the other taps it; a second finger while one is held presses the other), SELECT / START
  (between them = both), AA / BB up-left of A / B (turbo A / B). Extra pills: ⏪ L2 rewind (hold),
  ◀︎| / |▶︎ one frame back / forward (pauses first while playing), L slow motion, MENU, R pause,
  ⏩ R2 fast-forward through what was recorded (hold). D-pad size and follow, opacity, AA / BB,
  vibration: Quick Menu › Settings › Controls › Touch Controls; screen orientation (Auto /
  Portrait / Landscape): Settings › Display › Picture Shape.
- **Paused:** the seek bar - drag to scrub (replays, never records), step one frame (also L / R
  and D-pad ← / →), set A / B of a section at the playhead, practice it, ▶ resumes.
- **Game controllers** (MFi, Xbox, PlayStation, Switch Pro / Joy-Con): same bindings and rules as
  the Mac (L+R opens the Quick Menu, east confirms by default, L2 / R2 rewind / fast-forward,
  paused D-pad steps). The touch controls hide while one is connected (setting).
- **Quick Menu:** the same pages as on the Mac (Resume, Retry, Practice, Share, Settings, Game).
- The app pauses and saves when it leaves the foreground; the library offers "Continue".

## Free and unlocked features (gating for later paid unlocks)

| | Free | Unlock |
|---|---|---|
| Play, rewind, fast-forward, slow motion, frame step, flash reduction | yes | |
| Practice (A/B repeat), replay / takes / bookmarks of the current session | yes | |
| The current session is autosaved and resumed (single temporary slot, replaced when another game starts) | yes | |
| Keep recordings: every game starts its own project in `Projects/`, Save, "keep the previous session?" | | **Recording** |
| Share › Export MP4 | | **MP4 Export** |
| CRT display model (and CRT in exports, with MP4 Export) | | **CRT** |

Opening projects that already exist (made while unlocked, or copied from the Mac) is never
locked, and locking never deletes or hides anything.

Design (`Sources/Entitlements/`, core-agnostic, unit-tested):

- `FeatureGate.swift` - `PaidFeature` (`.recording`, `.mp4Export`, `.crt`), `EntitlementState`
  and the pure policy: `GatedAction` → feature, where a library game is recorded (temporary slot
  vs new project), what happens to a previous temporary session, effective CRT.
- `Entitlements.swift` - the observable state the UI reads; **Unlock Everything (Test)** (on by
  default in this prototype; Quick Menu › Settings › System › Unlocks, or `-debugUnlockAll NO`).
- `PurchaseStore.swift` - `StubPurchaseStore` (default: in memory / UserDefaults, no network;
  "Unlock" simulates a purchase) and `StoreKitPurchaseStore` (StoreKit 2: `Product.products`,
  `purchase`, `Transaction.currentEntitlements`; only created with `-storeKitLive YES`).
  Product ids are placeholders (`io.github.replaynes.unlock.recording` / `.mp4export` / `.crt`).

## Architecture

Single source of truth, as on every other platform:

- **Engine + shared frontend core** (C/C++): built for iOS by `scripts/build-engine.sh` from the
  same CMake source lists (`-DCMAKE_SYSTEM_NAME=iOS`, arm64, per SDK: `iphoneos`,
  `iphonesimulator`; `--xcframework` also packs `ReplayNESCore.xcframework`). The Xcode
  "Engine" target runs it for the SDK being built; the app links `libreplaynes_all.a`.
- **Swift shared with macOS, referenced in place** from `apps/macos` (no copies):
  `Sources/Core/**` (engine wrapper, library, game DB, input catalog, pacing logic
  (`DisplayCadence`, `InputDeadline`, `AudioRateControl`, resampler), timeline, practice, CRT
  model + Metal shaders, MP4 exporter, flash filter, resume, Quick Menu tree) and from
  `Sources/App`: `EmulationController` (emulation thread + `CAMetalDisplayLink` pacing),
  `MetalView` (`GameRenderer`, CRT), `Runtime` (audio ring / `AVAudioEngine` output with DRC),
  `LatencyMeter`, `InputManager` (game controllers: chord, confirm / cancel, paused stepping),
  `QuickMenuController`, `SeekMarkers`, `TimelineActions`, `Filmstrip`, `CRTSettings`, and the
  string catalog `Localizable.xcstrings`.
- **iOS only** (`apps/ios/Sources`): `AppModel` (session lifecycle without panels, background
  persistence, gating), `GameView` (`CAMetalLayer` view + touch controls in one UIKit view),
  `TouchLayout` / `TouchRouter` / `TouchControlsView` (raw `UITouch`, no gesture recognisers,
  haptics), `PlayView` / `SeekBarPanel`, `TouchQuickMenu` + `QuickMenuPages` (same tree and item
  ids as macOS), `LibraryView` / `LibraryModel` (Documents/ROM + Projects), `AudioSessionSetup`
  (playback, 48 kHz, 256-frame IO buffer), `ExportView`, `UnlocksView`, `Entitlements/*`.
- Changes to `apps/macos` (kept tiny for easy merges from `main`): `#if os(macOS)` around the
  AppKit view in `MetalView.swift` and the keyboard part of `InputManager.swift`, and
  `iOS 18.0` added to one `#available` in `CRTRenderer.swift`. Everything else that differs is a
  stand-in in `Sources/Support/Shims.swift` (`MenuPillOverlay`, `NSSound.beep`, the HAL buffer
  property id; in the simulator also `MTLDrawable.addPresentedHandler` and a silent
  `AVAudioEngine`, see below).
- iOS strings: `Resources/IOS.xcstrings` (table `IOS`, Japanese included). The shared catalog is
  never rewritten by these targets (`SWIFT_EMIT_LOC_STRINGS = NO`).

Pacing is the macOS design (docs/FRAME_PACING.md): the emulation thread owns a
`CAMetalDisplayLink`, emulates one frame per NES frame on the refresh that starts it (60 Hz: every
refresh; ProMotion 120 Hz: every 2nd, `CADisableMinimumFrameDurationOnPhone`), samples input just
in time and presents for exactly that refresh; audio follows with dynamic rate control.
Quick Menu › Settings › System › Latency Meter shows the live numbers on the device.

## Simulator, tests, measurements

```sh
cd apps/ios && xcodegen generate && cd ../..
xcodebuild -project apps/ios/ReplayNES.xcodeproj -scheme ReplayNES \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test      # 101 tests
xcrun simctl launch booted io.github.replaynes.dev -autoplayTestROM YES -pacingProbe 8
```

Import checks (scheme `ReplayNESTouchUI`, `ROMImportUITests`): `testMultiFileImportBatch` needs
nothing; `testShareFromFilesApp` shares On My iPhone › ShareROMs from the Files app through the
Share Extension (Select All › Share › ReplayNES › Add) and checks that every ROM arrives - put
7 `.nes` files (or set `TEST_RUNNER_SHARE_ROM_COUNT`) into the simulator's `…/data/Containers/Shared/AppGroup/<group.com.apple.FileProvider.LocalStorage>/File Provider Storage/ShareROMs`
first (`TEST_RUNNER_SHARE_WHILE_PLAYING=1` / `TEST_RUNNER_SHARE_COLD=1` for the other states).
The test also asserts that the share sheet lists exactly one ReplayNES entry.

Launch arguments for checks (`Sources/Support/TestHooks.swift`): `-autoplayTestROM YES`,
`-openMenu <page>`, `-pauseAfter <s>`, `-holdTouch r`, `-orientation landscape`, `-rotateCycle <s>`,
`-orientationLock 0|1|2`,
`-debugUnlockAll NO`, `-touchHideWithPad NO`, `-showLatency YES`, `-pacingProbe <s>` (writes
`Library/Caches/pacing.json` in the app container).

Simulator caveats (functional checks only - measure on the iPhone):

- The simulator has no sound in this build: on the Mac this was made on, the simulator's audio
  service deadlocks every `AVAudioEngine` (also a minimal one) and aborts the app, so simulator
  builds use a silent stand-in (`Shims.swift`). Device builds use the real engine.
- The simulator SDK lacks `MTLDrawable.addPresentedHandler`; a stand-in reports approximate
  times, so the latency numbers are meaningless there.
- Measured in the iPhone 16 Pro simulator: display link 60 Hz with a locked 1:1 cadence, but the
  simulator returns drawables slowly, so only ~40 frames / s are presented and emulated
  (step 0.4 ms per frame, sample → screen ~19 ms). On a device the same code is expected to run
  60 / 120 Hz like on the Mac; check with the Latency Meter.

---

## 日本語

> `ios` ブランチ専用・ローカル専用です。自分の iPhone で試すための個人用テストビルドで、他の
> プラットフォームと同じ Nestopia コア（GPL-2.0-or-later。App Store 配布時のライセンスは未解決）を
> 使っています。配布しないでください。

### iPhone で動かす（無料の Apple ID「Personal Team」）

必要なもの：Xcode（16 以降）が入った Mac、Homebrew の `xcodegen` `cmake` `ninja`
（`brew install xcodegen cmake ninja`）、サブモジュール込みのこのリポジトリ
（`git submodule update --init`）、iOS 17 以降の iPhone。

1. Xcode プロジェクトを生成：`cd apps/ios && xcodegen generate` を実行し、
   `apps/ios/ReplayNES.xcodeproj` を開きます。
2. Xcode › 設定（Settings）› Accounts › **＋** › Apple ID でサインイン。無料アカウントは
   「あなたの名前 (Personal Team)」として表示されます。
3. **ReplayNES** ターゲット › **Signing & Capabilities** で、Team に Personal Team を選び、
   Bundle Identifier を自分専用の値（例：`io.github.<自分の名前>.replaynes.dev`）に変えます
   （既定の `io.github.replaynes.dev` は最初に登録した人しか使えません）。
   プロジェクトを生成し直しても残すには、代わりに `apps/ios/Config/Signing.local.xcconfig`
   （コミットされません）に書きます：
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   PRODUCT_BUNDLE_IDENTIFIER = io.github.<自分の名前>.replaynes.dev
   ```
4. iPhone をケーブルで接続し、ロックを解除して「信頼」をタップ。
   **設定 › プライバシーとセキュリティ › デベロッパモード** をオンにします（再起動後に確認が出ます）。
   この項目は、一度 Xcode に接続すると表示されます。
5. Xcode のツールバーで実行先に自分の iPhone を選び、**Run**（⌘R）。初回はエミュレータコアの
   iOS 向けビルド（CMake、1 分ほど）も行います。
6. 初回起動は、開発元を信頼するまでブロックされます：
   **設定 › 一般 › VPN とデバイス管理 ›（自分の Apple ID）› 信頼**。

ターミナルから行う場合（`Signing.local.xcconfig` を書き、Release でビルドしてインストール・起動）：

```sh
apps/ios/scripts/build-device.sh --team ABCDE12345 --bundle-id io.github.<自分の名前>.replaynes.dev --install
apps/ios/scripts/build-device.sh --install        # 2 回目以降は値を覚えています
```

チーム ID は
`security find-certificate -a -c "Apple Development" -p | openssl x509 -noout -subject`
の `OU=` の値です。

**無料アカウントの制限：** プロビジョニングプロファイルは **7 日** で期限が切れ、アプリが
起動しなくなります。iPhone を接続してもう一度 Run（またはスクリプト）すれば復活し、ゲーム・記録・
設定はそのまま残ります。この方法で入れられるアプリは 3 個まで、App ID の登録は 7 日間に 10 個までです。

### ROM の入れ方

アプリの Documents フォルダは、ファイル App で **このiPhone内 › ReplayNES** として見えます。

- `ROM/` … `.nes` ファイル（1 階層までのサブフォルダも可）
- `Projects/` … 残した記録（`.nesrec`。Mac 版と同じ形式なので相互にコピーできます）
- `Exports/` … MP4 動画、`Backups/` …「最初からやり直す」前のバックアップ

入れ方：

- **Mac の Finder：** サイドバーで iPhone を選び › **ファイル** タブ › `.nes` を **ReplayNES** に
  ドラッグ。いちばん上に置かれたファイルは自動で `ROM/` に移動します。
- iPhone の **ファイル App：** このiPhone内 › ReplayNES › ROM へコピー／移動（iCloud Drive、
  AirDrop でファイル App へ、USB メモリからも）。
- アプリ内：ライブラリの **＋**（ファイル選択、複数可）、または他の App からの共有（共有拡張、下記）。読み込みはバックグラウンドで行い、各ファイルを確認（`.nes` かつ iNES ヘッダ）、同じ ROM
  （SHA-256）がすでにあれば追加せず、空いている名前（`名前 2.nes`）でコピーします。結果は
  「N 本のROMを追加しました」のトーストで表示（追加済み・スキップ件数つき）。読み込みでゲームが
  起動することはなく（1 ファイルでも）、実行中のセッションにも触れません。
  ファイル App（選択 › 共有）や他の App から複数ファイルを送るときは **共有拡張**（「ReplayNESに追加」。
  共有シートに出る ReplayNES はこれだけです。アプリは `.nes` の書類タイプを宣言しないので、`.nes` の
  「ReplayNES で開く」は出ません（アプリ本体の項目は最初の 1 ファイルしか受け取れないため）。
  `.nesrec` はその場で開けます）が「N 本をReplayNESに追加」を表示し、すべてのファイルを
  App Group の `ShareInbox` にコピーします。アプリは前面に来たとき（起動中ならすぐ）に上と同じ方法で
  読み込みます。共有した `.nesrec` は `Projects/` に入ります（1 つだけなら開きます）。拡張には
  App Group `group.<バンドルID>` が必要です（自動署名で拡張の ID `<バンドルID>.share` とともに登録されます）。
- ROM が手元にない場合：空のライブラリの **テストカートリッジを追加** で、エンジンに内蔵された ReplayNES テストカートリッジ（CC0 の小さなテストプログラム、`tools/testcart`）を追加できます。

### 使い方

- **ライブラリ：**「続きから」カード（前回の場面から再開）、ゲーム DB のタイトル付きカード、
  並べ替え（タイトル、最近遊んだ順、発売元、発売年、ジャンル）と表示（すべて、お気に入り、最近）、検索、カード長押しで
  お気に入り・残した記録。
- **プレイ：** 画面のコントローラーは NESTERM（Brickboy）のタッチ操作をそのまま移植したものです
  （docs/TOUCH_PORT.md）。縦持ちは上に画面・下に操作ボタン、横持ちは中央に画面・左右にボタン。
  親指に追従する十字キー（ゲームごとに 8 方向 / 4 方向：8-WAY ボタン）、A / B は一体のパッド
  （間を押すと両方、片方を押したまま親指を転がすともう片方をタップ、押している間の 2 本目の指は
  もう片方）、SELECT / START（間で両方）。追加ボタン：L2 巻き戻し（長押し）、L スロー、MENU、
  R 一時停止、R2 録画済み区間の早送り（長押し）、◀︎| / |▶︎ 1コマ戻る／進む（再生中は一時停止してから）、
  A / B の左斜め上に AA / BB（連射 A / B）。十字キーの大きさと追従・不透明度・AA / BB・振動：
  クイックメニュー › 設定 › 操作 › タッチ操作。画面の向き（自動／縦／横）：設定 › 画面 › 画面の形。
- **一時停止中：** シークバー。ドラッグで移動（再生のみで記録しません）、1 フレーム送り／戻し
  （L / R、十字キー ← / → でも）、再生位置に区間の A / B を設定、その区間を練習、▶ で再開。
- **ゲームコントローラ**（MFi、Xbox、PlayStation、Switch Pro / Joy-Con）：Mac と同じ割り当てと
  ルール（L+R でクイックメニュー、既定は右ボタンで決定、L2 / R2 で巻き戻し／早送り、一時停止中の
  十字キーでコマ送り）。接続中は画面のボタンを隠します（設定で変更可）。
- **クイックメニュー：** Mac と同じ構成（再開、やり直す、練習、共有、設定、ゲーム）。
- バックグラウンドに移ると一時停止して保存し、ライブラリに「続きから」が出ます。

### 無料機能とアンロック（将来の有料アンロックに向けた機能制限）

| | 無料 | アンロック |
|---|---|---|
| プレイ、巻き戻し、早送り、スロー、コマ送り、点滅軽減 | ○ | |
| 練習（A/B リピート）、現在のセッションのリプレイ／テイク／ブックマーク | ○ | |
| 現在のセッションの自動保存と再開（一時スロット 1 つ。別のゲームを始めると置き換え） | ○ | |
| 記録を残す：ゲームごとに `Projects/` へプロジェクト作成、保存、「前回のセッションを残す？」 | | **記録** |
| 共有 › MP4 書き出し | | **MP4書き出し** |
| CRT 表示モデル（MP4書き出しと併せて書き出しにも CRT） | | **CRT表示** |

既存のプロジェクト（アンロック中に作ったもの、Mac からコピーしたもの）を開くことは常に可能で、
ロックによってデータが消えたり隠れたりすることはありません。

設計（`Sources/Entitlements/`、コア非依存、ユニットテスト付き）：`FeatureGate.swift` が
`PaidFeature`（`.recording` `.mp4Export` `.crt`）と純粋なポリシー、`Entitlements.swift` が UI の
参照する状態と **すべてアンロック（テスト）** スイッチ（試作では既定オン。クイックメニュー › 設定 ›
システム › アンロック、または `-debugUnlockAll NO`）、`PurchaseStore.swift` が
`StubPurchaseStore`（既定。通信なし、「アンロック」は購入の擬似再現）と StoreKit 2 版
`StoreKitPurchaseStore`（`-storeKitLive YES` のときだけ使用）。プロダクト ID は仮の値です。

### 構成

- エンジンと共有フロントエンドコア（C/C++）は `scripts/build-engine.sh` が他のプラットフォームと
  同じ CMake ソースリストから iOS 向け（arm64、`iphoneos` / `iphonesimulator`）にビルドします。
- Mac 版と共有する Swift は `apps/macos` のファイルをそのまま参照しています（コピーなし）：
  `Sources/Core` 全体と、`EmulationController`（エミュレーションスレッドと `CAMetalDisplayLink`）、
  `MetalView`（描画・CRT）、`Runtime`（音声出力と DRC）、`InputManager`（ゲームコントローラ）、
  `QuickMenuController`、`SeekMarkers`、`TimelineActions`、`Filmstrip`、`CRTSettings`、
  `LatencyMeter`、文字列カタログ。
- `apps/macos` への変更は最小限（`MetalView.swift` と `InputManager.swift` の `#if os(macOS)`、
  `CRTRenderer.swift` の `#available` に `iOS 18.0` を追加）。それ以外の差分は
  `Sources/Support/Shims.swift` の代替実装で吸収しています。
- シミュレータでは音が出ません（この Mac のシミュレータ音声サービスが `AVAudioEngine` を
  デッドロックさせるため、無音の代替実装を使用）。表示タイミングの数値も実機で確認してください
  （シミュレータでは 60 Hz・1:1 で同期しつつ、描画面の返却が遅く毎秒約 40 フレーム）。
