"""Prepare approved AI masters without destructive white-background thresholding.

Run from project root after saving pose masters in work/resource-review/masters.
Dependencies: Pillow, numpy, scipy. Original files remain in work/resource-review/originals.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[1]
MASTERS = ROOT / 'work/resource-review/masters'
DEST = ROOT / 'Resources'
LANCZOS = Image.Resampling.LANCZOS


def keep_components(mask, minimum):
    labels, _ = ndi.label(mask)
    counts = np.bincount(labels.ravel())
    keep = counts >= minimum
    keep[0] = False
    return keep[labels]


def chroma_cutout(path):
    rgb = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)
    # Key saturated magenta only, not pale purple highlights or cyan eyes.
    chroma = np.minimum(rgb[:, :, 0], rgb[:, :, 2]) - rgb[:, :, 1]
    background = (chroma > 135) & (rgb[:, :, 1] < 110)
    mask = keep_components(~background, 180)
    solid = ndi.binary_erosion(mask, iterations=2)
    if not solid.any():
        raise ValueError('Empty foreground: ' + str(path))
    # Solve edge alpha against the nearest solid foreground, then remove key color.
    _, indices = ndi.distance_transform_edt(~solid, return_indices=True)
    foreground = rgb[indices[0], indices[1]]
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    key = np.median(border, axis=0)
    delta = foreground - key
    alpha = np.clip(np.sum((rgb - key) * delta, axis=2) / np.maximum(np.sum(delta * delta, axis=2), 1), 0, 1)
    alpha[solid] = 1
    alpha[~ndi.binary_dilation(mask, iterations=2)] = 0
    # No disconnected dust. Sleeping Z symbols remain substantial components.
    retained = keep_components(alpha > 0.1, 180)
    alpha[~ndi.binary_dilation(retained, iterations=1)] = 0
    recovered = np.clip((rgb - (1 - alpha[:, :, None]) * key) / np.maximum(alpha[:, :, None], 0.01), 0, 255)
    recovered[alpha == 0] = 0
    result = np.dstack([recovered, alpha * 255]).round().astype(np.uint8)
    return Image.fromarray(result)


def fit(image, size, margin=14, nearest=False):
    box = image.getbbox()
    if box is None:
        raise ValueError('Empty image')
    image = image.crop(box)
    factor = min((size[0]-2*margin)/image.width, (size[1]-2*margin)/image.height)
    image = image.resize((round(image.width*factor), round(image.height*factor)), Image.Resampling.NEAREST if nearest else LANCZOS)
    canvas = Image.new('RGBA', size)
    canvas.paste(image, ((size[0]-image.width)//2, (size[1]-image.height)//2))
    return canvas


def preview(names, target):
    width, cell, row = 1200, 240, 310
    output = Image.new('RGB', (width, row*2), '#F2F5FA')
    draw = ImageDraw.Draw(output)
    for theme, color in enumerate(['#F2F5FA', '#172434']):
        draw.rectangle((0, theme*row, width, (theme+1)*row), fill=color)
        for i, name in enumerate(names):
            image = Image.open(DEST / name).convert('RGBA')
            image.thumbnail((210, 250), LANCZOS)
            output.paste(image, (i*cell+(cell-image.width)//2, theme*row+15+(250-image.height)//2), image)
            draw.text((i*cell+16, theme*row+280), name, fill='#63758A' if theme == 0 else '#BDCBDC')
    output.save(target)


def prepare_rig():
    image = Image.open(DEST / 'Mascot3D.png').convert('RGBA')
    rgba = np.asarray(image).copy()
    polygons = [
        [(194, 650), (210, 667), (236, 686), (266, 701), (297, 708), (299, 783), (180, 783)],
        [(325, 708), (354, 702), (383, 688), (409, 670), (426, 650), (445, 783), (323, 783)]
    ]
    masks = []
    for points in polygons:
        mask = Image.new('L', (image.width*4, image.height*4))
        ImageDraw.Draw(mask).polygon([(x*4, y*4) for x, y in points], fill=255)
        masks.append(np.asarray(mask.resize(image.size, LANCZOS), dtype=np.float32)/255)
    body = rgba.copy()
    body[:, :, 3] = (rgba[:, :, 3]*(1-np.maximum(*masks))).round().astype(np.uint8)
    Image.fromarray(body).save(DEST / 'MascotBody.png')
    boxes = [(190, 648, 300, 773), (323, 648, 433, 773)]
    for mask, box, name in zip(masks, boxes, ['MascotLegLeft.png', 'MascotLegRight.png']):
        leg = rgba.copy()
        # Slight overlap inside the torso prevents a gap when a foot rotates.
        overlap = ndi.maximum_filter(mask, size=5)
        leg[:, :, 3] = (rgba[:, :, 3]*overlap).round().astype(np.uint8)
        crop = np.asarray(Image.fromarray(leg).crop(box)).copy()
        retained = keep_components(crop[:, :, 3] > 64, 8)
        crop[:, :, 3][~ndi.binary_dilation(retained, iterations=1)] = 0
        crop[crop[:, :, 3] == 0, :3] = 0
        Image.fromarray(crop).save(DEST / name)
    canvas = Image.new('RGBA', image.size)
    for box, name in zip(boxes, ['MascotLegLeft.png', 'MascotLegRight.png']):
        canvas.alpha_composite(Image.open(DEST/name), (box[0], box[1]))
    canvas.alpha_composite(Image.open(DEST/'MascotBody.png'))
    background = Image.new('RGBA', image.size, '#172434')
    background.alpha_composite(canvas)
    background.convert('RGB').save(ROOT/'work/resource-review/rig-check.jpg')


if __name__ == '__main__':
    mapping = {'front': ('Mascot3D.png', (621, 783)), 'writing': ('MascotWriting.png', (621, 783)),
               'back': ('MascotBack.png', (621, 783)), 'walking': ('MascotWalking.png', (445, 783)),
               'sleeping': ('MascotSleeping.png', (1024, 1024))}
    for key, (filename, dimensions) in mapping.items():
        fit(chroma_cutout(MASTERS / (key + '.png')), dimensions).save(DEST / filename)
    icon = fit(Image.open(MASTERS / 'icon.png').convert('RGBA'), (1024, 1024), margin=80)
    icon.save(DEST / 'AppIcon.png')
    icon.save(DEST / 'icon_1024.png')
    iconset = ROOT / 'work/resource-review/TransTools.iconset'
    iconset.mkdir(exist_ok=True)
    for side in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            suffix = '@2x' if scale == 2 else ''
            icon.resize((side*scale, side*scale), LANCZOS).save(iconset / f'icon_{side}x{side}{suffix}.png')
    fit(Image.open(MASTERS / 'pixel.png').convert('RGBA'), (64, 80), margin=2, nearest=True).save(DEST / 'Mini.png')
    prepare_rig()
    preview([x[0] for x in mapping.values()], ROOT / 'work/resource-review/after.png')
    print('Prepared 5 poses, 3 matching rig parts, icon and pixel companion.')
