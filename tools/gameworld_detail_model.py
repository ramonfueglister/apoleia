#!/opt/homebrew/bin/python3.14
"""Nativewindow -> simplified feature-preserving local coast/forestmodel candidate.
Does not mutate active gameworld-v1 or claim outerdomain composition is solved.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import collections,hashlib,json,math,pathlib
import numpy as np
from osgeo import gdal,ogr,osr
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-detail-v1';PAY=OUT/'payload';SRC=ROOT/'data/gameworld-v1/source-observations/ligurian-native-worldcover-2021v200.tif';POL=json.loads((OUT/'policy.json').read_text());gdal.UseExceptions();ogr.UseExceptions()
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def save(p,d):p.write_text(json.dumps(d,indent=2)+'\n')
def points(g):
 if g.GetPointCount():yield from g.GetPoints()
 else:
  for i in range(g.GetGeometryCount()):yield from points(g.GetGeometryRef(i))
def polygons(kind,mask,src,forward,inverse):
 w,h=src.RasterXSize,src.RasterYSize;mem=gdal.GetDriverByName('MEM').Create('',w,h,1,gdal.GDT_Byte);mem.SetGeoTransform(src.GetGeoTransform());mem.SetProjection(src.GetProjection());mem.GetRasterBand(1).WriteArray(mask);vector=ogr.GetDriverByName('Memory').CreateDataSource('');layer=vector.CreateLayer('areas',None,ogr.wkbPolygon);layer.CreateField(ogr.FieldDefn('value',ogr.OFTInteger));gdal.Polygonize(mem.GetRasterBand(1),None,layer,0,[],None);features=[];omissions=[];records=[];largest=None
 for j,f in enumerate(layer):
  if f.GetField('value')!=1:continue
  g=f.GetGeometryRef().Clone();g.Transform(forward);source_repaired=not g.IsValid()
  if source_repaired:g=g.MakeValid()
  area=g.GetArea();minimum=POL[kind+'_min_component_area_projected_m2'];fid=f'native-{kind}:{j}'
  if area<minimum:omissions.append(dict(id=fid,area_projected_m2=area,rule=f'{kind}-minarea-{minimum}'));continue
  simple=g.SimplifyPreserveTopology(POL['coast_simplification_projected_m'] if kind=='water' else POL['forest_simplification_projected_m'])
  simplification_fallback=False
  if not simple.IsValid():simple=g.Clone();simplification_fallback=True
  if not simple.IsValid() or (kind=='water' and simple.GetGeometryCount()!=g.GetGeometryCount()):raise RuntimeError('Protectedcomponent/hole changed '+fid)
  pts=list(points(g));boundary=simple.Boundary();dist=[]
  for p in pts[::max(1,len(pts)//32)]:
   pt=ogr.Geometry(ogr.wkbPoint);pt.AddPoint_2D(p[0],p[1]);dist.append(pt.Distance(boundary))
  record=dict(id=fid,source_geometry_makevalid=source_repaired,simplification_retained_exact_valid_source_fallback=simplification_fallback,source_geometry_components_or_rings=g.GetGeometryCount(),model_geometry_components_or_rings=simple.GetGeometryCount(),source_area_projected_m2=area,source_vertices=len(pts),model_vertices=len(list(points(simple))),directed_sample_max_projected_m=max(dist,default=0),sample_count=len(dist),holes_preserved=simple.GetGeometryCount()-1);records.append(record)
  simple.Transform(inverse);features.append(dict(type='Feature',properties=dict(source_component_id=fid,source_role='permanentwater' if kind=='water' else 'treecover',source_id='ESA2021v200-N42E009-nativewindow'),geometry=json.loads(simple.ExportToJson())))
 p=PAY/(kind+'.geojson');save(p,dict(type='FeatureCollection',features=features));print(kind,'retained',len(features),'omitted',len(omissions),flush=True);return dict(model=ref(p),retained=records,omissions=omissions,maximum_directed_sample_projected_m=max((x['directed_sample_max_projected_m'] for x in records),default=0))
def rasterize(path,b,wh):
 w,s,e,n=b;d=gdal.GetDriverByName('MEM').Create('',*wh,1,gdal.GDT_Byte);d.SetGeoTransform([w,(e-w)/wh[0],0,n,0,-(n-s)/wh[1]]);d.SetProjection('EPSG:4326');v=ogr.Open(str(path));gdal.RasterizeLayer(d,[1],v.GetLayer(),burn_values=[1]);return d.ReadAsArray()
def main():
 src=gdal.Open(str(SRC));a=src.ReadAsArray();gt=src.GetGeoTransform();w,h=src.RasterXSize,src.RasterYSize;b=[gt[0],gt[3]+gt[5]*h,gt[0]+gt[1]*w,gt[3]];srs=osr.SpatialReference();srs.ImportFromEPSG(4326);srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);target=osr.SpatialReference();target.ImportFromProj4('+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m');target.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);forward=osr.CoordinateTransformation(srs,target);inverse=osr.CoordinateTransformation(target,srs);water=polygons('water',(a==80).astype('u1'),src,forward,inverse);forest=polygons('forest',(a==10).astype('u1'),src,forward,inverse);nw=4096;nh=round(nw*h/w);wm=rasterize(PAY/'water.geojson',b,(nw,nh));fm=rasterize(PAY/'forest.geojson',b,(nw,nh));fm[wm>0]=0
 # Model classes andmaterialfields retainunknown/managed sourceclass provenance separately.
 coarse=gdal.Warp('',src,options=['-novshift'],format='MEM',outputBounds=b,width=nw,height=nh,dstSRS='EPSG:4326',resampleAlg='near').ReadAsArray();fm[(coarse==40)|(coarse==50)|(coarse==0)]=0;classes=np.full((nh,nw),30,dtype='u1');classes[coarse==0]=0;classes[fm>0]=10;classes[wm>0]=80;classes.tofile(PAY/'classes.u8');wm.astype('u1').tofile(PAY/'water.u8');fm.astype('u1').tofile(PAY/'forest-membership.u8')
 save(OUT/'model.json',dict(schema_version='gameworld-local-model-v1',revision='gameworld-detail-v1',status='implementiert',source=ref(SRC),source_observation=ref(ROOT/'data/gameworld-v1/coast-detail-source.json'),policy=ref(OUT/'policy.json'),bounds=dict(zip(['west','south','east','north'],b)),width=nw,height=nh,water=water,forest=forest,classes=ref(PAY/'classes.u8'),water_membership=ref(PAY/'water.u8'),forest_membership=ref(PAY/'forest-membership.u8'),managed_forest_pixel_count=int(np.count_nonzero(((coarse==40)|(coarse==50))&(classes==10))),raw_source_class_histogram={str(int(k)):int(v) for k,v in zip(*np.unique(a,return_counts=True))},integration_status=POL['integration_status'],height_binding='frozen gameworld-v1 canonical TIN, sameEqc41 and0.001scale; no newheightorreliefnoise'))
 print('candidate model ready',OUT/'model.json',flush=True)
if __name__=='__main__':main()
