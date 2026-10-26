#!/usr/bin/env python3
"""Independent source/mesh equations against actual runtime patch and motion records.
Reports sampled evidence, never a global GPU topology proof.
"""
import argparse,csv,functools,importlib.util,json,math,mmap,pathlib,struct
p=argparse.ArgumentParser();p.add_argument('run',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];m=json.loads((root/'data/derived/landscape.json').read_text());r=json.loads((a.run/'runtime.json').read_text());b=m['bounds'];W=m['height_detail_width'];H=m['height_detail_height'];WW=m['water_detail_width'];WH=m['water_detail_height']
files=[(root/'data/derived/height-detail.f32').open('rb'),(root/'artifacts/render-data/height-rg8.bin').open('rb'),(root/'data/derived/water-detail.u8').open('rb')]
raw,gpu,water=[mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)for f in files]
spec=importlib.util.spec_from_file_location('projection',pathlib.Path(__file__).with_name('expected_projection.py'));project=importlib.util.module_from_spec(spec);spec.loader.exec_module(project)
@functools.lru_cache(maxsize=500000)
def surface(u,v,packed=True):
 u=max(0.,min(1.,u));v=max(0.,min(1.,v));kind=water[min(WH-1,int(v*WH))*WW+min(WW-1,int(u*WW))]
 if kind==1:return 0.
 x=u*W-.5;y=v*H-.5;ix=max(0,min(W-2,math.floor(x)));iy=max(0,min(H-2,math.floor(y)));fx=max(0,min(1,x-ix));fy=max(0,min(1,y-iy))
 def sample(dx,dy):
  i=(iy+dy)*W+ix+dx
  return struct.unpack_from('>H',gpu,i*2)[0]*.25-8192 if packed else struct.unpack_from('<f',raw,i*4)[0]
 return ((sample(0,0)*(1-fx)+sample(1,0)*fx)*(1-fy)+(sample(0,1)*(1-fx)+sample(1,1)*fx)*fy)*.001

def triangle(u,v,sx,sy):
 x=math.floor(u/sx)*sx;y=math.floor(v/sy)*sy;fx=(u-x)/sx;fy=(v-y)/sy
 aa=surface(x,y);bb=surface(x+sx,y);cc=surface(x,y+sy);dd=surface(x+sx,y+sy)
 return aa+(bb-aa)*fx+(cc-aa)*fy if fx+fy<1 else dd+(cc-dd)*(1-fx)+(bb-dd)*(1-fy)
def mesh_height(u,v,patch):
 sx,sy=patch['uv_size'];w=patch['morph_weight']
 return triangle(u,v,sx/12,sy/12)*(1-w)+triangle(u,v,sx/24,sy/24)*w

def source_uv(lon,lat):return (lon-b['west'])/(b['east']-b['west']),(b['north']-lat)/(b['north']-b['south'])
def pixel(u,v,height,sample):return project.expected_pixel(b['west']+u*(b['east']-b['west']),b['north']-v*(b['north']-b['south']),height/.001,sample,b,0)
byframe={s['frame']:s for s in r['samples']};seams=[]
for shot in r.get('lod_snapshots',[]):
 sample=byframe[shot['frame']];patches=shot['patches']
 for i,pa in enumerate(patches):
  ax,ay=pa['uv_origin'];aw,ah=pa['uv_size']
  for pb in patches[i+1:]:
   bx,by=pb['uv_origin'];bw,bh=pb['uv_size'];line=None
   if (ax+aw==bx or bx+bw==ax) and min(ay+ah,by+bh)>max(ay,by):line=('vertical',max(ax,bx),max(ay,by),min(ay+ah,by+bh))
   if (ay+ah==by or by+bh==ay) and min(ax+aw,bx+bw)>max(ax,bx):line=('horizontal',max(ay,by),max(ax,bx),min(ax+aw,bx+bw))
   if line is None:continue
   for j in range(9):
    t=line[2]+(line[3]-line[2])*j/8;u,v=(line[1],t)if line[0]=='vertical' else(t,line[1]);ha=mesh_height(u,v,pa)*sample['relief_weight'];hb=mesh_height(u,v,pb)*sample['relief_weight'];x,y=pixel(u,v,(ha+hb)/2,sample);visible=0<=x<sample['viewport'][0]and 0<=y<sample['viewport'][1];error=abs(ha-hb)*math.cos(math.radians(sample['elevation_degrees']))*sample['viewport'][0]/sample['visible_width_model']
    seams.append({'frame':shot['frame'],'t_ms':shot['t_ms'],'zoom':shot['zoom'],'patch_a':pa['id'],'patch_b':pb['id'],'level_a':pa['level'],'level_b':pb['level'],'morph_a':pa['morph_weight'],'morph_b':pb['morph_weight'],'u':u,'v':v,'height_a_model':ha,'height_b_model':hb,'gap_source_m':abs(ha-hb)/.001,'gap_px':error,'in_viewport':visible,'edge_xy_residual_uv':0.0})

def write(name,rows):
 if not rows:return
 with(a.run/name).open('w')as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
write('lod-seam-pairs.csv',seams)
motion=[];previous={}
for s in r.get('motion_probes',[]):
 for point in s['points']:
  u,v=source_uv(point['source_lon'],point['source_lat']);height=surface(u,v,False)/.001;expected=project.expected_pixel(point['source_lon'],point['source_lat'],height,s,b,0);observed=point['observed_pixel'];old=previous.get(point['anchor_id'])
  if old and point['in_viewport']and old['visible']:
   delta=math.hypot((observed[0]-old['observed'][0])-(expected[0]-old['expected'][0]),(observed[1]-old['observed'][1])-(expected[1]-old['expected'][1]))
   motion.append({'frame':s['frame'],'t_ms':s['t_ms'],'anchor_id':point['anchor_id'],'zoom':s['zoom'],'transition_residual_px':delta,'frame_interval_ms':s['t_ms']-old['t_ms']})
  previous[point['anchor_id']]={'visible':point['in_viewport'],'observed':observed,'expected':expected,'t_ms':s['t_ms']}
write('motion-transition.csv',motion)
ridges=[]
for s in r['samples']:
 for point in s.get('ridge_probes',[]):
  ridges.append({'frame':s['frame'],'t_ms':s['t_ms'],'anchor_id':point['anchor_id'],'zoom':s['zoom'],'in_viewport':point['in_viewport'],'source_height_m':point['source_surface_height_m'],'rendered_height_model':point['rendered_height_model'],'tile_id':point['tile_id']})
write('ridge-window-probes.csv',ridges)
summary={'schema_version':'lod-motion-samples-v1','method':'independent canonical signed-source/packed corner decode, parent/fine triangle interpolation against actual runtime binary-UV patch/morph inventories; nine correspondence points per shared edge; visible-pixel criteria; no GPU vertex readback or global topology proof','snapshot_count':len(r.get('lod_snapshots',[])),'seam_samples':len(seams),'visible_seam_samples':sum(s['in_viewport']for s in seams),'visible_seam_gap_max_px':max((s['gap_px']for s in seams if s['in_viewport']),default=None),'all_seam_source_gap_max_m':max((s['gap_source_m']for s in seams),default=None),'dense_motion_frame_count':len(r.get('motion_probes',[])),'visible_transition_samples':len(motion),'transition_residual_max_px':max((x['transition_residual_px']for x in motion),default=None),'ridge_anchor_count':len(set(x['anchor_id']for x in ridges)),'ridge_visible_counts':{key:sum(x['in_viewport']for x in ridges if x['anchor_id']==key)for key in sorted(set(x['anchor_id']for x in ridges))}}
(a.run/'lod-motion-analysis.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
