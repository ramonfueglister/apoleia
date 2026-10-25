#!/usr/bin/env python3
"""Encode the already generalised world product for GPU upload, never raw DEM.
No downloads/installations. Signed quarter-metre height encoding has an explicit
0.125 m maximum rounding error; source bytes and canonical geometry stay intact.
"""
import argparse, hashlib, json, pathlib, math, time
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

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--manifest',type=pathlib.Path,default=ROOT/'data/gameworld-v1/landscape.json');args=parser.parse_args()
    path=args.manifest.resolve();base=path.parent;manifest=json.loads(path.read_text())
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
