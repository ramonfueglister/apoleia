#!/usr/bin/env python3
"""Independent hash and deterministic sample of signed render encoding."""
import hashlib,json,pathlib
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[3]
def read(p):return json.loads((ROOT/p).read_text())
def sha(p):
    with (ROOT/p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
manifest=read('data/derived/landscape.json')
packing=read('artifacts/render-data/height-packing.json')
rows=manifest['height_detail_height'];cols=manifest['height_detail_width']
source=np.memmap(ROOT/'data/derived/height-detail.f32',dtype='<f4',shape=(rows,cols))
packed=np.memmap(ROOT/'artifacts/render-data/height-rg8.bin',dtype='u1',shape=(rows,cols,2))
rng=np.random.default_rng(4107);y=rng.integers(0,rows-1,8192);x=rng.integers(0,cols-1,8192)
fx=rng.random(8192);fy=rng.random(8192);a=np.zeros(8192);b=np.zeros(8192);max_texel=0;byte_errors=0
for dx,dy,w in [(0,0,(1-fx)*(1-fy)),(1,0,fx*(1-fy)),(0,1,(1-fx)*fy),(1,1,fx*fy)]:
    z=np.asarray(source[y+dy,x+dx],dtype='f8');v=packed[y+dy,x+dx]
    q=np.floor(z*4+32768+.5).astype('u4')
    byte_errors+=int(np.count_nonzero((q>>8)!=v[:,0])+np.count_nonzero((q&255)!=v[:,1]))
    decoded=(v[:,0].astype('u4')*256+v[:,1].astype('u4'))/4-8192
    max_texel=max(max_texel,float(np.abs(z-decoded).max()));a+=z*w;b+=decoded*w
out={'kind':'independent-render-encoding-check','runtime_executed':False,'source_manifest_sha256':sha('data/derived/landscape.json'),
    'packing_manifest_sha256':sha('artifacts/render-data/height-packing.json'),
    'payload_sha256':sha('artifacts/render-data/height-rg8.bin'),
    'payload_hash_matches':sha('artifacts/render-data/height-rg8.bin')==packing['payload_sha256'],
    'source_hash_binding_matches':packing['policy']['source_sha256']==manifest['assets']['height-detail.f32']['sha256'],
    'source_manifest_binding_matches':packing['source_manifest_sha256']==sha('data/derived/landscape.json'),
    'independent_seed':4107,'independent_bilinear_queries':8192,'queried_corner_count':32768,'byte_mismatches':byte_errors,
    'sample_texel_error_max_m':max_texel,'sample_bilinear_error_max_m':float(np.abs(a-b).max()),'additional_encoding_budget_m':.125,
    'source_model_scale':manifest['source_to_model_scale'],
    'scope':'Independent deterministic sample and complete artifact hash. Full 121478400-texel mathematical byte comparison is separate data-owner evidence; GPU arithmetic, pixels and mesh/morph need runtime evidence.'}
print(json.dumps(out,indent=2))
