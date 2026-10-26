#!/opt/anaconda3/bin/python
"""Only the missing source-supported1degreehalo is generalised; inheritedcore is immutable."""
import pathlib,json,hashlib,numpy as np
import gameworld_build as gb
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';PAY=OUT/'payload';gb.OUT=OUT;gb.PAY=PAY;PAY.mkdir(exist_ok=True)
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 w,h=14160,9360;b=[-12,20,47,59];source=np.memmap(OUT/'source-observations/fine-height.f32',dtype='<f4',mode='r',shape=(h,w));p=PAY/'fine-model-height.f32';model=np.memmap(p,dtype='<f4',mode='w+',shape=(h,w));model[:]=np.nan;core=np.memmap(ROOT/'data/gameworld-v1/payload/core-model-height.f32',dtype='<f4',mode='r',shape=(8880,13680));model[240:9120,240:13920]=core;windows=[]
 # One source sample overlaps inheritedcore; every sharedboundary source sample is retained.
 for y in range(0,h-1,256):
  windows.extend([(0,y,241,min(257,h-y)),(13919,y,241,min(257,h-y))])
 for x in range(240,13919,256):
  windows.extend([(x,0,min(257,13920-x),241),(x,9119,min(257,13920-x),241)])
 records=[]
 for i,(x,y,ww,hh) in enumerate(windows):
  name=f'halo-{y:05d}-{x:05d}';z=np.array(source[y:y+hh,x:x+ww],dtype='f8');reconstructed,rec,features=gb.tin_block(z,b,x,y,w,h,name);model[y:y+hh,x:x+ww]=reconstructed;records.append(rec)
  if i%20==0:print('halo',i+1,'/',len(windows),'verts',rec['vertex_count'],flush=True)
 # Exact inheritedcentre values are authoritative, including source-backedsharedboundaryrow.
 model[240:9120,240:13920]=core;model.flush()
 if not np.isfinite(model).all():raise RuntimeError('Unfilledhalo cells')
 if not np.array_equal(model[240:9120,240:13920],core):raise RuntimeError('Inheritedcorechanged')
 data={'revision':'gameworld-v2-halo-TIN','bounds':dict(zip(['west','south','east','north'],b)),'width':w,'height':h,'model_height':{'path':str(p.relative_to(ROOT)),'sha256':sha(p),'bytes':p.stat().st_size},'source_height':str((OUT/'source-observations/fine-height.f32').relative_to(ROOT)),'blocks':records,'source_samples_including_shared_rows':sum(x['source_sample_count'] for x in records),'retained_vertices':sum(x['vertex_count'] for x in records),'max_source_height_residual_m':max(x['max_vertical_residual_source_m'] for x in records),'inherited_core_bitidentical':True,'canonical_transition_policy':'data/gameworld-v2/policy.json'};(OUT/'halo-mesh-manifest.json').write_text(json.dumps(data,indent=2)+'\n');print('halo complete',len(records),data['max_source_height_residual_m'],flush=True)
if __name__=='__main__':main()
