# SYNC_MusicStudio 作業ノート

最初に読む現在地。仕様はaviutl2_music_performance_editor_spec.md、設計はDESIGN.md、
手順はDEVELOPMENT.md、完了検証・素材引継ぎはHISTORY.mdを参照。
製品はSYNC / 演奏スタジオ、プロジェクトはSYNC_MusicStudio_Filter。
作業場所D:/DelphiProg/SYNC_MusicStudio。参照元ソース・既存素材・ユーザー差分を保護する。

## 現在地

- 1ページ統合編集画面。右の選択スロットで左の見出し/一覧/＋を切替、名前/色と属性UIを分離。
- 音声WAV/MP3、歌唱MIDI/KAR、共有PSD・母音12枠、PSD別表情/animation/姿勢、拍演奏ピアノロールとレイヤーstepを編集できる。
- 共有正本はKnown Folder Documents/SYNC_MusicStudio/Libraries/PSDAssets/<GUID>。
  原本は変更せず管理コピー、同内容重複排除、欠損復旧、版競合拒否。共有設定と作品の適用/取消は独立。
  PSD本体は一時コピーのサイズ/SHA256検証後に公開。共有rootのファイル排他＋revisionで同一実体の保存競合を拒否。
- 楽器トラックも歌唱可能。演奏は拍、音声/歌唱は秒。テンポ変化と曲全体の固定拍子を編集できる。
  schemaVersion=1、拍配置はarrangementVersion=3。旧スロット/拡張情報/直接PSD参照を保持。
- 編集プレビューは先頭4PSDの部位・母音・表情・姿勢・motion。固定列のキャラ画像は親見出しでなくPSDスロット行。
  左の歌唱PSD/表情一覧と表情クリップは合成画像を共有VisualCacheで表示。再生/一時停止は1ボタン、重複したインジケータ上の秒数を削除。
- AviUtl2最小映像を実装。先頭4PSDを透明・等幅・下揃えで重ね、オブジェクト内秒で母音等を評価。エフェクト別snapshot/完了待ち、音声出力なし。
- 設定背景は自身のPSD合成前フレームバッファを静止画で表示。透明オブジェクト画像とは区別し、描画EDIT_INFO=nil/再描画なし再オープンに対応。未取得は待機表示、取得状況は背景tooltip。背景修正はユーザー実機成功確認済み。今回のUI変更でも両DLLの背景/映像無音回帰を維持。
- 歌唱ピアノロールは休符で区切るフレーズ別音域で高さへfit。連続音/和音/持続音の相対音程を維持し、解析済み音域を配置/タイルで共有する。
- 本作業では無配備ビルドし、実作品/実共有設定を保護。終了時に別途Release/配備更新を検出して保持（HISTORY参照）。コミット/pushしていない。
  入口は.dproj、IDEの既存配備イベントを維持。無配備ビルドはDEVELOPMENT.mdの呼出時上書きを使う。

- 背景検証/不要生成物整理は完了。証拠はC:/Users/zan12/AppData/Local/Temp/SYNC_MusicStudio-background-20261011/、範囲・失敗履歴・回収量はHISTORY。
  旧Tests/Win64 EXEは整理済み、現行独立EXEは同証拠root/runroot/Tests/Win64。現在D空き約9GiB、外部Release/配備更新を保持。

- transport/PSD一覧画像の最終無音回帰・両DLL背景回帰は完了。最新証拠はC:/Users/zan12/AppData/Local/Temp/SYNC_MusicStudio-ui-thumbnails-20261011/、独立EXEは同root/runroot/Tests/Win64。
  実きりたんPNG・最終manifest・popupのフォーカス競合と隔離desktop実行の記録はHISTORY参照。Releaseは無配備。

- PSDサムネイルのreview P2修正済み。本体だけの欠損/復元監視と、70実体同時可視でも画像＋ジョブ予約64枠を検証。
  最新無配備Release/完全無音回帰/両DLL背景回帰・保護照合の証拠はC:/Users/zan12/AppData/Local/Temp/SYNC_MusicStudio-ui-review-20261011/。詳細はHISTORY。

