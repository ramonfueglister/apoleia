#!/usr/bin/env python3
"""Read-only targeted unquantized source-SDF curvature diagnostic."""
import pathlib,json,math,hashlib
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1]
# Reuse our independently implemented direct source-segment reader/distance,
# before its measurement loops. No renderer/SDFbuilder function is imported.
prefix=(ROOT/'tools/data_sdf_probe.py').read_text().split('coast=np.loadtxt')[0]
ns={'__file__':str(ROOT/'tools/data_sdf_probe.py')};exec(compile(prefix,'independent_sdf_helpers','exec'),ns)
nearest=ns['nearest'];grid=ns['grid'];kind=ns['kind'];sx=ns['sx'];sy=ns['sy'];b=ns['b'];w=ns['w'];h=ns['h'];R=ns['R'];C=ns['C'];geodesic=ns['geodesic']
prior=json.loads((ROOT/'docs/product-data/sdf-probe.json').read_text());visible=prior['film_planar_pixel_diagnostic']['measurements'];cache={}
def value(x,y):
 key=(x,y)
 if key not in cache:
  distance=min(nearest(np.array([(x+.5)*sx,(y+.5)*sy])),3000.);cache[key]=distance*(1 if kind[y,x]>0 else -1)
 return cache[key]
def zero(lon,lat):
 gx,gy=grid(lon,lat);ix=int(math.floor(gx));iy=int(math.floor(gy));candidates=[];U=np.linspace(0,1,4097)
 for y in range(max(0,iy-3),min(h-1,iy+4)):
  for x in range(max(0,ix-3),min(w-1,ix+4)):
   f=np.array([[value(x,y),value(x+1,y)],[value(x,y+1),value(x+1,y+1)]])
   if f.min()>0 or f.max()<0:continue
   a=f[0,0];bb=f[0,1]-a;cc=f[1,0]-a;dd=f[1,1]-a-bb-cc
   for swap in [False,True]:
    den=(bb if swap else cc)+dd*U;num=-(a+(cc if swap else bb)*U);v=np.divide(num,den,out=np.full_like(num,np.nan),where=np.abs(den)>1e-12);ok=(v>=0)&(v<=1)
    for u,other in zip(U[ok],v[ok]):candidates.append((x+(other if swap else u),y+(u if swap else other)))
 if not candidates:return None
 a=np.asarray(candidates);lon2=b['west']+(a[:,0]+.5)/w*(b['east']-b['west']);lat2=b['north']-(a[:,1]+.5)/h*(b['north']-b['south']);d=geodesic(lon,lat,lon2,lat2);i=int(np.argmin(d));return dict(longitude=float(lon2[i]),latitude=float(lat2[i]),distance_geodesic_m=float(d[i]))
old=prior['film_planar_pixel_diagnostic'];measurements=[];el=math.radians(old['elevation_degrees']);width=old['visible_width_source_m']
for p in visible:
 a=p['source'];lon=a['source_longitude'];lat=a['source_latitude'];q=zero(lon,lat);ex=(q['longitude']-lon)*math.pi/180*R*C;ez=-(q['latitude']-lat)*math.pi/180*R;px=math.hypot(ex,ez*math.sin(el))*1920/width
 measurements.append(dict(source_longitude=lon,source_latitude=lat,unquantized_source_SDF_zero=q,planar_pixel_offset=px,previous_R8_planar_pixel_offset=p['pixeloffset']))
result=dict(kind='independent-targeted-Float64-source-SDF-zero-diagnostic',reference_R8_payload_sha256=prior['sdf_payload_sha256'],source_geometry_sha256=ns['m']['identity']['source_sha256'],sampled_source_grid_centres=len(cache),root_samples_per_axis=4097,visible_source_points=len(measurements),max_planar_pixel_offset=max(x['planar_pixel_offset']for x in measurements),measurements=measurements,limitation='Exact direct nearest source segment Float64 distances at relevant centres, no R8/RG8 quantization. Limited3point zeroheight/profile diagnostic of curvature, not fullGPUedge/topology/Screenpass.')
print(json.dumps(result,indent=2))
