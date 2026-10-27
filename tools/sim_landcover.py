#!/usr/bin/env python3
"""Land cover and slope per 25-km cell for the grain economy (S73, rodbares Land).

Same sources, sample grid and overview reads as tools/gametiles_terrain.py
(whose helpers and raw cache data/raw/gametiles/ it reuses): ESA WorldCover
2021 v200 at 1/375 deg and Copernicus DEM GLO-90 at 300 rows per deg, sampled
every 1/300 deg. For every land sample (WorldCover not 0 or 80) it records the
cover group and the slope band, and counts them per 25-km cell
(data/projection.json eqc, col=floor(x/25000), row=floor(z/25000)).

Cover groups (WorldCover classes): farm = 40 cropland + 50 built-up (towns
stand on farmland), grass = 30 grassland, wood = 10 tree cover + 20
shrubland, other = 60 bare, 70 snow, 90/95 wetland, 100 moss.
Slope: central differences on the DEM overview grid (~370 m spacing, from
90 m data averaged by 4), so it underestimates short steep slopes. Bands
(per cent, as FAO GAEZ): <8, 8-16, 16-30, >=30.

Output sim/inputs/landcover25.csv: row, col, land_samples, then the share of
land samples per group and band: farm_8, farm_16, farm_30, farm_steep,
grass_..., wood_..., other_... (16 columns, summing to 1).
"""
import math,pathlib,sys,json,hashlib,datetime,concurrent.futures
import numpy as np
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
import gametiles_terrain as gt
ROOT=gt.ROOT;E=gt.E;R=gt.R;LAT0=gt.LAT0;LON0=gt.LON0;TILE=gt.TILE;SPD=gt.SPD
GROUPS=['farm','grass','wood','other'];BANDS=['8','16','30','steep']
def main():
 for d in ('dem','wc'):(gt.RAW/d).mkdir(parents=True,exist_ok=True)
 tl=gt.RAW/'tileList.txt'
 if not tl.exists():tl.write_bytes(gt.get(gt.DEMB+'tileList.txt'))
 have={l.strip() for l in tl.read_text().split()}
 cells=[(la,lo) for la in range(E['south'],E['north']) for lo in range(E['west'],E['east'])]
 wcs=sorted({(E['south']+3*((la-E['south'])//3),-12+3*((lo+12)//3)) for la,lo in cells})
 def dem(c):
  n=gt.dem_name(*c)
  if n not in have:return c,dict(status='not_in_tileList'),None
  return (c,)+gt.fetch_overview(gt.DEMB+f'{n}/{n}.tif',gt.RAW/'dem'/(n+'.bin'),lambda I:[j for j,t in enumerate(I) if t[257][0]==SPD][0])
 def wc(c):n=gt.wc_name(*c);return (c,)+gt.fetch_overview(gt.WCB+n+'.tif',gt.RAW/'wc'/(n+'.bin'),lambda I:[j for j,t in enumerate(I) if t[257][0]==1125][0])
 with concurrent.futures.ThreadPoolExecutor(16) as ex:
  W={c:(m,b) for c,m,b in ex.map(wc,wcs)};print('worldcover',sum(m['status']=='ok' for m,_ in W.values()),'/',len(W),flush=True)
  D={c:(m,b) for c,m,b in ex.map(dem,cells)};print('dem',sum(m['status']=='ok' for m,_ in D.values()),'/',len(D),flush=True)
 kx=R*math.cos(math.radians(LAT0))*math.pi/180;kz=R*math.pi/180
 c0=math.floor(kx*(E['west']-LON0)/TILE);c1=math.floor(kx*(E['east']-LON0)/TILE-1e-9);r0=math.floor(-kz*(E['north']-LAT0)/TILE);r1=math.floor(-kz*(E['south']-LAT0)/TILE-1e-9)
 NC=c1-c0+1;NT=NC*(r1-r0+1);S=np.zeros((NT,17),np.int64);WD={}
 f=(np.arange(SPD)+.5)/SPD
 grp=np.full(256,3,np.int64);grp[[40,50]]=0;grp[30]=1;grp[[10,20]]=2
 for la,lo in cells:
  lat=(la+1-f)[:,None]+0*f[None,:];lon=lo+f[None,:]+0*lat
  wlat,wlon=E['south']+3*((la-E['south'])//3),-12+3*((lo+12)//3)
  if (wlat,wlon) not in WD:m,b=W[(wlat,wlon)];WD[(wlat,wlon)]=gt.decode(m,b) if b else None
  wa=WD[(wlat,wlon)];cls=wa[np.minimum(((wlat+3-lat)*375).astype(int),1124),np.minimum(((lon-wlon)*375).astype(int),1124)] if wa is not None else np.zeros(lat.shape,np.uint8)
  land=(cls!=0)&(cls!=80)
  if not land.any():continue
  m,b=D[(la,lo)];slope=np.zeros(lat.shape,np.float32)
  if b:
   a=gt.decode(m,b);a=np.where(a>-1000,a,0).astype(np.float64)
   # Native overview spacing: 1/height deg north-south, 1/width deg east-west.
   dz=kz/m['height'];dx=kz*math.cos(math.radians(la+.5))/m['width']
   gy,gx=np.gradient(a,dz,dx);s=100*np.hypot(gx,gy)
   slope=s[:,np.minimum((f*m['width']).astype(int),m['width']-1)]
  band=np.digitize(slope,[8,16,30])
  k=grp[cls.astype(np.int64)]*4+band
  t=((np.floor(-kz*(lat-LAT0)/TILE).astype(int)-r0)*NC+np.floor(kx*(lon-LON0)/TILE).astype(int)-c0)
  lz=land.ravel();tz=t.ravel()[lz];kz_=k.ravel()[lz]
  S[:,0]+=np.bincount(tz,minlength=NT)
  S[:,1:]+=np.bincount(tz*16+kz_,minlength=NT*16).reshape(NT,16)
 head='row,col,land_samples,'+','.join(f'{g}_{b}' for g in GROUPS for b in BANDS)
 lines=[head]
 for i in range(NT):
  n=S[i,0]
  if not n:continue
  r,c=r0+i//NC,c0+i%NC
  lines.append(f'{r},{c},{n},'+','.join(f'{v/n:.4f}'.rstrip('0').rstrip('.') for v in S[i,1:]))
 out=ROOT/'sim/inputs/landcover25.csv';csv=('\n'.join(lines)+'\n').encode();out.write_bytes(csv)
 src=dict(revision='sim-landcover25-v1',generated_utc=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),tool='tools/sim_landcover.py',
  sources='as data/gametiles/terrain-sources.json (ESA WorldCover 2021 v200 CC BY 4.0: ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium; Copernicus DEM GLO-90)',
  groups=dict(farm='40 cropland, 50 built-up',grass='30 grassland',wood='10 tree cover, 20 shrubland',other='60 bare, 70 snow, 90 wetland, 95 mangroves, 100 moss'),
  slope_bands_pct=['<8','8-16','16-30','>=30'],slope='central differences on the DEM overview (300 rows/deg; ~370 m), underestimates short steep slopes',
  output=dict(path='sim/inputs/landcover25.csv',rows=len(lines)-1,sha256=hashlib.sha256(csv).hexdigest()))
 (ROOT/'sim/inputs/landcover25-sources.json').write_text(json.dumps(src,indent=1)+'\n');print('DONE',len(lines)-1,flush=True)
if __name__=='__main__':main()
