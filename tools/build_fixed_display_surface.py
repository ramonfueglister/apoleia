#!/usr/bin/env python3
"""Own fixed display-world derivation. Source/model products remain immutable."""
import hashlib,json,math,pathlib,argparse
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--source-manifest',default='data/gameworld-v1/landscape.json');parser.add_argument('--output',default='artifacts/render-data/fixed-diorama-v1');args,_=parser.parse_known_args()
OUT=ROOT/args.output
M=ROOT/args.source_manifest
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def readref(r):
 p=ROOT/r['path']
 if sha(p)!=r['sha256']:raise RuntimeError('source hash mismatch '+str(p))
 return p
m=json.loads(M.read_text());is_v2=m.get('required_sampling_contract')=='canonical-c2-domains-v2'
u=json.loads((M.parent/'upload/upload.json').read_text()) if not is_v2 else None
R=6371008.8;K=math.pi/180*R*.001;CX=K*math.cos(math.radians(41))
def rect(b):return np.array([(b['west']-19)*CX,(41-b['north'])*K]),np.array([(b['east']-b['west'])*CX,(b['north']-b['south'])*K])
wm,ws=rect(m['bounds']);dm,ds=rect(m['height_detail_bounds'])
def texture(path,w,h,dtype=np.uint8,channels=1):return np.memmap(path,dtype=dtype,mode='r',shape=(h,w,channels))
if not is_v2:
 context=texture(M.parent/u['domains']['context']['height']['payload']['path'],m['height_width'],m['height_height'],channels=2)
 fine=texture(M.parent/u['domains']['detail']['height']['payload']['path'],m['height_detail_width'],m['height_detail_height'],channels=2)
 wc=texture(M.parent/m['water_path'],m['water_width'],m['water_height']);wf=texture(M.parent/m['water_detail_path'],m['water_detail_width'],m['water_detail_height'])
 local=None
 ip=M.parent/'water-render-tiles.json'
 if ip.exists():
  inv=json.loads(ip.read_text());tile=json.loads(readref(inv['tiles'][0]['manifest']).read_text());local=(np.array(tile['world_min']),np.array(tile['world_size']),texture(readref(tile['water']),tile['width'],tile['height']))
 def inside(x,z,origin,size):return (x>=origin[0])&(x<=origin[0]+size[0])&(z>=origin[1])&(z<=origin[1]+size[1])
 def nearest(tex,x,z,origin,size):
  xx=np.clip(np.floor((x-origin[0])/size[0]*tex.shape[1]).astype(np.int32),0,tex.shape[1]-1);yy=np.clip(np.floor((z-origin[1])/size[1]*tex.shape[0]).astype(np.int32),0,tex.shape[0]-1)
  return tex[yy,xx,0]
 def water(x,z):
  v=np.where(inside(x,z,dm,ds),nearest(wf,x,z,dm,ds),nearest(wc,x,z,wm,ws))
  if local is not None:v=np.where(inside(x,z,local[0],local[1]),nearest(local[2],x,z,local[0],local[1]),v)
  return v

 def bilinear(tex,x,z,origin,size):
  xx=(x-origin[0])/size[0]*tex.shape[1]-.5;yy=(z-origin[1])/size[1]*tex.shape[0]-.5
  ix=np.clip(np.floor(xx).astype(np.int32),0,tex.shape[1]-2);iy=np.clip(np.floor(yy).astype(np.int32),0,tex.shape[0]-2);fx=np.clip(xx-ix,0,1);fy=np.clip(yy-iy,0,1)
  def q(dx,dy):v=tex[iy+dy,ix+dx];return(v[...,0].astype(np.float32)*256+v[...,1])*.25-8192
  return(q(0,0)*(1-fx)+q(1,0)*fx)*(1-fy)+(q(0,1)*(1-fx)+q(1,1)*fx)*fy

 def height(x,z):
  v=np.where(inside(x,z,dm,ds),bilinear(fine,x,z,dm,ds),bilinear(context,x,z,wm,ws))
  return np.where(water(x,z)==1,0,v)
else:
 from canonical_v2_sampler import CanonicalV2Sampler
 canonical=CanonicalV2Sampler(M);water=canonical.water;height=canonical.height
# Source-retained named anchor coordinates, loaded from the immutable inventories.
anchors=[];mesh=json.loads((M.parent/m.get('feature_mesh_manifest_path','core-mesh-manifest.json')).read_text());rules=json.loads((ROOT/'data/protection-rules.json').read_text())
for lon,lat in rules['ridges']['anchors']:
 p=np.array([(lon-19)*CX,(41-lat)*K])
 for entry in mesh['blocks']:
  a=np.array(entry['world_min']);s=np.array(entry['world_size'])
  if np.all(p>=a-1)&np.all(p<=a+s+1):
   feats=json.loads(readref(entry['feature_inventory']).read_text())['features'];verts=np.memmap(readref(entry['vertices']),dtype='<f4',mode='r').reshape(-1,3)
   for f in feats:
    if f['kind']=='ridge_anchor' and not any(v['id']==f['id'] for v in anchors):
     xyz=verts[int(f['retained_vertex_index'])].astype(float);anchors.append({'id':f['id'],'world_x':xyz[0],'world_z':xyz[2],'height_source_m':f['source_height_m'],'source_sample':f['source_sample'],'source_feature_inventory':entry['feature_inventory']})
