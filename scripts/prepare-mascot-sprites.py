"""Build the approved 8-direction / 8-frame 2D mascot sprite pack.

AI masters: work/mascot-sprites/masters. Uses the existing magenta matte pipeline.
Mirrored left-facing sprites are intended for UI animation, not ML training samples.
"""
from pathlib import Path
import json
import runpy
import hashlib
import numpy as np
from PIL import Image, ImageOps, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[1]
HELPERS = runpy.run_path(str(ROOT / 'scripts/prepare-resources.py'))
MASTERS = ROOT / 'work/mascot-sprites/masters'
DEST = ROOT / 'Resources/MascotSprites'
SIZE = (621, 783)
PREVIEW = ROOT / 'docs/assets'
RESAMPLE = Image.Resampling.LANCZOS


def clean(image):
    data = np.array(image)
    mask = HELPERS['keep_components'](data[:, :, 3] > 64, 12)
    data[:, :, 3][~ndi.binary_dilation(mask, iterations=1)] = 0
    data[data[:, :, 3] == 0, :3] = 0
    return Image.fromarray(data)


def build():
    for folder in ['angles', 'walk_right', 'walk_left']:
        (DEST/folder).mkdir(parents=True, exist_ok=True)
    angles = {'front': Image.open(ROOT/'Resources/Mascot3D.png').convert('RGBA'),
              'back': Image.open(ROOT/'Resources/MascotBack.png').convert('RGBA')}
    for name in ['front_right', 'right', 'back_right']:
        angles[name] = clean(HELPERS['fit'](HELPERS['chroma_cutout'](MASTERS/(name+'.png')), SIZE))
    for name in ['front', 'back']:
        angles[name] = clean(angles[name])
    for right, left in [('front_right', 'front_left'), ('right', 'left'), ('back_right', 'back_left')]:
        angles[left] = ImageOps.mirror(angles[right])
    for name, image in angles.items():
        image.save(DEST/'angles'/f'angle_{name}.png')

    sheet = Image.open(MASTERS/'walk_sheet.png')
    cells = []
    for row in range(2):
        for col in range(4):
            box = (round(col*sheet.width/4), round(row*sheet.height/2),
                   round((col+1)*sheet.width/4), round((row+1)*sheet.height/2))
            source = ROOT/'work/mascot-sprites'/f'cell-{len(cells):02d}.png'
            sheet.crop(box).save(source)
            cells.append(HELPERS['chroma_cutout'](source))
    # One shared scale for the whole cycle, stable head position and fixed canvas.
    boxes = [im.getbbox() for im in cells]
    assert all(boxes), 'Empty cell in walking sheet'
    scale = (SIZE[1]-28)/max(box[3]-box[1] for box in boxes)
    frames = []
    for i, image in enumerate(cells):
        a = np.array(image)[:, :, 3]
        head = a.copy(); head[int(image.height*0.58):] = 0
        ys, xs = np.where(head > 128)
        center_x = (xs.min()+xs.max())/2
        top = boxes[i][1]
        resized = image.resize((round(image.width*scale), round(image.height*scale)), RESAMPLE)
        output = Image.new('RGBA', SIZE)
        output.paste(resized, (round(SIZE[0]/2-center_x*scale), round(14-top*scale)))
        output = clean(output)
        output.save(DEST/'walk_right'/f'walk_right_{i:02d}.png')
        ImageOps.mirror(output).save(DEST/'walk_left'/f'walk_left_{i:02d}.png')
        frames.append(output)

    names = ['front','front_right','right','back_right','back','back_left','left','front_left']
    contact = Image.new('RGB', (1280, 500), '#162638')
    draw = ImageDraw.Draw(contact)
    for i, name in enumerate(names):
        image = angles[name].copy(); image.thumbnail((145, 200), RESAMPLE)
        x=i*160+(160-image.width)//2
        contact.paste(image, (x, 15), image)
        draw.text((i*160+8, 220), name, fill='#B8C9DE')
    for i, frame in enumerate(frames):
        image=frame.copy(); image.thumbnail((145, 200), RESAMPLE)
        contact.paste(image, (i*160+(160-image.width)//2, 260), image)
        draw.text((i*160+8, 474), f'walk {i+1}', fill='#B8C9DE')
    contact.save(PREVIEW/'mascot-sprites-preview.png')

    animation = []
    for facing in ['right', 'left']:
        for frame in frames:
            view = frame if facing == 'right' else ImageOps.mirror(frame)
            view=view.resize((198,250), RESAMPLE)
            bg=Image.new('RGB', (440,290), '#162638')
            bg.paste(view,(121,12),view)
            ImageDraw.Draw(bg).text((16,270),'TransTools | walk '+facing+' | 10 fps',fill='#B8C9DE')
            animation.append(bg)
    # Each direction plays three full cycles, then switches.
    sequence = animation[:8]*3+animation[8:]*3
    sequence[0].save(PREVIEW/'mascot-walk-preview.gif', save_all=True, append_images=sequence[1:], duration=100, loop=0, disposal=2)
    manifest={'version':1,'canvas':list(SIZE),'baseline':769,'frameRate':10,'angles':names,
              'walkFramesPerDirection':8,'leftViews':'mirrored from right-facing views for UI use',
              'source':'imagegen opaque masters + Python chroma matte and alignment',
              'files':{str(p.relative_to(DEST)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(DEST.rglob('*.png'))}}
    (DEST/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Created 8 directions + 16 walk frames, contact sheet, GIF and manifest.')


if __name__ == '__main__':
    build()
