#!/opt/homebrew/bin/python3.14
"""Fine render-distance tile from canonical model water contours, never new geography.
Reproducible arbitrary-bound access: same callable pipeline for any visibleregion.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import argparse,hashlib,json,math,pathlib
import numpy as np
from osgeo import gdal,ogr,osr
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v1';PAY=OUT/'payload/water-tiles';PAY.mkdir(exist_ok=True);gdal.UseExceptions();ogr.UseExceptions();R=6371008.8

def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def lines(g):
 if g.GetPointCount():yield g.GetPoints()
 else:
  for i in range(g.GetGeometryCount()):yield from lines(g.GetGeometryRef(i))
def main():
 a=argparse.ArgumentParser();a.add_argument('--lon',type=float,required=True);a.add_argument('--lat',type=float,required=True);a.add_argument('--size-m',type=float,default=64000);a.add_argument('--resolution',type=int,default=4096);q=a.parse_args();cx=(q.lon-19)*math.pi/180*R*math.cos(math.radians(41));cy=(q.lat-41)*math.pi/180*R;size=q.size_m;n=q.resolution;w=cx-size/2;s=cy-size/2;e=cx+size/2;nn=cy+size/2;step=size/n;name=f'water-{q.lon:.5f}-{q.lat:.5f}-{int(size)}-{n}';radius=3000.;field=np.full((n,n),radius,dtype='f4');src=osr.SpatialReference();src.ImportFromEPSG(4326);src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);dst=osr.SpatialReference();dst.ImportFromProj4('+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m');dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);transform=osr.CoordinateTransformation(src,dst)
 raster=gdal.GetDriverByName('MEM').Create('',n,n,1,gdal.GDT_Byte);raster.SetGeoTransform([w,step,0,nn,0,-step]);raster.SetProjection(dst.ExportToWkt());raster.GetRasterBand(1).Fill(1);sources=[];segs=0
 for kind,burn in [('land',0),('lakes',2)]:
  path=OUT/'payload'/(kind+'.geojson');sources.append(ref(path));ds=ogr.Open(str(path));layer=ds.GetLayer();memory=ogr.GetDriverByName('Memory').CreateDataSource('');ml=memory.CreateLayer(kind,dst,ogr.wkbUnknown)
  for f in layer:
   g=f.GetGeometryRef().Clone();g.Transform(transform);env=g.GetEnvelope()
   if env[1]<w-radius or env[0]>e+radius or env[3]<s-radius or env[2]>nn+radius:continue
   ff=ogr.Feature(ml.GetLayerDefn());ff.SetGeometry(g);ml.CreateFeature(ff)
   for line in lines(g):
    for aa,bb in zip(line,line[1:]):
     ax,ay=aa[:2];bx,by=bb[:2];x0=max(0,int(math.floor((min(ax,bx)-radius-w)/step)));x1=min(n-1,int(math.ceil((max(ax,bx)+radius-w)/step)));y0=max(0,int(math.floor((nn-max(ay,by)-radius)/step)));y1=min(n-1,int(math.ceil((nn-min(ay,by)+radius)/step)))
     if x1<x0 or y1<y0:continue
     dx=bx-ax;dy=by-ay;den=dx*dx+dy*dy
     if den<1e-16:continue
     xx=(w+(np.arange(x0,x1+1)+.5)*step-ax)[None,:];yy=(nn-(np.arange(y0,y1+1)+.5)*step-ay)[:,None];t=np.clip((xx*dx+yy*dy)/den,0,1);dist=np.hypot(xx-t*dx,yy-t*dy);np.minimum(field[y0:y1+1,x0:x1+1],dist,out=field[y0:y1+1,x0:x1+1]);segs+=1
  gdal.RasterizeLayer(raster,[1],ml,burn_values=[burn])
  print(kind,'segments',segs,flush=True)
 water=raster.ReadAsArray();wp=PAY/(name+'.water.u8');water.astype('u1').tofile(wp);dp=PAY/(name+'.distance.rg8');maximum=0.
 with dp.open('wb') as f:
  for y in range(n):
   signed=field[y].astype('f8')*np.where(water[y]>0,1.,-1.);code=np.rint((signed+4096.)*8).astype('u2');decoded=code.astype('f8')*.125-4096.;maximum=max(maximum,float(np.max(abs(decoded-signed))));packed=np.c_[code>>8,code&255].astype('u1');f.write(packed.tobytes())
 b=dict(west=w/(R*math.cos(math.radians(41)))*180/math.pi+19,south=s/R*180/math.pi+41,east=e/(R*math.cos(math.radians(41)))*180/math.pi+19,north=nn/R*180/math.pi+41);m=dict(schema_version='gameworld-water-tile-v1',revision='model-vector-distance-tile-v1',role='canonical-model-to-render distance encoding; not newsource shoreline or bathymetry',id=name,bounds=b,width=n,height=n,world_min=[w*.001,-nn*.001],world_size=[size*.001,size*.001],source_contours=sources,water=ref(wp),distance=ref(dp),distance_encoding='UInt8RG highbyte/lowbyte; signedprojectedmetres=-4096+.125*(R*256+G); positivewater,negativeland; saturation±3000m',segments=segs,cell_step_projected_m=step,quantization_max_projected_m=maximum,source_accuracy='inherits canonical NE1:10M and model100mcontour simplification; fineencoding does not claimfinergeoaccuracy');mp=PAY/(name+'.json');mp.write_text(json.dumps(m,indent=2)+'\n');print(str(mp),flush=True)
if __name__=='__main__':main()
