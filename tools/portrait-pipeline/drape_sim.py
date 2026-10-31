# Toga and palla draped by Blender's cloth simulation over the MakeHuman base
# body and the draped tunic (tunic_sim.py's OBJ as a second collider).
#   toga:  the band (balteus) from the right hip across the chest over the
#          left shoulder and down the back, gathered at both ends, so that
#          the slack in between falls in folds along the band; the left
#          shoulder and upper arm under the cloth
#   palla: a mantle round the shoulders and back, open in front, falling in
#          folds (the women's mantle over the tunic)
# usage: venv/bin/python drape_sim.py base.obj tunic.obj kind out.obj [frames]
import sys, math, os
import bpy, bmesh
import numpy as np
base, tunic, kind, outp, frames = sys.argv[-5], sys.argv[-4], sys.argv[-3], sys.argv[-2], int(sys.argv[-1])
BEND = float(os.environ.get('BEND', '1.5')); LOOSE = float(os.environ.get('LOOSE', '0.5'))
FRIC = float(os.environ.get('FRIC', '1.0'))
# the portrait shows the body down to about y 4.6: the cloth only down to YMIN,
# its lowest ring held there (the cloth goes on below)
YMIN = float(os.environ.get('YMIN', '2.6')); VY0 = float(os.environ.get('VY0', '4.3')); GATHER = float(os.environ.get('GATHER', '0.6'))
vs, faces, g = [], {}, None
for l in open(base):
    if l.startswith('v '):
        vs.append([float(t) for t in l.split()[1:4]])
    elif l.startswith('g '):
        g = l.split()[1]
    elif l.startswith('f '):
        faces.setdefault(g, []).append([int(t.split('/')[0]) - 1 for t in l.split()[1:]])
V = np.array(vs)
S = 0.1
body = [f for f in faces['body'] if all(V[i][1] > 1.2 and abs(V[i][0]) < 3.6 for i in f)]

def neck_ok(c, lift=0.0):
    x, y, z = c
    if y > 6.3:
        return False
    t = abs(math.atan2(x, z - 0.45)) / math.pi
    front = z > 0.25
    return y < (5.5 + lift + (5.9 - 5.5) * min(1, t * 1.6)) - 0.12 * max(0, 1 - abs(x) / 0.6) * (1 if front else 0)

# the toga's band: the line from the left shoulder (x > 0 is the body's left)
# down across the chest to the right hip, in front and (mirrored) at the back
# (in toga busts the band's upper edge runs from the left shoulder by the neck
# to under the right arm, so it crosses the upper chest)
_b = [float(t) for t in os.environ.get('BAND', '1.25,5.5,-1.95,-1.8').split(',')]
L0 = np.array(_b[:2]); LD = np.array(_b[2:]); LD = LD / np.linalg.norm(LD)
TEND = float(os.environ.get('TEND', '3.9'))
def band(c):
    q = np.array([c[0], c[1]]) - L0
    t = q @ LD
    d = abs(q[0] * LD[1] - q[1] * LD[0])
    return t, d

def region(c):
    x, y, z = c
    if kind == 'toga':
        if not neck_ok(c, 0.05) or y < YMIN:
            return False
        if x > 0.55 and y > 4.2:      # over the left shoulder and upper arm
            return True
        if z > -0.3 and x > 0.3:      # the first end, hanging down in front on the left
            return True
        t, d = band(c)
        return -0.2 < t < TEND and d < (0.75 if z > -0.3 else 1.1)
    elif kind == 'veil':
        # over the head and onto the shoulders, open for the face and in front
        # of the neck and chest
        if y < VY0 or abs(x) > 2.0:
            return False
        if y > 6.05 and y < 7.95 and z > 0.5 and abs(x) < 0.68:   # the face
            return False
        if y <= 6.05 and z > 0.1 and abs(x) < 0.68:               # neck and chest
            return False
        return True
    else:
        if not neck_ok(c, 0.05) or y < YMIN:
            return False
        # (not round the arms: there the cloth crumpled on the tunic's sleeves)
        return not (z > 0.2 and abs(x) < float(os.environ.get('OPEN', '0.8'))) and abs(x) < 2.1