- 表情一覧/クリップの合成サムネイル、選択表情クリップの左右端リサイズ、作品JSON内psd.transform配置を実装。
  歌唱PSDスロット選択で移動/四隅の縦横比維持拡縮、右クリック左右/上下反転。はみ出し可、灰色余白/トンボは編集画面のみ。
  Escape取消、Ctrl+Z/Ctrl+Y、保存再読込に対応。未設定/反転だけは従来配置。共有設定・原本とは独立。PSD間スナップは将来。
  今回版も未配備。無音回帰と両DLLの検証記録はHISTORY、証拠はC:/Users/zan12/AppData/Local/Temp/SYNC_MusicStudio-expressions-placement-20261011/。

- 歌唱PSDトラックへ演奏スロットを追加可能。小節クリック→左チェックで設定点/四角区間。既存ノートは旧ピアノロール、既存明示長/休符も保持。
  固定列、中央drag移動/右端drag長変更、grid snap/重複拒否、通常wheel zoom/空白drag pan、無音loop/pause/stopを追加。
  新点は次点/末尾まで、右端変更で明示長。画面内/作品Undoと取消に対応。再読込/読込取消はこの画面で非表示、内部取消を維持。
  基本/表情→演奏step→母音。休符復帰、別PSD拒否、保存/取消/UndoRedo、プレビュー/映像に対応。BPMは上部ボタン、既存テンポ点を保持。
  演奏は拍固定、音声/歌唱MIDIは秒固定。パターン長とclip長は別、暗黙loopなし。最新無音/両DLL記録はHISTORY。
  最新証拠root C:/Users/zan12/AppData/Local/Temp/SYNC_MusicStudio-layerstep-loop-20261012/。実PSDはTempコピーで試行、詳細はHISTORY。

- タイムラインは小節・拍、選択clipの左右端もグリッドへ吸着。小節右クリックで手動tempo点、0拍削除不可。
  テンポスロットのMIDI参照/snapshotを配置区間で曲全体へ合成し、手動Root.timingを独立保持。開始が新しいclip優先、同時は後のtrack/slot/clip。
  終了/移動/削除で下のclip/手動へ復帰。曲拍子は固定、MIDI途中拍子は未適用表示。詳細は仕様29/設計/HISTORY。
  同証拠root/artifactsに試行JSON/96・内部144DPI画像、OpenSilentDemo/OpenSilentTempoDemo.ps1で確認可能。
  review P2 4件も修正・最終全無音/両DLL成功。配備先の外部更新を検出して保持、詳細と最新hashはHISTORY。今回からの配備なし。

## 継続条件・次の作業

- 再生/停止を同幅、右にカーソル区間BPM欄。Enter/離脱で確定、Esc取消、入力中は追従上書きなし。
  clip中は配置固有補正、手動点は小節アンカー。音声/歌唱は秒固定。途中拍子はJSON/表示対応、表GUIは未対応。
  604800秒素材の100万拍超変換とBPM1～999.99、UI復元失敗の原子性も修正・検証済み。
  最新無配備/全無音/両DLL証拠はC:/Users/zan12/AppData/Local/Temp/SYNC_MusicStudio-cursor-upper-20261012/。詳細はHISTORY。

- ユーザーの音声再開連絡まで再生/試聴/waveOut/音声decode/fixtureとTestEditorStage1全体は保留。ミュートで続行しない。
  無音検証はScripts/TestNoAudio.ps1。映像callbackはScripts/TestVideoOutput.ps1。独立EXEの--silent手順と隔離ライブラリはREADME.md。
- 背景非表示修正の証拠はC:/Users/zan12/AppData/Local/Temp/SYNC_MusicStudio-background-fix-20261011/。旧DLLで失敗再現、新DLLで成功。
  背景はユーザー実機成功確認済み。今回UI版のAviUtl2操作/aup2保存再読込、音声回帰、実モニター間DPIは別途確認。無断配備しない。
