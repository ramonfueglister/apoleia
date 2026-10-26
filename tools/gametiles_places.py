#!/usr/bin/env python3
"""Fetch + normalize historical/modern city populations for adaptive game tiles.

Outputs data/gametiles/{places,places-manual,places-control}.csv and places-sources.json.
Every population value comes from a named dataset below; no value is typed in by hand.
Raw files go to data/raw/gametiles/places/ (gitignored) and are verified by sha256.
"""
import pathlib,subprocess,hashlib,json,re,math,unicodedata,difflib,csv
import numpy as np,pandas as pd
ROOT=pathlib.Path(__file__).resolve().parents[1];RAW=ROOT/'data/raw/gametiles/places';OUT=ROOT/'data/gametiles'
BBOX=(-11,21,46,58);YEARS=[117,400,1000,1500,1800,1900,2020];MINPOP=5000;MERGE_KM=10;MERGE_LOOSE_KM=25;MERGE_CERT3_KM=100;MERGE_NONAME_KM=2.5;PORT_KM=5
TOL={117:50,400:50,1000:50,1500:50,1800:25,1900:25,2020:25}
FIG='https://s3-eu-west-1.amazonaws.com/pfigshare-u-files/';GH='https://raw.githubusercontent.com/'
REBA='Reba M, Reitsma F, Seto KC (2016) Spatializing 6,000 years of global urbanization from 3700 BC to AD 2000. Sci Data 3:160034, doi:10.1038/sdata.2016.34'
S=[
 dict(id='chandler',file='chandlerV2.csv',url=FIG+'5407640/chandlerV2.csv',sha256='5b8df64e46988b216988eef18b46ebc2cba57ecc1adc8a5c2e1e6d5b78068031',version='figshare 10.6084/m9.figshare.2059494 (chandlerV2.csv, file 5407640)',licence='CC BY 4.0',citation=REBA+'; digitizes Chandler T (1987) Four Thousand Years of Urban Growth',note='figshare.com/ndownloader blocked by proxy; same file fetched from figshare S3 storage URL (sha256 equals the hash pinned by independent users of the file).',used='p117 (AD_100), p400 (AD_361), p1000, p1500, p1800, p1900: nearest year column within tolerance'),
 dict(id='modelski-anc',file='modelskiAncientV2.csv',url=FIG+'5356132/modelskiAncientV2.csv',sha256='71beafaacbdeb8d8fc156951521e9a14e20d6704b0d77be5528511c52fad3e1d',version='figshare 10.6084/m9.figshare.2059497 (modelskiAncientV2.csv, file 5356132)',licence='CC BY 4.0',citation=REBA+'; digitizes Modelski G (2003) World Cities -3000 to 2000',used='p117 (AD_100), p400 (AD_400), p1000 (AD_1000)'),
 dict(id='modelski-mod',file='modelskiModernV2.csv',url=FIG+'5407637/modelskiModernV2.csv',sha256='927ee6a9122be6aded1a2f71ff5bb6f36312aae6a778574af47f4e8c65265726',version='figshare 10.6084/m9.figshare.2059500 (modelskiModernV2.csv, file 5407637)',licence='CC BY 4.0',citation=REBA,used='p2020 fallback (AD_2000, 20 y off) when NE has no POP2020'),
 dict(id='hanson',file='Hanson2016_CitiesDatabase_OxREP.xlsx',url=GH+'wccarleton/urbanscale/HEAD/Data/Hanson2016_CitiesDatabase_OxREP.xlsx',sha256='582e326ad1cb1525ba8f36c69c2ab2b43d8d3c3b82138f085df1c9b97bb7a078',version='OxREP Cities Database (Hanson 2016), mirror in github.com/wccarleton/urbanscale (Zenodo 10.5281/zenodo.10925901), fetched 2026-10-26',licence='Original OxREP database: licence not stated in mirror (verify before redistribution); mirror repository CC BY 4.0',citation='Hanson JW (2016) An Urban Geography of the Roman World, 100 BC to AD 300. Archaeopress (OxREP databases)',note='oxrep.classics.ox.ac.uk blocked by proxy; mirror sheets Cities/Areas/Monuments identical in structure to the OxREP CSVs.',used='city list + coordinates (Cities), inhabited/walled area (Areas) -> p117 via Hanson-Ortman scaling, port flag from Monuments (Harbour*/Lighthouse*, uncertain "?" excluded)'),
 dict(id='hanson-ortman',file='HansonOrtmanetal2017_dataset.csv',url=GH+'past-networks/roman_ECI/HEAD/data/data_generation/HansonOrtmanetal2017_dataset.csv',sha256='39136b03677671116f387a620f4a28a47ad621a8f37d00597bbc4d820a4daad8',version='mirror in github.com/past-networks/roman_ECI, fetched 2026-10-26',licence='not stated in mirror (verify before redistribution); only fitted parameters used',citation='Hanson JW, Ortman SG (2017) A systematic method for estimating the populations of Greek and Roman settlements. J Roman Archaeol 30:301-324',used='fit N=d*A^p (log space, iterative |residual|<0.05) on its 125 area/population pairs; parameters applied to Hanson areas'),
 dict(id='b2l',file='b2l-bagdad_london_final_restat.dta',url=GH+'nikunjt0/HRE-Urban-City-Research/HEAD/docs/external/bosker_baghdad_london/bagdad_london_final_restat.dta',sha256='2b0df0f46e2e5d008733461f366c6f78761ad49c441c6cdb669a47f06bb5003e',version='Harvard Dataverse doi:10.7910/DVN/24747 (bagdad_london_final_restat.dta), mirror in github.com/nikunjt0/HRE-Urban-City-Research, fetched 2026-10-26',licence='CC0 1.0 (Dataverse terms, per mirror README)',citation='Bosker M, Buringh E, van Zanden JL (2013) From Baghdad to London: Unraveling urban development in Europe, the Middle East, and North Africa, 800-1800. Rev Econ Stat 95(4):1418-1437 (Bairoch-type European figures + MENA estimates)',note='dataverse.harvard.edu blocked by proxy.',used='p1000, p1500, p1800 from citypop_le5 (thousands; 0 = below 5,000 or unrecorded -> blank)'),
 dict(id='ne-places',file='ne_10m_populated_places.geojson',url=GH+'nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_populated_places.geojson',sha256='9b8e3de09048ef00dfc70357dbb9fa324493f214b5e0ae4daf1aa79a8d10116b',version='Natural Earth v5.1.2',licence='Public domain (Made with Natural Earth)',citation='Natural Earth 1:10m Populated Places v5.1.2',used='p2020 = POP2020 (UN World Urbanization Prospects agglomeration series carried by NE); fallback POP_MAX (undated, ~2010s, source id ne-popmax)'),
 dict(id='ne-ports',file='ne_10m_ports.geojson',url=GH+'nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_ports.geojson',sha256='c5a5028f5187a5e1b9fe7f0fab99804a8be7482099a2365d404fb7e9dd6b5457',version='Natural Earth v5.1.2',licence='Public domain (Made with Natural Earth)',citation='Natural Earth 1:10m Ports v5.1.2',used=f'port=1 if an NE port point lies within {PORT_KM} km'),
 dict(id='pleiades',file='pleiades-places.csv',url=GH+'isawnyu/pleiades.datasets/v4.1/data/gis/places.csv',sha256='5dd09b1a92c53e50cb9962bab44df12c5f0b7b683d4f228367d843637cfe5a59',version='pleiades.datasets v4.1 (28 May 2025), git tag v4.1',licence='CC BY 3.0',citation='Pleiades gazetteer of ancient places, isawnyu/pleiades.datasets v4.1',used=f'port=1 if a Pleiades place typed port/harbor lies within {PORT_KM} km; coordinates of places-manual.csv'),
 dict(id='pleiades-types',file='pleiades-places_place_types.csv',url=GH+'isawnyu/pleiades.datasets/v4.1/data/gis/places_place_types.csv',sha256='846acc52098771ead0ee673bf92e8304906389fc681c1750107f28d584e09d24',version='pleiades.datasets v4.1, git tag v4.1',licence='CC BY 3.0',citation='Pleiades gazetteer, place-type join table',used='place types for port flag and manual-site check'),
]
NOT_USED=[
 dict(id='hyde',why='HYDE hosts (geo.public.data.uu.nl, public.yoda.uu.nl) blocked by proxy'),
 dict(id='orbis',why='github emeeks/orbis_v2 sites.csv reachable but has no port flag or population; orbis.stanford.edu blocked'),
 dict(id='itiner-e',why='itiner-e.org and zenodo blocked by proxy'),
 dict(id='darmc',why='darmc.harvard.edu / dataverse blocked by proxy'),
 dict(id='ghsl',why='ghsl.jrc.ec.europa.eu blocked; NE POP2020 (UN WUP) used for 2020 instead'),
 dict(id='wikidata',why='query.wikidata.org and www.wikidata.org blocked by proxy'),
 dict(id='buringh-2021',why='Buringh city-population dataset (DANS/dataverse) blocked; Bosker-Buringh-van Zanden 2013 used instead'),
]
def fetch(s):
 p=RAW/s['file'];p.parent.mkdir(parents=True,exist_ok=True)
 if not p.exists():subprocess.run(['curl','-fLsS','--max-time','300','-o',str(p),s['url']],check=True)
 h=hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
 if h!=s['sha256']:raise RuntimeError(f"hash changed: {s['id']} {h}")
 return p
