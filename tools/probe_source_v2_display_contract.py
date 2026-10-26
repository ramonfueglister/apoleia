#!/usr/bin/env python3
"""Supplementary role/coast and effective node bounds probes, read-only inputs."""
import json,pathlib,argparse,numpy as np
from canonical_v2_sampler import CanonicalV2Sampler,sha
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--surface-dir',required=True);args=p.parse_args();P=ROOT/args.surface_dir;O=P/'contract-probes.json'
if O.exists():raise RuntimeError('refusing output overwrite')
s=CanonicalV2Sampler(ROOT/'data/gameworld-v2/landscape.json');m=json.loads((P/'surface.json').read_text());lod=json.loads((P/'chunks.json').read_text());w,h=m['width'],m['height'];q=np.memmap(P/'height.rg8',dtype='u1',mode='r',shape=(h,w,2));grid=(q[...,0].astype('f4')*256+q[...,1])*.25-8192
probes=[]
def record(x,z,label):
 phi,role,diag=s.fields(x,z,True);fine,local=s.weights(x,z)
 probes.append({'label':label,'lon':x/s.CX+19,'lat':41-z/s.K,'fine_weight':float(fine),'local_weight':float(local),'SDF_m':float(phi),'final_role':int(role),'associated_roles_context_fine_local':diag['associated_roles'],'height_m':float(s.raw_height(x,z))})
lon,lat=9.3675744629,44.2958298582;x=(lon-19)*s.CX;z=(41-lat)*s.K;e=.005
g=np.array([(s.fields(x+e,z)[0]-s.fields(x-e,z)[0]),(s.fields(x,z+e)[0]-s.fields(x,z-e)[0])],dtype=float);g/=np.linalg.norm(g)
for metres in [-100,-20,0,20,100]:record(x+g[0]*metres*.001,z+g[1]*metres*.001,'native_local_coast_normal_offset_'+str(metres)+'m')
d=s.domains['local']['definition'];pack=s.domains['local']['distance'];phi=(pack[...,0].astype('f4')*256+pack[...,1])*.125-4096;roles=s.domains['local']['role'];score=np.where(roles==2,phi,-np.inf);iz,ix=np.unravel_index(np.argmax(score),score.shape)
record(d['world_min'][0]+(ix+.5)*d['world_size'][0]/d['width'],d['world_min'][1]+(iz+.5)*d['world_size'][1]/d['height'],'positive_local_inlandwater_deepest_available_cell')
# At arbitrary land locations a role field can be marine/inland without water.
record((9.62-19)*s.CX,(41-44.30)*s.K,'fine_land_with_different_context_associated_role')
bounds=[];anchor_probes=[]
for c in lod['chunks']:
 cx,cz=c['cell'];lo=c['minimum_source_equivalent_m'];hi=c['maximum_source_equivalent_m'];ids=[]
 for a in m['anchors']:
  cell=np.floor((np.array([a['world_x'],a['world_z']])-m['world_min'])/m['world_size']*np.array([w-1,h-1])).astype(int)
  if tuple(cell//128)==(cx,cz):lo=min(lo,a['height_source_m']);hi=max(hi,a['height_source_m']);ids.append(a['id'])
 bounds.append({'cell':[cx,cz],'minimum_m':lo,'maximum_m':hi,'anchor_ids':ids})
for a in m['anchors']:
 raw=float(s.raw_height(a['world_x'],a['world_z']));anchor_probes.append({'id':a['id'],'canonical_height_m':raw,'fixed_star_vertex_height_m':a['height_source_m'],'source_height_delta_m':abs(raw-a['height_source_m'])})
if [v['final_role'] for v in probes]!=[0,0,0,1,1,2,0]:raise RuntimeError('pinned coast/inland/land role probe changed')
if not all(np.isfinite(v['minimum_m']) and np.isfinite(v['maximum_m']) for v in bounds):raise RuntimeError('nonfinite effective node bounds')
result={'revision':'source-v2-display-contract-probes-r1','reference_version':'kit1-landscape-v5 / gameworld-v2','status':'validiert','source_manifest_sha256':sha(s.path),'role_policy':'own integration decision: after final composed SDF>0, select nearest discrete role of finest spatially valid domain with transition weight>0; local>fine>context. Categorical discontinuities are allowed; no .5 threshold or code lerp.','roles':{'0':'land, decided only by final SDF','1':'marine','2':'inlandwater'},'role_probes':probes,'local_override_fields':['RGBA','SDF','discrete associated_role','classes','forest metadata'],'local_height_override':False,'effective_chunk_node_bounds':bounds,'bound_scope':'all fixed grid vertices plus named star vertices; same expansion as FixedDisplaySurface.configure; does not assert source accuracy or a GPU culling test','anchor_probes':anchor_probes,'all_effective_bounds_finite':all(np.isfinite(v['minimum_m']) and np.isfinite(v['maximum_m']) for v in bounds)}
O.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'path':str(O),'sha256':sha(O),'role_probes':probes,'anchors':anchor_probes}))
