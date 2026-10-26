#!/usr/bin/env python3
"""Independent read-only source-segment and bilinear-zero-contour SDF probe.
Writes only requested advisory report files; never any product source/payload.
"""
import json,pathlib,math,hashlib,sys,argparse
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--manifest',default='artifacts/render-data/water-distance.json');parser.add_argument('--payload',default='artifacts/render-data/water-distance.u8');parser.add_argument('--rg8',action='store_true');args=parser.parse_args()
m=json.loads((ROOT/args.manifest).read_text());b=m['identity']['bounds'];w=m['identity']['width'];h=m['identity']['height'];R=6371008.8;C=math.cos(math.radians(41));sx=math.radians(b['east']-b['west'])*R*C/w;sy=math.radians(b['north']-b['south'])*R/h
class RG8Codes:
 def __init__(self,path):self.data=np.memmap(path,dtype='u1',mode='r',shape=(h,w,2))
 def __getitem__(self,index):
  p=self.data[index];return p[...,0].astype(np.float64)*256+p[...,1].astype(np.float64)
raw=RG8Codes(ROOT/args.payload)if args.rg8 else np.memmap(ROOT/args.payload,dtype='u1',mode='r',shape=(h,w))
STEP,OFFSET=(.125,-4096.)if args.rg8 else (6000/255,-3000.)
kind=np.memmap(ROOT/'data/derived/water-detail.u8',dtype='u1',mode='r',shape=(h,w))
segments=[];excluded=0
for source in ['data/derived/land.geojson','data/derived/lakes.geojson']:
 for f in json.loads((ROOT/source).read_text())['features']:
  g=f['geometry'];polys=[g['coordinates']]if g['type']=='Polygon'else g['coordinates']
  for poly in polys:
   for ring in poly:
    for a,c in zip(ring,ring[1:]):
     if any(abs(a[k]-v)<1e-8 and abs(c[k]-v)<1e-8 for k,v in [(0,b['west']),(0,b['east']),(1,b['south']),(1,b['north'])]):excluded+=1;continue
     A=[math.radians(a[0]-b['west'])*R*C,math.radians(b['north']-a[1])*R];B=[math.radians(c[0]-b['west'])*R*C,math.radians(b['north']-c[1])*R]
     if np.dot(np.subtract(B,A),np.subtract(B,A))>1e-16:segments.append(A+B)
seg=np.asarray(segments);A=seg[:,:2];V=seg[:,2:]-A;L=np.sum(V*V,axis=1)
def nearest(p):
 d=p-A;t=np.clip(np.sum(d*V,axis=1)/L,0,1);return float(np.sqrt(np.min(np.sum((d-t[:,None]*V)**2,axis=1))))
def grid(lon,lat):return ((lon-b['west'])/(b['east']-b['west'])*w-.5,(b['north']-lat)/(b['north']-b['south'])*h-.5)
def geodesic(lon,lat,lon2,lat2):
 dl=np.radians(lon2-lon);dp=np.radians(lat2-lat);v=np.sin(dp/2)**2+math.cos(math.radians(lat))*np.cos(np.radians(lat2))*np.sin(dl/2)**2;return 2*R*np.arcsin(np.sqrt(np.clip(v,0,1)))
coast=np.loadtxt(ROOT/'data/derived/coast-detail.csv',delimiter=',',skiprows=1,usecols=[0,1]);rng=np.random.default_rng(445)
# Spatially distributed shorepoints, broad background, exact reported film view.
queries=[]
for lon,lat in coast[::4]:
 x,y=grid(lon,lat);queries.append((max(0,min(w-1,round(x))),max(0,min(h-1,round(y)))))
queries.extend(zip(rng.integers(0,w,256).tolist(),rng.integers(0,h,256).tolist()))
cx,cy=grid(1.0968509912,51.0591201782)
queries.extend((int(cx+dx),int(cy+dy))for dx in range(-10,11,2)for dy in range(-10,11,2))
measurements=[]
for x,y in queries:
 p=np.array([(x+.5)*sx,(y+.5)*sy]);dist=min(nearest(p),3000);signed=dist if kind[y,x]>0 else -dist;code=int(raw[y,x]);decoded=code*STEP+OFFSET;expected=int(math.floor((signed-OFFSET)/STEP+.5));measurements.append(dict(column=int(x),row=int(y),source_signed_projected_m=signed,code=code,expected_code=expected,decoded_projected_m=decoded,error_projected_m=abs(decoded-signed)))
# Build actual bilinear zero-isoline candidates in neighboring cells, using
# exact roots for one coordinate and33 fixed values for the other coordinate.
U=np.linspace(0,1,33)
def nearest_zero(lon,lat,sampling_count=33):
 U=np.linspace(0,1,sampling_count)
 gx,gy=grid(lon,lat);ix=int(math.floor(gx));iy=int(math.floor(gy));candidates=[]
 for yy in range(max(0,iy-5),min(h-1,iy+6)):
  for xx in range(max(0,ix-5),min(w-1,ix+6)):
   f=raw[yy:yy+2,xx:xx+2].astype(float)*STEP+OFFSET
   if f.min()>0 or f.max()<0:continue
   a=f[0,0];bb=f[0,1]-a;cc=f[1,0]-a;dd=f[1,1]-a-bb-cc
   for swap in [False,True]:
    den=(bb if swap else cc)+dd*U;num=-(a+(cc if swap else bb)*U)
    good=np.abs(den)>1e-12;v=np.divide(num,den,out=np.full_like(num,np.nan),where=good);ok=(v>=0)&(v<=1)
    for u,other in zip(U[ok],v[ok]):candidates.append((xx+(other if swap else u),yy+(u if swap else other)))
 if not candidates:return None
 c=np.asarray(candidates);lons=b['west']+(c[:,0]+.5)/w*(b['east']-b['west']);lats=b['north']-(c[:,1]+.5)/h*(b['north']-b['south']);d=geodesic(lon,lat,lons,lats);i=int(d.argmin());return dict(longitude=float(lons[i]),latitude=float(lats[i]),distance_geodesic_m=float(d[i]))
