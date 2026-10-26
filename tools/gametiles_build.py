#!/usr/bin/env python3
"""Adaptive logical game tiles (K25-K29): one quadtree on the eqc41 grid, headless.

Inputs (all tracked):  data/derived/land.geojson, data/derived/lakes.geojson (lakes count as land, K27),
data/gametiles/terrain-25km.csv (tools/gametiles_terrain.py), data/gametiles/places*.csv (tools/gametiles_places.py),
data/gametiles/rules.json.  Outputs: data/gametiles/tiles.csv, data/gametiles/summary.json, data/gametiles/debug-map.png.
Only numpy and Pillow (debug map) are needed. No rendering, no runtime binding.

Identity: eqc41-gt-v1:{level}:{row}:{col}, size_m=200000/2**level (level 3 = 25 km), row=floor(z/size_m),
col=floor(x/size_m) in projected metres of data/projection.json.  The parent of (l,r,c) is (l-1,r>>1,c>>1), so a merged tile is the parent of its four children
and later refinement never renames an existing ID (K28).  25 km tiles are exactly 25x25 cells of eqc41-km-v1 (K25).
"""
import csv,hashlib,json,math,pathlib,sys,zlib,struct
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gametiles'
R=6371008.8;KX=R*math.cos(math.radians(41))*math.pi/180;KZ=R*math.pi/180
BASE=25000;LEVELS=[200000,100000,50000,25000,12500,6250];L25=LEVELS.index(BASE)
def xz(lon,lat):return KX*(np.asarray(lon,float)-19),-KZ*(np.asarray(lat,float)-41)
def lonlat(x,z):return 19+x/KX,41-z/KZ
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def rel(p):return str(pathlib.Path(p).relative_to(ROOT))
def grow(b,d):return b[0]-d,b[1]-d,b[2]+d,b[3]+d
def subcells(l,r,c):
 if l>=L25:return [(r>>(l-L25),c>>(l-L25))]
 k=1<<(L25-l);return [(rr,cc) for rr in range(r*k,r*k+k) for cc in range(c*k,c*k+k)]
def tid(l,r,c):return f'eqc41-gt-v1:{l}:{r}:{c}'  # size_m = 200000/2**l, any depth (runtime splits too)
def size(l):return 200000/2**l
def tile_at(lon,lat,l):x,z=xz(lon,lat);return l,math.floor(float(z)/size(l)),math.floor(float(x)/size(l))
def parent(l,r,c):return l-1,r>>1,c>>1
def children(l,r,c):return [(l+1,2*r+i,2*c+j) for i in (0,1) for j in (0,1)]

# ---------- region and 1 km land raster (cell centres of eqc41-km-v1) ----------
EXT=json.loads((ROOT/'data/projection.json').read_text())['extent']
X0,Z0=map(float,xz(EXT["west"],EXT["north"]));X1,Z1=map(float,xz(EXT["east"],EXT["south"]))
C0,C1=math.floor(X0/1000),math.floor(X1/1000);R0,R1=math.floor(Z0/1000),math.floor(Z1/1000)
NC,NR=C1-C0+1,R1-R0+1
def rings(path):
 for f in json.loads((ROOT/path).read_text())['features']:
  g=f['geometry'];polys=g['coordinates'] if g['type']=='MultiPolygon' else [g['coordinates']]
  for p in polys:
   for ring in p:yield np.asarray(ring,float)
def raster(path):
 """Even-odd scanline fill at cell centres; holes and islands handled by parity over all rings."""
 rs,xs=[],[]
 for ring in rings(path):
  x,z=xz(ring[:,0],ring[:,1]);xa,za,xb,zb=x[:-1],z[:-1],x[1:],z[1:]
  lo=np.ceil(np.minimum(za,zb)/1000-.5);hi=np.ceil(np.maximum(za,zb)/1000-.5)  # rows with lo<=centre<hi
  n=(hi-lo).astype(int);keep=n>0
  if not keep.any():continue
  xa,za,xb,zb,lo,n=xa[keep],za[keep],xb[keep],zb[keep],lo[keep],n[keep]
  e=np.repeat(np.arange(len(n)),n);row=lo[e]+np.arange(n.sum())-np.repeat(np.cumsum(n)-n,n)
  zc=(row+.5)*1000;t=(zc-za[e])/(zb[e]-za[e]);rs.append(row.astype(int));xs.append(xa[e]+t*(xb[e]-xa[e]))
 row=np.concatenate(rs);x=np.concatenate(xs);o=np.lexsort((x,row));row,x=row[o],x[o]
 assert len(row)%2==0 and (row[0::2]==row[1::2]).all(),'unpaired scanline crossings'
 m=np.zeros((NR,NC+1),np.int32);r=row[0::2]-R0;ok=(r>=0)&(r<NR)
 a=np.clip(np.ceil(x[0::2][ok]/1000-.5).astype(int)-C0,0,NC);b=np.clip(np.ceil(x[1::2][ok]/1000-.5).astype(int)-C0,0,NC)
 np.add.at(m,(r[ok],a),1);np.add.at(m,(r[ok],b),-1)  # [a,b) runs
 return np.cumsum(m,axis=1)[:,:NC]>0
