#!/opt/homebrew/bin/python3.14
"""Versioned real water model + CPU triangle lookup acceleration, no GPU session."""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import argparse,hashlib,json,math,pathlib
import numpy as np
from osgeo import gdal,ogr,osr
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v1';PAY=OUT/'payload';gdal.UseExceptions();ogr.UseExceptions()
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def save(p,d):p.write_text(json.dumps(d,indent=2)+'\n')
def refs(geom):
 if geom.GetGeometryType() in [ogr.wkbPolygon,ogr.wkbPolygon25D]:return 1
 return sum(refs(geom.GetGeometryRef(i)) for i in range(geom.GetGeometryCount())) if geom.GetGeometryCount() else 1

def water():
 pol=json.loads((OUT/'model-world-policy.json').read_text());w,s,e,n=pol['source_bounds']['render_context'];clip=ogr.CreateGeometryFromWkt(f'POLYGON(({w} {s},{e} {s},{e} {n},{w} {n},{w} {s}))');srcsrs=osr.SpatialReference();srcsrs.ImportFromEPSG(4326);srcsrs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);dst=osr.SpatialReference();dst.ImportFromProj4('+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m');dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);forward=osr.CoordinateTransformation(srcsrs,dst);inverse=osr.CoordinateTransformation(dst,srcsrs);inventory=[];features=[]
 for kind in ['land','lakes','rivers']:
  source=ROOT/f'data/raw/ne_10m_{"rivers_lake_centerlines" if kind=="rivers" else kind}.geojson';ds=ogr.Open(str(source));layer=ds.GetLayer();layer.SetSpatialFilterRect(w,s,e,n);fs=[];stats=[]
  for f in layer:
   gg=f.GetGeometryRef().Clone()
   if not gg.IsValid():gg=gg.MakeValid()
   cut=gg.Intersection(clip)
   if cut.IsEmpty():continue
   props=json.loads(f.ExportToJson())['properties'];sid=str(props.get('ne_id',f.GetFID()));cut.Transform(forward);out=cut.SimplifyPreserveTopology(100.0)
   if not out.IsValid() or refs(out)!=refs(cut):raise RuntimeError('Water component/topology changed '+sid)
   # Measure deterministic native-vertex samples against simplified geometry.
   boundary=out.Boundary() if kind!='rivers' else out
   sample=[]
   def points(g):
    if g.GetPointCount():return g.GetPoints()
    return [p for j in range(g.GetGeometryCount()) for p in points(g.GetGeometryRef(j))]
   pts=points(cut);step=max(1,len(pts)//64)
   for p in pts[::step]:
    pt=ogr.Geometry(ogr.wkbPoint);pt.AddPoint_2D(p[0],p[1]);sample.append(float(pt.Distance(boundary)))
   oldpoints=len(pts);newpoints=len(points(out));out.Transform(inverse);props['source_id']=sid;props['gameworld_feature_id']=f'{kind}:{sid}';fs.append(dict(type='Feature',properties=props,geometry=json.loads(out.ExportToJson())))
   stats.append(dict(id=props['gameworld_feature_id'],source_feature_id=sid,source_vertex_count=oldpoints,model_vertex_count=newpoints,component_count=refs(cut),sampled_directed_distance_projected_m_max=max(sample,default=0),sample_count=len(sample)))
  p=PAY/(kind+'.geojson');save(p,dict(type='FeatureCollection',features=fs));inventory.append(dict(kind=kind,source=ref(source),model=ref(p),features=stats));features.extend(stats);print(kind,len(fs),flush=True)
 # Derive both model water rasters from own simplified physical contours.
 for domain,b,wh in [('context',pol['source_bounds']['render_context'],(7380,2580)),('core',pol['source_bounds']['core'],(8192,6144))]:
  w,s,e,n=b;ds=gdal.GetDriverByName('MEM').Create('',*wh,1,gdal.GDT_Byte);ds.SetGeoTransform([w,(e-w)/wh[0],0,n,0,-(n-s)/wh[1]]);ds.SetProjection('EPSG:4326');ds.GetRasterBand(1).Fill(1)
  for kind,burn in [('land',0),('lakes',2)]:
   src=ogr.Open(str(PAY/(kind+'.geojson')));gdal.RasterizeLayer(ds,[1],src.GetLayer(),burn_values=[burn])
  ds.ReadAsArray().astype('u1').tofile(PAY/(domain+'-water.u8'))
 save(OUT/'water-model.json',dict(schema_version='gameworld-water-v1',revision='gameworld-v1',status='implementiert',simplification_tolerance_projected_m=100,measurement='deterministic native-vertex samples directed to simplified boundary in eqc41 source projected metres; projection distortion is separate, source accuracy unknown',inventory=inventory,model_water_fields=[ref(PAY/(d+'-water.u8')) for d in ['context','core']],sources_and_sinks='not a hydraulic waterbalance, physical surface/cartographic network only',unexpected_component_changes=0))

def bins():
 for domain in ['core','context']:
  p=OUT/(domain+'-mesh-manifest.json')
  if not p.exists():continue
  m=json.loads(p.read_text())
  for b in m['blocks']:
   v=np.fromfile(ROOT/b['vertices']['path'],dtype='<f4').reshape(-1,3);idx=np.fromfile(ROOT/b['indices']['path'],dtype='<u4').reshape(-1,3);xz=v[:,[0,2]].astype('f8');lo=xz.min(0);size=np.ptp(xz,axis=0);n=32;lists=[[] for _ in range(n*n)];tri=xz[idx];tl=np.floor((tri.min(1)-lo)/size*n).astype(int);th=np.floor((tri.max(1)-lo)/size*n).astype(int);tl=np.clip(tl,0,n-1);th=np.clip(th,0,n-1)
   for fi,(a,z) in enumerate(zip(tl,th)):
    for y in range(a[1],z[1]+1):
     for x in range(a[0],z[0]+1):lists[y*n+x].append(fi)
   offsets=np.r_[0,np.cumsum([len(z) for z in lists])].astype('<u4');ids=np.array([x for z in lists for x in z],dtype='<u4');op=PAY/'blocks'/(b['id']+'.pick-offsets.u32');ip=PAY/'blocks'/(b['id']+'.pick-faces.u32');offsets.tofile(op);ids.tofile(ip);b['picking_grid']=dict(dimensions=[n,n],world_min=lo.tolist(),world_size=size.tolist(),offsets=ref(op),face_ids=ref(ip),offsets_path=str(op.relative_to(OUT)),face_ids_path=str(ip.relative_to(OUT)),rule='bin=floor((modelXZ-world_min)/world_size*32) clamped0..31; range offsets[bin]..offsets[bin+1]; candidatefaceIDs refer to index triplerows; barycentric weights from storedFloat32XZ, height from sameFloat32Y. Include boundary epsilon1e-6modelunits.')
  # Exact source-grid identity is the canonical coordinate definition; XYZf32 is transport.
  sm=json.loads((OUT/'source-observations.json').read_text())['domains'][domain];sw,sh=sm['height_dimensions'];bb=sm['bounds'];src=np.memmap(ROOT/sm['height']['path'],dtype='<f4',mode='r',shape=(sh,sw));rr=6371008.8
  for block in m['blocks']:
   xyz=np.fromfile(ROOT/block['vertices']['path'],dtype='<f4').reshape(-1,3).astype('f8');lon=xyz[:,0]/(.001*rr*math.cos(math.radians(41)))*180/math.pi+19;lat=41-xyz[:,2]/(.001*rr)*180/math.pi;xx=np.rint((lon-bb[0])/(bb[2]-bb[0])*sw-.5).astype('<u4');yy=np.rint((bb[3]-lat)/(bb[3]-bb[1])*sh-.5).astype('<u4');sp=PAY/'blocks'/(block['id']+'.source-grid.u32');hp=PAY/'blocks'/(block['id']+'.source-height.f32');np.c_[xx,yy].astype('<u4').tofile(sp);np.asarray(src[yy,xx],dtype='<f4').tofile(hp);block['canonical_source_grid']=ref(sp);block['canonical_source_heights']=ref(hp);block['canonical_coordinate_rule']='UInt32LE global source grid column,row at native pixelcentres; sourceFloat32height unchanged; Eqc41 formula and common0.001scale define exact canonical coordinates. verticesFloat32 is runtime transport.'
  save(p,m);print('picking bins',domain,len(m['blocks']),flush=True)
def main():
 a=argparse.ArgumentParser();a.add_argument('action',choices=['water','bins']);v=a.parse_args();water() if v.action=='water' else bins()
if __name__=='__main__':main()
