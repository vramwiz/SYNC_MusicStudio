"""Package image_gen's enlarged hand correction into the exact source layer."""
import hashlib
import json
from pathlib import Path
from PIL import Image

WORK = Path(__file__).resolve().parent
SOURCE = WORK / 'source-basic.png'
original = Image.open(SOURCE).convert('RGBA')
generated_crop = Image.open(WORK / 'generated-hand.png').convert('RGBA')
assert original.size == (1536, 1024)
assert generated_crop.width == generated_crop.height
context_box = (860, 320, 1116, 576)
generated = original.copy()
generated.paste(generated_crop.resize((256, 256), Image.Resampling.LANCZOS), context_box[:2])
box = (944, 407, 1033, 487)
mask = Image.new('L', (box[2] - box[0], box[3] - box[1]))
mask.putdata([round(255 * min(1, (min(x+1, y+1, mask.width-x, mask.height-y)-1)/4))
              for y in range(mask.height) for x in range(mask.width)])
local = Image.composite(generated.crop(box), original.crop(box), mask)
final = original.copy()
final.paste(local, box[:2])
final.putalpha(original.getchannel('A'))
output = WORK / '基本_スティック握り修正.png'
assert not output.exists(), 'Preserve existing output'
final.save(output)
a, b = original.tobytes(), final.tobytes()
changed = outside = 0
for y in range(original.height):
    for x in range(original.width):
        i = (y * original.width + x) * 4
        if a[i:i+4] != b[i:i+4]:
            changed += 1
            outside += not (box[0] <= x < box[2] and box[1] <= y < box[3])
assert changed > 0 and outside == 0
assert hashlib.sha256(a).hexdigest() == 'cd7bc7f06aca9a4a6375a339e6caeb64da77eccdfdd1606bb32085e539ba3f99'
assert final.getchannel('A').tobytes() == original.getchannel('A').tobytes()
with Image.open(output) as check:
    assert check.convert('RGBA').tobytes() == b
record = dict(source=str(SOURCE), generated=str(WORK / 'generated-hand.png'), output=str(output),
              size=list(final.size), generated_crop_size=list(generated_crop.size),
              context_rectangle_ltrb=list(context_box), edited_rectangle_ltrb=list(box),
              edge_transition_pixels=4, changed_pixels=changed, changed_pixels_outside_rectangle=outside,
              original_alpha_entirely_preserved=True, source_rgba_sha256=hashlib.sha256(a).hexdigest(),
              rgba_sha256=hashlib.sha256(b).hexdigest(), png_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
              artist='built-in image_gen; enlarged hand edit downsampled and locally composited')
(WORK / 'pixel-verification.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
for name, im in [('before', original), ('final', final)]:
    detail = im.crop((880, 360, 1080, 530))
    background = Image.new('RGBA', detail.size, '#dddddd')
    background.alpha_composite(detail)
    background.convert('RGB').resize((800, 680)).save(WORK / f'right-hand-{name}-detail.png')
print(json.dumps({'changed_pixels': changed, 'outside_rectangle': outside, 'size': list(final.size),
                  'generated_crop_size': list(generated_crop.size)}))