nx=int(math.ceil(ws[0]/2))+1;ny=int(math.ceil(ws[1]/2))+1
OUT.mkdir(parents=True,exist_ok=False)
target=np.memmap(OUT/'height.rg8',dtype=np.uint8,mode='w+',shape=(ny,nx,2))
maximum_delta=0.0;minimum=0.;maximum=0.
for first in range(0,ny,64):
 last=min(ny,first+64);x=np.broadcast_to(wm[0]+np.arange(nx)[None,:]*ws[0]/(nx-1),(last-first,nx));z=np.broadcast_to(wm[1]+np.arange(first,last)[:,None]*ws[1]/(ny-1),(last-first,nx))
 original=height(x,z);kind=water(x,z);total=original*4;weight=np.full(original.shape,4.);coastal=np.zeros(original.shape,bool)
 for dz in [-1,0,1]:
  for dx in [-1,0,1]:
   if dx==0 and dz==0:continue
   qx=x+dx*4.;qz=z+dz*4.;good=water(qx,qz)==0;w=2 if dx==0 or dz==0 else 1
   total+=np.where(good,height(qx,qz)*w,0);weight+=good*w;coastal|=~good
 protect=np.zeros(original.shape)
 for a in anchors:
  t=np.clip(np.hypot(x-a['world_x'],z-a['world_z'])/8,0,1);protect=np.maximum(protect,1-t**3*(t*(t*6-15)+10))
 generalized=total/weight;generalized=generalized*(1-protect)+original*protect
 result=np.where((kind!=0)|coastal,original,generalized)
 maximum_delta=max(maximum_delta,float(np.max(np.abs(result-original))));minimum=min(minimum,float(result.min()));maximum=max(maximum,float(result.max()))
 code=np.rint((result+8192)/.25).astype(np.int64)
 if code.min()<0 or code.max()>65535:raise RuntimeError('height encoding overflow')
 target[first:last,:,0]=code//256;target[first:last,:,1]=code%256
 if first%512==0:print(json.dumps({'rows':last,'total_rows':ny}),flush=True)
target.flush();del target
if maximum_delta>1500:raise RuntimeError('prebound1500m base grid-node budget exceeded: '+str(maximum_delta))
policy={'revision':'fixed-diorama-surface-v1','status':'implementiert','canonical_source_unchanged':True,'source_manifest_sha256':sha(M),'sampling_contract':m.get('required_sampling_contract','legacy-v1'),'source_to_grid_node_budget_m':1500,'kernel':'fixed land-only 3x3 Gaussian weights1/2/4 at4km axis offsets; coastal/water samples retain original height','kernel_axis_span_model':4.0,'named_anchor_protection_radius_model':8.0,'named_anchor_protection':'C2 radial weight returns to original local source height; exact named point inserted into its fixed grid cell','fixed_grid_spacing_working_model':2.0,'fixed_surface_definition':'RG8 decoded heights at fixed grid nodes; fixed diagonal NW-SE triangles; each named-anchor host cell replaced by four edge-to-anchor triangles. Independent of zoom, quadtree and render residency.','render_error_budget_px':.75,'render_method':'exact fixed-grid triangles with shared indices and bounded streamed chunks; no height simplification or parent morph','dominant_source_landforms':'the fixed4km field suppresses minor peaks; dominant source structures and named shoulders belong to the field, not per-view selection','world_min':wm.tolist(),'world_size':ws.tolist(),'width':nx,'height':ny,'height_encoding':{'minimum_m':-8192,'step_m':.25,'channels':'RG8 high-byte/low-byte'},'anchors':anchors,'source_to_grid_node_generalization_sample_max_m':maximum_delta,'source_to_grid_node_generalization_scope':'all fixed grid nodes; not all original native source centers or all triangle interiors','height_range_source_equivalent_m':[minimum,maximum]}
(OUT/'policy.json').write_text(json.dumps(policy,indent=2)+'\n');manifest={'revision':'fixed-diorama-surface-v1','policy':{'path':'policy.json','sha256':sha(OUT/'policy.json')},'height_payload':{'path':'height.rg8','sha256':sha(OUT/'height.rg8'),'bytes':(OUT/'height.rg8').stat().st_size},'source_manifest_sha256':sha(M),'world_min':wm.tolist(),'world_size':ws.tolist(),'width':nx,'height':ny,'anchors':anchors}
(OUT/'surface.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps({'complete':str(OUT),'width':nx,'height':ny,'max_grid_node_generalization_m':maximum_delta}),flush=True)
