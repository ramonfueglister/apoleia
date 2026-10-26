#!/opt/anaconda3/bin/python
import pathlib,json,hashlib,math,numpy as np
from scipy import ndimage
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v2';PAY=OUT/'payload';R=6371008.8

def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 local=json.loads((OUT/'local-composition.json').read_text());lb=[local['bounds'][k] for k in ['west','south','east','north']];domains={}
 for domain,b,shape in [('context',[-44,18,79,61],(2580,7380)),('fine',[-12,20,47,59],(6144,8192)),('local',lb,(local['height'],local['width']))]:
  h,w=shape;kind=np.memmap(PAY/(domain+'-water.u8'),dtype='u1',mode='r',shape=shape);sx=(b[2]-b[0])/w*math.pi/180*R*math.cos(math.radians(41));sy=(b[3]-b[1])/h*math.pi/180*R;wet=np.asarray(kind)>0;phi=ndimage.distance_transform_edt(wet,sampling=(sy,sx));phi-=ndimage.distance_transform_edt(~wet,sampling=(sy,sx));np.clip(phi,-3000,3000,out=phi);p=PAY/(domain+'-distance.rg8');maximum=0.
  with p.open('wb') as f:
   for y in range(h):
    code=np.rint((phi[y]+4096)*8).astype('u2');maximum=max(maximum,float(np.max(abs(code.astype('f8')*.125-4096-phi[y]))));packed=np.stack([code>>8,code&255],axis=1).astype('u1');f.write(packed.tobytes())
  del phi
  indexes=ndimage.distance_transform_edt(~wet,return_distances=False,return_indices=True);associated=np.asarray(kind)[indexes[0],indexes[1]];associated.astype('u1').tofile(PAY/(domain+'-water-role.u8'));del indexes,associated
  domains[domain]={'bounds':dict(zip(['west','south','east','north'],b)),'width':w,'height':h,'distance':{'path':str(p.relative_to(ROOT)),'sha256':sha(p),'bytes':p.stat().st_size},'associated_role':{'path':str((PAY/(domain+'-water-role.u8')).relative_to(ROOT)),'sha256':sha(PAY/(domain+'-water-role.u8'))},'quantization_max_projected_m':maximum,'sampling_step_projected_m':[sx,sy],'representation':'signeddistance to samecomposedcanonicalgeometry rasterizedatdomainresolution, linearreconstruction; source/modelprecision distinct. Fine/coarse representations sharestaticC2 canonicalsamplingpolicy. AssociatedrolemeaningfulonlyifcomposedSDFpositive; zero/negativeisland.'};print('SDFdone',domain,maximum,flush=True)
 (OUT/'water-distance-manifest.json').write_text(json.dumps({'revision':'gameworld-v2-water-distance','domains':domains,'encoding':'UInt8RGbigbyte:projectedmetres=(R*256+G)*0.125-4096; saturated±3000m','land_water_rule':'SameC2composedSDF<=0land, >0usesdiscrete associatedmarine1/inland2role; neverlerp rolecodes'},indent=2)+'\n')
if __name__=='__main__':main()
