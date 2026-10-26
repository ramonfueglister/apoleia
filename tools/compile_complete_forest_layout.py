#!/usr/bin/env python3
"""Bounded actual Godot-provider supervisor and complete layout publisher.
No RNG/sampler emulation. Execute flags require separately authorized engine/bake work.
"""
from __future__ import annotations
import argparse,hashlib,importlib.util,json,os,selectors,shutil,struct,subprocess,sys,time
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
DRAFT=ROOT/'tools/forest_layout_codec.py'
spec=importlib.util.spec_from_file_location('immutable_layout_draft',DRAFT)
codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(codec)
DEFAULT_CELLS=[(-7,-5),(-6,-5),(-2,2),(-42,-18),(-42,0),(39,0),(0,-18),(0,19)]
FORMAT='v19-layout64-le-r1'
FREEZE_FILES=['tools/compile_complete_forest_layout.py','app/tools/build_complete_forest_layout.gd','app/scripts/style/landscape_style.gd','app/scripts/canonical_domains_v2.gd','app/scripts/fixed_display_surface.gd','app/scripts/cache/fixed_forest_build_context.gd','app/scripts/cache/compact_forest_poses.gd','app/scripts/cache/fixed_forest_layout.gd','app/scripts/cache/fixed_forest_ground.gd','app/scripts/river/river_g_snapshot.gd','app/scripts/cache/compact_forest_identity.gd','app/shaders/terrain.gdshader','app/shaders/model_sampling.gdshaderinc','app/renderer-binding.json','data/projection.json',str(DRAFT.relative_to(ROOT))]

