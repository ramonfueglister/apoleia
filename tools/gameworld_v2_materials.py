#!/opt/anaconda3/bin/python
"""Source-bound semantic domains with strict managedguard and consistent expandedfinebounds."""
import pathlib,json,math,hashlib,numpy as np
from scipy import ndimage
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';PAY=OUT/'payload';OLD=ROOT/'data/gameworld-v1';R=6371008.8

def write(name,a):p=PAY/name;a.tofile(p)
def resample_mask(a,shape):
 y=np.clip(((np.arange(shape[0])+.5)/shape[0]*a.shape[0]).astype(int),0,a.shape[0]-1);x=np.clip(((np.arange(shape[1])+.5)/shape[1]*a.shape[1]).astype(int),0,a.shape[1]-1);return a[y[:,None],x[None,:]]
def main():
 summaries={}
 for domain,shape,b in [('context',(2580,7380),[-44,18,79,61]),('fine',(7020,10620),[-12,20,47,59])]:
  h,w=shape
  if domain=='context':
   raw=np.memmap(OLD/'source-observations/context-cover.u8',dtype='u1',mode='r',shape=shape);mats=np.fromfile(OLD/'payload/context-material.u8',dtype='u1').reshape(shape);weights=np.fromfile(OLD/'payload/context-surface-weights.rgba8',dtype='u1').reshape(h,w,4)
  else:
   raw=np.memmap(OUT/'source-observations/fine-cover.u8',dtype='u1',mode='r',shape=shape);lookup=np.zeros(256,dtype='u1')
   for c,mat in [(10,2),(20,3),(30,1),(40,1),(50,1),(60,4),(70,6),(80,8),(90,1),(95,2),(100,3)]:lookup[c]=mat
   mats=lookup[raw];weights=np.zeros((h,w,4),dtype='u1');mats[180:6840,180:10440]=np.memmap(OLD/'payload/core-material.u8',dtype='u1',mode='r',shape=(6660,10260));weights[180:6840,180:10440]=np.memmap(OLD/'payload/core-surface-weights.rgba8',dtype='u1',mode='r',shape=(6660,10260,4));weights[:,:,2][mats==4]=255
  water=np.memmap(PAY/(domain+'-semantic-water.u8'),dtype='u1',mode='r',shape=shape);managed=np.isin(raw,[0,40,50]);before=int(np.count_nonzero(managed&(mats==2)));mats[managed&(mats==2)]=1;mats[water>0]=8
  # OldNE-mask water becoming observedland staysunknown in regionalfallback until the localnative domain supplies it.
  # Class80 permanentwater on coarser physical-land remains known nonvegetatedwatercover, never unknownorforest.
  forest=mats==2;inside=ndimage.distance_transform_edt(forest);outside=ndimage.distance_transform_edt(~forest);weights[:,:,0]=np.rint(np.clip(.5+(inside-outside)/2,0,1)*255).astype('u1');weights[water>0,0]=0;del inside,outside
  sx=(b[2]-b[0])/w*math.pi/180*R*math.cos(math.radians(41));sy=(b[3]-b[1])/h*math.pi/180*R;shore=ndimage.distance_transform_edt(water==0,sampling=(sy,sx));weights[:,:,3]=np.rint(np.clip(1-shore/900,0,1)*255).astype('u1');weights[water>0,3]=255;del shore
  classes=np.zeros(shape,dtype='u1')
  for code,value in [(0,0),(1,30),(2,10),(3,20),(4,60),(5,60),(6,70),(7,30),(8,80)]:classes[mats==code]=value
  write(domain+'-classes.u8',classes);write(domain+'-material.u8',mats);write(domain+'-surface-weights.rgba8',weights);write(domain+'-managed-uncertainty.u8',managed.astype('u1'));summaries[domain]={'bounds':b,'width':w,'height':h,'managed_forest_before':before,'managed_forest_after':int(np.count_nonzero(managed&(mats==2))),'unknown_land_pixels_regionalfallback':int(np.count_nonzero((classes==0)&(water==0)))}
  if domain=='fine':
   labels,n=ndimage.label(forest);write('fine-forest-groups.u32',labels.astype('<u4'));distance=np.minimum(ndimage.distance_transform_edt(forest,sampling=(sy,sx)),4000).astype('<f4');write('fine-forest-interior.f32',distance);summaries[domain]['forest_groups']=n
  print('semantics',domain,summaries[domain],flush=True)
 (OUT/'semantic-composition-checks.json').write_text(json.dumps({'revision':'gameworld-v2-semantics','domains':summaries,'local_native_override':'localclasses/weights/groupIDnamespace1000000+ atsamerealcoordinates; staticatallzooms','source_rules':'Managed40/50/unknown0neverforest. ESAclass80outsidecoarserphysicalwater remainsknownnonvegetatedwatercover withuncertainty, not inventedforest; canonicalwatergeometry authoritative. Exactsame-coordinate semanticwater mask preventsresolutionalias frombecomingfalseNoData.'},indent=2)+'\n')
if __name__=='__main__':main()