def norm(s):
 s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
 return re.sub(r'\s+',' ',re.sub(r'[^a-z0-9 ]',' ',s)).strip()
def aliases(*xs):
 out=set()
 for x in xs:
  if x is None or (isinstance(x,float) and math.isnan(x)):continue
  for part in re.split(r'[(),;/|~\[\]]',str(x)):
   n=norm(part)
   if len(n)>=3 and n not in('the','city','al','el'):out.add(n)
 return out
def km(a,b,c,d):
 a,b,c,d=map(math.radians,(a,b,c,d));return 6371*2*math.asin(math.sqrt(math.sin((d-b)/2)**2+math.cos(b)*math.cos(d)*math.sin((c-a)/2)**2))
def namematch(A,B):
 for a in A:
  for b in B:
   if a==b or (min(len(a),len(b))>=4 and (a.startswith(b) or b.startswith(a))) or difflib.SequenceMatcher(None,a,b).ratio()>=0.85:return True
 return False
inbox=lambda x,y:BBOX[0]<=x<=BBOX[2] and BBOX[1]<=y<=BBOX[3]
def num(v):
 if v is None:return None
 if isinstance(v,str):
  v=v.replace(',','').strip()
  if not v:return None
 try:v=float(v)
 except ValueError:return None
 return None if math.isnan(v) or v<=0 else v
