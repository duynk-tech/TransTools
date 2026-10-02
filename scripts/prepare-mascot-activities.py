from pathlib import Path
import runpy,json,hashlib
from PIL import Image,ImageDraw
import numpy as np
from scipy import ndimage as ndi
ROOT=Path(__file__).resolve().parents[1]
helpers=runpy.run_path(str(ROOT/'scripts/prepare-resources.py'))
sheet=Image.open(ROOT/'work/mascot-activities/approved-sheet.png')
names=['coffee','writing','thinking','strolling','flowers','sleeping']
dest=ROOT/'Resources/MascotActivities'
preview=Image.new('RGB',(1200,640),'#172434');draw=ImageDraw.Draw(preview)
for i,name in enumerate(names):
 row,col=divmod(i,3)
 edges=[0,round(sheet.width/3),round(sheet.width*(0.653 if row else 2/3)),sheet.width]
 box=(edges[col],round(row*sheet.height/2),edges[col+1],round((row+1)*sheet.height/2))
 source=ROOT/f'work/mascot-activities/{name}-source.png';sheet.crop(box).save(source)
 cutout=helpers['chroma_cutout'](source)
 data=np.array(cutout)
 labels,_=ndi.label(data[:,:,3]>32)
 border=np.unique(np.concatenate([labels[0],labels[-1],labels[:,0],labels[:,-1]]))
 keep=(labels>0)&~np.isin(labels,border)
 data[:,:,3][~ndi.binary_dilation(keep,iterations=2)]=0
 cutout=Image.fromarray(data)
 bounds=cutout.getbbox();assert bounds and bounds[0]>1 and bounds[2]<cutout.width-5, (name,bounds)
 result=helpers['fit'](cutout,(621,783),margin=24)
 result.save(dest/f'{name}.png')
 thumb=result.copy();thumb.thumbnail((350,270));preview.paste(thumb,(col*400+(400-thumb.width)//2,row*320+10),thumb)
 draw.text((col*400+20,row*320+294),name,fill='white')
preview.save(ROOT/'docs/assets/mascot-activities-preview.png')
manifest={'version':1,'poses':names,'canvas':[621,783],'purpose':'UI pose images and artistic reference; not a trained Vision model','files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dest.glob('*.png'))}}
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Prepared six complete pose images with transparent background')
