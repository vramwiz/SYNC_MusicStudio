"""Publish the grip revision and retain the original conversion records."""
import hashlib
import json
import shutil
import sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

sys.stdout.reconfigure(encoding='utf-8')
WORK=Path(__file__).resolve().parent
PROJECT=WORK.parent.parent
ROOT=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
RECORD=ROOT/'01_演奏素材/04_ドラム/PSD変換記録/基本握り修正_20261009'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):
    with p.open('x',encoding='utf-8') as f:json.dump(d,f,ensure_ascii=False,indent=2)

app=read(WORK/'application-verification.json')
pixels=read(WORK/'pixel-verification.json')
preview=read(WORK/'preview-verification.json')
assert app['passed'] and preview['passed'] and pixels['changed_pixels_outside_rectangle']==0
assert pixels['original_alpha_entirely_preserved']
assert sha(Path(app['output']))==app['sha256']
assert sha(Path(app['original_psd']))==app['original_sha256']
assert sha(WORK/'基本_スティック握り修正.png')==pixels['png_sha256']
RECORD.mkdir(exist_ok=False)
for name in ['基本_スティック握り修正.png','生成プロンプト.txt','pixel-verification.json',
             'preview-verification.json','application-verification.json','before-apply-document.json',
             'after-import-document.json','after-save-document.json']:
    shutil.copyfile(WORK/name,RECORD/name)
shutil.copyfile(WORK/'app-corrected-preview.png',RECORD/'基本_修正後プレビュー.png')
shutil.copyfile(Path(pixels['source']).parent.parent/'preview.png',RECORD/'基本_修正前プレビュー.png')
before=Image.open(WORK/'right-hand-before-detail.png').convert('RGB')
after=Image.open(WORK/'right-hand-final-detail.png').convert('RGB')
comparison=Image.new('RGB',(1600,725),'#dddddd')
comparison.paste(before,(0,45));comparison.paste(after,(800,45))
draw=ImageDraw.Draw(comparison);font=ImageFont.truetype('C:/Windows/Fonts/meiryo.ttc',24)
draw.text((16,8),'修正前',font=font,fill='#202020');draw.text((816,8),'修正後',font=font,fill='#202020')
comparison.save(RECORD/'握り比較.png')
report=(f"2026-10-09 ドラム基本姿勢のスティック握り修正\n\n"
        f"修正版PSD: {app['output']}\n"
        f"元PSD（保持）: {app['original_psd']}\n\n"
        "ユーザー指示: 基本でスティックが手の上に乗って掴んでいないため差し替え。\n"
        "画面右・スネア側の手だけを組み込みimage_genで修正。親指と曲げた指で軸を包む形に変更。\n"
        "生成画像全体は採用せず、元の首下一体レイヤーの握り周辺へ局所反映。\n"
        f"変更対象矩形LTRB: {pixels['edited_rectangle_ltrb']} / 外周4pxで元画素へ接続。\n"
        f"変更画素: {pixels['changed_pixels']} / 矩形外変更: 0 / 元のalphaは全画素完全一致。\n"
        "キャンバス1536×1024、原点(0,0)、名前・階層・不透明度・マスクを保持。\n"
        "画面左の上げた手、スティックの両端と方向、機材、衣装、脚、頭部は保持。\n"
        "基本レイヤーをreplace_layerし、select_partで基本だけを表示。\n"
        "他の6姿勢と頭部のRGBA・座標・属性を実アプリで照合。新規名save・再読込後も一致。\n"
        "保存PSDのアプリ出力プレビューも握り周辺以外のRGBAと全alphaが修正前に完全一致。\n"
        "処理中の表示切替で旧ジョブがstaleとなったため、反映直前に最新状態を再export。\n"
        "当時の未保存編集を含む現在状態へ適用し、元PSDのファイルハッシュ不変を確認。\n"
        "検証用exportのみcancel。取り込んだ修正を取り消す操作はしていない。\n"
        "ユーザーのアプリを閉じず、修正版の基本を表示。修正前のPSD・交換snapshotも保持。\n\n"
        "画像確認: 全身・手の拡大を確認。修正版で親指が軸の手前を回り、握りの遮蔽ができている。\n"
        "ユーザーの見た目確認・本採用判断は未了。専門的な奏法や新しい演奏差分を保証するものではない。\n"
        "実行プロンプト: 生成プロンプト.txt。再現・作業用資料: "+str(WORK)+"\n")
