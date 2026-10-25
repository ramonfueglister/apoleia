#!/usr/bin/env python3
"""Read-only v2→v3 delta check; reuse v2 source verification by immutable hash."""
import datetime
import hashlib
import json
import math
import pathlib
import numpy as np

ROOT=pathlib.Path(__file__).resolve().parents[3]
RUN=pathlib.Path(__file__).resolve().parents[1]
ARCHIVE=RUN/'data-revisions/landscape-v2'
def read(p):return json.loads(p.read_text())
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
m=read(ROOT/'data/derived/landscape.json')
old=read(RUN/'independent-review/data-v2-check.json')
out={'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
     'dataset_revision':m['dataset_revision'],'manifest_sha256':sha(ROOT/'data/derived/landscape.json'),
     'runtime_executed':False,'payloads':[]}
old_payload={p['path']:p['sha256'] for p in old['hash_checks']}
for name,asset in m['assets'].items():
    p=ROOT/'data/derived'/name;export=RUN/'data/derived'/name
    actual=sha(p)
    out['payloads'].append({'path':str(p.relative_to(ROOT)),'sha256':actual,
        'matches_manifest':actual==asset['sha256'],'changed_from_v2':actual!=old_payload[str(p.relative_to(ROOT))],
        'export_hash_matches':actual==sha(export)})
policy=read(ROOT/'data/geodata_policy.json');v2_policy=read(ARCHIVE/'data/geodata_policy.json')
out['budgets_unchanged']=([s['budgets']for s in policy['levels']]==[s['budgets']for s in v2_policy['levels']])
previous=np.loadtxt(ARCHIVE/'data/derived/coast-overview.csv',delimiter=',',skiprows=1)
current=np.loadtxt(ROOT/'data/derived/coast-overview.csv',delimiter=',',skiprows=1)
out['coast_samples_same_coordinates_order']=np.array_equal(previous[:,:2],current[:,:2])
out['coast_sample_count']=len(current)
o=m['overview'];a=np.memmap(ROOT/'data/derived'/o['water_path'],dtype='u1',shape=(o['water_height'],o['water_width']))
water=a>0;edge=np.zeros_like(water)
edge[1:]|=water[1:]!=water[:-1];edge[:-1]|=water[1:]!=water[:-1]
edge[:,1:]|=water[:,1:]!=water[:,:-1];edge[:,:-1]|=water[:,1:]!=water[:,:-1]
b=m['bounds'];height,width=a.shape;lon=current[:,0];lat=current[:,1]
x=((lon-b['west'])/(b['east']-b['west'])*width).astype(int)
y=((b['north']-lat)/(b['north']-b['south'])*height).astype(int)
best=np.full(len(lon),np.inf);R=6371008.8
for dy in range(-8,9):
    for dx in range(-8,9):
        xx=np.clip(x+dx,0,width-1);yy=np.clip(y+dy,0,height-1)
        lx=b['west']+(xx+.5)/width*(b['east']-b['west'])
        ly=b['north']-(yy+.5)/height*(b['north']-b['south'])
        distances=np.hypot(np.radians(lx-lon)*R*np.cos(np.radians(lat)),np.radians(ly-lat)*R)
        best=np.minimum(best,np.where(edge[yy,xx],distances,np.inf))
out['coast_overview_independent']={'maximum_m':float(best.max()),'missing_count':int(np.count_nonzero(~np.isfinite(best))),
    'csv_maximum_m':float(current[:,2].max()),'maximum_distance_from_reported_m':float(np.max(np.abs(best-current[:,2]))),
    'budget_m':6000,'all_within_budget':bool(np.all(best<=6000)),
    'raw_sha256':sha(ROOT/'data/derived/coast-overview.csv')}
h=np.loadtxt(ROOT/'data/derived/horizontal-generalization.csv',delimiter=',',skiprows=1)
out['horizontal_generalization']={'samples':len(h),'coordinate_pairs_bit_equal_after_csv_read':bool(np.array_equal(h[:,:2],h[:,2:4])),
    'raw_displacement_maximum_m':float(h[:,4].max()),'nonzero_displacements':int(np.count_nonzero(h[:,4])),
    'raw_sha256':sha(ROOT/'data/derived/horizontal-generalization.csv'),
    'definition_sha256':sha(ROOT/'data/horizontal-metric.json'),
    'retained_roundtrip_sha256':sha(ROOT/'data/derived/horizontal-roundtrip.csv')}
anchor=read(ROOT/'data/anchors.json')['anchors'][0]
z=np.memmap(ROOT/'data/derived/height.f32',dtype='<f4',shape=(m['height'],m['width']))
actual=float(z[anchor['canonical_row'],anchor['canonical_col']])
out['alpine_anchor']={'declared_height_m':anchor['height_m'],'actual_canonical_height_m':actual,'matches':actual==anchor['height_m']}
journal=read(ROOT/'data/transformations.json');inv=read(ROOT/'data/derived/inventory.json')
out['metadata']={'journal_revision':journal['revision'],'inventory_has_misleading_full_source_field':'full_source_sha256'in inv,
    'source_vrt_sha256':inv['source_vrt_sha256'],'source_vrt_hash_matches':inv['source_vrt_sha256']==sha(ROOT/'data/derived/elevation-source.vrt')}
out['changed_input_snapshot']={str(p.relative_to(ROOT)):sha(p) for p in [ROOT/'data/derived/landscape.json',ROOT/'data/geodata_policy.json',ROOT/'data/derivation.json',ROOT/'data/anchors.json',ROOT/'data/transformations.json',ROOT/'data/horizontal-metric.json']}
print(json.dumps(out,indent=2))
