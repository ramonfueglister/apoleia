#!/usr/bin/env python3
"""Freeze WorldCover COG overview observations, with per-window hashes/metadata.
Source COGs are read at their actual native 562x562 overview. No full-file SHA is
claimed for remotely range-read COGs: hashes cover downloaded overview snapshots.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
os.environ['GDAL_DISABLE_READDIR_ON_OPEN']='EMPTY_DIR'
os.environ['CPL_VSIL_CURL_ALLOWED_EXTENSIONS']='.tif'
os.environ['GDAL_HTTP_MAX_RETRY']='2'
import json,pathlib,hashlib,concurrent.futures,time
from osgeo import gdal
import numpy as np
gdal.UseExceptions()
import argparse,math
ROOT=pathlib.Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--out',default='data/raw/worldcover');ap.add_argument('--atlas-manifest',help='cover every 3 degree tile intersecting this eqc node grid (plus a one-tile margin) instead of the fixed region positions');ap.add_argument('--seed-from',help='existing tile folder; its files are linked first and not downloaded again');cli=ap.parse_args()
OUT=ROOT/cli.out;OUT.mkdir(parents=True,exist_ok=True)
if cli.seed_from:
 for f in (ROOT/cli.seed_from).iterdir():
  if not (OUT/f.name).exists():(OUT/f.name).symlink_to(f.resolve())
b=json.loads((ROOT/'data/region.json').read_text())['extent']
def one(pos):
 lat,lon=pos; name=f'N{lat:02d}'+('E' if lon>=0 else 'W')+f'{abs(lon):03d}'
 path=OUT/(name+'.tif'); meta=OUT/(name+'.json')
 if path.exists() and meta.exists():return json.loads(meta.read_text())
 url=f'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{name}_Map.tif'
 try:
  ds=gdal.Open('/vsicurl/'+url);band=ds.GetRasterBand(1); ov=band.GetOverview(band.GetOverviewCount()-1)
  arr=ov.ReadAsArray();drv=gdal.GetDriverByName('GTiff');out=drv.Create(str(path),arr.shape[1],arr.shape[0],1,gdal.GDT_Byte,['COMPRESS=DEFLATE']);out.SetGeoTransform([lon,3/arr.shape[1],0,lat+3,0,-3/arr.shape[0]]);out.SetProjection(ds.GetProjection());out.GetRasterBand(1).WriteArray(arr);out.GetRasterBand(1).SetNoDataValue(0);out=None
  r=dict(id=name,url=url,version='2021-v200',source_grid=[ds.RasterXSize,ds.RasterYSize],overview_grid=list(arr.shape[::-1]),source_metadata=ds.GetMetadata(),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),path=str(path.relative_to(ROOT)),bytes=path.stat().st_size,full_cog_sha256=None,hash_scope='frozen GDAL lossless overview observation, not entire source COG',status='downloaded')
 except Exception as e:r=dict(id=name,url=url,status='unavailable',error=str(e))
 meta.write_text(json.dumps(r,indent=2)+'\n');print(name,r['status'],flush=True);return r
positions=[(lat,lon) for lat in range(21,60,3) for lon in range(-12,48,3)]
if cli.atlas_manifest:
 m=json.loads((ROOT/cli.atlas_manifest).read_text());R=6371008.8;K=math.pi/180*R*.001;CX=K*math.cos(math.radians(41))
 x0,z0=m['world_min'];w,h=m['world_size']
 west,east,south,north=19+x0/CX,19+(x0+w)/CX,41-(z0+h)/K,41-z0/K
 positions=[(lat,lon) for lat in range(int(math.floor(south/3))*3-3,int(math.ceil(north/3))*3+3,3) for lon in range(int(math.floor(west/3))*3-3,int(math.ceil(east/3))*3+3,3) if -60<=lat<=81]
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:results=list(ex.map(one,positions))
(ROOT/('data/worldcover-inventory.json' if not cli.atlas_manifest else 'artifacts/render-data/landcover-node-2km/worldcover-inventory.json')).write_text(json.dumps(dict(revision='worldcover-overview-v1',note='562-pixel native COG overviews ~0.00534 degree; source10m does not become delivered10m. Full source object hashes unknown; reproducibility freezes each downloaded subset.',tiles=results),indent=2)+'\n')
print('DONE',len(results),sum(r['status']=='downloaded' for r in results),flush=True)