def colyear(c):
 m=re.fullmatch(r'(BC|AD)_(\d+)',c);return None if not m else(-1 if m[1]=='BC' else 1)*int(m[2])
def nearest(row,cols,Y,tol):
 best=None
 for c,y in cols:
  v=num(row.get(c))
  if v and abs(y-Y)<=tol and(best is None or abs(y-Y)<abs(best[1]-Y)):best=(v,y)
 return best
R=[]  # records: src,names,lon,lat,pop{year:(value,source,data_year)},port,label
def reba(sid,years_src):
 d=pd.read_csv(RAW/next(s['file']for s in S if s['id']==sid),encoding='cp1252',dtype=str)
 cols=[(c,colyear(c))for c in d.columns if colyear(c)is not None]
 for _,r in d.iterrows():
  try:x,y=float(r.Longitude),float(r.Latitude)
  except(TypeError,ValueError):continue
  if not inbox(x,y):continue
  pop={}
  for Y in years_src:
   b=nearest(r,cols,Y,TOL[Y])
   if b:pop[Y]=(round(b[0]),sid,b[1])
  if pop:R.append(dict(src=sid,label=r.City,names=aliases(r.City,r.OtherName),lon=x,lat=y,pop=pop,port=False,cert=int(num(r.Certainty)or 1)))
