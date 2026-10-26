"""Read-only canonical-c2-domains-v2 sampling for offline display derivation.

Continuous fields use product smootherstep C2. Physical water is determined by
composed SDF; associated roles remain nearest-neighbour discrete codes.
"""
import hashlib
import json
import math
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def smoother(t):
    t = np.clip(t, 0., 1.)
    return t*t*t*(t*(6*t-15)+10)

def transition_weight(x, z, transition):
    a = np.asarray(transition['outer_world_min']); b = a + transition['outer_world_size']
    c = np.asarray(transition['inner_world_min']); d = c + transition['inner_world_size']
    return smoother((x-a[0])/(c[0]-a[0]))*smoother((b[0]-x)/(b[0]-d[0]))*smoother((z-a[1])/(c[1]-a[1]))*smoother((b[1]-z)/(b[1]-d[1]))

def sample(array, x, z, origin, size, nearest=False):
    h,w = array.shape[:2]
    u,v = np.broadcast_arrays((np.asarray(x)-origin[0])/size[0]*w-.5, (np.asarray(z)-origin[1])/size[1]*h-.5)
    u=np.clip(u,0,w-1); v=np.clip(v,0,h-1)
    if nearest:
        return array[np.minimum(np.floor(v+.5).astype(int),h-1),np.minimum(np.floor(u+.5).astype(int),w-1)]
    ix=u.astype(int); iy=v.astype(int); fx=u-ix; fy=v-iy
    if array.ndim==3: fx=fx[...,None]; fy=fy[...,None]
    return (array[iy,ix].astype('f8')*(1-fx)+array[iy,np.minimum(ix+1,w-1)].astype('f8')*fx)*(1-fy)+(array[np.minimum(iy+1,h-1),ix].astype('f8')*(1-fx)+array[np.minimum(iy+1,h-1),np.minimum(ix+1,w-1)].astype('f8')*fx)*fy

class CanonicalV2Sampler:
    def __init__(self, manifest):
        self.path=Path(manifest); self.m=json.loads(self.path.read_text())
        if self.m.get('required_sampling_contract') != 'canonical-c2-domains-v2': raise ValueError('unsupported canonical sampling contract')
        self.checked=[]
        for entry in self.m['assets'].values():
            path=self.path.parent/entry['path']
            if path.stat().st_size != entry['bytes'] or sha(path)!=entry['sha256']: raise ValueError('source asset mismatch: '+str(path))
            self.checked.append(entry)
        self.K=math.pi/180*6371008.8*.001; self.CX=self.K*math.cos(math.radians(41))
        self.context_height=self.top_texture('height_path','height_width','height_height','<f4')
        self.fine_height=self.top_texture('height_detail_path','height_detail_width','height_detail_height','<f4')
        self.context_rect=self.rect(self.m['bounds']); self.fine_rect=self.rect(self.m['height_detail_bounds'])
        self.wd=json.loads((self.path.parent/self.m['water_distance_manifest_path']).read_text())
        self.domains={}
        for name in ['context','fine','local']:
            d=self.wd['domains'][name]; shape=(d['height'],d['width'])
            self.domains[name]={'definition':d,'distance':np.memmap(ROOT/d['distance']['path'],dtype='u1',mode='r',shape=(*shape,2)), 'role':np.memmap(ROOT/d['associated_role']['path'],dtype='u1',mode='r',shape=shape)}
        self.rgba={
            'context':self.top_texture('surface_weights_path','surface_weights_width','surface_weights_height','u1',4),
            'fine':self.top_texture('detail_surface_weights_path','detail_surface_weights_width','detail_surface_weights_height','u1',4),
        }
        d=self.domains['local']['definition']; self.rgba['local']=np.memmap(ROOT/d['surface_weights']['path'],dtype='u1',mode='r',shape=(d['height'],d['width'],4))
    def rect(self,b): return (np.array([(b['west']-19)*self.CX,(41-b['north'])*self.K]),np.array([(b['east']-b['west'])*self.CX,(b['north']-b['south'])*self.K]))
    def top_texture(self,path,w,h,dtype,channels=None):
        shape=(self.m[h],self.m[w]); shape=(*shape,channels) if channels else shape
        return np.memmap(self.path.parent/self.m[path],dtype=dtype,mode='r',shape=shape)
    def weights(self,x,z): return transition_weight(x,z,self.m['domain_transition']),transition_weight(x,z,self.m['local_domain_transition'])
    def raw_height(self,x,z):
        w,_=self.weights(x,z)
        return sample(self.context_height,x,z,*self.context_rect)*(1-w)+sample(self.fine_height,x,z,*self.fine_rect)*w
    def fields(self,x,z,diagnostics=False):
        w,localw=self.weights(x,z); values=[]; roles=[]
        for name in ['context','fine','local']:
            d=self.domains[name]; r=d['definition']; rg=sample(d['distance'],x,z,r['world_min'],r['world_size'])
            values.append((rg[...,0]*256+rg[...,1])*.125-4096)
            roles.append(sample(d['role'],x,z,r['world_min'],r['world_size'],True))
        phi=values[0]*(1-w)+values[1]*w; phi=phi*(1-localw)+values[2]*localw
        role=np.where(w>0,roles[1],roles[0]); role=np.where(localw>0,roles[2],role)
        final=np.where(phi>0,role,0).astype('u1')
        if diagnostics:
            return phi,final,{'context_fine_overlap_wet_role_disagreements':int(np.count_nonzero((w>0)&(w<1)&(phi>0)&(roles[0]!=roles[1]))),'parent_local_overlap_wet_role_disagreements':int(np.count_nonzero((localw>0)&(localw<1)&(phi>0)&(np.where(w>0,roles[1],roles[0])!=roles[2]))),'associated_roles':[r.tolist() if r.ndim==0 else r for r in roles]}
        return phi,final
    def water(self,x,z): return self.fields(x,z)[1]
    def height(self,x,z): return np.where(self.water(x,z)==1,0,self.raw_height(x,z))
    def surface_weights(self,x,z):
        w,lw=self.weights(x,z)
        cr=self.rect(self.m['surface_weights_bounds']); fr=self.rect(self.m['detail_surface_weights_bounds']); d=self.domains['local']['definition']
        parent=sample(self.rgba['context'],x,z,*cr)*(1-w[...,None])+sample(self.rgba['fine'],x,z,*fr)*w[...,None]
        return parent*(1-lw[...,None])+sample(self.rgba['local'],x,z,d['world_min'],d['world_size'])*lw[...,None]