# (the tights helper covers the arms too: the toga takes the left upper arm)
src = 'body' if kind == 'veil' else 'helper-tights'
cl = [f for f in faces[src] if all(region(V[i]) and abs(V[i][0]) < 3.0 for i in f)]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def make(name, P, fl):
    me = bpy.data.meshes.new(name)
    me.from_pydata((np.stack([P[:, 0], -P[:, 2], P[:, 1]], -1) * S).tolist(), [], fl)
    me.update()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    return ob

def sub(fl):
    used = sorted({i for f in fl for i in f}); rm = {o: k for k, o in enumerate(used)}
    return used, [[rm[i] for i in f] for f in fl]

# collider: the body with the chest smoothed (as tunic_sim.py)
V0 = V.copy()
nb = {}
for f in body:
    for k in range(len(f)):
        nb.setdefault(f[k], set()).update((f[k - 1], f[(k + 1) % len(f)]))
chest = [i for i in nb if abs(V[i][0]) < 1.3 and 3.6 < V[i][1] < 5.2 and V[i][2] > 0.3]
for _ in range(25):
    Vn = V.copy()
    for i in chest:
        Vn[i] = 0.5 * V[i] + 0.5 * V[list(nb[i])].mean(0)
    V = Vn
used, fl = sub(body)
bo = make('body', V[used], fl)
V = V0
bo.modifiers.new('col', 'COLLISION')
bo.collision.cloth_friction = FRIC
bo.collision.thickness_outer = 0.009
# the tunic underneath as a second collider
tv, tf = [], []
for l in open(tunic):
    if l.startswith('v '):
        tv.append([float(t) for t in l.split()[1:4]])
    elif l.startswith('f '):
        tf.append([int(t) - 1 for t in l.split()[1:]])
tu = make('tunic', np.array(tv), tf)
from mathutils.bvhtree import BVHTree
from mathutils import Vector
# the tunic's crumples would catch the cloth: the collider is instead the body
# grown over the tunic (per body vertex the tunic's distance along the normal,
# spread to the neighbours and smoothed), a calm hull round body and tunic
from mathutils.bvhtree import BVHTree
from mathutils import Vector
tbv = BVHTree.FromObject(tu, bpy.context.evaluated_depsgraph_get())
HULL = os.environ.get('HULL', '0') == '1'
if not HULL:
    tu.modifiers.new('col', 'COLLISION')
    tu.collision.cloth_friction = FRIC
    tu.collision.thickness_outer = 0.006
bme = bo.data
nbv = np.zeros((len(bme.vertices), 3)); bme.vertices.foreach_get('normal', nbv.ravel())
pbv = np.zeros((len(bme.vertices), 3)); bme.vertices.foreach_get('co', pbv.ravel())
dd = np.zeros(len(pbv))
for i in range(len(pbv)):
    h = tbv.ray_cast(Vector(pbv[i]), Vector(nbv[i]), 0.25)
    if h[0] is not None:
        dd[i] = h[3]
adj = [set() for _ in range(len(pbv))]
for e in bme.edges:
    a_, b_ = e.vertices
    adj[a_].add(b_); adj[b_].add(a_)
adjl = [np.array(sorted(a_)) if a_ else np.array([i]) for i, a_ in enumerate(adj)]
for _ in range(3):
    dd = np.array([max(dd[i], dd[adjl[i]].max()) for i in range(len(dd))])
for _ in range(4):
    dd = 0.5 * dd + 0.5 * np.array([dd[a_].mean() for a_ in adjl])
if HULL:
    bme.vertices.foreach_set('co', (pbv + nbv * (dd[:, None] + 0.004)).ravel()); bme.update()
print('hull: tunic over the body up to', round(dd.max() / S, 2), 'units')

