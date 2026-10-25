#!/opt/homebrew/bin/python3.14
"""Whole-context native60s resampling/model error; budgets boundbefore measurement."""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import csv,hashlib,json,pathlib
import numpy as np
from osgeo import gdal
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v1';gdal.UseExceptions()
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def main():
 b=[-44,18,79,61];w,h=7380,2580;smallw,smallh=3690,1290;policy=OUT/'source-resampling-policy.json'
 native=gdal.Warp('',str(ROOT/'data/raw/ETOPO_2022_v1_60s_N90W180_surface.tif'),options=['-novshift'],format='MEM',outputBounds=b,width=w,height=h,dstSRS='EPSG:4326',resampleAlg='near').ReadAsArray();metrics={}
 for name,path,budget in [('prepared',OUT/'source-observations/context-height.f32',2000),('canonical',OUT/'payload/context-model-height.f32',2045)]:
  data=np.memmap(path,dtype='<f4',mode='r',shape=(smallh,smallw));ds=gdal.GetDriverByName('MEM').Create('',smallw,smallh,1,gdal.GDT_Float32);ds.SetGeoTransform([b[0],(b[2]-b[0])/smallw,0,b[3],0,-(b[3]-b[1])/smallh]);ds.SetProjection('EPSG:4326');ds.GetRasterBand(1).WriteArray(data);sampled=gdal.Warp('',ds,options=['-novshift'],format='MEM',outputBounds=b,width=w,height=h,dstSRS='EPSG:4326',resampleAlg='bilinear').ReadAsArray();error=np.abs(sampled.astype('f8')-native);imax=np.unravel_index(error.argmax(),error.shape);maximum=float(error[imax]);ep=OUT/'payload'/('native60s-context-'+name+'-error.f32');error.astype('<f4').tofile(ep);sp=OUT/('native60s-context-'+name+'-samples.csv')
  with sp.open('w') as f:
   wr=csv.writer(f);wr.writerow(['row','column','lon','lat','native_source_height_m','model_height_m','absolute_error_source_m'])
   ids=set(range(0,w*h,4096));ids.add(int(imax[0]*w+imax[1]))
   for k in sorted(ids):
    y,x=divmod(k,w);wr.writerow([y,x,b[0]+(x+.5)*(b[2]-b[0])/w,b[3]-(y+.5)*(b[3]-b[1])/h,float(native[y,x]),float(sampled[y,x]),float(error[y,x])])
  metrics[name]=dict(native_samples_checked=int(w*h),maximum_absolute_height_residual_source_m=maximum,budget_source_m=budget,budget_met=maximum<=budget,maximum_native_sample=[int(imax[0]),int(imax[1])],error_payload=ref(ep),raw_stratified_plus_max_samples=ref(sp),input=ref(path));print(name,maximum,'budget',budget,flush=True)
 report=dict(reference_version='kit1-landscape-v5/astra-replan-v2',revision='native60s-context-metrics-v1',status='validiert' if all(m['budget_met'] for m in metrics.values()) else 'offen',policy=ref(policy),source=ref(ROOT/'data/raw/ETOPO_2022_v1_60s_N90W180_surface.tif'),scope='complete native60s contextsamplecentres; geodetic surveyaccuracy/renderpixels excluded; canonical transport texturebilinear query includes contextTIN reconstruction interpolation',metrics=metrics);(OUT/'source-resampling-measurements.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
