# Replay ファミリー UI 統一と generalize 取り込みの差分一覧

ReplayNES と ReplayArcade を、全機種で同じ操作体系・見た目・フロントエンドに揃えるための
記録。基準は **ReplayArcade**（= `generalize` ブランチの共通フロントエンド）。ユーザーの決定
（2026-11-06、option A）により、ReplayNES の Android を Kotlin プレビューから generalize の
共通 SDL/Vulkan フロントエンドへ置き換える。これは Android 単体ではなく、`generalize` 全体
（全機種が同じ C++ フロントエンドを共有する「プロダクトプロファイル」化）を取り込むこと。

- 作業ブランチ: `merge-generalize`（`main` へはまだ merge しない / push しない / リリースしない）。
- マージコミット: `eb3a447`。`main`(a395775) に `generalize`(6c32d44) を取り込み。
- 規模: 302 files changed, +25,496 / −3,542（apps/android の構造置換を含む）。
- merge-base: `68b6890`（2026-10-24）。generalize は 101 コミット先行、main は 6 コミット先行。

---

## 1. generalize とは（共通化の中身）

`main` では各機種がそれぞれ UI を持っていた（特に Android は独立した Kotlin プレビュー）。
`generalize` は **1 つの C++ フロントエンド（SDL3 + Vulkan + Dear ImGui、`frontend/` と
`apps/desktop/`）を全機種で共有**し、製品差分を「プロダクトプロファイル」
（`cmake/products/replaynes.cmake` / `cmake/Product.cmake` / `engine/include/replaynes/product.h.in`）
に追い出す。これにより ReplayNES と ReplayArcade を同じソースから別製品としてビルドできる
（ReplayArcade は自身のプロファイル＋FBNeo コアを渡す）。

プロファイルが持つ主な製品差分: 製品名 / アプリ ID / 実行ファイル名 / データフォルダ /
ROM 拡張子 / 既定コア（ReplayNES=nestopia）/ ゲーム DB / フラッシュ低減の有無 /
オーバースキャン切り落としの有無 / NES ビルドの有無 / バージョン（root の CMake VERSION から導出）。

---

## 2. 機種ごとの差分

### エンジン（`engine/`, +1,939 / −330）
- **メディア情報と外部コア対応**: 画サイズ・フレームレート・ステレオを外部コアから受け取る
  （NES 以外のコアを載せる土台）。コンテンツのパス読み込みと同一性（content identity）。
- **フラッシュフィルタ**を 16 の倍数の任意画サイズに対応（従来は NES 固定）。
- **入力レイアウト**: ボタン単位ターボ、アナログ軸、任意コアの入力定義。
- ReplayNES の挙動（NES、256×240、フラッシュ低減 ON、オーバースキャン切り落とし ON）は
  プロファイルで同じ既定のまま。

### 共通フロントエンド（`frontend/`, +1,522 / −322 / `apps/desktop/`, +11,264 / −634）
- **メディア情報対応**: ペーシング・エクスポート・サムネイル・履歴・リール・VTR が画サイズ/回転/
  音声に追従。回転ゲーム向けに VTR 効果を走査線方向へ。
- **巻き戻しの作り直し**: ブロック単位キャッシュ＋先読み（巻き戻し中に下方向を温める、
  コールドギャップ跨ぎ、1 マシン共有コアでは表示 2 tick に 1 回）。大きいステートでも録画フレームを
  止めない疎チェックポイント。チェックポイントは描画後取得（`defer_checkpoints`）。
- **シークバーのサムネイル**をセッション跨ぎでテイクの入力をキーに保持。
- **設定の情報設計を目的別に再編**: Display / Controls / Sound / Play / App
  （`docs/reviews/settings-menu-ia-1.md`）。
- **ぼかしサイド（Blurred Sides）**: なし/シャープ/低/中/高。ライブラリは全 ROM の絵を背景に、
  マウスホイール/スワイプでページ送り。
- **スクリーンセーバー**（ゲームデモの巡回、`docs/design/SCREENSAVER.md`）。
- `rnf_set_rom_filter`（製品が再生できる ROM だけを一覧）、ROM フォルダ文言の製品別化。

### デスクトップ / Linux / Steam Deck（`apps/linux/`, +1,206 / −210）
- 任意コアの入力レイアウト対応のコントロール、ボタン単位ターボ、タイトル別バインド。
- **Steam Input のプレイヤー順**（Controls > Controller の Player Order）、アナログ整形、
  プレイヤー表示の常時化。Steam のメニューポーズ（gamescope の Xwayland を読む）、ゲームモードの
  画面減光抑止、Steam アートワークの更新追従。
