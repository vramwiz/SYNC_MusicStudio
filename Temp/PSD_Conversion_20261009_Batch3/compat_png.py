"""Create lossless decoder-compatibility copies; never edit source PNGs."""
import hashlib
import json
import shutil
import sys
from pathlib import Path
from PIL import Image

WORK=Path(__file__).resolve().parent
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d): p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
batch=read(WORK/'batch.json')
registry=WORK/'png-compatibility-copies.json'
copies=read(registry) if registry.exists() else {}
for item in batch:
    if item['instrument'] not in sys.argv[1:]: continue
    for source in [item['head_source']]+[p['source'] for p in item['poses']]:
        if source in copies: continue
        target=WORK/'compatible-inputs'/(hashlib.sha256(source.encode('utf-8')).hexdigest()[:20]+'.png')
        target.parent.mkdir(exist_ok=True)
        assert not target.exists()
        with Image.open(source) as im:
            assert im.mode=='RGBA'
            rgba=im.tobytes(); size=im.size
            im.save(target,format='PNG',compress_level=6)
        with Image.open(target) as im:
            assert im.mode=='RGBA' and im.size==size and im.tobytes()==rgba
        copies[source]=dict(source=source,source_sha256=sha(Path(source)),copy=str(target),
                            copy_sha256=sha(target),rgba_sha256=hashlib.sha256(rgba).hexdigest(),
                            canvas_wh=list(size),rgba_exact=True,
                            reason='Delphi PNG reader compatibility; original CRC and zlib scan passed. PNG encoding only, no pixel changes.')
for item in batch:
    config_path=Path(item['config'])
    config=read(config_path)
    used=[]
    for layer in config['layers']:
        original=layer.get('file')
        if original in copies:
            layer['file']=copies[original]['copy']
            used.append(copies[original])
        elif original:
            used.extend(c for c in copies.values() if c['copy']==original)
    if used:
        before=config_path.with_name(config_path.stem+'-before-compatibility.json')
        if not before.exists(): shutil.copyfile(config_path,before)
        write(config_path,config)
        item['png_encoding_compatibility_copies']=used
before=WORK/'batch-before-compatibility.json'
if not before.exists(): shutil.copyfile(WORK/'batch.json',before)
write(WORK/'batch.json',batch)
write(registry,copies)
print(f'PNG compatibility copies verified: {len(copies)}, all source RGBA unchanged.')
