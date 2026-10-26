#!/opt/anaconda3/bin/python
import pathlib,json,math,hashlib,numpy as np
from scipy import ndimage
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';PAY=OUT/'payload';R=6371008.8;SX=R*math.pi/180*math.cos(math.radians(41));SY=R*math.pi/180

def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def smooth(t):t=np.clip(t,0,1);return t*t*t*(t*(t*6-15)+10)
def weight(lon,lat):return smooth((lon+12)/.5)*smooth((47-lon)/.5)*smooth((lat-20)/.5)*smooth((59-lat)/.5)
def query(a,b,lon,lat):
 h,w=a.shape[:2];x=np.clip((np.asarray(lon)-b[0])/(b[2]-b[0])*w-.5,0,w-1);y=np.clip((b[3]-np.asarray(lat))/(b[3]-b[1])*h-.5,0,h-1);x,y=np.broadcast_arrays(x,y);x0=x.astype(int);y0=y.astype(int);fx=x-x0;fy=y-y0;x1=np.minimum(x0+1,w-1);y1=np.minimum(y0+1,h-1)
 if a.ndim==3:fx=fx[...,None];fy=fy[...,None]
 return (a[y0,x0].astype('f8')*(1-fx)+a[y0,x1].astype('f8')*fx)*(1-fy)+(a[y1,x0].astype('f8')*(1-fx)+a[y1,x1].astype('f8')*fx)*fy

