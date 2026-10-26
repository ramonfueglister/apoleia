#!/usr/bin/env python3
"""Build a progressive 256² height/material/water pyramid from existing sources.
Coarse tiles are written first and remain usable while finer tiles are built.
"""
from pathlib import Path
import argparse,json,math,time,shutil
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
class Sources:
 def __init__(self,surface='artifacts/render-data/fixed-source-v2-macro-r1/surface.json'):
  surface=ROOT/surface;self.surface=surface
  self.upload=json.loads((ROOT/'artifacts/render-data/source-v2-upload-r1/upload.json').read_text());self.g=json.loads(surface.read_text());self.arrays={}
  self.height=np.memmap(surface.parent/self.g['height_payload']['path'],dtype=np.uint8,mode='r',shape=(self.g['height'],self.g['width'],2))
 def sample(self,domain,name,x,z,nearest=False):
  d=self.upload['domains'][domain][name];key=(domain,name)
  if key not in self.arrays:self.arrays[key]=np.memmap(ROOT/d['payload']['path'],dtype=np.uint8,mode='r',shape=(d['height'],d['width'],d.get('bytes_per_pixel',d.get('channels',4 if name=='surface_weights' else 1 if name=='associated_role' else 2))))
  return sample(self.arrays[key],x,z,d['world_min'],d['world_size'],nearest)
 def weight(self,name,x,z):
  t=self.upload[name];a=np.array(t['outer_world_min']);b=a+t['outer_world_size'];c=np.array(t['inner_world_min']);e=c+t['inner_world_size']
  w=np.minimum.reduce([(x-a[0])/(c[0]-a[0]),(b[0]-x)/(b[0]-e[0]),(z-a[1])/(c[1]-a[1]),(b[1]-z)/(b[1]-e[1])]);w=np.clip(w,0,1);return w*w*w*(w*(w*6-15)+10)
 def tile(self,origin,span):
  axis=(np.arange(258,dtype=np.float64)-.5)/256*span;x,z=np.meshgrid(origin[0]+axis,origin[1]+axis)
  h=sample(self.height,x,z,self.g['world_min'],self.g['world_size'],False,True)
  height=(h[...,0]*256+h[...,1])*.25-8192
  fine=self.weight('domain_transition',x,z);local=self.weight('local_domain_transition',x,z)
  material=self.sample('context','surface_weights',x,z)*(1-fine[...,None])+self.sample('fine','surface_weights',x,z)*fine[...,None]
  material=material*(1-local[...,None])+self.sample('local','surface_weights',x,z)*local[...,None]
  distances=[];roles=[]
  for domain in ['context','fine','local']:
   d=self.sample(domain,'water_distance',x,z);distances.append((d[...,0]*256+d[...,1])*.125-4096);roles.append(self.sample(domain,'associated_role',x,z,True)[...,0])
  distance=(distances[0]*(1-fine)+distances[1]*fine)*(1-local)+distances[2]*local
  role=roles[0].copy()
  role=np.where((fine>0)&(distances[1]>0)&(roles[1]>0),roles[1],role)
  role=np.where((local>0)&(distances[2]>0)&(roles[2]>0),roles[2],role)
  role=np.where(distance<=0,0,role)
  ch=self.sample('context','height',x,z);fh=self.sample('fine','height',x,z)
  source_h=((ch[...,0]*256+ch[...,1])*.25-8192)*(1-fine)+((fh[...,0]*256+fh[...,1])*.25-8192)*fine
  depth=np.uint8(np.clip(np.rint(np.maximum(-source_h,0)/25),0,255))
  water=packed(distance,.125,-4096,role);water[...,3]=depth
  return packed(height,.25,-8192),np.uint8(np.clip(np.rint(material),0,255)),water
