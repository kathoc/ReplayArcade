# ReplayArcade

[English](README.md)

ReplayArcade は、[ReplayNES](https://github.com/kathoc/ReplayNES) のアーケード版です。遊んだすべてを記録するプレーヤーで、
エミュレーターのコアには [FinalBurn Neo](https://github.com/finalburnneo/FBNeo) を使っています。

- 遊んだ内容はすべて記録されます。巻き戻し（L2）、好きな場所からのやり直し、テイク、ブックマークが使えます。
- 区間を決めた練習ができます。開始前のカウントダウン（3、1、なし）、自動保存、続きからの再開に対応しています。
  一時停止中のシークバーで、上のボタンを押すと印を付けます（2 つで区間になり、印の上で押すと消えます）。
  左のボタンで練習を始めたり止めたりし、L / R で区間を切り替え、L + START で最初の印に戻ります。
- 動画の書き出し: 好きな範囲を MP4 で書き出せます。
- ボタンの割り当てと連射はゲームごとに設定でき、パッドとアーケードスティックで別々に覚えます
  （どちらかは自動で判別し、「コントローラー」のページで変えられます）。
- コントローラーだけで操作できます。画面は日本語と英語に対応しています。
- コントローラーとプレイヤー: Steam Deck 本体の操作がプレイヤー 1 のときにコントローラーをつなぐと、
  そのコントローラーがプレイヤー 1 になり、外すと本体に戻ります。プレイヤー 2〜4 は、つないだコントローラーを
  そのまま使い続けます。一時停止中は、左上の四角で、どのプレイヤーにコントローラーがあるかが分かり、
  ボタンを押すとその四角が光ります。
- アーケードのゲームだけを扱います。FinalBurn Neo の家庭用機のセット（メガドライブ、PC エンジン、
  ファミコンなど）は、開くことも一覧に出すこともしません。
- キーボード: 矢印キー、ボタン 1〜6 は Z X C / A S D、コインは 5（プレイヤー 2 は 6）、スタートは 1 または
  Return（プレイヤー 2 は 2）。MAME と同じ配置です。
- マウス（「設定 > 操作 > 詳細 > マウス」、既定は切）: アナログ操作のゲーム向けです。
  トラックボール、ダイヤル、パドルはマウスの動きに合わせて動きます（アルカノイド、サイバリオン、
  キャメルトライ）。フライトスティックはマウスの位置に合わせて動き、ホイールでスロットルを動かすか、
  アクセルとブレーキを押します。マウスの左・右・中ボタンは、ボタン 1〜3 になります
  （アフターバーナー II ではバルカン、ミサイル、速度。ギャラクシーフォース II も同様）。
  ゲーム中はポインターをゲームが使い、Esc で戻ります。パッドやゲーム用のキーを押すと、マウスで動かした
  スティックとレバーは中央に戻ります。
- 再生の一致: 最初から通して再生した記録は、Linux と Windows で同じ結果になります。FinalBurn Neo には、
  ステートセーブで保存されていなかった状態も保存するよう手を加えています（`patches/fbneo/`）。
  256 本のゲームで、シーク、巻き戻し、書き出し、プロジェクトの開き直しのどれを行っても、
  同じように再生されることを確かめています。

対応機種: Steam Deck / Linux（Flatpak）、Windows x64、Android（64 ビット）

## ダウンロード

**[最新版のリリース](https://github.com/kathoc/ReplayArcade/releases/latest)** から、お使いの機種のファイルを選んでください。

| 機種 | ファイル |
|---|---|
| Steam Deck / Linux | [io.github.kathoc.ReplayArcade.flatpakref](https://github.com/kathoc/ReplayArcade/releases/latest/download/io.github.kathoc.ReplayArcade.flatpakref)（または `io.github.kathoc.ReplayArcade-<版>-x86_64.flatpak`） |
| Windows x64 | `ReplayArcade-<版>-windows-x64.zip` |
| Android（64 ビット、Android 10 以降、Vulkan 対応） | `ReplayArcade-<版>-android-arm64.apk` |

## インストールと更新

### Steam Deck / Linux

1. デスクトップモードで Konsole を開き、次を実行します。
   ```bash
   flatpak install --user https://kathoc.github.io/ReplayArcade/flatpak/io.github.kathoc.ReplayArcade.flatpakref
   ```
   ダウンロードした `.flatpakref` を Discover で開いてもかまいません。リポジトリは GPG で署名しています。
2. アプリケーションメニューから起動します。ゲームモードで遊ぶには、デスクトップモードの Steam で、
   Steam 以外のゲームとして ReplayArcade を追加してください。
3. 更新: アプリが新しい版を自分で見つけ（「設定 > システム > ReplayArcadeのバージョン」）、Flatpak の
   ポータル経由で入れます。`flatpak update --user` や Discover でも更新できます。
   ポータルが最初に一度だけ出す「更新を許可するか」の確認は、ゲームモードでは表示されません。
   一度デスクトップモードで答えるか、
   `flatpak permission-set flatpak updates io.github.kathoc.ReplayArcade yes` を実行してください。
   Flatpak の権限が増える版（リリースノートに書きます）は、Discover か `flatpak update` で入れてください。

### Windows x64

1. 最新版のリリースから `ReplayArcade-<版>-windows-x64.zip` をダウンロードし、好きなフォルダーに展開します。
2. `ReplayArcade.exe` を実行します。「発行元が不明」と警告が出たら、「詳細情報」>「実行」を選んでください。
3. 更新: アプリが最新のリリースを確かめ（「設定 > システム > ReplayArcadeのバージョン」）、ダウンロードした
   ファイルの EdDSA 署名を検証してから入れます。

### Android

1. 端末で `ReplayArcade-<版>-android-arm64.apk` をダウンロードして開きます。インストールの許可を
   求められたら、ブラウザーやファイルマネージャーに許可を与えてください。
2. 一度 ReplayArcade を起動すると、フォルダーが作られます。そのあと、ROM の zip を
   `Android/data/io.github.kathoc.replayarcade/files/ReplayArcade/ROM` に入れてください
   （パソコンから USB で転送するか、`Android/data` を開けるファイルマネージャーを使います）。
3. 更新: 新しい APK を、入っているものの上からインストールします。記録と設定はそのまま残ります。
   いまはコントローラーが必要です（タッチ操作は準備中です）。

### ROM

**ROM は含まれていません。** 使用する権利のある ROM の zip（FinalBurn Neo のセット名、non-merged。
例: `gradius.zip`）を `Documents/ReplayArcade/ROM` に入れてください（Steam Deck / Linux / Windows。
Android は上を参照）。入れたあと ReplayArcade を起動し直すと、一覧に出ます。

## ビルド

```bash
git clone --recursive https://github.com/kathoc/ReplayArcade.git
cd ReplayArcade
scripts/fbneo-patches.sh            # FinalBurn Neo へのパッチを当てる

# Linux 版と試験（エンジンの試験には ROM が必要: REPLAYARCADE_ROMS=<フォルダー>）
cmake -S . -B build && cmake --build build -j
# Flatpak（Steam Deck）: packaging/linux/io.github.kathoc.ReplayArcade.yml
# Windows x64（llvm-mingw でクロスビルド。ReplayNES の docs/WINDOWS.md を参照）
scripts/build-windows.sh x86_64
```

## ライセンス

GPL-2.0-or-later です。FinalBurn Neo（独自の非商用ライセンス）と組み合わせるための追加の許可を
付けています。`COPYING.md`、`LICENSE`、`LICENSE-FBNeo.txt`、`THIRD_PARTY_NOTICES.md` を参照してください。
ReplayArcade は無料で、寄付も求めません。