- ベゼルは一度実装後にユーザー判断で撤回（`efe752b`）。水平ゲームのぼかしサイド。
- リリース運用（aarch64 Flatpak、macsrv 集約）は main 側をそのまま保持。

### Windows（`apps/windows/`, +881 / −218）
- プロダクトプロファイル追従。メディア情報（画・サムネイル・MP4 エクスポート）。D3D11 のぼかしサイド。
- 更新ヘルパー（旧インスタンス待ちのログ改善）。VM 試験は **macsrv では不可（Parallels Pro 必要）**、
  必要時に旧 Mac の VM で実施（main 側の方針を維持）。

### macOS（`apps/macos/`, +1,792 / −27）
- Metal のぼかしサイド、フロントエンドブリッジ/MP4/セッション復帰の追従。macOS アプリは再度ビルド可
  （`53bdc17`）。SwiftUI の独自 UI 層は維持（共通フロントエンドを Metal で描くブリッジ構成）。

### Android（`apps/android/`, 構造置換 / net +1,516 / −1,727）
**Kotlin プレビュー（`io.github.replaynes` パッケージ、独自 Views/JNI）を全廃**し、generalize の
**SDL/NDK 版**（`io.github.replaynes.android` パッケージ、Java グルー＋`src/*_android.cpp`、
共通フロントエンドを NDK の Vulkan で描画）に置換。

- AGP 9.5 / Gradle 9.8 / Java 21、CMake は `apps/android/CMakeLists.txt`、arm64-v8a のみ、minSdk 29。
- デバイスの向き/サイズ/サーフェス破棄（別アプリ復帰後の黒画面）を扱う（`docs/design/ANDROID.md`）。
- **タッチコントローラ**（iPhone 版のレイアウト/ルールを C++ 移植、`docs/design/TOUCH_ANDROID.md`）、
  ABXY ボタン位置の確認ページ、画面向き設定、システムバー非表示。
- **日本語 UI フォント**を同梱（Noto Sans JP, SIL OFL 1.1、`third_party/fonts/noto-sans-jp`）。
- ランチャーアイコンは `-PrnIcon`（製品の PNG）から mipmap 生成（main のビットマップ mipmap は廃止）。
- **ROM 取り込み（RomImport.java）**: Add ROMs（SAF、複数選択）/ Share・Open with（任意型）/
  ドキュメントプロバイダ（Files アプリに製品がルートとして出る）/ USB(MTP)/ デバイス全体検索。
  製品の ROM 判定は `rnf_library_is_rom_file`（拡張子＋ゲーム DB）。Direct Share ターゲットあり。

---

## 3. 既存挙動が変わる点（要注意）

- **Android は別実装に総入れ替え**。操作・外観・内部構造がすべて共通フロントエンドのものになる。
- **ROM 取り込みの重複処理が逆**: Kotlin 版（＋未コミット実装）は「同名・同内容は上書きせず飛ばし、
  n 本追加・m 本スキップを表示」。generalize の RomImport は「**同名は上書き**（新しいセット扱い）」で
  内容ハッシュ照合なし、トーストは追加数＋失敗/非ROM の列挙。→ §5 で共通側へ仕様を移す。
- **ROM 判定方式**: Kotlin 版は iNES ヘッダ判定。generalize は拡張子＋ゲーム DB（`nes`）。
- **バージョン体系**: `-PrnVersion` と root CMake VERSION 由来のプロダクト版に一本化（現在 0.6.5）。
- `apps/android/README.md` は廃止。Android の説明は `docs/design/ANDROID.md` に集約。

## 4. 衝突と解決（実績）

試行マージの衝突は **3 件のみ**、すべて `apps/android` の add/add:
`.gitignore` / `app/src/main/AndroidManifest.xml` / `gradle.properties`。
→ **apps/android を generalize 版で丸ごと採用**して解決（置換後、generalize とバイト一致を確認）。
main の 0.6.5 リリース成果（`scripts/build-linux-flatpak.sh` の `ARCH`、
`scripts/publish-flatpak-repo.sh` の `ARCHES`、`docs/RELEASE.md` の macsrv/aarch64）は generalize が
触れていないため自動マージで保持。root CMake は 0.6.5 を維持。

## 5. 試験範囲（merge-generalize 上で回す）

- エンジン＋共通フロントエンドの単体/ゴールデン試験（`tests/`、多数追加済み）。
- macOS アプリ（`apps/macos`、XCTest）。
- Android エミュレータ（ReplayArcade の `scripts/test-android-emu.sh` 相当、Android 10/11/13/16）。
- Linux（Lima VM `lima-flatpak`、オフスクリーン UI ツールで描画確認）。
- Windows の VM 試験は macsrv 不可（Parallels Pro 必要）。必要時に旧 Mac で実施。