def hanson():
 x=pd.read_excel(RAW/'Hanson2016_CitiesDatabase_OxREP.xlsx',sheet_name=None)
 ho=pd.read_csv(RAW/'HansonOrtmanetal2017_dataset.csv');ho=ho[ho['Area (ha)']>0]
 lx,ly=np.log(ho['Area (ha)'].values),np.log(ho.Population.values);m=np.ones(len(lx),bool)
 for _ in range(10):p,c=np.polyfit(lx[m],ly[m],1);m=np.abs(ly-(c+p*lx))<0.05
 d=math.exp(c);area=x['Areas'].set_index('Primary Key').Area
 mon=x['Monuments'];harb=set(mon[mon.Structure.str.match(r'^(Harbour|Lighthouse)',na=False)&~mon.Structure.str.contains(r'\?',na=False)]['Primary Key'])
 for _,r in x['Cities'].iterrows():
  lon,lat=float(r['Longitude (X)']),float(r['Latitude (Y)'])
  if not inbox(lon,lat):continue
  st,en=r['Start Date'],r['End Date'];active=(pd.isna(st) or st<=117)and(pd.isna(en) or en>=117)
  a=area.get(r['Primary Key']);pop={}
  if active and a is not None and not pd.isna(a) and a>0:pop[117]=(round(d*a**p),'hanson',117)
  anc=re.sub(r'\s*\(.*\)$','',str(r['Ancient Toponym']))
  R.append(dict(src='hanson',label=anc,modern=r['Modern Toponym'],names=aliases(r['Ancient Toponym'],r['Modern Toponym']),lon=lon,lat=lat,pop=pop,port=r['Primary Key']in harb,hanson=True))
 return dict(d=round(d,3),p=round(float(p),4),n_fit=int(m.sum()),n_sample=len(lx))
def b2l():
 d=pd.read_stata(RAW/'b2l-bagdad_london_final_restat.dta')
 for (name,lon,lat),g in d.groupby(['city','longitude','latitude']):
  if not inbox(lon,lat):continue
  pop={Y:(int(v*1000),'b2l',Y)for Y in(1000,1500,1800)for v in g.loc[g.year==Y,'citypop_le5']if v>0}
  if pop:R.append(dict(src='b2l',label=re.sub(r'\s*\(.*','',name).strip(),names=aliases(name),lon=float(lon),lat=float(lat),pop=pop,port=False))
def ne():
 for f in json.load(open(RAW/'ne_10m_populated_places.geojson'))['features']:
  q=f['properties'];x,y=f['geometry']['coordinates']
  if not inbox(x,y):continue
  if (q.get('POP2020')or 0)>0:pop={2020:(int(q['POP2020'])*1000,'ne-places',2020)}
  elif (q.get('POP_MAX')or 0)>=MINPOP:pop={2020:(int(q['POP_MAX']),'ne-popmax',None)}
  else:continue
  R.append(dict(src='ne',label=q['NAME'],names=aliases(q['NAME'],q['NAMEASCII'],q['NAMEALT'],q['NAME_EN'],q['NAME_DE'],q['NAME_FR'],q['NAME_IT'],q['NAME_ES'],q['NAME_TR'],q['MEGANAME'],q['LS_NAME']),lon=x,lat=y,pop=pop,port=False))
