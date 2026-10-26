#!/opt/homebrew/bin/python3.14
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import pathlib,json,hashlib,math,numpy as np
from osgeo import gdal,ogr
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';PAY=OUT/'payload';gdal.UseExceptions();ogr.UseExceptions();R=6371008.8;SX=R*math.pi/180*math.cos(math.radians(41));SY=R*math.pi/180

def read(p):return json.loads(p.read_text())
def save(p,d):p.write_text(json.dumps(d,indent=2)+'\n')
def union(features):
 result=None
 for f in features:
  g=ogr.CreateGeometryFromJson(json.dumps(f['geometry']));result=g if result is None else result.Union(g)
 return result

def rasterize(path,b,wh,initial=0,burn=1):
 ds=gdal.GetDriverByName('MEM').Create('',*wh,1,gdal.GDT_Byte);ds.SetGeoTransform([b[0],(b[2]-b[0])/wh[0],0,b[3],0,-(b[3]-b[1])/wh[1]]);ds.SetProjection('EPSG:4326');ds.GetRasterBand(1).Fill(initial);src=ogr.Open(str(path));gdal.RasterizeLayer(ds,[1],src.GetLayer(),burn_values=[burn]);return ds.ReadAsArray()
def polygonize(a,b):
 h,w=a.shape;ds=gdal.GetDriverByName('MEM').Create('',w,h,1,gdal.GDT_Byte);ds.SetGeoTransform([b[0],(b[2]-b[0])/w,0,b[3],0,-(b[3]-b[1])/h]);ds.SetProjection('EPSG:4326');ds.GetRasterBand(1).WriteArray(a);v=ogr.GetDriverByName('Memory').CreateDataSource('');l=v.CreateLayer('model',None,ogr.wkbPolygon);l.CreateField(ogr.FieldDefn('kind',ogr.OFTInteger));gdal.Polygonize(ds.GetRasterBand(1),None,l,0,[],None);fs=[]
 for i,f in enumerate(l):
  g=f.GetGeometryRef().Clone()
  if not g.IsValid():g=g.MakeValid()
  fs.append({'type':'Feature','properties':{'kind':f.GetField('kind'),'composition_id':i},'geometry':json.loads(g.ExportToJson())})
 return fs

def pts(g):
 if g.GetPointCount():return [p[:2] for p in g.GetPoints()]
 return [p for i in range(g.GetGeometryCount()) for p in pts(g.GetGeometryRef(i))]
def snap_boundary(geometry,targets,b):
 count=0;maximum=0.
 def visit(g):
  nonlocal count,maximum
  for i in range(g.GetPointCount()):
   x,y,*_=g.GetPoint(i)
   if min(abs(x-b[0]),abs(x-b[2]),abs(y-b[1]),abs(y-b[3]))>1e-8:continue
   if not targets:continue
   distances=[math.hypot((x-t[0])*SX,(y-t[1])*SY) for t in targets];j=int(np.argmin(distances))
   if distances[j]<=50:g.SetPoint_2D(i,*targets[j]);count+=1;maximum=max(maximum,distances[j])
  for i in range(g.GetGeometryCount()):visit(g.GetGeometryRef(i))
 visit(geometry);return count,maximum