(RECORD/'作業報告.txt').write_text(report,encoding='utf-8-sig')
revision=dict(date='2026-10-09',instrument='drums',attribute='打撃',name_ja='ドラム_基本握り修正',
              original_psd=app['original_psd'],psd=app['output'],psd_sha256=app['sha256'],pose_count=7,
              corrected_pose='*基本',change_ja='画面右・スネア側のスティック握りのみ修正',
              other_six_pose_pixels_unchanged=True,original_psd_unchanged=True,record_directory=str(RECORD),
              user_visual_acceptance='pending')
write(RECORD/'修正目録.json',revision)
progress_path=ROOT/'PSD変換進捗.json'
progress=read(progress_path)
assert not any(x.get('name_ja')==revision['name_ja'] for x in progress.get('post_conversion_revisions',[]))
progress.setdefault('post_conversion_revisions',[]).append(revision)
progress_path.write_text(json.dumps(progress,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
note=PROJECT/'note.md';raw=note.read_bytes()
anchor='ユーザー指定条件（作成済みPSDを全てPSDフォルダーへ配置）を満たし、今回の変換作業は完了。進捗は同キャラ直下の`PSD変換進捗.json`。'
assert raw.count(anchor.encode('utf-8'))==1
ending='\r\n' if b'\r\n' in raw else '\n'
line='ドラム基本のスネア側握り修正版を`Characters/PSD/東北きりたん_打撃_ドラム_基本握り修正.psd`へ保存・アプリ反映。元PSDと他6姿勢を保持。見た目の採用確認は未了。'
note.write_bytes(raw.replace(anchor.encode('utf-8'),(anchor+ending+line).encode('utf-8')))
history=PROJECT/'HISTORY.md';raw=history.read_bytes();ending='\r\n' if b'\r\n' in raw else '\n'
addition='''

## 2026-10-09 ドラム基本のスティック握り修正

- 起動中AIArtToPSDへ現在のエンドポイントで接続。ユーザー指示により基本の画面右・スネア側の手を修正。
  組み込みimage_genで親指と指が軸を包む握りを作り、元の一体レイヤーへ局所反映。
- 修正対象89×80px内の6,742画素だけ変更。対象外のRGBAと全画素のalphaは元画像と一致。
  上げた手、頭、他6姿勢、機材・衣装・脚、寸法1536×1024・原点・層名・階層・属性を保持。
- 作業中の表示切替で最初のexportがstaleとなったため、適用直前に現在文書を再export。
  最新の未保存状態を保持して基本だけreplace_layer・排他選択。非対象層のRGBA・座標・属性を照合。
- 同じPSDフォルダーの`東北きりたん_打撃_ドラム_基本握り修正.psd`へ新規名save・再読込を確認。
  元PSDのハッシュは不変。保存後のアプリプレビューも握り周辺以外のRGBA・全alphaが修正前と一致。
  ユーザーのアプリを閉じず、修正版の基本を表示。検証用exportのcancelは修正を戻すものではない。
- 変換時の20PSD・100姿勢の集計は保持し、修正版をpost_conversion_revisionsとして追加。
  PNG側`04_ドラム/PSD変換記録/基本握り修正_20261009/`へ修正PNG、前後プレビュー、握り比較、生成指示、検証・報告を保存。
  再現用資料は`Temp/DrumGripFix_20261009/`。ユーザーの見た目確認・本採用判断は未了。
'''
assert '## 2026-10-09 ドラム基本のスティック握り修正'.encode('utf-8') not in raw
history.write_bytes(raw+addition.replace('\n',ending).encode('utf-8'))
write(WORK/'final-verification.json',dict(passed=True,output=app['output'],record_directory=str(RECORD),
      corrected_pixels=pixels['changed_pixels'],outside_pixels_unchanged=True,alpha_entirely_unchanged=True,
      other_six_poses_unchanged=True,original_psd_unchanged=True,user_visual_acceptance='pending'))
print(json.dumps({'passed':True,'psd':app['output'],'records':str(RECORD)},ensure_ascii=False))
