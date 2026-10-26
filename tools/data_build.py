#!/usr/bin/env python3
"""Build frozen regional terrain and physical vectors from actual sources.
Requires prebound region/policy. Uses existing GDAL and numpy, no installs.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import json,hashlib,pathlib,math
import numpy as np
from osgeo import gdal,ogr
from data_bind import ROOT,ref,save,read,feature,geom
gdal.UseExceptions();ogr.UseExceptions()
B=read('data/region.json')['extent']; W,E,S,N=[B[k] for k in ['west','east','south','north']]; D=ROOT/'data/derived'
D.mkdir(exist_ok=True)
width,height=3420,2220 # 60arcsec exact source cells across bound region
bounds=[W,S,E,N]
def output_array(name,a):
 p=D/name;a.tofile(p);return dict(path=name,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),bytes=p.stat().st_size)
def warp(src,width,height,resample='bilinear'):
 return gdal.Warp('',str(src),options=['-novshift'],format='MEM',outputBounds=bounds,width=width,height=height,dstSRS='EPSG:4326',resampleAlg=resample).ReadAsArray()
# Freeze geographic physical features; preserve exact clipped geometry, never
# invent small waterways. A 1:10M source has limited near detail.
clip=ogr.CreateGeometryFromWkt(f'POLYGON(({W} {S},{E} {S},{E} {N},{W} {N},{W} {S}))')
vector_stats={}
for kind,name in [('land','ne_10m_land.geojson'),('rivers','ne_10m_rivers_lake_centerlines.geojson'),('lakes','ne_10m_lakes.geojson')]:
 src=ogr.Open(str(ROOT/'data/raw'/name));layer=src.GetLayer();layer.SetSpatialFilterRect(W,S,E,N);fs=[];invalid=0
 for f in layer:
  g=f.GetGeometryRef()
  if not g.IsValid():invalid+=1;g=g.MakeValid()
  cut=g.Intersection(clip)
  if cut.IsEmpty():continue
  props=json.loads(f.ExportToJson())['properties'];props['source_id']=str(props.get('ne_id',f.GetFID()));fs.append(feature(cut,props))
 save('data/derived/'+kind+'.geojson',dict(type='FeatureCollection',features=fs))
 vector_stats[kind]=dict(features=len(fs),input_invalid_repaired=invalid,output_invalid=sum(not geom(f).IsValid() for f in fs),output_sha256=ref('data/derived/'+kind+'.geojson')['sha256'])
# Water domain uses NE polygon raster rather than elevation sign (Dead Sea
# depression must not turn into ocean). Lakes have an independent physical source.
def mask_at(w,h):
 ds=gdal.GetDriverByName('MEM').Create('',w,h,1,gdal.GDT_Byte);ds.SetGeoTransform([W,(E-W)/w,0,N,0,-(N-S)/h]);ds.SetProjection('EPSG:4326');ds.GetRasterBand(1).Fill(0)
 land=ogr.Open(str(D/'land.geojson'));gdal.RasterizeLayer(ds,[1],land.GetLayer(),burn_values=[1]);a=(1-ds.ReadAsArray()).astype('uint8');ds.GetRasterBand(1).WriteArray(a)
 lake=ogr.Open(str(D/'lakes.geojson'));gdal.RasterizeLayer(ds,[1],lake.GetLayer(),burn_values=[2]);a=ds.ReadAsArray();return a.astype('uint8')
raw=ROOT/'data/raw/ETOPO_2022_v1_60s_N90W180_surface.tif'
fine=ROOT/'data/etopo15-inventory.json'
if fine.exists():
 tiles=read('data/etopo15-inventory.json')['sources'];gdal.BuildVRT(str(D/'elevation-source.vrt'),[str(ROOT/t['path']) for t in tiles]);raw=D/'elevation-source.vrt'
ds=gdal.Open(str(raw));print('DEM opened',ds.RasterXSize,ds.RasterYSize,flush=True)
z=warp(raw,width,height).astype('<f4'); water=mask_at(width,height)
if not np.isfinite(z).all():raise RuntimeError('Unresolved DEM NoData')
# Assemble native last-overview observations. Each snapshot losslessly frozen.
inv=read('data/worldcover-inventory.json');paths=[str(ROOT/t['path']) for t in inv['tiles'] if t['status']=='downloaded'];vrt=gdal.BuildVRT(str(D/'worldcover.vrt'),paths);vrt=None
classes=warp(D/'worldcover.vrt',width,height,'near').astype('uint8');classes[water>0]=80
unknown=int(np.count_nonzero((classes==0)&(water==0)))
# Explicit unresolved unknown remains 0; not invented vegetation.
wdw,wdh=8192,6144;wd=mask_at(wdw,wdh);output_array('water-detail.u8',wd)
assets={}
for name,a in [('height.f32',z),('landcover.u8',classes),('water.u8',water)]:assets[name]=output_array(name,a)
# PNGs for cross-engine inspection; raw grids remain authoritative.
for name,a in [('water',(water>0).astype('uint8')*255),('landcover',classes)]:
 m=gdal.GetDriverByName('MEM').Create('',width,height,1,gdal.GDT_Byte);m.GetRasterBand(1).WriteArray(a);gdal.Translate(str(D/(name+'.png')),m,format='PNG')
# Overview is derived from same ETOPO, not an independent geography.
w,h=2048,1536;over=warp(raw,w,h).astype('<f4'); ow=mask_at(4096,3072)
output_array('overview-height.f32',over);output_array('overview-water.u8',ow)
fine_fields={}
if fine.exists():
 fw,fh=13680,8880;fz=warp(raw,fw,fh).astype('<f4');output_array('height-detail.f32',fz);fine_fields=dict(height_detail_path='height-detail.f32',height_detail_width=fw,height_detail_height=fh)
manifest=dict(**fine_fields,schema_version='landscape-data-v1',dataset_revision='landscape-v3',region_revision='region-v1',mask_revision='mask-v1',mapping_revision='mapping-v1',width=width,height=height,bounds=B,sample_registration='pixel_center',row_order='north_to_south',height_path='height.f32',class_path='landcover.u8',water_path='water.u8',water_detail_path='water-detail.u8',water_detail_width=wdw,water_detail_height=wdh,height_encoding='Float32LE',height_units='metres EGM2008',class_encoding='UInt8 ESA WorldCover codes (0 unknown,80 water)',water_encoding='UInt8 0 land 1 ocean 2 inland lakes; only ocean has sea-level surface0; inland lake levels inherit uncertain source heights',projection=read('data/projection.json'),source_to_model_scale=.001,vertical_exaggeration=1,assets=assets,rivers_path='rivers.geojson',lakes_path='lakes.geojson',vector_paths=dict(land='land.geojson',rivers='rivers.geojson',lakes='lakes.geojson'),source_quality=('ETOPO15s native elevation (245-433m east-west;463m north-south).' if fine.exists() else 'ETOPO60s native elevation (~1-1.85km).')+' WorldCover last overview (~0.6km). Natural Earth1:10M physical water. No fabricated small relief or historical vegetation.',nodata=dict(elevation=0,landcover_land_cells=unknown),overview=dict(width=w,height=h,height_path='overview-height.f32',water_path='overview-water.u8',water_width=4096,water_height=3072),water_lod_policy='Runtime shares water-detail8192x6144 at all zooms; canonical fallback and offline4096x3072overview separate',tile_grid='../tile-grid.json')
for filename in ['height-detail.f32','water-detail.u8','rivers.geojson','lakes.geojson','land.geojson','overview-height.f32','overview-water.u8']:
 p=D/filename
 if p.exists():manifest['assets'][filename]=dict(path=filename,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),bytes=p.stat().st_size)
save('data/derived/landscape.json',manifest)
save('data/derived/inventory.json',dict(revision='landscape-v3',region_revision='region-v1',gdal_version=gdal.VersionInfo('--version'),native_elevation_grid=[ds.RasterXSize,ds.RasterYSize],canonical_dimensions=[width,height],total_cells=width*height,land_cells=int(np.count_nonzero(water==0)),ocean_lake_cells=int(np.count_nonzero(water)),unknown_landcover_cells=unknown,elevation_min=float(z.min()),elevation_max=float(z.max()),class_histogram={str(k):int(v) for k,v in zip(*np.unique(classes,return_counts=True))},vectors=vector_stats,worldcover_sources=len(paths),unavailable_worldcover=[t['id'] for t in inv['tiles'] if t['status']!='downloaded'],source_vrt_sha256=ref(raw)['sha256'],source_vrt_hash_scope='VRTdescriptorhash; originalTIFFhashes in etopo15-inventory.json'))
print('BUILT',width,height,'unknown_landcover',unknown,flush=True)
