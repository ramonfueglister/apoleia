#!/usr/bin/env python3
"""Graphic marine-coast falloff from immutable V1 role cells; no physical roles edited."""
import hashlib,json,math,pathlib,sys,time,argparse
import numpy as np
import scipy
from scipy.ndimage import distance_transform_edt
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--source-manifest',default='data/gameworld-v1/landscape.json');parser.add_argument('--output',default='artifacts/render-data/display-coast-v1');args=parser.parse_args()
BASE=(ROOT/args.source_manifest).parent;OUT=ROOT/args.output
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
start=time.monotonic();mp=BASE/'landscape.json';m=json.loads(mp.read_text());source=BASE/m['water_path']
expected=m['assets'][m['water_path']]['sha256']
if sha(source)!=expected:raise SystemExit('Role source hash mismatch')
if OUT.exists():raise SystemExit('Refusing to overwrite existing graphic sidecar')
w=int(m['water_width']);h=int(m['water_height']);b=m['bounds'];r=6371008.8;scale=.001
sx=math.radians(b['east']-b['west'])*r*math.cos(math.radians(41))/w
sy=math.radians(b['north']-b['south'])*r/h
if m.get('required_sampling_contract')=='canonical-c2-domains-v2':
 from canonical_v2_sampler import CanonicalV2Sampler
 canonical=CanonicalV2Sampler(mp);roles=np.empty((h,w),dtype='u1');origin,size=canonical.rect(b)
 for row in range(0,h,64):
  end=min(h,row+64);x=origin[0]+(np.arange(w)[None,:]+.5)*size[0]/w;z=origin[1]+(np.arange(row,end)[:,None]+.5)*size[1]/h;roles[row:end]=canonical.water(x,z)
else:roles=np.memmap(source,mode='r',dtype='u1',shape=(h,w))
marine=roles==1
boundary=np.zeros((h,w),dtype=bool)
d=marine[:-1]!=marine[1:];boundary[:-1]|=d;boundary[1:]|=d
d=marine[:,:-1]!=marine[:,1:];boundary[:,:-1]|=d;boundary[:,1:]|=d
if not boundary.any():raise SystemExit('No marine boundary seeds')
distance=distance_transform_edt(~boundary,sampling=(sy,sx));np.minimum(distance,64000,out=distance)
codes=np.floor(distance*.5+.5).astype(np.uint16);packed=np.empty((h,w,2),dtype='u1');packed[:,:,0]=codes>>8;packed[:,:,1]=codes&255
OUT.mkdir(parents=True);payload=OUT/'distance.rg8';tmp=OUT/'distance.tmp';tmp.write_bytes(packed.tobytes());tmp.replace(payload)
world_min=[math.radians(b['west']-19)*r*math.cos(math.radians(41))*scale,math.radians(41-b['north'])*r*scale]
world_size=[sx*w*scale,sy*h*scale]
manifest={'revision':'display-coast-distance-v1','status':'implementiert; graphic transport, GPU/style validation pending','source_manifest_sha256':sha(mp),'source_role_path':str(source.relative_to(ROOT)),'source_role_sha256':expected,'sampling_contract':m.get('required_sampling_contract','legacy-v1'),'source_role_composition':'canonical C2 composed SDF then discrete associated role at graphic pixel centers' if m.get('required_sampling_contract') else 'source water mask','source_roles':{str(int(v)):int(n)for v,n in zip(*np.unique(roles,return_counts=True))},'width':w,'height':h,'world_min':world_min,'world_size':world_size,'raster_contract':'full domain extent; first pixel center at min+size/(2*dimensions); sample uv*N-.5; no synthetic outer-rectangle boundary','encoding':{'channels':'RG8 high/low unsigned','step_m':2.,'cap_m':64000.,'quantization_error_max_m':1.},'definition':'unsigned nearest composed-source marine/nonmarine boundary-cell center; EDT on both adjoining cell centers, no new physical coast or water role','spacing_m':[sx,sy],'mask_cell_boundary_uncertainty_bound_m':math.hypot(sx,sy),'uncertainty_note':'conservative one-cell diagonal relative to raster boundary; does not bound vector/source coastline accuracy; original exact near-shore SDF still owns contour','inland_role_rule':'role2 never marine; distance may exist there but shader retains inland original path','payload':{'path':str(payload.relative_to(ROOT)),'sha256':sha(payload),'bytes':payload.stat().st_size},'provenance':{'builder_sha256':sha(pathlib.Path(__file__)),'numpy':np.__version__,'scipy':scipy.__version__,'python':sys.version.split()[0]},'build_seconds':time.monotonic()-start}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps({'path':str(OUT/'manifest.json'),'manifest_sha256':sha(OUT/'manifest.json'),'build_seconds':manifest['build_seconds'],'cell_uncertainty_m':manifest['mask_cell_boundary_uncertainty_bound_m']}))
