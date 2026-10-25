#!/usr/bin/env python3
"""Encode the already generalised world product for GPU upload, never raw DEM.
No downloads/installations. Signed quarter-metre height encoding has an explicit
0.125 m maximum rounding error; source bytes and canonical geometry stay intact.
"""
import argparse, hashlib, json, pathlib, math, time, shutil, sys
import numpy as np
ROOT = pathlib.Path(__file__).resolve().parents[2]

def sha(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()

def record(path, base):
    return {'path':str(path.relative_to(base)), 'sha256':sha(path), 'bytes':path.stat().st_size}

def height_upload(base, manifest, domain):
    detail=domain=='detail'
    key='height_detail_path' if detail else 'height_path'
    source=base/manifest[key]
    width=int(manifest['height_detail_width'] if detail else manifest.get('height_width',manifest.get('width',manifest.get('grid_width'))))
    height=int(manifest['height_detail_height'] if detail else manifest.get('height_height',manifest.get('height',manifest.get('grid_height'))))
    expected=manifest['assets'][manifest[key]]['sha256']
    if sha(source)!=expected: raise ValueError('Generalised height source hash mismatch')
    if source.stat().st_size!=width*height*4: raise ValueError('Generalised height dimensions mismatch')
    policy={'encoding':'RG8 high-byte/low-byte','minimum_m':-8192.,'step_m':.25,'max_rounding_error_m':.125,'width':width,'height':height,'source_sha256':expected,'source_path':manifest[key]}
    target=base/'upload'/f'{domain}-height.rg8'
    metadata=target.with_suffix('.json')
    if metadata.exists() and target.exists():
        prior=json.loads(metadata.read_text())
        if prior['policy']==policy and prior['payload']['sha256']==sha(target): return prior
    values=np.memmap(source,mode='r',dtype='<f4')
    maximum_error=0.;minimum=float('inf');maximum=float('-inf')
    temporary=target.with_suffix('.tmp')
    with temporary.open('wb') as stream:
        for start in range(0,len(values),1_000_000):
            chunk=np.array(values[start:start+1_000_000],dtype=np.float64)
            if not np.all(np.isfinite(chunk)) or chunk.min()<-8192 or chunk.max()>8191.75:
                raise ValueError('Source outside signed encoding interval; refusing clamp')
            codes=np.floor((chunk+8192)*4+.5).astype(np.uint16)
            decoded=codes.astype(np.float64)*.25-8192
            maximum_error=max(maximum_error,float(np.max(np.abs(decoded-chunk))))
            minimum=min(minimum,float(chunk.min()));maximum=max(maximum,float(chunk.max()))
            packed=np.empty((len(codes),2),dtype=np.uint8)
            packed[:,0]=codes>>8;packed[:,1]=codes&255;stream.write(packed.tobytes())
    if maximum_error>.125: raise ValueError('Predeclared upload encoding budget exceeded')
    temporary.replace(target)
    result={'policy':policy,'payload':record(target,base),'measured_max_rounding_error_m':maximum_error,'model_min_m':minimum,'model_max_m':maximum}
    metadata.write_text(json.dumps(result,indent=2)+'\n')
    return result

def water_upload(base, manifest, domain):
    detail=domain=='detail'
    key='detail_water_path' if detail else 'water_path'
    if key not in manifest: return None
    source=base/manifest[key]
    width=int(manifest['detail_water_width'] if detail else manifest.get('water_width',manifest.get('height_width',manifest.get('width',manifest.get('grid_width')))))
    height=int(manifest['detail_water_height'] if detail else manifest.get('water_height',manifest.get('height_height',manifest.get('height',manifest.get('grid_height')))))
    bounds=manifest.get('height_detail_bounds',manifest['core_bounds']) if detail else manifest['bounds']
    if isinstance(bounds,list): bounds=dict(zip(['west','south','east','north'],bounds))
    expected=manifest['assets'][manifest[key]]['sha256']
    if sha(source)!=expected: raise ValueError('Model water source hash mismatch')
    vector_paths=[base/manifest['vector_paths'][name] for name in ['land','lakes']]
    vector_hashes={str(path.relative_to(base)):sha(path) for path in vector_paths}
    if source.stat().st_size!=width*height: raise ValueError('Model water dimensions mismatch')
    sx=math.radians(bounds['east']-bounds['west'])*6371008.8*math.cos(math.radians(41))/width
    sy=math.radians(bounds['north']-bounds['south'])*6371008.8/height
    policy={'algorithm':'nearest canonical generalised vector boundary segment within3000 projected metres; no external rectangle segments','source_path':manifest[key],'source_sha256':expected,'width':width,'height':height,'bounds':bounds,'encoding':'RG8 high-byte/low-byte, code*0.125-4096 projectedmetres, positivewater','radius_m':3000.,'sx_m':sx,'sy_m':sy,'canonical_vector_sha256':vector_hashes,'geographic_accuracy':'limited by canonical generalised vectors and texture sampling, not the0.0625m encoding rounding; representation distance is not new coastline data'}
    target=base/'upload'/f'{domain}-water-vector-distance.rg8';metadata=target.with_suffix('.json')
    if metadata.exists() and target.exists():
        prior=json.loads(metadata.read_text())
        if prior['policy']==policy and prior['payload']['sha256']==sha(target): return prior
    water=np.memmap(source,mode='r',dtype='u1',shape=(height,width))>0
    field=np.full((height,width),3000.,dtype=np.float32)
    def rings(geometry):
        if geometry.get('type')=='Polygon': yield from geometry['coordinates']
        elif geometry.get('type')=='MultiPolygon':
            for polygon in geometry['coordinates']: yield from polygon
    for path in vector_paths:
        for feature in json.loads(path.read_text())['features']:
            for ring in rings(feature['geometry']):
                for a,b in zip(ring,ring[1:]):
                    ax=(a[0]-bounds['west'])/(bounds['east']-bounds['west'])*width-.5
                    ay=(bounds['north']-a[1])/(bounds['north']-bounds['south'])*height-.5
                    bx=(b[0]-bounds['west'])/(bounds['east']-bounds['west'])*width-.5
                    by=(bounds['north']-b[1])/(bounds['north']-bounds['south'])*height-.5
                    x0=max(0,math.floor(min(ax,bx)-3000/sx));x1=min(width-1,math.ceil(max(ax,bx)+3000/sx))
                    y0=max(0,math.floor(min(ay,by)-3000/sy));y1=min(height-1,math.ceil(max(ay,by)+3000/sy))
                    if x1<x0 or y1<y0: continue
                    dx=(bx-ax)*sx;dy=(by-ay)*sy;denominator=dx*dx+dy*dy
                    if denominator<1e-16: continue
                    xx=(np.arange(x0,x1+1,dtype=np.float64)-ax)[None,:]*sx
                    yy=(np.arange(y0,y1+1,dtype=np.float64)-ay)[:,None]*sy
                    fraction=np.clip((xx*dx+yy*dy)/denominator,0,1)
                    distance=np.hypot(xx-fraction*dx,yy-fraction*dy)
                    destination=field[y0:y1+1,x0:x1+1]
                    np.minimum(destination,distance,out=destination)
    temporary=target.with_suffix('.tmp');maximum_error=0.
    with temporary.open('wb') as stream:
        for y in range(height):
            signed=field[y].astype(np.float64)*np.where(water[y],1.,-1.)
            codes=np.floor((signed+4096)*8+.5).astype(np.uint16)
            maximum_error=max(maximum_error,float(np.max(np.abs(codes.astype(np.float64)*.125-4096-signed))))
            packed=np.empty((width,2),dtype=np.uint8);packed[:,0]=codes>>8;packed[:,1]=codes&255;stream.write(packed.tobytes())
    temporary.replace(target)
    result={'policy':policy,'payload':record(target,base),'measured_max_rounding_error_m':maximum_error}
    metadata.write_text(json.dumps(result,indent=2)+'\n');return result


# V2 is a separate immutable transport path. The V1 encoder above is retained.
def _v2_ref(path):
    return {'path':str(path.resolve().relative_to(ROOT)), 'path_base':'repository_root', 'sha256':sha(path), 'bytes':path.stat().st_size}

def _v2_rect(bounds):
    k=math.pi/180*6371008.8*.001;cx=k*math.cos(math.radians(41))
    return [(bounds['west']-19)*cx,(41-bounds['north'])*k],[(bounds['east']-bounds['west'])*cx,(bounds['north']-bounds['south'])*k]

def _v2_checked(reference):
    path=ROOT/reference['path']
    if path.stat().st_size!=reference['bytes'] or sha(path)!=reference['sha256']:
        raise ValueError('Canonical V2 input hash/size mismatch: '+str(path))
    return path

def _v2_field(reference,width,height,bounds,encoding,filtering,output=None):
    source=_v2_checked(reference)
    if output is not None:
        shutil.copyfile(source,output)
        payload=_v2_ref(output)
        if payload['sha256']!=reference['sha256']: raise ValueError('Nonidentical V2 transport')
    else:payload=_v2_ref(source)
    origin,size=_v2_rect(bounds)
    return {'payload':payload,'source_path':str(source.resolve().relative_to(ROOT)),'source_sha256':reference['sha256'],'source_bytes':reference['bytes'],'width':int(width),'height':int(height),'bounds':bounds,'world_min':origin,'world_size':size,'encoding':encoding,'sampling_filter':filtering,'sample_registration':'pixel_center','UV_contract':'uv=(p-world_min)/world_size; texel=uv*dimensions-.5; edge clamp; no exterior extrapolation','transform':'byte-identical transport' if output else 'immutable canonical reference','additional_encoding_error':0}

def _v2_height(source_ref,width,height,bounds,output):
    source=_v2_checked(source_ref)
    if source.stat().st_size!=int(width)*int(height)*4:raise ValueError('V2 height dimensions mismatch')
    values=np.memmap(source,dtype='<f4',mode='r');maximum_error=0.;minimum=float('inf');maximum=float('-inf');count=0
    with output.open('xb') as stream:
        for start in range(0,len(values),1_000_000):
            chunk=np.array(values[start:start+1_000_000],dtype='f8')
            if not np.isfinite(chunk).all() or chunk.min()<-8192 or chunk.max()>8191.75:raise ValueError('Nonfinite/out-of-range height: no clamp or fabricated fill')
            code=np.floor((chunk+8192)*4+.5).astype('u2');decoded=code.astype('f8')*.25-8192
            maximum_error=max(maximum_error,float(np.abs(decoded-chunk).max()));minimum=min(minimum,float(chunk.min()));maximum=max(maximum,float(chunk.max()));count+=chunk.size
            packed=np.empty((chunk.size,2),dtype='u1');packed[:,0]=code>>8;packed[:,1]=code&255;stream.write(packed.tobytes())
    if maximum_error>.125:raise ValueError('Prebound V2 height encoding budget exceeded')
    # Re-read the actual emitted bytes against every original Float32 value.
    packed=np.memmap(output,dtype='u1',mode='r',shape=(len(values),2));reread_max=0.
    for start in range(0,len(values),1_000_000):
        end=min(len(values),start+1_000_000);v=packed[start:end];decoded=(v[:,0].astype('f8')*256+v[:,1])*.25-8192
        reread_max=max(reread_max,float(np.abs(decoded-values[start:end]).max()))
    if reread_max>.125:raise ValueError('Actual height encode/decode budget exceeded')
    origin,size=_v2_rect(bounds)
    return {'payload':_v2_ref(output),'source_path':str(source.resolve().relative_to(ROOT)),'source_sha256':source_ref['sha256'],'source_bytes':source_ref['bytes'],'width':int(width),'height':int(height),'bounds':bounds,'world_min':origin,'world_size':size,'encoding':{'format':'RG8 high-byte/low-byte','decode':'(R_byte*256+G_byte)*0.25-8192','minimum_m':-8192,'step_m':.25,'max_rounding_error_m':.125,'clamping':'forbidden'},'sampling_filter':'bilinear decoded linear height','sample_registration':'pixel_center','UV_contract':'uv=(p-world_min)/world_size; texel=uv*dimensions-.5; edge clamp; no exterior extrapolation','transform':'representation encoding only; no height/geography/generalization change','measured_max_rounding_error_m':reread_max,'all_source_pixels_checked':count,'source_range_m':[minimum,maximum]}

def _v2_sample(field,x,z,encoding,cache):
    key=field['payload']['path']
    if key not in cache:
        channels=2 if encoding in ['height','SDF'] else (4 if encoding=='RGBA' else 1)
        shape=(field['height'],field['width']) if channels==1 else (field['height'],field['width'],channels)
        cache[key]=np.memmap(_v2_checked(field['payload']),dtype='u1',mode='r',shape=shape)
    a=cache[key];h,w=a.shape[:2];ox,oz=field['world_min'];sx,sz=field['world_size'];u=min(max((x-ox)/sx*w-.5,0.),w-1.);v=min(max((z-oz)/sz*h-.5,0.),h-1.)
    if encoding=='role':return int(a[min(int(math.floor(v+.5)),h-1),min(int(math.floor(u+.5)),w-1)])
    ix=int(math.floor(u));iz=int(math.floor(v));fx=u-ix;fz=v-iz
    def decoded(dx,dz):
        q=a[min(iz+dz,h-1),min(ix+dx,w-1)].astype('f8')
        if encoding=='height':return (q[0]*256+q[1])*.25-8192
        if encoding=='SDF':return (q[0]*256+q[1])*.125-4096
        return q
    return (decoded(0,0)*(1-fx)+decoded(1,0)*fx)*(1-fz)+(decoded(0,1)*(1-fx)+decoded(1,1)*fx)*fz

def _v2_weight(x,z,t):
    o=t['outer_world_min'];s=t['outer_world_size'];i=t['inner_world_min'];q=t['inner_world_size']
    values=[(x-o[0])/(i[0]-o[0]),(o[0]+s[0]-x)/(o[0]+s[0]-i[0]-q[0]),(z-o[1])/(i[1]-o[1]),(o[1]+s[1]-z)/(o[1]+s[1]-i[1]-q[1])]
    weight=1.
    for v in values:
        v=min(max(v,0.),1.);weight*=v*v*v*(v*(6*v-15)+10)
    return weight

def verify_v2_upload(path,source_path):
    sys.path.insert(0,str(ROOT/'tools'))
    from canonical_v2_sampler import CanonicalV2Sampler
    source=CanonicalV2Sampler(source_path);m=json.loads(path.read_text());domains=m['domains'];cache={};input_mismatches=[]
    if m['source_manifest_sha256']!=sha(source_path):raise ValueError('V2 upload source identity mismatch')
    if domains['detail']!=domains['fine']:raise ValueError('V2 detail/fine alias mismatch')
    transport=[];height_pixel_checks=[]
    for name in ['context','fine','local']:
        d=domains[name]
        if 'height' in d:
            field=d['height'];original=np.memmap(ROOT/field['source_path'],dtype='<f4',mode='r');packed=np.memmap(_v2_checked(field['payload']),dtype='u1',mode='r',shape=(len(original),2));maximum_error=0.
            if sha(ROOT/field['source_path'])!=field['source_sha256'] or len(original)!=field['width']*field['height']:raise ValueError('Height source identity/dimensions mismatch')
            for start in range(0,len(original),1_000_000):
                end=min(len(original),start+1_000_000);q=packed[start:end];decoded=(q[:,0].astype('f8')*256+q[:,1])*.25-8192;raw=original[start:end]
                if not np.isfinite(raw).all():raise ValueError('Nonfinite original height')
                maximum_error=max(maximum_error,float(np.abs(decoded-raw).max()))
            if maximum_error>.125:raise ValueError('Actual full height pixel roundtrip fails')
            height_pixel_checks.append({'domain':name,'pixels_checked':len(original),'decoded_pixel_max_error_m':maximum_error})
        for fieldname in ['water_distance','associated_role','water','surface_weights','classes','forest_groups','forest_interior','forest_membership']:
            if fieldname not in d:continue
            field=d[fieldname];payload=_v2_checked(field['payload'])
            if sha(ROOT/field['source_path'])!=field['source_sha256'] or field['payload']['sha256']!=field['source_sha256']:input_mismatches.append(name+'.'+fieldname)
        rg=np.memmap(_v2_checked(d['water_distance']['payload']),dtype='u1',mode='r',shape=(d['water_distance']['height'],d['water_distance']['width'],2))
        code=rg[...,0].astype('i4')*256+rg[...,1];minimum=float(code.min()*.125-4096);maximum=float(code.max()*.125-4096)
        if minimum<-3000 or maximum>3000:raise ValueError('Invalid source SDF saturation interval')
        roles=np.memmap(_v2_checked(d['associated_role']['payload']),dtype='u1',mode='r');unique=np.unique(roles).tolist()
        if any(v not in [1,2] for v in unique):raise ValueError('Invalid associated role code')
        transport.append({'domain':name,'SDF_min_m':minimum,'SDF_max_m':maximum,'negative_saturated_cells':int(np.count_nonzero(code==8768)),'positive_saturated_cells':int(np.count_nonzero(code==56768)),'associated_role_codes':unique,'additional_transport_error_m':0})
    # Existing frozen source-V2 evidence is used as a fixed probe inventory.
    old=ROOT/'artifacts/render-data/fixed-source-v2-macro-r1'
    inventory=json.loads((old/'verification.json').read_text())['probes'];native=json.loads((old/'contract-probes.json').read_text())['role_probes']
    points=[(v['lon'],v['lat'],'frozen_V2_probe') for v in inventory]+[(v['lon'],v['lat'],v['label']) for v in native]
    points += [(-44,61,'context_NW_boundary'),(79,18,'context_SE_boundary'),(-44,18,'context_SW_boundary'),(79,61,'context_NE_boundary')]
    rows=[];maxh=0.;maxphi=0.;maxrgba=0.;role_errors=0
    for lon,lat,label in points:
        x=(lon-19)*source.CX;z=(41-lat)*source.K;w=_v2_weight(x,z,m['domain_transition']);l=_v2_weight(x,z,domains['local']['domain_transition'])
        h0=_v2_sample(domains['context']['height'],x,z,'height',cache);h1=_v2_sample(domains['fine']['height'],x,z,'height',cache);actual_h=h0*(1-w)+h1*w
        phis=[float(_v2_sample(domains[n]['water_distance'],x,z,'SDF',cache)) for n in ['context','fine','local']];phi=(phis[0]*(1-w)+phis[1]*w)*(1-l)+phis[2]*l
        roles=[_v2_sample(domains[n]['associated_role'],x,z,'role',cache) for n in ['context','fine','local']];role=roles[2] if l>0 else (roles[1] if w>0 else roles[0]);role=role if phi>0 else 0
        rgba=[_v2_sample(domains[n]['surface_weights'],x,z,'RGBA',cache) for n in ['context','fine','local']];actual_rgba=(rgba[0]*(1-w)+rgba[1]*w)*(1-l)+rgba[2]*l
        expected_h=float(source.raw_height(x,z));expected_phi,expected_role=source.fields(x,z);expected_rgba=source.surface_weights(np.asarray(x),np.asarray(z));dh=abs(actual_h-expected_h);dp=abs(phi-float(expected_phi));dr=float(np.max(np.abs(actual_rgba-expected_rgba)));maxh=max(maxh,dh);maxphi=max(maxphi,dp);maxrgba=max(maxrgba,dr);role_errors+=int(role!=int(expected_role))
        rows.append({'label':label,'lon':lon,'lat':lat,'fine_weight':w,'local_weight':l,'height_original_m':expected_h,'height_decoded_m':actual_h,'height_error_m':dh,'SDF_original_m':float(expected_phi),'SDF_decoded_m':phi,'SDF_error_m':dp,'associated_roles_context_fine_local':roles,'final_role':role,'expected_role':int(expected_role),'RGBA_error_byte_units':dr})
    if input_mismatches or maxh>.125+1e-9 or maxphi>1e-7 or maxrgba>1e-6 or role_errors:raise ValueError('Prebound V2 encode/decode validation failed')
    inland=[r for r in rows if r['label']=='positive_local_inlandwater_deepest_available_cell']
    if not inland or inland[0]['final_role']!=2 or inland[0]['SDF_decoded_m']<=0:raise ValueError('Local inlandwater role lost')
    return {'revision':'source-v2-upload-verification-r1','status':'validiert','scope':'CPU representation encoding and transport; no GPU/runtime/visual acceptance','source_manifest_sha256':sha(source_path),'upload_manifest_sha256':sha(path),'prebound_budgets':m['encoding_budgets'],'height_composed_probe_max_error_m':maxh,'SDF_transport_composed_probe_max_error_m':maxphi,'RGBA_transport_composed_probe_max_error_byte_units':maxrgba,'role_mismatches':role_errors,'input_transport_mismatches':input_mismatches,'height_pixel_roundtrip_checks':height_pixel_checks,'domains':transport,'probes':rows,'nodata_rule':'All original height pixels checked finite and encoding range; all transported SDFs finite integer codes in declared saturation interval; all associated_role codes1/2. No invented fill. This is not a native-source accuracy claim.','open':['GPU texture upload and sampling parity','Runtime explicit binding','images and continuous zoom','GPU performance','overall Kit1 acceptance']}

def v2_upload(source_path,out,verify_only=False):
    sys.path.insert(0,str(ROOT/'tools'))
    from canonical_v2_sampler import CanonicalV2Sampler
    if verify_only:
        result=verify_v2_upload(out/'upload.json',source_path);print(json.dumps(result,indent=2));return
    if out.exists():raise ValueError('V2 output already exists; use a new immutable revision directory')
    source=CanonicalV2Sampler(source_path);m=source.m;base=source_path.parent;wd=source.wd;out.mkdir(parents=True,exist_ok=False)
    def topref(key):return _v2_ref((base/m[key]).resolve())
    domains={}
    for name in ['context','fine','local']:
        d=wd['domains'][name];b=d['bounds'];w=d['width'];h=d['height'];domain={'bounds':b,'world_min':d['world_min'],'world_size':d['world_size']}
        if name in ['fine','local']:domain['domain_transition']=m['domain_transition'] if name=='fine' else m['local_domain_transition']
        if name!='local':
            keys=('height_path','height_width','height_height','bounds') if name=='context' else ('height_detail_path','height_detail_width','height_detail_height','height_detail_bounds')
            domain['height']=_v2_height(topref(keys[0]),m[keys[1]],m[keys[2]],m[keys[3]],out/(name+'-height.rg8'))
        domain['water_distance']=_v2_field(d['distance'],w,h,b,{'format':'RG8 high-byte/low-byte','decode':'(R_byte*256+G_byte)*0.125-4096','step_projected_m':.125,'saturation_projected_m':[-3000,3000],'canonical_quantization_max_projected_m':d['quantization_max_projected_m'],'additional_quantization_error_m':0},'bilinear decoded signed distance',out/(name+'-water-distance.rg8'))
        domain['associated_role']=_v2_field(d['associated_role'],w,h,b,{'format':'UInt8','associated_codes':{'1':'marine','2':'inlandwater'},'land_rule':'association on land has no water meaning; final composed SDF<=0 yields0land'},'nearest discrete',out/(name+'-associated-role.u8'))
        domain['water']=_v2_field(d['water'],w,h,b,{'format':'UInt8','codes':{'0':'land','1':'marine','2':'inlandwater'},'use':'canonical mask reference; final composed SDF owns physical contour'},'nearest discrete',out/(name+'-water.u8'))
        if name=='local':
            for key,encoding in [('surface_weights','RGBA8 linear forest/rock/dry/shore'),('classes','UInt8 ESA generalized codes'),('forest_groups','UInt32LE connected group IDs'),('forest_interior','Float32LE projected source metres'),('forest_membership','UInt8 membership')]:
                domain[key]=_v2_field(d[key],w,h,b,encoding,'bilinear' if key in ['surface_weights','forest_interior'] else 'nearest discrete')
        else:
            isfine=name=='fine';prefix='detail_' if isfine else '';cw=m[prefix+'class_width'] if isfine else m['class_width'];ch=m[prefix+'class_height'] if isfine else m['class_height'];cb=m['detail_class_bounds'] if isfine else m['bounds']
            domain['classes']=_v2_field(topref(prefix+'class_path' if isfine else 'class_path'),cw,ch,cb,'UInt8 generalized ESA codes','nearest discrete')
            sw=prefix+'surface_weights';domain['surface_weights']=_v2_field(topref(sw+'_path'),m[sw+'_width'],m[sw+'_height'],m[sw+'_bounds'],'RGBA8 linear forest/rock/dry/shore','bilinear linear data, never sRGB')
            if isfine:
                for key,pathkey,encoding in [('forest_groups','forest_group_labels_path','UInt32LE connected group IDs'),('forest_interior','forest_interior_distance_path','Float32LE projected source metres')]:domain[key]=_v2_field(topref(pathkey),m['forest_group_width'],m['forest_group_height'],m['forest_group_bounds'],encoding,'nearest discrete' if key=='forest_groups' else 'bilinear')
        domains[name]=domain
    domains['detail']=domains['fine']
    result={'schema_version':'gameworld-gpu-upload-v2','revision':'source-v2-upload-r1','status':'implementiert; CPU verification follows; runtime GPU acceptance open','source_manifest':_v2_ref(source_path),'source_manifest_sha256':sha(source_path),'required_sampling_contract':'canonical-c2-domains-v2','path_base':'repository_root','domain_transition':m['domain_transition'],'local_domain_transition':m['local_domain_transition'],'domains':domains,'domain_aliases':{'detail':'fine'},'local_height_override':False,'sampling_contract':{'continuous_fields':'static product smootherstep C2, context→fine then parent→local; local has no height','normal_rule':'differentiate composed height, including transition-weight gradient','sign':'Phi<=0 land; Phi>0 water','final_role_enum':{'0':'land','1':'marine','2':'inlandwater'},'role_selection':'Own documented integration decision: after final Phi>0 select nearest associated_role from finest valid domain with weight>0; local>fine>context; no numeric code interpolation or .5 threshold. Categorical roles are not continuous.','pixel_registration':'first pixel at min+size/(2*dimensions), uv*N-.5, edge clamp','zoom_dependent':False},'encoding_budgets':{'height_pixel_and_composed_height_error_m':.125,'SDF_additional_transport_error_m':0,'associated_role_code_error':0,'RGBA_additional_transport_error_byte_units':0,'source_SDF_encoding_step_m':.125,'source_SDF_quantization_upper_bound_m':.0625,'source_SDF_saturation_m':[-3000,3000],'floating_point_probe_tolerance_m':1e-7},'source_accuracy':'Encoding and byte transport do not improve canonical/native accuracy. Trusted native local coast and outer source-fusion collar retain their separate source budgets.','provenance':{'encoder':_v2_ref(pathlib.Path(__file__)),'canonical_sampler':_v2_ref(ROOT/'tools/canonical_v2_sampler.py'),'python':sys.version.split()[0],'numpy':np.__version__},'transform':'Height representation encoding plus byte-identical SDF/associated-role/water transport; remaining fields reference immutable canonical payloads. No new water-distance derivation.'}
    shutil.copyfile(pathlib.Path(__file__),out/'encoder-source.py')
    result['provenance']['encoder_snapshot']=_v2_ref(out/'encoder-source.py')
    path=out/'upload.json';path.write_text(json.dumps(result,indent=2)+'\n');verification=verify_v2_upload(path,source_path);vp=out/'verification.json';vp.write_text(json.dumps(verification,indent=2)+'\n')
    handoff=f'''# Source V2 — separater Uploadhandoff r1

Referenz `kit1-landscape-v5 / gameworld-v2 / source-v2-upload-r1`.
Status: implementiert; CPU-Encode/Decode und Byte-Transport validiert.
Runtime/GPU/Bilder/Leistung und Gesamtabnahme offen; App nicht umgeschaltet.

Source-Manifest-SHA256: `{sha(source_path)}`.
Uploadmanifest: `{str(path.relative_to(ROOT))}`, SHA256 `{sha(path)}`.
Prüfbeleg: `{str(vp.relative_to(ROOT))}`, SHA256 `{sha(vp)}`.
READY bindet sämtliche neuen Ausgabedateien; der Encoderstand ist als
`encoder-source.py` mitgehasht. Alte Source-, Atlas- und V1-Uploadbestände bleiben unverändert.

## Vereinbarte Runtimebindung

Explizit diesen neuen Uploadmanifestpfad im V2-Integrationscheckpoint auswählen.
Alle `payload.path` sind repositoryrelativ mit `path_base=repository_root`.
Nicht relativ zum Source-Datasetordner oder Uploadmanifestordner auflösen.
Jedes Feld besitzt eigene width/height, volle world_min/world_size und Bounds.
Fine-Höhe, Fine-SDF und Fine-RGBA besitzen unterschiedliche Auflösungen.
`domains.detail` ist identischer Alias von `domains.fine`; lokal besitzt keine Höhe.
Bestehende V1-Defaults im Encoder bleiben erhalten. Runtime-.gd-/Shaderdateien wurden nicht geändert.

Gegebene SDF, associated_role und Wasserbytes sind byteidentisch transportiert.
RGBA/Klassen/Waldmetadaten verweisen gehasht auf die unveränderten kanonischen Dateien.
Es wurde keine nearest-vector-SDF ausgeführt, kein Küstenverlauf und kein Waldcache erzeugt.

## Kodierung, Komposition und getrennte Budgets

Höhe: RG8 high/low, `(R*256+G)*0.25-8192` Meter; Clamp verboten,
vorab maximal0.125m Rundung je Pixel und komponierter Höhe.
Alle `{sum(v['pixels_checked'] for v in verification['height_pixel_roundtrip_checks'])}`
originalen Höhenpixel wurden gegen erneut eingelesene Uploadbytes geprüft.
Komponierte Höhenprobes maximal `{verification['height_composed_probe_max_error_m']}`m.

SDF: RG8 high/low, `(R*256+G)*0.125-4096` projizierte Meter,
kanonische Sättigung ±3000m. Zusätzlicher Transportfehler0m,
bestehender Quellkodierungsschritt0.125m/maximale Quellquantisierung0.0625m separat.
Bei Bilinearrekonstruktion und C2 entstehen nur numerische Rundungsreste;
vorab Vergleichstoleranz1e-7m, gemessen `{verification['SDF_transport_composed_probe_max_error_m']}`m.
Dies verbessert keine Native-Quellenpräzision; der vertrauensvolle lokale
Native-Küstenbereich und äußere Quellfusionskragen behalten ihre getrennten Grenzen.

Phi≤0 bedeutet Land. Phi>0 bedeutet Wasser; erst dann diskrete Rolle:0Land,
1Meer,2Inlandwasser. Assoziierte Quelldomänen führen nur1/2; ihre Rollen auf
Land haben keine Wasseraussage. Eigene dokumentierte Integrationsentscheidung:
nearest-Rolle der feinsten räumlich gültigen Domäne bei C2-Gewicht>0,
lokal→fine→context; keine .5-Schwelle und kein Rollenlerp. Kategorische Rollen
sind nicht kontinuierlich. Kontinuierliche SDF/RGBA und Elternhöhe verwenden
das statische Produkt der vier C2-Kantenfaktoren; keine lokale Höhenüberschreibung.
Pixelzentren: uv*N−0.5, äußerer Cachezugriff geclampft, keine extrapolierte Quelle.

Die echten Disk-Decodeprobes decken den äußeren/inneren Halo, winziges/halbes/
volles C2-Gewicht, Core, lokale Nativeküste, Sättigung und alle Kontext-Ecken ab.
Die lokale Inlandwasserprobe9.3351428223E/44.3125437865N bleibt
Phi+53.625m/Rolle2 trotz assoziierter Elternrollen1; negativePhi-Probes bleiben Land.
Rollenabweichungen gegen den kanonischen Sampler: `{verification['role_mismatches']}`.
Keine nichtendlichen Höhen oder ungültigen assoziierten Codes werden aufgefüllt.

## Reproduktion

Vorhandenes Anaconda-Python, keine Installation. Für Neubau freien neuen Revisionspfad wählen:

```sh
/opt/anaconda3/bin/python app/scripts/pack_model_uploads.py --manifest data/gameworld-v2/landscape.json --output-dir artifacts/render-data/source-v2-upload-r1
```

Vorhandenen Freeze ausschließlich lesend prüfen:

```sh
/opt/anaconda3/bin/python app/scripts/pack_model_uploads.py --manifest data/gameworld-v2/landscape.json --output-dir artifacts/render-data/source-v2-upload-r1 --verify-only
```

Keine App-/GPU-Starts, kein Commit/Push durch diesen Auftrag.
'''
    (out/'HANDOFF.md').write_text(handoff)
    ready={'revision':'source-v2-upload-r1','status':'validiert','scope':'offline representation encoding/transport; no active runtime switch','upload_manifest':_v2_ref(path),'verification':_v2_ref(vp),'source_manifest':_v2_ref(source_path),'outputs':[_v2_ref(p) for p in sorted(out.iterdir()) if p.is_file()],'runtime_gpu_visual_acceptance':'offen'}
    (out/'READY.json').write_text(json.dumps(ready,indent=2)+'\n');print(json.dumps({'READY':_v2_ref(out/'READY.json'),'upload_manifest':_v2_ref(path),'verification':_v2_ref(vp)}))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--manifest',type=pathlib.Path,default=ROOT/'data/gameworld-v1/landscape.json');parser.add_argument('--output-dir',type=pathlib.Path);parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    path=args.manifest.resolve();base=path.parent;manifest=json.loads(path.read_text())
    if manifest.get('required_sampling_contract')=='canonical-c2-domains-v2':
        if args.output_dir is None:raise ValueError('V2 requires explicit new --output-dir; source directories are never mutated')
        v2_upload(path,args.output_dir.resolve(),args.verify_only);return
    if args.output_dir is not None or args.verify_only:raise ValueError('--output-dir/--verify-only belong to the separate V2 transport path')
    if 'water_detail_path' in manifest:
        manifest['detail_water_path']=manifest['water_detail_path']
        manifest['detail_water_width']=manifest['water_detail_width']
        manifest['detail_water_height']=manifest['water_detail_height']
    if not manifest.get('core_bounds') or not manifest.get('render_context_bounds'):
        raise ValueError('This encoder requires the canonical reduced gameworld product')
    (base/'upload').mkdir(exist_ok=True)
    domains={'context':{'height':height_upload(base,manifest,'context')}}
    if 'height_detail_path' in manifest: domains['detail']={'height':height_upload(base,manifest,'detail')}
    elif 'detail_water_path' in manifest: domains['detail']={}
    for domain in domains:
        water=water_upload(base,manifest,domain)
        if water: domains[domain]['water_distance']=water
    result={'schema_version':'gameworld-gpu-upload-v1','source_manifest_sha256':sha(path),'domains':domains,'numpy_version':np.__version__,'transform':'representation encoding only; no geometry/generalisation changes'}
    output=base/'upload/upload.json';temporary=output.with_suffix('.tmp');temporary.write_text(json.dumps(result,indent=2)+'\n');temporary.replace(output)
    print(json.dumps({'upload_manifest':str(output),'source_manifest_sha256':result['source_manifest_sha256'],'domains':list(domains)}))

if __name__=='__main__': main()
