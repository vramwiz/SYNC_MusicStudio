"""Prepare the remaining nine core instruments using unmodified source rasters."""
import hashlib
import json
import shutil
import sys
from pathlib import Path
from PIL import Image

sys.stdout.reconfigure(encoding='utf-8')
WORK=Path(__file__).resolve().parent
PREVIOUS=WORK.parent/'PSD_Conversion_20261009_Batch2'
ROOT=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
PSD=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD')

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_new(path,data):
    if path.exists():
        assert read(path)==data,('Different existing preparation record',path)
        return
    with path.open('x',encoding='utf-8') as f:
        json.dump(data,f,ensure_ascii=False,indent=2)

LABELS={
 'triangle':['基本_下辺接触・近接','ビーター上げ準備','ビーター下方離し','金属把持_ミュート待機'],
 'ukulele':['基本_音孔付近接触','下ストローク端','上ストローク接触_改稿B','ミュート待機'],
 'double_bass':['基本_右指接触','低め_右指接触','右指離し_準備','左押弦手_低位置'],
 'bongo':['基本_両掌接触','右手_画面左_上げ','左手_画面右_上げ','両手上げ待機'],
 'shamisen':['基本_撥接触','下げた撥','撥上げ_準備','胴端_待機'],
 'harp':['基本_弦側の両手','右手_高め','左手_低め','右手_響板保持待機'],
 'taiko':['基本_右上げ・左鼓面側','右鼓面側・左上げ','両撥上げ準備','両撥低位置_待機'],
 'steelpan':['基本_両マレット低位置','右手_画面左上げ・左手低打点候補','左手_画面右上げ・右手近接','両マレット上げ_待機'],
 'handbells':['基本_画面右高・左低','画面左高・右低','両手首_外向き傾斜','両腕下げ_待機'],
}
ATTRIBUTES={'triangle':'打撃','ukulele':'撥弦','double_bass':'撥弦','bongo':'打撃',
            'shamisen':'撥弦','harp':'撥弦','taiko':'打撃','steelpan':'打撃','handbells':'振奏'}
