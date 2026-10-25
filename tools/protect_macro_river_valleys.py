#!/usr/bin/env python3
"""Keep existing source river corridors on the previous fixed model, no new rivers."""
import pathlib,json,hashlib,math,argparse
import numpy as np
from scipy.ndimage import distance_transform_edt
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--source-manifest',default='data/gameworld-v1/landscape.json');parser.add_argument('--base-dir',default='artifacts/render-data/fixed-diorama-v1');parser.add_argument('--surface-dir',default='artifacts/render-data/fixed-diorama-v2');args=parser.parse_args()
BASE=ROOT/args.base_dir;OUT=ROOT/args.surface_dir
if (OUT/'READY.json').exists() or (OUT/'river-protection.json').exists():raise RuntimeError('refusing to mutate frozen/already protected surface')
m=json.loads((OUT/'surface.json').read_text());w,h=m['width'],m['height'];origin=np.array(m['world_min']);step=np.array(m['world_size'])/np.array([w-1,h-1]);mask=np.zeros((h,w),bool);sampled=[]
source_path=ROOT/args.source_manifest;source=json.loads(source_path.read_text());river_path=source_path.parent/source['rivers_path'];features=json.loads(river_path.read_text())['features'];R=6371008.8;K=math.pi/180*R*.001;X=K*math.cos(math.radians(41))
for feature in features:
 geom=feature['geometry'];lines=[geom['coordinates']] if geom['type']=='LineString' else geom['coordinates']
 for line in lines:
  p=np.asarray(line,dtype=float);p=np.stack([(p[:,0]-19)*X,(41-p[:,1])*K],axis=1);g=(p-origin)/step
  for a,b in zip(g[:-1],g[1:]):
   n=max(1,int(np.ceil(np.max(np.abs(b-a))*2)));t=np.linspace(0,1,n+1);points=a[None,:]+t[:,None]*(b-a)[None,:];ij=np.rint(points).astype(int);ok=(ij[:,0]>=0)&(ij[:,0]<w)&(ij[:,1]>=0)&(ij[:,1]<h);ij=ij[ok];mask[ij[:,1],ij[:,0]]=True;sampled.extend(points[ok].tolist())
distance=distance_transform_edt(~mask,sampling=step[::-1]);t=np.clip((distance-4)/4,0,1);weight=1-t**3*(t*(t*6-15)+10)
def decode(p):q=np.memmap(p,dtype=np.uint8,mode='r',shape=(h,w,2));return(q[...,0].astype(np.float32)*256+q[...,1])*.25-8192
base=decode(BASE/'height.rg8');candidate=decode(OUT/'height.rg8');result=candidate*(1-weight)+base*weight;code=np.rint((result+8192)/.25).astype(np.uint16);payload=np.empty((h,w,2),np.uint8);payload[...,0]=code//256;payload[...,1]=code%256;tmp=OUT/'height.protected.rg8';payload.tofile(tmp);tmp.replace(OUT/'height.rg8')
def triangular(grid,p):
 p=np.clip(p,[0,0],[w-1,h-1]);cell=np.minimum(np.floor(p).astype(int),[w-2,h-2]);f=p-cell;x=cell[:,0];z=cell[:,1];a=grid[z,x];b=grid[z,x+1];c=grid[z+1,x];d=grid[z+1,x+1];return np.where(f[:,0]+f[:,1]<1,a+(b-a)*f[:,0]+(c-a)*f[:,1],d+(c-d)*(1-f[:,0])+(b-d)*(1-f[:,1]))
q=decode(OUT/'height.rg8');points=np.asarray(sampled);before=triangular(base,points);after=triangular(q,points);error=float(np.max(np.abs(after-before)));proof={'revision':'source-river-valley-protection-v1','status':'validiert' if error<.001 else 'offen','source_rivers_sha256':hashlib.sha256(river_path.read_bytes()).hexdigest(),'source_features':len(features),'source_centerline_changed':False,'dense_source_line_samples':len(points),'maximum_before_after_model_height_delta_source_equivalent_m':error,'inner_original_surface_radius_model':4.,'outer_C2_radius_model':8.,'bound_scope':'source line vertices and <=1km dense segment samples, not missing rivers, hydraulic flow or historical180 shore validation'}
if error>.001:raise RuntimeError('existing river surface changed '+str(error))
(OUT/'river-protection.json').write_text(json.dumps(proof,indent=2)+'\n');policy=json.loads((OUT/'policy.json').read_text());policy['river_valley_protection']=proof;policy['height_range_source_equivalent_m']=[float(q.min()),float(q.max())];policy['source_to_model_bound_after_river_protection']='convex mixture of the bound base and macro grid-node samples; must be remeasured against the bound canonical source after river protection; no native source accuracy claim';(OUT/'policy.json').write_text(json.dumps(policy,indent=2)+'\n');sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();m['policy']['sha256']=sha(OUT/'policy.json');m['height_payload']['sha256']=sha(OUT/'height.rg8');m.pop('chunks',None);(OUT/'surface.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(proof),flush=True)
