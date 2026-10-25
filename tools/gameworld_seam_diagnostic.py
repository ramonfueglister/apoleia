#!/opt/homebrew/bin/python3.14
"""Same-coordinate, independent-domain observations; no model/file mutation."""
import json,pathlib,math,numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[1];BASE=ROOT/'data/gameworld-v1';R=6371008.8;SX=R*math.pi/180*math.cos(math.radians(41));SY=R*math.pi/180

def bilinear(a,b,lon,lat):
 h,w=a.shape[:2];x=(lon-b['west'])/(b['east']-b['west'])*w-.5;y=(b['north']-lat)/(b['north']-b['south'])*h-.5;x=np.clip(x,0,w-1);y=np.clip(y,0,h-1);x0=int(x);y0=int(y);fx=x-x0;fy=y-y0;x1=min(x0+1,w-1);y1=min(y0+1,h-1);return (a[y0,x0].astype('f8')*(1-fx)+a[y0,x1].astype('f8')*fx)*(1-fy)+(a[y1,x0].astype('f8')*(1-fx)+a[y1,x1].astype('f8')*fx)*fy

def nearest(a,b,lon,lat):
 h,w=a.shape[:2];x=np.clip(int((lon-b['west'])/(b['east']-b['west'])*w),0,w-1);y=np.clip(int((b['north']-lat)/(b['north']-b['south'])*h),0,h-1);return np.asarray(a[y,x]).tolist()
def main():
 m=json.loads((BASE/'landscape.json').read_text());upload=json.loads((BASE/'upload/upload.json').read_text());domains={}
 for name in ['context','detail']:
  fine=name=='detail';b=m['core_bounds'] if fine else m['bounds'];wh=(m['height_detail_width'],m['height_detail_height']) if fine else (m['height_width'],m['height_height']);path=m['height_detail_path'] if fine else m['height_path'];height=np.memmap(BASE/path,dtype='<f4',mode='r',shape=wh[::-1]);cw,ch=(m['detail_class_width'],m['detail_class_height']) if fine else (m['class_width'],m['class_height']);cp=m['detail_class_path'] if fine else m['class_path'];wp=m['detail_surface_weights_path'] if fine else m['surface_weights_path'];classes=np.memmap(BASE/cp,dtype='u1',mode='r',shape=(ch,cw));weights=np.memmap(BASE/wp,dtype='u1',mode='r',shape=(ch,cw,4));sd=upload['domains'][name]['water_distance'];sw,sh=sd['policy']['width'],sd['policy']['height'];packed=np.memmap(BASE/sd['payload']['path'],dtype='u1',mode='r',shape=(sh,sw,2));distance=(packed[:,:,0].astype('f4')*256+packed[:,:,1])*.125-4096;domains[name]=(b,height,classes,weights,distance)
 records=[]
 for lon,lat in [(-10.999,26),(45.999,26),(-10.999,32),(45.999,32),(45.99,32),(-11,26),(46,26)]:
  rec={'lon':lon,'lat':lat,'domains':{}}
  for name,(b,z,c,w,sdf) in domains.items():
   eps=50.;dx=(float(bilinear(z,b,lon+eps/SX,lat))-float(bilinear(z,b,lon-eps/SX,lat)))/(2*eps);dz=(float(bilinear(z,b,lon,lat-eps/SY))-float(bilinear(z,b,lon,lat+eps/SY)))/(2*eps);normal=np.array([-dx,1,-dz]);normal/=np.linalg.norm(normal);rec['domains'][name]={'height_m':float(bilinear(z,b,lon,lat)),'normal_epsilon_projected_m':eps,'interpolated_normal':normal.tolist(),'gradient_dx_dz': [dx,dz],'class_nearest':nearest(c,b,lon,lat),'rgba_nearest':nearest(w,b,lon,lat),'rgba_bilinear':bilinear(w,b,lon,lat).tolist(),'sdf_projected_m':float(bilinear(sdf,b,lon,lat))}
  a,b=rec['domains']['context'],rec['domains']['detail'];rec['difference']={'height_m':a['height_m']-b['height_m'],'normal_angle_degrees':math.degrees(math.acos(float(np.clip(np.dot(a['interpolated_normal'],b['interpolated_normal']),-1,1)))),'sdf_m':a['sdf_projected_m']-b['sdf_projected_m']};records.append(rec)
 p=ROOT/'runs/kit1-gamegraphics-v2-2026-10-25/data-v2/seam-before.json';p.write_text(json.dumps({'reference':'frozen gameworld-v1 same-coordinate raw domain samplers, before correction','records':records},indent=2)+'\n');print(json.dumps(records,indent=2))
if __name__=='__main__':main()
