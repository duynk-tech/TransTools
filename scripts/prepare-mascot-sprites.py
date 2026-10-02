"""Build the approved 8-direction / 8-frame 2D mascot sprite pack.

AI masters: work/mascot-sprites/masters. Uses the existing magenta matte pipeline.
Mirrored left-facing sprites are intended for UI animation, not ML training samples.
"""
from pathlib import Path
import json
import runpy
import hashlib
import numpy as np
import cv2
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


def interpolate_cycle(keyframes, subdivisions=4):
    """Bidirectional optical-flow interpolation of premultiplied RGBA.

    Include last-to-first interpolation so the loop has no hard seam.
    Motion estimation uses an opaque dark composite at half resolution.
    """
    dense = []
    estimator = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    estimator.setFinestScale(0)
    estimator.setGradientDescentIterations(64)
    estimator.setVariationalRefinementIterations(10)
    for index, first in enumerate(keyframes):
        second = keyframes[(index + 1) % len(keyframes)]
        a = np.asarray(first, dtype=np.float32) / 255
        b = np.asarray(second, dtype=np.float32) / 255
        def gray(rgba):
            rgb = rgba[:, :, :3] * rgba[:, :, 3:] + (1-rgba[:, :, 3:]) * np.array([0.086,0.149,0.22])
            small = cv2.resize((rgb*255).astype(np.uint8), (310,391))
            mask = (cv2.resize(rgba[:, :, 3], (310,391)) > 0.5).astype(np.uint8)
            field = cv2.distanceTransform(mask, cv2.DIST_L2, 5) - cv2.distanceTransform(1-mask, cv2.DIST_L2, 5)
            shape = np.clip(128 + field*3, 0, 255)
            return (0.3*cv2.cvtColor(small, cv2.COLOR_RGB2GRAY) + 0.7*shape).astype(np.uint8)
        ga, gb = gray(a), gray(b)
        forward = estimator.calc(ga, gb, None)
        backward = estimator.calc(gb, ga, None)
        def full(flow):
            result = cv2.resize(flow, SIZE)
            result[:, :, 0] *= SIZE[0]/310
            result[:, :, 1] *= SIZE[1]/391
            return result
        forward, backward = full(forward), full(backward)
        def signed_distance(alpha):
            mask = (alpha > 0.5).astype(np.uint8)
            return cv2.distanceTransform(mask, cv2.DIST_L2, 5) - cv2.distanceTransform(1-mask, cv2.DIST_L2, 5)
        da, db = signed_distance(a[:, :, 3]), signed_distance(b[:, :, 3])
        yy, xx = np.mgrid[:SIZE[1], :SIZE[0]].astype(np.float32)
        pa, pb = a.copy(), b.copy()
        pa[:, :, :3] *= pa[:, :, 3:]
        pb[:, :, :3] *= pb[:, :, 3:]
        for step in range(subdivisions):
            if step == 0:
                dense.append(first.copy())
                continue
            t = step/subdivisions
            wa = cv2.remap(pa, xx-t*forward[:, :, 0], yy-t*forward[:, :, 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
            wb = cv2.remap(pb, xx-(1-t)*backward[:, :, 0], yy-(1-t)*backward[:, :, 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
            rgba = wa*(1-t) + wb*t
            rgba[:, :, :3] /= np.maximum(rgba[:, :, 3:], 1/255)
            # Interpolate silhouettes as signed distances to avoid translucent
            # duplicate feet where one leg occludes the other.
            sa = cv2.remap(da, xx-t*forward[:, :, 0], yy-t*forward[:, :, 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=-100)
            sb = cv2.remap(db, xx-(1-t)*backward[:, :, 0], yy-(1-t)*backward[:, :, 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=-100)
            silhouette = sa*(1-t)+sb*t
            mask = (silhouette > 0).astype(np.uint8)
            mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9,9), np.uint8))
            rgba[:, :, 3] = cv2.GaussianBlur(mask.astype(np.float32), (5,5), 0.7)
            rgba[rgba[:, :, 3] < 1/255] = 0
            dense.append(clean(Image.fromarray((np.clip(rgba,0,1)*255).round().astype(np.uint8))))
    return dense


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

    # 5-layer bipedal puppet with synchronized contralateral arm/leg swing
    torso_inpaint = np.array(Image.open(MASTERS/'puppet_torso.png').convert('RGBA'))
    clean_torso = torso_inpaint.copy()

    # Hip sockets contour masking
    for y in range(334, 444):
        for x in range(444):
            if x < 238:
                dx = (x - 206) / 36.0
                dy = (y - 332) / 25.0
                if dx*dx + dy*dy > 1.0 and y > 334:
                    clean_torso[y, x, 3] = 0
                if y >= 357:
                    clean_torso[y, x, 3] = 0
            else:
                if y >= 358:
                    clean_torso[y, x, 3] = 0

    # Leg sprite with ball joint
    cut1 = HELPERS['chroma_cutout'](ROOT/'work/mascot-sprites/cell-01.png')
    arr1 = np.array(cut1.resize((444, 444), RESAMPLE))
    cx_hip, cy_hip = 216, 348
    M_vert = cv2.getRotationMatrix2D((cx_hip, cy_hip), -11.3, 1.0)
    arr_vert = cv2.warpAffine(arr1, M_vert, (444, 444), flags=cv2.INTER_LANCZOS4)
    r = 21
    leg_sym = np.zeros_like(arr_vert)
    for y in range(cy_hip - r, 438):
        for x in range(cx_hip - 24, cx_hip + 50):
            dx = x - cx_hip
            dy = y - cy_hip
            d2 = dx*dx + dy*dy
            if y < cy_hip:
                if d2 <= r*r:
                    leg_sym[y, x] = arr_vert[y, x]
            elif y < 400:
                if abs(dx) <= 22:
                    leg_sym[y, x] = arr_vert[y, x]
            else:
                if dx >= -22 and dx <= 46:
                    leg_sym[y, x] = arr_vert[y, x]

    # Arm sprite on 444x444 canvas
    arm_cutout = np.array(Image.open(MASTERS/'puppet_arm.png').convert('RGBA'))
    arm_canvas = np.zeros((444, 444, 4), dtype=np.uint8)
    arm_canvas[245:245+arm_cutout.shape[0], 190:190+arm_cutout.shape[1]] = arm_cutout

    # Dynamic contralateral angles (opposite arm swings opposite to leg)
    angles_leg_near = [24.0, 8.0, -6.0, -22.0, -14.0, 2.0, 16.0, 22.0]
    angles_arm_near = [-30.0, -12.0, 10.0, 32.0, 18.0, -4.0, -22.0, -28.0]

    scale = 750.0 / 412.0
    center_x = 213.0
    w_new = round(444 * scale)
    h_new = round(444 * scale)
    paste_x = round(SIZE[0] / 2.0 - center_x * scale)
    paste_y = round(18.0 - 18.0 * scale)

    keyframes = []
    for i in range(8):
        ang_ln = angles_leg_near[i]
        ang_lf = angles_leg_near[(i + 4) % 8]
        ang_an = angles_arm_near[i]
        ang_af = angles_arm_near[(i + 4) % 8]

        bob = int(round(-abs(np.sin(i * np.pi / 4.0)) * 3.5))

        p_sn = (213, 271 + bob)
        p_sf = (187, 263 + bob)
        p_hn = (216, 348 + bob)
        p_hf = (186, 340 + bob)

        # 1. Far Arm (in background)
        M_af = cv2.getRotationMatrix2D((213, 271), ang_af, 0.92)
        rot_af_temp = cv2.warpAffine(arm_canvas, M_af, (444, 444), flags=cv2.INTER_LANCZOS4)
        dx_af = p_sf[0] - 213
        dy_af = p_sf[1] - 271
        M_af_shift = np.float32([[1, 0, dx_af], [0, 1, dy_af]])
        rot_af = cv2.warpAffine(rot_af_temp, M_af_shift, (444, 444), flags=cv2.INTER_LANCZOS4)
        rot_af[:, :, :3] = (rot_af[:, :, :3] * 0.84).astype(np.uint8)

        # 2. Far Leg (in background)
        M_lf = cv2.getRotationMatrix2D((216, 348), ang_lf, 0.94)
        rot_lf_temp = cv2.warpAffine(leg_sym, M_lf, (444, 444), flags=cv2.INTER_LANCZOS4)
        lift_lf = -round(max(0, -ang_lf) * 0.45)
        dx_lf = p_hf[0] - 216
        dy_lf = p_hf[1] - 348 + lift_lf
        M_lf_shift = np.float32([[1, 0, dx_lf], [0, 1, dy_lf]])
        rot_lf = cv2.warpAffine(rot_lf_temp, M_lf_shift, (444, 444), flags=cv2.INTER_LANCZOS4)
        rot_lf[:, :, :3] = (rot_lf[:, :, :3] * 0.86).astype(np.uint8)

        # 3. Torso bob
        M_bob = np.float32([[1, 0, 0], [0, 1, bob]])
        torso_bob = cv2.warpAffine(clean_torso, M_bob, (444, 444), flags=cv2.INTER_LANCZOS4)

        # 4. Near Leg (foreground)
        M_ln = cv2.getRotationMatrix2D((216, 348), ang_ln, 1.0)
        rot_ln_temp = cv2.warpAffine(leg_sym, M_ln, (444, 444), flags=cv2.INTER_LANCZOS4)
        lift_ln = -round(max(0, -ang_ln) * 0.45)
        dy_ln = bob + lift_ln
        M_ln_shift = np.float32([[1, 0, 0], [0, 1, dy_ln]])
        rot_ln = cv2.warpAffine(rot_ln_temp, M_ln_shift, (444, 444), flags=cv2.INTER_LANCZOS4)

        # 5. Near Arm (in front of torso)
        M_an = cv2.getRotationMatrix2D((213, 271), ang_an, 1.0)
        rot_an_temp = cv2.warpAffine(arm_canvas, M_an, (444, 444), flags=cv2.INTER_LANCZOS4)
        M_an_shift = np.float32([[1, 0, 0], [0, 1, bob]])
        rot_an = cv2.warpAffine(rot_an_temp, M_an_shift, (444, 444), flags=cv2.INTER_LANCZOS4)

        # Composite: Far Arm -> Far Leg -> Torso -> Near Leg -> Near Arm
        comp = Image.new('RGBA', (444, 444), (0, 0, 0, 0))
        comp.paste(Image.fromarray(rot_af), (0, 0), Image.fromarray(rot_af))
        comp.paste(Image.fromarray(rot_lf), (0, 0), Image.fromarray(rot_lf))
        comp.paste(Image.fromarray(torso_bob), (0, 0), Image.fromarray(torso_bob))
        comp.paste(Image.fromarray(rot_ln), (0, 0), Image.fromarray(rot_ln))
        comp.paste(Image.fromarray(rot_an), (0, 0), Image.fromarray(rot_an))

        resized = comp.resize((w_new, h_new), RESAMPLE)
        canvas = Image.new('RGBA', SIZE, (0, 0, 0, 0))
        canvas.paste(resized, (paste_x, paste_y))

        # Clamp to floor baseline 769
        arr_c = np.array(canvas)
        arr_c[770:, :, 3] = 0
        keyframes.append(clean(Image.fromarray(arr_c)))

    frames = interpolate_cycle(keyframes)
    for i in range(len(frames)):
        arr = np.array(frames[i])
        arr[770:, :, 3] = 0
        frames[i] = clean(Image.fromarray(arr))
    for folder in ['walk_right', 'walk_left']:
        for old in (DEST/folder).glob('*.png'):
            old.unlink()
    for i, frame in enumerate(frames):
        frame.save(DEST/'walk_right'/f'walk_right_{i:02d}.png')
        ImageOps.mirror(frame).save(DEST/'walk_left'/f'walk_left_{i:02d}.png')

    names = ['front','front_right','right','back_right','back','back_left','left','front_left']
    contact = Image.new('RGB', (1280, 500), '#162638')
    draw = ImageDraw.Draw(contact)
    for i, name in enumerate(names):
        image = angles[name].copy(); image.thumbnail((145, 200), RESAMPLE)
        x=i*160+(160-image.width)//2
        contact.paste(image, (x, 15), image)
        draw.text((i*160+8, 220), name, fill='#B8C9DE')
    for i, frame in enumerate(keyframes):
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
            ImageDraw.Draw(bg).text((16,270),'TransTools | walk '+facing+' | 32 frames per cycle',fill='#B8C9DE')
            animation.append(bg)
    # Each direction plays three full cycles, then switches.
    sequence = animation[:32]*3+animation[32:]*3
    sequence[0].save(PREVIEW/'mascot-walk-preview.gif', save_all=True, append_images=sequence[1:], duration=[20,30]*96, loop=0, disposal=2)
    manifest={'version':3,'headShape':'smooth rounded oval; no speech-bubble tail or pointed chin','canvas':list(SIZE),'baseline':769,'frameRate':40,'stridePointsAtSize80':26,'playback':'distance driven in Dock; fixed planted-foot baseline','angles':names,
              'walkFramesPerDirection':32,'keyframesPerDirection':8,'interpolation':'bidirectional optical flow, premultiplied alpha','leftViews':'mirrored from right-facing views for UI use',
              'source':'imagegen opaque masters + Python chroma matte and alignment',
              'files':{str(p.relative_to(DEST)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(DEST.rglob('*.png'))}}
    (DEST/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Created 8 directions + 64 walk frames, contact sheet, GIF and manifest.')


if __name__ == '__main__':
    build()
