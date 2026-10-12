"""Record and verify the user-requested PSD directory/name change."""
import hashlib
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')
PROJECT = Path(r'D:\DelphiProg\SYNC_MusicStudio')
CHARACTERS = Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters')
PNG = CHARACTERS / 'PNG' / '東北きりたん'
PSD = CHARACTERS / 'PSD'
WORK = Path(__file__).resolve().parent
PROGRESS = PNG / 'PSD変換進捗.json'
BATCHES = [PROJECT/'Temp/PSD_Conversion_20261009/batch.json',
           PROJECT/'Temp/PSD_Conversion_20261009_Batch2/batch.json']

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def backup(path):
    rel = str(path)
    key = hashlib.sha256(rel.encode('utf-8')).hexdigest()[:20]
    dest = WORK/'metadata-before'/key
    dest.parent.mkdir(exist_ok=True)
    if not dest.exists():
        dest.write_bytes(path.read_bytes())
    return {'path': rel, 'backup': str(dest), 'sha256': sha(dest)}

if sys.argv[1] == 'plan':
    assert not (WORK/'plan.json').exists(), 'Plan already exists'
    assert PSD.is_dir()
    progress = read(PROGRESS)
    entries = progress['batch_1']+progress['batch_2']
    batches = [(p, x) for p in BATCHES for x in read(p)]
    assert len(entries) == len(batches) == 11
    moves, protected = [], {}
    for entry in entries:
        batch_path, item = next((p, x) for p, x in batches if x['instrument']==entry['instrument'])
        source = Path(entry['psd']).resolve(strict=True)
        assert source.is_relative_to(PNG.resolve()) and not source.is_symlink()
        assert source == Path(item['destination']).resolve()
        assert sha(source) == entry['psd_sha256']
        filename = f'東北きりたん_{item["attribute"]}_{entry["name_ja"]}.psd'
        destination = PSD / filename
        assert destination.parent.resolve() == PSD.resolve() and not destination.exists()
        moves.append(dict(instrument=entry['instrument'], character='東北きりたん',
                          attribute=item['attribute'], name_ja=entry['name_ja'],
                          source=str(source), destination=str(destination), sha256=entry['psd_sha256'],
                          record_directory=entry['record_directory'], batch_file=str(batch_path)))
        paths = [item['head_source']]+[p['source'] for p in item['poses']]
        paths += [p['supplied_composite'] for p in item['poses'] if p.get('supplied_composite')]
        for path in paths:
            protected[path] = sha(Path(path))
    vocal = PSD/'東北きりたん_立ち絵.psd'
    protected[str(vocal)] = sha(vocal)
    assert len({m['destination'] for m in moves}) == 11
    write(WORK/'plan.json', dict(date='2026-10-09', png_root=str(PNG), psd_root=str(PSD),
                               naming='人名_属性_楽器名.psd', moves=moves, protected_files=protected))
    print(json.dumps({'planned':len(moves), 'protected_files':len(protected),
                      'filenames':[Path(m['destination']).name for m in moves]},ensure_ascii=False))
    sys.exit()

assert sys.argv[1] == 'finish'
assert not (WORK/'verification.json').exists(), 'Already finalized'
plan = read(WORK/'plan.json')
moved = read(WORK/'move-result.json')
assert moved['passed'] and moved['count']==len(plan['moves'])==11
for item in plan['moves']:
    assert not Path(item['source']).exists()
    assert sha(Path(item['destination'])) == item['sha256']
for path, expected in plan['protected_files'].items():
    assert sha(Path(path)) == expected

backups = []
def edit_json(path, data):
    backups.append(backup(path))
    write(path, data)

progress = read(PROGRESS)
progress['psd_directory'] = str(PSD)
progress['psd_filename_format'] = plan['naming']
progress['location_change_record'] = str(WORK/'verification.json')
for item in plan['moves']:
    entry = next(e for e in progress['batch_1']+progress['batch_2'] if e['instrument']==item['instrument'])
    entry['psd'] = item['destination']
    entry['attribute'] = item['attribute']
    record = Path(item['record_directory'])
    mapping = read(record/'元画像とPSDの対応.json')
    mapping['previous_destination'] = item['source']
    mapping['destination'] = item['destination']
    mapping['filename_format'] = plan['naming']
    edit_json(record/'元画像とPSDの対応.json', mapping)
    report = record/'作業報告.txt'
    old = report.read_bytes()
    assert item['source'] in old.decode('utf-8-sig')
    backups.append(backup(report))
    report.write_bytes(old.replace(item['source'].encode('utf-8'), item['destination'].encode('utf-8')))
    relocation = dict(date=plan['date'], previous_psd=item['source'], current_psd=item['destination'],
                      sha256=item['sha256'], bytes_unchanged=True,
                      historical_verification='app-verification等は実行時の保存先を保持。現在の保存先は本記録と対応表を参照。')
    write(record/'PSD保存先変更.json', relocation)
edit_json(PROGRESS, progress)

for batch_path in BATCHES:
    batch = read(batch_path)
    for item in batch:
        move = next(m for m in plan['moves'] if m['instrument']==item['instrument'])
        item['previous_destination'] = move['source']
        item['destination'] = move['destination']
    edit_json(batch_path, batch)

