#!/usr/bin/env python3
"""Repack a pinned complete-r3 layout into a NEW producer-only v3 identity.
No Source sampler configuration, geometry generation, GPU, or bake. Payload bytes
are copied, validated, and compared; only header binding32bytes and JSON refs change.
"""
from __future__ import annotations
import argparse,hashlib,importlib.util,json,os,shutil,struct,sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('layout_codec',ROOT/'tools/forest_layout_codec.py')
CODEC=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(CODEC)
FORMAT='v19-layout-source-binding-v3'
CONTRACT=ROOT/'app/scripts/cache/forest_layout_source_contract.gd'
COMMON=('source_manifest_sha256','upload_manifest_sha256','source_sampler_sha256','ground_sampler_sha256','canonical_surface_identity_sha256','canonical_surface_gd_json','style_sha256','projection_sha256','template_arrays_sha256','compact_variants','policy','engine_build','numerics','region','metadata_encoding')
def sha(raw):return hashlib.sha256(raw).hexdigest()
def file_sha(path):
 h=hashlib.sha256()
 with Path(path).open('rb') as f:
  while chunk:=f.read(65536):h.update(chunk)
 return h.hexdigest()
def json_bytes(value):return (json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
def load_json(path,limit=1048576):
 p=Path(path)
 if p.stat().st_size>limit:raise ValueError('JSON size cap')
 return json.loads(p.read_bytes())
def ref(root,value,limit):
 if not isinstance(value,dict) or type(value.get('bytes')) is not int or not 0<=value['bytes']<=limit:raise ValueError('reference shape')
 relative=Path(value.get('path',''))
 if relative.is_absolute() or '..' in relative.parts:raise ValueError('reference path')
 p=(root/relative).resolve()
 if not p.is_relative_to(root.resolve()) or p.stat().st_size!=value['bytes'] or file_sha(p)!=value.get('sha256'):raise ValueError('reference hash/size')
 return p
def atomic(path,raw):
 temporary=path.with_name(path.name+'.tmp')
 with temporary.open('xb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
 os.replace(temporary,path)
 fd=os.open(path.parent,os.O_RDONLY)
 try:os.fsync(fd)
 finally:os.close(fd)
def function(source,name,indent=''):
 prefix=indent+'func '+name+'(';lines=[];found=False
 for line in source.split('\n'):
  if not found:
   if line.startswith(prefix):found=True;lines.append(line)
  else:
   if line and not line.startswith(indent+' '):break
   lines.append(line)
 while lines and not lines[-1]:lines.pop()
 return '\n'.join(lines)+'\n' if found else ''
def callbacks():
 source=(ROOT/'app/scripts/cache/fixed_forest_build_context.gd').read_text();names=['_put','role','forest','land','sample'];bodies={};text=''
 for name in names:
  body=function(source,name,'    ')
  if not body:raise ValueError('missing actual callback')
  if name=='sample':
   branch='            if stride!=0:\n                height=ground.height_at(p)*owner_context._display_scale\n'
   if body.count(branch)!=1:raise ValueError('unknown stride0 callback branch')
   body=body.replace(branch,'            # Producer is exactly stride0: height remains original0.0.\n')
  bodies[name]=sha(body.encode());text+=body
 declaration='    const LIMIT=4096'
 if '\n'+declaration+'\n' not in source:raise ValueError('callback memo limit changed')
 text+=declaration+'\n'
 return {'contract':'RequestSamples-stride0-exact-v1','functions':names,'function_sha256':bodies,'sha256':sha(text.encode()),'memo_limit':4096,'source_stride':0,'height_contract':'originalFloat64zero; nonzero-support ground branch unreachable','key_contract':'exact existing Vector2F32 keys; no coordinate quantization'}
def validate_contract(old,new,freeze):
 if new.get('format')!=FORMAT or new.get('metadata_encoding')!=CODEC.METADATA_ENCODING or new.get('source_contract_sha256')!=file_sha(CONTRACT):raise ValueError('new source contract schema/code')
 for key in COMMON:
  if old.get(key)!=new.get(key):raise ValueError('producer dependency changed:'+key)
 if new.get('source_callbacks')!=callbacks():raise ValueError('actual stride0 callback contract mismatch')
 # r3 source callbacks are byte-identical NOW, so removing nonzero ground branch
 # is an evidenced dependency split, not a newly invented sampling implementation.
 context='app/scripts/cache/fixed_forest_build_context.gd'
 if freeze.get(context)!=old.get('sampling_callbacks_sha256') or file_sha(ROOT/context)!=freeze[context]:raise ValueError('r3 original callback implementation not exact')
 product=load_json(ROOT/'app/renderer-binding.json')
 for key,bound in [('source','source_manifest_sha256'),('upload','upload_manifest_sha256'),('atlas','atlas_manifest_sha256')]:
  if new.get(bound)!=product[key]['sha256'] or file_sha(ROOT/product[key]['path'])!=product[key]['sha256']:raise ValueError('static source/upload/G manifest changed')
 for path,key in [('app/scripts/canonical_domains_v2.gd','source_sampler_sha256'),('app/scripts/fixed_display_surface.gd','ground_sampler_sha256'),('app/scripts/style/landscape_style.gd','style_sha256'),('data/projection.json','projection_sha256')]:
  if file_sha(ROOT/path)!=old[key] or freeze.get(path)!=old[key]:raise ValueError('actual original implementation changed:'+path)
 source=(ROOT/'app/scripts/cache/compact_forest_poses.gd').read_text();body=next(('static func '+part for part in source.split('\nstatic func ') if part.startswith('variants(')),None);width=next((line for line in source.split('\n') if line.startswith('const WIDTHS=')),None)
 if not body or not width or sha(body.encode())!=old['compact_variants']['sha256'] or sha(width.encode())!=old['compact_variants']['WIDTHS_declaration_sha256']:raise ValueError('actual variants/widths changed')
 forbidden=['final_ground_consumer_sha256','render_vertex_trace_sha256','terrain_shader_sha256','model_sampling_shader_sha256','runtime_geometry','identity_contract_sha256','binding_loader_sha256','sampling_callbacks_sha256','compact_module_sha256']
 if any(key in new for key in forbidden):raise ValueError('runtime consumer field leaked into source identity')
 return {'exact_r3_original_context_sha256':old['sampling_callbacks_sha256'],'source_callbacks_sha256':new['source_callbacks']['sha256'],'canonical_source_sampler_sha256':old['source_sampler_sha256'],'canonical_G_sampler_sha256':old['ground_sampler_sha256'],'style_sha256':old['style_sha256'],'variants_sha256':old['compact_variants']['sha256'],'templates_sha256':old['template_arrays_sha256'],'claim':'exact canonical source producer dependencies unchanged; nonzero-support ground/display consumers excluded by explicit stride0 branch'}
def compare_after_header(source,destination):
 total=0;h=hashlib.sha256()
 with source.open('rb') as a,destination.open('rb') as b:
  ha=a.read(128);hb=b.read(128)
  if ha[:80]!=hb[:80] or ha[112:]!=hb[112:]:raise ValueError('header modified beyond binding digest')
  while True:
   x=a.read(65536);y=b.read(65536)
   if x!=y:raise ValueError('index/records/metadata changed')
   if not x:break
   h.update(x);total+=len(x)
 return {'bytes_after_header':total,'index_records_metadata_sha256':h.hexdigest(),'bit_identical':True,'only_header_binding_bytes_changed':[80,112]}
def rebind(source,destination,binding,expected_manifest_sha256):
 source=Path(source).resolve();out=Path(destination).resolve();binding=Path(binding).resolve()
 if out.exists():raise ValueError('new output directory required')
 manifest_path=source/'manifest.json'
 if file_sha(manifest_path)!=expected_manifest_sha256:raise ValueError('original manifest pin')
 old_manifest=load_json(manifest_path);ready=load_json(source/'READY.json',4096)
 if ready.get('coverage')!='complete' or ready.get('manifest_sha256')!=expected_manifest_sha256 or old_manifest.get('coverage')!='complete':raise ValueError('original complete READY')
 old_binding_path=ref(source,old_manifest['binding'],1048576);old_binding=load_json(old_binding_path)
 old_layout=ref(source,old_manifest['layout'],CODEC.MAX_FILE)
 verified=CODEC.verify_layout(old_layout,old_binding_path.read_bytes())
 if verified['rows']!=old_manifest.get('record_count') or verified['accepted_layout_records_sha256']!=old_manifest.get('accepted_layout_records_sha256'):raise ValueError('old accepted record/count proof')
 new_binding=load_json(binding);new_raw=CODEC.canonical_binding(new_binding)
 proof=validate_contract(old_binding,new_binding,load_json(source/'freeze.json'))
 out.mkdir(parents=True);temporary=out/'layout.bin.tmp';new_sha=sha(new_raw)
 try:
  with old_layout.open('rb') as src,temporary.open('xb') as dst:
   h=bytearray(src.read(128));h[80:112]=bytes.fromhex(new_sha);dst.write(h)
   while block:=src.read(65536):dst.write(block)
   dst.flush();os.fsync(dst.fileno())
  payload_proof=compare_after_header(old_layout,temporary)
  h=temporary.open('rb').read(128)
  if h[80:112].hex()!=new_sha or len(h)!=128:raise ValueError('new header binding')
  # Old verifier validated all index spans/record hashes/metadata. Exact equality
  # after header proves those same validations on the new file, without bypass.
  os.rename(temporary,out/'layout.bin');atomic(out/'binding.json',new_raw)
  manifest={**old_manifest,'revision':'forest-layout-source-contract-v3-r1','binding':{'path':'binding.json','bytes':len(new_raw),'sha256':new_sha},'layout':{'path':'layout.bin','bytes':(out/'layout.bin').stat().st_size,'sha256':file_sha(out/'layout.bin')},'source_rebind':{'source_manifest':{'path':str(manifest_path.relative_to(ROOT)),'sha256':expected_manifest_sha256},'source_binding_sha256':old_manifest['binding']['sha256'],'tool_sha256':file_sha(Path(__file__)),'source_contract_sha256':file_sha(CONTRACT),'producer_proof':proof,'payload_proof':payload_proof,'no_source_bake':True},'verification':{**old_manifest.get('verification',{}),'producer_consumer_split':'v3 explicit; no runtime cache compatibility exception','index_records_metadata_bit_identical':True}}
  raw=json_bytes(manifest);atomic(out/'manifest.json',raw)
  if file_sha(manifest_path)!=expected_manifest_sha256 or file_sha(old_layout)!=old_manifest['layout']['sha256']:raise ValueError('original changed during repack')
  compare_after_header(old_layout,out/'layout.bin')
  atomic(out/'READY.json',json_bytes({'coverage':'complete','manifest_sha256':sha(raw)}))
  return {'status':'new source-bound revision; same complete payload','manifest_sha256':sha(raw),'binding_sha256':new_sha,'layout_sha256':manifest['layout']['sha256'],'record_count':verified['rows'],'payload_proof':payload_proof,'output':str(out),'source_bake':False}
 except Exception:
  # Keep incomplete new evidence. Never expose READY for a failed validation.
  raise
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',required=True);p.add_argument('--output',required=True);p.add_argument('--binding',required=True);p.add_argument('--source-manifest-sha256',required=True)
 args=p.parse_args();print(json.dumps(rebind(args.source,args.output,args.binding,args.source_manifest_sha256),indent=2))
