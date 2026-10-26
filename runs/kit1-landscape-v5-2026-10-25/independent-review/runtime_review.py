#!/usr/bin/env python3
"""Read-only analysis of real renderer telemetry; no renderer imports."""
import hashlib,json,math,pathlib,sys
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[3]
path=pathlib.Path(sys.argv[1]).resolve()
data=json.loads(path.read_text())
manifest=json.loads((ROOT/'data/derived/landscape.json').read_text());b=manifest['bounds']
h=np.memmap(ROOT/'data/derived'/manifest['height_detail_path'],dtype='<f4',shape=(manifest['height_detail_height'],manifest['height_detail_width']))
w=np.memmap(ROOT/'data/derived'/manifest['water_detail_path'],dtype='u1',shape=(manifest['water_detail_height'],manifest['water_detail_width']))
R=6371008.8
expected_tiles=json.loads((ROOT/'data/expected-tiles.json').read_text())
tiles={q['anchor_id']:q['expected']['canonical_tile_id']for q in expected_tiles['probes']}

def independent_height(lon,lat):
    u=(lon-b['west'])/(b['east']-b['west']);v=(b['north']-lat)/(b['north']-b['south'])
    kind=int(w[min(w.shape[0]-1,max(0,int(v*w.shape[0]))),min(w.shape[1]-1,max(0,int(u*w.shape[1])))])
    if kind==1:return 0.0
    x=min(h.shape[1]-1,max(0,u*h.shape[1]-.5));y=min(h.shape[0]-1,max(0,v*h.shape[0]-.5))
    ix=int(x);iy=int(y);xx=min(ix+1,h.shape[1]-1);yy=min(iy+1,h.shape[0]-1);fx=x-ix;fy=y-iy
    return float((h[iy,ix]*(1-fx)+h[iy,xx]*fx)*(1-fy)+(h[yy,ix]*(1-fx)+h[yy,xx]*fx)*fy)

def pixel(s,a,height):
    k=s['viewport'][0]/s['visible_width_model'];angle=math.radians(s['elevation_degrees'])
    x=R*math.cos(math.radians(41))*math.radians(a['source_lon']-s['center_lon'])*.001
    z=-R*math.radians(a['source_lat']-s['center_lat'])*.001
    return np.array([s['viewport'][0]/2+x*k,s['viewport'][1]/2-((height-s['target_height_model'])*math.cos(angle)-z*math.sin(angle))*k])

mapping=[];screen=[];transitions=[];tile_errors=[];previous={};visible={};heights={}
for s in data['samples']:
    for a in s['anchor_probes']:
        ident=a['anchor_id']
        if a['tile_id']!=tiles[ident]:tile_errors.append({'frame':s['frame'],'anchor_id':ident,'observed':a['tile_id'],'expected':tiles[ident]})
        if ident not in heights:heights[ident]=independent_height(a['source_lon'],a['source_lat'])
        observed=np.array(a['observed_pixel'])
        proj_expected=pixel(s,a,a['rendered_height_model'])
        expected=pixel(s,a,heights[ident]*.001*s['relief_weight'])
        if a['in_viewport']:
            visible.setdefault(ident,[]).append(s['zoom'])
            mapping.append({'error_px':float(np.linalg.norm(observed-proj_expected)),'frame':s['frame'],'t_ms':s['t_ms'],'anchor_id':ident,'zoom':s['zoom']})
            residual=observed-expected
            screen.append({'error_px':float(np.linalg.norm(residual)),'frame':s['frame'],'t_ms':s['t_ms'],'anchor_id':ident,'zoom':s['zoom']})
            if ident in previous:
                prev=previous[ident]
                transitions.append({'residual_change_px':float(np.linalg.norm(residual-prev['residual'])),'anchor_id':ident,'frame':s['frame'],'previous_frame':prev['frame'],'dt_ms':s['t_ms']-prev['t_ms']})
            previous[ident]={'residual':residual,'frame':s['frame'],'t_ms':s['t_ms']}
        else:previous.pop(ident,None)
