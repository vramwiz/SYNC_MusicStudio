"""Final artifact/source verification and concise continuation notes."""
import hashlib
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')
WORK=Path(__file__).resolve().parent
PROJECT=WORK.parent.parent
ROOT=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):
    with p.open('x',encoding='utf-8') as f: json.dump(d,f,ensure_ascii=False,indent=2)

batch=read(WORK/'batch.json')
progress=read(ROOT/'PSD変換進捗.json')
prior=read(WORK/'progress-before.json')
assert progress['completed_core_instruments']==19 and progress['completed_core_poses']==97
assert progress['remaining_core_instruments']==progress['remaining_core_poses']==0
assert progress['total_verified_psds']==20 and progress['total_verified_poses']==100
assert all(progress[k]==prior[k] for k in ('batch_1','batch_2'))
sources=read(WORK/'source-hashes-before.json')
for name,expected in sources.items(): assert sha(Path(name))==expected,name
outputs=[]
for item in batch:
    psd=Path(item['destination']); app=read(Path(item['staging'])/'app-verification.json')
    with psd.open('rb') as f: assert f.read(6)==b'8BPS\x00\x01'
    assert sha(psd)==app['file_sha256'] and app['passed'] and app['selected_pose_count']==4
    record=Path(item['record_directory'])
    for name in ['作業報告.txt','元画像とPSDの対応.json','レイヤー構造.txt','全姿勢一覧.jpg','首境界_白黒背景.jpg',
                 'native-verification.json','app-verification.json','app-document-after.json']:
        assert (record/name).is_file(),record/name
    assert len(list((record/'プレビュー').glob('*.png')))==4
    assert read(record/'元画像とPSDの対応.json')['destination']==str(psd)
    outputs.append(dict(instrument=item['instrument'],psd=str(psd),poses=4,sha256=sha(psd)))
assert len(outputs)==9
cleanup=read(WORK/'exchange-cleanup.json')
assert cleanup['source_and_final_assets_preserved'] and cleanup['verified_jobs_cleaned']==45
visual=read(WORK/'visual-review.json')
assert visual['all_36_pose_previews_reviewed'] and visual['all_36_neck_boundaries_reviewed_on_white_and_black']
copies=read(WORK/'png-compatibility-copies.json')
assert len(copies)==5 and all(c['rgba_exact'] for c in copies.values())

note=PROJECT/'note.md'
raw=note.read_bytes()
changes={
 '追加PNGはcore10楽器61姿勢＋通常配置マリンバ3姿勢を一体差分PSD化済み。':
 '追加PNGはcore19楽器97姿勢＋通常配置マリンバ3姿勢を一体差分PSD化済み（20PSD・100姿勢）。',
 '全体進捗は同キャラ直下の`PSD変換進捗.json`。次は11トライアングル以降の9楽器36姿勢。補修候補・任意頭・箏構図用は別枠。':
 '全体進捗は同キャラ直下の`PSD変換進捗.json`。coreの未変換はなし。補修候補・任意頭・箏構図用は別枠。',
 '再現用ソース・設定・検証は`Temp/PSD_Conversion_20261009/`と`Temp/PSD_Conversion_20261009_Batch2/`。':
 '再現用資料は`Temp/PSD_Conversion_20261009/`および`_Batch2/`・`_Batch3/`。既存キーボード・タンバリンPSDの作成後編集は保持し、進捗JSONで版を区別。',
}
write(WORK/'note-before-finalize.json',{'bytes_sha256':sha(note),'replacements':changes})
for old,new in changes.items():
    assert raw.count(old.encode('utf-8'))==1,old
    raw=raw.replace(old.encode('utf-8'),new.encode('utf-8'))
