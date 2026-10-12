"""Package the image_gen arm variation; preserve fixed pixels outside its mask."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

W = Path(__file__).resolve().parent
source = Image.open(W / 'source-basic.png').convert('RGBA')
generated = Image.open(W / 'generated-raised-crop.png').convert('RGBA')
assert source.size == (1536, 1024) and generated.width == generated.height
crop = generated.resize((320, 320), Image.Resampling.LANCZOS)
crop.putalpha(crop.getchannel('A').point(lambda v: round(v*254/255)))
placed = source.copy()
placed.paste(crop, (850, 270))
mask = Image.new('L', source.size, 0)
draw = ImageDraw.Draw(mask)
polygon = [(994,280),(1134,280),(1134,553),(1080,553),(1005,497),
           (953,478),(940,445),(941,394),(966,366),(985,326)]
draw.polygon(polygon, fill=255)
draw.line([(918,516),(1018,367)], fill=255, width=24)
for x, y in [(918,516),(1018,367)]:
    draw.ellipse((x-12,y-12,x+12,y+12), fill=255)
soft = mask.filter(ImageFilter.GaussianBlur(1.1))
soft = Image.composite(soft, Image.new('L',source.size,0), mask)
# The crop also contains the left edge of the fixed hi-hat. Keep its gold
# surface and adjacent outline/shadow from the source, rather than its redraw.
cymbal = Image.new('L',source.size,0)
for y in range(374,466):
    for x in range(1085,1148):
        r,g,b,a = source.getpixel((x,y))
        if a > 64 and r > 110 and g > 65 and b < r*.8 and g < r*1.1:
            cymbal.putpixel((x,y),255)
cymbal = cymbal.filter(ImageFilter.MaxFilter(9))
soft.paste(0,(0,0),cymbal)
final = Image.composite(placed,source,soft)
output = W / '基本_スティック上げ_非打撃.png'
if output.exists():
    previous=json.loads((W/'pixel-verification.json').read_text(encoding='utf-8'))
    assert hashlib.sha256(output.read_bytes()).hexdigest()==previous['png_sha256']
final.save(output)
soft.save(W/'applied-region-mask.png')
cymbal.save(W/'fixed-cymbal-protection-mask.png')
a,b,m,c=source.tobytes(),final.tobytes(),soft.tobytes(),cymbal.tobytes()
changed=outside=alpha_changes=0
for i,value in enumerate(m):
    if a[4*i:4*i+4]!=b[4*i:4*i+4]:
        changed+=1
        outside+=value==0
        assert c[i]==0
    if a[4*i+3]!=b[4*i+3]:
        alpha_changes+=1
        assert value>0
assert changed>0 and outside==0
record=dict(source=str(W/'source-basic.png'),generated=str(W/'generated-raised-crop.png'),
 output=str(output),size=list(source.size),context_rectangle_ltrb=[850,270,1170,590],edit_polygon=polygon,
 old_stick_erase_capsule={'endpoints':[[918,516],[1018,367]],'radius':12},
 changed_pixels=changed,changed_pixels_outside_mask=outside,alpha_changed_pixels=alpha_changes,
 alpha_outside_mask_unchanged=True,fixed_cymbal_pixels_preserved=True,mask_bounds=list(soft.getbbox()),
 source_rgba_sha256=hashlib.sha256(a).hexdigest(),rgba_sha256=hashlib.sha256(b).hexdigest(),
 png_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
 lifted_stick_bottom_tip_approx_xy=[996,447],snare_top_beneath_tip_approx_y=514,
 artist='built-in image_gen; generated arm, hand, stick and uncovered-area patch only')
(W/'pixel-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
head=Image.open(W/'source-head.png').convert('RGBA')
for name,body in [('before',source),('raised',final)]:
    transparent=Image.new('RGBA',source.size)
    transparent.alpha_composite(body)
    transparent.alpha_composite(head)
    background=Image.new('RGBA',source.size,'#dddddd')
    background.alpha_composite(transparent)
    background.convert('RGB').save(W/(name+'-preview-gray.png'))
    background.crop((880,270,1170,560)).resize((870,870),Image.Resampling.LANCZOS).convert('RGB').save(W/(name+'-hand-detail.png'))
print(json.dumps({'changed_pixels':changed,'outside_mask':outside,'cymbal_preserved':True}))
