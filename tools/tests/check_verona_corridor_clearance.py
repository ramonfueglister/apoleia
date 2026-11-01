#!/usr/bin/env python3
"""Independent footprint test of authored corridor quads against protected parcels.
Uses polygon clipping, rather than the generator's ray-box width selection.
"""
import json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def norm(v):
 l=math.hypot(*v);return (v[0]/l,v[1]/l) if l else (0,0)
def delta(a,b):return (a[0]-b[0],a[1]-b[1])
def area(poly):return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1])))/2 if len(poly)>2 else 0
def clip(poly,box):
 for axis,bound,sign in [(0,box[0],1),(0,box[2],-1),(1,box[1],1),(1,box[3],-1)]:
  old=poly;poly=[]
  if not old:break
  for a,b in zip(old,old[1:]+old[:1]):
   inside_a=sign*(a[axis]-bound)>=0;inside_b=sign*(b[axis]-bound)>=0
   if inside_a:poly.append(a)
   if inside_a!=inside_b:
    t=(bound-a[axis])/(b[axis]-a[axis]);poly.append(tuple(a[k]+t*(b[k]-a[k]) for k in (0,1)))
 return poly

def run():
 data=json.loads((ROOT/'app/assets/environment/verona_river/profile.json').read_text());audit=json.loads((ROOT/'docs/handover/verona-river/corridor-space.json').read_text())
 points=data['points'];o=data['origin'];edges=[];bad=[];overlap=[];mesh_overlap=[]
 scene=json.loads((ROOT/'docs/handover/verona-river/scene-footprints.json').read_text())
 for i,p in enumerate(points):
  d=norm(delta(p,points[i-1])) if i else norm(delta(points[1],p));e=norm(delta(points[i+1],p)) if i<len(points)-1 else d
  n=(-d[1],d[0]);m=norm((n[0]-e[1],n[1]+e[0]));den=max(m[0]*n[0]+m[1]*n[1],.5);m=(m[0]/den,m[1]/den)
  edges.append([(o[0]+p[0]+side*m[0]*p[3 if side<0 else 4],o[1]+p[1]+side*m[1]*p[3 if side<0 else 4]) for side in [-1,1]])
  if p[3]<.075 or p[4]<.075:bad.append(f'width inside water at {i}')
  if i and p[2]>points[i-1][2]+1e-8:bad.append(f'uphill source station {i}')
 for i in range(len(points)-1):
  quad=[edges[i][0],edges[i+1][0],edges[i+1][1],edges[i][1]]
  lo=[min(v[k] for v in quad) for k in (0,1)];hi=[max(v[k] for v in quad) for k in (0,1)]
  for obj in audit['protected_parcels']:
   b=obj['bounds']
   if hi[0]<b[0] or hi[1]<b[1] or lo[0]>b[2] or lo[1]>b[3]:continue
   a=area(clip(quad,b))
   if a>1e-10:overlap.append({'station':i,'parcel':obj['parcel'],'area_km2':a})
  for obj in scene['buildings']:
   p=obj['aabb_position'];size=obj['aabb_size'];box=[p[0],p[2],p[0]+size[0],p[2]+size[2]]
   if hi[0]<box[0] or hi[1]<box[1] or lo[0]>box[2] or lo[1]>box[3]:continue
   a=area(clip(quad,box))
   if a>1e-10:mesh_overlap.append({'station':i,'building':obj['id'],'area_km2':a})
 report={'status':'authored corridor footprint tested; GPU displacement and visual quality separate','stations':len(points),'protected_parcels':len(audit['protected_parcels']),'minimum_radius_km':min(min(p[3:5]) for p in points),'overlaps':overlap,'instantiated_building_aabb_count':len(scene['buildings']),'building_aabb_overlaps':mesh_overlap,'failures':bad}
 out=ROOT/'build/verona-river/corridor-clearance.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report));return bool(bad or overlap or mesh_overlap)
if __name__=='__main__':raise SystemExit(run())