# Keep future preparations consistent with the requested directory and names.
for path, old, new in [
    (BATCHES[0].parent/'prepare_batch.py',
     "final = folder / ('東北きりたん_' + inst['name_ja'] + '.psd')",
     "final = PSD_ROOT / ('東北きりたん_' + ATTRIBUTES[instrument] + '_' + inst['name_ja'] + '.psd')"),
    (BATCHES[1].parent/'prepare_batch2.py',
     "final=folder/('東北きりたん_'+name+'.psd')",
     "final=PSD_ROOT/('東北きりたん_'+ATTRIBUTES[instrument]+'_'+name+'.psd')")]:
    raw = path.read_bytes()
    assert raw.count(old.encode('utf-8'))==1
    backups.append(backup(path))
    ending = b'\r\n' if b'\r\n' in raw else b'\n'
    root_line = b"PSD_ROOT = Path(r'C:\\Users\\zan12\\Documents\\SYNC_MusicStudio\\Characters\\PSD')"
    marker = b'from PIL import Image'+ending
    assert raw.count(marker)==1
    raw = raw.replace(marker, marker+ending+root_line+ending)
    path.write_bytes(raw.replace(old.encode('utf-8'), new.encode('utf-8')))

guide = PROJECT/'Instrument_PSD_Conversion_Instructions.md'
raw = guide.read_bytes()
anchor = '- 元画像、生成したPSD、差分ごとのプレビュー、作業記録を楽器・キャラクター単位で整理してください。'.encode('utf-8')
assert raw.count(anchor)==1
backups.append(backup(guide))
ending = b'\r\n' if b'\r\n' in raw else b'\n'
rule = ('- 生成PSDはPNGと分けて `C:/Users/zan12/Documents/SYNC_MusicStudio/Characters/PSD/` 直下へ保存し、'
        'ファイル名を `人名_属性_楽器名.psd` とします。属性は演奏方法に基づく既存分類（鍵盤・撥弦・打撃・弓奏等）を使い、'
        'バリエーションは楽器名の後ろに保持します。例：`東北きりたん_鍵盤_キーボード.psd`。'
        '確認画像・対応表は元PNG側の各楽器フォルダーに保持し、PSDへの参照を更新します。').encode('utf-8')
guide.write_bytes(raw.replace(anchor, anchor+ending+rule))

note = PROJECT/'note.md'
raw = note.read_bytes()
old = '追加PNGはcore10楽器61姿勢＋通常配置マリンバ3姿勢を一体差分PSD化済み。PSD・確認画像・対応表は各楽器フォルダー。'
new = ('追加PNGはcore10楽器61姿勢＋通常配置マリンバ3姿勢を一体差分PSD化済み。'
       'PSDは`Characters/PSD/`直下へ`人名_属性_楽器名.psd`で保存。確認画像・対応表は元PNG側の各楽器フォルダー。')
assert raw.count(old.encode('utf-8'))==1
backups.append(backup(note))
note.write_bytes(raw.replace(old.encode('utf-8'),new.encode('utf-8')))

history = PROJECT/'HISTORY.md'
backups.append(backup(history))
raw = history.read_bytes()
ending = '\r\n' if b'\r\n' in raw else '\n'
addition = '''

## 2026-10-09 作成PSDの保存先・ファイル名統一

- ユーザー指定により、今回作成した11PSDをPNG側から`Characters/PSD/`直下へ移動。
  `東北きりたん_属性_楽器名.psd`に改名し、属性は既存の鍵盤・撥弦・打撃・弓奏を使用。
  マリンバの通常配置・非標準配置の区別を保持。既存の`東北きりたん_立ち絵.psd`は変更なし。
- 11PSDの移動前後のSHA-256一致、旧保存先の不存在、元PNG・既存立ち絵PSDのハッシュ不変を確認。
  PSDの画素・レイヤー内容は変更していない。累計11PSD・64姿勢と未完了要件は従来どおり。
- 進捗JSON、対応表、作業報告、バッチ設定と今後の準備スクリプトを新保存先へ更新。
  確認画像は元PNG側に保持。過去のアプリ検証ログは実行時のパスを残し、保存先変更記録を併置。
  制作指示書とnote.mdにも保存先・命名を明記。移動一覧・元メタデータは`Temp/PSD_Relocation_20261009/`。
'''
history.write_bytes(raw+addition.replace('\n',ending).encode('utf-8'))
write(WORK/'metadata-backups.json',backups)

for item in plan['moves']:
    assert sha(Path(item['destination']))==item['sha256'] and not Path(item['source']).exists()
    assert read(Path(item['record_directory'])/'元画像とPSDの対応.json')['destination']==item['destination']
for path, expected in plan['protected_files'].items():
    assert sha(Path(path))==expected
write(WORK/'verification.json',dict(passed=True,date=plan['date'],psd_count=11,
      filename_format=plan['naming'],psd_directory=str(PSD),psd_content_unchanged=True,
      protected_files_unchanged=len(plan['protected_files']), moves=plan['moves']))
print(json.dumps({'passed':True,'moved_psds':11,'psd_content_unchanged':True,
                  'protected_files_unchanged':len(plan['protected_files'])},ensure_ascii=False))
