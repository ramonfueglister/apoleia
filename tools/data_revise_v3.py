#!/usr/bin/env python3
"""Targeted v2→v3 repair, no downloads or terrain elevation mutation.
Keeps failed v2 diagnostics and an unchanged budget policy, improves the offline
water overview and clarifies horizontal identity vs projection roundoff.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import pathlib,json,hashlib,shutil
import numpy as np
from osgeo import gdal,ogr
from data_bind import ROOT,read,ref
RUN=ROOT/'runs/kit1-landscape-v5-2026-10-25'
def write(path,x):
 p=ROOT/path;tmp=p.with_name('.'+p.name+'.v3.tmp');tmp.write_text(json.dumps(x,indent=2)+'\n');os.replace(tmp,p)
def h(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
# Retain the actual failed v2 measurements and provenance. References are all
# content-bound; source+payload originals are retained via run snapshot links.
if read('data/derived/landscape.json')['dataset_revision']=='landscape-v3':
 print('v3 targetedmigration already applied; no mutation or downloads');raise SystemExit(0)
assert read('data/derived/landscape.json')['dataset_revision']=='landscape-v2'
backup=RUN/'data-revisions/landscape-v2'
if not backup.exists():
 for p in (RUN/'data').rglob('*'):
  if p.is_file():
   dst=backup/'data'/p.relative_to(RUN/'data');dst.parent.mkdir(parents=True,exist_ok=True);os.link(p,dst)
 for name in ['sources','region','coverage','geodata_policy','derivation']:
  p=RUN/(name+'.json')
  if p.exists():os.link(p,backup/(name+'.json'))
# Break hardlinks for all *generated metadata/sample* files that the existing
# measurement tools rewrite; native DEM/water/class payloads remain byteidentical.
for folder in [ROOT/'data',ROOT/'data/derived']:
 for p in folder.iterdir():
  if p.is_file() and p.suffix in ['.json','.csv'] and p.stat().st_nlink>1:
   tmp=p.with_name('.'+p.name+'.detach');shutil.copy2(p,tmp);os.replace(tmp,p)
D=ROOT/'data/derived';m=read('data/derived/landscape.json');B=m['bounds'];w,e,s,n=[B[k]for k in ['west','east','south','north']]
# Improve the coarse product, keeping the predeclared 6000m budget. Native
# shoreline detail remains independent and shared by all actual render zooms.
ww,hh=4096,3072
ds=gdal.GetDriverByName('MEM').Create('',ww,hh,1,gdal.GDT_Byte);ds.SetGeoTransform([w,(e-w)/ww,0,n,0,-(n-s)/hh]);ds.SetProjection('EPSG:4326');ds.GetRasterBand(1).Fill(0)
land=ogr.Open(str(D/'land.geojson'));gdal.RasterizeLayer(ds,[1],land.GetLayer(),burn_values=[1]);a=(1-ds.ReadAsArray()).astype('uint8');ds.GetRasterBand(1).WriteArray(a)
lakes=ogr.Open(str(D/'lakes.geojson'));gdal.RasterizeLayer(ds,[1],lakes.GetLayer(),burn_values=[2]);a=ds.ReadAsArray()
p=D/'overview-water.u8';tmp=D/'.overview-water.v3.tmp';a.tofile(tmp);os.replace(tmp,p)
m['dataset_revision']='landscape-v3';m['source_quality']='ETOPO15s native elevation (~245-433m east-west;463m north-south). WorldCover last overview (~0.6km). Natural Earth1:10M physical water. No fabricated small relief or historical vegetation.';m['overview'].update(water_width=ww,water_height=hh)
m['water_lod_policy']='Actual runtime uses water-detail8192x6144 at every zoom; canonical water is integrity-failure fallback, overview-water4096x3072 is offline prepared product only, never a hidden rendered coastLOD.'
m['assets']['overview-water.u8']=dict(path='overview-water.u8',sha256=h(p),bytes=p.stat().st_size);write('data/derived/landscape.json',m)
inv=read('data/derived/inventory.json');inv['revision']='landscape-v3';inv['source_vrt_sha256']=inv.pop('full_source_sha256');inv['source_vrt_hash_scope']='Hash of complete elevation-source.vrt descriptor, NOT a TIFF or merged elevation payload. Original complete TIFF hashes are in etopo15-inventory.json and sources.json.';write('data/derived/inventory.json',inv)
# Refresh anchor height from exactly the same canonical file used by the other8.
a=read('data/anchors.json');a['revision']='anchors-v3';z=np.memmap(D/'height.f32',dtype='<f4',shape=(m['height'],m['width']))
for x in a['anchors']:x['height_m']=float(z[x['canonical_row'],x['canonical_col']])
write('data/anchors.json',a)
# Define intended metric before remeasurement; retain the numeric roundtrip as
# a separate diagnostic rather than rounding it away or loosening budget0.
write('data/horizontal-metric.json',dict(revision='horizontal-identity-v1',status='spezifiziert',metric='terrain_horizontal_m',definition='Horizontal change introduced by heightfield generalization at each fixed sourcequery coordinate: compare the sourcequery longitude/latitude with the same query positions supplied to the height-only generalization. Generalization has no horizontal coordinate operator. Independently reconstructed query arrays must compare bitwise; nonidentity is failure. Source/height/model mapping remains unchanged.',method='Construct sourcequery positions independently from native source affine indices; construct generalized surfacequery positions from the identical affine sourcegeography that sample_bilinear actually uses. Check np.array_equal on each coordinate array; compute unrounded geodetic displacement between these paired arrays. No threshold rounding.',budget_m=0,projection_roundtrip='Forward/inverse projection diagnostic retained separately, including ~1e-9m finite-precision residuals. It is not horizontal displacement introduced by the height-only generalization. Does not claim renderer Float32 positions or actual mesh/morph accuracy.',supersedes='v2 mislabeled numerical forward/inverse projection roundtrip as terrain generalization displacement. v2 strict0 policy failed its old measurement; no pass relabeling for that old result.'))
pol=read('data/geodata_policy.json');oldbudgets={x['id']:x['budgets']for x in pol['levels']};pol['revision']='policy-v3'
plan=read('data/sampling-plan.json');plan['revision']='policy-v3';plan['horizontal_metric']='data/horizontal-metric.json; source-query identity, projection numerical roundtrip separate; no rounding or budget change';plan['coast_sampling']='Same fixed every17th exterior vertex and same2340points; overviewwater increased4096x3072; 6000m limit unchanged';write('data/sampling-plan.json',plan)
for level in pol['levels']:level['sampling_plan']=ref('data/sampling-plan.json')
dec=read('data/policy-decision.json');dec['revision']='policy-v3';dec['targeted_v3_repair']='v2overviewcoast6418.557m>6000m. Improve derived overviewwater to4096x3072, do not change any budget; actual runtime already shares8192x6144shoreline at everyzoom. Horizontal queryidentity separated from numeric projectionroundtrip before newmeasurement. Height/classes/nativewater/riverpayloads unchanged.';write('data/policy-decision.json',dec)
pol['decision']=ref('data/policy-decision.json');pol['model_render_transition']=ref('docs/product-renderer/camera-profile.json');assert oldbudgets=={x['id']:x['budgets']for x in pol['levels']};write('data/geodata_policy.json',pol)
j=read('data/jobs.json');j['revision']='data-jobs-v3'
for x in j['jobs']:
 if x['session_id']==15288:x['state']='terminal download complete; unused legacy60s source excluded from v3export and v3source manifest';x['actual_bytes']=(ROOT/x['output']).stat().st_size
write('data/jobs.json',j)
print('v3 wateroverview derived; originalv2 snapshot preserved. Policybudgets unchanged; ready for targeted remeasurement.')
