#!/opt/anaconda3/bin/python
"""Source samples -> adaptive canonical game terrain, semantic zones and forest groups.
Run with existing Anaconda numpy/scipy. No installers and no render/GPU process.
A reconstructed height texture encodes the reduced TIN, never unmodified DEM.
"""
import argparse,hashlib,json,math,pathlib,time
import numpy as np
from scipy.spatial import Delaunay
from scipy.interpolate import LinearNDInterpolator
from scipy import ndimage
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v1';RAW=OUT/'source-observations';PAY=OUT/'payload';PAY.mkdir(exist_ok=True)
POLICY_PATH=next((OUT/x for x in ['model-world-policy-v3.json','model-world-policy-v2.json','model-world-policy.json'] if (OUT/x).exists()));POLICY=json.loads(POLICY_PATH.read_text());REV='gameworld-v1';R=6371008.8

def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def save(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_suffix(p.suffix+'.tmp');tmp.write_text(json.dumps(d,indent=2)+'\n');tmp.replace(p)
def write(name,a):
 p=PAY/name;tmp=p.with_suffix(p.suffix+'.tmp');a.tofile(tmp);tmp.replace(p);return ref(p)
def proj(lon,lat):return ((np.asarray(lon)-19)*math.pi/180*R*math.cos(math.radians(41))*.001,(41-np.asarray(lat))*math.pi/180*R*.001)
def bbox_dict(b):return dict(zip(['west','south','east','north'],b))
def input_meta():return json.loads((OUT/'source-observations.json').read_text())
def samples(domain):
 d=input_meta()['domains'][domain];w,h=d['height_dimensions'];z=np.memmap(ROOT/d['height']['path'],dtype='<f4',mode='r',shape=(h,w));return d,z

def tin_block(z,b,ix,iy,w,h,name):
 """Retained input-cell centers form exact planar coordinates; no height amplification.
 Shared boundaries retain every source sample. Adaptive residual loop checks every
 input source center, protecting all max/min sign-change crest/trough candidates.
 """
 hh,ww=z.shape;yy,xx=np.indices(z.shape);points=np.c_[xx.ravel(),yy.ravel()]
 initial=POLICY['terrain']['initial_spacing_cells'];sel=np.zeros(z.shape,bool);sel[::initial,::initial]=True;sel[0,:]=sel[-1,:]=True;sel[:,0]=sel[:,-1]=True
 # Directional crest/trough along E-W OR N-S, significant local relief against5cell mean.
 mean=ndimage.uniform_filter(z.astype('f8'),size=5,mode='nearest');prom=np.abs(z-mean)
 dx0=z[:,1:-1]-z[:,:-2];dx1=z[:,1:-1]-z[:,2:];dy0=z[1:-1]-z[:-2];dy1=z[1:-1]-z[2:]
 features=np.zeros(z.shape,bool);features[:,1:-1]|=(dx0*dx1>0)&(np.abs(dx0)+np.abs(dx1)>20);features[1:-1]|=(dy0*dy1>0)&(np.abs(dy0)+np.abs(dy1)>20)
 features&=prom>=POLICY['terrain']['peak_prominence_lock_m'];sel|=features
 named=[]
 if name.startswith('core'):
  protection=json.loads((ROOT/'data/protection-rules.json').read_text())
  for ai,(alon,alat) in enumerate(protection['ridges']['anchors']):
   ax=int(round((alon-b[0])/(b[2]-b[0])*w-.5));ay=int(round((b[3]-alat)/(b[3]-b[1])*h-.5))
   if ix<=ax<ix+ww and iy<=ay<iy+hh:sel[ay-iy,ax-ix]=True;named.append((ai,ay-iy,ax-ix))
 budget=POLICY['terrain']['vertical_error_budget_m'];bin_size=POLICY['terrain']['refinement_bin_cells'];passes=0
 for passes in range(POLICY['terrain']['max_refine_passes']):
  inds=np.flatnonzero(sel);tri=Delaunay(points[inds]);interp=LinearNDInterpolator(tri,z.ravel()[inds],fill_value=np.nan);reconstructed=np.asarray(interp(points)).reshape(z.shape);errors=np.abs(reconstructed-z);maximum=float(np.max(errors))
  if not np.isfinite(maximum):raise RuntimeError('TIN uncovered source sample')
  if maximum<=budget:break
  # After four sparse refinements insert all violating source samples. Budget is unchanged.
  if passes>=4:
   sel|=errors>budget
   continue
  # Deterministic maximum-error insertion per source8x8bin; stable across reruns.
  for by in range(0,hh,bin_size):
   for bx in range(0,ww,bin_size):
    win=errors[by:by+bin_size,bx:bx+bin_size]
    if win.max()>budget:
     oy,ox=np.unravel_index(np.argmax(win),win.shape);sel[by+oy,bx+ox]=True
 else:raise RuntimeError(f'{name}: cannot meet prebound budget {maximum}')
 lon=b[0]+(ix+points[inds,0]+.5)*(b[2]-b[0])/w;lat=b[3]-(iy+points[inds,1]+.5)*(b[3]-b[1])/h;x,zcoord=proj(lon,lat);verts=np.c_[x,z.ravel()[inds]*.001,zcoord].astype('<f4');idx=tri.simplices.astype('<u4')
 # Winding produces upward Y normals in east/south coordinate system.
 veca=verts[idx[:,1]]-verts[idx[:,0]];vecb=verts[idx[:,2]]-verts[idx[:,0]];flip=np.cross(veca,vecb)[:,1]<0;idx[flip]=idx[flip][:,[0,2,1]]
 vp=PAY/'blocks'/(name+'.vertices.f32');ip=PAY/'blocks'/(name+'.indices.u32');vp.parent.mkdir(exist_ok=True);verts.tofile(vp);idx.tofile(ip)
 # Coordinates below are source-grid identities and source-height protected vertices.
 fid=np.flatnonzero(features);fy,fx=np.unravel_index(fid,z.shape)
 feature_records=[dict(id=f'{name}:landform:{int(y)}:{int(x)}',kind='ridge' if float(z[y,x])>float(mean[y,x]) else 'valley',source_sample=[int(iy+y),int(ix+x)],source_height_m=float(z[y,x]),retained_vertex_index=int(np.searchsorted(inds,int(y*ww+x)))) for y,x in zip(fy,fx)]
 for ai,ay,ax in named:feature_records.append(dict(id=f'massif-anchor:{ai}',kind='ridge_anchor',source_sample=[int(iy+ay),int(ix+ax)],source_height_m=float(z[ay,ax]),retained_vertex_index=int(np.searchsorted(inds,int(ay*ww+ax)))))
 record=dict(id=name,domain='core' if name.startswith('core') else 'context',source_window=[ix,iy,ww,hh],model_bounds=[float(verts[:,0].min()),float(verts[:,2].min()),float(verts[:,0].max()),float(verts[:,2].max())],height_min_source_m=float(z.min()),height_max_source_m=float(z.max()),vertices=ref(vp),indices=ref(ip),vertex_count=len(verts),triangle_count=len(idx),source_sample_count=z.size,max_vertical_residual_source_m=maximum,refine_passes=passes+1,protected_landform_count=len(feature_records),shared_boundary_rule='all input source centers retained; block bounds overlap by1source sample',geometry_status='canonical reduced model, not renderLOD',vertices_path=str(vp.relative_to(OUT)),indices_path=str(ip.relative_to(OUT)),bounds={'west':float(lon.min()),'south':float(lat.min()),'east':float(lon.max()),'north':float(lat.max())},world_min=[float(verts[:,0].min()),float(verts[:,2].min())],world_size=[float(np.ptp(verts[:,0])),float(np.ptp(verts[:,2]))])
 return reconstructed.astype('<f4'),record,feature_records

def terrain(domain,only_style=False,refresh_protected=False):
 d,src=samples(domain);h,w=src.shape;b=d['bounds'];bs=POLICY['terrain']['block_cells'];model_path=PAY/(domain+'-model-height.f32');model=np.memmap(model_path,dtype='<f4',mode='w+' if not model_path.exists() else 'r+',shape=(h,w));records=[];features=[]
 # Styleproof block first, same whole-region deterministic recipe. No special geometry.
 xs=list(range(0,w-1,bs));ys=list(range(0,h-1,bs));order=[(ix,iy) for iy in ys for ix in xs]
 if domain=='core':
  lon,lat=POLICY['style_proof']['lon'],POLICY['style_proof']['lat'];px=int((lon-b[0])/(b[2]-b[0])*w);py=int((b[3]-lat)/(b[3]-b[1])*h);style=(px//bs*bs,py//bs*bs);order.remove(style);order.insert(0,style)
 if only_style:order=order[:1]
 checkpoint=OUT/(domain+'-terrain-checkpoint.json');previous={}
 if checkpoint.exists():previous={x['id']:x for x in json.loads(checkpoint.read_text())['blocks']}
 for k,(ix,iy) in enumerate(order):
  ix1=min(w,ix+bs+1);iy1=min(h,iy+bs+1);name=f'{domain}-{iy:05d}-{ix:05d}';old=previous.get(name)
  force=False
  if refresh_protected and domain=='core':
   for alon,alat in json.loads((ROOT/'data/protection-rules.json').read_text())['ridges']['anchors']:
    ax=int(round((alon-b[0])/(b[2]-b[0])*w-.5));ay=int(round((b[3]-alat)/(b[3]-b[1])*h-.5))
    if ix<=ax<ix1 and iy<=ay<iy1:force=True
  if old and (ROOT/old['vertices']['path']).exists() and not force:records.append(old);continue
  zz=np.array(src[iy:iy1,ix:ix1],dtype='f8');reconstructed,rec,feats=tin_block(zz,b,ix,iy,w,h,name);model[iy:iy1,ix:ix1]=reconstructed;records.append(rec);features.extend(feats)
  # Perblock feature lists avoid huge in-memory inventory and allow resume.
  save(PAY/'blocks'/(name+'.features.json'),dict(block_id=name,features=feats));rec['feature_inventory']=ref(PAY/'blocks'/(name+'.features.json'))
  model.flush()
  if k%10==0 or only_style or k==len(order)-1:
   save(checkpoint,dict(revision=REV,domain=domain,status='partial' if k<len(order)-1 or only_style else 'complete',expected_blocks=len(xs)*len(ys),blocks=records));print('terrain',domain,k+1,'/',len(order),'verts',rec['vertex_count'],'error',rec['max_vertical_residual_source_m'],flush=True)
 save(OUT/(domain+'-mesh-manifest.json'),dict(schema_version='gameworld-mesh-v1',revision=REV,status='partial' if only_style else 'implementiert',canonical_geometry='adaptive source-vertex TIN',reconstruction_texture=ref(model_path),bounds=bbox_dict(b),height_dimensions=[w,h],vertex_stride_bytes=12,vertex_encoding='Float32LE model XYZ; shared common scale0.001, signed height',index_encoding='UInt32LE triangle triples upward winding',blocks=records,source=ref(RAW/(domain+'-height.f32')),policy=ref(OUT/'model-world-policy.json'),protected_features='perblock feature inventories, exact source samples and retainedvertexmapping',total_source_samples=sum(x['source_sample_count'] for x in records),total_retained_vertices=sum(x['vertex_count'] for x in records),max_vertical_residual_source_m=max(x['max_vertical_residual_source_m'] for x in records)))

def material_zones(domain):
 d=input_meta()['domains'][domain];w,h=d['cover_dimensions'];b=d['bounds'];raw=np.memmap(ROOT/d['cover']['path'],dtype='u1',mode='r',shape=(h,w));water=np.memmap(ROOT/d['water']['path'],dtype='u1',mode='r',shape=(h,w));lookup=np.zeros(256,dtype='u1')
 for code,mat in [(10,2),(20,3),(30,1),(40,1),(50,1),(60,4),(70,6),(80,8),(90,1),(95,2),(100,3)]:lookup[code]=mat
 mats=lookup[raw].copy();mats[water>0]=8;before=mats.copy();omissions=[];groups=[];structure=ndimage.generate_binary_structure(2,1)
 # Own graphic rockzone from supported barecover plus real elevation/slope, not a geology survey.
 hd,hz=samples(domain);resized=ndimage.zoom(np.asarray(hz),[h/hz.shape[0],w/hz.shape[1]],order=1,prefilter=False)
 sx=(b[2]-b[0])/w*math.pi/180*R*math.cos(math.radians(41));sy=(b[3]-b[1])/h*math.pi/180*R
 gy,gx=np.gradient(resized,sy,sx);slope=np.hypot(gx,gy);rock=((raw==60)&(resized>700)&(slope>.16))|((resized>2500)&(slope>.30)&(water==0));mats[rock]=5
 del resized,gx,gy,slope,rock
 # Aggregate tiny zones against dominant touching neighbour, preserving all water.
 for code in [1,2,3,4,6]:
  labels,count=ndimage.label(mats==code,structure);sizes=np.bincount(labels.ravel());small=np.flatnonzero((sizes<POLICY['materials']['component_min_cells'])&(sizes>0));small=small[small!=0]
  slices=ndimage.find_objects(labels)
  for lab in small:
   sy,sx=slices[lab-1];ys=slice(max(0,sy.start-1),min(h,sy.stop+1));xs=slice(max(0,sx.start-1),min(w,sx.stop+1));window=mats[ys,xs];region=labels[ys,xs]==lab;ly,lx=np.nonzero(region);y=ly+ys.start;x=lx+xs.start;adj=window[ndimage.binary_dilation(region)&~region];adj=adj[(adj!=8)&(adj!=0)&(adj!=code)]
   if not adj.size:continue
   # Existing regression forest anchor component alwaysprotected.
   ax=int((8.9916667-b[0])/(b[2]-b[0])*w);ay=int((b[3]-46.0083333)/(b[3]-b[1])*h)
   if code==2 and labels[ay,ax]==lab:continue
   target=int(np.bincount(adj,minlength=9).argmax())
   if target==2 and np.any((raw[y,x]==40)|(raw[y,x]==50)|(raw[y,x]==0)):continue
   mats[y,x]=target;omissions.append(dict(id=f'material-sourcepatch:{code}:{lab}',source_class_codes=np.unique(raw[y,x]).tolist(),source_pixel_count=len(y),source_bbox_cells=[int(x.min()),int(y.min()),int(x.max()+1),int(y.max()+1)],rule='min4connectedcovercells-dominant-neighbour',represented_by_material=target))
  print('zoneclass',code,'components',count,'small',len(small),flush=True)
 # Natural shoreline zone is derived from actual distance to physical water, nevera paintedmap frame.
 pixel_x=(b[2]-b[0])/w*math.pi/180*R*math.cos(math.radians(41));pixel_y=(b[3]-b[1])/h*math.pi/180*R
 shore_dist=ndimage.distance_transform_edt(water==0,sampling=(pixel_y,pixel_x));weights=np.zeros((h,w,4),dtype='u1')
 # Continuous distance transitions within one sourcecover cell. Mask prevents class extension into sea.
 for channel,mask in [(0,mats==2),(1,mats==5),(2,mats==4)]:
  inside=ndimage.distance_transform_edt(mask);outside=ndimage.distance_transform_edt(~mask);weight=np.clip(.5+(inside-outside)/2,0,1);weight[water>0]=0;weights[:,:,channel]=np.rint(weight*255).astype('u1')
 weights[:,:,3]=np.rint(np.clip(1-shore_dist/900,0,1)*255).astype('u1');weights[water>0,3]=255;mats[(shore_dist<450)&(water==0)&(mats!=2)]=7
 # Forestgroups: connected semantic zones, stable IDs and representative cell-scale densityfield.
 forest=mats==2;labels,count=ndimage.label(forest,structure);distance=ndimage.distance_transform_edt(forest,sampling=(pixel_y,pixel_x));distance=np.minimum(distance,4000).astype('<f4');slices=ndimage.find_objects(labels);sizes=np.bincount(labels.ravel())
 for i,sl in enumerate(slices,1):
  if sl is None:continue
  yy,xx=sl;lon0=b[0]+xx.start/w*(b[2]-b[0]);lon1=b[0]+xx.stop/w*(b[2]-b[0]);lat0=b[3]-yy.stop/h*(b[3]-b[1]);lat1=b[3]-yy.start/h*(b[3]-b[1]);cx,cz=proj((lon0+lon1)/2,(lat0+lat1)/2)
  groups.append(dict(group_id=f'forest-v1:{i}',source_bbox=[lon0,lat0,lon1,lat1],source_cell_count=int(sizes[i]),source_class_codes=[10,95],material_code=2,seed=(117180+i*2654435761)&0xffffffff,model_center=[float(cx),float(cz)],edge_density=.42,core_density=.88,density_transition_source_m=900,representation='source-supported covergroup; individualcrownpositions procedural stable representatives, notsurveyed trees'))
 generalized=raw.copy();genlookup={0:0,1:30,2:10,3:20,4:60,5:60,6:70,7:30,8:80}
 for code,value in genlookup.items():generalized[mats==code]=value
 uncertainty=((raw==40)|(raw==50)|(raw==0)).astype('u1');write(domain+'-material.u8',mats);write(domain+'-classes.u8',generalized);write(domain+'-surface-weights.rgba8',weights);write(domain+'-forest-groups.u32',labels.astype('<u4'));write(domain+'-forest-interior.f32',distance);write(domain+'-managed-uncertainty.u8',uncertainty)
 save(OUT/(domain+'-forest-groups.json'),dict(revision=REV,grouping='4-connected semantic sourcecover zones',bounds=bbox_dict(b),dimensions=[w,h],groups=groups,group_labels=ref(PAY/(domain+'-forest-groups.u32')),interior_distance=ref(PAY/(domain+'-forest-interior.f32')),representative_spacing_source_m=20,edge_spacing_source_m=28,core_crown_lobes_per_representative=3,edge_crown_lobes_per_representative=[1,2],representation_revision='forest-grove-v2'))
 save(OUT/(domain+'-material-zones.json'),dict(revision=REV,bounds=bbox_dict(b),dimensions=[w,h],codes=POLICY['materials']['codes'],material=ref(PAY/(domain+'-material.u8')),surface_weights=ref(PAY/(domain+'-surface-weights.rgba8')),weights_channels=['forest','rock','dry','shore'],filter_rule='distancefield one sourcecover-cell support, physical water mask hardconstraint',uncertainty=ref(PAY/(domain+'-managed-uncertainty.u8')),changed_sourcecells=int(np.count_nonzero(before!=mats)),omitted_components=omissions,source=ref(ROOT/d['cover']['path']),policy=ref(POLICY_PATH),managed_forest_guard='Raw40/50/0 patches maynever merge into forest; neutralopen retained',status='implementiert'))
 print('materials done groups',count,'aggregations',len(omissions),flush=True)

def main():
 a=argparse.ArgumentParser();a.add_argument('action',choices=['core','context','materials']);a.add_argument('--style-only',action='store_true');a.add_argument('--refresh-protected',action='store_true');a.add_argument('--domain',default='context',choices=['core','context']);args=a.parse_args()
 if args.action=='materials':material_zones(args.domain)
 else:terrain(args.action,args.style_only,args.refresh_protected)
if __name__=='__main__':main()
