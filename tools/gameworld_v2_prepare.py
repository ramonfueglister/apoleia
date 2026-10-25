#!/opt/homebrew/bin/python3.14
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import pathlib,json,hashlib,numpy as np
from osgeo import gdal
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';RAW=OUT/'source-observations';gdal.UseExceptions()
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 b=[-12,20,47,59];products={}
 for name,source,wh,alg in [('height',ROOT/'data/derived/elevation-source.vrt',(14160,9360),'bilinear'),('cover',ROOT/'data/gameworld-v1/source-observations/context-cover.vrt',(10620,7020),'near')]:
  ds=gdal.Warp('',str(source),format='MEM',options=['-novshift'],outputBounds=b,width=wh[0],height=wh[1],dstSRS='EPSG:4326',resampleAlg=alg);a=ds.ReadAsArray().astype('<f4' if name=='height' else 'u1');p=RAW/('fine-'+name+('.f32' if name=='height' else '.u8'));a.tofile(p);products[name]={'path':str(p.relative_to(ROOT)),'sha256':sha(p),'width':wh[0],'height':wh[1],'minimum':float(a.min()),'maximum':float(a.max()),'unknown_or_nodata':int(np.count_nonzero(a==-99999 if name=='height' else a==0))};print(name,products[name],flush=True)
 (OUT/'halo-source-observations.json').write_text(json.dumps({'revision':'gameworld-v2-halo-observations','bounds':b,'source_policy':'data/gameworld-v2/policy.json','products':products},indent=2)+'\n')
if __name__=='__main__':main()
