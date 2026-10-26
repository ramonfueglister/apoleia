#!/usr/bin/env python3
import json,math
import numpy as np
from data_bind import ROOT,read,save,ref,geom
m=read('data/derived/landscape.json');b=m['bounds'];w,h=m['width'],m['height'];a=np.memmap(ROOT/'data/derived/landcover.u8',dtype='uint8',shape=(h,w));z=np.memmap(ROOT/'data/derived/height.f32',dtype='<f4',shape=(h,w));anchors=read('data/anchors.json')['anchors'][:1]
def add(id,lon,lat,kind,source,feature):
 x=max(0,min(w-1,int((lon-b['west'])/(b['east']-b['west'])*w)));y=max(0,min(h-1,int((b['north']-lat)/(b['north']-b['south'])*h)));anchors.append(dict(id=id,longitude=lon,latitude=lat,kind=kind,source_ref=ref(source),source_feature_id=feature,class_code=int(a[y,x]),height_m=float(z[y,x]),canonical_row=y,canonical_col=x))
for id,lon,lat in [('italy',12.49,41.89),('england',-1.5,54.0),('north-africa',10.2,35.5),('eastern-extent',42,36),('jordandepression',35.5,31.5)]:add(id,lon,lat,'interior','data/etopo15-inventory.json','ETOPO2022v1 native raster sample location')
add('region-edge',b['west'],45,'region_edge','data/reference/mask.geojson','project-mask-v1 west edge')
R=6371008.8;lon=19;add('tile-seam',lon,41,'tile_seam','data/tile-grid.json','eqc41-km-v1:0:0; projectedx=0m,z=0m')
pts=[]
def walk(g):
 if g.GetPointCount():
  for i,p in enumerate(g.GetPoints()):yield i,p
 else:
  for child in g:
   yield from walk(child)
for f in read('data/derived/land.geojson')['features']:
 for i,p in walk(geom(f)):
  if b['west']+.1<p[0]<b['east']-.1 and b['south']+.1<p[1]<b['north']-.1:pts.append(((p[0]-12.2)**2+(p[1]-41.7)**2,p[0],p[1],f['properties']['source_id'],i))
_,lon,lat,fid,i=min(pts);add('coast-ostia',lon,lat,'coast','data/derived/land.geojson',f'sourcefeature{fid}:vertex{i}')
# First woodland anchor was already located at actual sourceclass10 pixel.
anchors[0]['kind']='interior';anchors[0]['source_ref']=ref('data/worldcover-inventory.json');anchors[0]['source_feature_id']='WorldCoverN45E006 native overview pixel; canonical719,1199'
for anchor in anchors:anchor['height_m']=float(z[anchor['canonical_row'],anchor['canonical_col']])
save('data/anchors.json',dict(revision='anchors-v3',anchors=anchors))
print(len(anchors),'anchors')