zeros=[]
for lon,lat in coast[::4]:zeros.append(dict(source_longitude=float(lon),source_latitude=float(lat),nearest_bilinear_zero=nearest_zero(lon,lat)))
# Coastal sourcepoints nearest the exact reported film target, not just easy tests.
mid=(seg[:,:2]+seg[:,2:])/2
midlon=b['west']+mid[:,0]/(R*C)*180/math.pi;midlat=b['north']-mid[:,1]/R*180/math.pi
rank=np.argsort(geodesic(1.0968509912,51.0591201782,midlon,midlat))[:64]
film=[dict(source_longitude=float(midlon[i]),source_latitude=float(midlat[i]),source_distance_from_film_target_geodesic_m=float(geodesic(1.0968509912,51.0591201782,midlon[i],midlat[i])),nearest_bilinear_zero=nearest_zero(midlon[i],midlat[i],2049))for i in rank]
# Preserved protected island interiors; their sign must remain land (<0).
islands=[]
for name,(lon,lat)in zip(['Sicily','Sardinia','Corsica','Crete','Cyprus'],json.loads((ROOT/'data/protection-rules.json').read_text())['islands']['anchors']):
 x,y=grid(lon,lat);x,y=round(x),round(y);islands.append(dict(name=name,column=x,row=y,kind=int(kind[y,x]),code=int(raw[y,x]),land_preserved=int(raw[y,x])*STEP+OFFSET<0))
vals=[x['error_projected_m']for x in measurements];zv=[x['nearest_bilinear_zero']['distance_geodesic_m']for x in zeros if x['nearest_bilinear_zero']];fv=[x['nearest_bilinear_zero']['distance_geodesic_m']for x in film if x['nearest_bilinear_zero']]
result=dict(kind='independent-source-vector-SDF-probe',encoding='RG8'if args.rg8 else 'R8',encoding_step_projected_m=STEP,encoding_offset_projected_m=OFFSET,sdf_payload_sha256=hashlib.file_digest(open(ROOT/args.payload,'rb'),'sha256').hexdigest(),source_segment_count=len(segments),artificial_clip_segments_excluded=excluded,texel_sample_count=len(measurements),code_mismatches=sum(x['code']!=x['expected_code']for x in measurements),sample_max_distance_plus_quant_error_projected_m=max(vals),zero_contour_sample_count=len(zeros),zero_contour_missing=sum(x['nearest_bilinear_zero']is None for x in zeros),sample_max_zero_offset_geodesic_m=max(zv)if zv else None,film_zero_curve_samples_per_axis=2049,film_source_sample_count=len(film),film_missing=sum(x['nearest_bilinear_zero']is None for x in film),film_sample_max_zero_offset_geodesic_m=max(fv)if fv else None,protected_islands=islands,texel_measurements=measurements,zero_contour_measurements=zeros,film_measurements=film,limitations='Nearest source segment exact exhaustive Float64 for sampled texels. Zeroiso roots sampled along bilinear curves produce conservative candidate distances, not proven global Hausdorff maximum. No GPU/Screen2px/transition1px validation or all-small-island topology proof. Source smallcomponent omissions remain explicit.')
capture_path=ROOT/'artifacts/runtime/final-mobile-capture/runtime.json'
if capture_path.exists():
 capture=json.loads(capture_path.read_text());matches=[x for x in capture['captures']if x['frame']==334]
 if matches:
  cap=matches[0];far=capture['samples'][0]['visible_width_source_m'];z=cap['zoom'];width=math.exp(math.log(far)*(1-z)+math.log(500)*z);tt=max(0,min(1,(z-.05)/.9));relief=tt*tt*(3-2*tt);el=math.radians(90+(35.2643897-90)*relief);visible=[]
  for point in film:
   q=point['nearest_bilinear_zero']
   if q is None:continue
   lon=point['source_longitude'];lat=point['source_latitude'];dx=math.radians(lon-cap['center'][0])*R*C;dz=-math.radians(lat-cap['center'][1])*R
   if abs(dx)>width/2 or abs(dz*math.sin(el))>width*1080/1920/2:continue
   ex=math.radians(q['longitude']-lon)*R*C;ez=-math.radians(q['latitude']-lat)*R;px=math.hypot(ex,ez*math.sin(el))*1920/width;visible.append(dict(source=point,pixeloffset=px))
  result['film_planar_pixel_diagnostic']=dict(capture_frame=334,center=cap['center'],zoom=z,visible_width_source_m=width,elevation_degrees=math.degrees(el),viewport=[1920,1080],visible_zero_height_point_count=len(visible),maximum_planar_pixel_offset=max(x['pixeloffset']for x in visible)if visible else None,measurements=visible,limitation='Sourcecontour vs bilinear zeroiso projected at old frame334 profile under zeroheight assumption, no actual GPUedge measurement or global Screenpass.')
print(json.dumps(result,indent=2))
