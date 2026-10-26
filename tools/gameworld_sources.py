#!/opt/homebrew/bin/python3.14
"""Prepare immutable source observations for gameworld-v1. No source mutation.
Uses existing Python3.14/GDAL. Fetch mode resumes completed overview observations;
network calls have bounded retry and expose output status, never silent land fill.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
os.environ['GDAL_DISABLE_READDIR_ON_OPEN']='EMPTY_DIR'
os.environ['CPL_VSIL_CURL_ALLOWED_EXTENSIONS']='.tif'
os.environ['GDAL_HTTP_MAX_RETRY']='1'
os.environ['GDAL_HTTP_TIMEOUT']='45'
import argparse,concurrent.futures,hashlib,json,math,pathlib,time
import numpy as np
from osgeo import gdal,ogr
ROOT=pathlib.Path(__file__).resolve().parents[1]; OUT=ROOT/'data/gameworld-v1'; RAW=OUT/'source-observations'
gdal.UseExceptions(); ogr.UseExceptions()
RETRY_UNAVAILABLE=False
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def save(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,indent=2)+'\n')
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def bounds():return json.loads((OUT/'model-world-policy.json').read_text())['source_bounds']['render_context']
def selected():
 w,s,e,n=bounds();w=math.floor(w/3)*3;s=math.floor(s/3)*3;e=math.ceil(e/3)*3;n=math.ceil(n/3)*3
 nx,ny=int((e-w)/3),int((n-s)/3)
 d=gdal.GetDriverByName('MEM').Create('',nx,ny,1,gdal.GDT_Byte);d.SetGeoTransform([w,3,0,n,0,-3]);d.SetProjection('EPSG:4326')
 src=ogr.Open(str(ROOT/'data/raw/ne_10m_land.geojson'));gdal.RasterizeLayer(d,[1],src.GetLayer(),burn_values=[1],options=['ALL_TOUCHED=TRUE'])
 y,x=np.nonzero(d.ReadAsArray());return [(int(n-(yy+1)*3),int(w+xx*3)) for yy,xx in zip(y,x)]

def fetch_one(pos):
 lat,lon=pos;name=f'N{lat:02d}'+('E' if lon>=0 else 'W')+f'{abs(lon):03d}';p=RAW/(name+'.tif');meta=RAW/(name+'.json')
 old=ROOT/'data/raw/worldcover'/(name+'.tif');om=old.with_suffix('.json')
 if old.exists() and om.exists():
  d=json.loads(om.read_text());d['reused_existing_observation']=True;return d
 if p.exists() and meta.exists():return json.loads(meta.read_text())
 url=f'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{name}_Map.tif'
 try:
  ds=gdal.Open('/vsicurl/'+url);b=ds.GetRasterBand(1);ov=b.GetOverview(b.GetOverviewCount()-1);a=ov.ReadAsArray();dso=gdal.GetDriverByName('GTiff').Create(str(p),a.shape[1],a.shape[0],1,gdal.GDT_Byte,['COMPRESS=DEFLATE']);dso.SetGeoTransform([lon,3/a.shape[1],0,lat+3,0,-3/a.shape[0]]);dso.SetProjection(ds.GetProjection());dso.GetRasterBand(1).WriteArray(a);dso.GetRasterBand(1).SetNoDataValue(0);dso=None
  d=dict(id=name,url=url,version='2021-v200',status='downloaded',source_grid=[ds.RasterXSize,ds.RasterYSize],overview_grid=list(a.shape[::-1]),path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size,full_cog_sha256=None,hash_scope='lossless frozen native last-overview observation, not full remote COG')
 except Exception as ex:d=dict(id=name,url=url,status='unavailable',error=str(ex))
 save(meta,d);print(name,d['status'],flush=True);return d

def warp(src,b,wh,alg='bilinear'):
 w,s,e,n=b;return gdal.Warp('',str(src),options=['-novshift'],format='MEM',outputBounds=[w,s,e,n],width=wh[0],height=wh[1],dstSRS='EPSG:4326',resampleAlg=alg).ReadAsArray()
def water(b,wh):
 w,s,e,n=b;d=gdal.GetDriverByName('MEM').Create('',*wh,1,gdal.GDT_Byte);d.SetGeoTransform([w,(e-w)/wh[0],0,n,0,-(n-s)/wh[1]]);d.SetProjection('EPSG:4326');d.GetRasterBand(1).Fill(1)
 for kind,value in [('land',0),('lakes',2)]:
  src=ogr.Open(str(ROOT/f'data/raw/ne_10m_{kind}.geojson'));gdal.RasterizeLayer(d,[1],src.GetLayer(),burn_values=[value])
 return d.ReadAsArray()
def prepare():
 inv=json.loads((OUT/'source-context-inventory.json').read_text());paths=[str(ROOT/t['path']) for t in inv['tiles'] if t['status']=='downloaded'];gdal.BuildVRT(str(RAW/'context-cover.vrt'),paths)
 # Complete source mosaic only, model simplification occurs in gameworld_build.py.
 products={}
 for domain,b,wh in [('context',bounds(),(3690,1290)),('core',[-11,21,46,58],(13680,8880))]:
  z=warp(ROOT/('data/derived/elevation-source.vrt' if domain=='core' else 'data/raw/ETOPO_2022_v1_60s_N90W180_surface.tif'),b,wh).astype('<f4');z.tofile(RAW/(domain+'-height.f32'))
  # Cover on exact60arcsec grid; source observation ~0.00534degrees.
  factor=180 if domain=='core' else 60
  cw,ch=(int(round((b[2]-b[0])*factor)),int(round((b[3]-b[1])*factor)))
  cover=warp(RAW/'context-cover.vrt',b,(cw,ch),'near').astype('u1');wm=water(b,(cw,ch)).astype('u1');cover[wm>0]=80
  cover.tofile(RAW/(domain+'-cover.u8'));wm.tofile(RAW/(domain+'-water.u8'))
  products[domain]=dict(bounds=b,height_dimensions=wh,cover_dimensions=[cw,ch],height=ref(RAW/(domain+'-height.f32')),cover=ref(RAW/(domain+'-cover.u8')),water=ref(RAW/(domain+'-water.u8')),unknown_cover_land=int(np.count_nonzero((cover==0)&(wm==0))),height_nonfinite=int(np.count_nonzero(~np.isfinite(z))))
  print('prepared',domain,products[domain]['unknown_cover_land'],'unknown cover land',flush=True)
 save(OUT/'source-observations.json',dict(revision='gameworld-source-observations-v1',policy=ref(OUT/'model-world-policy.json'),existing_sources=ref(ROOT/'data/sources.json'),context_inventory=ref(OUT/'source-context-inventory.json'),domains=products))
def main():
 a=argparse.ArgumentParser();a.add_argument('action',choices=['fetch','prepare','inventory']);a.add_argument('--workers',type=int,default=4);args=a.parse_args();RAW.mkdir(parents=True,exist_ok=True)
 if args.action=='prepare':prepare();return
 positions=selected();print('selected land-intersecting overview windows',len(positions),flush=True)
 if args.action=='inventory':print(positions);return
 with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:tiles=list(ex.map(fetch_one,positions))
 save(OUT/'source-context-inventory.json',dict(revision='gameworld-context-sources-v1',bounds=bounds(),selection='Natural Earth5.1.2 land geometry bbox intersection, not assumed ocean by missing ESA object',tiles=tiles,legacy_elevation=ref(ROOT/'data/raw/ETOPO_2022_v1_60s_N90W180_surface.tif'),source_policy=ref(OUT/'model-world-policy.json')))
 print('finished',len(tiles),sum(t['status']=='downloaded' for t in tiles),flush=True)
if __name__=='__main__':main()
