from pathlib import Path
import hashlib
import json
import shutil

work = Path(r'D:\DelphiProg\SYNC_MusicStudio\Temp\DrumMatchedGrip_20261009')
repo = Path(r'D:\DelphiProg\SYNC_MusicStudio')
character = Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
records = character / '01_演奏素材' / '04_ドラム' / 'PSD変換記録' / '持ち方修正_20261009'

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\r\n')

def update_document(path, transform):
    raw = path.read_bytes()
    bom = raw.startswith(b'\xef\xbb\xbf')
    body = raw[3:] if bom else raw
    text = body.decode('utf-8')
    result = transform(text)
    assert result != text, f'No document update: {path}'
    path.write_bytes((b'\xef\xbb\xbf' if bom else b'') + result.encode('utf-8'))

app = read_json(work / 'application-verification.json')
pixels = read_json(work / 'pixel-verification.json')
preview = read_json(work / 'preview-verification.json')
cleanup = read_json(work / 'cleanup-manifest.json')
assert app['passed'] and app['saved_and_reloaded'] and preview['passed']
assert app['pose_count'] == 8 and app['layer_count'] == 15
assert app['all_other_six_pose_and_head_pixels_unchanged']
assert app['existing_bounds_attributes_hierarchy_unchanged']
output = Path(app['output'])
assert output.read_bytes()[:4] == b'8BPS'
assert digest(output) == app['sha256'], 'Output changed since save verification'
assert digest(Path(app['original_psd'])) == app['original_sha256'], 'Original PSD changed'
for item in pixels:
    assert item['changed_pixels_outside_mask'] == 0
    assert digest(Path(item['output'])) == item['png_sha256']
assert preview['saved_basic_rgba_identical']
assert all(item['changed_pixels_outside_mask'] == 0 for item in preview['pose_previews'])

records.mkdir(parents=True, exist_ok=True)
files = [
    'basic-grip-fixed.png', 'raised-grip-fixed.png',
    'app-basic-preview.png', 'app-raised-preview.png', 'app-saved-basic-preview.png',
    'actual-basic-detail.png', 'actual-raised-detail.png',
    'actual-basic-detail-dark.png', 'actual-raised-detail-dark.png', '握り修正_2姿勢.png',
    'basic-applied-mask.png', 'raised-applied-mask.png',
    '生成プロンプト_基本.txt', '生成プロンプト_スティック上げ.txt',
    'user-grip-reference.png', 'user-reference-right-hand.png', 'user-reference-left-hand.png',
    'pixel-verification.json', 'preview-verification.json', 'application-verification.json',
    'before-apply-document.json', 'after-import-document.json', 'after-save-document.json',
    'cleanup-manifest.json', 'package_matched_grips.py', 'ApplyMatchedGrips.ps1',
]
published = []
for name in files:
    src, dst = work / name, records / name
    shutil.copy2(src, dst)
    assert digest(src) == digest(dst)
    published.append({'name': name, 'bytes': dst.stat().st_size, 'sha256': digest(dst)})

prompt_set = '生成方式: 組み込み image_gen（画像編集）\nユーザー提供の握り参考図と既存のキャラクター画像を参照。\n\n'
for name in ('生成プロンプト_基本.txt', '生成プロンプト_スティック上げ.txt'):
    prompt_set += name + '\n' + (work / name).read_text(encoding='utf-8-sig') + '\n\n'
(records / '生成指示一式.txt').write_text(prompt_set, encoding='utf-8', newline='\r\n')

report = f'''ドラム2姿勢の持ち方修正（2026-10-09）

保存PSD: {output}
SHA-256: {app['sha256']}

基本とスティック上げの2枚を、ユーザー提供の握り参考図に沿って修正。
基本は下打ち、上げた差分は長い先端を上へ向ける方針を明示して実施。
指・親指・手首の向きと棒の通り方を組み込みimage_genで描き直し、局所だけ反映。
上げた差分では根元の短い端を手首側に残し、打面との隙間を保持。
端点の完全固定を検証したものではなく、握りと手首の修正に合わせて局所の形を調整した。

基本38927画素、上げ37858画素を変更。適用マスク外RGBAの変更は0。
手・袖・棒の輪郭内では透過を更新。他6姿勢と頭部の画素は完全一致。
全層の名前・境界・属性・階層を保持し、15層・8姿勢で保存。
実アプリで2姿勢を排他切替し、保存・再読込を確認。基本プレビューは保存前後RGBA完全一致。
元PSDファイルのSHA-256不変を確認。適用直前の未保存状態も保持。
ユーザーのアプリへ反映済み。今回の見た目の採用判断は未了。

参考図追加前の不採用案はアプリへ未反映。不要な作業コピー{cleanup['file_count']}点、
{cleanup['total_bytes']} bytesを明示パスで削除。生成原本・元画像・参考図・生成指示・交換snapshotを保持。
元の変換完了集計20PSD・100姿勢は維持し、追加修正版として進捗へ記録。
再現資料: {work}
'''
(records / '作業報告.txt').write_text(report, encoding='utf-8', newline='\r\n')
manifest = {
    'date': '2026-10-09', 'status': 'saved_and_verified',
    'psd': str(output), 'psd_sha256': app['sha256'],
    'original_psd': app['original_psd'], 'original_sha256': app['original_sha256'],
    'pose_count': 8, 'layer_count': 15, 'corrected_poses': app['corrected_poses'],
    'user_visual_acceptance': 'pending', 'image_generation_mode': 'built-in image_gen',
    'generated_original_paths': [
        r'C:\Users\zan12\.codex\generated_images\01a11f61-6b79-7cb2-8b41-08a506f687c1\exec-abe91628-0e3f-4e8f-be3c-dbc0b8bc5981.png',
        r'C:\Users\zan12\.codex\generated_images\01a11f61-6b79-7cb2-8b41-08a506f687c1\exec-a898826e-afc5-4b51-911e-31e47deb7895.png',
    ],
    'files': published, 'work_directory': str(work),
}
assert all(Path(p).is_file() for p in manifest['generated_original_paths'])
write_json(records / '修正目録.json', manifest)