def sha(raw):return hashlib.sha256(raw).hexdigest()
def write_atomic(path,raw):
    path=Path(path);temporary=path.with_name(path.name+'.tmp')
    with temporary.open('xb') as file:file.write(raw);file.flush();os.fsync(file.fileno())
    os.replace(temporary,path)
    fd=os.open(path.parent,os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
def json_raw(value):return (json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
def freeze():
    refs=list(FREEZE_FILES)
    product=json.loads((ROOT/'app/renderer-binding.json').read_text())
    refs.extend(product[key]['path'] for key in ('source','atlas','upload'))
    # Manifests/code only. Actual payload loading/hashing is done by the engine.
    return {name:sha((ROOT/name).read_bytes()) for name in sorted(set(refs))}
def rss_kib(pid):
    result=subprocess.run(['/bin/ps','-o','rss=','-p',str(pid)],text=True,capture_output=True)
    text=result.stdout.strip()
    return int(text) if result.returncode==0 and text else None
def disk_bytes(path):return sum(f.stat().st_size for f in Path(path).rglob('*') if f.is_file())
def checked_relative(root,relative):
    p=Path(relative)
    if p.is_absolute() or '..' in p.parts:raise ValueError('unsafe reference')
    result=(root/p).resolve()
    if not result.is_relative_to(root.resolve()):raise ValueError('reference escaped output')
    return result

def verify_cell(folder,response,binding_sha,seen,*,probe=True):
    cell=tuple(int(x) for x in response['cell'])
    if not (codec.FULL[0]<=cell[0]<codec.FULL[2] and codec.FULL[1]<=cell[1]<codec.FULL[3]):raise ValueError('probe cell outside full coverage')
    if response['binding_sha256']!=binding_sha:raise ValueError('cell binding mismatch')
    payloads={}
    for field in (('records','oracle_records','metadata') if probe else ('records','metadata')):
        ref=response[field];path=checked_relative(folder,ref['path']);size=int(ref['bytes'])
        cap=1369*(72 if field=='oracle_records' else 64) if field!='metadata' else 4096
        if size<0 or size>cap or path.stat().st_size!=size:raise ValueError('bounded spool shape')
        raw=path.read_bytes()
        if sha(raw)!=ref['sha256']:raise ValueError('spool hash')
        payloads[field]=raw
    raw=payloads['records'];oracle=payloads.get('oracle_records');count=int(response['records']['count'])
    if count<0 or count>1369 or len(raw)!=count*64 or (probe and len(oracle)!=count*72):raise ValueError('record count/stride')
    previous=None
    for i in range(count):
        row=codec.ROW.unpack_from(raw,i*64);codec.validate_row(row,cell,seen)
        key=(row[1],row[0])
        if previous is not None and key<=previous:raise ValueError('root scan order')
        previous=key
        if probe:
            original=struct.unpack_from('<ii8d',oracle,i*72)
            if struct.pack('<ii8d',*codec.restore_row(row,0.))!=oracle[i*72:(i+1)*72]:raise ValueError('lossless original record parity')
            if struct.pack('<d',original[7])!=struct.pack('<d',0.):raise ValueError('oracle ground0')
    metadata=json.loads(payloads['metadata'])
    if metadata.get('legacy_ground_support')!=0 or not isinstance(metadata.get('legacy_metadata'),dict) or metadata['legacy_metadata'].get('crown_count')!=count:raise ValueError('metadata support/count')
    for key in ('source_root_sha256','placement_sha256'):
        if len(metadata['legacy_metadata'].get(key,''))!=64:raise ValueError('missing legacy digest')
    if not response.get('engine_record_roundtrip_bit_exact') or not response.get('metadata_full_precision_roundtrip'):raise ValueError('engine parity not established')
    return count

def sha_file(path,guard=lambda:None):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block:=stream.read(65536):guard();h.update(block)
    return h.hexdigest()

def publish_complete(out,entries,binding_raw,*,guard=lambda:None,frozen_files=None):
    """Storage-only complete publication; every3116 visited spool required.
    Used by synthetic tests with synthetic rows in temporary directories only.
    Real CLI passes current freeze and resource/deadline guard after actual provider.
    """
    out=Path(out);expected=list(codec.cells())
    if len(entries)!=3116 or [tuple(x['cell']) for x in entries]!=expected:raise ValueError('complete publication requires every visited cell in canonical order')
    codec.validate_binding(binding_raw);binding_sha=sha(binding_raw)
    seen=bytearray((codec.ROOT_COUNT+7)//8)
    def provider():
        for cell,entry in zip(expected,entries):
            guard();verify_cell(out,entry,binding_sha,seen,probe=False)
            raw=checked_relative(out,entry['records']['path']).read_bytes()
            rows=[codec.restore_row(codec.ROW.unpack_from(raw,i),0.) for i in range(0,len(raw),64)]
            metadata=json.loads(checked_relative(out,entry['metadata']['path']).read_bytes())
            yield cell,rows,metadata
    temporary=out/'layout.bin.tmp';final=out/'layout.bin'
    if final.exists() or temporary.exists() or (out/'manifest.json').exists() or (out/'READY.json').exists():raise ValueError('refuse replacing existing publication')
    storage=codec.write_layout(temporary,provider(),binding_raw)
    guard();verified=codec.verify_layout(temporary,binding_raw);guard()
    if storage['rows']!=verified['rows']:raise ValueError('final codec record count')
    layout_hash=sha_file(temporary,guard)
    if frozen_files is not None and freeze()!=frozen_files:raise ValueError('freeze changed before complete publication')
    os.rename(temporary,final)
    directory_fd=os.open(out,os.O_RDONLY)
    try:os.fsync(directory_fd)
    finally:os.close(directory_fd)
    manifest={'format':FORMAT,'coverage':'complete','chunk_bounds':list(codec.FULL),'root_bounds':list(codec.ROOT),'chunk_count':3116,'record_count':verified['rows'],'layout':{'path':'layout.bin','bytes':storage['file_bytes'],'sha256':layout_hash},'binding':{'path':'binding.json','bytes':len(binding_raw),'sha256':binding_sha},'accepted_digest_encoding':'concat-layout64-rows-index-order-r1','accepted_layout_records_sha256':verified['accepted_layout_records_sha256'],'compiler':{'provider_sha256':sha((ROOT/'app/tools/build_complete_forest_layout.gd').read_bytes()),'supervisor_sha256':sha(Path(__file__).read_bytes()),'storage_codec_sha256':sha(DRAFT.read_bytes()),'frozen_files_sha256':sha(json_raw(frozen_files)) if frozen_files is not None else 'synthetic-storage-fixture-only'},'verification':{'all3116_cells_visited':True,'empty_cells_explicit':True,'global_root_uniqueness_checked':True,'lossless_storage_codec':'immutable v19-complete-layout-plan-r1/draft_codec.py'}}
    guard();raw=json_raw(manifest);write_atomic(out/'manifest.json',raw)
    write_atomic(out/'READY.json',json_raw({'coverage':'complete','manifest_sha256':sha(raw)}))
    return manifest

def compare_probe_rows(out,entries,previous):
    previous=Path(previous).resolve();manifest_path=previous/'manifest.json'
    if manifest_path.stat().st_size>1048576:raise ValueError('previous probe manifest cap')
    old=json.loads(manifest_path.read_text())
    if old.get('coverage')!='incomplete-probe':raise ValueError('comparison requires previous incomplete probe')
    ordered=sorted(entries,key=lambda r:(r['cell'][1],r['cell'][0]))
    if [r['cell'] for r in ordered]!=old.get('visited_cells'):raise ValueError('probe comparison cell set')
    previous_entries={tuple(r['cell']):r for r in old['cells']};count=0
    for entry in ordered:
        before=previous_entries[tuple(entry['cell'])]
        for field in ('records','metadata'):
            cap=1369*64 if field=='records' else 4096
            a=checked_relative(out,entry[field]['path']);b=checked_relative(previous,before[field]['path'])
            if a.stat().st_size>cap or b.stat().st_size>cap or a.read_bytes()!=b.read_bytes():raise ValueError('probe comparison byte difference:'+str(entry['cell'])+':'+field)
        count+=entry['records']['count']
    return {'status':'exact byte equality','previous_probe':str(previous),'cells':len(ordered),'records':count,'rows_byte_identical':True,'metadata_byte_identical':True,'previous_binding_sha256':old['binding']['sha256'],'current_binding_sha256':entries[0]['binding_sha256'],'binding_change_allowed_only_with_fresh_current_factory':True}

def checkpoint(out,responses,binding_sha,complete):
    value={'coverage':'incomplete-build','binding_sha256':binding_sha,'completed_cells':len(responses),'last_cell':responses[-1]['cell'] if responses else None,'checkpoint_scheme':'canonical-prefix+per-cell-checkpoint-r1'} if complete else {'coverage':'incomplete-probe','binding_sha256':binding_sha,'visited_cells':[r['cell'] for r in responses],'cells':responses}
    write_atomic(out/'checkpoint.json',json_raw(value))

def prepare_run(args):
    complete=args.mode=='complete' or args.execute_complete
    if args.execute_probe and complete:raise ValueError('probe execution cannot request complete mode')
    cells=list(codec.cells()) if complete else DEFAULT_CELLS if not args.cells else [tuple(map(int,item.split(','))) for item in args.cells]
    if complete and args.cells:raise ValueError('complete mode never accepts partial cell selection')
    if complete and args.compare_probe:raise ValueError('probe comparison is not complete-build input')
    if not complete and (not 1<=len(cells)<=16 or len(set(cells))!=len(cells)):raise ValueError('one to16 unique probe cells required')
    if any(len(c)!=2 or not (-42<=c[0]<40 and -18<=c[1]<20) for c in cells):raise ValueError('invalid full-region cell')
    if args.resume and not complete:raise ValueError('resume is for interrupted complete-build checkpoints only')
    out=Path(args.output).resolve();frozen=freeze();responses=[];old_binding=None
    if out.exists():
        if not args.resume:raise ValueError('new output or explicit incomplete-build resume required')
        if (out/'READY.json').exists():raise ValueError('published artifacts cannot be resumed/overwritten')
        if json.loads((out/'freeze.json').read_text())!=frozen:raise ValueError('resume input/code freeze changed')
        saved=json.loads((out/'checkpoint.json').read_text()) if (out/'checkpoint.json').exists() else {'completed_cells':0,'coverage':'incomplete-build'}
        if saved.get('coverage')!='incomplete-build':raise ValueError('not a complete-build checkpoint')
        hint=saved.get('completed_cells',0)
        if not isinstance(hint,int) or not 0<=hint<=3116:raise ValueError('resume checkpoint count')
        if (out/'binding.json').exists():
            old_binding=(out/'binding.json').read_bytes();codec.validate_binding(old_binding);seen=bytearray(228390)
            for cell in cells:
                ref=out/'cells'/(str(cell[0])+'_'+str(cell[1]))/'checkpoint.json'
                if not ref.exists():break
                entry=json.loads(ref.read_text())
                if tuple(entry['cell'])!=cell:raise ValueError('resume missing/duplicate/out-of-order cell prefix')
                verify_cell(out,entry,sha(old_binding),seen,probe=False);responses.append(entry)
        if len(responses)<hint:raise ValueError('durable prefix shorter than acknowledged checkpoint')
        # Preserve interrupted attempts, never erase or overwrite earlier evidence.
        archive=out/'attempts'/str(time.time_ns());archive.mkdir(parents=True)
        for name in ('engine.log','command.json','provider-config.json','warmup.json','probe-result.json','build-result.json','layout.bin.tmp','layout.bin','manifest.json'):
            if (out/name).exists():os.rename(out/name,archive/name)
        committed_names={str(cell[0])+'_'+str(cell[1]) for cell in cells[:len(responses)]}
        for folder in (out/'cells').iterdir():
            if folder.name not in committed_names:os.rename(folder,archive/folder.name)
        # Existing ACK files are per-attempt; archive them so no stale ACK advances jobs.
        if (out/'acks').exists():os.rename(out/'acks',archive/'acks')
        (out/'acks').mkdir()
    else:
        if args.resume:raise ValueError('resume output missing')
        out.mkdir(parents=True);(out/'cells').mkdir();(out/'acks').mkdir();write_atomic(out/'freeze.json',json_raw(frozen))
    pending=cells[len(responses):]
    config={'mode':'complete-build' if complete else 'incomplete-probe','repository_root':str(ROOT),'output':str(out),'cells':pending,'resume_from_ordinal':len(responses) if complete else 0,'frozen_files':frozen}
    config_path=out/'provider-config.json';write_atomic(config_path,json_raw(config))
    return complete,cells,pending,out,frozen,responses,old_binding,config_path

def run(args):
    complete,cells,pending,out,frozen,responses,old_binding,config_path=prepare_run(args)
    execute=args.execute_complete if complete else args.execute_probe
    if not execute:
        print(json.dumps({'status':'prepared; engine NOT started','config':str(config_path),'mode':'complete-build' if complete else 'incomplete-probe','pending_cells':len(pending)}));return
    godot=Path(args.godot).expanduser().resolve()
    if not godot.is_file():raise ValueError('Godot executable missing')
    if shutil.disk_usage(out).free<512*1024*1024:raise ValueError('512MiB free disk reservation unavailable')
    command=[str(godot),'--headless','--path',str(ROOT/'app'),'--script',str(ROOT/'app/tools/build_complete_forest_layout.gd'),'--','--config',str(config_path)]
    write_atomic(out/'command.json',json_raw(command))
    disk_before=disk_bytes(out);free_before=shutil.disk_usage(out).free
    started=time.monotonic();last_event=started;warm=None;baseline=None;parent_baseline=None;peak=0;rss_samples=[];seen=bytearray(228390);binding_raw=old_binding;finished=False;failure=None;binding_sha=sha(old_binding) if old_binding else None;resume_count=len(responses);publication=None
    if old_binding:
        for entry in responses:verify_cell(out,entry,binding_sha,seen,probe=False)
    wall=args.max_runtime_seconds if args.max_runtime_seconds is not None else 1800 if complete else 300
    process=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,bufsize=0)
    print(json.dumps({'event':'provider_started','pid':process.pid,'log':str(out/'engine.log'),'mode':'complete-build' if complete else 'incomplete-probe'}),flush=True)
    selector=selectors.DefaultSelector();selector.register(process.stdout,selectors.EVENT_READ);buffer=b'';next_sample=0.;log=(out/'engine.log').open('wb')
    def guard():
        if time.monotonic()-started>wall:raise TimeoutError('overall wall budget')
        parent=rss_kib(os.getpid())
        if parent_baseline is not None and parent is not None and parent-parent_baseline>args.scratch_mib*1024:raise MemoryError('supervisor incremental scratch budget')
        # Admission reserve is512MiB before start; at most384MiB may be consumed before abort.
        if shutil.disk_usage(out).free<128*1024*1024:raise OSError('remaining disk safety floor128MiB')
    try:
        while True:
            now=time.monotonic();guard()
            if warm is None and now-started>args.warmup_timeout:raise TimeoutError('warmup budget')
            if warm is not None and now-last_event>args.cell_timeout:raise TimeoutError('cell progress watchdog')
            if now>=next_sample:
                rss=rss_kib(process.pid);parent=rss_kib(os.getpid());next_sample=now+.05
                if rss is not None:
                    peak=max(peak,rss);sample={'elapsed_seconds':now-started,'rss_kib':rss,'supervisor_rss_kib':parent,'phase':'warmup' if warm is None else 'build'};rss_samples.append(sample)
                    extra=max(0,rss-(baseline or rss))+max(0,(parent or 0)-(parent_baseline or parent or 0))
                    if baseline is not None and extra>args.scratch_mib*1024:raise MemoryError('combined sampled incremental scratch RSS budget')
            for key,event in selector.select(.025):
                block=os.read(key.fileobj.fileno(),65536)
                if not block:selector.unregister(key.fileobj);continue
                log.write(block);log.flush();buffer+=block
                while b'\n' in buffer:
                    line,buffer=buffer.split(b'\n',1)
                    try:value=json.loads(line)
                    except (json.JSONDecodeError,UnicodeDecodeError):continue
                    if not isinstance(value,dict) or 'event' not in value:continue
                    last_event=time.monotonic();print(json.dumps({'event':value['event'],'cell':value.get('cell'),'elapsed_seconds':last_event-started}),flush=True)
                    if value['event']=='warmup_ready':
                        if warm is not None:raise ValueError('duplicate warmup')
                        warm=value;baseline=rss_kib(process.pid);parent_baseline=rss_kib(os.getpid())
                        if baseline is None or parent_baseline is None:raise ValueError('external ps warm RSS unavailable')
                        peak=max(peak,baseline);rss_samples.append({'elapsed_seconds':time.monotonic()-started,'rss_kib':baseline,'supervisor_rss_kib':parent_baseline,'phase':'build'})
                        current_binding=codec.canonical_binding(value['binding']);codec.validate_binding(current_binding)
                        if old_binding is not None and current_binding!=old_binding:raise ValueError('resume actual binding changed')
                        binding_raw=current_binding;binding_sha=sha(binding_raw)
                        if old_binding is None:write_atomic(out/'binding.json',binding_raw)
                        write_atomic(out/'warmup.json',json_raw({**value,'external_ps_rss_kib':baseline,'supervisor_external_ps_rss_kib':parent_baseline,'external_ps_pid':process.pid,'engine_executable_sha256':sha_file(godot)}))
                        write_atomic(out/'acks/warmup',b'ack\n')
                    elif value['event']=='cell_ready':
                        if warm is None or binding_sha is None:raise ValueError('cell before warmup')
                        ordinal=int(value['ordinal'])
                        if ordinal!=len(responses)-resume_count or tuple(value['cell'])!=pending[ordinal]:raise ValueError('cell omission/duplicate/order')
                        cell=pending[ordinal];folder=Path(value['folder']).resolve();expected=(out/'cells'/('.'+str(cell[0])+'_'+str(cell[1])+'.tmp')).resolve()
                        if folder!=expected:raise ValueError('provider spool path mismatch')
                        verify_cell(folder,value,binding_sha,seen,probe=not complete)
                        for f in folder.iterdir():
                            with f.open('rb') as stream:os.fsync(stream.fileno())
                        final=out/'cells'/(str(cell[0])+'_'+str(cell[1]));os.rename(folder,final)
                        directory_fd=os.open(final.parent,os.O_RDONLY)
                        try:os.fsync(directory_fd)
                        finally:os.close(directory_fd)
                        entry={k:v for k,v in value.items() if k not in ('event','folder','ordinal')}
                        for field in (('records','metadata') if complete else ('records','oracle_records','metadata')):entry[field]={**entry[field],'path':str((final/entry[field]['path']).relative_to(out))}
                        write_atomic(final/'checkpoint.json',json_raw(entry));responses.append(entry);checkpoint(out,responses,binding_sha,complete)
                        write_atomic(out/'acks'/('cell_'+str(ordinal)),b'ack\n')
                    elif value['event']=='cell_verified':
                        ordinal=int(value['ordinal'])
                        if complete or ordinal!=len(responses)-1 or tuple(value['cell'])!=tuple(responses[ordinal]['cell']) or not value.get('disk_vs_fresh_direct_records_bit_exact') or not value.get('disk_vs_fresh_direct_metadata_bytes_exact'):raise ValueError('fresh direct API disk replay parity')
                        responses[ordinal].update({key:val for key,val in value.items() if key not in ('event','ordinal','cell')})
                        final=out/'cells'/(str(pending[ordinal][0])+'_'+str(pending[ordinal][1]));write_atomic(final/'checkpoint.json',json_raw(responses[ordinal]));checkpoint(out,responses,binding_sha,complete)
                    elif value['event']=='provider_error':raise RuntimeError(value['reason'])
                    elif value['event'] in ('probe_complete','generation_complete'):
                        if not value.get('input_freeze_unchanged') or value.get('binding_sha256')!=binding_sha or len(responses)!=len(cells):raise ValueError('incomplete provider finish/freeze')
                        if not complete and not all(r.get('disk_vs_fresh_direct_records_bit_exact') and r.get('disk_vs_fresh_direct_metadata_bytes_exact') for r in responses):raise ValueError('incomplete probe parity')
                        finished=True
            if process.poll() is not None and not selector.get_map():break
        if process.returncode!=0 or not finished:raise RuntimeError('engine exit/generation completion')
        log.flush()
        if any(marker in (out/'engine.log').read_text(errors='replace') for marker in ('ERROR:','SCRIPT ERROR:')):raise RuntimeError('engine log contains errors; no publication')
        if freeze()!=frozen:raise ValueError('inputs changed during build')
        guard()
        if complete:publication=publish_complete(out,responses,binding_raw,guard=guard,frozen_files=frozen)
        else:
            published_cells=sorted(responses,key=lambda r:(r['cell'][1],r['cell'][0]))
            if args.compare_probe:write_atomic(out/'probe-comparison.json',json_raw(compare_probe_rows(out,published_cells,args.compare_probe)))
            manifest={'format':FORMAT,'coverage':'incomplete-probe','chunk_bounds':list(codec.FULL),'root_bounds':list(codec.ROOT),'chunk_count':len(responses),'record_count':sum(r['records']['count'] for r in responses),'binding':{'path':'binding.json','bytes':len(binding_raw),'sha256':binding_sha},'visited_cells':[r['cell'] for r in published_cells],'cells':published_cells,'accepted_digest_encoding':'concat-layout64-rows-index-order-r1','note':'Sparse actual probe ONLY. Unvisited cells unknown; no full layout/index or complete bake.'}
            h=hashlib.sha256()
            for entry in published_cells:h.update(checked_relative(out,entry['records']['path']).read_bytes())
            manifest['accepted_layout_records_sha256']=h.hexdigest();raw=json_raw(manifest);write_atomic(out/'manifest.json',raw);write_atomic(out/'READY.json',json_raw({'coverage':'incomplete-probe','manifest_sha256':sha(raw)}));publication=manifest
    except Exception as error:
        failure=str(error)
        if process.poll() is None:process.terminate()
    finally:
        try:process.wait(timeout=5)
        except subprocess.TimeoutExpired:process.kill();process.wait()
        selector.close();log.close();elapsed=time.monotonic()-started
        builds=[r['build_usec']/1e6 for r in responses];after_warm=[s['rss_kib'] for s in rss_samples if s['phase']=='build'];combined=[max(0,s['rss_kib']-(baseline or s['rss_kib']))+max(0,(s.get('supervisor_rss_kib') or 0)-(parent_baseline or s.get('supervisor_rss_kib') or 0)) for s in rss_samples if s['phase']=='build']
        result={'status':('complete layout published' if complete else 'partial real probe validated; full bake NOT authorized') if failure is None else 'build failed; incomplete checkpoint retained','failure':failure,'mode':'complete-build' if complete else 'incomplete-probe','pid':process.pid,'engine_exit':process.returncode,'elapsed_seconds':elapsed,'source_baseline_external_ps_rss_kib':baseline,'supervisor_baseline_external_ps_rss_kib':parent_baseline,'sampled_peak_external_ps_rss_kib':peak,'sampled_incremental_child_scratch_peak_kib':max(0,max(after_warm,default=baseline or 0)-(baseline or 0)) if baseline is not None else None,'sampled_combined_incremental_scratch_peak_kib':max(combined,default=0),'rss_method':'external /bin/ps child+supervisor RSS; sampled50ms nominal, not OS high-water proof','rss_samples':rss_samples,'cells_completed':len(responses),'cells_reused':resume_count,'records':sum(r['records']['count'] for r in responses),'cell_build_seconds':builds,'build_only_records_per_second':sum(r['records']['count'] for r in responses)/sum(builds) if sum(builds)>0 else None,'output_disk_delta_bytes':disk_bytes(out)-disk_before,'filesystem_free_delta_bytes':free_before-shutil.disk_usage(out).free,'disk_note':'logical own-output delta includes summary; filesystem free delta may include concurrent jobs','budgets':{'wall_seconds':wall,'warmup_seconds':args.warmup_timeout,'cell_watchdog_seconds':args.cell_timeout,'combined_incremental_scratch_mib':args.scratch_mib,'disk_admission_mib':512,'disk_abort_floor_mib':128,'workers':1},'source_payload_residency_bytes':warm.get('source_field_payload_bytes') if warm else None,'surface_payload_residency_bytes':warm.get('surface_payload_bytes') if warm else None,'full_bake_started':complete}
        base_output_delta=disk_bytes(out)-disk_before
        for _ in range(8):
            actual=base_output_delta+len(json_raw(result))
            if result['output_disk_delta_bytes']==actual:break
            result['output_disk_delta_bytes']=actual
        write_atomic(out/('build-result.json' if complete else 'probe-result.json'),json_raw(result));print(json.dumps({k:v for k,v in result.items() if k!='rss_samples'},indent=2))
    if failure:raise SystemExit(2)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True);parser.add_argument('--mode',choices=['probe','complete'],default='probe');parser.add_argument('--resume',action='store_true')
    execution=parser.add_mutually_exclusive_group();execution.add_argument('--execute-probe',action='store_true');execution.add_argument('--execute-complete',action='store_true',help='Run ONLY after explicit Root full-bake authorization and final dependency freeze')
    parser.add_argument('--compare-probe',help='probe-only prior artifact; require all accepted row and metadata bytes exactly equal before READY publication')
    parser.add_argument('--godot',default='/Applications/Godot.app/Contents/MacOS/Godot');parser.add_argument('--cells',nargs='*',help='probe-only explicit x,z cells, max16; complete always all3116')
    parser.add_argument('--max-runtime-seconds',type=float,default=None,help='default300 probe /1800 complete');parser.add_argument('--warmup-timeout',type=float,default=180);parser.add_argument('--cell-timeout',type=float,default=15);parser.add_argument('--scratch-mib',type=int,default=64)
    run(parser.parse_args())
