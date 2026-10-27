# SYNC_MusicStudio 作業ノート

root: D:/DelphiProg/MyApp/SYNC_MusicStudio。製品: SYNC / 演奏スタジオ、project: SYNC_MusicStudio_Filter。
仕様はaviutl2_music_performance_editor_spec.md、UIはTRACK_SLOT_UI.md、設計/手順はDESIGN.md・DEVELOPMENT.md。完了検証・過去note・素材引継ぎはHISTORY.md。

## 現在地（2026-10-28 整理）

- PSDごとの口サイズ設定（初期off）、歌唱/演奏/リズムanimationを実装。空白dragで配置、左clickで7種類、移動/両端/Undo。歌唱/演奏は元slotが必要、リズムは絶対拍で元slot不要。28高、短い紫見出し、追加はsubmenu。
- liveは完成frameを順に公開、停止/seek/映像は厳密時刻。実paperdollsのbounce10.10→1.39ms、worker18.25→5.20ms、実84＋合成2268ケース全画素一致。Debug性能logはTempのSYNC_MusicStudio-profile-<PID>.jsonl、Release無効。
- SettingsFormはメニュー構築を分離して1489行。Source/Testsの機能folderを維持。現行84unit、folder最大6unit。BuildLocal前のTestSourceLayoutで1500行/folder12unit・BOM/CRLF・目的コメント・dpr/dproj参照/dfm同居を検査。10/28無配備Debug/Release、Release Foundation、専用animation無音検証成功。
- 終了証拠: Temp/SYNC_MusicStudio-EndOfDay-20261026/。性能詳細はAnimationProfile、UI詳細はAnimationPolishのHISTORY記録。

## 継続条件

- 音声fixture/decode/再生/試聴/waveOutは再開指示まで停止。DPI試験不要。専用無音ケースのみ。popupを残さず、timeout/例外時もテスト所有processの終了を確認。
- ビルドはScripts/BuildLocal.ps1の無配備上書き。IDE既定eventは配備あり。配備/commit/pushは次の指示に従う。
- sample.aup2のユーザー差分・共有設定・実PSD・継承UI・参照元を保護。新unitはdpr/dproj両登録。BOM/CRLF、約1500行で責務分割、form/dfm同居。
- 不要生成物はユーザーが手動削除する（10/28指定）。対象リンク提示済み: Temp、Tests/Win64、Win64/Debug/DCU、Win64/Release/DCU。こちらから削除を再試行しない。検証結果はHISTORYへ保持。
- 現作品はpaperdolls_kiritan_800px、共有ID b5867f43-455f-4a27-95b4-df0b25607cd0（D:/Users/take6/SYNC_MusicStudio/Libraries/PSDAssets）。素材更新は明示対象に限定する。旧素材指定はHISTORY。
- 歌声生成、音符からの手足自動生成、途中拍子の専用GUI、実AviUtl2/aup2保存再読込は別途。重いPSDで短い打撃要求を飛び越す課題は既存HISTORYと区別する。
