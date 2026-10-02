"""Prepare refreshed writing/sleep PNGs and two coherent 64-frame loops.
User-authorized Python matte cleanup and local premultiplied RGBA animation.
"""
from pathlib import Path
import runpy,json,hashlib,shutil,math
import numpy as np
import cv2
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'work/mascot-write-sleep';DEST=ROOT/'Resources/MascotActivities';ANIM=DEST/'animations'
helpers=runpy.run_path(str(ROOT/'scripts/prepare-resources.py'))
manifest=json.loads((ANIM/'manifest.json').read_text());preview=Image.new('RGB',(900,450),'#243444');clips=[]
for name in ['writing','sleeping']:
 master=helpers['chroma_cutout'](WORK/f'{name}-master.png')
 size=(621,783) if name=='writing' else (900,650)
 fitted=helpers['fit'](master,size,margin=24)
 for path in [DEST/f'{name}.png',ROOT/f'Resources/Mascot{name.title()}.png']:
  original=WORK/'originals'/path.relative_to(ROOT)
  if not original.exists():original.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,original)
  fitted.save(path)
 data=np.asarray(master,dtype=np.float32)/255;data[:,:,:3]*=data[:,:,3:]
 height,width=data.shape[:2];yy,xx=np.mgrid[:height,:width].astype(np.float32)
 files=[];frames=[]
 for index in range(64):
  p=index/64;phase=2*math.pi*p;mx=xx.copy();my=yy.copy()
  if name=='writing':
   # Coherent short strokes, then a brief pencil lift; notebook and feet stay put.
   gate=math.sin(math.pi*min(p/.75,1))**.65 if p<.75 else 0
   lift=math.sin(math.pi*(p-.75)/.25) if p>=.75 else 0
   hand=np.exp(-((xx-width*.40)/(width*.15))**4-((yy-height*.575)/(height*.115))**4)
   dx=width*.016*math.sin(phase*4)*gate
   dy=height*.0025*math.sin(phase*8)*gate-height*.013*lift
   mx-=hand*dx;my-=hand*dy
  else:
   # Pillow stays planted; blanket rises softly with a four-second breath.
   breath=(1-math.cos(phase))/2
   chest=np.exp(-((xx-width*.70)/(width*.25))**4-((yy-height*.53)/(height*.21))**4)
   my+=chest*height*.007*breath
   head=np.exp(-((xx-width*.40)/(width*.27))**4-((yy-height*.35)/(height*.28))**4)
   my+=head*height*.0018*breath
  rgba=cv2.remap(data,mx.astype(np.float32),my.astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_CONSTANT)
  rgba=np.clip(rgba,0,1);rgba[:,:,:3]/=np.maximum(rgba[:,:,3:],1/255);rgba[rgba[:,:,3]<1/255]=0
  im=Image.fromarray((np.clip(rgba,0,1)*255).round().astype('uint8'))
  # Constant transform, using master bounds instead of animated bounds.
  box=master.getbbox();im=im.crop(box)
  scale=min((size[0]-48)/im.width,(size[1]-48)/im.height)
  im=im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',size);canvas.alpha_composite(im,((size[0]-im.width)//2,(size[1]-im.height)//2))
  output=canvas.resize((size[0]//2,size[1]//2),Image.Resampling.LANCZOS)
  a=np.asarray(output)[:,:,3];assert a.max()==255 and a[0].max()==0 and a[-1].max()==0
  filename=f'{name}/{name}_{index:02d}.png';path=ANIM/filename;path.parent.mkdir(exist_ok=True);output.save(path);files.append(filename);frames.append(output)
 manifest['clips'][name]={'fps':16.0,'durationSeconds':4.0,'canvas':[size[0]//2,size[1]//2],'frames':files,'motion':'short strokes and pencil lift' if name=='writing' else 'subtle chest/blanket breathing'}
 clips.append(frames)
 thumb=fitted.copy();thumb.thumbnail((420,390));x=0 if name=='writing' else 450;preview.paste(thumb,(x+(450-thumb.width)//2,(410-thumb.height)//2),thumb);ImageDraw.Draw(preview).text((x+15,425),name,fill='white')
manifest['files']={str(p.relative_to(ANIM)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(ANIM.rglob('*.png'))}
(ANIM/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
static_manifest=json.loads((DEST/'manifest.json').read_text());static_manifest['files']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(DEST.glob('*.png'))};static_manifest['poseCanvases']={'writing':[621,783],'sleeping':[900,650]};(DEST/'manifest.json').write_text(json.dumps(static_manifest,indent=2)+'\n')
preview.save(ROOT/'docs/assets/mascot-write-sleep-preview.png')
gif=[]
for i in range(64):
 canvas=Image.new('RGB',(650,350),'#243444');draw=ImageDraw.Draw(canvas)
 for j,frames in enumerate(clips):
  im=frames[i].copy();im.thumbnail((315,315));canvas.paste(im,(j*325+(325-im.width)//2,(320-im.height)//2),im)
 draw.text((15,330),'Writing',fill='white');draw.text((340,330),'Sleeping',fill='white');gif.append(canvas)
gif[0].save(ROOT/'docs/assets/mascot-write-sleep-preview.gif',save_all=True,append_images=gif[1:],duration=[60,65]*32,loop=0,disposal=2)
print('Prepared writing/open notebook and sleeping/pillow/blanket; 128 transparent frames; original PNGs backed up')
