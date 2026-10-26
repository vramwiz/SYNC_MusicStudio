# SYNC_MusicStudio 作業ノート

作業root: D:/DelphiProg/MyApp/SYNC_MusicStudio。
製品はSYNC / 演奏スタジオ、プロジェクトはSYNC_MusicStudio_Filter。
仕様はaviutl2_music_performance_editor_spec.md、UIはTRACK_SLOT_UI.md、設計/手順はDESIGN.md・DEVELOPMENT.md。完了検証・過去note・素材引継ぎはHISTORY.md。

## 現在地（2026-10-26）

- 統合timelineの横/縦scrollbarを独自ダーク部品へ置換。親子の背景消去/上塗りを抑制し、clip移動中にbarを毎回再描画しない。capture中のcursorはWin32へも明示し、WM_SETCURSORで矢印へ戻る問題を修正。専用--dark-scroll/slot/compact、両構成成功、無配備。証拠: Temp/SYNC_MusicStudio-DarkScroll-20261026/。

- 歌唱clipは端を含む範囲内を一律移動cursorに統一し、端dragも長さを変えず全体移動。旧伸縮gripを除き、配置の正確な開始Xへ水色2px線を表示。専用--singing-gestures/compactと両構成成功、無配備。証拠: Temp/SYNC_MusicStudio-SingingGestures-20261026/。

- 歌唱参照にUST/VSQX3・4/MusicXML・XML・MXL/MSCX・MSCZを追加。SingingFormatsで音符/歌詞/tempoを共通秒データへ変換し、設定・歌詞帯・口パクへ接続。MID/MIDI/KARは既存reader。旧VSQ/USTXや詳細記譜には未対応あり（DESIGN参照）。専用formats/既存MIDI歌詞帯/stage成功、無配備。証拠: Temp/SYNC_MusicStudio-SingingFormats-20261026/。

- 統合タイムラインの歌唱本文は音程ロールから歌詞帯へ変更。音符の横位置/長さを保ち、同一Yで文字より少し高い帯に左寄せ表示。ひらがな/カタカナ等は元のLyric表記を使う。--lyric-timelineとcompact、両構成ビルド成功、無配備。証拠: Temp/SYNC_MusicStudio-LyricTimeline-20261026/。

- PSD割当設定はリスト右クリック中心へ整理。中段の割当/解除/確認/再読込/取消欄を非表示にし、同じ操作をmenuへ集約。行選択は確認母音より優先し、*排他/親枝を切替えて差分を試写する（設定JSONは不変）。専用--mouth-listとstage、両構成ビルド成功、無配備。証拠: Temp/SYNC_MusicStudio-MouthList-20261026/。

- 音声トラック列選択で音声一覧へ切替。音声中はPSD/演奏/歌唱タブ無効、WAV/MP3外部dropは作品内の音声参照登録へ振分。ダブルクリックのファイル設定/配置/Undoは既存経路を維持。専用--audio-libraryは既存WAVの参照のみで確認し、音声decode/再生なし。証拠: Temp/SYNC_MusicStudio-AudioLibrary-20261026/。

- トラック/スロットを別列に分離し、メニューとDel対象を明確化。挿入線付きdrag並替、手動＋/−、PSD画像/ファイル名caption。音声42固定、歌唱/演奏60、小型20。展開先頭行を見出し横へ詰めた。
- 歌唱は6母音の自動/手動設定で対応判定。PSD能力に応じて追加枠を制限。表情カスタムは全レイヤー表示snapshotを作品内へ保存し、歌唱と併用する。
- プレビューを上側へ移動。7680×4320/中心0,0、trackの原寸座標/倍率、4点拡縮/内部drag移動/反転。中dragで表示pan、wheel zoom。上trackほど前、4人制限廃止。
- 目/soloは編集表示だけで非表示の評価/合成を停止。最終映像は全track。フィルターX/Y/拡大率で出力位置/全体倍率を制御。X/Yは出力pixel。口は1/2→3/4→1で同母音も発音ごとに動く。
- 前回の共通演奏の番号/7色・部位別候補記憶・右クリック削除、パターン内Undoと閉じた編集全体の作品/正本Undoは維持。
- Debug/Releaseと実DLL SDK/Release Foundation、専用stage/slot/compact/psd-drop/gestures成功。無配備、実AviUtl2操作/aup2保存再読込は未確認。証拠: C:/Users/vramw/AppData/Local/Temp/SYNC_MusicStudio-StageEditor-20261026/。

## 継続条件

- ユーザーの再開連絡まで音声fixture/decode/再生/試聴/waveOutを停止。DPI変更/比較試験も不要。専用無音ケースだけを実行し、全体スイートを繰り返さない。
- 無配備ビルドはScripts/BuildLocal.ps1。IDE既定イベントには配備があるので直接呼出を避ける。無断配備/commit/pushをしない。
- 作品sample.aup2、共有設定、参照元ソース、継承UI、実素材とユーザー差分を保護。日本語pas/dprはBOM/CRLF、約1500行で責務分割。新unitはdpr/dproj両方へ登録。
- 旧DCU/空フォルダーは削除が自動承認レビューで拒否され残存。迂回しない。対象/経緯はHISTORY。今回の依存監査で不要sourceはなし。
- 実素材はD:/VoiceroidProj/PSD/VRAM/東北きりたん/楽器_調整後の同名本体。派生名PSD/新規登録を増やさない指定。原本/管理コピー更新は対象が承認された作業に限定する。
- 共有演奏の正本は固定属性別、歌唱は作品共有。原本PSD/共有基本設定と作品の保存/取消を分け、版競合を拒否する。
- 実時間映像は重い合成で125ms打撃の要求を飛び越す課題が残る。必要時にworker負荷/キャッシュを改善。従来計測とGIF時間修正の詳細はHISTORY。
- 歌声生成、ノートから手足動作の自動生成、途中拍子の専用GUIは未対応。PSD未対応blend等は既存診断を維持する。
