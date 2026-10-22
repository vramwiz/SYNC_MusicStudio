# 仮想JSONで編集画面をデバッグする

実データを必要としない構造確認用のサンプル。音源・MIDI・PSDは埋め込まず、
存在しない`__SYNC_DEBUG_MISSING__`配下を参照する。実ファイルは作成・変更しない。

`Scripts/TestEditorStage1.ps1`で独立確認用EXEを生成した後、作業フォルダーから実行する。

```powershell
& .\Tests\Win64\SYNC_MusicStudio_EditorPreview.exe .\Samples\Debug\generic-slots.json
```

EXEの「サンプルJSON…」から選ぶか、通常の「JSON読込」でも同じファイルを開ける。
ビルド出力/独立EXEからはサンプルフォルダーを候補表示する。配備先にサンプルがない場合は手動選択する。
元のサンプルを残すには「JSON保存」で別名へ保存する。

- `generic-slots.json`: 音声A/Bの独立枠、ギター奏者の演奏予約・歌唱/口パク・感情予約・リズム予約、汎用受入枠。
  トラックをクリックすると、そのトラックだけスロットを展開する。
  左の歌唱パターンを「口パク / 歌唱」へ置ける。「演奏（予約）」には拒否理由が出る。
  汎用枠は音声/歌唱の両方を受け入れ、トラックの種類で歌唱を固定しない。
- `legacy-tracks.json`: 旧トラック直下clipsの移行確認。配置IDと拡張フィールドを保持して既定スロットへ移す。
  保存後は`arrangementVersion: 2`、`slots`、配置の`slotId`を持つ。
- `unsupported-version.json`: 未対応arrangementVersionを明確に拒否する確認用。現在の編集文書は失わない。

スロット行の右クリックで設定・順番変更・削除を試す。名前/色はパターン・トラックと同じ共通枠。
受入属性を外す際、その属性を使う配置が残っていれば変更を拒否する。
スロット削除では、その枠の配置だけを消す。他のスロット・元パターン・素材ファイルは保持する。

欠損参照は属性設定を開くと表示する。WAVの波形、MIDIの音符、PSDの画像を仮造しない。
サンプルの長さ・配置・演奏予約パターンは仮想メタデータ。実デコードした音声・演奏結果ではない。
演奏/感情/リズムの属性編集、口形・楽器演奏アニメーション、AviUtl2映像への描画は未実装。

## 試聴と編集プレビュー

音声パターンへ実WAV/MP3を選び、トラックの受入スロットへ配置して「再生」を押す。
「一時停止」は現在位置を保持、「停止」は0秒へ戻る。下のシークバーまたは時間目盛のクリックで移動する。
配置開始・長さ・音量を反映し、重なった音声を合成する。JSON切替・変更・閉じる時は旧再生を止める。
欠損音源は理由を表示して無音扱い。仮想JSONの欠損音源を再生成功として扱わない。

PSDトラックの参照を設定すると、保存済みの合成画像を静止表示する。RGB 8bit PSD v1、raw/RLE、8M画素まで。
レイヤー差分や口形は動かない。歌唱は選択したMIDIトラックの歌詞/音高を現在の配置時刻に合わせて表示し、歌声は生成しない。
最大32音声配置、PSD/MIDI読込は先頭4件ずつ。音声試聴の簡易レート変換/先頭2ch表示は最終レンダリングとは別。

検証スクリプト実行後、生成された合成素材のデモを次で開ける（実作品の素材を使用しない）。

```powershell
& .\Tests\Win64\SYNC_MusicStudio_EditorPreview.exe .\Temp\EditorStage1\verification\preview-demo.json
```

デモは短い合成音声、青い合成PSD画像、MIDI歌詞の同期確認用。実人物PSDの読取確認画像とは区別する。
`preview-playing.png`は出力中の実フォーム、`preview-existing-psd.png`は既存PSDを読取のみで表示した確認画像。

検証ログ、編集後JSON、通常/最小サイズの実フォームPNGは`Temp/EditorStage1/verification/`に生成する。
`generic-slots-loaded.png`は読込直後、`generic-slots.png`は編集/並替え後。
`slot-settings.png`、`generic-slot-scrolled.png`、`sample-missing-audio.png`等も参照。

## ドラムパターン操作UI（PSD不要・無音）

`drum-pattern.json`は打点3件（未判定/正常/異常の表示例）と表情/全体モーションのバーを持つ。
演奏スロットを選択し、左一覧の「ドラムパターン（操作UIサンプル）」をダブルクリックする。
新規作成は演奏スロットの左＋→「ドラムパターン」。PSDの割当は不要。

```powershell
& .\Tests\Win64\SYNC_MusicStudio_EditorPreview.exe --silent .\Samples\Debug\drum-pattern.json --library-root "$env:TEMP\SYNC_MusicStudio-drum-demo\PSDAssets"
```

打点クリックでON/OFF。下2行は空白dragでバー追加、バーclickで種類、中央dragで移動、両端dragで伸縮、Deleteで削除。
Ctrl+Z/Y、時間軸clickでシーク、再生/一時停止/停止に対応し、全体をフォーム幅・高さに自動fitする（スクロールバー/拡大率欄なし）。実音声、PSD演奏、エフェクト描画は行わない。
再現テストはNoAudioTestsの`<Temp証拠先> --drums`。関連する既存合成素材回帰は`--drum-regression`。
無配備ビルドは`Scripts/BuildLocal.ps1`。IDEの既存配備イベントは維持する。