frames=data.get('frame_intervals_ms',[]);sorted_frames=sorted(frames)
motion_previous={};motion_results=[]
for s in data.get('motion_probes',[]):
    for p in s['points']:
        ident=p['anchor_id']
        if not p['in_viewport']:
            motion_previous.pop(ident,None)
            continue
        if ident not in heights:heights[ident]=independent_height(p['source_lon'],p['source_lat'])
        expected=pixel(s,p,heights[ident]*.001*s['relief_weight'])
        residual=np.array(p['observed_pixel'])-expected
        if ident in motion_previous:
            prev=motion_previous[ident]
            motion_results.append({'anchor_id':ident,'frame':s['frame'],'previous_frame':prev['frame'],
                'dt_ms':s['t_ms']-prev['t_ms'],'residual_change_px':float(np.linalg.norm(residual-prev['residual']))})
        motion_previous[ident]={'frame':s['frame'],'t_ms':s['t_ms'],'residual':residual}
percentiles={}
if frames:
    percentiles={k:sorted_frames[min(len(frames)-1,int(len(frames)*q))]for k,q in [('p50',.5),('p95',.95),('p99',.99)]}
    percentiles['max']=max(frames)
rss_path=path.parent/'process-rss.json'
rss=json.loads(rss_path.read_text())if rss_path.exists()else None
out={'kind':'independent-runtime-raw-analysis','raw_path':str(path),'raw_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
     'dataset_revision':data['dataset_revision'],'manifest_sha256':data['manifest_sha256'],'renderer_source_sha256':data['renderer_source_sha256'],
     'renderer_asset_sha256':data.get('renderer_asset_sha256',{}),'profile_sha256':data['profile_sha256'],'packing_manifest_sha256':data.get('packing_manifest_sha256'),
     'rendering_method':data['rendering_method'],'duration_seconds':data['duration_seconds'],'frame_count':data['frame_count'],
     'all_frame_intervals_count':len(frames),'all_frame_ms_independent':percentiles,
     'peak_gpu_monitor_bytes':max(s['gpu_memory_bytes']for s in data['samples']),
     'peak_process_rss_bytes':rss['peak_rss_bytes']if rss else None,
     'rss_raw_sha256':hashlib.sha256(rss_path.read_bytes()).hexdigest()if rss else None,
     'integrity_passed':data['integrity_passed'],'tile_observation_count':sum(len(s['anchor_probes'])for s in data['samples']),
     'tile_mismatches':tile_errors,'mapping_maximum':max(mapping,key=lambda r:r['error_px'])if mapping else None,
     'source_to_render_screen_maximum':max(screen,key=lambda r:r['error_px'])if screen else None,
     'sampled_transition_residual_maximum':max(transitions,key=lambda r:r['residual_change_px'])if transitions else None,
     'per_frame_motion_sample_count':len(data.get('motion_probes',[])),
     'per_frame_motion_visible_consecutive_pairs':len(motion_results),
     'per_frame_motion_residual_maximum':max(motion_results,key=lambda r:r['residual_change_px'])if motion_results else None,
     'wall_interval_max_excluding_initial_engine_delta_ms':max(frames[1:])if len(frames)>1 else None,
     'initial_interval_source':'First raw interval is engine delta fallback, not observed inter-frame wall time; retained in raw and all-frame percentile calculation',
     'visible_anchor_zoom_ranges':{key:{'count':len(v),'minimum':min(v),'maximum':max(v)}for key,v in visible.items()},
     'actual_start':{k:data['samples'][0][k]for k in ['zoom','center_lon','center_lat','relief_weight','viewport']},
     'actual_return':{k:data['samples'][-1][k]for k in ['zoom','center_lon','center_lat','relief_weight','viewport']},
     'pipeline_events':data.get('pipeline_events',[]),'pipeline_counts_final':data.get('pipeline_counts_final',{}),
     'interaction_events':data.get('interaction_events',[]),
     'limitations':'Real Camera3D probes are CPU projections of CPU-evaluated active terrain; no independent GPU transform-feedback or framebuffer feature detection. Mapping compares scalar math with actual Camera3D output. Source screen error uses independently sampled original signed detail grid plus profile relief. Transition residual is change in observed-minus-expected residual at consecutive visible telemetry samples, subtracting legitimate camera movement; it is sampled, not full-frame mesh or ridge/seam proof.'}
print(json.dumps(out,indent=2))
