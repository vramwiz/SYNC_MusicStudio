"""Update only the relevant note sentence and append completed verification."""
import json
from pathlib import Path

REPO=Path(r'D:\DelphiProg\SYNC_MusicStudio')
ROOT=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
progress=json.loads((ROOT/'PSD変換進捗.json').read_text(encoding='utf-8-sig'))
assert progress['completed_core_instruments']==4 and progress['completed_core_poses']==36

note=REPO/'note.md'
old='追加素材の動作・PSD化試験は未実施。まず付属の主要4楽器選定ガイドから確認する。'.encode('utf-8')
new=('追加PNGは主要4楽器36姿勢を一体差分PSD化済み。PSD・確認画像・対応表はPNG内の各楽器フォルダー。\n'
     '全体進捗は同キャラ直下の`PSD変換進捗.json`。次は05アコーディオン以降の15楽器61姿勢と通常配置マリンバ。\n'
     '付属固定頭を保持。ボーカルの個別頭部・表情レイヤー移植は未完了。部位分割は第二段階。\n'
     '再現用ソース・設定・検証は`Temp/PSD_Conversion_20261009/`。').encode('utf-8')
content=note.read_bytes()
if old not in content:
    raise ValueError('Current note sentence changed; preserve it and reconcile explicitly')
note.write_bytes(content.replace(old,new,1))

heading='## 2026-10-09 追加PNGの一体差分PSD化・第1バッチ'
history=REPO/'HISTORY.md'
existing=history.read_bytes()
if heading.encode('utf-8') in existing:
    raise ValueError('Existing completed history entry is preserved')
entry='''

## 2026-10-09 追加PNGの一体差分PSD化・第1バッチ

- `Instrument_PSD_Conversion_Instructions.md`に従い、主要4楽器の首下一体差分PSDを作成。
  キーボード14・エレキギター8・ベース7・ドラム7、計36姿勢。PNG配下の各楽器フォルダーへ保存した。
- AIArtToPSDのArtDocument / ArtPng / ArtPsd / ArtPartsを再利用する専用Win64ヘルパーを使用。
  ヘルパーはDelphi 37.0で警告0・エラー0。製品ソース・参照プロジェクトは変更していない。
- 全画像を元キャンバス・原点(0,0)・原寸で保持し、トリミング・再拡縮・生成・補完は行っていない。
  `キャラクター/頭部`と`キャラクター/演奏姿勢`を分離し、姿勢は同親`*`の排他群とした。
  固定識別階層`楽器名/演奏属性/楽器正式名`は画素を持たないメタデータ群。
  描画用楽器・接触する手足は一体差分内に保持。不要な楽器_前・楽器_後群は作っていない。
- 保存・再読込で全層のRGBA・座標・階層・表示状態が一致。保存PSDから全36状態を描画し、
  付属頭と該当首下の2層合成と完全一致。全プレビュー・全姿勢一覧を目視した。
- AIArtToPSD Release実アプリの専用インスタンスで全36姿勢を1枚ずつ排他選択。
  常に1姿勢だけON、全層画素・原点不変を確認。基本へ戻して新規名save・再読込を実施し、
  既定プレビューもネイティブ検証画像とRGBA完全一致。専用インスタンスだけを終了した。
- 元PNGと元ボーカルPSDのSHA-256は変更なし。各楽器の`PSD変換記録/`に透明プレビュー、
  元画像とPSDの対応、レイヤー構造、実アプリ・ネイティブ検証JSON、作業報告を保存。
  全体進捗はキャラ直下の`PSD変換進捗.json`。再現用資料は`Temp/PSD_Conversion_20261009/`。
- 頭部は付属の合成済み固定頭。ボーカルの目・眉・口・髪の個別レイヤー移植は未完了。
  ドラムの人物・脚間スネア・イス・機材は一体のまま。個別固定化・シンバル独立可動は未実施。
  ギターDの袖差、ベースDの首穴、ドラムDの未接触など原素材の制約を注意名と報告に残した。
  PSD化を素材修復・演奏動作完成とは扱わず、分離可能性と中間素材の有無を楽器別に記録した。
- 残りはcore15楽器61姿勢と、通常配置マリンバ等の別枠素材。第2段階の部位分割、
  MusicStudio実登録、MIDI同期・時間制御、外部PSDホスト互換は未検証。
'''
history.write_bytes(existing+entry.replace('\n','\r\n').encode('utf-8'))
print('Updated concise continuation note and appended completed verification history.')