- D:/DelphiProg広域整理は20プロジェクトの再生成可能DCU 14,783件・約945MiBを削除して完了。MusicStudio/稼働中2件/保持指定Graph/用途不明の旧rootは保持。
  全52 rootの結果と削除前後の保持検証はC:/Users/zan12/AppData/Local/Temp/DelphiProg-cleanup-20261011/project-results.md、詳細はHISTORY。
- 歌唱PSDは行選択だけで表情をプレビュー。母音列は約2文字幅、複数割当は「通+」等・全文tooltip。右クリック割当、ホイール拡縮、左ドラッグ移動、全体表示/ダブルクリックfit。統合再生も合成中の完成画像保持とバッファ描画で空白を防ぐ。詳細検証はHISTORY。本作業からの配備なし。
- TestEditorStage1の旧スロット/一覧前提は更新済み。スクリプト/EXEは既定停止、TestAudioGateは停止入口だけを検証する。
  音声を含む全回帰は再開後に実行。現在はMIDI/JSON/GUIを分離した無音ホストを使う。
- 歌声生成、音符からの手足/ドラム動作の自動生成、途中拍子の専用GUIは未対応。
  母音onset/decayは将来作業。連続同母音も発音開始ごとに口中心の縮小で区切る方針を保持。
- PSD v1/RGB8/raw・RLE/通常・乗算/画像mask/通常グループmask。その他blend・clipping・マスク付きpass等は未対応理由を表示する。
  ドラムの命名規則はDRUM_PSD_NAMING.md。その他の楽器別必須名は保留。PSD試験素材名を必須名にしない。既存のドラム持ち方修正版採用確認も未了。
- 添付Library参考PNGは取得403でこの作業では未閲覧。実装/実画面証拠はTemp/EditorStage1/slot-library/。
- Dots取得/分類/20PSD・100姿勢/ドラム修正/部位分割の素材引継ぎはHISTORY.md末尾に原文を保持。

## 2026-10-22 ドラム操作UI（無配備）

- 演奏スロットの左＋→ドラムパターン。PSD未割当で作成・編集・保存可能。既存レイヤーstep/ノート編集は維持。
- 打点9行/スティック、表情・全体モーションのバー、無音transport、UndoRedo、メインプレビューへの位置/状態通知を追加。PSD関連付け・動作描画は未実装。
- 確認用はSamples/Debug/drum-pattern.json、再現手順は同README。検証の範囲・環境依存の未完了はHISTORY末尾。
- 現在の実作業rootはD:/DelphiProg/MyApp/SYNC_MusicStudio。旧root/zan12の証拠パスは過去記録として扱う。無配備手順はScripts/BuildLocal.ps1。
- 今回の専用DCU86件（約13.2MiB）と誤生成の空ディレクトリは削除操作が自動承認レビューで拒否され未整理。対象・理由はHISTORY末尾。

- ドラムUI追修正: 小節/分割コンボ（矢印を含む）をダーク表示、縦横scrollと拡大率欄を削除し全体をフォーム幅・高さへfit。再開時もこの仕様を維持。検証はHISTORY末尾。

## ドラムPSD命名規則と自動認識（2026-10-22）

- DRUM_PSD_NAMING.mdを正本とし、この規則のPSDがある前提で進める。未確定名は仮でよいというユーザー指定。
- PSD読込時に階層/動作段階/制御記号/固定キーを解析し、左右・H/HO/HC・共通姿勢・ベースの補完済み参照を生成。描画cloneは解析済みテーブルを複製。
- 仮名BASE/SD_BASE、CM_n、FX、ST/CR/RDは同mdの16節とDrumPsdRulesの定数へ集約。通常のドラムUIとPSD原本は変更しない。
- 現在は自動認識/内部参照と開発用JSON診断まで。次は既存9行の左右指示化、独立時間/ペダル保持/競合判定、表示切替とプレビュー接続。音声保留・無断配備なしを維持。
- ユーザー指定: DPI試験は以後不要。DPIを含む全体スイートを繰り返さず、変更箇所の専用ケースだけに絞る（DEVELOPMENT冒頭参照）。
