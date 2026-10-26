#!/usr/bin/env python3
"""Exact fixed-world subset LOD error bounds; no source or height changes."""
import json,math,pathlib,hashlib,argparse
import numpy as np
parser=argparse.ArgumentParser();parser.add_argument('--surface-dir',default='artifacts/render-data/fixed-diorama-v1');args=parser.parse_args();P=pathlib.Path(__file__).resolve().parents[1]/args.surface_dir
if (P/'READY.json').exists() or (P/'chunks.json').exists():raise RuntimeError('refusing to mutate frozen/already derived LOD metadata')
m=json.loads((P/'surface.json').read_text());w,h=m['width'],m['height'];q=np.memmap(P/'height.rg8',dtype=np.uint8,mode='r',shape=(h,w,2));height=(q[...,0].astype(np.float32)*256+q[...,1])*.25-8192
special=set()
for p in m['anchors']:
 ix=int((p['world_x']-m['world_min'][0])/m['world_size'][0]*(w-1));iz=int((p['world_z']-m['world_min'][1])/m['world_size'][1]*(h-1));special.add((ix//128,iz//128))
chunks=[]
for cz in range(math.ceil((h-1)/128)):
 for cx in range(math.ceil((w-1)/128)):
  patch=height[cz*128:min(cz*128+129,h),cx*128:min(cx*128+129,w)];errors=[0.]
  if patch.shape!=(129,129) or (cx,cz) in special:errors += [None]*7
  else:
   z,x=np.mgrid[:129,:129]
   for s in [2,4,8,16,32,64,128]:
    x0=np.minimum(x//s*s,128-s);z0=np.minimum(z//s*s,128-s);fx=(x-x0)/s;fz=(z-z0)/s
    a=patch[z0,x0];b=patch[z0,x0+s];c=patch[z0+s,x0];d=patch[z0+s,x0+s]
    model=np.where(fx+fz<1,a+(b-a)*fx+(c-a)*fz,d+(c-d)*(1-fx)+(b-d)*(1-fz))
    errors.append(float(np.max(np.abs(model-patch))))
  chunks.append({'cell':[cx,cz],'minimum_source_equivalent_m':float(patch.min()),'maximum_source_equivalent_m':float(patch.max()),'lod_height_error_m':errors,'named_anchor_cell':(cx,cz) in special})
out={'revision':'fixed-triangular-subset-lod-bounds-v1','chunk_cells':128,'strides':[1,2,4,8,16,32,64,128],'bound':'exact extrema at all fixed-grid nodes; coarse dyadic diagonals are subsets of fine grid triangle edges, hence difference is linear on every fine face. Named-anchor/partial outer chunks only use exact stride1.','screen_error_budget_px':.75,'chunks':chunks}
(P/'chunks.json').write_text(json.dumps(out,separators=(',',':'))+'\n');m['chunks']={'path':'chunks.json','sha256':hashlib.sha256((P/'chunks.json').read_bytes()).hexdigest()};tmp=P/'surface.json.new';tmp.write_text(json.dumps(m,indent=2)+'\n');tmp.replace(P/'surface.json');print(json.dumps({'chunks':len(chunks),'height_unchanged':hashlib.sha256((P/'height.rg8').read_bytes()).hexdigest()==m['height_payload']['sha256']}))
