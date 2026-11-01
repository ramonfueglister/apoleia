#!/usr/bin/env python3
"""Bounded bank widths from audited protected atlas parcels, not invented geography."""
import json, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'app/assets/environment/verona_river/profile.json'
d=json.loads(p.read_text()); audit=json.loads((ROOT/'docs/handover/verona-river/corridor-space.json').read_text())
points=d['points']; origin=d['origin']; rects=[r['bounds'] for r in audit['protected_parcels']]
def unit(v):
 l=math.hypot(*v);return (v[0]/l,v[1]/l)
def normal(i):
 a=points[max(0,i-1)];b=points[i];c=points[min(len(points)-1,i+1)]
 u=unit((b[0]-a[0],b[1]-a[1])) if i else unit((c[0]-b[0],c[1]-b[1]))
 v=unit((c[0]-b[0],c[1]-b[1])) if i<len(points)-1 else u
 n=(-u[1],u[0]);m=unit((n[0]-v[1],n[1]+v[0]));den=max(m[0]*n[0]+m[1]*n[1],.5)
 return(m[0]/den,m[1]/den)
def entry(q,n,r):
 lo,hi=0.,math.inf
 for k in range(2):
  a,b=r[k]-.015,r[k+2]+.015
  if abs(n[k])<1e-9:
   if not a<=q[k]<=b:return math.inf
  else:
   x,y=(a-q[k])/n[k],(b-q[k])/n[k]
   lo=max(lo,min(x,y));hi=min(hi,max(x,y))
 return lo if hi>=lo else math.inf
widths=[]
for i,pt in enumerate(points):
 n=normal(i);q=(pt[0]+origin[0],pt[1]+origin[1]);ws=[]
 for side in [-1,1]:ws.append(min(.40,min(entry(q,(n[0]*side,n[1]*side),r) for r in rects)))
 widths.append(ws)
# Width never exceeds measured clearance; constrain widening to a 1:1 slope.
for side in range(2):
 for indices in [range(1,len(points)),range(len(points)-2,-1,-1)]:
  for i in indices:
   prev=i-1 if indices.step>0 else i+1
   length=math.dist(points[i][:2],points[prev][:2])
   widths[i][side]=min(widths[i][side],widths[prev][side]+length*.65)
assert min(min(w) for w in widths)>.09
for pt,w in zip(points,widths):pt[3:]=w
# Explicit design: smooth lower-only ground interpolation inside this bounded width.
d['corridor']={'maximum_radius_km':.40,'protected_parcel_margin_km':.015,'minimum_radius_km':min(min(w) for w in widths),'width_gradient_limit':.65,'source':'docs/handover/verona-river/corridor-space.json','protected_parcels':[r['parcel'] for r in audit['protected_parcels']]}
# Regular quarter-aligned grid covers every potential corrected bank fragment.
# Store integer cells to keep runtime free of a large spatial search.
grid=.025; world_min=(-5286.959516530886,-2223.9016046706583)
cells=set()
for pt,w in zip(points,widths):
 q=(pt[0]+origin[0],pt[1]+origin[1]);radius=max(w)+.04
 x0=math.floor((q[0]-radius-world_min[0])/grid);x1=math.floor((q[0]+radius-world_min[0])/grid)
 y0=math.floor((q[1]-radius-world_min[1])/grid);y1=math.floor((q[1]+radius-world_min[1])/grid)
 for y in range(y0,y1+1):
  for x in range(x0,x1+1):
   cx=world_min[0]+(x+.5)*grid;cy=world_min[1]+(y+.5)*grid
   if math.hypot(cx-q[0],cy-q[1])<=radius:cells.add((x,y))
d['corridor']['grid_km']=grid
base_index=[round((origin[i]-world_min[i])/grid) for i in range(2)]
d['corridor']['shore_cells']=[[cell[0]-base_index[0],cell[1]-base_index[1]] for cell in sorted(cells,key=lambda q:(q[1],q[0]))]
p.write_text(json.dumps(d,indent=2)+'\n')
print({key:value for key,value in d['corridor'].items() if key not in ['shore_cells','protected_parcels']});print('shore cells',len(cells))
