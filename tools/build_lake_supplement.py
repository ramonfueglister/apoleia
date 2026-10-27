#!/usr/bin/env python3
"""Lake supplement from Natural Earth's Europe lakes (display water).

The canonical water mask comes from ne_10m_lakes, which misses central
Italian lakes such as Trasimeno and Bolsena. Natural Earth publishes them in
the Europe supplement. Rule (no hand edits): featurecla "Lake", scalerank
<= 10, centroid inside the atlas world. Lakes also in ne_10m_lakes are kept
(Bolsena is there but was lost in the derived water mask); adding water
where water already is changes nothing. Output polygons are in model world
km (x, z) for build_clipmap_tiles.py --lakes.

Usage: tools/build_lake_supplement.py [--raw path/to/ne_10m_lakes_europe.geojson]
"""
from pathlib import Path
import argparse,hashlib,json,math,urllib.request
import shapely
from shapely.geometry import shape
ROOT=Path(__file__).resolve().parents[1]
URL='https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_lakes_europe.geojson'
RAW_SHA256='b4dd9e7a5edd0d07b54768b5404d1ebe77f80b9d579c85fff65f90cf50369769'
OUT=ROOT/'artifacts/render-data/lakes-europe-supplement-r1'
R=6371008.8;MAX_RANK=10
def world_xz(lon,lat):
    return (math.radians(lon-19.0)*R*math.cos(math.radians(41.0))*.001,math.radians(41.0-lat)*R*.001)
def main():
    p=argparse.ArgumentParser();p.add_argument('--raw');args=p.parse_args()
    raw=Path(args.raw).read_bytes() if args.raw else urllib.request.urlopen(URL,timeout=60).read()
    if hashlib.sha256(raw).hexdigest()!=RAW_SHA256:raise SystemExit('Natural Earth Europe lakes: sha256 mismatch')
    surface=json.loads((ROOT/'artifacts/render-data/fixed-source-v2-mountain-r7/surface.json').read_text())
    wmin=surface['world_min'];wsize=surface['world_size']
    canonical=[shape(f['geometry']) for f in json.loads((ROOT/'data/raw/ne_10m_lakes.geojson').read_text())['features']]
    tree=shapely.STRtree(canonical)
    kept=[];skipped={'feature_class':0,'rank':0,'outside':0,'duplicate':0}
    for f in json.loads(raw)['features']:
        props=f['properties']
        if props.get('featurecla')!='Lake':skipped['feature_class']+=1;continue
        if float(props.get('scalerank',99))>MAX_RANK:skipped['rank']+=1;continue
        g=shape(f['geometry']);c=g.centroid;x,z=world_xz(c.x,c.y)
        if not(wmin[0]<=x<=wmin[0]+wsize[0] and wmin[1]<=z<=wmin[1]+wsize[1]):skipped['outside']+=1;continue
        if any(canonical[i].contains(c) for i in tree.query(c)):skipped['duplicate']+=1
        wg=shapely.transform(g,lambda a:__import__('numpy').array([world_xz(lon,lat) for lon,lat in a]))
        kept.append({'type':'Feature','properties':{'name':props.get('name'),'scalerank':props.get('scalerank'),'source':'ne_10m_lakes_europe','crs':'model world km (x, z)'},'geometry':shapely.geometry.mapping(wg)})
    OUT.mkdir(parents=True,exist_ok=True)
    payload=(json.dumps({'type':'FeatureCollection','features':kept},separators=(',',':'))+'\n').encode()
    (OUT/'lakes.geojson').write_bytes(payload)
    manifest={'format':'apoleia-lake-supplement-v1','source':{'name':'Natural Earth 1:10m lakes, Europe supplement','version':'v5.1.2','url':URL,'sha256':RAW_SHA256,'license':'Public domain; Made with Natural Earth'},'rule':f'featurecla Lake, scalerank <= {MAX_RANK}, centroid inside the atlas world; duplicates of ne_10m_lakes kept (counted)','features':len(kept),'names':[f['properties']['name'] for f in kept],'skipped':skipped,'payload':{'path':'lakes.geojson','sha256':hashlib.sha256(payload).hexdigest(),'bytes':len(payload)}}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(manifest['features'],manifest['skipped'],[n for n in manifest['names'] if n and any(k in n for k in ('Trasimeno','Bolsena','Bracciano','Vico'))])
if __name__=='__main__':main()
