#!/usr/bin/env python3
"""Check hydrological/geometry constraints of the bounded display profile."""
import json
import math
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_verona_river_profile import build
source=json.loads((ROOT/'docs/handover/verona-river/baseline-ordered-profile.json').read_text())
raw=build(source,conditioned=False)['points']
expected=build(source)['points']
data=json.loads((ROOT/'app/assets/environment/verona_river/profile.json').read_text())
actual=[p[:3] for p in data['points']]
assert actual==expected,'Runtime profile differs from reproducible source builder'
assert all(a[:2]==b[:2] for a,b in zip(raw,actual)),'Geographic centreline moved'
assert actual[0][2]==raw[0][2] and actual[-1][2]==raw[-1][2],'Endpoint join changed'
assert all(b[2]<=a[2]+1e-9 for a,b in zip(raw,actual)),'Conditioning raised water'
assert all(a[2]>=b[2]-1e-9 for a,b in zip(actual,actual[1:])),'Downstream rise'
arc=[0.]
for a,b in zip(actual,actual[1:]):arc.append(arc[-1]+math.dist(a[:2],b[:2]))
bends=[]
for i in range(1,len(actual)-1):
 a,b,c=actual[i-1:i+2];u=(b[0]-a[0],b[1]-a[1]);v=(c[0]-b[0],c[1]-b[1])
 if abs(u[0]*v[1]-u[1]*v[0])>1e-9:
  heights=[p[2] for j,p in enumerate(actual) if abs(arc[j]-arc[i])<=.10+1e-9]
  assert max(heights)-min(heights)<1e-9,f'Nonlevel bend overlap at station{i}'
  bends.append(i)
print(json.dumps({'status':'passed','stations':len(actual),'level_bends':len(bends),'unchanged_geographic_points':len(actual),'maximum_additional_lowering_world_km':max(a[2]-b[2] for a,b in zip(raw,actual)),'endpoints':[actual[0][2],actual[-1][2]]}))
