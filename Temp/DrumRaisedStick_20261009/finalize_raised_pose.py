"""Publish the raised-stick PSD variation and its verification records."""
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

W=Path(__file__).resolve().parent
PROJECT=W.parent.parent
ROOT=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
RECORD=ROOT/'01_演奏素材/04_ドラム/PSD変換記録/基本スティック上げ_20261009'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write_new(path,data):
    with path.open('x',encoding='utf-8') as f:json.dump(data,f,ensure_ascii=False,indent=2)

app=read(W/'application-verification.json')
pixels=read(W/'pixel-verification.json')
preview=read(W/'preview-verification.json')
assert app['passed'] and preview['passed'] and pixels['changed_pixels_outside_mask']==0
assert sha(Path(app['output']))==app['sha256']
assert sha(Path(app['original_psd']))==app['original_sha256']
assert sha(W/'基本_スティック上げ_非打撃.png')==pixels['png_sha256']

# Remove only the unused preview of whichever pose was visible during export.
unused=W/'source-visible-preview.png'
assert unused.resolve().parent==W.resolve()
cleanup=dict(path=str(unused),bytes=unused.stat().st_size,sha256=sha(unused),
             reason='Unused source export preview; accepted-basic and saved-raised native previews retained')
unused.unlink()
write_new(W/'cleanup.json',cleanup)

RECORD.mkdir(exist_ok=False)
for name in ['基本_スティック上げ_非打撃.png','生成プロンプト.txt','pixel-verification.json',
             'preview-verification.json','application-verification.json','before-apply-document.json',
             'after-import-document.json','after-save-document.json','applied-region-mask.png',
             'fixed-cymbal-protection-mask.png','cleanup.json']:
    shutil.copyfile(W/name,RECORD/name)
for source,dest in [('app-basic-preview.png','基本_握り修正版プレビュー.png'),
                    ('app-saved-preview.png','基本_スティック上げプレビュー.png'),
                    ('saved-detail-white.png','スティック上げ_手元拡大.png'),
                    ('saved-detail-dark.png','スティック上げ_手元拡大_暗背景.png')]:
    shutil.copyfile(W/source,RECORD/dest)
before=Image.open(W/'before-hand-detail.png').convert('RGB')
after=Image.open(W/'saved-detail-white.png').convert('RGB')
comparison=Image.new('RGB',(1740,915),'#dddddd')
comparison.paste(before,(0,45));comparison.paste(after,(870,45))
draw=ImageDraw.Draw(comparison);font=ImageFont.truetype('C:/Windows/Fonts/meiryo.ttc',24)
draw.text((16,8),'基本（握り修正02・確認済み）',font=font,fill='#202020')
draw.text((886,8),'追加：スティック上げ・非打撃',font=font,fill='#202020')
comparison.save(RECORD/'基本とスティック上げ比較.png')

revision=dict(date='2026-10-09',instrument='drums',attribute='打撃',name_ja='ドラム_基本スティック上げ',
    original_psd=app['original_psd'],psd=app['output'],psd_sha256=app['sha256'],pose_count=8,
    added_pose=app['added_pose'],added_pose_count=1,source_pose='*基本',
    change_ja='確認済みの基本からスネア側の手・スティックを持ち上げ、打面から離した新規差分を追加',
    all_existing_seven_pose_pixels_unchanged=True,original_psd_unchanged=True,
    record_directory=str(RECORD),user_visual_acceptance='pending')
write_new(RECORD/'差分追加目録.json',revision)
(RECORD/'作業報告.txt').write_text(
    '2026-10-09 ドラム基本のスティック上げ・非打撃差分を追加\n\n'
    f"PSD: {app['output']}\n元PSD（保持）: {app['original_psd']}\n\n"
    'ユーザーは前回の握り修正02を「うまくいった」と確認。その基本から、\n'
    'ドラムを叩いていない、スティックを上に移動させた差分を直接指定。\n'
    '今回の新規生成はこの明示指示に基づく。組み込みimage_genで手・棒・前腕・袖を修正。\n'
    'スネア側の手と棒を持ち上げ、先端と打面に明確な隙間を設けた。古い手・棒の跡を補完。\n'
    '小さく滑らかな指で棒を握る。頭部・反対の手・身体の大部分・機材を元の位置に保持。\n'
    '元の一体差分レイヤーの局所へ生成パッチを反映し、ハイハット表面・輪郭は元画素を再適用。\n'
    f"本体の変更画素 {pixels['changed_pixels']}、適用マスク外RGBA変更0。\n"
    '移動した棒・袖の新旧輪郭ではalphaを更新。マスク外alphaは元と完全一致。\n'
    '原寸1536×1024・原点(0,0)の首下一体差分として、演奏姿勢の直下へ追加。\n'
    '新レイヤー名: *基本_スティック上げ_非打撃。既存基本の直後へ配置。\n'
    '既存7姿勢・頭部は全RGBA、全層の境界・不透明度・マスク・名前・階層を保持。\n'
    '実アプリで新差分→基本→新差分の排他切替を確認後、新規名save・再読込。\n'
    '基本のアプリプレビューは確認済み握り修正02とRGBA完全一致。\n'
    '新差分の保存前後プレビューもRGBA完全一致。基本と新差分のマスク外RGBAも一致。\n'
    '白・暗背景、全身と手元を目視し、棒の浮き、握り、旧棒跡、首と腕、背景透過を確認。\n'
    '元PSDのファイルハッシュは不変。現在の未保存編集も保持した新規PSDで8姿勢・15層。\n'
    'ユーザーのアプリは開いたまま、新差分を表示して保存。新差分の採用判断は未了。\n'
    f"未使用の書出しプレビュー1枚（{cleanup['bytes']} bytes）を確認して整理。\n"
    '採用画像・生成原本・交換snapshot・検証記録は保持。\n'
    f'最終生成指示: 生成プロンプト.txt。再現資料: {W}\n',encoding='utf-8-sig')

