#!/usr/bin/env python3
"""Independent mathematical edge/ridge check of actual runtime LOD inventories.

Read-only product inputs. Reports CPU-contract surface continuity, not GPU
transform-feedback. Different LOD edge heights are measured, never hidden by
assuming that skirt existence implies continuity.
"""
import csv,json,math,pathlib,sys
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[3]
runtime=pathlib.Path(sys.argv[1]).resolve()
outpath=pathlib.Path(sys.argv[2]).resolve()
d=json.loads(runtime.read_text());m=json.loads((ROOT/'data/derived/landscape.json').read_text());b=m['bounds'];R=6371008.8
h=np.memmap(ROOT/'data/derived'/m['height_detail_path'],dtype='<f4',shape=(m['height_detail_height'],m['height_detail_width']))
w=np.memmap(ROOT/'data/derived'/m['water_detail_path'],dtype='u1',shape=(m['water_detail_height'],m['water_detail_width']))
world_min=np.array([math.radians(b['west']-19)*R*math.cos(math.radians(41)),-math.radians(b['north']-41)*R])*.001
world_size=np.array([math.radians(b['east']-b['west'])*R*math.cos(math.radians(41)),math.radians(b['north']-b['south'])*R])*.001

def packed_height(points):
    points=np.asarray(points);uv=(points-world_min)/world_size
    x=np.clip(uv[:,0]*h.shape[1]-.5,0,h.shape[1]-1);y=np.clip(uv[:,1]*h.shape[0]-.5,0,h.shape[0]-1)
    ix=x.astype(int);iy=y.astype(int);xx=np.minimum(ix+1,h.shape[1]-1);yy=np.minimum(iy+1,h.shape[0]-1);fx=x-ix;fy=y-iy
    def quant(a):return np.floor(np.asarray(a,dtype='f8')*4+32768+.5)*.25-8192
    z=(quant(h[iy,ix])*(1-fx)+quant(h[iy,xx])*fx)*(1-fy)+(quant(h[yy,ix])*(1-fx)+quant(h[yy,xx])*fx)*fy
    wx=np.clip((uv[:,0]*w.shape[1]).astype(int),0,w.shape[1]-1);wy=np.clip((uv[:,1]*w.shape[0]).astype(int),0,w.shape[0]-1)
    return np.where(w[wy,wx]==1,0,z)*.001

def triangle(points,step):
    cell=np.floor((points-world_min)/step);origin=world_min+cell*step;f=(points-origin)/step
    a=packed_height(origin);bb=packed_height(origin+np.array([step[0],0]));c=packed_height(origin+np.array([0,step[1]]));dd=packed_height(origin+step)
    return np.where(f[:,0]+f[:,1]<1,a+(bb-a)*f[:,0]+(c-a)*f[:,1],dd+(c-dd)*(1-f[:,0])+(bb-dd)*(1-f[:,1]))

def surface(points,p,relief):
    size=np.array(p['uv_size'])*world_size;t=p['morph_weight']
    return (triangle(points,size/12)*(1-t)+triangle(points,size/24)*t)*relief

def pixels(points,heights,s):
    angle=math.radians(s['elevation_degrees']);k=s['viewport'][0]/s['visible_width_model']
    target=np.array([math.radians(s['center_lon']-19)*R*math.cos(math.radians(41)),-math.radians(s['center_lat']-41)*R])*.001
    return np.column_stack([s['viewport'][0]/2+(points[:,0]-target[0])*k,s['viewport'][1]/2-((heights-s['target_height_model'])*math.cos(angle)-(points[:,1]-target[1])*math.sin(angle))*k])