if kind == 'veil':
    # the veil as a regular grid round the head's centre: rays from there to
    # the body (head, neck, shoulders), open for the face and the front of the
    # neck and chest (the body's own head mesh has ears and lids that tore the
    # cloth into spikes)
    hb = BVHTree.FromObject(bo, bpy.context.evaluated_depsgraph_get())
    C = np.array([0.0, 6.95, 0.2])
    rows, gp, fl = [], [], []
    NPH = 96
    ths = np.arange(84.0, -56.0, -2.5)
    idx = {}
    for r_, th in enumerate(ths):
        for k in range(NPH):
            ph = 360.0 * k / NPH - 180.0    # 0 in front
            if abs(ph) < 42 and th < 38:
                continue                     # the face and the neck in front
            t_, p_ = math.radians(th), math.radians(ph)
            d = np.array([math.cos(t_) * math.sin(p_), math.sin(t_), math.cos(t_) * math.cos(p_)])
            o_ = Vector(np.array([C[0], -C[2], C[1]]) * S); dv = Vector([d[0], -d[2], d[1]])
            h = hb.ray_cast(o_, dv, 1.0)
            if h[0] is None:
                continue
            q = np.array(h[0]) / S
            idx[(r_, k)] = len(gp)
            gp.append([q[0], q[2], -q[1]])
            rows.append(h[3] / S)
    # below the last ring of rays the cloth goes on as a skirt, a little
    # outwards and down, to fall onto the shoulders in the simulation
    R = len(ths) - 1
    for j in range(1, int(os.environ.get('SKIRT', '6')) + 1):
        for k in range(NPH):
            if (R + j - 1, k) not in idx:
                continue
            ph = math.radians(360.0 * k / NPH - 180.0)
            q = np.array(gp[idx[(R + j - 1, k)]]) + np.array([0.12 * math.sin(ph), -0.28, 0.12 * math.cos(ph)])
            idx[(R + j, k)] = len(gp)
            gp.append(list(q))
    for (r_, k), i in idx.items():
        a_, b_, c_ = idx.get((r_, (k + 1) % NPH)), idx.get((r_ + 1, k)), idx.get((r_ + 1, (k + 1) % NPH))
        if a_ is not None and b_ is not None and c_ is not None:
            fl += [[i, b_, c_], [i, c_, a_]]
    # the crown closed by a fan
    gp.append(list(C + np.array([0.0, 1.6, -0.1]))); top = len(gp) - 1
    for k in range(NPH):
        a_, b_ = idx.get((0, k)), idx.get((0, (k + 1) % NPH))
        if a_ is not None and b_ is not None:
            fl.append([top, a_, b_])
    GP = np.array(gp)
    # the crown point on the head
    hh = hb.ray_cast(Vector(np.array([C[0], -C[2], C[1]]) * S), Vector([0, 0.06, 1]), 1.0)
    if hh[0] is not None:
        q = np.array(hh[0]) / S; GP[top] = [q[0], q[2], -q[1]]
    to = make('drape', GP, fl)
    print('veil grid', len(GP), len(fl))
else:
    used, fl = sub(cl)
    to = make('drape', V[used], fl)
