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

## 6. 未決・要判断（STOP 項目）

1. **【STOP】Android の applicationId と署名（最重要）**
   - 現 v0.6.5 Kotlin リリースのパッケージは **`io.github.replaynes`**（2026-11-05 作成の RSA4096 鍵、
     alias `replaynes`、`~/.config/replaynes/android-release.jks`）。
   - generalize の既定 applicationId は **`io.github.replaynes.android`**（`-PrnApplicationId` で上書き可）。
     署名は環境変数（`RN_ANDROID_KEYSTORE` 他）読み。generalize 単体には ReplayNES 用のリリース
     ビルド script が無い（ANDROID.md の M3「Signing for release」が未了）。
   - **このままだと applicationId が違い、既存 v0.6.5 利用者は上書き更新されず別アプリが入る**
     （データ分離）。→ 推奨: ReplayNES の Android リリースで
     `-PrnApplicationId=io.github.replaynes -PrnAppName=ReplayNES -PrnVersion=<版>` を渡し、
     署名は既存 `android-release.jks`/alias `replaynes` を環境変数経由で使う（同一鍵＝上書き更新可）。
     この配線（`scripts/build-android.sh` 相当）を入れるかどうかの判断が要る。ここで一旦止めて報告。
2. **RomImport の重複仕様**: 「同名・同内容は上書きせず飛ばし、n 追加/m スキップ表示」へ変更
   （generalize の「同名上書き」とは逆の設計。ReplayNES/ReplayArcade 共通になる）。
3. **ReplayArcade サブモジュール更新**（`dfb3bc5` → `6c32d44` 以降）はユーザー承認制。提案のみ。
