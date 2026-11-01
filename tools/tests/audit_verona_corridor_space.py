#!/usr/bin/env python3
"""Conservative atlas parcel clearance from the audited river centreline.
Not a rendered-mesh or elevation audit. Does not authorize moving buildings.
"""
import json,math
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
def ray_box(p,d,box):
 lo,hi=0.,float('inf')
 for k in range(2):
  if abs(d[k])<1e-12:
   if not box[k]<=p[k]<=box[k+2]: return None
  else:
   a=(box[k]-p[k])/d[k];b=(box[k+2]-p[k])/d[k]
   lo=max(lo,min(a,b));hi=min(hi,max(a,b))
 return lo if hi>=lo else None

def run():
 info=json.loads((ROOT/'artifacts/render-data/city-plans-r1/city-plans-x1.json').read_text())
 atlas=Image.open(ROOT/'artifacts/render-data/city-plans-r1'/info['atlas']).convert('RGB')
 slots={(x,y):s for x,y,s in info['page_slots']}; n=info['page_parcels']; columns=info['atlas_slots_per_row']; world=info['world_min']
 def texel(x,y):
  s=slots.get((x//n,y//n))
  return (0,0,0) if s is None else atlas.getpixel(((s%columns)*n+x%n,(s//columns)*n+y%n))
 protected=[]; bridges=[]
 for y in range(6898,6938):
  for x in range(18436,18482):
   k=texel(x,y)[0]
   if 0<k<12:
    row={'parcel':[x,y],'kind':k,'bounds':[world[0]+x*.25,world[1]+y*.25,world[0]+(x+1)*.25,world[1]+(y+1)*.25]}
    (bridges if k==10 else protected).append(row)
 data=json.loads((ROOT/'docs/handover/verona-river/baseline-ordered-profile.json').read_text())
 rows=[]
 for seg in data['ordered_segments']:
  a,b=seg['start'],seg['end'];length=math.dist(a,b);normal=[-(b[1]-a[1])/length,(b[0]-a[0])/length]
  clear=[]
  for side in [-1,1]:
   samples=[]
   for j in range(21):
    p=[a[k]+(b[k]-a[k])*j/20 for k in (0,1)];d=[side*v for v in normal]
    hits=[]
    for obj in protected:
     t=ray_box(p,d,obj['bounds'])
     if t is not None: hits.append((t,obj))
    t,obj=min(hits,key=lambda row:row[0]) if hits else (999,None)
    samples.append({'t':j/20,'clearance_from_center_km':t,'parcel':obj['parcel'] if obj else None,'kind':obj['kind'] if obj else None})
   clear.append({'side':side,'minimum_km':min(s['clearance_from_center_km'] for s in samples),'samples':samples})
  rows.append({'parcel':seg['parcel'],'start':a,'end':b,'sides':clear})
 result={'status':'conservative atlas space audit; not actual footprint validation','water_half_width_km':.075,'protected_parcels':protected,'bridge_parcels_separate':bridges,'segments':rows}
 out=ROOT/'docs/handover/verona-river/corridor-space.json';out.write_text(json.dumps(result,indent=2)+'\n')
 for row in rows:
  if any(s['minimum_km']<.35 for s in row['sides']):print(row['parcel'],[(s['side'],round(s['minimum_km'],4),min(s['samples'],key=lambda q:q['clearance_from_center_km'])['parcel']) for s in row['sides']])
 print('Protected parcels',len(protected),'bridge parcels',len(bridges))
if __name__=='__main__':run()
