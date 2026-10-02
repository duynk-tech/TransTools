from pathlib import Path
from PIL import Image,ImageDraw
import zipfile,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'renders/mascot-model'
comparison=Image.new('RGB',(1000,680),'#172434');draw=ImageDraw.Draw(comparison)
for i,(name,path) in enumerate([('Approved PNG',ROOT/'Resources/Mascot3D.png'),('Authored 3D render',out/'front.png')]):
 im=Image.open(path).convert('RGBA');im=im.crop(im.getbbox());im.thumbnail((440,590))
 comparison.paste(im,(i*500+(500-im.width)//2,20),im);draw.text((i*500+30,635),name,fill='white')
comparison.save(out/'comparison.png')
contact=Image.new('RGB',(1200,450),'#172434');draw=ImageDraw.Draw(contact)
for i,name in enumerate(['front','front_right','right','back']):
 im=Image.open(out/f'{name}.png').convert('RGBA');im=im.crop(im.getbbox());im.thumbnail((270,390))
 contact.paste(im,(i*300+(300-im.width)//2,10),im);draw.text((i*300+20,417),name,fill='white')
contact.save(out/'angles.png')
p=ROOT/'Resources/MascotModel/TransToolsMascot.usdz'
with zipfile.ZipFile(p) as z:
 assert z.testzip() is None
 files=z.namelist();assert any(f.endswith('.usdc') or f.endswith('.usd') for f in files)
 assert sum(f.endswith('.png') for f in files)>=2
 for f in z.infolist():
  # USDZ requires uncompressed entries aligned to 64 bytes.
  assert f.compress_type==zipfile.ZIP_STORED
  with p.open('rb') as stream:
   stream.seek(f.header_offset+26);import struct
   name_len,extra_len=struct.unpack('<HH',stream.read(4))
  assert (f.header_offset+30+name_len+extra_len)%64==0
meta={'version':1,'source':'scripts/build-mascot-model.py','blender':'4.5.0 official arm64; checksum verified','reference':'Resources/Mascot3D.png','coordinateConvention':'Source Blender +Z up, -Y forward; USD export converts to +Y up for RealityKit','rigged':False,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(p.parent/'manifest.json').write_text(json.dumps(meta,indent=2)+'\n')
print('USDZ structure/alignment/textures verified; comparisons generated')