PRIO={117:['hanson','modelski-anc','chandler'],400:['modelski-anc','chandler'],1000:['b2l','chandler','modelski-anc'],1500:['b2l','chandler'],1800:['b2l','chandler'],1900:['chandler'],2020:['ne-places','modelski-mod','ne-popmax']}
COORD=['ne','b2l','hanson','chandler','modelski-anc','modelski-mod']
def cluster():
 # constrained single-link: candidate pairs sorted (name-matched first, then by distance); two groups join only if their source sets are disjoint
 key=lambda r:(int(math.floor(r['lon'])),int(math.floor(r['lat'])));grid={}
 for i,r in enumerate(R):grid.setdefault(key(r),[]).append(i)
 E=[]
 for i,r in enumerate(R):
  kx,ky=key(r)
  for a in range(kx-2,kx+3):
   for b in range(ky-2,ky+3):
    for j in grid.get((a,b),[]):
     q=R[j]
     if j<=i or q['src']==r['src']:continue
     dk=km(r['lon'],r['lat'],q['lon'],q['lat']);lim={0:MERGE_KM,1:MERGE_LOOSE_KM,2:MERGE_LOOSE_KM,3:MERGE_CERT3_KM}[max(r.get('cert',0),q.get('cert',0))]
     nm=namematch(r['names'],q['names'])
     if (nm and dk<lim)or dk<MERGE_NONAME_KM:E.append((0 if nm else 1,dk,i,j))
 par=list(range(len(R)));srcs=[{r['src']}for r in R]
 def f(i):
  while par[i]!=i:par[i]=par[par[i]];i=par[i]
  return i
 for _,_,i,j in sorted(E):
  a,b=f(i),f(j)
  if a!=b and not(srcs[a]&srcs[b]):par[b]=a;srcs[a]|=srcs[b]
 G={}
 for i,r in enumerate(R):G.setdefault(f(i),[]).append(r)
 return[dict(members=m)for m in G.values()]