class Area:
 """Summed-area tables over the 1 km grid: O(1) land / in-region counts for any rectangle in metres."""
 def __init__(s,land):
  s.sat=np.pad(land.astype(np.int64).cumsum(0).cumsum(1),((1,0),(1,0)))
 def _sum(s,t,x0,z0,x1,z1):
  a=lambda v,o,n:int(min(max(math.ceil(v/1000-.5)-o,0),n))  # cells whose centre lies in [v0,v1)
  c0,c1,r0,r1=a(x0,C0,NC),a(x1,C0,NC),a(z0,R0,NR),a(z1,R0,NR)
  return int(t[r1,c1]-t[r0,c1]-t[r1,c0]+t[r0,c0]),(r1-r0)*(c1-c0)
 def land(s,x0,z0,x1,z1):return s._sum(s.sat,x0,z0,x1,z1)
 def count(s,x0,z0,x1,z1):return s._sum(s.sat,x0,z0,x1,z1)[0]

# ---------- quadtree ----------
class Tree:
 def __init__(s):s.leaves={}
 @staticmethod
 def bounds(s_,r,c):return c*s_,r*s_,(c+1)*s_,(r+1)*s_
 @staticmethod
 def in_region(s_,r,c):
  x0,z0,x1,z1=Tree.bounds(s_,r,c);return x0<X1 and x1>X0 and z0<Z1 and z1>Z0
 def children(s,l,r,c):
  return [(l+1,2*r+i,2*c+j) for i in (0,1) for j in (0,1) if Tree.in_region(LEVELS[l+1],2*r+i,2*c+j)]
 def covering(s,l,r,c):
  for k in range(l,-1,-1):
   key=(k,r>>(l-k),c>>(l-k))
   if key in s.leaves:return key
 def split(s,key,why):
  """Split a leaf; first split coarser edge neighbours so all neighbours stay within one level (2:1 rule)."""
  l,r,c=key
  for dr,dc in((-1,0),(1,0),(0,-1),(0,1)):
   n=s.covering(l,r+dr,c+dc)
   if n and n[0]<l:s.split(n,'balance')
  if key not in s.leaves:return
  info=s.leaves.pop(key)
  for ch in s.children(l,r,c):s.leaves[ch]=dict(why=why if why!='balance' else 'balance',parent_why=info['why'])
 def balance(s):
  changed=True
  while changed:
   changed=False
   for (l,r,c) in sorted(s.leaves,reverse=True):
    if (l,r,c) not in s.leaves:continue
    for dr,dc in((-1,0),(1,0),(0,-1),(0,1)):
     n=s.covering(l,r+dr,c+dc)
     if n and n[0]<l-1:s.split(n,'balance');changed=True
def id_selftest():
 """Contract for runtime split/merge below the static leaves (e.g. 1.5 km at level 7): pure arithmetic, no table."""
 assert tid(*tile_at(19,41,3))=='eqc41-gt-v1:3:0:0' and tile_at(19-1e-9,41,3)[2]==-1 and tile_at(19,41+1e-9,3)[1]==-1
 for l in range(1,9):
  k=tile_at(12.49,41.89,l);assert parent(*k)==tile_at(12.49,41.89,l-1) and k in children(*parent(*k))
 assert size(3)==BASE and size(7)==1562.5

