#!/usr/bin/env python3
"""Build the display river supplement from Natural Earth's Europe rivers.

The canonical dataset carries ne_10m_rivers_lake_centerlines only (168
features in the region); it has no Arno, Volturno or Liri basin. Natural
Earth publishes the missing medium rivers in a separate Europe supplement.
Rule (no hand edits): featurecla "River", scalerank <= 10, at least one
vertex inside the atlas world, and not a duplicate of a canonical river
(more than half its vertices on 0.05 deg cells the canonical set covers).

Usage: tools/build_river_supplement.py [--raw path/to/ne_10m_rivers_europe.geojson]
"""
from pathlib import Path
import argparse,hashlib,json,math,urllib.request
ROOT=Path(__file__).resolve().parents[1]
URL='https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_rivers_europe.geojson'
RAW_SHA256='90712202ac46985812e90840df9acd5101599a9c649868d5bc55ee96c2fedd4c'
OUT=ROOT/'artifacts/render-data/rivers-europe-supplement-r1'
EARTH_RADIUS=6371008.8;MODEL_SCALE=.001;MAX_RANK=10;CELL=.05

def world_xz(lon,lat):
    return (math.radians(lon-19.0)*EARTH_RADIUS*math.cos(math.radians(41.0))*MODEL_SCALE,math.radians(41.0-lat)*EARTH_RADIUS*MODEL_SCALE)
def lines(geometry):
    return [geometry['coordinates']] if geometry['type']=='LineString' else geometry['coordinates']
def main():
    p=argparse.ArgumentParser();p.add_argument('--raw');args=p.parse_args()
    raw=Path(args.raw).read_bytes() if args.raw else urllib.request.urlopen(URL,timeout=60).read()
    if hashlib.sha256(raw).hexdigest()!=RAW_SHA256:raise SystemExit('Natural Earth Europe rivers: sha256 mismatch')
    surface=json.loads((ROOT/'artifacts/render-data/fixed-source-v2-mountain-r7/surface.json').read_text())
    wmin=surface['world_min'];wsize=surface['world_size']
    def inside(lon,lat):
        x,z=world_xz(lon,lat);return wmin[0]<=x<=wmin[0]+wsize[0] and wmin[1]<=z<=wmin[1]+wsize[1]
    canonical=json.loads((ROOT/'data/derived/rivers.geojson').read_text())
    covered={(round(x/CELL),round(y/CELL)) for f in canonical['features'] for line in lines(f['geometry']) for x,y in line}
    kept=[];skipped={'feature_class':0,'rank':0,'outside':0,'duplicate':0}
    for f in json.loads(raw)['features']:
        props=f['properties']
        if props.get('featurecla')!='River':skipped['feature_class']+=1;continue
        if float(props.get('scalerank',99))>MAX_RANK:skipped['rank']+=1;continue
        points=[q for line in lines(f['geometry']) for q in line]
        if not any(inside(*q) for q in points):skipped['outside']+=1;continue
        if sum((round(x/CELL),round(y/CELL)) in covered for x,y in points)>len(points)*.5:skipped['duplicate']+=1;continue
        kept.append({'type':'Feature','properties':{'name':props.get('name'),'scalerank':props.get('scalerank'),'featurecla':props.get('featurecla'),'wikidataid':props.get('wikidataid'),'source':'ne_10m_rivers_europe'},'geometry':f['geometry']})
    OUT.mkdir(parents=True,exist_ok=True)
    payload=(json.dumps({'type':'FeatureCollection','features':kept},separators=(',',':'))+'\n').encode()
    (OUT/'rivers.geojson').write_bytes(payload)
    manifest={'format':'apoleia-river-supplement-v1','role':'display only; the canonical dataset rivers stay unchanged','source':{'name':'Natural Earth 1:10m rivers, Europe supplement','version':'v5.1.2','url':URL,'sha256':RAW_SHA256,'license':'Public domain; Made with Natural Earth'},'rule':f'featurecla River, scalerank <= {MAX_RANK}, a vertex inside the atlas world, not a duplicate of a canonical river (>50 % of vertices on {CELL} deg cells the canonical set covers)','features':len(kept),'vertices':sum(len(q) for f in kept for q in lines(f['geometry'])),'skipped':skipped,'payload':{'path':'rivers.geojson','sha256':hashlib.sha256(payload).hexdigest(),'bytes':len(payload)},'known_gaps':'Natural Earth has no Liri/Garigliano at 1:10m; its tributary Sacco is scalerank 11 and therefore not drawn'}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:manifest[k] for k in ('features','vertices','skipped')}),manifest['payload']['sha256'])
if __name__=='__main__':main()
