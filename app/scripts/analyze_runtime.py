#!/usr/bin/env python3
"""Independent source read + scalar projection checks against actual camera probes."""
import argparse, csv, importlib.util, json, math, mmap, pathlib, struct
p=argparse.ArgumentParser();p.add_argument('run',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
manifest=json.loads((root/'data/derived/landscape.json').read_text())
runtime=json.loads((a.run/'runtime.json').read_text())
spec=importlib.util.spec_from_file_location('expected_projection',pathlib.Path(__file__).with_name('expected_projection.py'))
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
b=manifest['bounds']; hw=manifest['height_detail_width'];hh=manifest['height_detail_height'];ww=manifest['water_detail_width'];wh=manifest['water_detail_height']
with (root/'data/derived'/manifest['height_detail_path']).open('rb') as hf,(root/'data/derived'/manifest['water_detail_path']).open('rb') as wf:
 h=mmap.mmap(hf.fileno(),0,access=mmap.ACCESS_READ);w=mmap.mmap(wf.fileno(),0,access=mmap.ACCESS_READ)
 def height(lon,lat):
  u=(lon-b['west'])/(b['east']-b['west']);v=(b['north']-lat)/(b['north']-b['south'])
  kind=w[min(wh-1,max(0,int(v*wh)))*ww+min(ww-1,max(0,int(u*ww)))]
  x=u*hw-.5;y=v*hh-.5;ix=max(0,min(hw-2,math.floor(x)));iy=max(0,min(hh-2,math.floor(y)));fx=max(0,min(1,x-ix));fy=max(0,min(1,y-iy))
  def e(dx,dy):return struct.unpack_from('<f',h,((iy+dy)*hw+ix+dx)*4)[0]
  raw=(e(0,0)*(1-fx)+e(1,0)*fx)*(1-fy)+(e(0,1)*(1-fx)+e(1,1)*fx)*fy
  return (0.0 if kind==1 else raw),kind
 rows=[]
 for sample in runtime['samples']:
  for probe in sample['anchor_probes']:
   z,kind=height(probe['source_lon'],probe['source_lat'])
   expected=mod.expected_pixel(probe['source_lon'],probe['source_lat'],z,sample,b,kind)
   observed=probe['observed_pixel'];error=math.dist(expected,observed)
   x=math.radians(probe['source_lon']-19)*6371008.8*math.cos(math.radians(41));zz=math.radians(41-probe['source_lat'])*6371008.8
   tile=f'eqc41-km-v1:{math.floor(zz/1000)}:{math.floor(x/1000)}'
   rows.append({'t_ms':sample['t_ms'],'zoom':sample['zoom'],'anchor':probe['anchor_id'],'in_viewport':probe['in_viewport'],'source_height_m':z,'renderer_source_height_m':probe['source_surface_height_m'],'height_read_residual_m':abs(z-probe['source_surface_height_m']),'expected_x_px':expected[0],'expected_y_px':expected[1],'observed_x_px':observed[0],'observed_y_px':observed[1],'screen_residual_px':error,'expected_tile_id':tile,'observed_tile_id':probe['tile_id'],'tile_match':tile==probe['tile_id'],'source_residency':probe.get('source_residency',{}).get('status','unrecorded'),'source_mip_level':probe.get('source_residency',{}).get('mip_level')})
 with (a.run/'anchor-projection.csv').open('w') as out:
  writer=csv.DictWriter(out,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
 summary={'schema_version':'anchor-analysis-v1','method':'independent mmap source bilinear pixel-center read; independent scalar expected projection; observed Camera3D actual state + active terrain triangle CPU probe, not framebuffer feature recognition','sample_count':len(rows),'visible_sample_count':sum(r['in_viewport']for r in rows),'visible_screen_residual_max_px':max((r['screen_residual_px']for r in rows if r['in_viewport']),default=None),'source_height_read_residual_max_m':max(r['height_read_residual_m']for r in rows),
  # Streaming renderers answer from a coarser parent mip until the anchor's block is native;
  # only native reads are comparable to the full-resolution source.
  'source_height_read_residual_native_max_m':max((r['height_read_residual_m']for r in rows if r['source_residency']=='native'),default=None),'source_height_read_residual_parent_fallback_max_m':max((r['height_read_residual_m']for r in rows if r['source_residency']=='parent_fallback'),default=None),'source_residency_counts':{k:sum(r['source_residency']==k for r in rows) for k in sorted({r['source_residency'] for r in rows})},'tile_mismatch_count':sum(not r['tile_match']for r in rows)}
 (a.run/'anchor-analysis.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
