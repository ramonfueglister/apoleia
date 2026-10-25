#!/usr/bin/env python3
"""Measured offline source-space errors; does not pretend runtime pixels."""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import json,pathlib,math
import numpy as np
from osgeo import gdal,ogr
from data_bind import ROOT,save,ref,read,geom
m=read('data/derived/landscape.json');B=m['bounds'];w,e,s,n=[B[k] for k in ['west','east','south','north']]
# Fixed source-cell centre lattice, every17th native15s sample, includes boundaries.
source=gdal.Open(str(ROOT/'data/derived/elevation-source.vrt')) if (ROOT/'data/derived/elevation-source.vrt').exists() else gdal.Open(str(ROOT/'data/raw/ETOPO_2022_v1_60s_N90W180_surface.tif'))
gt=source.GetGeoTransform();out=[]
def sample_bilinear(a,lon,lat):
 x=np.clip((lon-w)/(e-w)*a.shape[1]-.5,0,a.shape[1]-1);y=np.clip((n-lat)/(n-s)*a.shape[0]-.5,0,a.shape[0]-1)
 ix=x.astype(int);iy=y.astype(int);jx=np.minimum(ix+1,a.shape[1]-1);jy=np.minimum(iy+1,a.shape[0]-1);fx=x-ix;fy=y-iy
 return (a[iy,ix]*(1-fx)+a[iy,jx]*fx)*(1-fy)+(a[jy,ix]*(1-fx)+a[jy,jx]*fx)*fy
# Rasterize the entire region at native source registration then sample fixed17.
src=gdal.Translate('',source,format='MEM',projWin=[w,n,e,s]);a=src.ReadAsArray();SG=src.GetGeoTransform()
rows=np.arange(0,a.shape[0],17);cols=np.arange(0,a.shape[1],17);yy,xx=np.meshgrid(rows,cols,indexing='ij');lon=SG[0]+(xx.ravel()+.5)*SG[1];lat=SG[3]+(yy.ravel()+.5)*SG[5];truth=a[yy,xx].ravel()
for level,path,ww,hh in [('overview','overview-height.f32',m['overview']['width'],m['overview']['height']),('canonical','height.f32',m['width'],m['height'])]+([('detail',m['height_detail_path'],m['height_detail_width'],m['height_detail_height'])] if 'height_detail_path'in m else []):
 z=np.memmap(ROOT/'data/derived'/path,dtype='<f4',shape=(hh,ww));observed=sample_bilinear(z,lon,lat);err=np.abs(observed-truth)
 # All samples are exported, plus their source coordinates/values reproducible.
 p=ROOT/f'data/derived/error-{level}.csv';np.savetxt(p,np.column_stack([lon,lat,truth,observed,err]),delimiter=',',header='longitude,latitude,source_height_m,model_unscaled_height_m,absolute_error_m',comments='',fmt='%.9f')
 out.append(dict(level=level,metric='terrain_vertical_m',sample_count=len(err),sample_max=float(err.max()),p95=float(np.quantile(err,.95)),rms=float(np.sqrt(np.mean(err**2))),raw=ref(p),scope='fixed source-centre lattice every17th native pixel; not global bound'))
# Measure local map scale deviation separately from terrain simplification.
R=6371008.8;latitudes=np.arange(s,n+.001,1);sc=np.cos(math.radians(41))/np.cos(np.radians(latitudes));values=[dict(latitude=float(lat),east_west_scale=float(v),north_south_scale=1,projection_scale_error_ratio=float(abs(v-1)))for lat,v in zip(latitudes,sc)]
save('data/derived/projection-measurements.json',dict(metric='projection_scale_error_ratio',method='Analytic infinitesimal principal scales on same sphere R6371008.8; spherical model is separately different from WGS84 ellipsoid.',samples=values,sample_max=max(x['projection_scale_error_ratio']for x in values),note='No false equal-distance/equal-area claim.'))
# Measure actual forward/inverse coordinate round-trip at source sample points.
prx=R*np.cos(np.radians(41))*(lon-19)*np.pi/180;prz=-R*(lat-41)*np.pi/180
backlon=19+prx/(R*np.cos(np.radians(41)))*180/np.pi;backlat=41-prz/R*180/np.pi
horizontal=np.hypot((backlon-lon)*np.pi/180*R*np.cos(np.radians(lat)),(backlat-lat)*np.pi/180*R)
hp=ROOT/'data/derived/horizontal-roundtrip.csv';np.savetxt(hp,np.column_stack([lon,lat,backlon,backlat,horizontal]),delimiter=',',header='longitude,latitude,inverse_longitude,inverse_latitude,distance_m',comments='',fmt='%.15g')
# Source-query positions are preserved by a height-only resampling. Rebuild the
# supplied query geography independently from the actual source affine.
genlon=SG[0]+(xx.ravel()+.5)*SG[1];genlat=SG[3]+(yy.ravel()+.5)*SG[5]
assert np.array_equal(lon,genlon) and np.array_equal(lat,genlat), 'Generalizer moved horizontalquery positions'
hgen=np.hypot((genlon-lon)*np.pi/180*R*np.cos(np.radians(lat)),(genlat-lat)*np.pi/180*R)
hgp=ROOT/'data/derived/horizontal-generalization.csv';np.savetxt(hgp,np.column_stack([lon,lat,genlon,genlat,hgen]),delimiter=',',header='source_query_longitude,source_query_latitude,generalized_query_longitude,generalized_query_latitude,unrounded_displacement_m',comments='',fmt='%.15g')
save('data/derived/derivation-measurements.json',dict(revision=m['dataset_revision'],policy=ref('data/geodata_policy.json'),elevation=out,horizontal_terrain=dict(method='Explicitly specified sourcequery identity for height-only generalization; independent affinequery arrays compared bitwise and unrounded displacement computed',sample_max_m=float(hgen.max()),sample_count=len(hgen),raw=ref(hgp),definition=ref('data/horizontal-metric.json')),projection_roundtrip_diagnostic=dict(sample_max_m=float(horizontal.max()),raw=ref(hp),limitation='Actual finiteprecision diagnostic, not removed or rounded into terrain displacement'),screen_error_px=None,transition_residual_px=None,missing='Runtime screen/transition evidence must come from renderer capture; no offline surrogate. Native source uncertainty remains unknown, separate from resampling error.'))
# Measured coverage inventory is a cell census, not physical geodetic area.
inv=read('data/derived/inventory.json'); save('data/derived/coverage-measurements.json',dict(revision=m['dataset_revision'],region_revision='region-v1',mask_revision='mask-v1',aggregation='Complete canonical pixel-centre census; fractions are sample-cell fractions, not equal-area physical area.',land_cells=inv['land_cells'],water_cells=inv['ocean_lake_cells'],landcover_nodata_cells=inv['unknown_landcover_cells'],elevation_nodata_cells=m['nodata']['elevation'],source_unavailable_tiles=inv['unavailable_worldcover'],reference_containment=ref('data/reference/completeness.json')))
print(json.dumps(out,indent=2))
