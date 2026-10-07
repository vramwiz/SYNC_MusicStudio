# 演奏スタジオ 現在の設計

製品全体の仕様は`aviutl2_music_performance_editor_spec.md`を正本とする。
この文書は初期化・設定管理として実装済みの範囲だけを扱う。

## Filterと設定

- `FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER`で単体配置できるFilterとして登録する。
- グループはSYNC、名前は演奏スタジオ。項目は設定ボタンとJSONデータ文字列のみ。
- 設定画面は参照元同期編集フォームの複製を整理したもの。原本のUIは移植用に保持する。
- 設定JSONを検証して開いた時点のオブジェクトへUTF-8で反映する。
- 適用成功時だけ閉じる。タイトルバーの閉じる操作も適用する。キャンセル時は反映しない。
- 映像処理は元映像を維持する。音声処理、毎フレームのファイル読込・JSON解析は行わない。

## 暫定JSON文書

```json
{
  "schemaVersion": 1,
  "previewAudio": null,
  "materials": [],
  "characters": [],
  "tracks": []
}
```

previewAudioはnullまたは次の1件のファイル参照を持つ。

```json
{
  "filePath": "D:\\Music\\song.wav",
  "displayName": "プレビュー音源"
}
```

materials、characters、tracksの要素とスロット・クリップの詳細スキーマは次段階で確定する。
将来のフィールドを失わないよう、現時点では未知のフィールドもそのまま保持する。
schemaVersion以外のキーを並び順で解釈しない。単行化後32,767文字以内に制限し、
不正なJSON、未知のバージョン、不正なルート型は保存しない。

## 実装待ち

音楽素材登録、固定IDと参照整合性、WAV再生、MIDI解析、ドラムパターン、
キャラ登録、専用PSD描画、タイムライン、プレビュー上のキャラ編集は未実装。
楽器別PSDレイヤー名と必須構成、再生速度変更、ポーズスロットは保留のままにする。
