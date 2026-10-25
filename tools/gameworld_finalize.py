#!/opt/homebrew/bin/python3.14
"""Bind completed canonical domains into immutable-by-revision renderer contract.
Partial core is explicitly excluded from raster detail until every block exists.
"""
import argparse,gzip,hashlib,json,pathlib
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v1';PAY=OUT/'payload'
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def save(p,d):
 tmp=p.with_suffix(p.suffix+'.tmp');tmp.write_text(json.dumps(d,indent=2)+'\n');tmp.replace(p)
def compact():
 for domain in ['core','context']:
  for kind,key in [('forest-groups','groups'),('material-zones','omitted_components')]:
   p=OUT/(domain+'-'+kind+'.json')
   if not p.exists():continue
   d=json.loads(p.read_text())
   if key not in d:continue
   items=d.pop(key);gp=PAY/(domain+'-'+kind+'-inventory.jsonl.gz')
   with gp.open('wb') as base:
    with gzip.GzipFile(filename='',mode='wb',fileobj=base,compresslevel=6,mtime=0) as f:
     for item in items:f.write((json.dumps(item,separators=(',',':'))+'\n').encode('utf-8'))
   d[key+'_count']=len(items);d[key+'_inventory']=ref(gp);save(p,d)

def manifest():
 compact();source=json.loads((OUT/'source-observations.json').read_text());active_policy=next(OUT/x for x in ['model-world-policy-v3.json','model-world-policy-v2.json','model-world-policy.json'] if (OUT/x).exists());policy=json.loads(active_policy.read_text());ctx=json.loads((OUT/'context-mesh-manifest.json').read_text());core=json.loads((OUT/'core-mesh-manifest.json').read_text());cz=json.loads((OUT/'context-material-zones.json').read_text());dz=json.loads((OUT/'core-material-zones.json').read_text())
 b=ctx['bounds'];cw,ch=cz['dimensions'];hw,hh=ctx['height_dimensions'];assets={}
 def add(p):
  p=pathlib.Path(p);p=p if p.is_absolute() else OUT/p;r=ref(p);rel=str(p.relative_to(OUT));assets[rel]=dict(path=rel,sha256=r['sha256'],bytes=r['bytes']);return rel
 m=dict(schema_version='gameworld-landscape-v1',dataset_revision='gameworld-v1',mapping_revision='mapping-v1',region_revision='region-v1',mask_revision='mask-v1',bounds=b,core_bounds=dict(zip(['west','south','east','north'],policy['source_bounds']['core'])),render_context_bounds=b,width=hw,height=hh,class_width=cw,class_height=ch,height_width=hw,height_height=hh,height_path=add(PAY/'context-model-height.f32'),class_path=add(PAY/'context-classes.u8'),material_path=add(PAY/'context-material.u8'),surface_weights_path=add(PAY/'context-surface-weights.rgba8'),surface_weights_width=cw,surface_weights_height=ch,surface_weights_bounds=b,water_path=add(PAY/'context-water.u8'),water_width=7380,water_height=2580,water_detail_path=add(PAY/'core-water.u8'),water_detail_width=8192,water_detail_height=6144,water_detail_bounds=dict(zip(['west','south','east','north'],policy['source_bounds']['core'])),height_encoding='Float32LE source metres encoded from reduced canonical TIN; not native DEM',height_units='metres EGM2008',sample_registration='pixel_center',row_order='north_to_south',projection=json.loads((ROOT/'data/projection.json').read_text()),source_to_model_scale=.001,vertical_exaggeration=1,source_quality='ETOPO2022v1 native15s core/60s context; ESA2021v200 last-overview observations; NE5.1.2 1:10M. Measurement accuracy unknown. Canonical terrain reduced through adaptive TIN45m source-sample maximum budget, not raw DEM scaling.',model_policy=ref(active_policy),canonical_model='adaptive source-vertex TIN + semantic material zones + connected forest groups + simplified physicalwater',feature_mesh_manifest_path=add(OUT/'core-mesh-manifest.json'),context_mesh_manifest_path=add(OUT/'context-mesh-manifest.json'),forest_groups_path=add(OUT/'core-forest-groups.json'),forest_group_labels_path=add(PAY/'core-forest-groups.u32'),forest_interior_distance_path=add(PAY/'core-forest-interior.f32'),forest_group_width=10260,forest_group_height=6660,forest_group_bounds=dict(zip(['west','south','east','north'],policy['source_bounds']['core'])),forest_density_policy=dict(edge=.42,core=.88,transition_source_m=900,representative_spacing_source_m=20,edge_spacing_source_m=28,core_crown_lobes=3,edge_crown_lobes=[1,2],seed=117180),material_zones_path=add(OUT/'context-material-zones.json'),detail_material_zones_path=add(OUT/'core-material-zones.json'),detail_class_path=add(PAY/'core-classes.u8'),detail_class_width=10260,detail_class_height=6660,detail_class_bounds=dict(zip(['west','south','east','north'],policy['source_bounds']['core'])),detail_material_path=add(PAY/'core-material.u8'),detail_surface_weights_path=add(PAY/'core-surface-weights.rgba8'),detail_surface_weights_width=10260,detail_surface_weights_height=6660,detail_surface_weights_bounds=dict(zip(['west','south','east','north'],policy['source_bounds']['core'])),rivers_path=add(PAY/'rivers.geojson'),lakes_path=add(PAY/'lakes.geojson'),vector_paths=dict(land=add(PAY/'land.geojson'),rivers=add(PAY/'rivers.geojson'),lakes=add(PAY/'lakes.geojson')),tile_grid='../tile-grid.json',nodata=dict(elevation=0,landcover_land_cells=0),model_completion=dict(context='complete',core=core['status'],core_blocks=len(core['blocks']),core_expected_blocks=1890),render_contract='data/gameworld-v1/render-derivation-policy.json')
 if (OUT/'water-render-tiles.json').exists():m['water_tile_manifest_path']=add(OUT/'water-render-tiles.json')
 if core['status']!='partial' and len(core['blocks'])==1890:
  m.update(height_detail_path=add(PAY/'core-model-height.f32'),height_detail_width=13680,height_detail_height=8880,height_detail_bounds=m['core_bounds'])
 for p in [OUT/'water-model.json',OUT/'source-observations.json',OUT/'source-context-inventory.json',OUT/'model-world-policy.json',OUT/'render-derivation-policy.json',OUT/'feature-protection.json',OUT/'model-world-policy-v2.json',OUT/'model-world-policy-v3.json',OUT/'sources.json',OUT/'source-resampling-policy.json',OUT/'source-resampling-measurements.json',OUT/'coverage-measurements.json']:
  if p.exists():add(p)
 m['assets']=assets;save(OUT/'landscape.json',m)
 save(OUT/'source-to-model-map.json',dict(schema_version='gameworld-derivation-v1',revision='gameworld-v1',source_observations=ref(OUT/'source-observations.json'),policy=ref(OUT/'model-world-policy.json'),canonical_meshes=[ref(OUT/(d+'-mesh-manifest.json')) for d in ['core','context']],semantics=[ref(OUT/(d+'-material-zones.json')) for d in ['core','context']],forest_groups=[ref(OUT/(d+'-forest-groups.json')) for d in ['core','context']],water=ref(OUT/'water-model.json'),renderer_manifest=ref(OUT/'landscape.json'),source_model_render_separation='native observations unmodified; reduced TIN with declared source budget; semantic spatial aggregation and controlled contour simplification; uploadLODpixel/relief errors are separate renderer observations',reference_version='kit1-landscape-v5/astra-replan-v2'))
 print('manifest ready',m['model_completion'],flush=True)
def main():
 a=argparse.ArgumentParser();a.add_argument('--compact-only',action='store_true');v=a.parse_args();compact() if v.compact_only else manifest()
if __name__=='__main__':main()
