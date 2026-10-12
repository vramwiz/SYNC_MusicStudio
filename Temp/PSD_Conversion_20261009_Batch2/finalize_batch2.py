"""Audit delivered files after cleanup and record completed work."""
import hashlib
import json
from pathlib import Path

WORK=Path(__file__).resolve().parent
REPO=Path(r'D:\DelphiProg\SYNC_MusicStudio')
ROOT=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')

def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

batch=read(WORK/'batch.json')
progress=read(ROOT/'PSD変換進捗.json')
assert progress['completed_core_instruments']==10 and progress['completed_core_poses']==61
assert progress['total_verified_psds']==11 and progress['total_verified_poses']==64
sources=read(WORK/'source-hashes-before.json')
assert all(digest(Path(p))==h for p,h in sources.items())
summary=[]
for item in batch:
    final=Path(item['destination']); record=Path(item['record_directory'])
    verification=read(record/'app-verification.json')
    assert verification['passed'] and verification['selected_pose_count']==item['pose_count']
    assert digest(final)==verification['file_sha256']
    with final.open('rb') as f: assert f.read(4)==b'8BPS'
    assert len(list((record/'プレビュー').glob('*.png')))==item['pose_count']
    assert all((record/p).is_file() for p in ('全姿勢一覧.jpg','元画像とPSDの対応.json','レイヤー構造.txt','作業報告.txt'))
    summary.append(dict(instrument=item['instrument'],poses=item['pose_count'],psd_bytes=final.stat().st_size))

note=REPO/'note.md'
old1='追加PNGは主要4楽器36姿勢を一体差分PSD化済み。PSD・確認画像・対応表はPNG内の各楽器フォルダー。'
new1='追加PNGはcore10楽器61姿勢＋通常配置マリンバ3姿勢を一体差分PSD化済み。PSD・確認画像・対応表は各楽器フォルダー。'
old2='全体進捗は同キャラ直下の`PSD変換進捗.json`。次は05アコーディオン以降の15楽器61姿勢と通常配置マリンバ。'
new2='全体進捗は同キャラ直下の`PSD変換進捗.json`。次は11トライアングル以降の9楽器36姿勢。補修候補・任意頭・箏構図用は別枠。'
old3='再現用ソース・設定・検証は`Temp/PSD_Conversion_20261009/`。'
new3='再現用ソース・設定・検証は`Temp/PSD_Conversion_20261009/`と`Temp/PSD_Conversion_20261009_Batch2/`。'
content=note.read_bytes()
for old,new in ((old1,new1),(old2,new2),(old3,new3)):
    assert old.encode('utf-8') in content,'Current continuation note changed; preserve it'
    content=content.replace(old.encode('utf-8'),new.encode('utf-8'),1)
note.write_bytes(content)

cleanup=read(WORK/'exchange-cleanup.json')
heading='## 2026-10-09 追加PNGの一体差分PSD化・第2バッチ'
history=REPO/'HISTORY.md'
existing=history.read_bytes()
assert heading.encode('utf-8') not in existing
entry=f'''

{heading}

- アコーディオン5・タンバリン4・バイオリン3・アコースティックギター5・
  非標準配置マリンバ5・チェロ3のcore6楽器25姿勢と、通常配置マリンバ3姿勢をPSD化。
  計7点28姿勢をPNG配下の各楽器フォルダーへ保存した。前回4点のPSDと元素材は変更なし。
- 前回検証済みのAIArtToPSD実装を使うヘルパーと実アプリの既存パイプを再利用。
  製品ソースは変更せず、原寸・原点(0,0)・フルキャンバス・元RGBAを保持した。
  頭部は付属固定頭、演奏姿勢は同親*排他。楽器の固定識別階層も前回と同じ。
- 保存再読込後の全層RGBA・座標・階層・表示状態が一致。全28状態を保存PSDから描画し、
  指定頭と該当首下の2層合成と完全一致。7枚の全姿勢一覧で全提供姿勢を目視した。
- AIArtToPSD Releaseの専用インスタンスで全28姿勢を選択し、1姿勢だけON・画素不変を確認。
  基本へ戻して新規名save・再読込。各既定プレビューもネイティブ検証画像とRGBA完全一致。
  専用インスタンスのみ終了した。元PNG・ボーカルPSD・前回4PSDのハッシュも不変。
- 通常配置マリンバはcore97姿勢および非標準配置とは別PSD・別集計。
  付属固定頭合成済み3PNGとalpha完全一致。可視RGBと白黒背景表示の差は最大1/255の合成丸め。
  大きい生RGB差はalpha=0領域だけ。頭・首下の元レイヤーRGBAは不変で、測定値を対応JSONへ保存。
- 非標準配置マリンバの00/A黒窓群とB/C/D透明窓群の差をレイヤー名・報告へ記録。
  バイオリン上げ弓未成立、アコギ顎下の薄い隙間、チェロBの位置差等は原素材のまま。
  チェロのイス・脚・楽器も一体で保持。未提供の中間・待機等を生成せず、分離可能性を楽器別に記録。
- 各`PSD変換記録/`へ28枚の透過プレビュー、全姿勢一覧、対応表、層名一覧、作業報告、検証JSONを保存。
  進捗JSONはbatch_1を保持してbatch_2を追加。累計11PSD・64姿勢（core10楽器61＋別枠3）。
  再現用資料は`Temp/PSD_Conversion_20261009_Batch2/`。
- 保存・報告確定後、専用交換{cleanup['verified_jobs_cleaned']}ジョブの不要なsnapshot/input/preview等だけを整理し、
  約{cleanup['reclaimed_bytes']/1048576:,.1f} MiBを回収。要求・結果・接続・cleanupメタデータは保持。
  整理後も元ファイル、最終PSDハッシュ、確認画像と各報告の存在を再照合した。
- 残りは11トライアングル以降のcore9楽器36姿勢と、補修候補・任意頭・箏構図等の別枠。
  個別頭部・表情移植、第二段階部位分割、MusicStudio登録・MIDI同期・外部PSDホスト互換は未完了。
'''
with history.open('ab') as f: f.write(entry.replace('\n','\r\n').encode('utf-8'))
audit=dict(passed=True,new_outputs=summary,source_hashes_unchanged=len(sources),
           total_psds=11,total_poses=64,remaining_core_instruments=9,remaining_core_poses=36)
with (WORK/'final-verification.json').open('x',encoding='utf-8') as f:
    json.dump(audit,f,ensure_ascii=False,indent=2)
print(json.dumps(audit,ensure_ascii=True))
