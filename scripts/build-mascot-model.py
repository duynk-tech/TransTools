"""Build a reference-matched, editable mascot in Blender 4.5.
Run: Blender --background --python scripts/build-mascot-model.py -- --draft
"""
import bpy, math, sys, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'work/mascot-model'; RENDERS=ROOT/'renders/mascot-model'
OUT.mkdir(parents=True,exist_ok=True);RENDERS.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32 if '--draft' in sys.argv else 96
scene.cycles.use_denoising=True
scene.render.resolution_x=800;scene.render.resolution_y=1000;scene.render.resolution_percentage=80 if '--draft' in sys.argv else 100
scene.render.film_transparent=True
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.view_settings.view_transform='Standard'
world=bpy.data.worlds.new('Soft studio world');scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.74,.80,.90,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.16

collection=bpy.data.collections.new('Mascot geometry');scene.collection.children.link(collection)
root=bpy.data.objects.new('MascotRoot',None);collection.objects.link(root)

def place(obj,name,group=root):
 obj.name=name
 for c in list(obj.users_collection):c.objects.unlink(obj)
 collection.objects.link(obj);obj.parent=group
 for polygon in getattr(obj.data,'polygons',[]):polygon.use_smooth=True
 return obj

def material(name,color,roughness=.32,metallic=0,coat=.2):
 mat=bpy.data.materials.new(name);mat.use_nodes=True
 bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
 bs.inputs['Roughness'].default_value=roughness;bs.inputs['Metallic'].default_value=metallic
 bs.inputs['Coat Weight'].default_value=coat;bs.inputs['Coat Roughness'].default_value=.22
 return mat
pearl=material('Pearl ceramic shell',(.87,.90,.94),.42,0,.18)
face=material('Warm pearl face',(.91,.90,.95),.35,.025,.22)
lilac=material('Soft lilac seam',(.59,.58,.72),.42,.08,.1)
mint=material('Mint headphone accent',(.25,.85,.79),.25,.09,.28)
pad=material('Soft ear cushion',(.69,.73,.81),.49,0,.07)
sole=material('Pearl foot sole',(.78,.81,.86),.47,0,.08)

def oval(name,location,scale,mat,parent=root):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=80,ring_count=48,location=location)
 obj=place(bpy.context.object,name,parent);obj.scale=scale;obj.data.materials.append(mat)
 return obj

def signed(v,exponent):return math.copysign(abs(v)**exponent,v)
def superoval(name,loc,scale,mat,exponent=.72):
 # Smooth rounded box/oval shell, rather than a stretched stock sphere.
 vertices=[];faces=[];rows=64;cols=128
 for j in range(rows+1):
  lat=-math.pi/2+math.pi*j/rows
  for i in range(cols):
   lon=2*math.pi*i/cols
   vertices.append((scale[0]*signed(math.cos(lat),exponent)*signed(math.cos(lon),exponent),scale[1]*signed(math.cos(lat),exponent)*signed(math.sin(lon),exponent),scale[2]*signed(math.sin(lat),exponent)))
 for j in range(rows):
  for i in range(cols):
   n=(i+1)%cols;faces.append((j*cols+i,j*cols+n,(j+1)*cols+n,(j+1)*cols+i))
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
 obj=bpy.data.objects.new(name,mesh);collection.objects.link(obj);obj.parent=root;obj.location=loc;obj.data.materials.append(mat)
 for p in mesh.polygons:p.use_smooth=True
 return obj

def tube(name,points,radius,mat,parent=root):
 curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.resolution_u=32;curve.bevel_depth=radius;curve.bevel_resolution=6
 spline=curve.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
 for point,co in zip(spline.bezier_points,points):point.co=co;point.handle_left_type='AUTO';point.handle_right_type='AUTO'
 obj=bpy.data.objects.new(name,curve);collection.objects.link(obj);obj.parent=parent;obj.data.materials.append(mat)
 return obj

# Coordinate convention: +Z up; mascot's forward/toes face -Y.
head=superoval('Head rounded oval',(0,0,1.48),(.745,.425,.505),pearl,.83)
# Round the crown independently, preserving the approved lower face silhouette.
for vertex in head.data.vertices:
 if vertex.co.z > 0:
  t=vertex.co.z/.505
  vertex.co.z += .045*t*t
  vertex.co.x *= 1-.035*t*t
# Thin inset face and hairline perimeter: no protruding speech bubble chin.
superoval('Face inset perimeter',(0,-.398,1.47),(.650,.112,.407),lilac,.94)
superoval('Face ceramic panel',(0,-.407,1.47),(.644,.112,.402),face,.94)

for side,label in [(-1,'Left'),(1,'Right')]:
 # Discs are shallow ellipsoids oriented perpendicular to the headband.
 oval('Ear '+label+' cushion',(side*.767,.008,1.48),(.103,.285,.327),pad)
 oval('Ear '+label+' shell',(side*.86,.018,1.48),(.090,.254,.312),pearl)
 oval('Ear '+label+' mint rim',(side*.898,.018,1.48),(.041,.237,.293),mint)
 oval('Ear '+label+' outer plate',(side*.923,.018,1.48),(.038,.216,.268),pearl)

