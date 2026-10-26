#!/usr/bin/env python3
"""Independent read-only checks; no imports from product pipeline or renderer."""
import datetime
import hashlib
import json
import math
import pathlib
import numpy as np
from osgeo import gdal, ogr

ROOT = pathlib.Path(__file__).resolve().parents[3]
RUN = pathlib.Path(__file__).resolve().parents[1]
CACHE = {}


def read(p):
    return json.loads((ROOT / p).read_text())


def sha(p):
    p = pathlib.Path(p)
    if not p.is_absolute():
        p = ROOT / p
    key = (p.stat().st_dev, p.stat().st_ino, p.stat().st_mtime_ns, p.stat().st_size)
    if key not in CACHE:
        with p.open('rb') as stream:
            CACHE[key] = hashlib.file_digest(stream, 'sha256').hexdigest()
    return CACHE[key]


def bilinear(arr, lon, lat, extent):
    height, width = arr.shape
    u = np.clip((lon-extent['west'])/(extent['east']-extent['west'])*width-.5, 0, width-1)
    v = np.clip((extent['north']-lat)/(extent['north']-extent['south'])*height-.5, 0, height-1)
    x = u.astype(int); y = v.astype(int)
    xx = np.minimum(x+1, width-1); yy = np.minimum(y+1, height-1)
    fx = u-x; fy = v-y
    return ((1-fx)*arr[y,x]+fx*arr[y,xx])*(1-fy) + ((1-fx)*arr[yy,x]+fx*arr[yy,xx])*fy


m = read('data/derived/landscape.json')
b = m['bounds']
result = {'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'kind': 'independent_offline_data_review', 'dataset_revision': m['dataset_revision'],
          'manifest_sha256': sha('data/derived/landscape.json'),
          'runtime_executed': False, 'hash_checks': [], 'input_hash_checks': [], 'anchors': []}
for name, asset in m['assets'].items():
    p = ROOT / 'data/derived' / name
    exported = RUN / 'data/derived' / name
    result['hash_checks'].append({'path': str(p.relative_to(ROOT)), 'sha256': sha(p),
        'matches': sha(p) == asset['sha256'], 'bytes_match': p.stat().st_size == asset['bytes'],
        'run_export_exists': exported.exists(), 'run_export_same_inode': exported.exists() and p.samefile(exported),
        'run_export_hash_matches': exported.exists() and sha(exported) == sha(p)})
for source in read('data/sources.json')['sources']:
    p = ROOT / source['artifact_path']
    result['input_hash_checks'].append({'id': source['id'], 'path': source['artifact_path'],
        'matches': p.exists() and sha(p) == source['sha256'], 'license_declared': bool(source.get('license'))})

grids = {
    'overview': np.memmap(ROOT/'data/derived'/m['overview']['height_path'], dtype='<f4', shape=(m['overview']['height'],m['overview']['width'])),
    'canonical': np.memmap(ROOT/'data/derived'/m['height_path'], dtype='<f4', shape=(m['height'],m['width'])),
    'detail': np.memmap(ROOT/'data/derived'/m['height_detail_path'], dtype='<f4', shape=(m['height_detail_height'],m['height_detail_width']))}
cover = np.memmap(ROOT/'data/derived'/m['class_path'],dtype='u1',shape=(m['height'],m['width']))
water = np.memmap(ROOT/'data/derived'/m['water_path'],dtype='u1',shape=cover.shape)
detail_water = np.memmap(ROOT/'data/derived'/m['water_detail_path'],dtype='u1',shape=(m['water_detail_height'],m['water_detail_width']))
result['canonical_census'] = {'cells': cover.size, 'nonfinite_heights': int(np.count_nonzero(~np.isfinite(grids['canonical']))),
    'unknown_landcover_on_land': int(np.count_nonzero((cover==0)&(water==0))),
    'negative_land_cells': int(np.count_nonzero((grids['canonical']<0)&(water==0))),
    'water_kinds': {str(k): int(v) for k,v in zip(*np.unique(water, return_counts=True))}}