records=[];summary=[];ridge=[];samples=d['samples']
for snapshot in d.get('lod_snapshots',[]):
    s=min(samples,key=lambda q:abs(q['t_ms']-snapshot['t_ms']));patches=snapshot['patches'];pairs=0;visible_queries=0;maximum=0.;worst=None
    for i,a in enumerate(patches):
        ao=np.array(a['uv_origin']);az=np.array(a['uv_size']);ae=ao+az
        for bb in patches[i+1:]:
            bo=np.array(bb['uv_origin']);bz=np.array(bb['uv_size']);be=bo+bz
            axis=None;constant=None
            if abs(ae[0]-bo[0])<1e-12 or abs(be[0]-ao[0])<1e-12:
                axis=1;constant=ae[0]if abs(ae[0]-bo[0])<1e-12 else be[0]
            elif abs(ae[1]-bo[1])<1e-12 or abs(be[1]-ao[1])<1e-12:
                axis=0;constant=ae[1]if abs(ae[1]-bo[1])<1e-12 else be[1]
            if axis is None:continue
            low=max(ao[axis],bo[axis]);high=min(ae[axis],be[axis])
            if high-low<=1e-12:continue
            pairs+=1
            # Union of both actual edge vertex lattices plus interval midpoints.
            coords=np.unique(np.r_[np.linspace(ao[axis],ae[axis],25),np.linspace(bo[axis],be[axis],25),low,high])
            coords=coords[(coords>=low-1e-12)&(coords<=high+1e-12)]
            coords=np.unique(np.r_[coords,(coords[1:]+coords[:-1])/2])
            uv=np.zeros((len(coords),2));uv[:,axis]=coords;uv[:,1-axis]=constant;points=world_min+uv*world_size
            ha=surface(points,a,snapshot['relief_weight']);hb=surface(points,bb,snapshot['relief_weight']);pix=pixels(points,(ha+hb)/2,s)
            visible=(pix[:,0]>=0)&(pix[:,0]<s['viewport'][0])&(pix[:,1]>=0)&(pix[:,1]<s['viewport'][1])
            gap=np.abs(ha-hb);screen=gap*abs(math.cos(math.radians(s['elevation_degrees'])))*s['viewport'][0]/s['visible_width_model']
            visible_queries+=int(visible.sum())
            for k in np.where(visible)[0]:
                rec=[snapshot['frame'],snapshot['t_ms'],a['id'],bb['id'],a['level'],bb['level'],uv[k,0],uv[k,1],ha[k],hb[k],gap[k],screen[k]]
                records.append(rec)
                if screen[k]>maximum:maximum=float(screen[k]);worst=rec
    summary.append({'frame':snapshot['frame'],'t_ms':snapshot['t_ms'],'adjacent_edge_pairs':pairs,'visible_queries':visible_queries,'maximum_visible_edge_gap_px':maximum,'worst':worst})
for s in samples:
    for p in s.get('ridge_probes',[]):
        lon=p['source_lon'];lat=p['source_lat'];point=np.array([[math.radians(lon-19)*R*math.cos(math.radians(41)),-math.radians(lat-41)*R]])*.001
        source=float(packed_height(point)[0])*s['relief_weight'];actual=p['rendered_height_model']
        ridge.append({'frame':s['frame'],'t_ms':s['t_ms'],'anchor_id':p['anchor_id'],'source_lon':lon,'source_lat':lat,'visible':p['in_viewport'],'packed_source_model_height':source,'cpu_rendered_height_model':actual,'height_residual_source_m':abs(source-actual)/.001,'screen_height_residual_px':abs(source-actual)*abs(math.cos(math.radians(s['elevation_degrees'])))*s['viewport'][0]/s['visible_width_model']})
with outpath.with_suffix('.csv').open('w') as f:
    writer=csv.writer(f);writer.writerow(['frame','t_ms','patch_a','patch_b','level_a','level_b','u','v','height_a_model','height_b_model','gap_model','gap_screen_px']);writer.writerows(records)
visible_ridge=[p for p in ridge if p['visible']]
out={'scope':'Actual runtime patch inventories and declared canonical mesh/morph contract independently evaluated in Float64. Shared-edge heights measured without skirts. Does not claim actual GPU vertex/fragment readback or full ridge-line topology.',
     'runtime':str(runtime),'snapshot_count':len(summary),'visible_edge_query_count':len(records),'snapshots':summary,
     'maximum_visible_edge_gap_px':max((p['maximum_visible_edge_gap_px']for p in summary),default=None),
     'ridge_probe_count':len(ridge),'unique_ridge_ids':sorted(set(p['anchor_id']for p in ridge)),
     'visible_ridge_probe_count':len(visible_ridge),'visible_ridge_maximum_screen_residual_px':max((p['screen_height_residual_px']for p in visible_ridge),default=None),'ridge_probes':ridge}
outpath.write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps({k:out[k]for k in ['snapshot_count','visible_edge_query_count','maximum_visible_edge_gap_px','ridge_probe_count','unique_ridge_ids','visible_ridge_probe_count','visible_ridge_maximum_screen_residual_px']},indent=2))
