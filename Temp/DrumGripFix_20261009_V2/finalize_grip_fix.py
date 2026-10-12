"""Publish the second grip correction and update concise project records."""
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

WORK = Path(__file__).resolve().parent
PROJECT = WORK.parent.parent
ROOT = Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
RECORD = ROOT / '01_演奏素材/04_ドラム/PSD変換記録/基本握り修正_20261009_V2'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_new(path, data):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)

app = read(WORK / 'application-verification.json')
pixels = read(WORK / 'pixel-verification.json')
preview = read(WORK / 'preview-verification.json')
assert app['passed'] and preview['passed']
assert pixels['changed_pixels_outside_rectangle'] == 0
assert pixels['original_alpha_entirely_preserved']
assert sha(Path(app['output'])) == app['sha256']
assert sha(Path(app['original_psd'])) == app['original_sha256']
assert sha(WORK / '基本_スティック握り修正.png') == pixels['png_sha256']

RECORD.mkdir(exist_ok=False)
for name in ['基本_スティック握り修正.png', 'pixel-verification.json', 'preview-verification.json',
             'application-verification.json', 'before-apply-document.json',
             'after-import-document.json', 'after-save-document.json']:
    shutil.copyfile(WORK / name, RECORD / name)
shutil.copyfile(WORK / '生成プロンプト_拡大修正.txt', RECORD / '生成プロンプト.txt')
shutil.copyfile(WORK / 'app-corrected-preview.png', RECORD / '基本_修正後プレビュー.png')
shutil.copyfile(Path(preview['comparison_before']), RECORD / '基本_修正前プレビュー.png')
shutil.copyfile(WORK / 'right-hand-final-detail.png', RECORD / '修正後_手元拡大.png')

comparison = Image.new('RGB', (1600, 725), '#dddddd')
comparison.paste(Image.open(WORK / 'right-hand-before-detail.png').convert('RGB'), (0, 45))
comparison.paste(Image.open(WORK / 'right-hand-final-detail.png').convert('RGB'), (800, 45))
draw = ImageDraw.Draw(comparison)
font = ImageFont.truetype('C:/Windows/Fonts/meiryo.ttc', 24)
draw.text((16, 8), '前回の握り修正版', font=font, fill='#202020')
draw.text((816, 8), '指の形・滑らかさを再修正', font=font, fill='#202020')
comparison.save(RECORD / '握り比較.png')

revision = dict(date='2026-10-09', instrument='drums', attribute='打撃', name_ja='ドラム_基本握り修正_02',
                original_psd=app['original_psd'], psd=app['output'], psd_sha256=app['sha256'],
                pose_count=7, corrected_pose='*基本',
                change_ja='画面右・スネア側の指の分岐を解消し、細く滑らかな指へ再修正',
                other_six_pose_pixels_unchanged=True, original_psd_unchanged=True,
                record_directory=str(RECORD), user_visual_acceptance='pending')
write_new(RECORD / '修正目録.json', revision)
report = (
    '2026-10-09 ドラム基本の指の形・滑らかさの再修正\n\n'
    f"修正版PSD: {app['output']}\n前回PSD（保持）: {app['original_psd']}\n\n"
    'ユーザー指示: スティックを持つ指の1本が同じ根元から下へ分かれて見える。\n'
    '指がゴツゴツした男性の指に見えるので滑らかにする。\n'
    '組み込みimage_genで手元の拡大画像を修正。親指の下に垂れた余分な指形を除き、\n'
    '親指・軸の奥の人差し指・掌へ曲げた3本の指として整理。強い関節陰影を抑制。\n'
    '全身の初回生成案は修正が不足していたため採用せず、拡大修正の手元のみ採用。\n'
    '拡大出力1254×1254を元の256×256範囲へ縮小後、握り89×80px内へ局所反映。\n'
    f"変更画素 {pixels['changed_pixels']}、矩形外RGBA変更0、全alpha完全一致。\n"
    'スティック両端、反対側の手、頭部、衣装・機材・脚、他6姿勢を保持。\n'
    '1536×1024・原点・層名・階層・不透明度・マスクを保持。\n'
    '反映直前の現在文書を再exportし、基本の元RGBA一致を確認してreplace_layer・select_part。\n'
    '保存・再読込後も非対象層の画素・属性・座標が一致。前回PSDのファイルハッシュ不変。\n'
    '保存後アプリプレビューも前回の基本プレビューと握り矩形外RGBAおよび全alphaが一致。\n'
    'ユーザーのアプリは開いたまま、修正版PSDの基本だけを表示。見た目の採用判断は未了。\n'
    '実行した最終生成指示は生成プロンプト.txt。作業用資料: ' + str(WORK) + '\n'
)
(RECORD / '作業報告.txt').write_text(report, encoding='utf-8-sig')