def main():
 fine=np.memmap(PAY/'fine-model-height.f32',dtype='<f4',mode='r',shape=(9360,14160));old=np.memmap(ROOT/'data/gameworld-v1/payload/core-model-height.f32',dtype='<f4',mode='r',shape=(8880,13680));coarse=np.memmap(ROOT/'data/gameworld-v1/payload/context-model-height.f32',dtype='<f4',mode='r',shape=(1290,3690));fb=[-12,20,47,59];cb=[-44,18,79,61];native=np.memmap(OUT/'source-observations/fine-height.f32',dtype='<f4',mode='r',shape=fine.shape);core_equal=np.array_equal(fine[240:9120,240:13920],old)
 def height(lon,lat):
  w=weight(lon,lat);return query(coarse,cb,lon,lat)*(1-w)+query(fine,fb,lon,lat)*w
 def normal(lon,lat):
  e=25.;dx=(height(lon+e/SX,lat)-height(lon-e/SX,lat))/(2*e);dz=(height(lon,lat-e/SY)-height(lon,lat+e/SY))/(2*e);v=np.array([-dx,1,-dz],dtype='f8');return v/np.linalg.norm(v)
 probes=[];max_limit=0.;max_angle=0.
 for lon,lat in [(-11,26),(46,26),(-11,32),(46,32),(-12,26),(47,26),(-12,32),(47,32)]:
  e=.01;hh=height(lon,lat);left=height(lon-e/SX,lat);right=height(lon+e/SX,lat);der=(height(lon+1/SX,lat)-height(lon-1/SX,lat))/2;res=abs((right-left)-2*e*der);nl=normal(lon-e/SX,lat);nr=normal(lon+e/SX,lat);angle=math.degrees(math.acos(float(np.clip(np.dot(nl,nr),-1,1))));max_limit=max(max_limit,float(res));max_angle=max(max_angle,angle);probes.append({'lon':lon,'lat':lat,'weight':float(weight(lon,lat)),'composed_height_m':float(hh),'height_continuity_residual_m':float(res),'one_sided_normal_angle_degrees':angle})
 maximum=0.;count=0
 # Complete noncore halo inputcentres, bounded memory; no newmodelgeneration.
 windows=[(0,0,240,9360),(13920,0,240,9360),(240,0,13680,240),(240,9120,13680,240)]
 for x,y,w,h in windows:
  for row in range(y,y+h,64):
   stop=min(y+h,row+64);lon=-12+(np.arange(x,x+w)+.5)/240;lat=59-(np.arange(row,stop)+.5)/240;actual=height(lon[None,:],lat[:,None]);error=np.abs(actual-native[row:stop,x:x+w]);maximum=max(maximum,float(error.max()));count+=error.size
 # Sourcecoast accuracy only in fullytrustednativeconfidence; outercollar isexplicitsourcefusion.
 d=np.load(OUT/'source-observations/local-composition-inputs.npz');raw=d['source_classes'];lb=d['bounds'];h,w=raw.shape;labels,n=ndimage.label(raw==80);sizes=np.bincount(labels.ravel());sizes[0]=0;marine=labels==int(sizes.argmax());edge=marine&~ndimage.binary_erosion(marine);edge[0,:]=False;edge[-1,:]=False;edge[:,0]=False;edge[:,-1]=False;yy,xx=np.nonzero(edge);lon=lb[0]+(xx+.5)*(lb[2]-lb[0])/w;lat=lb[3]-(yy+.5)*(lb[3]-lb[1])/h;trusted=(lon>=lb[0]+.03)&(lon<=lb[2]-.03)&(lat>=lb[1]+.03)&(lat<=lb[3]-.03);pack=np.memmap(PAY/'local-distance.rg8',dtype='u1',mode='r',shape=(h,w,2));sdf=(pack[:,:,0].astype('f4')*256+pack[:,:,1])*.125-4096;dist=np.abs(query(sdf,lb,lon,lat));innermax=float(dist[trusted].max());outermax=float(dist[~trusted].max()) if (~trusted).any() else 0.;closest=int(np.argmin(((lon-9.37)*SX)**2+((lat-44.3)*SY)**2));near=(np.abs((lon-lon[closest])*SX)<250)&(np.abs((lat-lat[closest])*SY)<250);nearmax=float(dist[near&trusted].max()) if (near&trusted).any() else None
 sem=json.loads((OUT/'semantic-composition-checks.json').read_text());geo=json.loads((OUT/'geometry-composition-checks.json').read_text());loc=json.loads((OUT/'local-composition.json').read_text());manifest=json.loads((OUT/'landscape.pending.json').read_text());bad=[]
 for k,a in manifest['assets'].items():
  if sha(OUT/a['path'])!=a['sha256']:bad.append(k)
 field_probes=[]
 cw=np.memmap(PAY/'context-surface-weights.rgba8',dtype='u1',mode='r',shape=(2580,7380,4));fw=np.memmap(PAY/'fine-surface-weights.rgba8',dtype='u1',mode='r',shape=(7020,10620,4));cs=np.memmap(PAY/'context-distance.rg8',dtype='u1',mode='r',shape=(2580,7380,2));fs=np.memmap(PAY/'fine-distance.rg8',dtype='u1',mode='r',shape=(6144,8192,2));cc=np.memmap(PAY/'context-classes.u8',dtype='u1',mode='r',shape=(2580,7380));fc=np.memmap(PAY/'fine-classes.u8',dtype='u1',mode='r',shape=(7020,10620))
 def sdf_at(a,b,x,y):
  rg=query(a,b,x,y);return float((rg[0]*256+rg[1])*.125-4096)
 def cls_at(a,b,x,y):return int(a[min(a.shape[0]-1,max(0,int((b[3]-y)/(b[3]-b[1])*a.shape[0]))),min(a.shape[1]-1,max(0,int((x-b[0])/(b[2]-b[0])*a.shape[1])))])
 for x,y in [(-10.999,26),(45.999,26),(-10.999,32),(45.999,32),(45.99,32)]:
  ww=float(weight(x,y));ca=query(cw,cb,x,y);fa=query(fw,fb,x,y);sp=sdf_at(cs,cb,x,y);fp=sdf_at(fs,fb,x,y);field_probes.append({'lon':x,'lat':y,'fine_weight':ww,'raw_context_height_m':float(query(coarse,cb,x,y)),'raw_fine_height_m':float(query(fine,fb,x,y)),'composed_height_m':float(height(x,y)),'context_class':cls_at(cc,cb,x,y),'fine_class':cls_at(fc,fb,x,y),'context_RGBA':ca.tolist(),'fine_RGBA':fa.tolist(),'composed_RGBA':((1-ww)*ca+ww*fa).tolist(),'context_SDF_m':sp,'fine_SDF_m':fp,'composed_SDF_m':(1-ww)*sp+ww*fp,'composed_normal':normal(x,y).tolist()})
 v1=sha(ROOT/'data/gameworld-v1/landscape.json');checks={'revision':'gameworld-v2-verification','manifest_sha256':sha(OUT/'landscape.pending.json'),'inherited_v1_manifest_sha256':v1,'inherited_v1_unchanged':v1=='7dc424f5011c74dde822102616d959f9d18812963c98285f83fe74e052d93f7c','core_height_bitidentical':core_equal,'halo_native15s_samples_checked':count,'composed_halo_max_vertical_error_m':maximum,'halo_budget_m':2500,'seam_probes':probes,'same_coordinate_geometry_semantic_SDF_probes':field_probes,'seam_max_height_continuity_residual_m':max_limit,'seam_max_one_sided_normal_angle_degrees':max_angle,'source_native_marine_edge_samples':int(trusted.sum()),'trusted_native_coast_to_canonicalSDF_max_projected_m':innermax,'trusted_coast_budget_m':100,'native_coast_500m_window_max_projected_m':nearmax,'native_coast_probe_lon_lat':[float(lon[closest]),float(lat[closest])],'outer_sourcefusion_raw_native_disagreement_m':outermax,'outer_disagreement_scope':'Sourceconfidencefusion collar, not a100m native-onlyaccuracy claim. Both realobservations and spatialpolicyexplicit.','managed_forest_after':{k:x['managed_forest_after'] for k,x in sem['domains'].items()},'land_nodata_after':{k:x['unknown_land_pixels_regionalfallback'] for k,x in sem['domains'].items()},'geometry':geo,'local_source_guard_failures':loc['source_guard_failures'],'local_forest_water_overlap':loc['forest_water_overlap'],'asset_hash_mismatches':bad,'asset_count':len(manifest['assets'])}
 passed=core_equal and checks['inherited_v1_unchanged'] and maximum<=2500 and max_limit<=.01 and max_angle<=.01 and innermax<=100 and not geo['protected_island_anchors_missing'] and geo['global_land_valid'] and geo['local_marine_component_count']==1 and not bad and not any(checks['managed_forest_after'].values()) and not any(checks['land_nodata_after'].values()) and loc['source_guard_failures']==0 and loc['forest_water_overlap']==0;checks['passed']=bool(passed);(OUT/'verification.json').write_text(json.dumps(checks,indent=2)+'\n');print(json.dumps(checks,indent=2));raise SystemExit(0 if passed else 1)
if __name__=='__main__':main()
