#!/usr/bin/env python3
"""Reproducible GPU upload encoding; canonical signed source is unchanged."""
import hashlib,json,pathlib
import numpy as np
root=pathlib.Path(__file__).resolve().parents[2]
source=root/'data/derived/height-detail.f32';meta=root/'data/derived/landscape.json'
out=root/'artifacts/render-data';out.mkdir(parents=True,exist_ok=True)
manifest=json.loads(meta.read_text());source_sha=manifest['assets']['height-detail.f32']['sha256']
policy={'revision':'signed-rg8-quarter-metre-v1','source_sha256':source_sha,'width':manifest['height_detail_width'],'height':manifest['height_detail_height'],'encoding':'R=high byte,G=low byte','minimum_m':-8192.0,'maximum_m':8191.75,'step_m':.25,'maximum_quantization_error_m':.125,'sampling':'decode four nearest texels, then pixel-center bilinear interpolation; marine clamp only after interpolation at query point','canonical_model_scale':.001,'source_mutation':False}
report=out/'height-packing.json';payload=out/'height-rg8.bin'
if report.exists() and payload.exists():
 old=json.loads(report.read_text())
 if old.get('policy')==policy and payload.stat().st_size==policy['width']*policy['height']*2 and hashlib.file_digest(payload.open('rb'),'sha256').hexdigest()==old['payload_sha256']:
  print('Validated existing signed-rg8-quarter-metre-v1 payload');raise SystemExit()
if hashlib.file_digest(source.open('rb'),'sha256').hexdigest()!=source_sha:raise SystemExit('Source hash mismatch')
# Chunking bounds host allocations; never clamp valid source values.
src=np.memmap(source,dtype='<f4',mode='r');tmp=out/'height-rg8.tmp'
max_error=0.;sum_square=0.;minimum=float('inf');maximum=float('-inf');count=0
with tmp.open('wb') as f:
 for i in range(0,len(src),1000000):
  values=np.array(src[i:i+1000000],dtype=np.float64)
  if not np.all(np.isfinite(values)) or np.any(values<policy['minimum_m']) or np.any(values>policy['maximum_m']):raise SystemExit('Source outside signed packing range')
  code=np.floor((values-policy['minimum_m'])/policy['step_m']+.5).astype(np.uint16)
  decoded=code.astype(np.float64)*policy['step_m']+policy['minimum_m'];error=np.abs(decoded-values)
  max_error=max(max_error,float(error.max()));sum_square+=float(np.square(error).sum());count+=len(values);minimum=min(minimum,float(values.min()));maximum=max(maximum,float(values.max()))
  packed=np.empty((len(code),2),dtype=np.uint8);packed[:,0]=code>>8;packed[:,1]=code&255;f.write(packed.tobytes())
if max_error>policy['maximum_quantization_error_m']:raise SystemExit('Predeclared packing budget exceeded')
tmp.replace(payload)
result={'schema_version':'renderer-upload-v1','policy':policy,'payload_path':'height-rg8.bin','payload_sha256':hashlib.file_digest(payload.open('rb'),'sha256').hexdigest(),'source_manifest_sha256':hashlib.file_digest(meta.open('rb'),'sha256').hexdigest(),'texel_count':count,'source_min_m':minimum,'source_max_m':maximum,'quantization_max_m':max_error,'quantization_rms_m':(sum_square/count)**.5,'bytes':payload.stat().st_size,'source_bytes':source.stat().st_size,'numpy_version':np.__version__}
report.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
