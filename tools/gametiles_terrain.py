#!/usr/bin/env python3
"""Per-25-km game-tile terrain statistics (Hochgebirge/Wueste candidates).

Needs only Python 3 stdlib + numpy (own minimal TIFF/COG reader: DEFLATE,
predictor 1 and 3, tiled). No GDAL, no tifffile. Network: HTTPS range reads.

Sources (public COGs, read via HTTP range requests of internal overviews only):
- Copernicus DEM GLO-90 (COP-DEM_GLO-90-DGED, AWS Open Data bucket
  copernicus-dem-90m), 1x1 deg tiles, overview with 300 rows/deg (factor 4 of
  1200, average-downsampled per bucket readme). Missing tiles = ocean = no data.
- ESA WorldCover 10 m 2021 v200, 3x3 deg tiles, overview 1125 px/3 deg
  (1/375 deg, factor 32 of 36000; overview resampling method not stated in file).
Sample grid: cell centres every 1/300 deg in lat and lon over lon -11..46,
lat 21..58; each sample takes the nearest/containing overview pixel of both
sources. Land = WorldCover class not in {0 nodata, 80 permanent water}.
Elevation statistics use land samples with a DEM value; fractions are relative
to all land samples (land without DEM value counts as not above threshold).
Tiles: data/projection.json eqc, col=floor(x/25000), row=floor(z/25000).
Raw overview blobs + per-file metadata (sha256, byte ranges) are cached under
data/raw/gametiles/ (gitignored); reruns reuse the cache.
Outputs: data/gametiles/terrain-25km.csv, data/gametiles/terrain-sources.json.
"""
import json,pathlib,hashlib,struct,zlib,math,time,urllib.request,urllib.error,concurrent.futures,datetime
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1];RAW=ROOT/'data/raw/gametiles';OUT=ROOT/'data/gametiles'
P=json.loads((ROOT/'data/projection.json').read_text());E=P['extent'];R=P['radius_m'];LAT0=P['center_latitude'];LON0=P['center_longitude']
TILE=25000.;SPD=300;BIN=10;BMIN=-500;NB=650
DEMB='https://copernicus-dem-90m.s3.amazonaws.com/';WCB='https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/'
FETCHED=[0]
def get(url,a=None,b=None):
 for k in range(5):
  try:
   req=urllib.request.Request(url,headers={'Range':f'bytes={a}-{b}'} if a is not None else {})
   with urllib.request.urlopen(req,timeout=120) as r:
    d=r.read()
    if a is not None and (r.status!=206 or len(d)!=b-a+1):raise IOError(f'bad range {url} {r.status} {len(d)}')
    FETCHED[0]+=len(d);return d
  except urllib.error.HTTPError as e:
   if e.code==404:return None
   if k==4:raise
  except Exception:
   if k==4:raise
  time.sleep(2**k)
def ifds(h):
 """Parse little-endian classic TIFF IFDs from header bytes h; IndexError if h too short."""
 T={1:(1,'B'),2:(1,'s'),3:(2,'H'),4:(4,'I'),5:(8,'II'),7:(1,'B'),11:(4,'f'),12:(8,'d'),16:(8,'Q')}
 if h[:4]!=b'II*\x00':raise ValueError('not little-endian classic TIFF')
 off=struct.unpack_from('<I',h,4)[0];out=[]
 while off:
  if off+2>len(h):raise IndexError
  n=struct.unpack_from('<H',h,off)[0];tags={}
  if off+6+12*n>len(h):raise IndexError
  for i in range(n):
   tag,typ,cnt=struct.unpack_from('<HHI',h,off+2+12*i);sz,f=T[typ];sz*=cnt;p=off+10+12*i if sz<=4 else struct.unpack_from('<I',h,off+10+12*i)[0]
   if p+sz>len(h):raise IndexError
   tags[tag]=h[p:p+sz] if typ==2 else struct.unpack_from('<'+f*cnt,h,p)
  out.append(tags);off=struct.unpack_from('<I',h,off+2+12*n)[0]
 return out