def slug(s):return re.sub(r'[^a-z0-9]+','-',norm(s)).strip('-')[:40]or'place'
def main():
 for s in S:fetch(s)
 reba('chandler',[117,400,1000,1500,1800,1900]);reba('modelski-anc',[117,400,1000]);reba('modelski-mod',[2020])
 fit=hanson();b2l();ne();C=cluster()
 pts=[(f['geometry']['coordinates'][0],f['geometry']['coordinates'][1],'ne-ports')for f in json.load(open(RAW/'ne_10m_ports.geojson'))['features']]
 pl=pd.read_csv(RAW/'pleiades-places.csv',encoding='utf-8-sig',usecols=['id','title','representative_latitude','representative_longitude','location_precision'])
 pt=pd.read_csv(RAW/'pleiades-places_place_types.csv',encoding='utf-8-sig');portids=set(pt[pt.place_type.isin(['port','harbor'])].place_id)
 pp=pl[pl.id.isin(portids)&(pl.location_precision=='precise')].dropna(subset=['representative_longitude'])
 pts+=[(r.representative_longitude,r.representative_latitude,'pleiades')for r in pp.itertuples()]
 pgrid={}
 for x,y,s in pts:pgrid.setdefault((int(math.floor(x*5)),int(math.floor(y*5))),[]).append((x,y,s))
 rows=[];used=set();dropped3=[]
 for c in C:
  ms=c['members'];bysrc={m['src']:m for m in ms};pop={};chosen={}
  for Y in YEARS:
   for sid in PRIO[Y]:
    if sid!='b2l' and 'b2l' in bysrc and Y in(1000,1500,1800):break  # B2L row present: authoritative, 0 (=<5,000) blocks fallback
    v=[m['pop'][Y]for m in ms if Y in m['pop']and m['pop'][Y][1]==sid]
    if v:pop[Y]=v[0][0];chosen[Y]=sid;break
  hz=any(m.get('hanson')for m in ms)
  if all(m.get('cert',0)==3 for m in ms):dropped3.append(ms[0]['label']);continue  # only low-certainty Reba geocodes: not placed
  if not hz and max(pop.values(),default=0)<MINPOP:continue
  rep=next(bysrc[s]for s in COORD if s in bysrc);x,y=rep['lon'],rep['lat']
  srcs={v[1]for m in ms for v in m['pop'].values()}|({'hanson'}if hz else set())
  port=any(m['port']for m in ms)
  kx,ky=int(math.floor(x*5)),int(math.floor(y*5))
  for i in range(kx-1,kx+2):
   for j in range(ky-1,ky+2):
    for px,py,s in pgrid.get((i,j),[]):
     if km(x,y,px,py)<=PORT_KM:port=True;srcs.add(s)
  mod=next((bysrc[s]['label']for s in['ne','b2l','chandler','modelski-mod','modelski-anc']if s in bysrc),None)
  h=bysrc.get('hanson')
  if mod is None:mod=h['modern']if h is not None and isinstance(h.get('modern'),str)and h['modern'].strip()else h['label']
  mod=re.sub(r'[\u200b-\u200f\u202a-\u202e\ufeff]','',str(mod)).strip()
  name=mod if h is None or norm(h['label'])==norm(mod)else f"{mod} ({h['label']})"
  base=slug(mod);i=base;n=2
  while i in used:i=f'{base}-{n}';n+=1
  used.add(i)
  rows.append(dict(id=i,name=name,lon=round(x,4),lat=round(y,4),**{f'p{Y}':pop.get(Y,'')for Y in YEARS},port=int(port),sources=';'.join(sorted(srcs)),_chosen=chosen))
 rows.sort(key=lambda r:r['id'])
 OUT.mkdir(parents=True,exist_ok=True)
 cols=['id','name','lon','lat']+[f'p{Y}'for Y in YEARS]+['port','sources']
 with open(OUT/'places.csv','w',newline='')as f:
  w=csv.DictWriter(f,cols,extrasaction='ignore',lineterminator='\n');w.writeheader();w.writerows(rows)
 with open(OUT/'places-control.csv','w',newline='')as f:
  w=csv.writer(f,lineterminator='\n');w.writerow(['year','rank','name','lon','lat','pop','source'])
  for Y in[117,1000,1500,2020]:
   top=sorted([r for r in rows if r[f'p{Y}']!=''],key=lambda r:-r[f'p{Y}'])[:50]
   for k,r in enumerate(top,1):w.writerow([Y,k,r['name'],r['lon'],r['lat'],r[f'p{Y}'],r['_chosen'][Y]])
 manual(pl,pt)
 cov={f'p{Y}':sum(1 for r in rows if r[f'p{Y}']!='')for Y in YEARS}
 for s in S:s['raw_file']=str((RAW/s['file']).relative_to(ROOT))
 meta=dict(generated_by='tools/gametiles_places.py',region_bbox_lon_lat=BBOX,sample_years=YEARS,year_tolerance=TOL,
  rules=dict(value_choice='per sample year, the first source in priority order that has a value within tolerance',priority=PRIO,
   hanson_p117=f'N=d*A^p, d={fit["d"]}, p={fit["p"]} fitted to Hanson-Ortman 2017 sample ({fit["n_fit"]}/{fit["n_sample"]} pairs within 5%); only cities with Start<=117<=End; model estimate, not a count',
   b2l='citypop_le5*1000; 0 means below 5,000 -> blank; where a place has a B2L row, B2L is authoritative for 1000/1500/1800 (no fallback to Chandler/Modelski)',reba_cert3='places formed only by Reba rows with Certainty 3 (low location certainty) are not placed: '+'; '.join(sorted(set(dropped3))),ne='POP2020*1000 (field is in thousands; UN WUP agglomeration, dated 2020) else POP_MAX (undated, NE v5.1.2) as source ne-popmax',
   dedup=f'same place if <{MERGE_KM} km (<{MERGE_LOOSE_KM} km when a Reba/Chandler-Modelski row with Certainty 1-2 is involved, <{MERGE_CERT3_KM} km for Certainty 3: Reba geocodes are often 10-35 km off) and a name/alias match (exact, prefix>=4 chars, or difflib ratio>=0.85), or <{MERGE_NONAME_KM} km regardless of name; constrained single-link, a merged place never holds two rows of the same source',
   keep=f'max population >= {MINPOP} in any sample year, or listed by Hanson 2016',port=f'Hanson Monuments Harbour*/Lighthouse* (no "?"), or Pleiades port/harbor (precise) or NE port within {PORT_KM} km',
   coords='first available of '+','.join(COORD),sources_column='all sources matched to the place (population, port or Hanson membership), not only the ones whose value was chosen'),
  counts=dict(rows=len(rows),coverage=cov,ports=sum(r['port']for r in rows)),sources=S,not_used=NOT_USED)
 (OUT/'places-sources.json').write_text(json.dumps(meta,indent=1,ensure_ascii=False)+'\n')
 print(json.dumps(meta['counts']),fit)
