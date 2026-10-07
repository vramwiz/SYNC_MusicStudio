# SYNC_MusicStudio 実装・検証履歴

## 2026-10-06 初期プロジェクト作成

- aviutl2_music_performance_editor_spec.mdを確認し、JSON、外部ファイル参照、
  素材と演奏者トラックの分離、3画面構成、未確定のPSDレイヤー仕様を整理した。
- SYNC_Lyricsのソース、UI、ライブラリ、素材、文書をコピーした。
  Git情報、IDE履歴・復旧・ローカル設定、生成済みWin32/Win64成果物は除外した。
- FilterをSYNC_MusicStudio_Filterへ改名し、新しいProjectGuidを発行した。
  名前は演奏スタジオ、グループはSYNC、項目は設定とJSONデータのみへ整理した。
- 参照元の同期編集フォームを複製してJSON管理画面へ整理した。
  JSON編集、読込、保存、復元、適用、明示キャンセルを実装した。
  タイトルバーの閉じる操作は適用し、保存失敗時は設定画面を維持する。
- schemaVersion=1の初期JSON、ルート構造検証、未知フィールド保持、単行化、
  32,767文字の保存上限を実装した。配列要素の詳細スキーマ・固定IDは次段階とする。
- 現行dpr/dprojのコンパイル対象を6ユニットに絞り、旧歌詞描画・同期・Inputを外した。
  旧UI、SongReader、音声関連、共通部品は移植用に保持している。
- 独立したSYNC_MusicStudioフォルダーへ配備するPowerShellビルドイベントを追加した。
  現行段階ではSkia/FFmpeg DLLの追加配備は不要。
- note.mdなどの現行文書を整理し、完成前の不要ファイル削除を必須項目として記録した。
  参照元の元文書はReference/SYNC_Lyricsへ控えを残した。

### 検証結果

- Delphi 37.0 / Win64 Debug: 警告0、エラー0。
- Delphi 37.0 / Win64 Release: 警告0、エラー0。
- JSON: 空文書初期化、日本語・ファイル参照・未知フィールド・エスケープ改行の保持、
  不正JSON・余分な後続JSON・不正バージョン・不正型の拒否、32,767文字境界と超過拒否を確認。
- VCL設定フォーム: DFM生成、初期文書、復元、閉じる時の適用、
  不正な既存データからの明示キャンセル、ヘッダーと入力領域の配置を確認。
  フォーム画像を生成して操作ボタン・JSON本文・ステータスが表示されることを確認した。
- 配備したDebug/Releaseのauf2をLoadLibraryで読み込み、3エクスポート、
  InitializePlugin、SYNC / 演奏スタジオ、設定・JSONデータの2項目とnil終端、
  パススルー映像コールバック、音声コールバックなし、解放を確認。
- 参照元のDFM全12ファイルはコピー後も内容ハッシュが一致した。
- Release配備先ではauf2だけを保持し、DLL/RSMの削除を確認。

検証プログラム: Tests/SYNC_MusicStudio_FoundationTests.dpr。
実行スクリプト: Scripts/TestFoundation.ps1。
AviUtl2本体での配置・設定操作・aup2保存再読込は未確認。
音楽データUI、タイムライン、WAVプレビュー、PSD描画は未実装。
