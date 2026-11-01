#!/usr/bin/env python3
"""Freeze an audited near-Verona profile; this is not a global hydrology bake.

Input is actual GPU terrain samples ordered using independently inferred Adige
flow direction (tools/tests/analyze_verona_river_profile.py). Lower-only running
minimum is a deliberate display repair, not a surveyed historical water level.
"""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = (-676.959516530886, -498.1516046706583)

def condition_profile(points):
    raw=[p[2] for p in points]
    distances=[0.]
    for a,b in zip(points,points[1:]):distances.append(distances[-1]+math.dist(a[:2],b[:2]))
    bends=[]
    for i in range(1,len(points)-1):
        a,b,c=points[i-1:i+2]
        u=(b[0]-a[0],b[1]-a[1]);v=(c[0]-b[0],c[1]-b[1])
        if abs(u[0]*v[1]-u[1]*v[0])>1e-9:bends.append(i)
    ends=[0]+bends+[len(points)-1];knots=set(ends)
    for a,b in zip(ends,ends[1:]):
        axis=abs(points[b][0]-points[a][0])<1e-9 or abs(points[b][1]-points[a][1])<1e-9
        knots.update(range(a,b+1,2 if axis else 1))
    knots=sorted(knots);heights=[min(raw[a:b+1]) for a,b in zip(knots,knots[1:])]+[raw[-1]]
    ks=[distances[i] for i in knots]
    groups=[]
    for bend in bends:
        lo=max(k for k,s in enumerate(ks) if s<=distances[bend]-.10)
        hi=min(k for k,s in enumerate(ks) if s>=distances[bend]+.10)
        if groups and lo<=groups[-1][1]:groups[-1]=(groups[-1][0],hi)
        else:groups.append((lo,hi))
    for lo,hi in reversed(groups):
        target=heights[hi]
        ramp=max(0,next((k for k in reversed(range(lo)) if ks[k]<=ks[lo]-.25),0))
        top=heights[ramp];span=ks[lo]-ks[ramp]
        if span>0:
            for k in range(ramp,lo):heights[k]=min(heights[k],top+(target-top)*(ks[k]-ks[ramp])/span)
        for k in range(lo,hi+1):heights[k]=target
    out=[p[:] for p in points]
    for k,(a,b) in enumerate(zip(knots,knots[1:])):
        for i in range(a,b+1):out[i][2]=heights[k]+(heights[k+1]-heights[k])*(distances[i]-distances[a])/(distances[b]-distances[a])
    assert all(a[2]>=b[2]-1e-10 for a,b in zip(out,out[1:]))
    assert all(p[2]<=old+1e-9 for p,old in zip(out,raw))
    assert out[0][2]==raw[0] and out[-1][2]==raw[-1]
    return out,knots

def cap_water_apron(points, reference):
    """Sample actual captured GPU terrain across water plus its adjoining grid fan.

    The 0.125 km radius covers the 0.075 km water miter and a 0.025 km grid
    diagonal. This prevents lower-only banks from sitting beneath the water edge.
    """
    def ground(x, z):
        gx=(x-reference["world_min"][0])/reference["tile_km"]
        gz=(z-reference["world_min"][1])/reference["tile_km"]
        tx,tz=math.floor(gx),math.floor(gz);u,v=gx-tx,gz-tz
        px,pz=tx-reference["origin"][0],tz-reference["origin"][1]
        assert 0<=px<reference["size"][0] and 0<=pz<reference["size"][1],"GPU fixture does not cover water apron"
        i=(pz*reference["size"][0]+px)*4;c=reference["values"][i:i+4]
        if abs(c[0]-c[2])<=abs(c[1]-c[3]):
            h=c[0]+(c[1]-c[0])*u+(c[2]-c[1])*v if u>=v else c[0]+(c[3]-c[0])*v+(c[2]-c[3])*u
        else:
            h=c[0]+(c[1]-c[0])*u+(c[3]-c[0])*v if u+v<=1 else c[2]+(c[3]-c[2])*(1-u)+(c[1]-c[2])*(1-v)
        return h*reference["level_h"]
    out=[p[:] for p in points];level=math.inf
    for i,p in enumerate(out):
        a=points[max(0,i-1)];b=points[min(len(points)-1,i+1)]
        dx,dz=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dz);normal=(-dz/length,dx/length)
        low=min(ground(p[0]+ORIGIN[0]+normal[0]*.125*(2*j/32-1),p[1]+ORIGIN[1]+normal[1]*.125*(2*j/32-1)) for j in range(33))
        level=min(level,p[2],low);p[2]=level
    return out

def build(report, conditioned=True):
    points = []
    height = float("inf")
    for sample in report["samples"]:
        # Samples are twentieths of the 0.25 km segment grid. Snap removes GPU
        # world-position float32 noise without moving the underlying tile path.
        xy = [round((sample["xz"][i] - ORIGIN[i]) * 80) / 80 for i in (0, 1)]
        height = min(height, sample["height"], sample["left_height"], sample["right_height"])
        if not points or xy != points[-1][:2]:
            points.append(xy + [height])
    raw = points
    if conditioned:
        reference=json.loads((ROOT / "docs/handover/verona-river/gpu-corridor-corners.json").read_text())
        points, knots = condition_profile(cap_water_apron(points,reference))
    return {"conditioning": {"method": "grid-aligned lower envelope with level bend buffers", "bend_buffer_world_km": .10, "water_apron_radius_world_km": .125, "ground_reference": "docs/handover/verona-river/gpu-corridor-corners.json", "upstream_ramp_world_km": .25,
                              "additional_lowering_world_km": max(a[2]-b[2] for a,b in zip(raw,points)), "changed_stations": sum(a[2]!=b[2] for a,b in zip(raw,points))},
            "origin": ORIGIN, "direction": report["direction"],
            "source": "GPU actual terrain baseline, lower-only running minimum plus conservative grid-aligned bend conditioning; bounded Verona repair",
            "points": points}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "app/assets/environment/verona_river/profile.json")
    args = parser.parse_args()
    args.output.write_text(json.dumps(build(json.loads(args.input.read_text())), indent=2))
