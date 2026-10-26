#!/usr/bin/env python3
"""Subpixel shoreline render representation from frozen physical source vectors."""
import hashlib,json,math,pathlib,time
import numpy as np
root=pathlib.Path(__file__).resolve().parents[2];out=root/'artifacts/render-data';out.mkdir(parents=True,exist_ok=True)
m=json.loads((root/'data/derived/landscape.json').read_text());b=m['bounds'];w=m['water_detail_width'];h=m['water_detail_height'];radius=3000.
policy=root/'docs/product-renderer/water-distance-policy-v2.json';sources=[root/'data/derived/land.geojson',root/'data/derived/lakes.geojson',root/'data/derived/water-detail.u8']
hashes={str(p.relative_to(root)):hashlib.file_digest(p.open('rb'),'sha256').hexdigest()for p in sources}
identity={'policy_sha256':hashlib.file_digest(policy.open('rb'),'sha256').hexdigest(),'source_sha256':hashes,'width':w,'height':h,'bounds':b}
meta=out/'water-distance-rg8.json';payload=out/'water-distance-rg8.bin'
if meta.exists() and payload.exists():
 old=json.loads(meta.read_text())
 if old.get('identity')==identity and hashlib.file_digest(payload.open('rb'),'sha256').hexdigest()==old['payload_sha256']:
  print('Validated existing vector-water-distance-rg8-v2');raise SystemExit()
R=6371008.8;sx=math.radians(b['east']-b['west'])*R*math.cos(math.radians(41))/w;sy=math.radians(b['north']-b['south'])*R/h
field=np.full((h,w),radius,dtype=np.float32);segments=0;excluded=0

def rings(geom):
 typ=geom.get('type');coords=geom.get('coordinates',[])
 if typ=='Polygon':yield from coords
 elif typ=='MultiPolygon':
  for polygon in coords:yield from polygon

def on_clip(a,bp):
 return any(abs(a[k]-v)<1e-8 and abs(bp[k]-v)<1e-8 for k,v in [(0,b['west']),(0,b['east']),(1,b['south']),(1,b['north'])])

start=time.monotonic()
for source in sources[:2]:
 for feature in json.loads(source.read_text())['features']:
  for ring in rings(feature['geometry']):
   for a,bp in zip(ring,ring[1:]):
    if on_clip(a,bp):excluded+=1;continue
    ax=(a[0]-b['west'])/(b['east']-b['west'])*w-.5;ay=(b['north']-a[1])/(b['north']-b['south'])*h-.5
    bx=(bp[0]-b['west'])/(b['east']-b['west'])*w-.5;by=(b['north']-bp[1])/(b['north']-b['south'])*h-.5
    x0=max(0,math.floor(min(ax,bx)-radius/sx));x1=min(w-1,math.ceil(max(ax,bx)+radius/sx));y0=max(0,math.floor(min(ay,by)-radius/sy));y1=min(h-1,math.ceil(max(ay,by)+radius/sy))
    if x1<x0 or y1<y0:continue
    dx=(bx-ax)*sx;dy=(by-ay)*sy;den=dx*dx+dy*dy
    if den<1e-16:continue
    xx=(np.arange(x0,x1+1,dtype=np.float64)-ax)[None,:]*sx;yy=(np.arange(y0,y1+1,dtype=np.float64)-ay)[:,None]*sy
    t=np.clip((xx*dx+yy*dy)/den,0,1);distance=np.hypot(xx-t*dx,yy-t*dy)
    tile=field[y0:y1+1,x0:x1+1];np.minimum(tile,distance,out=tile);segments+=1
kind=np.memmap(sources[2],dtype='u1',mode='r',shape=(h,w));max_quant=0.
with payload.open('wb') as f:
 for y in range(h):
  signed=field[y].astype(np.float64)*np.where(kind[y]>0,1.,-1.)
  code=np.floor((signed+4096.)*8+.5).astype(np.uint16)
  decoded=code.astype(np.float64)*.125-4096.;max_quant=max(max_quant,float(np.max(abs(decoded-signed))))
  packed=np.empty((w,2),dtype=np.uint8);packed[:,0]=code>>8;packed[:,1]=code&255;f.write(packed.tobytes())
report={'schema_version':'renderer-water-distance-v1','revision':'vector-water-distance-rg8-v2','identity':identity,'payload_sha256':hashlib.file_digest(payload.open('rb'),'sha256').hexdigest(),'bytes':payload.stat().st_size,'segments_measured':segments,'artificial_region_clip_segments_excluded':excluded,'sx_projected_m':sx,'sy_projected_m':sy,'quantization_max_projected_m':max_quant,'elapsed_seconds':time.monotonic()-start,'zero_isoline_source_accuracy':'not inferred from quantization; independent data-owner probe required','policy':json.loads(policy.read_text())}
meta.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
