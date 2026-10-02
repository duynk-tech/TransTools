"""Package the current default Chip Chip PNG as the macOS application icon."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import shutil
ROOT = Path(__file__).resolve().parents[1]
size = 1024
canvas = Image.new('RGBA', (size, size))
mask = Image.new('L', (size, size))
ImageDraw.Draw(mask).rounded_rectangle((80, 80, 944, 944), radius=190, fill=255)
background = Image.new('RGBA', (size, size))
draw = ImageDraw.Draw(background)
for y in range(size):
    t = y / size
    draw.line((0, y, size, y), fill=(round(48 - 23*t), round(77 - 33*t), round(104 - 37*t), 255))
background.putalpha(mask)
canvas.alpha_composite(background)
mascot = Image.open(ROOT/'Resources/Mascot3D.png').convert('RGBA')
mascot = mascot.crop(mascot.getchannel('A').getbbox())
mascot.thumbnail((780, 790), Image.Resampling.LANCZOS)
x = (size - mascot.width)//2
y = 112 + (790 - mascot.height)//2
shadow = Image.new('RGBA', (size, size))
ImageDraw.Draw(shadow).ellipse((270, 844, 754, 900), fill=(4, 18, 55, 115))
canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
canvas.alpha_composite(mascot, (x, y))
canvas.save(ROOT/'Resources/AppIcon.png')
canvas.save(ROOT/'Resources/icon_1024.png')
iconset = ROOT/'work/AppIcon.iconset'
iconset.mkdir(parents=True, exist_ok=True)
for side in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        suffix = '@2x' if scale == 2 else ''
        canvas.resize((side*scale, side*scale), Image.Resampling.LANCZOS).save(iconset/f'icon_{side}x{side}{suffix}.png')
shutil.copy2(ROOT/'Resources/AppIcon.png', ROOT/'docs/assets/app-icon.png')
print(iconset)
