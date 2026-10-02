"""Create transparent activity loops from identity-locked AI activity masters.
One shared transform per cell prevents normalization-induced size jumps.
"""
from pathlib import Path
import runpy,json,hashlib
import numpy as np
import cv2,math
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'work/mascot-activity-animation';DEST=ROOT/'Resources/MascotActivities/animations'
DEST.mkdir(parents=True,exist_ok=True)
helpers=runpy.run_path(str(ROOT/'scripts/prepare-resources.py'))
sheet=Image.open(WORK/'keyframe-sheet.png');size=(621,783)
manifest={'version':1,'canvas':[310,391],'sourceKeyframesPerClip':1,'interpolation':'continuous local PNG deformation; identity locked, periodic head/hand motion and butterfly wings','clips':{}}
preview=Image.new('RGB',(1200,640),'#203044');draw=ImageDraw.Draw(preview);clips=[]
for row,name in enumerate(['flowers','butterfly']):
 keyframes=[]
 for col in range(4):
  box=(round(col*sheet.width/4),round(row*sheet.height/2),round((col+1)*sheet.width/4),round((row+1)*sheet.height/2))
  source=WORK/f'{name}-key-{col}.png';sheet.crop(box).save(source)
  im=helpers['chroma_cutout'](source)
  scale=min((size[0]-40)/im.width,(size[1]-32)/im.height)
  im=im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',size);canvas.alpha_composite(im,((size[0]-im.width)//2,size[1]-16-im.height))
  keyframes.append(canvas)
 # Optical-flow drafts ghosted the eyes during a large head bend. Use one
 # identity-locked master per clip with continuous, small local deformations.
 master=helpers['chroma_cutout'](WORK/f'{name}-key-0.png')
 data=np.asarray(master,dtype=np.float32)/255
 data[:,:,:3]*=data[:,:,3:]
 height,width=data.shape[:2];yy,xx=np.mgrid[:height,:width].astype(np.float32)
 frames=[]
 for index in range(64):
  phase=2*math.pi*index/64
  ease=(1-math.cos(phase))/2
  neckX=width*.50;neckY=height*.565
  headWeight=np.clip((height*.615-yy)/(height*.060),0,1)
  angle=math.radians((5 if name=='flowers' else -3)*ease)
  dx=xx-neckX;dy=yy-neckY
  mx=xx+headWeight*(math.cos(angle)*dx+math.sin(angle)*dy-dx)
  my=yy+headWeight*(-math.sin(angle)*dx+math.cos(angle)*dy-dy)
  if name=='flowers':
   hand=np.exp(-((xx-width*.65)/(width*.14))**4-((yy-height*.68)/(height*.16))**4)
   my+=hand*height*.025*ease
   mx+=hand*width*.007*math.sin(phase)
  else:
   hand=np.exp(-((xx-width*.77)/(width*.16))**4-((yy-height*.57)/(height*.12))**4)
   my+=hand*height*.010*ease
   # Gentle wing foreshortening, feathered into the transparent surroundings.
   bx=width*.91;by=height*.415
   wing=np.exp(-((xx-bx)/(width*.095))**6-((yy-by)/(height*.083))**6)
   wingScale=.82+.18*math.cos(phase*4)
   mx+=wing*(xx-bx)*(1/wingScale-1)
   my+=wing*height*.006*math.sin(phase*2)
  rgba=cv2.remap(data,mx.astype(np.float32),my.astype(np.float32),cv2.INTER_CUBIC,borderMode=cv2.BORDER_CONSTANT)
  rgba=np.clip(rgba,0,1);rgba[:,:,:3]/=np.maximum(rgba[:,:,3:],1/255)
  rgba[rgba[:,:,3]<1/255]=0
  im=Image.fromarray((np.clip(rgba,0,1)*255).round().astype('uint8'))
  scale=min((size[0]-40)/im.width,(size[1]-32)/im.height)
  im=im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',size);canvas.alpha_composite(im,((size[0]-im.width)//2,size[1]-16-im.height));frames.append(canvas)
 files=[]
 for i,frame in enumerate(frames):
  frame=frame.resize((310,391),Image.Resampling.LANCZOS)
  alpha=np.asarray(frame)[:,:,3];assert alpha.max()==255 and alpha[0].max()==0 and alpha[-1].max()==0
  filename=f'{name}/{name}_{i:02d}.png';path=DEST/filename;path.parent.mkdir(exist_ok=True);frame.save(path);files.append(filename)
  if i%8==0:
   thumb=frame.copy();thumb.thumbnail((145,265));x=(i//8)*150;y=row*320
   preview.paste(thumb,(x+(150-thumb.width)//2,y+15),thumb);draw.text((x+8,y+290),f'{name} {i:02d}',fill='white')
 manifest['clips'][name]={'fps':16.0,'durationSeconds':4.0,'frames':files}
 clips.append([Image.open(DEST/f).convert('RGBA') for f in files]);print(name,len(frames),flush=True)
manifest['files']={str(p.relative_to(DEST)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(DEST.rglob('*.png'))}
(DEST/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
preview.save(ROOT/'docs/assets/mascot-activity-animation-preview.png')
gif=[]
for i in range(64):
 canvas=Image.new('RGB',(480,310),'#203044');d=ImageDraw.Draw(canvas)
 for j,frames in enumerate(clips):
  thumb=frames[i].copy();thumb.thumbnail((235,285));canvas.paste(thumb,(j*240+(240-thumb.width)//2,0),thumb)
 d.text((15,290),'Flowers',fill='white');d.text((255,290),'Butterfly',fill='white');gif.append(canvas)
gif[0].save(ROOT/'docs/assets/mascot-activity-animation-preview.gif',save_all=True,append_images=gif[1:],duration=[60,65]*32,loop=0,disposal=2)
print('Verified 128 transparent frames and wrote manifest / GIF / contact sheet',flush=True)
