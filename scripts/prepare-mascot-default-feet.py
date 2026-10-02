"""Apply AI-authored soft feet to default PNG angles; preserve upper originals."""
from pathlib import Path
import runpy,json,hashlib,shutil
import numpy as np
from PIL import Image,ImageOps,ImageDraw
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'work/mascot-default-feet';DEST=ROOT/'Resources/MascotSprites'
helpers=runpy.run_path(str(ROOT/'scripts/prepare-resources.py'))
patches={'front':650,'front_right':650,'right':610,'back_right':660,'back':670}
results={}
for name,split in patches.items():
 path=DEST/'angles'/f'angle_{name}.png';original=WORK/'originals'/path.relative_to(ROOT)
 if not original.exists():original.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,original)
 before=Image.open(original).convert('RGBA');edited=helpers['fit'](helpers['chroma_cutout'](WORK/f'{name}-master.png'),before.size,margin=14)
 a=np.asarray(before,dtype=np.float32)/255;b=np.asarray(edited,dtype=np.float32)/255
 # Blend only the small attachment seam in premultiplied alpha.
 a[:,:,:3]*=a[:,:,3:];b[:,:,:3]*=b[:,:,3:]
 weight=np.clip((np.arange(before.height)-split)/28,0,1)[:,None,None]
 out=a*(1-weight)+b*weight;out[:,:,:3]/=np.maximum(out[:,:,3:],1/255);out[out[:,:,3]<1/255]=0
 out=(np.clip(out,0,1)*255).round().astype('uint8');out[:split+1]=np.asarray(before)[:split+1]
 assert np.array_equal(out[:split+1],np.asarray(before)[:split+1])
 result=Image.fromarray(out);result.save(path);results[name]=result
for right,left in [('front_right','front_left'),('right','left'),('back_right','back_left')]:
 path=DEST/'angles'/f'angle_{left}.png';original=WORK/'originals'/path.relative_to(ROOT)
 if not original.exists():original.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,original)
 result=ImageOps.mirror(results[right]);result.save(path);results[left]=result
for name,filename in [('front','Mascot3D.png'),('back','MascotBack.png')]:
 path=ROOT/'Resources'/filename;original=WORK/'originals'/path.relative_to(ROOT)
 if not original.exists():original.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,original)
 results[name].save(path)
manifest=json.loads((DEST/'manifest.json').read_text());manifest['defaultFeet']='soft continuous short legs and forward oval toes; five AI lower-body edits plus three mirrored views; upper PNG pixels preserved'
manifest['files']={str(p.relative_to(DEST)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(DEST.rglob('*.png'))};(DEST/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
names=['front','front_right','right','back_right','back','back_left','left','front_left']
preview=Image.new('RGB',(1000,580),'#243444');d=ImageDraw.Draw(preview)
for i,name in enumerate(names):
 im=results[name].copy();im.thumbnail((215,245));x=(i%4)*250;y=(i//4)*290;preview.paste(im,(x+(250-im.width)//2,y+5),im);d.text((x+12,y+265),name,fill='white')
preview.save(ROOT/'docs/assets/mascot-default-angles.png')
print('Updated 8 default angles + primary front/back; upper pixels and alpha preserved above leg seam')
