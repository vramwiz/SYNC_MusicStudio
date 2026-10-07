# SYNC_MusicStudio 開発・運用ルール

参照元の規約から、本プロジェクトの現行範囲に必要なものを引き継ぐ。

## 安全性・性能

- AviUtl2のCコールバック境界へDelphi例外を漏らさない。
- ファイル不存在、JSON破損、設定反映失敗でAviUtl2を停止・終了させない。
- 設定変更は検証後に反映し、失敗時は修正できる画面を維持する。
- 設定画面はオブジェクトごとのJSONを扱い、ユーザー設定をDLL共通の可変状態へ保存しない。
- 映像コールバックで外部ファイルや設定の再読込を行わない。
- 並列描画を導入する段階で、キャッシュは読み取り専用データとして設計する。

## ビルド

- Delphi 37.0、Win64のみ。`SYNC_MusicStudio_Filter.dproj`のDebugとReleaseを検証する。
- 警告0、エラー0を原則とする。旧Inputと旧歌詞テストは現行ビルド対象外。
- 出力先は`C:ProgramDataaviutl2PluginSYNC_MusicStudio`。
- ビルドイベントは`ScriptsBuildPlugin.ps1`。DebugはDLL/RSMとauf2を保持し、
  Releaseはauf2生成後に今回のDLL/RSMだけを削除する。
- 現行プロジェクトはSkia/FFmpegを使用しない。将来Skiaを組み込むときは、保存した
  `ScriptsPrepareSkiaUnit.ps1`と初期化資料を参照し、DLLロード中の初期化を避ける。
- Windows PowerShellで使う日本語を含むps1はUTF-8 BOM付きで保存する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild "D:\DelphiProg\MyApp\SYNC_MusicStudio\SYNC_MusicStudio_Filter.dproj" /t:Build /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild "D:\DelphiProg\MyApp\SYNC_MusicStudio\SYNC_MusicStudio_Filter.dproj" /t:Build /p:Config=Release /p:Platform=Win64'
```

配備先は`C:ProgramDataaviutl2PluginSYNC_MusicStudioSYNC_MusicStudio_Filter.auf2`。

## コメント・分割・文字コード

- ユニット先頭に目的と責務を書き、公開処理には入出力と重要な副作用を説明する。
- 状態、ABI配置、所有権や保存対象を明記する。コードの単純な言い換えコメントを増やさない。
- 日本語文字列を持つpas/dprはUTF-8 BOM付き、改行はCRLFとする。
- 1ユニットが約1,000行を超える前に責務の抽出を検討する。フォームとdfmは同じフォルダーへ置く。
- SDK型の順序、サイズ、配置を変更するときは公式SDKと照合する。
- フォームは操作と画面状態を担当し、JSON検証・解析・同期計算・描画は専用ユニットへ置く。

## 保管・配布

- 元のUIを保管し、必要な処理は複製して適応させる。完成に近づいた段階の不要ファイル削除は必須。
- コピーしたSetup、旧Input、旧テスト、git_init.batは参照元用。現在の配布・Git初期化へ使用しない。
- 配布を整える段階でインストール先は{pluginsDir}、共通の永続データは{dataDir}を使用する。
- JSONはファイル参照のみを持ち、WAV/MIDI/PSDの実データを埋め込まない。
- ソース、dfm、プロジェクト、res、必要な文書・スクリプト・素材を管理対象にする。
- Win32/Win64、dcu、rsm、dll、auf2、IDEローカル設定・履歴はGitへ追加しない。

## 設定・JSON・配備プラグインの検証

ビルド後に次を実行する。JSON保存境界、設定フォーム、指定auf2のロードと登録を検証する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Scripts\TestFoundation.ps1
```

Tests/Win64内へ検証用EXE/DCUを生成する。AviUtl2本体のaup2保存・再読込は別途実機確認する。