def fetch_overview(url,path,pick):
 """Cache blob of the overview IFD chosen by pick(ifds) -> index; returns (meta, blob)."""
 meta=path.with_suffix('.json')
 if meta.exists():
  m=json.loads(meta.read_text());return m,(path.read_bytes() if m['status']=='ok' else None)
 hl=16384
 while True:
  h=get(url,0,hl-1)
  if h is None:m=dict(url=url,status='missing',http=404);meta.write_text(json.dumps(m)+'\n');return m,None
  try:I=ifds(h);break
  except IndexError:hl*=4
 i=pick(I);t=I[i];offs,lens=t[324],t[325];blob=b''.join(get(url,o,o+l-1) for o,l in zip(offs,lens));path.write_bytes(blob)
 m=dict(url=url,status='ok',ifd=i,width=t[256][0],height=t[257][0],tile=[t[322][0],t[323][0]],bits=t[258][0],compression=t[259][0],predictor=t.get(317,(1,))[0],sampleformat=t.get(339,(1,))[0],
  lens=list(lens),source_grid=[I[0][256][0],I[0][257][0]],header_bytes=hl,blob_bytes=len(blob),blob_sha256=hashlib.sha256(blob).hexdigest())
 meta.write_text(json.dumps(m)+'\n');return m,blob