def main():
 local=read(OUT/'local-composition.json');b=[local['bounds'][k] for k in ['west','south','east','north']];w,h=local['width'],local['height'];kind=np.fromfile(PAY/'local-water.u8',dtype='u1').reshape(h,w);forest=np.fromfile(PAY/'local-forest-membership.u8',dtype='u1').reshape(h,w);clip=ogr.CreateGeometryFromWkt(f'POLYGON(({b[0]} {b[1]},{b[2]} {b[1]},{b[2]} {b[3]},{b[0]} {b[3]},{b[0]} {b[1]}))');oldland=read(ROOT/'data/gameworld-v1/payload/land.geojson')['features'];outside=[];targets=[]
 for f in oldland:
  g=ogr.CreateGeometryFromJson(json.dumps(f['geometry']));cross=g.Boundary().Intersection(clip.Boundary());targets.extend(pts(cross));cut=g.Difference(clip)
  if not cut.IsEmpty():outside.append({'type':'Feature','properties':f['properties'],'geometry':json.loads(cut.ExportToJson())})
 landfs=polygonize((kind!=1).astype('u1'),b);inside=union([f for f in landfs if f['properties']['kind']==1]);snaps,snapmax=snap_boundary(inside,targets,b);allland=union(outside).Union(inside)
 if not allland.IsValid():allland=allland.MakeValid()
 save(PAY/'land.geojson',{'type':'FeatureCollection','features':[{'type':'Feature','properties':{'source_id':'NE5.1.2+ESA2021v200-local-confidence-composition','revision':'gameworld-v2','source_rule':'regionalphysicaloutsideROI, nativecoastinsideconfidence, C2signeddistancecollar and exactregionalboundaryjoin'},'geometry':json.loads(allland.ExportToJson())}]})
 oldlakes=read(ROOT/'data/gameworld-v1/payload/lakes.geojson')['features'];lakefs=[]
 for f in oldlakes:
  g=ogr.CreateGeometryFromJson(json.dumps(f['geometry']));cut=g.Difference(clip)
  if not cut.IsEmpty():lakefs.append({'type':'Feature','properties':f['properties'],'geometry':json.loads(cut.ExportToJson())})
 localwaterfs=polygonize(kind,b);marine=[]
 for f in localwaterfs:
  k=f['properties']['kind']
  if k==2:f['properties'].update(source_id='ESA-native-inland:'+str(f['properties']['composition_id']),water_role='inland',level_source='canonicalTIN; surfacelevel uncertainty not surveyed',historical180='unknown');lakefs.append(f)
  elif k==1:f['properties']['water_role']='marine_connected_to_regional_ocean';marine.append(f)
 save(PAY/'lakes.geojson',{'type':'FeatureCollection','features':lakefs});save(PAY/'local-marine.geojson',{'type':'FeatureCollection','features':marine});save(PAY/'local-forest.geojson',{'type':'FeatureCollection','features':[f for f in polygonize(forest,b) if f['properties']['kind']==1]})
 # Every domain is a representation of the same composedphysicalgeometry.
 for domain,bb,wh in [('context',[-44,18,79,61],(7380,2580)),('fine',[-12,20,47,59],(8192,6144)),('local',b,(w,h))]:
  land=rasterize(PAY/'land.geojson',bb,wh);lakes=rasterize(PAY/'lakes.geojson',bb,wh);a=np.where(land==0,1,np.where(lakes>0,2,0)).astype('u1');a.tofile(PAY/(domain+'-water.u8'));print('water roles',domain,dict(zip(*np.unique(a,return_counts=True))),flush=True)
 required=[(14,37.5),(9,40),(9,42),(24.9,35.2),(33,35)];missing=[]
 for x,y in required:
  point=ogr.Geometry(ogr.wkbPoint);point.AddPoint_2D(x,y)
  if not allland.Intersects(point):missing.append([x,y])
 checks={'revision':'gameworld-v2-geometry-composition','regional_boundary_snap_count':snaps,'regional_boundary_snap_max_projected_m':snapmax,'regional_boundary_target_intersections':len(targets),'global_land_valid':bool(allland.IsValid()),'protected_island_anchors_missing':missing,'local_marine_component_count':len(marine),'local_inland_feature_count':sum(f['properties'].get('water_role')=='inland' for f in lakefs),'source_notes':'Permanentwater class doesnot classify natural/artificial origin or historicaldate; no dams/buildings imported.','canonical_geography':'Allmain/fine/localwaterrole fields derivefromsamecomposedland/lakegeometries; explicitnativewatermarineconnectedcomponent.'};save(OUT/'geometry-composition-checks.json',checks)
 if missing or not allland.IsValid():raise RuntimeError('Protected geography failed')
 print('geometry composition done',checks,flush=True)
if __name__=='__main__':main()