note.write_bytes(raw)
history=PROJECT/'HISTORY.md'
raw=history.read_bytes(); ending='\r\n' if b'\r\n' in raw else '\n'
mib=cleanup['reclaimed_bytes']/1024/1024
addition=f'''

## 2026-10-09 追加PNGの一体差分PSD化・第3バッチ

- 残りcore9楽器36姿勢（トライアングル、ウクレレ、コントラバス、ボンゴ、三味線、ハープ、和太鼓、スティールパン、ハンドベル）を追加。
  ユーザー指定の`Characters/PSD/`直下へ`東北きりたん_属性_楽器名.psd`で保存。
  コントラバスは素材のピチカートに基づく撥弦、ハンドベルは振る姿勢に基づく振奏として記録。
- AIArtToPSDの既存コードを用いる検証済み補助ツールを再利用。全36姿勢の元RGBA、原寸、原点(0,0)、階層、排他表示の保存・再読込一致を確認。
  ハープ1536×1024、和太鼓1152×1664と既存余白を維持。頭の二重変換、素材にない姿勢生成、機材やイスの無理な分離は実施せず。
- ボンゴPNGのDelphi読込でCRC例外。独立した全44入力のチャンクCRC・zlib展開は正常。
  ボンゴ頭・4本体の5PNGを作業用コピーへ再符号化し、原寸・全RGBA完全一致を確認。共通頭コピーはハンドベルでも使用。
  原PNGは変更なし。ネイティブPSDレイヤーと元PNGのRGBA SHA-256も一致。コピーの一覧とハッシュを対応JSONに保存。
- AIArtToPSD Release専用インスタンスで全36姿勢を排他選択し、全層画素・境界・階層を照合。
  基本へ戻して新規名save・再読込し、既定プレビューとネイティブ検証画像がRGBA完全一致。専用インスタンスのみ終了。
- 全身36枚と首境界の白黒背景36組を目視。原素材の首の細線・隙間、ハープB/Cの椅子脚、反射や静止機材の描画差等を記録。
  音高・運指・物理的接触・発音タイミング、音楽に合わせた高速切替の成立を保証するものではない。
- 各元PNG側の`PSD変換記録/`へ透過プレビュー、全姿勢一覧、首境界白黒一覧、対応表、層名一覧、作業報告、検証JSONを保存。
  batch_1・batch_2を保持して進捗へbatch_3を追加。core19楽器97姿勢が揃い、通常配置マリンバ込みで累計20PSD・100姿勢。
- 作業開始時に既存キーボード・タンバリンPSDが前回検証版から変更されていたため、その現状を保護し今回の出力対象から除外。
  前回作成時・今回開始時のSHA-256を区別し、以前の検証は以前の版に適用。現在版の全姿勢再検証は未実施。
  元PNG、ガイド、ボーカルPSD、既存11PSDの今回開始時からのハッシュ不変を確認。
- 保存・報告確定後、専用交換45ジョブのsnapshot/input/preview等だけを整理し約{mib:.1f} MiB回収。
  要求・結果・接続・cleanupメタデータを保持。最終PSDと報告・プレビューの存在を整理後に再照合。
- 残りは個別頭部・表情の移植と補修候補・任意頭・箏構図用等の別枠。第二段階の部位分割、MusicStudio登録、MIDI同期、外部PSDホスト互換は未完了。
  再現用資料は`Temp/PSD_Conversion_20261009_Batch3/`。本体プラグインとAIArtToPSDのソースは変更していない。
'''
assert '## 2026-10-09 追加PNGの一体差分PSD化・第3バッチ'.encode('utf-8') not in raw
history.write_bytes(raw+addition.replace('\n',ending).encode('utf-8'))
write(WORK/'final-verification.json',dict(passed=True,new_outputs=outputs,published_poses=36,
      source_files_unchanged=len(sources),total_psds=20,total_poses=100,
      remaining_core_instruments=0,remaining_core_poses=0,
      current_preexisting_versions_pending_verification=progress['current_version_verification_pending']))
print(json.dumps({'passed':True,'new_psds':9,'new_poses':36,'total_psds':20,'total_poses':100,
                  'remaining_core_instruments':0,'sources_and_previous_outputs_unchanged':len(sources)},ensure_ascii=False))