# Hand-picked game-relevant sites missing from population data. Coordinates are looked up from Pleiades v4.1 (precise only).
MANUAL=[(540726,'Delphi','Panhellenisches Heiligtum/Orakel'),(570531,'Olympia','Panhellenisches Heiligtum, Spiele'),(530843,'Dodona','Orakelheiligtum Epirus'),
 (599587,'Delos','Heiligtum und Freihafen'),(599593,'Didyma','Apollon-Orakel bei Milet'),(716520,'Ammon (Siwa)','Orakel des Ammon, Oase'),(786089,'Philae','Isis-Heiligtum, Südgrenze Ägyptens'),
 (570316,'Isthmia','Heiligtum und Isthmische Spiele'),(963101156,'Laureion','Silberminen Attikas'),(236536,'Las Médulas','Römische Goldminen'),(82301,'Dolaucothi','Römische Goldminen in Wales'),
 (281718504,'Alburnus Maior','Goldminen Dakiens'),(256297,'Metallum Vipascense','Kupfer-/Silberbergbau Lusitanien'),(766391,'Mons Porphyrites','Porphyr-Steinbruch Ostwüste'),
 (89313,'Vindolanda','Hadrianswall-Kastell'),(89311,'Vercovicium (Housesteads)','Hadrianswall-Kastell'),(79678,'Segontium','Kastell Nordwales'),(109297,'Saalburg','Limes-Kastell Obergermanien'),
 (177661,'Vindonissa','Legionslager'),(108867,'Castra Vetera','Legionslager Niedergermanien'),(118929,'Castra Regina','Legionslager Raetien'),(216899,'Novae','Legionslager Untere Donau'),
 (334570,'Lambaesis','Legionslager Numidien'),(334553,'Gemellae','Kastell Fossatum Africae'),(687968,'Masada','Festung Judäa'),
 (541140,'Thermopylae','Engpass Griechenland'),(191777,'Brenner Pass','Alpenpass'),(167871,'Poeninus (Großer St. Bernhard)','Alpenpass Summus Poeninus'),(167743,'Summae Alpes (Montgenèvre)','Alpenpass Alpis Cottia'),(570317,'Isthmos von Korinth','Landenge/Diolkos')]
def manual(pl,pt):
 P=pl.set_index('id');rows=[]
 for pid,name,why in MANUAL:
  r=P.loc[pid]
  if r.location_precision!='precise' or pd.isna(r.representative_longitude):raise RuntimeError(f'pleiades {pid} not precise')
  x,y=float(r.representative_longitude),float(r.representative_latitude)
  if not inbox(x,y):raise RuntimeError(f'{name} outside region')
  rows.append([slug(name),name,round(x,4),round(y,4),4,f'Designentscheidung (Vorschlag): {why}; Koordinate: Pleiades {pid} "{r.title}" v4.1 (precise)'])
 with open(OUT/'places-manual.csv','w',newline='')as f:
  w=csv.writer(f,lineterminator='\n');w.writerow(['id','name','lon','lat','tier','reason']);w.writerows(rows)
if __name__=='__main__':main()