def decode(m,blob):
 """Decode cached overview blob to a 2-D array (DEFLATE; predictor 1 uint8 or predictor 3 float32)."""
 assert m['compression']==8,m;tw,th=m['tile'];W,H=m['width'],m['height'];nx=-(-W//tw);ny=-(-H//th);bps=m['bits']//8
 out=np.zeros((ny*th,nx*tw),np.float32 if m['sampleformat']==3 else np.uint8);p=0
 for k,l in enumerate(m['lens']):
  rows=min(th,H-(k//nx)*th);raw=zlib.decompressobj().decompress(blob[p:p+l],rows*tw*bps);p+=l
  a=np.frombuffer(raw,np.uint8).reshape(rows,tw*bps)
  if m['predictor']==3:a=np.cumsum(a,axis=1,dtype=np.uint8).reshape(rows,bps,tw).transpose(0,2,1).copy().view('>f4')[...,0].astype(np.float32)
  else:assert m['predictor']==1 and bps==1,m
  out[(k//nx)*th:(k//nx)*th+rows,(k%nx)*tw:(k%nx+1)*tw]=a
 return out[:H,:W]
def hemi(v,p,n,w):return (p if v>=0 else n)+f'{abs(v):0{w}d}'
def dem_name(lat,lon):return f"Copernicus_DSM_COG_30_{hemi(lat,'N','S',2)}_00_{hemi(lon,'E','W',3)}_00_DEM"
def wc_name(lat,lon):return f"ESA_WorldCover_10m_2021_v200_{hemi(lat,'N','S',2)}{hemi(lon,'E','W',3)}_Map"
def main():
 for d in ('dem','wc'):(RAW/d).mkdir(parents=True,exist_ok=True)
 OUT.mkdir(parents=True,exist_ok=True)
 tl=RAW/'tileList.txt'
 if not tl.exists():tl.write_bytes(get(DEMB+'tileList.txt'))
 have={l.strip() for l in tl.read_text().split()}
 cells=[(la,lo) for la in range(E['south'],E['north']) for lo in range(E['west'],E['east'])]
 wcs=sorted({(E['south']+3*((la-E['south'])//3),-12+3*((lo+12)//3)) for la,lo in cells})
 def dem(c):
  n=dem_name(*c)
  if n not in have:return c,dict(status='not_in_tileList'),None
  return (c,)+fetch_overview(DEMB+f'{n}/{n}.tif',RAW/'dem'/(n+'.bin'),lambda I:[j for j,t in enumerate(I) if t[257][0]==SPD][0])
 def wc(c):n=wc_name(*c);return (c,)+fetch_overview(WCB+n+'.tif',RAW/'wc'/(n+'.bin'),lambda I:[j for j,t in enumerate(I) if t[257][0]==1125][0])
 with concurrent.futures.ThreadPoolExecutor(16) as ex:
  W={c:(m,b) for c,m,b in ex.map(wc,wcs)};print('worldcover',sum(m['status']=='ok' for m,_ in W.values()),'/',len(W),flush=True)
  D={c:(m,b) for c,m,b in ex.map(dem,cells)};print('dem',sum(m['status']=='ok' for m,_ in D.values()),'/',len(D),flush=True)
 kx=R*math.cos(math.radians(LAT0))*math.pi/180;kz=R*math.pi/180
 c0=math.floor(kx*(E['west']-LON0)/TILE);c1=math.floor(kx*(E['east']-LON0)/TILE-1e-9);r0=math.floor(-kz*(E['north']-LAT0)/TILE);r1=math.floor(-kz*(E['south']-LAT0)/TILE-1e-9)
 NC=c1-c0+1;NT=NC*(r1-r0+1);S=np.zeros((NT,7),np.int64);ES=np.zeros(NT);H=np.zeros((NT,NB),np.int32);WD={}
 f=(np.arange(SPD)+.5)/SPD;nodem=0
 for la,lo in cells:
  lat=(la+1-f)[:,None]+0*f[None,:];lon=lo+f[None,:]+0*lat
  wlat,wlon=E['south']+3*((la-E['south'])//3),-12+3*((lo+12)//3)
  if (wlat,wlon) not in WD:m,b=W[(wlat,wlon)];WD[(wlat,wlon)]=decode(m,b) if b else None
  wa=WD[(wlat,wlon)];cls=wa[np.minimum(((wlat+3-lat)*375).astype(int),1124),np.minimum(((lon-wlon)*375).astype(int),1124)] if wa is not None else np.zeros(lat.shape,np.uint8)
  m,b=D[(la,lo)];el=np.full(lat.shape,np.nan,np.float32)
  if b:a=decode(m,b);el=a[:,np.minimum((f*m['width']).astype(int),m['width']-1)]
  el=np.where(el>-1000,el,np.nan);land=(cls!=0)&(cls!=80);ok=land&np.isfinite(el);nodem+=int((land&~np.isfinite(el)).sum())
  t=((np.floor(-kz*(lat-LAT0)/TILE).astype(int)-r0)*NC+np.floor(kx*(lon-LON0)/TILE).astype(int)-c0).ravel()
  cols=[np.ones(t.size,bool),land,ok,land&(el>1500),land&(el>2000),land&(cls==60),land&(cls==70)]
  for k,v in enumerate(cols):S[:,k]+=np.bincount(t,v.ravel(),NT).astype(np.int64)
  oz=ok.ravel();ES+=np.bincount(t[oz],el.ravel()[oz].astype(np.float64),NT)
  bi=np.clip(((el.ravel()[oz]-BMIN)//BIN).astype(int),0,NB-1);u,iv=np.unique(t[oz],return_inverse=True);H[u]+=np.bincount(iv.ravel()*NB+bi,minlength=len(u)*NB).reshape(-1,NB).astype(np.int32)
 lines=['row,col,samples,land_samples,elev_mean_m,elev_p50_m,frac_land_above_1500m,frac_land_above_2000m,frac_land_bare,frac_land_snow']
 fr=lambda x,n:f'{x/n:.3f}'.rstrip('0').rstrip('.') if n else ''
 for i in range(NT):
  s=S[i];r,c=r0+i//NC,c0+i%NC;mean=p50=''
  if s[2]:mean=f'{ES[i]/s[2]:.0f}';cs=np.cumsum(H[i]);p50=str(BMIN+BIN*int(np.searchsorted(cs,(cs[-1]+1)//2))+BIN//2)
  lines.append(f'{r},{c},{s[0]},{s[1]},{mean},{p50},{fr(s[3],s[1])},{fr(s[4],s[1])},{fr(s[5],s[1])},{fr(s[6],s[1])}')
 csv=('\n'.join(lines)+'\n').encode();(OUT/'terrain-25km.csv').write_bytes(csv)
 def inv(X):
  ok=[m for m,_ in X.values() if m['status']=='ok']
  return dict(files_read=len(ok),files_absent=len(X)-len(ok),header_bytes=sum(m['header_bytes'] for m in ok),overview_bytes=sum(m['blob_bytes'] for m in ok),
   overview_blobs_sha256=hashlib.sha256('\n'.join(sorted(f"{m['url']} {m['blob_sha256']}" for m in ok)).encode()).hexdigest())
 di,wi=inv(D),inv(W);tot=di['header_bytes']+di['overview_bytes']+wi['header_bytes']+wi['overview_bytes']+tl.stat().st_size
 src=dict(revision='gametiles-terrain-25km-v1',generated_utc=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),tool='tools/gametiles_terrain.py',status='erforscht (derived statistics; thresholds for Hochgebirge/Wueste are a separate design decision)',
  grid=dict(projection='data/projection.json '+P['revision'],tile_m=25000,col='floor(x/25000)',row='floor(z/25000)',cols=[c0,c1],rows=[r0,r1],tiles=NT,region=E),
  sampling=dict(grid_deg=f'1/{SPD}',points='cell centres within region rectangle',approx_spacing_m=dict(lat=round(kz/SPD),lon_at_41N=round(kx/SPD)),lookup='nearest/containing overview pixel of each source',
   land='WorldCover class not in {0 nodata/absent tile, 80 permanent water}',bare='WorldCover 60 Bare/sparse vegetation',snow='WorldCover 70 Snow and ice',
   elevation='DEM value > -1000 m; DSM (includes canopy/buildings); land samples without DEM value excluded from mean/p50 and counted as not above thresholds',land_samples_without_dem=nodem,
   p50=f'median from {BIN} m histogram (bin centre), range {BMIN}..{BMIN+BIN*NB} m',fractions='relative to land_samples; empty when land_samples=0',
   caveats=['Copernicus DEM is pixel-is-point; overview pixel treated as area cell (offset <= ~0.5 native pixel, ~45 m), negligible at 25 km',
    'WorldCover overview resampling method is not stated in the COG; categorical fractions at 1/375 deg are an overview estimate, not 10 m statistics',
    'DEM overview (factor 4, average) smooths peaks: high-threshold fractions slightly underestimate small summits']),
  sources=[dict(id='copernicus-dem-glo90',name='Copernicus DEM GLO-90 (COP-DEM_GLO-90-DGED) COG on AWS Open Data',url=DEMB,tile_index=DEMB+'tileList.txt',readme=DEMB+'readme.html',
    version='GLO-90 DGED as served by bucket (bucket does not state release; sample object Last-Modified 2022-05-09)',
    license='Copernicus DEM GLO-90 licence, free for the general public (https://spacedata.copernicus.eu/collections/copernicus-digital-elevation-model, Licencing); (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved',
    read=f'internal overview with {SPD} rows per deg (1/{SPD} deg; lon 1/200 deg for 50-60N), single 2048x2048 tile, DEFLATE predictor 3',**di),
   dict(id='esa-worldcover-2021-v200',name='ESA WorldCover 10 m 2021 v200',url=WCB,version='v200 (2021), algorithm V2.0.0',doi='10.5281/zenodo.7254221',
    license='CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/); attribution: ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium',
    read='internal overview 1125x1125 per 3 deg tile (1/375 deg, factor 32), 2x2 tiles of 1024, DEFLATE predictor 1',**wi)],
  bytes_downloaded_total=tot,bytes_fetched_this_run=FETCHED[0],
  output=dict(path='data/gametiles/terrain-25km.csv',rows=NT,sha256=hashlib.sha256(csv).hexdigest(),bytes=len(csv)))
 (OUT/'terrain-sources.json').write_text(json.dumps(src,indent=1)+'\n');print('DONE tiles',NT,'bytes',tot,flush=True)
if __name__=='__main__':main()
