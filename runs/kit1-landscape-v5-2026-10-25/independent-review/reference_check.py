#!/usr/bin/env python3
"""Independent read-only geometric checks of fixed Kit 1 references.

Run with existing /opt/homebrew/bin/python3.14 and PROJ_DATA=/opt/homebrew/share/proj.
Does not import product pipeline code, build data, or start the renderer.
"""
import datetime
import hashlib
import json
import pathlib
from osgeo import ogr

ROOT = pathlib.Path(__file__).resolve().parents[3]


def read(path):
    return json.loads((ROOT / path).read_text())


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def geometries(path):
    data = read(path)
    return [ogr.CreateGeometryFromJson(json.dumps(f['geometry'])) for f in data['features']]


region = read('data/region.json')
mask_path = region['region_mask']['artifact_path']
mask_parts = geometries(mask_path)
mask = mask_parts[0].Clone()
for part in mask_parts[1:]:
    mask = mask.Union(part)
result = {
    'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'scope': 'Independent actual source geometry containment and metadata checks; no historical frontier truth or runtime claim',
    'region_sha256': sha('data/region.json'),
    'mask_sha256': sha(mask_path),
    'mask_hash_matches': sha(mask_path) == region['region_mask']['sha256'],
    'mask_valid': bool(mask.IsValid()),
    'mask_geometry_type': mask.GetGeometryName(),
    'mask_connected_polygon': mask.GetGeometryName() == 'POLYGON',
    'references': [],
}
for item in region['reference_geometries']:
    path = item['source']['artifact_path']
    parts = geometries(path)
    envelopes = [p.GetEnvelope() for p in parts]
    extent = dict(west=min(e[0] for e in envelopes), east=max(e[1] for e in envelopes),
                  south=min(e[2] for e in envelopes), north=max(e[3] for e in envelopes))
    outside = [p.Difference(mask).GetArea() for p in parts]
    result['references'].append({
        'id': item['id'], 'file_sha256': sha(path),
        'hash_matches': sha(path) == item['source']['sha256'],
        'feature_count': len(parts), 'invalid_count': sum(not p.IsValid() for p in parts),
        'actual_extent': extent,
        'declared_extent_max_difference_deg': max(abs(extent[k] - item['extent'][k]) for k in extent),
        'outside_mask_square_degrees': sum(outside),
        'features_with_outside_area': sum(a > 0 for a in outside),
    })
england = next(r for r in result['references'] if r['id'] == 'england_and_northern_context')
result['northern_context'] = {
    'england_north_actual_deg': england['actual_extent']['north'],
    'mask_north_deg': mask.GetEnvelope()[3],
    'actual_buffer_deg': mask.GetEnvelope()[3] - england['actual_extent']['north'],
    'declared_buffer_deg': region['north_context_degrees'],
}
print(json.dumps(result, indent=2))