# Different, independently selected native lattice plus per-tile regional extrema.
# Read original TIFF pixels directly: no Warp, datum conversion, or product VRT.
checks = {level: {'sample_count':0, 'maximum_absolute_error_m':0.0} for level in grids}
source_reports=[]
for tile in read('data/etopo15-inventory.json')['sources']:
    ds=gdal.Open(str(ROOT/tile['path']))
    gt=ds.GetGeoTransform(); a=ds.ReadAsArray()
    xs=gt[0]+(np.arange(ds.RasterXSize)+.5)*gt[1]
    ys=gt[3]+(np.arange(ds.RasterYSize)+.5)*gt[5]
    cols=np.where((xs>=b['west'])&(xs<=b['east']))[0]
    rows=np.where((ys>=b['south'])&(ys<=b['north']))[0]
    cc,rr=np.meshgrid(cols[::173],rows[::173])
    sub=a[np.ix_(rows,cols)]
    locs=[np.unravel_index(np.argmin(sub),sub.shape),np.unravel_index(np.argmax(sub),sub.shape)]
    ix=np.r_[cc.ravel(),[cols[k[1]] for k in locs]]
    iy=np.r_[rr.ravel(),[rows[k[0]] for k in locs]]
    lon=xs[ix];lat=ys[iy];truth=a[iy,ix]
    for level,grid in grids.items():
        error=np.abs(bilinear(grid,lon,lat,b)-truth)
        checks[level]['sample_count']+=len(error)
        checks[level]['maximum_absolute_error_m']=max(checks[level]['maximum_absolute_error_m'],float(error.max()))
    source_reports.append({'path':tile['path'],'width':ds.RasterXSize,'height':ds.RasterYSize,
        'geotransform':list(gt),'has_EGM2008_in_crs': 'EGM2008' in ds.GetProjection(),
        'nodata':ds.GetRasterBand(1).GetNoDataValue()})
result['independent_native_lattice']={'method':'Every 173rd original TIFF source pixel within region plus original regional min/max per tile; direct original ReadAsArray, bilinear delivered grids; different sample from producer. Sample maxima, no global bound.',
    'metrics':checks,'source_grids':source_reports}

expected={p['anchor_id']:p['expected'] for p in read('data/expected-tiles.json')['probes']}
R=6371008.8
for anchor in read('data/anchors.json')['anchors']:
    lon=anchor['longitude']; lat=anchor['latitude']
    x=R*math.cos(math.radians(41))*math.radians(lon-19)
    z=-R*math.radians(lat-41)
    row=math.floor(z/1000);col=math.floor(x/1000)
    tile=f'eqc41-km-v1:{row}:{col}'
    xi=min(m['width']-1,math.floor((lon-b['west'])/(b['east']-b['west'])*m['width']))
    yi=min(m['height']-1,math.floor((b['north']-lat)/(b['north']-b['south'])*m['height']))
    result['anchors'].append({'id':anchor['id'],'computed_tile_id':tile,
        'tile_matches':tile==expected[anchor['id']]['canonical_tile_id'],
        'class_at_pixel':int(cover[yi,xi]),'class_matches':int(cover[yi,xi])==anchor['class_code'],
        'nearest_canonical_height_m':float(grids['canonical'][yi,xi]),
        'declared_height_m':anchor['height_m'],'water_kind':int(water[yi,xi])})

# Cross-check retained river coordinates dimensionally, not area of line difference.
clip=ogr.CreateGeometryFromWkt(f"POLYGON(({b['west']} {b['south']},{b['east']} {b['south']},{b['east']} {b['north']},{b['west']} {b['north']},{b['west']} {b['south']}))")
original=read('data/raw/ne_10m_rivers_lake_centerlines.geojson')['features']
expected_rivers={}
for i,f in enumerate(original):
    g=ogr.CreateGeometryFromJson(json.dumps(f['geometry']))
    if g.Intersects(clip):
        cut=g.Intersection(clip)
        if not cut.IsEmpty():expected_rivers[str(f['properties'].get('ne_id',i))]=cut
river_records=[]
for f in read('data/derived/rivers.geojson')['features']:
    key=f['properties']['source_id']; actual=ogr.CreateGeometryFromJson(json.dumps(f['geometry']))
    exp=expected_rivers[key]
    river_records.append({'id':key,'topological_equals':bool(actual.Equals(exp)),
        'symmetric_difference_length_degrees':actual.SymmetricDifference(exp).Length(),
        'actual_length_degrees':actual.Length(),'expected_length_degrees':exp.Length(),
        'actual_geometry_type':actual.GetGeometryName(),'expected_geometry_type':exp.GetGeometryName()})
result['river_coordinate_checks']=river_records
result['raw_csv_maxima']=[]
for level in grids:
    for prefix,col in [('error',4),('coast',2)]:
        path=ROOT/f'data/derived/{prefix}-{level}.csv'
        values=np.loadtxt(path,delimiter=',',skiprows=1)
        idx=int(np.nanargmax(values[:,col]))
        result['raw_csv_maxima'].append({'path':str(path.relative_to(ROOT)),'sha256':sha(path),
            'sample_count':len(values),'maximum':float(values[idx,col]),'maximum_row':values[idx].tolist()})
result['input_snapshot']={p:sha(p) for p in ['data/derived/landscape.json','data/geodata_policy.json','data/coverage.json','data/derivation.json','data/anchors.json','data/expected-tiles.json','data/transformations.json','data/derived/inventory.json','app/scripts/landscape.gd','app/shaders/terrain.gdshader','app/scripts/expected_projection.py','docs/product-renderer/camera-profile.json']}
print(json.dumps(result,indent=2))
