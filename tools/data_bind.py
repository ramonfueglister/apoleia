#!/usr/bin/env python3
"""Bind real source geometry and predeclare policy BEFORE processing terrain."""
import json, hashlib, math, pathlib
from osgeo import ogr
ROOT=pathlib.Path(__file__).resolve().parents[1]
def save(p,x):
 p=ROOT/p;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n');return ref(p)
def ref(p):
 p=pathlib.Path(p);p=p if p.is_absolute() else ROOT/p
 return {'artifact_path':str(p.relative_to(ROOT)), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def extent(g):
 w,e,s,n=g.GetEnvelope();return dict(west=w,east=e,south=s,north=n)
def fc(features):return dict(type='FeatureCollection',features=features)
def read(p):return json.loads((ROOT/p).read_text())
def geom(f):return ogr.CreateGeometryFromJson(json.dumps(f['geometry']))
def feature(g,props):return dict(type='Feature',properties=props,geometry=json.loads(g.ExportToJson()))
def main():
 roman=read('data/reference/roman-117.geojson')
 eng=next(f for f in read('data/reference/GBR-ADM1.geojson')['features'] if f['properties']['shapeName']=='England')
 # Natural Earth marine polygons are generalized sea label extents. Union named
 # Mediterranean/subbasin features; source is a scope reference, NOT water mask.
 names={'Mediterranean Sea','Alboran Sea','Balearic Sea','Ligurian Sea','Tyrrhenian Sea','Adriatic Sea','Ionian Sea','Aegean Sea','Sea of Crete','Sea of Marmara','Strait of Gibraltar'}
 marine=[f for f in read('data/reference/marine-10m-v5.1.2.geojson')['features'] if f['properties']['name'] in names]
 save('data/reference/england.geojson',fc([eng]));save('data/reference/mediterranean.geojson',fc(marine))
 refs=[]
 for id,source,path,fs,revision in [('imperial_maximum_extent','awmc117','data/reference/roman-117.geojson',roman['features'],'AWMC-7ecf8bc'),('entire_mediterranean','ne-marine','data/reference/mediterranean.geojson',marine,'NE-v5.1.2'),('england_and_northern_context','gb-england','data/reference/england.geojson',[eng],'gbOpen-9469f09')]:
  union=ogr.Geometry(ogr.wkbMultiPolygon)
  for f in fs:
   g=geom(f)
   if g.GetGeometryType()==ogr.wkbPolygon:union.AddGeometry(g)
   else:
    for sub in g:union.AddGeometry(sub)
  ids=[str(f['properties'].get('shapeID',f['properties'].get('ne_id',f['properties'].get('OBJECTID')))) for f in fs]
  refs.append(dict(id=id,source_id={'awmc117':'imperial_extent_source','ne-marine':'mediterranean_source','gb-england':'england_extent_source'}[source],source=ref(path),revision=revision,crs='EPSG:4326',extent=extent(union),feature_ids=ids))
 # Fixed padding: at least 1.5deg land/context around imperial extent; 2deg north
 # of England. Rounded outward to whole degrees for deterministic source windows.
 w=math.floor(min(r['extent']['west'] for r in refs)-1.5);e=math.ceil(max(r['extent']['east'] for r in refs)+1.5)
 s=math.floor(min(r['extent']['south'] for r in refs)-1.5);n=math.ceil(max(r['extent']['north'] for r in refs)+2)
 b=dict(west=w,east=e,south=s,north=n)
 mask=ogr.CreateGeometryFromWkt(f'POLYGON(({w} {s},{e} {s},{e} {n},{w} {n},{w} {s}))')
 save('data/reference/mask.geojson',fc([feature(mask,{'id':'project-mask-v1','rule':'outward whole-degree envelope + >=1.5deg context, >=2deg England north'})]))
 checks=[]
 for r in refs:
  fs=read(r['source']['artifact_path'])['features']; outside=sum(geom(f).Difference(mask).GetArea() for f in fs)
  checks.append(dict(id=r['id'],outside_mask_square_degrees=outside,feature_count=len(fs),source=r['source']))
 save('data/reference/completeness.json',dict(revision='region-v1',checks=checks,connected_mask=mask.IsValid(),note='Containment computed on actual source polygons. Historical frontier source convention uncertain; no exact 117 truth claim. Mediterranean label polygons are generalized scope references, not shorelines.'))
 region=dict(schema_version='kit1-ops-v5',kind='region',scope_id='roman_maximum_extent_and_mediterranean',reference_extent_year_ce=117,landscape_reference_year_ce=180,crs='EPSG:4326',revision='region-v1',extent=b,boundary_convention='AWMC AD117 outline (ODbL), generalized Natural Earth Mediterranean + named subbasin scope polygons, geoBoundaries England ADM1. Contemporary reference geometries; imperial frontier uncertainty retained. Rectangle includes entire references with contextual land/sea, never political clipping.',sea_context_policy='Full connected rectangular envelope, >=1.5 degrees contextual margin, all sea inside; water classification from real physical/landcover source. No bathymetry required.',imperial_extent_source=refs[0]['source'],mediterranean_source=refs[1]['source'],england_extent_source=refs[2]['source'],region_mask=ref('data/reference/mask.geojson'),completeness_evidence=ref('data/reference/completeness.json'),england_north_latitude=refs[2]['extent']['north'],north_context_degrees=n-refs[2]['extent']['north'],reference_geometries=refs,mask_revision='mask-v1')
 save('data/region.json',region)
 projection=dict(revision='mapping-v1',crs='spherical equidistant cylindrical',proj='+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m',radius_m=6371008.8,center_latitude=41,center_longitude=19,formula='x=R*cos(41deg)*(lon-19deg)*pi/180; z=-R*(lat-41deg)*pi/180; y=height_m; all multiplied by 0.001',model_scale=0.001,vertical_exaggeration=1,choice='Continuous simple regional mapping shared with portable renderer. Distortion measured and disclosed, not geodetic equal-distance or equal-area claim.',extent=b)
 save('data/projection.json',projection)
 save('data/tile-grid.json',dict(schema_version='tile-grid-v1',revision='tile-grid-v1',grid_id='eqc41-km-v1',space='source projected metres before common model scaling',projection=ref('data/projection.json'),cell_size_m=1000,origin_x_m=0,origin_z_m=0,axes=dict(column='east',row='south'),id_format='eqc41-km-v1:{row}:{column}',rule='column=floor(x/1000),row=floor(z/1000); half-open cells [min,max), exact seam assigned east/south; regional mask outer edge retained with clamp to last interior cell. No longitude wrap within project.',lod='Rendering LOD aggregates immutable logical IDs, never changes identity.',coast='Coast/rivers cut cells freely. Raster data pixels and rendering patches are independent address spaces.'))
 # Geodata policy and detail rules are versioned, reviewed immutable inputs.
 # data_bind only reconstructs region/projection/addressing, never overwrites them.
 print(json.dumps(region,indent=2))

if __name__ == '__main__':main()