def sample(a,x,z,minimum,size,nearest=False,vertices=False):
 n,m=a.shape[:2];qx=(x-minimum[0])/size[0]*(m-1 if vertices else m)-(0 if vertices else .5);qz=(z-minimum[1])/size[1]*(n-1 if vertices else n)-(0 if vertices else .5)
 if nearest:return a[np.clip(np.rint(qz).astype(int),0,n-1),np.clip(np.rint(qx).astype(int),0,m-1)].astype(np.float32)
 ix=np.floor(qx).astype(int);iz=np.floor(qz).astype(int);fx=(qx-ix)[...,None];fz=(qz-iz)[...,None]
 x0=np.clip(ix,0,m-1);x1=np.clip(ix+1,0,m-1);z0=np.clip(iz,0,n-1);z1=np.clip(iz+1,0,n-1)
 return (a[z0,x0]*(1-fx)+a[z0,x1]*fx)*(1-fz)+(a[z1,x0]*(1-fx)+a[z1,x1]*fx)*fz
def packed(value,scale,offset,role=None):
 code=np.uint16(np.clip(np.rint((value-offset)/scale),0,65535));out=np.zeros(code.shape+(4,),np.uint8);out[...,0]=code>>8;out[...,1]=code&255;out[...,3]=255
 if role is not None:out[...,2]=np.uint8(role)
 return out
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',default='artifacts/render-data/clipmap-tiles-r3');p.add_argument('--max-tiles',type=int,default=0);p.add_argument('--focus',nargs=2,type=float);p.add_argument('--radius-tiles',type=int,default=0);p.add_argument('--surface',default='artifacts/render-data/fixed-source-v2-macro-r1/surface.json');args=p.parse_args()
 source=Sources(args.surface);base=128.;minimum=np.floor(np.array(source.g['world_min'])/base)*base;end=np.array(source.g['world_min'])+source.g['world_size'];counts=np.ceil((end-minimum)/base).astype(int);maxlevel=int(math.ceil(math.log2(max(counts))));out=ROOT/args.output;out.mkdir(parents=True,exist_ok=True)
 manifest={'format':'apoleia-clipmap-tiles-v1','tile_samples':256,'image_size':258,'halo':1,'base_span':base,'origin':minimum.tolist(),'world_min':source.g['world_min'],'world_size':source.g['world_size'],'tile_counts':counts.tolist(),'max_level':maxlevel,'root':f'{maxlevel}/0/0','height_encoding':[.25,-8192],'water_encoding':[.125,-4096],'water_depth_encoding':{'channel':'A','metres_per_code':25,'maximum_metres':6375,'source':'C2 context/fine source height; G render height unchanged'},'source':'existing '+source.surface.parent.name+' and source-v2-upload-r1','fields':['height','material','water']}
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');done=0;started=time.monotonic()
 for level in range(maxlevel,-1,-1):
  span=base*2**level;nx,nz=np.ceil(counts/2**level).astype(int);tiles=[(x,z) for z in range(nz) for x in range(nx)]
  if args.focus and args.radius_tiles:
   center=np.floor((np.array(args.focus)-minimum)/span).astype(int);tiles=[q for q in tiles if max(abs(q[0]-center[0]),abs(q[1]-center[1]))<=args.radius_tiles or level==maxlevel]
  if args.focus:tiles.sort(key=lambda q:(minimum[0]+(q[0]+.5)*span-args.focus[0])**2+(minimum[1]+(q[1]+.5)*span-args.focus[1])**2)
  for x,z in tiles:
   if shutil.disk_usage(out).free<512*1024*1024:raise SystemExit('Stopped: keep 512MiB disk reserve; coarse pyramid remains usable')
   folder=out/str(level)/str(x);folder.mkdir(parents=True,exist_ok=True)
   if not (folder/f'{z}-water.png').exists():
    arrays=source.tile(minimum+np.array([x,z])*span,span)
    for name,array in zip(manifest['fields'],arrays):
     destination=folder/f'{z}-{name}.png';temporary=destination.with_suffix('.tmp');Image.fromarray(array,'RGBA').save(temporary,format='PNG',compress_level=2);temporary.replace(destination)
   done+=1
   if done%10==0 or done==1:print(f'{done} tiles, level {level}, {time.monotonic()-started:.1f}s',flush=True)
   if args.max_tiles and done>=args.max_tiles:return
 (out/'READY').write_text('prioritized region; coarse coverage complete\n' if args.radius_tiles else 'complete\n');print(f'complete {done} tiles {time.monotonic()-started:.1f}s',flush=True)
if __name__=='__main__':main()