# Broad smooth arc, using one mesh instead of bead-like segments.
vertices=[];normals=[];faces=[];steps=128;sides=24
for j in range(steps+1):
 a=math.pi*j/steps;center=Vector((.855*math.cos(a),.045,1.68+.790*math.sin(a)))
 normal=Vector((math.cos(a)/.855,0,math.sin(a)/.790)).normalized()
 for i in range(sides):
  t=2*math.pi*i/sides
  p=center+normal*(.056*math.cos(t))+Vector((0,.115*math.sin(t),0));vertices.append(tuple(p))
for j in range(steps):
 for i in range(sides):
  n=(i+1)%sides;faces.append((j*sides+i,(j+1)*sides+i,(j+1)*sides+n,j*sides+n))
mesh=bpy.data.meshes.new('Continuous headphone band');mesh.from_pydata(vertices,[],faces);mesh.update()
band=bpy.data.objects.new('Headphone band',mesh);collection.objects.link(band);band.parent=root;band.data.materials.append(pearl)
for p in mesh.polygons:p.use_smooth=True
# Subtle mint accent along rear edge of the arc.
tube('Mint band piping',[(.855*math.cos(math.pi*i/32),.122,1.68+.79*math.sin(math.pi*i/32)) for i in range(33)],.013,mint)

# Curved eye surfaces use approved PNG iris detail, preserving teal/violet.
for side,label in [(-1,'Left'),(1,'Right')]:
 vertices=[(side*.263,-.560,1.50)];uvs=[(.5,.5)];faces=[];rings=16;segments=96
 for j in range(1,rings+1):
  r=j/rings
  for i in range(segments):
   a=2*math.pi*i/segments;x=r*math.cos(a);z=r*math.sin(a)
   vertices.append((side*.263+x*.192,-.529-.031*math.sqrt(max(0,1-r*r)),1.50+z*.200));uvs.append(((x+1)/2,(z+1)/2))
 for i in range(segments):faces.append((0,1+i,1+(i+1)%segments))
 for j in range(rings-1):
  a=1+j*segments;b=a+segments
  for i in range(segments):n=(i+1)%segments;faces.append((a+i,b+i,b+n,a+n))
 mesh=bpy.data.meshes.new(label+' iris cap');mesh.from_pydata(vertices,[],faces);mesh.update();layer=mesh.uv_layers.new()
 for polygon in mesh.polygons:
  polygon.use_smooth=True
  for loop in polygon.loop_indices:layer.data[loop].uv=uvs[mesh.loops[loop].vertex_index]
 obj=bpy.data.objects.new(label+' eye',mesh);collection.objects.link(obj);obj.parent=root
 eye=bpy.data.materials.new(label+' approved iris');eye.use_nodes=True
 bs=eye.node_tree.nodes['Principled BSDF'];tex=eye.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ROOT/f'Resources/MascotActivities/Eye{label}.png'));tex.image.pack()
 bs.inputs['Base Color'].default_value=(0,0,0,1);eye.node_tree.links.new(tex.outputs['Alpha'],bs.inputs['Alpha'])
 bs.inputs['Roughness'].default_value=.38;bs.inputs['Coat Weight'].default_value=.04
 bs.inputs['Specular IOR Level'].default_value=.08
 eye.node_tree.links.new(tex.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=1
 eye.surface_render_method='DITHERED';obj.data.materials.append(eye)

# A small curved smile follows the ceramic face instead of floating in front.
smile_material=material('Soft plum smile',(.24,.22,.34),.5,0,.02)
smile_points=[]
for i in range(17):
 x=-.105+.210*i/16
 z=1.215+.040*(x/.105)**2
 # Match the superellipsoid panel depth at each point.
 lat=math.asin(abs((z-1.47)/.402)**(1/.94))
 width=.644*math.cos(lat)**.94
 depth=.112*math.cos(lat)**.94*(1-(abs(x)/width)**(2/.94))**(.94/2)
 smile_points.append((x,-.407-depth-.004,z))
tube('Gentle smile',smile_points,.009,smile_material)
for label,point in [('Left',smile_points[0]),('Right',smile_points[-1])]:
 oval(label+' smile rounded tip',point,(.009,.009,.009),smile_material)

# Compact body, raised rounded hands and concealed leg joints match PNG pose.
oval('Neck',(0,.015,.977),(.115,.115,.045),pearl)
superoval('Torso',(0,.035,.655),(.35,.245,.325),pearl,.88)
for side,label in [(-1,'Left'),(1,'Right')]:
 # Fuse the palm, wrist and thumb into a soft mitten with no ball joints.
 parts=[oval(label+' shoulder',(side*.275,.018,.815),(.122,.132,.125),pearl),
        oval(label+' forearm',(side*.31,-.105,.795),(.112,.175,.115),pearl),
        oval(label+' palm',(side*.305,-.265,.805),(.139,.128,.155),pearl),
        oval(label+' thumb',(side*.217,-.267,.852),(.065,.077,.088),pearl)]
 parts[2].rotation_euler.y=side*-.28
 bpy.ops.object.select_all(action='DESELECT')
 for part in parts:part.select_set(True)
 bpy.context.view_layer.objects.active=parts[2]
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 bpy.ops.object.join();hand=bpy.context.object;hand.name=label+' smooth mitten arm'
 remesh=hand.modifiers.new('Continuous mitten surface','REMESH');remesh.mode='VOXEL';remesh.voxel_size=.009
 bpy.ops.object.modifier_apply(modifier=remesh.name)
 smooth=hand.modifiers.new('Soft palm transitions','SMOOTH');smooth.factor=.8;smooth.iterations=8
 bpy.ops.object.modifier_apply(modifier=smooth.name)
 subdivision=hand.modifiers.new('Silky hand curvature','SUBSURF');subdivision.levels=1
 bpy.ops.object.modifier_apply(modifier=subdivision.name)
 for polygon in hand.data.polygons:polygon.use_smooth=True
 # Large single leg shells hide knee joints in this standing pose.
 leg=oval(label+' leg shell',(side*.175,.020,.26),(.135,.15,.18),pearl);leg.rotation_euler.y=side*-.10
 for vertex in leg.data.vertices:
  if vertex.co.z < -.2: vertex.co.y -= .22*((-vertex.co.z-.2)/.8)**2

# Named pose pivots reserved for rigging after silhouette approval.
for name,position in [('HeadPivot',(0,0,.94)),('LeftShoulder',(-.28,0,.83)),('RightShoulder',(.28,0,.83)),('LeftHip',(-.185,0,.48)),('RightHip',(.185,0,.48))]:
 pivot=bpy.data.objects.new(name,None);collection.objects.link(pivot);pivot.parent=root;pivot.location=position;pivot.empty_display_size=.06

# Reference is embedded in the .blend for manual comparison.
reference=bpy.data.images.load(str(ROOT/'Resources/Mascot3D.png'));reference.pack()
reference_empty=bpy.data.objects.new('Approved PNG reference',None);scene.collection.objects.link(reference_empty);reference_empty.empty_display_type='IMAGE';reference_empty.data=reference;reference_empty.location=(3,0,1.25);reference_empty.empty_display_size=2.5;reference_empty.hide_render=True

def point_at(obj,target):obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(0,-7,1.30));camera=bpy.context.object;camera.name='Front reference camera';camera.data.type='ORTHO';camera.data.ortho_scale=2.66;point_at(camera,(0,0,1.26));scene.camera=camera

