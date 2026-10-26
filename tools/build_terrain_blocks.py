#!/usr/bin/env python3
"""Build a complete, individually verified terrain quadtree from the bound fixed atlas.

Own derived representation; no synthetic geography. Grid/diagonals/anchor stars match
fixed_display_surface.gd. Source atlas is memory mapped offline, never runtime resident.
"""
import argparse, hashlib, json, math, pathlib, struct
import numpy as np
from terrain_mesh_topology import node_existing_edges, topology
ROOT = pathlib.Path(__file__).resolve().parents[1]

def sha(p):
    with pathlib.Path(p).open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def enc(v): return json.dumps(v,separators=(',',':'),ensure_ascii=False).encode()
def atomic_json(p,v):
    t=p.with_suffix(p.suffix+'.tmp');t.write_bytes(enc(v)+b'\n');t.replace(p)

def build(surface_path, out, cells=128, upload_path=None, material_cap=256, coast_path=None):
    if out.exists(): raise RuntimeError('new output directory required; never mutate a frozen tree')
    m=json.loads(surface_path.read_text()); base=surface_path.parent
    for k in ('height_payload','policy','chunks'):
        if sha(base/m[k]['path'])!=m[k]['sha256']:raise ValueError('invalid atlas '+k)
    w,h=m['width'],m['height']; raw=np.memmap(base/m['height_payload']['path'],dtype='>u2',mode='r',shape=(h,w))
    origin=np.array(m['world_min']); spacing=np.array(m['world_size'])/[w-1,h-1]
    anchors=m.get('anchors',[]); anchors=[dict(a,grid=(np.array([a['world_x'],a['world_z']])-origin)/spacing) for a in anchors]
    depth=max(0,math.ceil(math.log2(max(w-1,h-1)/cells))); root_span=cells*2**depth
    out.mkdir(parents=True);(out/'blocks').mkdir(); blocks={}; payload_bytes=0
    upload=json.loads(upload_path.read_text()) if upload_path else None
    coast=json.loads(coast_path.read_text()) if coast_path else None
    bpp={'coast_distance':2,'height':2,'water_distance':2,'associated_role':1,'classes':1,'surface_weights':4,'forest_groups':4,'forest_interior':4,'forest_membership':1}
    mapped={}
    source_domains={dn:dict(upload['domains'][dn]) for dn in ('context','fine','local')} if upload else {}
    if coast:source_domains['display']={'coast_distance':dict(coast,payload=coast['payload'])}
    if upload:
        checked=set()
        for dn,domain in source_domains.items():
            for fn,d in domain.items():
                if fn not in bpp:continue
                payload=d['payload'];path=ROOT/payload['path']
                if payload['path'] not in checked:
                    if path.stat().st_size!=payload['bytes'] or sha(path)!=payload['sha256']:raise ValueError('invalid source backing store: '+str(path))
                    checked.add(payload['path'])
                mapped[dn,fn]=np.memmap(ROOT/d['payload']['path'],dtype='u1',mode='r',shape=(d['height'],d['width'],bpp[fn]))
    def source_windows(world_begin,world_end,leaf):
        result={}
        if not upload:return result
        for dn,domain in source_domains.items():
            result[dn]={}
            for fn,d in domain.items():
                if fn not in bpp:continue
                a=np.array(d['world_min']);size=np.array(d['world_size']);dim=np.array([d['width'],d['height']]);pixel=size/dim
                radius=.6 if fn=='surface_weights' else 0.
                low=np.floor((world_begin-radius-a)/pixel-.5).astype(int)-2;high=np.ceil((world_end+radius-a)/pixel-.5).astype(int)+2
                intersects=np.all(world_end+radius>=a) and np.all(world_begin-radius<=a+size)
                if not intersects:low=np.clip(low,0,dim-1);high=low+1
                else:low=np.maximum(low,-2);high=np.minimum(high,dim+1)
                step=1
                if not leaf:
                    while np.max(np.ceil((high-low)/step)+1)>material_cap:step*=2
                low=np.floor_divide(low,step)*step;high=np.ceil(high/step).astype(int)*step
                xs=np.arange(low[0],high[0]+1,step);zs=np.arange(low[1],high[1]+1,step)
                tile=mapped[dn,fn][np.ix_(np.clip(zs,0,dim[1]-1),np.clip(xs,0,dim[0]-1))];rawbytes=tile.tobytes()
                result[dn][fn]={'source':d['payload'],'source_width':int(dim[0]),'source_height':int(dim[1]),'bpp':bpp[fn],'sample_begin':low.tolist(),'sample_step':step,'width':len(xs),'height':len(zs),'bytes':len(rawbytes),'sha256':hashlib.sha256(rawbytes).hexdigest(),'texture_world_min':(a+(low+.5-step*.5)*pixel).tolist(),'texture_world_size':(np.array([len(xs),len(zs)])*step*pixel).tolist(),'semantic_world_min':d['world_min'],'semantic_world_size':d['world_size'],'mip_level':int(math.log2(step)),'halo':2,'query_radius_world':radius,'maximum_color_mip':0,'sampling':'original texel centers; stride fallback; nearest discrete fields; unchanged source bytes at mip0'}
        return result
    def must_split_local(begin,end,level):
        if not upload or level<depth:return level<depth
        loc=upload['domains']['local']['surface_weights'];a=np.array(loc['world_min']);b=a+loc['world_size'];wb=origin+begin*spacing;we=origin+end*spacing
        return np.all(we+.6>a) and np.all(wb-.6<b) and np.max(end-begin)>2

    def height(x,z):return (raw[np.clip(z,0,h-1),np.clip(x,0,w-1)].astype('f8')*.25-8192)*.001
    def normal(x,z):
        dx=(height(x+1,z)-height(x-1,z))/(2*spacing[0]);dz=(height(x,z+1)-height(x,z-1))/(2*spacing[1])
        v=np.stack([-dx,np.ones_like(dx),-dz],axis=-1);return v/np.linalg.norm(v,axis=-1,keepdims=True)
    def bary(p,a,b,c):
        uv=np.array([[b[0]-a[0],c[0]-a[0]],[b[2]-a[2],c[2]-a[2]]]);d=np.linalg.det(uv)
        if abs(d)<1e-14:return None
        beta,gamma=np.linalg.solve(uv,p-a[[0,2]])
        if beta>=-1e-6 and gamma>=-1e-6 and beta+gamma<=1.000001:return a[1]+beta*(b[1]-a[1])+gamma*(c[1]-a[1])
        return None
    def sample_parent(points, begin, end, stride):
        q=(points[:,[0,2]]-origin)/spacing;lo=begin+np.floor((q-begin)/stride).astype(int)*stride;lo=np.minimum(lo,end-1);hi=np.minimum(lo+stride,end)
        fx=(q[:,0]-lo[:,0])/(hi[:,0]-lo[:,0]);fz=(q[:,1]-lo[:,1])/(hi[:,1]-lo[:,1]);a=height(lo[:,0],lo[:,1]);b=height(hi[:,0],lo[:,1]);c=height(lo[:,0],hi[:,1]);d=height(hi[:,0],hi[:,1]);v=np.where(fx+fz<1,a+(b-a)*fx+(c-a)*fz,d+(c-d)*(1-fx)+(b-d)*(1-fz))
        for anchor in anchors:
            ac=np.floor(anchor['grid']).astype(int);mask=(lo[:,0]<=ac[0])&(hi[:,0]>ac[0])&(lo[:,1]<=ac[1])&(hi[:,1]>ac[1]);indices=np.flatnonzero(mask)
            for i in indices:
                corners=[]
                for x,z in [(lo[i,0],lo[i,1]),(hi[i,0],lo[i,1]),(hi[i,0],hi[i,1]),(lo[i,0],hi[i,1])]:corners.append(np.array([origin[0]+x*spacing[0],height(x,z),origin[1]+z*spacing[1]]))
                peak=np.array([anchor['world_x'],anchor['height_source_m']*.001,anchor['world_z']])
                for k in range(4):
                    value=bary(points[i,[0,2]],corners[k],corners[(k+1)%4],peak)
                    if value is not None:v[i]=value;break
        return v
    def node(level,x,z,parent=None):
        nonlocal payload_bytes
        span=max(1,root_span//2**level);begin=np.array([x*span,z*span]);end=np.minimum(begin+span,[w-1,h-1])
        if np.any(begin>=end):return None
        stride=max(1,2**(depth-level));xs=np.r_[np.arange(begin[0],end[0],stride),end[0]];zs=np.r_[np.arange(begin[1],end[1],stride),end[1]];xx,zz=np.meshgrid(xs,zs)
        points=np.stack([origin[0]+xx*spacing[0],height(xx,zz),origin[1]+zz*spacing[1]],axis=-1).reshape(-1,3); normals=normal(xx,zz).reshape(-1,3); indices=[]
        stars={}
        for a in anchors:
            ag=np.floor(a['grid']).astype(int)
            if np.all(ag>=begin) and np.all(ag<end):stars[(int((ag[0]-begin[0])//stride),int((ag[1]-begin[1])//stride))]=a
        for iz in range(len(zs)-1):
            for ix in range(len(xs)-1):
                a=iz*len(xs)+ix;b=a+1;c=a+len(xs);d=c+1
                if (ix,iz) in stars:
                    peak=stars[ix,iz];k=len(points);points=np.vstack([points,[peak['world_x'],peak['height_source_m']*.001,peak['world_z']]]);normals=np.vstack([normals,normal(int(peak['grid'][0]),int(peak['grid'][1]))]);indices.extend([a,b,k,b,d,k,d,c,k,c,a,k])
                else:indices.extend([a,b,c,b,d,c])
        unrefined_vertex_count=len(points)
        # Split child faces at the actual parent star rays. Vertex-only endpoint
        # sampling is insufficient where a parent star edge crosses a fine face.
        if parent is not None and anchors:
            pb=np.array(parent['grid_begin']);pe=np.array(parent['grid_end']);ps=parent['stride'];new_indices=list(indices);point_list=points.tolist();normal_list=normals.tolist()
            for anchor in anchors:
                ag=np.floor(anchor['grid']).astype(int)
                if not (np.all(ag>=pb) and np.all(ag<pe)):continue
                lo=pb+((ag-pb)//ps)*ps;hi=np.minimum(lo+ps,pe)
                if not (np.all(end>lo) and np.all(begin<hi)):continue
                center=np.array([anchor['world_x'],anchor['world_z']]);rays=[origin+np.array(c)*spacing-center for c in [(lo[0],lo[1]),(hi[0],lo[1]),(hi[0],hi[1]),(lo[0],hi[1])]];updated=[]
                for j in range(0,len(new_indices),3):
                    ids=new_indices[j:j+3];triangle=np.array([point_list[i] for i in ids]);g=(triangle[:,[0,2]]-origin)/spacing
                    if np.any(g.max(axis=0)<lo-1e-8) or np.any(g.min(axis=0)>hi+1e-8):updated.extend(ids);continue
                    polygons=[triangle]
                    for ray in rays:
                        next_polygons=[]
                        for poly in polygons:
                            delta=poly[:,[0,2]]-center;sign=ray[0]*delta[:,1]-ray[1]*delta[:,0]
                            if sign.min()>=-1e-8 or sign.max()<=1e-8:next_polygons.append(poly);continue
                            for side in (-1,1):
                                clipped=[]
                                for k in range(len(poly)):
                                    a=poly[k];b=poly[(k+1)%len(poly)];sa=sign[k]*side;sb=sign[(k+1)%len(poly)]*side
                                    if sa>=-1e-10:clipped.append(a)
                                    if (sa>1e-10 and sb<-1e-10) or (sa<-1e-10 and sb>1e-10):clipped.append(a+(b-a)*(sa/(sa-sb)))
                                if len(clipped)>=3:next_polygons.append(np.array(clipped))
                        polygons=next_polygons
                    if len(polygons)==1:updated.extend(ids);continue
                    for poly in polygons:
                        base_id=len(point_list)
                        for vertex in poly:
                            point_list.append(vertex.tolist());grid=(vertex[[0,2]]-origin)/spacing;normal_list.append(normal(int(round(grid[0])),int(round(grid[1]))).tolist())
                        for k in range(1,len(poly)-1):updated.extend([base_id,base_id+k,base_id+k+1])
                new_indices=updated
            indices=new_indices;points=np.array(point_list);normals=np.array(normal_list)
        parent_y=points[:,1].copy() if parent is None else sample_parent(points,np.array(parent['grid_begin']),np.array(parent['grid_end']),parent['stride'])
        geometry_ids=None
        if len(points)>unrefined_vertex_count:
            points,normals,parent_y,indices,geometry_ids,_=node_existing_edges(points,normals,parent_y,indices)
            conformity=topology(points,indices,geometry_ids)
            if conformity["Euler"]!=1 or conformity["inner_unpaired_edges"]!=0 or conformity["nonmanifold_edges"]!=0:raise ValueError("nonconforming parentstar common refinement: "+str(conformity))
        # Exact max error on fixed fine-grid nodes (piecewise planar compatible dyadic diagonals);
        # named stars included explicitly; max endpoint deviation bounds linear interpolation.
        max_error=0.;minimum=math.inf;maximum=-math.inf
        for row in range(begin[1],end[1]+1,64):
            gx,gz=np.meshgrid(np.arange(begin[0],end[0]+1),np.arange(row,min(row+64,end[1]+1)))
            p=np.stack([origin[0]+gx*spacing[0],height(gx,gz),origin[1]+gz*spacing[1]],axis=-1).reshape(-1,3)
            max_error=max(max_error,float(np.max(np.abs(sample_parent(p,begin,end,stride)-p[:,1])))*1000);minimum=min(minimum,float(p[:,1].min()));maximum=max(maximum,float(p[:,1].max()))
        if stars:
            minimum=min(minimum,min(a['height_source_m']*.001 for a in stars.values()));maximum=max(maximum,max(a['height_source_m']*.001 for a in stars.values()));max_error=max(max_error,(maximum-minimum)*1000)
        sections={};body=bytearray()
        def append(name,array,dtype,components):
            data=np.asarray(array,dtype=dtype).tobytes();sections[name]={'offset':len(body),'bytes':len(data),'components':components};body.extend(data)
        append('vertices',points,'<f4',3);append('normals',normals,'<f4',3);append('parent_y',parent_y,'<f4',1);append('indices',indices,'<i4',1)
        if geometry_ids is not None:append('geometry_ids',geometry_ids,'<i4',1)
        # Native vertex grid halo supports exact local atlas queries; no global height upload.
        hb=np.maximum(begin-stride,0);he=np.minimum(end+stride,[w-1,h-1]);hx=np.r_[np.arange(hb[0],he[0],stride),he[0]];hz=np.r_[np.arange(hb[1],he[1],stride),he[1]];tile=np.asarray(raw[np.ix_(hz,hx)],dtype='>u2');append('atlas_rg8',tile,'>u2',2)
        split=must_split_local(begin,end,level)
        material_fields=source_windows(origin+begin*spacing,origin+end*spacing,not split)
        material_bytes=sum(d['bytes'] for domain in material_fields.values() for d in domain.values())
        material_error=max([max(np.array(d['texture_world_size'])/[d['width'],d['height']]) for domain in material_fields.values() for d in domain.values() if d['mip_level']>0]+[0.])
        ident=f'{level}/{x}/{z}';header={'schema_version':'terrain-block-v1','id':ident,'sections':sections,'atlas_grid_begin':hb.tolist(),'atlas_grid_end':he.tolist(),'atlas_stride':stride,'atlas_width':len(hx),'atlas_height':len(hz),'vertex_count':len(points),'index_count':len(indices)}
        header_bytes=enc(header);data=b'TBL1'+struct.pack('<I',len(header_bytes))+header_bytes+body;p=out/'blocks'/f'{level}-{x}-{z}.bin';p.write_bytes(data);payload_bytes+=len(data)
        rec={'id':ident,'level':level,'parent':parent['id'] if parent else None,'children':[],'grid_begin':begin.tolist(),'grid_end':end.tolist(),'stride':stride,'world_min':(origin+begin*spacing).tolist(),'world_size':((end-begin)*spacing).tolist(),'height_error_m':max_error,'height_bounds_m':[minimum*1000,maximum*1000],'vertex_count':len(points),'index_count':len(indices),'geometry_bytes':len(body),'payload':{'path':str(p.relative_to(out)),'bytes':len(data),'sha256':sha(p)},'parent_payload_sha256':parent['payload']['sha256'] if parent else None,'fields':material_fields,'material_bytes':material_bytes,'material_error_world':material_error,'decoded_bytes':len(body)+material_bytes};blocks[ident]=rec
        if split:
            for dz in (0,1):
                for dx in (0,1):
                    child=node(level+1,x*2+dx,z*2+dz,rec)
                    if child:rec['children'].append(child)
        return ident
    root=node(0,0,0)
    manifest={'schema_version':'terrain-tree-v1','dataset_revision':'terrain-blocks-source-v2-r2','status':'implementiert; runtime/integrated visual acceptance open','source_manifest_sha256':m['source_manifest_sha256'],'atlas_manifest_sha256':sha(surface_path),'atlas_identity':m,'atlas_policy':json.loads((base/m['policy']['path']).read_text()),'root':root,'depth':max(r['level'] for r in blocks.values()),'base_depth':depth,'material_parent_cap':material_cap,'upload_manifest_sha256':sha(upload_path) if upload_path else None,'upload_manifest':upload,'coast_manifest':coast,'coast_manifest_sha256':sha(coast_path) if coast_path else None,'leaf_cells':cells,'world_min':m['world_min'],'world_size':m['world_size'],'width':w,'height':h,'spacing':spacing.tolist(),'payload_bytes':payload_bytes,'blocks':blocks,'query_footprints':{'revision':'terrain-query-footprints-r1','RGBA_world_radius':.6,'source_height_normal_world_radius':.1,'fixed_G_normal_atlas_steps':1,'native_texel_filter_halo':2,'color_maximum_mip':0,'SDF_role_bathymetry_coast_world_radius':0.,'screen_derivatives':'same invocation field values; no extra world lookup'},'contracts':{'diagonal':'a,b,c / b,d,c; source-retained anchor stars at every level','sample_origin':'fixed atlas vertex aligned; native RG8 halo inclusive','source_height_quantum_m':.25,'parent_y':'actual parent triangle including retained stars','material_G':'native atlas plane excludes star-only topology; SourceV2 RGBA unchanged','integrity':'SHA256 per independently loaded block; manifest bound in product config'}}
    atomic_json(out/'tree.json',manifest);atomic_json(out/'READY.json',{'manifest_sha256':sha(out/'tree.json'),'blocks':len(blocks),'complete':True});return {'manifest':str(out/'tree.json'),'sha256':sha(out/'tree.json'),'blocks':len(blocks),'payload_bytes':payload_bytes}

def estimate(surface_path,upload_path,coast_path,cells=128,cap=256):
    m=json.loads(surface_path.read_text());u=json.loads(upload_path.read_text());coast=json.loads(coast_path.read_text());w,h=m['width'],m['height'];origin=np.array(m['world_min']);spacing=np.array(m['world_size'])/[w-1,h-1];depth=max(0,math.ceil(math.log2(max(w-1,h-1)/cells)));span=cells*2**depth
    bpp={'height':2,'water_distance':2,'associated_role':1,'classes':1,'surface_weights':4,'forest_groups':4,'forest_interior':4,'forest_membership':1};fields=[(d,bpp[f],f) for name in ('context','fine','local') for f,d in u['domains'][name].items() if f in bpp]+[(coast,2,'coast_distance')];local=u['domains']['local']['surface_weights'];la=np.array(local['world_min']);lb=la+local['world_size'];result={'geometry_bytes_estimate':0,'blocks':0,'leaves':0,'max_depth':0,'max_decoded_bytes_estimate':0,'max_page_edge':0,'all_source_windows_bytes':0,'backing_store_bytes':0};sources={d['payload']['path']:d['payload']['bytes'] for d,_,_ in fields};result['backing_store_bytes']=sum(sources.values())
    def node(level,x,z):
        s=span//2**level;begin=np.array([x*s,z*s]);end=np.minimum(begin+s,[w-1,h-1])
        if np.any(begin>=end):return
        wb=origin+begin*spacing;we=origin+end*spacing;split=level<depth or (np.all(we+.6>la) and np.all(wb-.6<lb) and np.max(end-begin)>2)
        total=0
        for d,channels,fn in fields:
            radius=.6 if fn=='surface_weights' else 0.
            a=np.array(d['world_min']);size=np.array(d['world_size']);dim=np.array([d['width'],d['height']]);pixel=size/dim;low=np.floor((wb-radius-a)/pixel-.5).astype(int)-2;high=np.ceil((we+radius-a)/pixel-.5).astype(int)+2
            if not(np.all(we+radius>=a) and np.all(wb-radius<=a+size)):low=np.clip(low,0,dim-1);high=low+1
            else:low=np.maximum(low,-2);high=np.minimum(high,dim+1)
            step=1
            if split:
                while np.max(np.ceil((high-low)/step)+1)>cap:step*=2
            low=np.floor_divide(low,step)*step;high=np.ceil(high/step).astype(int)*step;dims=(high-low)//step+1;total+=int(np.prod(dims))*channels;result['max_page_edge']=max(result['max_page_edge'],int(dims.max()))
        stride=max(1,2**(depth-level));dims=np.ceil((end-begin)/stride).astype(int)+1;geometry=int(np.prod(dims))*30+int(np.prod(dims-1))*24+int(np.prod(dims+2))*2
        result['geometry_bytes_estimate']+=geometry;result['blocks']+=1;result['max_depth']=max(result['max_depth'],level);result['all_source_windows_bytes']+=total;result['max_decoded_bytes_estimate']=max(result['max_decoded_bytes_estimate'],total+geometry)
        if level==0:result['root_material_bytes']=total;result['root_decoded_bytes_estimate']=total+geometry
        if split:
            for dz in (0,1):
                for dx in (0,1):node(level+1,x*2+dx,z*2+dz)
        else:result['leaves']+=1
    node(0,0,0);return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--estimate-only',action='store_true');p.add_argument('--surface',default='artifacts/render-data/fixed-source-v2-macro-r1/surface.json');p.add_argument('--out',default='artifacts/render-data/terrain-blocks-source-v2-r2');p.add_argument('--upload',default='artifacts/render-data/source-v2-upload-r1/upload.json');p.add_argument('--coast',default='artifacts/render-data/display-coast-source-v2-r1/manifest.json');p.add_argument('--material-parent-cap',type=int,default=256);a=p.parse_args();print(json.dumps(estimate(ROOT/a.surface,ROOT/a.upload,ROOT/a.coast,cap=a.material_parent_cap) if a.estimate_only else build(ROOT/a.surface,ROOT/a.out,upload_path=ROOT/a.upload,material_cap=a.material_parent_cap,coast_path=ROOT/a.coast)))
