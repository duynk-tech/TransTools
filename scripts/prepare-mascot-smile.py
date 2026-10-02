"""Composite only the AI smile onto approved PNGs; retain original pixels/alpha.
User-authorized Python processing avoids the generated background artifacts.
"""
from pathlib import Path
import json,hashlib,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'work/mascot-mouth';BACKUP=WORK/'originals'
source=Image.open(WORK/'generated-smile.png').convert('RGBA')
# Extract only the dark stroke from the face, discarding generated face/background.
crop=source.crop((508,669,599,706));a=np.array(crop,dtype=np.float32)
luma=a[:,:,:3].mean(axis=2)
alpha=np.clip((185-luma)/75,0,1)
a[:,:,:3]=(110,96,118);a[:,:,3]=alpha*255
mouth=Image.fromarray(a.astype('uint8'));mouth=mouth.crop(mouth.getbbox())
mouth.save(WORK/'smile-overlay.png')
# Centers follow each face plane; positive angle tilts up toward image right.
placements={
 'Resources/Mascot3D.png':(310,393,46,0),
 'Resources/MascotBody.png':(310,393,46,0),
 'Resources/MascotWriting.png':(358,401,44,0),
 'Resources/MascotSprites/angles/angle_front.png':(310,393,46,0),
 'Resources/MascotSprites/angles/angle_front_right.png':(424,383,39,3),
 'Resources/MascotSprites/angles/angle_front_left.png':(196,383,39,-3),
 'Resources/MascotActivities/coffee.png':(310,372,42,0),
 'Resources/MascotActivities/writing.png':(310,386,42,0),
 'Resources/MascotActivities/thinking.png':(275,354,42,-18),
 'Resources/MascotActivities/flowers.png':(332,393,42,22),
}
preview=Image.new('RGB',(1000,600),'#243444');draw=ImageDraw.Draw(preview)
for i,(rel,(x,y,width,angle)) in enumerate(placements.items()):
 path=ROOT/rel;original=BACKUP/rel
 if not original.exists():original.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,original)
 im=Image.open(original).convert('RGBA');before=np.array(im)
 patch=mouth.resize((width,round(width*mouth.height/mouth.width)),Image.Resampling.LANCZOS)
 patch=patch.rotate(angle,resample=Image.Resampling.BICUBIC,expand=True)
 overlay=Image.new('RGBA',im.size);overlay.alpha_composite(patch,(round(x-patch.width/2),round(y-patch.height/2)))
 result=Image.alpha_composite(im,overlay);after=np.array(result)
 # Never let the added stroke alter silhouette or background transparency.
 after[:,:,3]=before[:,:,3];result=Image.fromarray(after)
 mask=np.array(overlay)[:,:,3]>0
 assert np.array_equal(after[~mask],before[~mask])
 assert np.array_equal(after[:,:,3],before[:,:,3])
 result.save(path)
 thumb=result.copy();thumb.thumbnail((190,260));px=(i%5)*200;py=(i//5)*300
 preview.paste(thumb,(px+(200-thumb.width)//2,py),thumb);draw.text((px+4,py+270),path.stem,fill='white')
preview.save(ROOT/'docs/assets/mascot-smile-preview.png')
for folder in ['MascotActivities','MascotSprites']:
 path=ROOT/f'Resources/{folder}/manifest.json';data=json.loads(path.read_text())
 if folder=='MascotActivities':data['files']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(path.parent.glob('*.png'))}
 else:
  # Preserve the existing metadata format; refresh checksum fields if present.
  def refresh(node):
   if isinstance(node,dict):
    for key,val in node.items():
     candidate=path.parent/key
     if isinstance(val,str) and len(val)==64 and candidate.is_file():node[key]=hashlib.sha256(candidate.read_bytes()).hexdigest()
     else:refresh(val)
   elif isinstance(node,list):
    for val in node:refresh(val)
  refresh(data)
 data['smile']='Small AI-derived closed smile composited onto visible front/three-quarter faces; original alpha preserved'
 path.write_text(json.dumps(data,indent=2)+'\n')
print(f'Updated {len(placements)} PNGs; verified unchanged alpha and pixels outside mouth')
