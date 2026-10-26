#!/opt/homebrew/bin/python3.14
"""Targeted native ESA permanent-water observation for a proven missing coastalform.
No full tile download. Freeze source nativewindow/hash and retain all classes.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
os.environ['GDAL_DISABLE_READDIR_ON_OPEN']='EMPTY_DIR'
os.environ['CPL_VSIL_CURL_ALLOWED_EXTENSIONS']='.tif'
os.environ['GDAL_HTTP_MAX_RETRY']='1'
os.environ['GDAL_HTTP_TIMEOUT']='60'
import argparse,hashlib,json,pathlib,time
import numpy as np
from osgeo import gdal
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v1';RAW=OUT/'source-observations';gdal.UseExceptions()
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 p=RAW/'ligurian-native-worldcover-2021v200.tif';meta=OUT/'coast-detail-source.json'
 if p.exists() and meta.exists():print('Existing frozen nativewindow',sha(p));return
 url='https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N42E009_Map.tif';ds=gdal.Open('/vsicurl/'+url);b=[9.24,44.20,9.65,44.44];start=time.monotonic();out=gdal.Translate(str(p),ds,format='GTiff',projWin=[b[0],b[3],b[2],b[1]],creationOptions=['COMPRESS=DEFLATE','TILED=YES']);a=out.ReadAsArray();gt=out.GetGeoTransform();m=dict(revision='ligurian-water-native-observation-v1',role='targetedcoastformsourcecandidate; sourceESAclass80permanentwater, classes0/40/50/otherretainedforrolevalidation',reason='Independent visualowner observed only~3canonicalNE1:10Mcoastsegments across5km after rasterstairs were removed; geometric source detail is missing, not hidden bypalette.',url=url,version='ESA2021v200',license='CC-BY4.0',attribution='ESA WorldCoverproject2021; modifiedCopernicusSentineldata2021 processedby ESAWorldCoverconsortium',requested_bounds=b,actual_geotransform=list(gt),dimensions=[out.RasterXSize,out.RasterYSize],source_dimensions=[ds.RasterXSize,ds.RasterYSize],source_native_geotransform=list(ds.GetGeoTransform()),crs='EPSG:4326',native_read=True,overview_read=False,artifact=dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size),full_remote_cog_sha256=None,hash_scope='lossless nativepixelwindow frozen locally, not complete remoteCOG',class_histogram={str(int(k)):int(v) for k,v in zip(*np.unique(a,return_counts=True))},elapsed_seconds=time.monotonic()-start,status='erforscht',limitations='Modern permanentwater classification; no tidaldatum or historicalcoast. Suitability must be checked againstmarine/source NoData before source-to-model conversion. No invented coastline.' );meta.write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m,indent=2))
if __name__=='__main__':main()
