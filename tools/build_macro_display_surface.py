#!/usr/bin/env python3
"""Fixed source-bound macrofacet display model; no canonical payload edits."""
import pathlib,json,hashlib,math,os,argparse
import numpy as np
from scipy.spatial import Delaunay
from scipy.interpolate import LinearNDInterpolator
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--source-manifest',default='data/gameworld-v1/landscape.json');parser.add_argument('--base-dir',default='artifacts/render-data/fixed-diorama-v1');parser.add_argument('--output',default='artifacts/render-data/fixed-diorama-v2');args=parser.parse_args()
BASE=ROOT/args.base_dir;OUT=ROOT/args.output
m=json.loads((BASE/'surface.json').read_text());w,h=m['width'],m['height'];origin=np.array(m['world_min']);extent=np.array(m['world_size']);spacing=extent/np.array([w-1,h-1]);q=np.memmap(BASE/'height.rg8',dtype=np.uint8,mode='r',shape=(h,w,2));field=(q[...,0].astype(np.float32)*256+q[...,1])*.25-8192
# Reuse the exact, versioned read-only source samplers; stop before derivation.
source=ROOT/'tools/build_fixed_display_surface.py';namespace={'__file__':str(source)};exec(source.read_text().split('nx=int(math.ceil')[0],namespace);water=namespace['water'];original_height=namespace['height']
if m['source_manifest_sha256']!=namespace['sha'](namespace['M']):raise RuntimeError('base/source manifest mismatch')
roles=np.empty((h,w),np.uint8)
for z in range(0,h,64):
 zz=np.arange(z,min(z+64,h))[:,None]*spacing[1]+origin[1];xx=np.arange(w)[None,:]*spacing[0]+origin[0];roles[z:z+64]=water(xx,zz)
controls={}
def put(x,z):controls[(int(x),int(z))]=float(field[int(z),int(x)])
# Global24km addresses; chosen positions are observed fixed-model nodes, not jittered terrain.
for z in range(0,h-1,12):
 for x in range(0,w-1,12):
  patch=field[z:min(z+12,h),x:min(x+12,w)];mask=roles[z:z+patch.shape[0],x:x+patch.shape[1]]==0
  if not mask.any():put(x+patch.shape[1]//2,z+patch.shape[0]//2);continue
  values=patch[mask];mean=float(values.mean());error=np.where(mask,np.abs(patch-mean),np.inf);iz,ix=np.unravel_index(np.argmin(error),patch.shape);put(x+ix,z+iz)
  if values.max()>750 and values.max()-values.min()>350:
   hi=np.where(mask,patch,-np.inf);lo=np.where(mask,patch,np.inf)
   if float(values.max())-mean>=180:iz,ix=np.unravel_index(np.argmax(hi),patch.shape);put(x+ix,z+iz)
   if mean-float(values.min())>=180:iz,ix=np.unravel_index(np.argmin(lo),patch.shape);put(x+ix,z+iz)
# Protect physical boundary supports and domain boundary; shore is never inferred from H.
coast=np.zeros((h,w),bool)
for dz,dx in [(1,0),(-1,0),(0,1),(0,-1),(2,0),(-2,0),(0,2),(0,-2)]:coast|=roles!=np.roll(np.roll(roles,dz,axis=0),dx,axis=1)
for x in range(w):put(x,0);put(x,h-1)
for z in range(h):put(0,z);put(w-1,z)
for z,x in zip(*np.where(coast)):
 if (x+z)%3==0:put(x,z)
print(json.dumps({'controls':len(controls),'grid':[w,h]}),flush=True)
points=np.array(list(controls),dtype=np.float64);values=np.array(list(controls.values()));tri=Delaunay(points);interpolator=LinearNDInterpolator(tri,values)
OUT.mkdir(parents=True,exist_ok=False);target=np.memmap(OUT/'height.rg8',dtype=np.uint8,mode='w+',shape=(h,w,2));maximum=0.;maxbase=0.;minimum=0.;highest=0.
for start in range(0,h,64):
 end=min(start+64,h);z,x=np.mgrid[start:end,:w];candidate=np.asarray(interpolator(x,z));base=field[start:end];candidate=np.where(np.isnan(candidate),base,candidate)
 protect=np.zeros(candidate.shape)
 worldx=origin[0]+x*spacing[0];worldz=origin[1]+z*spacing[1]
 for a in m['anchors']:
  t=np.clip(np.hypot(worldx-a['world_x'],worldz-a['world_z'])/12,0,1);protect=np.maximum(protect,1-t**3*(t*(t*6-15)+10))
 candidate=candidate*(1-protect)+base*protect;candidate=np.where((roles[start:end]!=0)|coast[start:end],base,candidate)
 raw=original_height(worldx,worldz);maximum=max(maximum,float(np.max(np.abs(candidate-raw))));maxbase=max(maxbase,float(np.max(np.abs(candidate-base))));minimum=min(minimum,float(candidate.min()));highest=max(highest,float(candidate.max()))
 code=np.rint((candidate+8192)/.25).astype(np.int64)
 if code.min()<0 or code.max()>65535:raise RuntimeError('encoding overflow')
 target[start:end,:,0]=code//256;target[start:end,:,1]=code%256
 if start%512==0:print(json.dumps({'rows':end,'total':h}),flush=True)
target.flush();del target
if maximum>2500:raise RuntimeError('prebound2500m source-to-display grid-node budget exceeded: '+str(maximum))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
policy=json.loads((BASE/'policy.json').read_text());policy.update({'revision':'fixed-diorama-macrofacets-v2','macrofacet_partition':'global24km addresses; source-land representative closest to local mean plus dominant ridge/valley extrema; source node positions; Delaunay interpolation; coast/water and named-original shoulders protected','macro_control_count':len(controls),'macro_source_height_budget_m':2500,'macro_source_to_grid_node_max_m':maximum,'macro_base_to_grid_node_max_m':maxbase,'base_surface_manifest_sha256':sha(BASE/'surface.json'),'height_range_source_equivalent_m':[minimum,highest],'numpy_version':np.__version__,'scipy_method':'Delaunay/LinearNDInterpolator, existing Anaconda runtime','fixed_surface_definition':'unchanged2km RG8 triangular grid definition and named anchor star cells; globally fixed across every zoom','status':'implementiert; GPU/visual validation pending'})
(OUT/'policy.json').write_text(json.dumps(policy,indent=2)+'\n');m.pop('chunks',None);m['revision']='fixed-diorama-macrofacets-v2';m['policy']={'path':'policy.json','sha256':sha(OUT/'policy.json')};m['height_payload']={'path':'height.rg8','sha256':sha(OUT/'height.rg8'),'bytes':(OUT/'height.rg8').stat().st_size};(OUT/'surface.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps({'complete':str(OUT),'source_max_m':maximum,'base_max_m':maxbase}),flush=True)