progress_path=ROOT/'PSD変換進捗.json'
progress=read(progress_path)
revisions=progress.setdefault('post_conversion_revisions',[])
assert not any(item.get('psd')==app['output'] for item in revisions)
previous=[item for item in revisions if item.get('psd')==app['original_psd']]
assert len(previous)==1
previous[0]['user_visual_acceptance']='accepted'
previous[0]['user_acceptance_comment_ja']='うまくいった'
revisions.append(revision)
progress_path.write_text(json.dumps(progress,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
acceptance=Path(previous[0]['record_directory'])/'ユーザー確認_20261009.json'
write_new(acceptance,dict(date='2026-10-09',psd=app['original_psd'],
    user_visual_acceptance='accepted',comment_ja='うまくいった',next_request_ja='基本からスティック上げ・非打撃差分を追加'))

note=PROJECT/'note.md';raw=note.read_bytes()
old='ドラム基本の指の形と滑らかさを再修正し、`Characters/PSD/東北きりたん_打撃_ドラム_基本握り修正_02.psd`へ保存・アプリ反映。元PSD・前版・他6姿勢を保持。見た目の採用確認は未了。'
new='ドラム握り修正02はユーザー確認済み。基本のスティック上げ・非打撃差分を追加し、`Characters/PSD/東北きりたん_打撃_ドラム_基本スティック上げ.psd`へ保存・アプリ反映（8姿勢）。既存7姿勢を保持。新差分の採用確認は未了。'
assert raw.count(old.encode('utf-8'))==1
note.write_bytes(raw.replace(old.encode('utf-8'),new.encode('utf-8')))
history=PROJECT/'HISTORY.md';raw=history.read_bytes();ending='\r\n' if b'\r\n' in raw else '\n'
addition='''

## 2026-10-09 ドラム基本のスティック上げ・非打撃差分を追加

- 前回の握り修正02をユーザーが「うまくいった」と確認。続けて、同じ基本から棒を上に移動した非打撃差分を明示指定。
  組み込みimage_genでスネア側の手・棒・前腕・袖を持ち上げ、打面との隙間を設けた。旧手・棒の跡を補完。
- 採用した局所だけを基本画像へ反映し、ハイハット表面・輪郭は元画素を保持。
  本体41,996画素を変更。マスク外RGBA・alphaは一致。新旧の棒・袖の輪郭内ではalphaを更新。
  原寸1536×1024・原点(0,0)・首下一体差分のまま`演奏姿勢`直下へ`*基本_スティック上げ_非打撃`を追加。
- 反映直前に現在文書を再exportし、確認済み基本のRGBA一致を照合。既存7姿勢と頭部の画素、既存全層の名前・境界・属性・階層を保持。
  実アプリで新差分→基本→新差分を排他切替してから、新規名save・再読込。8姿勢・15層として保存。
- `Characters/PSD/東北きりたん_打撃_ドラム_基本スティック上げ.psd`へ保存。元PSDのファイルハッシュ不変。
  基本のアプリプレビューは握り修正02とRGBA完全一致、新差分も保存前後で完全一致。
  新旧プレビューの変更は適用マスク内だけ。全身、手元、白・暗背景で浮き・握り・旧棒跡・つながり・透過を目視。
- PNG側`04_ドラム/PSD変換記録/基本スティック上げ_20261009/`へ新PNG、比較・プレビュー、生成指示、検証・報告を保存。
  進捗JSONへ追加生成として記録し、元の20PSD・100姿勢の変換完了集計は維持。握り修正02のユーザー確認も記録。
  未使用の初期書出しプレビュー1枚を確認して削除。生成原本・採用画像・交換snapshot・検証記録は保持。
  作業資料は`Temp/DrumRaisedStick_20261009/`。ユーザーのアプリは開いたまま。新差分の見た目の採用判断は未了。
'''
assert addition.splitlines()[2].encode('utf-8') not in raw
history.write_bytes(raw+addition.replace('\n',ending).encode('utf-8'))
write_new(W/'final-verification.json',dict(passed=True,output=app['output'],record_directory=str(RECORD),
    existing_seven_poses_preserved=True,pose_count=8,layer_count=15,source_grip_accepted=True,
    basic_and_raised_switched_exclusively=True,original_psd_unchanged=True,user_visual_acceptance='pending'))
print(json.dumps({'passed':True,'psd':app['output'],'records':str(RECORD)},ensure_ascii=False))