progress_path = ROOT / 'PSD変換進捗.json'
progress = read(progress_path)
revisions = progress.setdefault('post_conversion_revisions', [])
assert not any(item.get('psd') == app['output'] for item in revisions)
previous = [item for item in revisions if item.get('psd') == app['original_psd']]
assert len(previous) == 1
previous[0]['user_visual_acceptance'] = 'revision_requested'
previous[0]['revision_requested_reason_ja'] = '指が同じ根元から分かれ下を向いて見える。ゴツゴツした指を滑らかにする。'
previous[0]['superseded_by_psd'] = app['output']
revisions.append(revision)
progress_path.write_text(json.dumps(progress, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

note = PROJECT / 'note.md'
raw = note.read_bytes()
old = 'ドラム基本のスネア側握り修正版を`Characters/PSD/東北きりたん_打撃_ドラム_基本握り修正.psd`へ保存・アプリ反映。元PSDと他6姿勢を保持。見た目の採用確認は未了。'
new = 'ドラム基本の指の形と滑らかさを再修正し、`Characters/PSD/東北きりたん_打撃_ドラム_基本握り修正_02.psd`へ保存・アプリ反映。元PSD・前版・他6姿勢を保持。見た目の採用確認は未了。'
assert raw.count(old.encode('utf-8')) == 1
note.write_bytes(raw.replace(old.encode('utf-8'), new.encode('utf-8')))

history = PROJECT / 'HISTORY.md'
raw = history.read_bytes()
ending = '\r\n' if b'\r\n' in raw else '\n'
addition = '''

## 2026-10-09 ドラム基本の指の形と滑らかさを再修正

- ユーザーより前回握りの指が同じ根元から下へ分岐して見え、ゴツゴツしているとの指摘。
  組み込みimage_genで手元を拡大して再修正。親指の下に垂れた指形を除き、指の曲線と陰影を滑らかにした。
- 採用した手元だけを元の基本レイヤーへ局所反映。89×80px内の6,776画素を変更し、
  矩形外RGBAと全alphaが一致。反対側の手・スティック両端・頭部・衣装・機材・脚を保持。
- 反映直前に現在文書を再exportして基本RGBA一致を照合。replace_layer・排他選択後、
  `Characters/PSD/東北きりたん_打撃_ドラム_基本握り修正_02.psd`へ新規名save・再読込。
  他6姿勢と頭部の画素、全層の境界・属性・階層を照合し、前回PSDのハッシュ不変も確認。
  保存後アプリプレビューも前回基本と握り矩形外RGBA・全alphaが一致。ユーザーのアプリは開いたまま。
- PNG側`04_ドラム/PSD変換記録/基本握り修正_20261009_V2/`へ修正PNG、比較、プレビュー、生成指示、検証記録を保存。
  進捗JSONに第2版を追加し、前版へ再修正要望を記録。20PSD・100姿勢の変換完了集計は維持。
  作業資料は`Temp/DrumGripFix_20261009_V2/`。ユーザーの見た目の採用判断は未了。
'''
assert addition.splitlines()[2].encode('utf-8') not in raw
history.write_bytes(raw + addition.replace('\n', ending).encode('utf-8'))

write_new(WORK / 'final-verification.json', dict(passed=True, output=app['output'],
          record_directory=str(RECORD), corrected_pixels=pixels['changed_pixels'],
          outside_pixels_unchanged=True, alpha_entirely_unchanged=True,
          other_six_poses_unchanged=True, previous_psd_unchanged=True, user_visual_acceptance='pending'))
print(json.dumps({'passed': True, 'psd': app['output'], 'records': str(RECORD)}, ensure_ascii=False))