def main():
 id_selftest()
 rules=json.loads((OUT/'rules.json').read_text())
 land=raster('data/derived/land.geojson')|raster('data/derived/lakes.geojson');A=Area(land)
 # 25 km base cells
 rb0,rb1=math.floor(Z0/BASE),math.floor((Z1-1e-6)/BASE);cb0,cb1=math.floor(X0/BASE),math.floor((X1-1e-6)/BASE)
 base={}
 for r in range(rb0,rb1+1):
  for c in range(cb0,cb1+1):
   lc,n=A.land(*Tree.bounds(BASE,r,c));base[(r,c)]=dict(land=lc,cells=n)
 terr={}
 tp=OUT/'terrain-25km.csv'
 if tp.exists():
  for t in csv.DictReader(tp.open()):terr[(int(t['row']),int(t['col']))]=t
 tr=rules['terrain']
 def kind25(r,c):
  b=base[(r,c)]
  if b['land']==0:return 'sea'
  t=terr.get((r,c))
  if b['land']<b['cells'] or t is None or int(t['land_samples'])==0:return 'land'
  if float(t['frac_land_bare'])>=tr['desert_min_bare_fraction']:return 'desert'
  if float(t['frac_land_above_1500m'])>=tr['mountain_min_fraction_above_1500m'] and float(t['frac_land_above_2000m'])>=tr['mountain_min_fraction_above_2000m']:return 'mountain'
  return 'land'
 kinds={k:kind25(*k) for k in base}
 # optional context land (rules.context_land): land far from the reference extent may be coarser than 25 km
 cr=rules.get('context_land',{});ctx=set()
 if cr.get('enabled'):
  REF=Area(raster(cr['reference']))
  ctx={k for k in base if kinds[k]!='sea' and REF.count(*grow(Tree.bounds(BASE,*k),cr['min_distance_m']))==0}
 # empty land: no place (any epoch, any source, manual list) within the 25 km cell grown by empty_land_margin_m
 empty=set()
 if tr.get('empty_land_max_size_m'):
  occ=set();m=tr.get('empty_land_margin_m',0)
  for f in ('places.csv','places-manual.csv'):
   if (OUT/f).exists():
    for p in csv.DictReader((OUT/f).open()):
     x,z=xz(float(p['lon']),float(p['lat']))
     for rr in range(math.floor((float(z)-m)/BASE),math.floor((float(z)+m)/BASE)+1):
      for cc in range(math.floor((float(x)-m)/BASE),math.floor((float(x)+m)/BASE)+1):occ.add((rr,cc))
  empty={k for k in base if kinds[k]!='sea' and k not in occ}
 global EMPTY;EMPTY=empty
 # how coarse may a block be?  (K27 classes and context land; urban refinement comes later)
 sr=rules['sea']
 def may_leaf(l,r,c):
  s_=LEVELS[l];x0,z0,x1,z1=Tree.bounds(s_,r,c)
  if l>=L25:return True
  sub=[q for q in subcells(l,r,c) if q in kinds];ks={kinds[q] for q in sub}
  if ks=={'sea'}:
   clear=sr['open_clearance_m'].get(str(s_))
   if clear is None:return False
   lc,_=A.land(x0-clear,z0-clear,x1+clear,z1+clear);return lc==0
  if l==L25-1 and ks<= {'desert','mountain'} and ks:return True
  if ks=={'desert'} and s_<=tr.get('desert_max_size_m',50000):return True
  em=tr.get('empty_land_max_size_m',0)
  if s_<=em and 'sea' not in ks and all(q in empty for q in sub):return True
  if ctx and all(q in ctx for q in sub):
   clear=cr['clearance_m'].get(str(s_))
   return clear is not None and REF.count(*grow((x0,z0,x1,z1),clear))==0
  return False
 t=Tree()
 for r in range(math.floor(Z0/LEVELS[0]),math.floor((Z1-1e-6)/LEVELS[0])+1):
  for c in range(math.floor(X0/LEVELS[0]),math.floor((X1-1e-6)/LEVELS[0])+1):t.leaves[(0,r,c)]=dict(why='root')
 todo=list(t.leaves)
 while todo:
  key=todo.pop()
  if key in t.leaves and not may_leaf(*key):
   t.leaves.pop(key)
   for ch in t.children(*key):t.leaves[ch]=dict(why='class');todo.append(ch)
 t.balance();n_classes=len(t.leaves)
 # ---------- urban refinement (K29): epoch-relative importance, max over sample years, budget ----------
 ur=rules['urban'];years=ur['years'];global YEARS;YEARS=years;plc=[];manual=[]
 pp=OUT/'places.csv'
 if pp.exists():plc=list(csv.DictReader(pp.open()))
 mp=OUT/'places-manual.csv'
 if mp.exists():manual=list(csv.DictReader(mp.open()))
 def cell(lon,lat,s_):x,z=xz(lon,lat);return math.floor(float(z)/s_),math.floor(float(x)/s_)
 imp={};cityscore=[]
 for y in years:
  vals=[(p,float(p[f'p{y}'])) for p in plc if p.get(f'p{y}')]
  if not vals:continue
  per={}
  for p,v in vals:
   k=cell(float(p['lon']),float(p['lat']),BASE)
   if k in base:per[k]=per.get(k,0)+v
  ref_=np.mean(sorted(per.values())[-ur['epoch_reference_top_n']:])  # epoch scale: mean of top-N urban tiles
  for k,v in per.items():imp[k]=max(imp.get(k,0),v/ref_)
  ranked=sorted(vals,key=lambda pv:-pv[1])
  for i,(p,v) in enumerate(ranked):cityscore.append((i,-v/ranked[0][1],p['id'],y))
 for p in plc:
  if p.get('port')=='1':
   k=cell(float(p['lon']),float(p['lat']),BASE)
   if k in imp:imp[k]+=ur['port_bonus']
 # level 5: best rank of a city over all years, then within-rank by relative size
 best={}
 for rank,neg,pid,y in sorted(cityscore):best.setdefault(pid,(rank,neg,y))
 byid={p['id']:p for p in plc}
 big=sorted(best.items(),key=lambda kv:kv[1])[:ur['major_city_count']]
 cand=[]
 for pid,(rank,neg,y) in big:
  p=byid[pid];cand.append(('urban6',(L25+2,)+cell(float(p['lon']),float(p['lat']),LEVELS[L25+2]),pid,y,rank))
 for m in manual:
  cand.append(('manual',(L25,)+cell(float(m['lon']),float(m['lat']),BASE),m['id'],None,None))
 for k,v in sorted(imp.items(),key=lambda kv:-kv[1]):
  if kinds.get(k)!='sea' and v>=ur['min_importance']:cand.append(('urban12',(L25,)+k,None,None,v))
 budget=ur['budget'];applied=[];stopped=None
 def refine_to(t,l,r,c,why):
  """Split covering leaves until (l,r,c) itself is a leaf (the whole 25 km tile for urban12, the 6.25 km cell's
  25 km tile fully for urban6 so the city and its surroundings sit in 6.25 km tiles)."""
  while True:
   cov=t.covering(l,r,c)
   if cov is None or cov[0]>=l:return
   t.split(cov,why)
 for why,(l,r,c),pid,y,score in cand:
  snap={k:dict(v) for k,v in t.leaves.items()}
  if why=='urban6':
   r25,c25=r>>2,c>>2
   for i in range(4):
    for j in range(4):refine_to(t,l,r25*4+i,c25*4+j,why)
  else:refine_to(t,L25+1,2*r,2*c,why)
  t.balance()
  if len(t.leaves)>budget:t.leaves=snap;stopped=dict(kind=why,id=pid,tile=tid(l,r,c),score=score);break
  applied.append(dict(kind=why,place=pid,year=y,tile=tid(l,r,c),score=None if score is None else round(float(score),4),leaves_after=len(t.leaves)))
 write(t,kinds,ctx,base,A,terr,imp,rules,applied,stopped,n_classes,plc,manual)

