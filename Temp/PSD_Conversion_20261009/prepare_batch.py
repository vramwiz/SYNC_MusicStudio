"""Prepare the first four instruments without altering source image bytes."""
import hashlib
import json
from pathlib import Path
from PIL import Image

PSD_ROOT = Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD')

ROOT = Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
WORK = Path(__file__).resolve().parent
CATALOG = json.loads((ROOT / '分類目録.json').read_text(encoding='utf-8-sig'))
CORE = json.loads((ROOT / '00_ガイドと目録/01_演奏素材/manifest_core.json').read_text(encoding='utf-8-sig'))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_new(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

LABELS = {
    'keyboard': ['基本', '画面左手を中央へ', '画面右手を中央へ', '画面左手を外側へ',
                 '画面右手を外側へ', '両手を中央寄りへ', '両手を広めへ', '画面左手_大きい離鍵',
                 '画面右手_大きい離鍵', '両手待機_鍵盤直上', '両手を画面左寄り', '両手を画面右寄り',
                 '画面左手_小さい離鍵', '画面右手_小さい離鍵'],
    'guitar': ['基本_低フレット', 'ダウンストローク', 'アップストローク_中フレット', '待機_ミュート',
               'アップストローク_低フレット_要調整', '中間ストローク_中フレット',
               'ダウンストローク_中フレット', '高フレット_リード'],
    'bass': ['基本', '低フレット', '高フレット', 'ミュート', '待機_首境界要調整', 'ブリッジ寄り', '親指アクセント'],
    'drums': ['基本_左手上げとスネア', 'タム前の低い構えとスネア', '両タム', '左クラッシュとスネア',
              '右ハイハット_接触未成立', '左クラッシュ予備動作', '左手大振り_予備動作'],
}
ATTRIBUTES = {'keyboard': '鍵盤', 'guitar': '撥弦', 'bass': '撥弦', 'drums': '打撃'}

batch = []
for instrument in LABELS:
    inst = next(x for x in CATALOG['instruments'] if x['instrument'] == instrument)
    guide = next(x for x in CORE['instruments'] if x['instrument'] == instrument)
    poses = [x for x in CATALOG['poses'] if x['instrument'] == instrument and x['group'] == 'core']
    assert len(poses) == len(LABELS[instrument])
    folder = ROOT / inst['folder']
    final = PSD_ROOT / ('東北きりたん_' + ATTRIBUTES[instrument] + '_' + inst['name_ja'] + '.psd')
    if final.exists():
        raise FileExistsError(final)
    head = ROOT / inst['head_file']
    with Image.open(head) as im:
        size = im.size
    records = []
    def group(key, name, parent=''):
        records.append(dict(key=key, name=name, parent=parent, visible=True))
    group('character', 'キャラクター')
    group('head_group', '頭部', 'character')
    records.append(dict(key='head', name='固定頭（付属PNG）', parent='head_group', visible=True, file=str(head)))
    group('poses', '演奏姿勢', 'character')
    mapping = []
    for n, (pose, label) in enumerate(zip(poses, LABELS[instrument])):
        source = ROOT / pose['body_file']
        with Image.open(source) as im:
            assert im.size == size and im.mode == 'RGBA', source
            pixel_hash = hashlib.sha256(im.tobytes()).hexdigest()
        name = '*基本' if n == 0 else f'*演奏{n:02d}_{pose["pose_id"]}_{label}'
        key = f'pose_{n:02d}'
        records.append(dict(key=key, name=name, parent='poses', visible=n == 0, file=str(source)))
        mapping.append(dict(pose_id=pose['pose_id'], label_ja=label, source_label_ja=pose['label_ja'],
                            layer_name=name, layer_path='キャラクター/演奏姿勢/' + name, key=key,
                            source=str(source), source_sha256=digest(source), rgba_sha256=pixel_hash,
                            preview_file=f'プレビュー/{pose["pose_id"]}.png'))
    # The required instrument-identification hierarchy contains metadata only.
    # Raster gear stays inside each integrated pose to preserve contact/occlusion.
    group('instrument_metadata', '楽器名')
    group('attribute', ATTRIBUTES[instrument], 'instrument_metadata')
    group('formal_name', inst['name_ja'], 'attribute')
    config = dict(width=size[0], height=size[1], output=str(WORK / instrument),
                  layers=records, states=[dict(key=m['key'], id=m['pose_id']) for m in mapping])
    config_path = WORK / (instrument + '-config.json')
    write_new(config_path, config)
    item = dict(instrument=instrument, name_ja=inst['name_ja'], attribute=ATTRIBUTES[instrument],
                config=str(config_path), staging=str(WORK / instrument), destination=str(final),
                record_directory=str(folder / 'PSD変換記録'), canvas_wh=list(size), pose_count=len(poses),
                head_source=str(head), head_sha256=digest(head), poses=mapping, guide=guide,
                head_policy='supplied fixed head unchanged; vocal expression-layer migration pending',
                instrument_metadata_is_not_separate_raster=True,
                chair_and_equipment_integrated=instrument == 'drums')
    batch.append(item)

write_new(WORK / 'batch.json', batch)
sources = {item['head_source']:item['head_sha256'] for item in batch}
for item in batch:
    sources.update({p['source']:p['source_sha256'] for p in item['poses']})
vocal = Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD\東北きりたん_立ち絵.psd')
sources[str(vocal)] = digest(vocal)
write_new(WORK / 'source-hashes-before.json', sources)

# Delphi source encoding follows DEVELOPMENT.md.
pascal = WORK / 'BuildInstrumentPsd.dpr'
content = pascal.read_text(encoding='utf-8-sig').replace('\r\n', '\n')
pascal.write_bytes(content.replace('\n', '\r\n').encode('utf-8-sig'))
print('Prepared keyboard 14 / electric guitar 8 / bass 7 / drums 7. Sources unchanged.')
