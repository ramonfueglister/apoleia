#!/usr/bin/env python3
"""Download versioned complete NOAA15s source tiles, with hashes and headers."""
import pathlib,subprocess,concurrent.futures,json,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/raw/etopo15';OUT.mkdir(parents=True,exist_ok=True)
def one(p):
 n,lon=p;name=f'ETOPO_2022_v1_15s_N{n:02d}'+('W' if lon<0 else 'E')+f'{abs(lon):03d}_surface.tif';path=OUT/name;meta=OUT/(name+'.json');url='https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/data/15s/15s_surface_elev_gtif/'+name
 if not meta.exists():
  done=subprocess.run(['curl','-fLsS','--max-time','600','-D',str(OUT/(name+'.headers')),'-o',str(path),url])
  if done.returncode:raise RuntimeError(name+' failed; inspect before retry')
  r=dict(id=name,url=url,path=str(path.relative_to(ROOT)),version='ETOPO2022v1-15s',sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size);meta.write_text(json.dumps(r,indent=2)+'\n')
 print(name,'complete',flush=True);return json.loads(meta.read_text())
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:r=list(ex.map(one,[(n,lon) for n in [30,45,60] for lon in [-15,0,15,30,45]]))
(ROOT/'data/etopo15-inventory.json').write_text(json.dumps(dict(revision='etopo2022v1-15s-regional-v1',sources=r),indent=2)+'\n');print('DONE',len(r),flush=True)