me = to.data
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
if kind != 'veil':
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True, smooth=0.5)
bmesh.ops.triangulate(bm, faces=bm.faces[:])
inner = [v for v in bm.verts if not v.is_boundary]
for _ in range(10):
    bmesh.ops.smooth_vert(bm, verts=inner, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
bm.to_mesh(me); bm.free(); me.update()
n = np.zeros((len(me.vertices), 3)); me.vertices.foreach_get('normal', n.ravel())
P = np.zeros((len(me.vertices), 3)); me.vertices.foreach_get('co', P.ravel())
B = np.stack([P[:, 0], P[:, 2], -P[:, 1]], -1) / S   # back in base units
if kind == 'toga':
    # standing off the tunic, more in the band's middle (the slack)
    tb = np.array([band(c)[0] for c in B])
    mid = np.clip(1 - np.abs(tb - TEND / 2) / (TEND / 2), 0, 1)
    off = (0.16 + LOOSE * mid) * S
elif kind == 'veil':
    # close over the flat hair on the head, looser down the sides
    off = (0.1 + LOOSE * np.clip((7.6 - B[:, 1]) / 1.8, 0, 1) - 0.4 * LOOSE * np.clip((5.6 - B[:, 1]) / 1.0, 0, 1)) * S
else:
    off = (0.15 + LOOSE * np.clip((5.4 - B[:, 1]) / 1.4, 0, 1)) * S
# start outside the tunic: where a ray along the normal meets the tunic, at
# least a little beyond it (collisions only keep the cloth from crossing)
hbv = BVHTree.FromObject(bo, bpy.context.evaluated_depsgraph_get()) if HULL else tbv
for i in range(len(P)):
    hit = hbv.ray_cast(Vector(P[i]), Vector(n[i]), 0.25)
    if hit[0] is not None:
        off[i] = max(off[i], hit[3] + 0.04 * S)
P1 = P + n * off[:, None]
me.vertices.foreach_set('co', P1.ravel()); me.update()
# gathering: the band's lower ends drawn together towards the line over the
# first frames and held there (tucked under the belt, or held on the arm)
to.shape_key_add(name='Basis')
G = P1.copy()
pin = np.zeros(len(P), bool)
if kind == 'toga':
    for i, c in enumerate(B):
        t, d = band(c)
        if c[1] < YMIN + 0.35 and (c[0] > 0.3 or c[2] < -0.3 or YMIN > 3.0):
            pin[i] = True   # the cloth goes on below the cut: held there
        if c[1] > 5.5 and 0.75 < c[0] < 2.0:
            pin[i] = True   # resting on the shoulder (its weight on both sides),
            # gathered there into a narrower width, so that folds fan out below
            SG = float(os.environ.get('SGATHER', '0.0'))
            G[i, 0] = (1.35 + (c[0] - 1.35) * (1 - SG)) * S
        if t > TEND - 0.5 and c[0] < -0.9 and c[2] > -0.3:
            q = np.array([c[0], c[1]]) - L0
            on = L0 + LD * t
            k = GATHER
            G[i, 0] = (c[0] + (on[0] - c[0]) * k) * S
            G[i, 2] = (c[1] + (on[1] - c[1]) * k) * S
            pin[i] = True
elif kind == 'veil':
    pin = (B[:, 1] > 8.05) | (B[:, 1] < VY0 + 0.2)
else:
    pin = B[:, 1] < YMIN + 0.25
    # resting on both shoulders
    pin |= (B[:, 1] > 5.5) & (np.abs(B[:, 0]) > 0.75) & (np.abs(B[:, 0]) < 1.9)
kb = to.shape_key_add(name='gather')
kb.data.foreach_set('co', G.ravel())
kb.value = 0.0; kb.keyframe_insert('value', frame=1)
kb.value = 1.0; kb.keyframe_insert('value', frame=20)
vg = to.vertex_groups.new(name='pin')
vg.add([int(i) for i in np.where(pin)[0]], 1.0, 'REPLACE')
print('drape verts', len(P), 'pinned', int(pin.sum()))
cm = to.modifiers.new('cloth', 'CLOTH')
s = cm.settings
s.vertex_group_mass = 'pin'
s.quality = 8
s.mass = float(os.environ.get('MASS', '0.45'))
s.tension_stiffness = float(os.environ.get('TENS', '30')); s.compression_stiffness = 60; s.shear_stiffness = 10
s.bending_stiffness = BEND
s.air_damping = 1.0
cm.collision_settings.use_collision = True
cm.collision_settings.distance_min = 0.003
cm.collision_settings.use_self_collision = True
cm.collision_settings.self_distance_min = 0.002
cm.point_cache.frame_end = frames
sc.frame_start, sc.frame_end = 1, frames
for f in range(1, frames + 1):
    sc.frame_set(f)
dg = bpy.context.evaluated_depsgraph_get()
m2 = to.evaluated_get(dg).to_mesh()
# where the tunic still pokes through (or lies closer than 3 mm), the cloth is
# lifted off it along its normal
Q = np.zeros((len(m2.vertices), 3)); m2.vertices.foreach_get('co', Q.ravel())
Nq = np.zeros((len(m2.vertices), 3)); m2.vertices.foreach_get('normal', Nq.ravel())
lifted = 0
for i in range(len(Q)):
    # the cloth's normals point outward (as the helper's): the tunic between 3 mm
    # under the cloth and 4 cm over it
    nn = Nq[i]
    h = tbv.ray_cast(Vector(Q[i] - nn * 0.003), Vector(nn), 0.043)
    if h[0] is not None:
        Q[i] = np.array(h[0]) + nn * 0.003
        lifted += 1
print('lifted off the tunic', lifted)
with open(outp, 'w') as fo:
    for v in Q:
        fo.write('v %.5f %.5f %.5f\n' % (v[0] / S, v[2] / S, -v[1] / S))
    for p in m2.polygons:
        fo.write('f ' + ' '.join(str(i + 1) for i in p.vertices) + '\n')
print(kind, 'verts', len(m2.vertices), 'faces', len(m2.polygons))