catalog_path=ROOT/'分類目録.json'
guide_path=ROOT/'00_ガイドと目録/01_演奏素材/manifest_core.json'
catalog=read(catalog_path)
core=read(guide_path)
batch=[]
sources={str(p):digest(p) for p in (catalog_path,guide_path)}
assert PSD.is_dir()
for inst in catalog['instruments'][10:]:
    instrument=inst['instrument']
    labels=LABELS[instrument]
    guide=next(x for x in core['instruments'] if x['instrument']==instrument)
    poses=[p for p in catalog['poses'] if p['group']=='core' and p['instrument']==instrument]
    assert len(poses)==len(labels)==4
    assert [p['pose_id'] for p in poses]==guide['display_order']
    folder=ROOT/inst['folder']
    destination=PSD/f'東北きりたん_{ATTRIBUTES[instrument]}_{inst["name_ja"]}.psd'
    assert not destination.exists(),destination
    assert not (folder/'PSD変換記録').exists()
    head=ROOT/inst['head_file']
    with Image.open(head) as im:
        assert im.mode=='RGBA'
        size=im.size
    assert list(size)==guide['canvas_wh']
    assert all(p['head_file']==inst['head_file'] and p['placement_xy']==[0,0] and p['canvas_wh']==list(size) for p in poses)
    layers=[]
    def group(key,name,parent=''):
        layers.append(dict(key=key,name=name,parent=parent,visible=True))
    group('character','キャラクター')
    group('head_group','頭部','character')
    layers.append(dict(key='head',name='固定頭（付属PNG）',parent='head_group',visible=True,file=str(head)))
    group('poses','演奏姿勢','character')
    mapping=[]
    for n,(pose,label) in enumerate(zip(poses,labels)):
        source=ROOT/pose['body_file']
        with Image.open(source) as im:
            assert im.mode=='RGBA' and im.size==size,source
            pixel_hash=hashlib.sha256(im.tobytes()).hexdigest()
        name='*基本' if n==0 else f'*演奏{n:02d}_{pose["pose_id"]}_{label}'
        key=f'pose_{n:02d}'
        layers.append(dict(key=key,name=name,parent='poses',visible=n==0,file=str(source)))
        mapping.append(dict(pose_id=pose['pose_id'],label_ja=label,source_label_ja=pose['label_ja'],
                            key=key,layer_name=name,layer_path='キャラクター/演奏姿勢/'+name,
                            source=str(source),source_sha256=digest(source),rgba_sha256=pixel_hash,
                            preview_file=f'プレビュー/{pose["pose_id"]}.png'))
        sources[str(source)]=digest(source)
    group('instrument_metadata','楽器名')
    group('attribute',ATTRIBUTES[instrument],'instrument_metadata')
    group('formal_name',inst['name_ja'],'attribute')
    config_path=WORK/(instrument+'-config.json')
    write_new(config_path,dict(width=size[0],height=size[1],output=str(WORK/instrument),layers=layers,
                               states=[dict(key=p['key'],id=p['pose_id']) for p in mapping]))
    batch.append(dict(instrument=instrument,source_group='core',name_ja=inst['name_ja'],attribute=ATTRIBUTES[instrument],
                      config=str(config_path),staging=str(WORK/instrument),destination=str(destination),
                      record_directory=str(folder/'PSD変換記録'),canvas_wh=list(size),pose_count=4,
                      head_source=str(head),head_sha256=digest(head),poses=mapping,guide=guide,
                      head_policy='supplied fixed head unchanged; vocal expression-layer migration pending',
                      instrument_metadata_is_not_separate_raster=True,
                      chair_and_equipment_integrated=instrument in ('shamisen','harp'),
                      attribute_reason_ja=('提供素材はピチカート4姿勢のため撥弦。弓奏は未収録。' if instrument=='double_bass' else
                                           '腕・手首を振る姿勢のため振奏。製品の必須分類を確定するものではない。' if instrument=='handbells' else
                                           '提供された演奏方法に基づく素材整理用属性。')))
    sources[str(head)]=digest(head)
progress_path=ROOT/'PSD変換進捗.json'
prior=read(progress_path)
assert prior['completed_core_instruments']==10 and prior['completed_core_poses']==61
assert 'batch_3' not in prior
existing_versions=[]
for existing in prior['batch_1']+prior['batch_2']:
    path=Path(existing['psd'])
    current_hash=digest(path)
    sources[str(path)]=current_hash
    existing_versions.append(dict(instrument=existing['instrument'],psd=str(path),
                                  created_version_sha256=existing['psd_sha256'],
                                  before_batch3_sha256=current_hash,
                                  changed_since_created=current_hash!=existing['psd_sha256'],
                                  policy='Preserve the current file; previous verification applies to the created version.'))
vocal=PSD/'東北きりたん_立ち絵.psd'
sources[str(vocal)]=digest(vocal)
shutil.copyfile(progress_path,WORK/'progress-before.json')
write_new(WORK/'batch.json',batch)
write_new(WORK/'source-hashes-before.json',sources)
write_new(WORK/'preexisting-output-versions.json',existing_versions)
for name in ('VerifyAndSave.ps1','CleanupVerifiedExchange.ps1','BuildInstrumentPsd.dpr'):
    target=WORK/name
    assert not target.exists()
    shutil.copyfile(PREVIOUS/name,target)
(WORK/'build').mkdir()
shutil.copyfile(PREVIOUS/'build/BuildInstrumentPsd.exe',WORK/'build/BuildInstrumentPsd.exe')
write_new(WORK/'reused-tools.json',{name:digest(WORK/name) for name in
          ['VerifyAndSave.ps1','CleanupVerifiedExchange.ps1','BuildInstrumentPsd.dpr','build/BuildInstrumentPsd.exe']})
print('Prepared 9 remaining core instruments / 36 poses; PSD directory and names follow user instruction.')
