#!/usr/bin/env python3
import json
from data_bind import ROOT,save,read,ref
r=read('data/region.json');sources=read('data/sources.json')['sources'];byrole={role:[s['id']for s in sources if s['role']==role]for role in ['elevation','water','landcover']};allids=sum(byrole.values(),[]);evidence=[ref('data/derived/coverage-measurements.json'),ref('data/derived/topology-measurements.json')]
roles=[dict(role=k,source_ids=v)for k,v in byrole.items()]
dom=[]
for id in ['land','ocean']:
 rr=roles if id=='land'else[dict(role='water',source_ids=byrole['water'])]
 dom.append(dict(id=id,status='validiert',source_ids=allids if id=='land'else byrole['water'],represented_fraction=1,unresolved_nodata_fraction=0,render_policy='Data-domain pixel census complete; land heights signedEGM2008; ocean surface0; inland lakes retain uncertain DEMheight; native resolution limits documented.',evidence=evidence,role_bindings=rr))
sp=[dict(id=id,status='offen',bounds=r['extent'],source_ids=allids,finding='Offline geographic source coverage complete; runtime seam/coast/mapedge render inspection remains independent.',evidence=evidence,domain_ids=['land','ocean'],role_bindings=roles)for id in ['region_boundary','coastal_interfaces','tile_seams']]
refs=[dict(id=x['id'],represented_fraction=1,evidence=[ref('data/reference/completeness.json')],reference_geometry_id=x['id'],reference_revision=x['revision'],reference_source_id=x['source_id'],reference_source=x['source'],mask_revision=r['mask_revision'])for x in r['reference_geometries']]
treat=[]
for cls,codes in [('cultivated_fields',['40']),('plantations',['10','20','40']),('managed_areas',['10','20','30','40']),('built_up',['50']),('transport',['50'])]:
 treat.append(dict(semantic_class=cls,source_ids=byrole['landcover'],source_class_codes=codes,treatment='abstract',rationale='Homogeneous natural-looking material, no source color textures, field geometry, plantation rows, streets or built objects. WorldCover does not separately identify every managed forest or transport class; no reconstruction of untouched natural vegetation.',evidence=[ref('data/detail-rules.json')],visible_result='unresolved'))
save('data/coverage.json',dict(schema_version='kit1-ops-v5',kind='coverage',synthetic=False,revision='coverage-v3',run_id='kit1-landscape-v5-2026-10-25',sources_revision='sources-v1',mapping_revision='mapping-v1',crs='EPSG:4326',extent=r['extent'],method=ref('data/derived/coverage-measurements.json'),domains=dom,special_regions=sp,nodata=[dict(id='wc-ocean-only-tiles',domain='ocean',status='resolved',description='Eleven unavailable WorldCover sourceCOGs intersect only non-land at canonical census resolution.',treatment='NEphysical land/lakes supplies explicit waterdomain. No landcoverunknown cells remain in full canonical census. This is resolution-bound, not proof of every tiny island.',evidence=evidence)],landcover_treatments=treat,region_revision=r['revision'],region_definition=ref('data/region.json'),reference_components=refs))
print('coverage generated')
