"""Package the AI-generated hand correction without changing other source pixels."""
import hashlib
import json
from pathlib import Path
from PIL import Image

WORK=Path(__file__).resolve().parent
SOURCE=Path(r'D:\DelphiProg\AIArtToPSD\Exchange\{E7D3A536-9A38-4D0A-8462-453431B62210}\input\source-2.png')
original=Image.open(SOURCE).convert('RGBA')
generated=Image.open(WORK/'generated-full.png').convert('RGBA')
assert original.size==generated.size==(1536,1024)
box=(944,407,1033,487)
# The visual correction comes from image_gen. Local packaging retains exact
# source RGBA outside this small rectangle, including all background alpha.
mask=Image.new('L',(box[2]-box[0],box[3]-box[1]))
mask.putdata([round(255*min(1,(min(x+1,y+1,box[2]-box[0]-x,box[3]-box[1]-y)-1)/4))
              for y in range(mask.height) for x in range(mask.width)])
local=Image.composite(generated.crop(box),original.crop(box),mask)
final=original.copy()
final.paste(local,box[:2])
final.putalpha(original.getchannel('A'))
output=WORK/'基本_スティック握り修正.png'
if output.exists():
    previous=json.loads((WORK/'pixel-verification.json').read_text(encoding='utf-8'))
    assert hashlib.sha256(output.read_bytes()).hexdigest()==previous['png_sha256']
final.save(output)
a,b=original.tobytes(),final.tobytes()
changed=outside=0
for y in range(original.height):
    for x in range(original.width):
        i=(y*original.width+x)*4
        if a[i:i+4]!=b[i:i+4]:
            changed+=1
            outside+=not(box[0]<=x<box[2] and box[1]<=y<box[3])
assert changed>0 and outside==0
with Image.open(output) as check: assert check.convert('RGBA').tobytes()==b
record=dict(source=str(SOURCE),generated=str(WORK/'generated-full.png'),output=str(output),
            size=list(final.size),edited_rectangle_ltrb=list(box),edge_transition_pixels=4,
            changed_pixels=changed,changed_pixels_outside_rectangle=outside,
            original_alpha_entirely_preserved=final.getchannel('A').tobytes()==original.getchannel('A').tobytes(),
            source_rgba_sha256=hashlib.sha256(a).hexdigest(),rgba_sha256=hashlib.sha256(b).hexdigest(),
            png_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
            artist='built-in image_gen; only generated grip region packaged into original source')
(WORK/'pixel-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
detail=final.crop((880,360,1080,530))
back=Image.new('RGBA',detail.size,'#dddddd');back.alpha_composite(detail)
back.convert('RGB').resize((800,680)).save(WORK/'right-hand-final-detail.png')
head=Image.open(r'D:\DelphiProg\AIArtToPSD\Exchange\{E7D3A536-9A38-4D0A-8462-453431B62210}\input\source-1.png').convert('RGBA')
preview=final.copy();preview.alpha_composite(head)
preview.save(WORK/'expected-basic-preview.png')
print(json.dumps({'changed_pixels':changed,'outside_rectangle':outside,'size':list(final.size)}))