progress_path = character / 'PSD変換進捗.json'
progress = read_json(progress_path)
revisions = progress['post_conversion_revisions']
assert not any(r['psd'] == str(output) for r in revisions), 'Revision already recorded'
for revision in revisions:
    if revision['name_ja'] in ('ドラム_基本握り修正_02', 'ドラム_基本スティック上げ'):
        revision['previous_user_visual_acceptance'] = revision['user_visual_acceptance']
        revision['user_visual_acceptance'] = 'revision_requested'
        revision['revision_requested_reason_ja'] = '2枚ともスティックの根元を持たせる。追加参考図に沿って指・親指・手首の向きも修正。'
        revision['superseded_by_psd'] = str(output)
revisions.append({
    'date': '2026-10-09', 'instrument': 'drums', 'attribute': '打撃', 'name_ja': 'ドラム_持ち方修正',
    'original_psd': app['original_psd'], 'psd': str(output), 'psd_sha256': app['sha256'],
    'pose_count': 8, 'corrected_poses': app['corrected_poses'],
    'change_ja': '提供参考図に沿い、基本の下打ちとスティック上げの2姿勢で根元を握る指・親指・手首を修正。',
    'all_other_six_pose_and_head_pixels_unchanged': True,
    'original_psd_unchanged': True, 'record_directory': str(records), 'user_visual_acceptance': 'pending',
})
assert progress['total_verified_psds'] == 20 and progress['total_verified_poses'] == 100
write_json(progress_path, progress)

old_note = 'ドラム握り修正02はユーザー確認済み。基本のスティック上げ・非打撃差分を追加し、`Characters/PSD/東北きりたん_打撃_ドラム_基本スティック上げ.psd`へ保存・アプリ反映（8姿勢）。既存7姿勢を保持。新差分の採用確認は未了。'
new_note = 'ドラム基本とスティック上げの持ち方をユーザー参考図に沿って再修正し、`Characters/PSD/東北きりたん_打撃_ドラム_持ち方修正.psd`へ保存・アプリ反映（8姿勢）。他6姿勢を保持。修正版の採用確認は未了。'
update_document(repo / 'note.md', lambda text: text.replace(old_note, new_note))

history = f'''

## 2026-10-09 ドラム2姿勢の持ち方を参考図に沿って修正

- ユーザーから2枚とも棒の根元を握る指示と、握りの参考図を受領。
  参考図追加前の根元位置だけを変えた案は未反映のまま不採用とし、組み込みimage_genで指・親指・手首を再修正。
  基本は下打ち、上げた差分は長い先端を上へ向ける方針を明示して実施。
- 基本38927画素、上げ37858画素を局所変更。適用マスク外RGBAの変更は0。
  手・袖・棒の輪郭内ではalphaを更新。棒の端点の完全固定は要件とせず、握りに合わせて手首と形を調整。
  基本の打面側と、上げた差分の非接触の状態を目視確認。
- 適用直前の現在文書を再exportし、未保存状態を保持して2姿勢だけreplace_layer。
  他6姿勢と固定頭のRGBA、全層の名前・境界・属性・階層を保持。15層・8姿勢。
- 実アプリで基本→上げ→基本を排他切替し、`Characters/PSD/東北きりたん_打撃_ドラム_持ち方修正.psd`へ新規名save・再読込。
  保存前後の基本プレビューRGBA完全一致。変更は各マスク内だけ（基本28558、上げ28441画素）。白・暗背景で手元と旧棒跡を目視。
  元PSDのSHA-256不変を確認し、ユーザーのアプリは修正版を開いたまま保持。
- PNG側`04_ドラム/PSD変換記録/持ち方修正_20261009/`へ2姿勢PNG、実アプリ比較、参考図、生成指示、検証・報告を保存。
  進捗JSONに追加修正版を記録し、前版への握り再修正要望と、修正02が一度ユーザー確認済みだった履歴を保持。
  元の20PSD・100姿勢の変換完了集計は維持。今回の見た目の採用判断は未了。
- 未反映の不採用案の作業コピー{cleanup['file_count']}点（{cleanup['total_bytes']} bytes）を明示パスで整理。
  生成原本・採用画像・元画像・参考図・生成指示・交換snapshotは保持。削除一覧とSHA-256を記録。
  再現資料は`Temp/DrumMatchedGrip_20261009/`。プラグインとAIArtToPSDのソースは変更していない。
'''
def append_history(text):
    assert '## 2026-10-09 ドラム2姿勢の持ち方を参考図に沿って修正' not in text
    newline = '\r\n' if '\r\n' in text else '\n'
    return text.rstrip('\r\n') + history.replace('\n', newline)
update_document(repo / 'HISTORY.md', append_history)

final = {'passed': True, 'psd': str(output), 'sha256': digest(output),
         'record_directory': str(records), 'published_file_count': len(published),
         'progress_revision_count': len(revisions), 'original_psd_unchanged': True,
         'user_visual_acceptance': 'pending'}
write_json(work / 'final-verification.json', final)
write_json(records / 'final-verification.json', final)
print(json.dumps(final, ensure_ascii=False, indent=2))
