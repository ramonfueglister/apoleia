#!/usr/bin/env python3
"""Independent input→clipped-vector consistency and raster shoreline sampling."""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import json,math,collections
import numpy as np
from osgeo import ogr
from data_bind import ROOT,save,read,ref,geom
t=read('data/derived/landscape.json');b=t['bounds'];W,E,S,N=[b[k]for k in ['west','east','south','north']];R=6371008.8
clip=ogr.CreateGeometryFromWkt(f'POLYGON(({W} {S},{E} {S},{E} {N},{W} {N},{W} {S}))');checks=[]
for layer,src in [('land','ne_10m_land'),('rivers','ne_10m_rivers_lake_centerlines'),('lakes','ne_10m_lakes')]:
 expected={};original=read('data/raw/'+src+'.geojson')
 for i,f in enumerate(original['features']):
  g=geom(f)
  if not g.Intersects(clip):continue
  c=g.Intersection(clip)
  if not c.IsEmpty():expected[str(f['properties'].get('ne_id',i))]=c
 actual=read('data/derived/'+layer+'.geojson')['features'];unexpected=[]
 for f in actual:
  id=f['properties']['source_id'];g=geom(f)
  if id not in expected:unexpected.append(id)
  elif not g.Equals(expected[id]):
   delta=g.SymmetricDifference(expected[id]);
   if not delta.IsEmpty() and ((g.GetDimension()==2 and delta.GetArea()>1e-10) or (g.GetDimension()==1 and delta.Length()>1e-12) or g.GetDimension()==0):unexpected.append(id)
 checks.append(dict(layer=layer,source_feature_count=len(expected),output_feature_count=len(actual),unexpected_feature_ids=unexpected,missing_feature_ids=sorted(set(expected)-{f['properties']['source_id']for f in actual}),invalid_outputs=sum(not geom(f).IsValid()for f in actual),method='Independent repeat actual geometry intersection with fixed region; OGR equality; dimension2 symmetric-difference area<=1e-10squaredegrees for JSONfloatingroundoff; dimension1 symmetric-difference LENGTH<=1e-12degrees, never area; points require exactequality. Not a claim of complete real-world hydrography.'))
wm=np.memmap(ROOT/'data/derived/water.u8',dtype='uint8',shape=(t['height'],t['width']));dw=np.memmap(ROOT/'data/derived/water-detail.u8',dtype='uint8',shape=(t['water_detail_height'],t['water_detail_width']))
islands=[]
for name,(lon,lat)in zip(['Sicily','Sardinia','Corsica','Crete','Cyprus'],read('data/protection-rules.json')['islands']['anchors']):
 vals=[]
 for a in [wm,dw]:
  x=int((lon-W)/(E-W)*a.shape[1]);y=int((N-lat)/(N-S)*a.shape[0]);vals.append(int(a[y,x]))
 islands.append(dict(name=name,longitude=lon,latitude=lat,canonical_kind=vals[0],detail_kind=vals[1],preserved_land=all(v==0 for v in vals)))
# Coast: sample every17th vertex of retained polygon exterior rings of >=10km2.
# Smaller islands stay in vector archive but may be subpixel at raster LODs.
points=[];omitted=[]
def polygons(g):
 if g.GetGeometryName()=='POLYGON':yield g
 else:
  for c in g:yield from polygons(c)
for f in read('data/derived/land.geojson')['features']:
 for i,g in enumerate(polygons(geom(f))):
  c=g.Centroid();km2=g.GetArea()*(R*math.pi/180)**2*math.cos(math.radians(c.GetY()))/1e6
  if km2<10:omitted.append(dict(source_feature_id=f['properties']['source_id'],component=i,area_km2=km2,rule='subpixel-small-island'));continue
  ring=g.GetGeometryRef(0)
  points.extend(ring.GetPoints()[::17])
# Source polygon includes regional clipping boundary; coast excludes mapedge.
p=np.asarray(points)[:,:2];p=p[(p[:,0]>W+.05)&(p[:,0]<E-.05)&(p[:,1]>S+.05)&(p[:,1]<N-.05)]
records=[]
ow=np.memmap(ROOT/'data/derived/overview-water.u8',dtype='uint8',shape=(t['overview'].get('water_height',t['overview']['height']),t['overview'].get('water_width',t['overview']['width'])))
for lev,a in [('overview',ow),('canonical',wm),('detail',dw)]:
 h,w=a.shape;water=a>0;edge=np.zeros_like(water);edge[1:]|=water[1:]!=water[:-1];edge[:-1]|=water[1:]!=water[:-1];edge[:,1:]|=water[:,1:]!=water[:,:-1];edge[:,:-1]|=water[:,1:]!=water[:,:-1]
 x=((p[:,0]-W)/(E-W)*w).astype(int);y=((N-p[:,1])/(N-S)*h).astype(int);best=np.full(len(p),np.inf)
 # Bounded search range8cells. Report unresolved distances as missing, never0.
 for dy in range(-8,9):
  for dx in range(-8,9):
   xx=np.clip(x+dx,0,w-1);yy=np.clip(y+dy,0,h-1);valid=edge[yy,xx];lon=W+(xx+.5)/w*(E-W);lat=N-(yy+.5)/h*(N-S)
   d=np.hypot((lon-p[:,0])*np.pi/180*R*np.cos(np.radians(p[:,1])),(lat-p[:,1])*np.pi/180*R);best=np.minimum(best,np.where(valid,d,np.inf))
 out=ROOT/f'data/derived/coast-{lev}.csv';v=np.column_stack([p,best]);np.savetxt(out,v,delimiter=',',header='longitude,latitude,distance_to_nearest_raster_interface_center_m',comments='',fmt='%.9f');finite=np.isfinite(best)
 records.append(dict(level=lev,metric='coastline_displacement_m',method='Approximate local tangent distance to nearest raster-interface pixel centre within8cells, every17th retained source exterior vertex; no global bound and not coastline survey error.',sample_count=len(best),unresolved_count=int((~finite).sum()),sample_max=float(best[finite].max())if finite.any()else None,raw=ref(out)))
save('data/derived/topology-measurements.json',dict(revision=t['dataset_revision'],vector_checks=checks,protected_islands=islands,planned_small_component_omissions=omitted,coastline=records,ridges='Native15s height samples retained; vertical measurement checks lattice. No independently traced or validated real ridge-line network.',tile_seams='Single shared global source raster, stable logical-address contract. Runtime seam triangles and transitions are separate renderer evidence.'))
print(json.dumps(dict(checks=checks,islands=islands,coastline=records,omissions=len(omitted)),indent=2))
