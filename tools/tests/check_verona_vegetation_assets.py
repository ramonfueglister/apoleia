"""Independent GLB geometry audit for Blender-authored Verona vegetation.

Run: build/verona-venv/bin/python tools/tests/check_verona_vegetation_assets.py
Checks actual exported buffers, not generator metadata. Does not establish
in-game placement or visual quality; the renderer checks cover those separately.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from check_verona_bridge_assets import read_glb, accessor, primitives, lod_triangles, require

ROOT = Path(__file__).resolve().parents[2]
SLUGS = ('oak', 'cypress', 'stone_pine', 'olive', 'willow', 'shrub', 'reeds', 'courtyard_planter')
TREE_CAPS = {'oak':8.1, 'cypress':8.1, 'stone_pine':8.1, 'olive':6.1, 'willow':8.1}
TAGS = ('detail','medium','far')


def silhouette(triangles, bounds, axes, size=48):
    """Orthographic triangle coverage on a fixed common grid, no renderer."""
    low, high = bounds
    extent = high[list(axes)] - low[list(axes)]
    points = low[list(axes)] + (np.stack(np.meshgrid(np.arange(size)+.5, np.arange(size)+.5), axis=-1).reshape(-1,2) / size) * extent
    covered = np.zeros(size*size, dtype=bool)
    for tri in triangles[:,:,list(axes)]:
        a,b,c = tri
        e0, e1 = b-a, c-a
        det = e0[0]*e1[1]-e0[1]*e1[0]
        if abs(det)<1e-10: continue
        candidate = (~covered & np.all(points >= tri.min(axis=0),axis=1) & np.all(points <= tri.max(axis=0),axis=1))
        ids=np.flatnonzero(candidate)
        p=points[ids]-a
        u=(p[:,0]*e1[1]-p[:,1]*e1[0])/det
        v=(e0[0]*p[:,1]-e0[1]*p[:,0])/det
        covered[ids[(u>=0)&(v>=0)&(u+v<=1)]]=True
    return covered


def audit(slug):
    path=ROOT/'app/assets/vegetation'/slug/(slug+'.glb')
    document,binary=read_glb(path)
    require(not document.get('textures'), f'{slug}: textures violate single-surface color batching contract')
    require(len(document.get('materials',[]))==1, f'{slug}: expected one material')
    material=document['materials'][0]
    require(material.get('alphaMode','OPAQUE')=='OPAQUE', f'{slug}: alpha sorting must not be necessary')
    lods=[]; meshes=[]
    for tag in TAGS:
        node=next(i for i,n in enumerate(document['nodes']) if n.get('name')=='Model_'+tag)
        parts=list(primitives(document,node))
        require(len(parts)==1,f'{slug}/{tag}: expected one batchable surface')
        part=parts[0]
        require('COLOR_0' in part['attributes'],f'{slug}/{tag}: missing vertex colours')
        colour=accessor(document,binary,part['attributes']['COLOR_0'])
        require(np.unique(colour[:,:3],axis=0).shape[0]>=3, f'{slug}/{tag}: lost material colour distinctions')
        normals=accessor(document,binary,part['attributes']['NORMAL'])
        require(np.allclose(np.linalg.norm(normals,axis=1),1,atol=.005), f'{slug}/{tag}: nonunit normals')
        mesh=lod_triangles(document,binary,tag)
        areas=np.linalg.norm(np.cross(mesh[:,1]-mesh[:,0],mesh[:,2]-mesh[:,0]),axis=1)*.5
        require(np.all(areas>1e-9),f'{slug}/{tag}: degenerate triangles ({int((areas<=1e-9).sum())})')
        low=mesh.min(axis=(0,1)); high=mesh.max(axis=(0,1)); span=high-low
        require(abs(low[2])<.035,f'{slug}/{tag}: base is not authored at ground')
        require(np.all(span>.05),f'{slug}/{tag}: collapsed axis')
        if slug in TREE_CAPS:
            require(4.0<=high[2]<=TREE_CAPS[slug],f'{slug}/{tag}: wrong tree height {high[2]}')
            require(max(span[:2])<12.0,f'{slug}/{tag}: excessive crown spread')
        else:
            require(high[2]<4.0,f'{slug}/{tag}: decorative vegetation exceeds intended scale')
        require(len(mesh)<16000,f'{slug}/{tag}: excessive per-instance triangle cost')
        if tag=='far': require(len(mesh)<2000,f'{slug}: far mesh too expensive')
        lods.append({'lod':tag,'triangles':len(mesh),'bounds_min_xyz_m':low.tolist(),'bounds_max_xyz_m':high.tolist()})
        meshes.append(mesh)
    counts=[len(m) for m in meshes]
    require(counts[0]>counts[1]>counts[2],f'{slug}: LODs do not reduce triangle cost {counts}')
    low=meshes[0].min(axis=(0,1)); high=meshes[0].max(axis=(0,1))
    coverage=[]
    for axes in ((0,2),(1,2),(0,1)):
        base=silhouette(meshes[0],(low,high),axes)
        for tag,mesh in zip(TAGS[1:],meshes[1:]):
            mask=silhouette(mesh,(low,high),axes)
            score=float((base&mask).sum()/max(1,(base|mask).sum()))
            require(score>=.55,f'{slug}/{tag}: silhouette changed excessively on axes{axes}: {score:.3f}')
            coverage.append({'lod':tag,'axes':axes,'intersection_over_union':score})
    return {'asset':slug,'lods':lods,'silhouette_checks':coverage}


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,default=ROOT/'build/verona-vegetation/asset-validation.json');args=parser.parse_args()
    report={'test':'verona_vegetation_assets','assets':[],'failures':[]}
    for slug in SLUGS:
        try: report['assets'].append(audit(slug))
        except Exception as error: report['failures'].append(f'{slug}: {error}')
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'assets_checked':len(report['assets']),'failures':report['failures'],'report':str(args.output)}))
    return bool(report['failures'])

if __name__=='__main__': raise SystemExit(main())