def write(t,kinds,ctx,base,A,terr,imp,rules,applied,stopped,n_classes,plc,manual):
 rows=[]
 for (l,r,c),info in sorted(t.leaves.items(),key=lambda kv:(-LEVELS[kv[0][0]],kv[0][1],kv[0][2])):
  s_=LEVELS[l];x0,z0,x1,z1=Tree.bounds(s_,r,c);lc,n=A.land(x0,z0,x1,z1)
  k='+'.join(sorted({kinds[q] for q in subcells(l,r,c) if q in kinds}))
  if k=='sea':k='sea-coastal' if s_<=50000 else 'sea-open'
  if not k.startswith('sea') and all(q in ctx for q in subcells(l,r,c) if q in kinds):k='context-'+k
  elif not k.startswith('sea') and k!='desert' and s_>BASE and all(q in EMPTY for q in subcells(l,r,c) if q in kinds):k='empty-'+k
  ix0,iz0,ix1,iz1=max(x0,X0),max(z0,Z0),min(x1,X1),min(z1,Z1)
  w,n_,e,s=*lonlat(ix0,iz0),*lonlat(ix1,iz1)
  rows.append(dict(id=tid(l,r,c),parent=tid(l-1,r>>1,c>>1) if l else '',level=l,size_m=s_,row=r,col=c,x0_m=x0,z0_m=z0,
   class_=k,land_fraction=round(lc/n,4) if n else 0,region_fraction=round((ix1-ix0)*(iz1-iz0)/(s_*s_),4),
   reason=info['why'],west=round(w,5),north=round(n_,5),east=round(e,5),south=round(s,5)))
 fields=list(rows[0]);OUT.mkdir(parents=True,exist_ok=True)
 with (OUT/'tiles.csv').open('w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=[x.rstrip('_') for x in fields],lineterminator='\n');w.writeheader()
  for r in rows:w.writerow({k.rstrip('_'):v for k,v in r.items()})
 checks=check(t,rows,plc,applied)
 count=lambda key:{str(k):sum(1 for r in rows if r[key]==k) for k in sorted({r[key] for r in rows},key=str)}
 inputs=[ROOT/'data/derived/land.geojson',ROOT/'data/derived/lakes.geojson',OUT/'rules.json',ROOT/'data/projection.json']+[p for p in (OUT/'terrain-25km.csv',OUT/'places.csv',OUT/'places-manual.csv') if p.exists()]
 summary=dict(schema_version='gametiles-v1',revision='gametiles-v1',grid_id='eqc41-gt-v1',
  id_format='eqc41-gt-v1:{level}:{row}:{col}; size_m=200000/2**level; row=floor(z/size_m), col=floor(x/size_m); parent=(level-1,floor(row/2),floor(col/2)); children=(level+1,2row+i,2col+j)',
  decisions=['K25','K26','K27','K28','K29'],tile_count=len(rows),budget=rules['urban']['budget'],tiles_after_class_merge=n_classes,
  by_size_m=count('size_m'),by_class=count('class_'),by_reason=count('reason'),base_25km_cells=len(base),
  base_25km_land_cells=sum(1 for k in kinds.values() if k!='sea'),base_25km_by_kind={k:sum(1 for v in kinds.values() if v==k) for k in sorted(set(kinds.values()))},
  refinements_applied=len(applied),refinement_stopped_at=stopped,checks=checks,
  inputs={rel(p):sha(p) for p in inputs},outputs={'data/gametiles/tiles.csv':sha(OUT/'tiles.csv')},refinements=applied)
 (OUT/'summary.json').write_text(json.dumps(summary,indent=1,ensure_ascii=False)+'\n')
 debug_map(rows)
 bad=[k for k,v in checks.items() if isinstance(v,dict) and v.get('ok') is False]
 print(json.dumps({k:summary[k] for k in('tile_count','by_size_m','by_class','refinements_applied')}),'FAILED:'+','.join(bad) if bad else 'all checks ok')
 if bad:sys.exit(1)

def check(t,rows,plc,applied):
 """Self-checks: unique IDs, ID<->geometry round trip, exact cover of the region, 2:1 rule, 25 km alignment."""
 ids=[r['id'] for r in rows];out={}
 out['unique_ids']=dict(ok=len(ids)==len(set(ids)),n=len(ids))
 ok=all(r['id']==tid(r['level'],math.floor(r['z0_m']/r['size_m']),math.floor(r['x0_m']/r['size_m'])) for r in rows)
 out['id_geometry_roundtrip']=dict(ok=ok)
 out['aligned_25km_to_1km_grid']=dict(ok=all(r['x0_m']%1000==0 and r['z0_m']%1000==0 for r in rows if r['size_m']>=BASE))
 area=sum((min(r['x0_m']+r['size_m'],X1)-max(r['x0_m'],X0))*(min(r['z0_m']+r['size_m'],Z1)-max(r['z0_m'],Z0)) for r in rows)
 out['region_area_cover']=dict(ok=abs(area/((X1-X0)*(Z1-Z0))-1)<1e-9,ratio=area/((X1-X0)*(Z1-Z0)))
 # no overlap: each leaf's ancestors are not leaves, and a random sample of points hits exactly one leaf
 anc=sum(1 for (l,r,c) in t.leaves for k in range(l) if (k,r>>(l-k),c>>(l-k)) in t.leaves)
 rng=np.random.default_rng(0);px=rng.uniform(X0,X1,20000);pz=rng.uniform(Z0,Z1,20000);miss=0;multi=0
 for x,z in zip(px,pz):
  hits=sum(1 for l in range(len(LEVELS)) if (l,math.floor(z/LEVELS[l]),math.floor(x/LEVELS[l])) in t.leaves)
  miss+=hits==0;multi+=hits>1
 out['no_overlap_no_gap']=dict(ok=anc==0 and miss==0 and multi==0,ancestor_leaves=anc,sample_points=20000,miss=miss,multi=multi)
 viol=0
 for (l,r,c) in t.leaves:
  for dr,dc in((-1,0),(1,0),(0,-1),(0,1)):
   n=t.covering(l,r+dr,c+dc)
   if n and n[0]<l-1:viol+=1
 out['balance_2to1']=dict(ok=viol==0,violations=viol)
 # stable IDs: re-deriving the 25 km ancestor of every finer tile gives a 25 km cell inside the base grid
 out['finer_tiles_nest_in_25km']=dict(ok=all((r['row']>>(r['level']-L25),r['col']>>(r['level']-L25)) for r in rows if r['level']>L25))
 if plc:out.update(check_control(rows,plc,applied))
 return out

def check_control(rows,plc,applied):
 cp=OUT/'places-control.csv'
 if not cp.exists():return {}
 lv={(r['size_m'],r['row'],r['col']):r for r in rows};fine=[];miss=[]
 for p in csv.DictReader(cp.open()):
  x,z=xz(float(p['lon']),float(p['lat']));hit=None
  for s_ in LEVELS:
   k=(s_,math.floor(float(z)/s_),math.floor(float(x)/s_))
   if k in lv:hit=lv[k];break
  (fine if hit and hit['size_m']<=12500 else miss).append(f"{p['year']}:{p['name']}"+('' if not hit else f"@{hit['size_m']}"))
 ctl=[xz(float(p['lon']),float(p['lat'])) for p in csv.DictReader(cp.open())];byid={p['id']:p for p in plc};orphan=[]
 for a in applied:
  if a['kind']!='urban6':continue
  x,z=xz(float(byid[a['place']]['lon']),float(byid[a['place']]['lat']))
  top=any(a['place'] in {q['id'] for q in sorted((q for q in plc if q.get(f'p{y}')),key=lambda q:-float(q[f'p{y}']))[:50]} for y in YEARS)
  if not top and not any(math.hypot(float(x-cx),float(z-cz))<10000 for cx,cz in ctl):orphan.append(a['place'])
 return {'control_cities_in_fine_tiles':dict(ok=not miss,note='Kontrollliste: Top 50 je 117/1000/1500/2020 liegt in 12,5- oder 6,25-km-Tile',fine=len(fine),not_fine=len(miss),not_fine_list=miss[:200]),
  'major_cities_in_control_list':dict(ok=not orphan,note='Gegenprobe: jede 6,25-km-Stadt gehört in einem Stichjahr zu den Top 50 der Daten oder steht in der Kontrollliste',orphans=orphan)}

def debug_map(rows):
 """Internal debug map only (not shown in game): 1 px per 6.25 km, colour by class, darker outline per tile."""
 px=6250;W=math.ceil((X1-X0)/px);H=math.ceil((Z1-Z0)/px);img=np.zeros((H,W,3),np.uint8)
 col={'sea-open':(40,70,120),'sea-coastal':(70,120,170),'land':(150,170,110),'desert':(220,195,130),'mountain':(150,140,135)}
 for r in rows:
  a=int((max(r['x0_m'],X0)-X0)//px);b=int(math.ceil((min(r['x0_m']+r['size_m'],X1)-X0)/px))
  u=int((max(r['z0_m'],Z0)-Z0)//px);v=int(math.ceil((min(r['z0_m']+r['size_m'],Z1)-Z0)/px))
  k=r['class_'];ctx=k.startswith('context-');k=k.removeprefix('context-');cc=col.get(k,(190,160,150) if '+' in k else (200,200,200))
  if ctx:cc=tuple(int(v*.45+215*.55) for v in cc)  # context land: same hue, washed out
  if r['size_m']<=12500:cc=(200,60,50) if r['size_m']==6250 else (230,130,60)
  img[u:v,a:b]=cc;img[u:v,a]=(img[u:v,a]*.6).astype(np.uint8);img[u,a:b]=(img[u,a:b]*.6).astype(np.uint8)
 from PIL import Image
 Image.fromarray(img).resize((W*2,H*2),Image.NEAREST).save(OUT/'debug-map.png',optimize=True)

if __name__=='__main__':main()