## 6. 判断の結果（2026-11-06、ユーザー承認）と実装

1. **Android の applicationId と署名** — ユーザー承認: リリースは `io.github.replaynes` に固定し、既存
   `android-release.jks`（alias `replaynes`）で署名。→ `scripts/build-android.sh` を追加
   （`-PrnApplicationId=io.github.replaynes -PrnAppName=ReplayNES -PrnVersion=<CMake版>`、署名は
   `~/.config/replaynes/android-signing.properties` を `RN_ANDROID_*` 環境変数へ渡す）。debug の既定 ID
   （`io.github.replaynes.android`）と ReplayArcade の ID（`rnProductFile` 経由）は不変、build.gradle 無改変。
2. **データ移行** — リリース ID が同じなので更新後も内部ストレージは残る。`MainActivity.setRomDir` に
   一度きりの移行を追加: 旧 Kotlin の内部 `roms/`・`projects/<name>.nesrec` を外部ライブラリの
   `ROM/`・`Projects/` へ移す（既存の同名は上書きしない。一度きりのフラグで防護）。
3. **RomImport の重複仕様** — ユーザー承認どおり変更: 同名・同内容（SHA-256）はスキップ、
   同名・異内容は `name (2).ext` で別名取り込み、トーストに追加/スキップ件数（`rn_import_skipped`, en/ja）。
4. **ReplayArcade サブモジュール更新**（`dfb3bc5` → `6c32d44` 以降）はユーザー承認制。提案のみ（未実施）。

## 7. 検証結果

- **ホスト（エンジン＋共通フロントエンド）**: `cmake -G Ninja … && ninja && ctest` で **39/39 合格**
  （当初 `product_release_identity` のみ失敗＝`frontend.h` のフォールバック版が 0.6.4 のままだった取りこぼし。
  0.6.5 へ修正して解消）。
- **Android リリースビルド**: `scripts/build-android.sh` で `app-release.apk` 生成（package `io.github.replaynes`、
  versionCode 605、versionName 0.6.5、arm64-v8a、署名証明書 SHA-256 が旧 v0.6.5 と**完全一致**）。
- **上書き更新（エミュレータ API29/arm64）**: 旧 v0.6.5(versionCode 7) 導入 → `adb install -r` 新版 → **成功**、
  versionCode が 605 に更新（別アプリにならない）。
- **データ移行（同エミュレータ）**: 旧の内部 `roms/seedrom.nes`・`projects/seedrom.nesrec/journal.bin` を seed →
  更新・起動後、外部 `ROM/`・`Projects/` へ中身そのまま移動、内部は空、ログに
  「migrate: moved 1 ROMs and 1 projects」。
- **Q2（RomImport）**: リリースビルドでコンパイル通過（文言含む）。on-device の重複スキップ動作そのものは未実施
  （共通 RomImport なので ReplayArcade のエミュレータ試験マトリクスが同経路を網羅する）。
- **macOS（XCTest）**: 当初ビルド成功・126 中 6 失敗（QuickMenu/入力カタログ/メニュー移行）。原因は新
  フロントエンドの `settings.play`・`controls.turbo_page`・入力カタログ layout 9・L3 Undo に macOS の Swift
  鏡像が未追従で、pristine な generalize(6c32d44) でも同じ 6 件が再現（＝マージ起因でなく generalize の
  未完了）。**この作業で実装を追従させて修正済み**（ユーザー指示、2026-11-06）。QMPage に Play/Turbo を追加し
  ページ内容を新 IA へ移設、InputManager 移行ラダーを layout 9 へ、テスト期待値も layout 9 へ。l10n は新規 1 行を
  日本語付きで追加し未使用 22 件を剪定。結果 **test-macos.sh: 126 tests 0 失敗 / l10n 0 問題 / smoke 180 frames**。
  コミット f10a036。
  - 判断 1 件: frontend の Play ページにある「Play in the Background」は、macOS が常時背景再生（ウィンドウ非表示でも
    描画継続、トグルなし）のため macOS では行を省略（既存の macOS 固有省略と同じ扱い）。トグル新設が要るなら follow-up。
- **Linux（Lima）**: merge 版の flatpak ビルド（aarch64、SDK 内コンパイル）が **成功**（exit 0）。
- Windows の VM 試験は macsrv 不可（Parallels Pro 必要）。必要時に旧 Mac で実施。

## 8. follow-up（別途・要判断）

- **Q2（RomImport）の on-device 重複スキップ動作**は未実施（共通 RomImport なので ReplayArcade のエミュ試験
  マトリクスが同経路を網羅）。
- **ReplayArcade サブモジュール更新**（`dfb3bc5` → `6c32d44` 以降）はユーザー承認制。提案のみ（未実施）。