def light(name,location,power,size,color,target=(0,0,1.2)):
 bpy.ops.object.light_add(type='AREA',location=location);obj=bpy.context.object;obj.name=name;obj.data.energy=power;obj.data.shape='DISK';obj.data.size=size;obj.data.color=color;point_at(obj,target)
light('Large softbox key',(-3,-4,5),140,4,(1,.96,.92))
light('Cool fill',(3,-2,3),80,3,(.83,.93,1))
light('Lower front fill',(0,-4,.75),60,3,(.95,.98,1),target=(0,0,.65))
light('Pearl rim',(0,2,4),120,3,(.87,1,.98))

# Save editable source with textures packed, then export only model geometry.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'TransToolsMascot.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in collection.objects:
 if obj.type=='CURVE':obj.select_set(True);bpy.context.view_layer.objects.active=obj
if bpy.context.selected_objects:bpy.ops.object.convert(target='MESH')
bpy.ops.object.select_all(action='DESELECT')
for obj in collection.objects:obj.select_set(True)
scene.world=None
# Portable USD uses ordinary diffuse texture binding for the iris. RealityKit's
# review view replaces it with UnlitMaterial to preserve approved baked detail.
for label in ['Left','Right']:
 mat=bpy.data.materials[label+' approved iris'];bs=mat.node_tree.nodes['Principled BSDF'];tex=next(n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE')
 mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);bs.inputs['Emission Strength'].default_value=0
try:
 bpy.ops.wm.usd_export(filepath=str(ROOT/'Resources/MascotModel/TransToolsMascot.usdz'),selected_objects_only=True,export_materials=True,export_textures=True,convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y')
except Exception as error:
 (OUT/'export-error.txt').write_text(str(error))
 bpy.ops.wm.usd_export(filepath=str(OUT/'TransToolsMascot.usdc'),selected_objects_only=True,export_materials=True,export_textures=True,convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y')
for label in ['Left','Right']:
 mat=bpy.data.materials[label+' approved iris'];bs=mat.node_tree.nodes['Principled BSDF']
 for link in list(bs.inputs['Base Color'].links):mat.node_tree.links.remove(link)
 bs.inputs['Base Color'].default_value=(0,0,0,1);bs.inputs['Emission Strength'].default_value=1
scene.world=world
scene.render.filepath=str(RENDERS/'front.png');bpy.ops.render.render(write_still=True)
if '--draft' not in sys.argv:
 for name,location in [('front_right',(4,-7,1.4)),('right',(7,0,1.4)),('back',(0,7,1.4))]:
  camera.location=location;point_at(camera,(0,0,1.26));scene.render.filepath=str(RENDERS/f'{name}.png');bpy.ops.render.render(write_still=True)
print('Saved editable Blender model, USD export and render previews')
