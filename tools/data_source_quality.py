#!/usr/bin/env python3
import json
from data_bind import ROOT,read,save,geom,feature,ref
from osgeo import ogr
ogr.UseExceptions();p=read('data/reference/roman-117.geojson');fs=[];bad=[]
for f in p['features']:
 g=geom(f);valid=g.IsValid();fixed=g if valid else g.MakeValid()
 if not valid:bad.append(dict(source_feature_id=str(f['properties']['OBJECTID']),original_type=g.GetGeometryName(),normalized_type=fixed.GetGeometryName(),normalized_valid=fixed.IsValid(),source_extent=g.GetEnvelope(),normalized_extent=fixed.GetEnvelope(),area_change_square_degrees=fixed.GetArea()-g.GetArea()))
 fs.append(feature(fixed,f['properties']))
save('data/reference/roman-117-normalized.geojson',dict(type='FeatureCollection',features=fs))
save('data/source-topology-quality.json',dict(revision='sourcequality-v1',input=ref('data/reference/roman-117.geojson'),output=ref('data/reference/roman-117-normalized.geojson'),method='OGR MakeValid only for invalid original source polygons. Original AWMC bytes untouched. Reference-region extent comes from original geometry envelopes; normalization is an independent audit artifact, not a historical correction.',source_feature_count=len(fs),invalid_sources=len(bad),normalizations=bad))
print(len(bad),'source geometry normalized separately')
