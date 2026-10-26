#!/opt/homebrew/bin/python3.14
"""Freeze same-coordinate canonical/native inputs for local contour composition."""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import pathlib,json,numpy as np
from osgeo import gdal,ogr
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';RAW=OUT/'source-observations';gdal.UseExceptions();ogr.UseExceptions()
def raster(path,b,wh,burn=1,initial=0):
 ds=gdal.GetDriverByName('MEM').Create('',*wh,1,gdal.GDT_Byte);ds.SetGeoTransform([b[0],(b[2]-b[0])/wh[0],0,b[3],0,-(b[3]-b[1])/wh[1]]);ds.SetProjection('EPSG:4326');ds.GetRasterBand(1).Fill(initial);src=ogr.Open(str(path));gdal.RasterizeLayer(ds,[1],src.GetLayer(),burn_values=[burn]);return ds.ReadAsArray()
def main():
 local=json.loads((ROOT/'data/gameworld-detail-v1/model.json').read_text());b=[local['bounds'][k] for k in ['west','south','east','north']];wh=(local['width'],local['height']);land=raster(ROOT/'data/gameworld-v1/payload/land.geojson',b,wh);lakes=raster(ROOT/'data/gameworld-v1/payload/lakes.geojson',b,wh);global_water=np.where(land==0,1,np.where(lakes>0,2,0)).astype('u1');src=gdal.Open(str(ROOT/local['source']['path']));sourceclasses=gdal.Warp('',src,format='MEM',outputBounds=b,width=wh[0],height=wh[1],dstSRS='EPSG:4326',resampleAlg='near').ReadAsArray();gt=src.GetGeoTransform();oldclass=np.memmap(ROOT/'data/gameworld-v1/payload/core-classes.u8',dtype='u1',mode='r',shape=(6660,10260));xs=np.clip(((b[0]+(np.arange(wh[0])+.5)*(b[2]-b[0])/wh[0]+11)/57*10260).astype(int),0,10259);ys=np.clip(((58-(b[3]-(np.arange(wh[1])+.5)*(b[3]-b[1])/wh[1]))/37*6660).astype(int),0,6659);global_forest=oldclass[ys[:,None],xs[None,:]]==10
 nativewater=raster(ROOT/local['water']['model']['path'],b,wh);nativeforest=raster(ROOT/local['forest']['model']['path'],b,wh);np.savez(RAW/'local-composition-inputs.npz',bounds=np.array(b),global_water=global_water,global_forest=global_forest,native_water=nativewater,native_forest=nativeforest,source_classes=sourceclasses);print('prepared local',wh,b,flush=True)
if __name__=='__main__':main()
