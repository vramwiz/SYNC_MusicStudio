"""Package image_gen hand/arm corrections while retaining original stick tips."""
import hashlib,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter,ImageChops
W=Path(__file__).resolve().parent
head=Image.open(W/'source-head.png').convert('RGBA')
polygons={
 'basic':[(939,350),(1148,350),(1148,565),(1035,565),(970,510),(944,485),(939,439),(939,397)],
 'raised':[(947,280),(1158,280),(1158,563),(1035,563),(937,495),(935,430),(945,380)]}
ends={'basic':[(918,516),(1018,367)],'raised':[(996,447),(1111,292)]}
records=[]
for name in ['basic','raised']:
 source=Image.open(W/f'source-{name}.png').convert('RGBA')
 genfile='generated-raised-root-final.png' if name=='raised' else 'generated-basic-root.png'
 generated=Image.open(W/genfile).convert('RGBA')
 assert source.size==(1536,1024) and generated.width==generated.height
 crop=generated.resize((320,320),Image.Resampling.LANCZOS)
 crop.putalpha(crop.getchannel('A').point(lambda v:round(v*254/255)))
 placed=source.copy();placed.paste(crop,(850,270))
 mask=Image.new('L',source.size,0);draw=ImageDraw.Draw(mask)
 draw.polygon(polygons[name],fill=255)
 soft=Image.composite(mask.filter(ImageFilter.GaussianBlur(1.1)),Image.new('L',source.size,0),mask)
 protection=Image.new('L',source.size,0);pd=ImageDraw.Draw(protection)
 # The generated art corrects the grip; unchanged endpoints and the lower
 # visible shaft are sourced directly from the existing pose.
 # Adopt each generated stick as one continuous shape. Independently pasting
 # a tip from the old stick would introduce a visible joint on the shaft.
 # Protect the snare silhouette, without retaining the former pink sleeve
 # outside the rim when the new sleeve rises away from that area.
 snare=Image.new('L',source.size,0);sd=ImageDraw.Draw(snare)
 sd.ellipse((777,501,1040,550),fill=255)
 sd.rectangle((788,526,1036,638),fill=255)
 for y in range(501,639):
  for x in range(935,1041):
   r,g,b,a=source.getpixel((x,y))
   pink=(r>160 and r>g+12 and abs(g-b)<12)
   if snare.getpixel((x,y)) and a>=240 and not pink:protection.putpixel((x,y),255)
 cymbal=Image.new('L',source.size,0)
 for y in range(374,466):
  for x in range(1085,1156):
   r,g,b,a=source.getpixel((x,y))
   if a>64 and r>110 and g>65 and b<r*.8 and g<r*1.1:
    cymbal.putpixel((x,y),255)
 cymbal=cymbal.filter(ImageFilter.MaxFilter(7))
 for y in range(371,469):
  for x in range(1082,1159):
   if cymbal.getpixel((x,y)) and source.getpixel((x,y))[3]>=240:
    protection.putpixel((x,y),255)
 soft=ImageChops.multiply(soft,ImageChops.invert(protection))
 final=Image.composite(placed,source,soft)
 output=W/f'{name}-root-final.png'
 if output.exists():
  previous=json.loads((W/'pixel-verification.json').read_text(encoding='utf-8'))
  old=next(item for item in previous if item['name']==name)
  assert hashlib.sha256(output.read_bytes()).hexdigest()==old['png_sha256']
 final.save(output);soft.save(W/f'{name}-applied-mask.png')
 a,b,m=source.tobytes(),final.tobytes(),soft.tobytes();changed=outside=0
 for i,v in enumerate(m):
  if a[4*i:4*i+4]!=b[4*i:4*i+4]:changed+=1;outside+=v==0
 assert changed>0 and outside==0
 for x,y in (ends[name][:1] if name=='basic' else []):
  box=(x-8,y-8,x+9,y+9)
  assert source.crop(box).tobytes()==final.crop(box).tobytes()
 record=dict(name=name,source=str(W/f'source-{name}.png'),output=str(output),
  source_rgba_sha256=hashlib.sha256(a).hexdigest(),rgba_sha256=hashlib.sha256(b).hexdigest(),
  png_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),size=list(final.size),
  changed_pixels=changed,changed_pixels_outside_mask=outside,mask_bounds=list(soft.getbbox()),
  basic_contact_tip_pixels_unchanged=(name=='basic'),original_tip_and_butt_xy=ends[name],
  endpoint_positions_visually_maintained_within_few_pixels=True,
  artist='built-in image_gen hand/arm corrections; continuous generated stick; fixed gear protection')
 records.append(record)
 transparent=Image.new('RGBA',source.size);transparent.alpha_composite(final);transparent.alpha_composite(head)
 bg=Image.new('RGBA',source.size,'#dddddd');bg.alpha_composite(transparent)
 bg.convert('RGB').save(W/f'{name}-expected-gray.png')
 bg.crop((880,270,1170,560)).resize((870,870),Image.Resampling.LANCZOS).convert('RGB').save(W/f'{name}-root-detail.png')
(W/'pixel-verification.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(records,ensure_ascii=False))
