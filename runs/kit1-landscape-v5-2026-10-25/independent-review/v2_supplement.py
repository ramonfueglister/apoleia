#!/usr/bin/env python3
"""Additional independent read-only normalization and worst-coast checks."""
import json
import math
import pathlib
import numpy as np
from osgeo import ogr

ROOT=pathlib.Path(__file__).resolve().parents[3]
def read(p):return json.loads((ROOT/p).read_text())
def geometry(f):return ogr.CreateGeometryFromJson(json.dumps(f['geometry']))

original=read('data/reference/roman-117.geojson')['features']
normalized=read('data/reference/roman-117-normalized.geojson')['features']
checks=[]
for source,output in zip(original,normalized):
    a=geometry(source);b=geometry(output)
    expected=a if a.IsValid() else a.MakeValid()
    checks.append({'source_feature_id':str(source['properties']['OBJECTID']),
        'original_valid':bool(a.IsValid()),'output_valid':bool(b.IsValid()),
        'equals_expected_normalization':bool(expected.Equals(b)),
        'envelope_unchanged':a.GetEnvelope()==b.GetEnvelope(),
        'symmetric_difference_area_square_degrees':expected.SymmetricDifference(b).GetArea()})

m=read('data/derived/landscape.json');b=m['bounds'];R=6371008.8
records=[]
for level,path,w,h in [('overview',m['overview']['water_path'],m['overview']['width'],m['overview']['height']),
                       ('canonical',m['water_path'],m['width'],m['height']),
                       ('detail',m['water_detail_path'],m['water_detail_width'],m['water_detail_height'])]:
    rows=np.loadtxt(ROOT/f'data/derived/coast-{level}.csv',delimiter=',',skiprows=1)
    lon,lat,reported=rows[np.argmax(rows[:,2])]
    water=np.memmap(ROOT/'data/derived'/path,dtype='u1',shape=(h,w))>0
    edge=np.zeros_like(water)
    edge[1:]|=water[1:]!=water[:-1];edge[:-1]|=water[1:]!=water[:-1]
    edge[:,1:]|=water[:,1:]!=water[:,:-1];edge[:,:-1]|=water[:,1:]!=water[:,:-1]
    x=int((lon-b['west'])/(b['east']-b['west'])*w)
    y=int((b['north']-lat)/(b['north']-b['south'])*h)
    best=math.inf;best_pixel=None
    for yy in range(max(0,y-8),min(h,y+9)):
        for xx in range(max(0,x-8),min(w,x+9)):
            if not edge[yy,xx]:continue
            lx=b['west']+(xx+.5)/w*(b['east']-b['west'])
            ly=b['north']-(yy+.5)/h*(b['north']-b['south'])
            distance=math.hypot(math.radians(lx-lon)*R*math.cos(math.radians(lat)),math.radians(ly-lat)*R)
            if distance<best:best=distance;best_pixel=[xx,yy]
    records.append({'level':level,'sample_lon':float(lon),'sample_lat':float(lat),
        'csv_reported_distance_m':float(reported),'independent_distance_m':best,
        'nearest_interface_pixel':best_pixel,'budget_m':6000,'within_budget':best<=6000})
print(json.dumps({'roman_normalization':checks,'coast_maximum_recomputed':records},indent=2))
