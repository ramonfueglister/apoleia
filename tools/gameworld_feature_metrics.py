#!/opt/homebrew/bin/python3.14
"""Protected feature graph/endpoint/contour metrics against original clipped sources.
Explicit sparse derived landformgraph scope; doesnot invent surveyed ridge networks.
"""
import os
os.environ['PROJ_DATA']='/opt/homebrew/share/proj'
import collections,hashlib,json,math,pathlib
import numpy as np
from osgeo import ogr,osr
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'data/gameworld-v1';R=6371008.8;ogr.UseExceptions()
def read(p):return json.loads(p.read_text())
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ref(p):return dict(path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size)
def chains(g):
 if g.GetPointCount():yield np.asarray(g.GetPoints())[:,:2]
 else:
  for i in range(g.GetGeometryCount()):yield from chains(g.GetGeometryRef(i))
def projected(g):
 gg=g.Clone();a=osr.SpatialReference();a.ImportFromEPSG(4326);a.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);b=osr.SpatialReference();b.ImportFromProj4('+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m');b.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER);gg.Transform(osr.CoordinateTransformation(a,b));return gg
def geodistance(a,b):
 lon0=a[0]/(R*math.cos(math.radians(41)));lat0=a[1]/R+math.radians(41);lon1=b[0]/(R*math.cos(math.radians(41)));lat1=b[1]/R+math.radians(41);v=math.sin((lat1-lat0)/2)**2+math.cos(lat0)*math.cos(lat1)*math.sin((lon1-lon0)/2)**2;return 2*R*math.asin(min(1,math.sqrt(v)))
def water_metrics():
 w,s,e,n=[-44,18,79,61];clip=ogr.CreateGeometryFromWkt(f'POLYGON(({w} {s},{e} {s},{e} {n},{w} {n},{w} {s}))');records=[];endpoints_source=[];endpoints_model=[];max_endpoint=0.
 for kind in ['land','lakes','rivers']:
  model=read(OUT/'payload'/(kind+'.geojson'));lookup={f['properties']['source_id']:ogr.CreateGeometryFromJson(json.dumps(f['geometry'])) for f in model['features']};source=ogr.Open(str(ROOT/f'data/raw/ne_10m_{"rivers_lake_centerlines" if kind=="rivers" else kind}.geojson'));layer=source.GetLayer();layer.SetSpatialFilterRect(w,s,e,n)
  for f in layer:
   sid=str(json.loads(f.ExportToJson())['properties'].get('ne_id',f.GetFID()));g=f.GetGeometryRef().Clone()
   if not g.IsValid():g=g.MakeValid()
   g=g.Intersection(clip)
   if g.IsEmpty():continue
   a=projected(g);b=projected(lookup[sid]);ca=list(chains(a));cb=list(chains(b))
   if kind=='rivers':
    ea=np.array([p for c in ca for p in [c[0],c[-1]]]);eb=np.array([p for c in cb for p in [c[0],c[-1]]]);max_endpoint=max(max_endpoint,float(np.max(np.linalg.norm(ea-eb,axis=1))));endpoints_source.extend([tuple(np.rint(p*1e4).astype('i8')) for p in ea]);endpoints_model.extend([tuple(np.rint(p*1e4).astype('i8')) for p in eb]);continue
   aa=np.concatenate([c[:-1] for c in cb if len(c)>1]);bb=np.concatenate([c[1:] for c in cb if len(c)>1]);delta=bb-aa;den=(delta*delta).sum(1);den[den==0]=1;pts=np.concatenate(ca);step=max(1,len(pts)//64);dist=[]
   for p in pts[::step]:
    t=np.clip(((p-aa)*delta).sum(1)/den,0,1);closest=aa+t[:,None]*delta;idx=int(np.argmin(((p-closest)**2).sum(1)));dist.append(geodistance(p,closest[idx]))
   records.append(dict(id=f'{kind}:{sid}',sample_count=len(dist),maximum_directed_geodetic_m=max(dist,default=0)))
 endpoint_graph_equal=collections.Counter(endpoints_source)==collections.Counter(endpoints_model);maximum=max(x['maximum_directed_geodetic_m'] for x in records);return dict(coast_lake_directed_geodetic_max_m=maximum,coast_lake_budget_m=150,records=records,river_endpoint_max_projected_m=max_endpoint,river_endpoint_budget_projected_m=.00001,river_endpoint_node_multiset_equal=endpoint_graph_equal,river_endpoint_count=len(endpoints_source),unexpected_river_endpoint_changes=0 if endpoint_graph_equal else 1,status='validiert' if maximum<=150 and max_endpoint<=.00001 and endpoint_graph_equal else 'offen')
def terrain_metrics():
 counts=collections.Counter();lost=0;records=[];anchors=[];seams={};seam_fail=0
 for domain in ['core','context']:
  m=read(OUT/(domain+'-mesh-manifest.json'))
  for block in m['blocks']:
   features=read(ROOT/block['feature_inventory']['path'])['features'];idx=np.fromfile(ROOT/block['indices']['path'],dtype='<u4').reshape(-1,3);edgeids=np.concatenate([idx[:,[0,1]],idx[:,[1,2]],idx[:,[0,2]]]);edgeids.sort(1);edges={tuple(z) for z in edgeids};grid=np.fromfile(ROOT/block['canonical_source_grid']['path'],dtype='<u4').reshape(-1,2);height=np.fromfile(ROOT/block['canonical_source_heights']['path'],dtype='<f4');lookup={tuple(f['source_sample']):f for f in features};total=0;missing=[]
   for f in features:
    counts[f['kind']]+=1
    if f['kind']=='ridge_anchor':anchors.append(dict(id=f['id'],block=block['id'],source_sample=f['source_sample'],height_m=f['source_height_m']))
    row,col=f['source_sample']
    for neighbor in [(row+1,col),(row,col+1)]:
     o=lookup.get(neighbor)
     if o is None or o['kind']!=f['kind']:continue
     total+=1;a,b=sorted([f['retained_vertex_index'],o['retained_vertex_index']])
     if (a,b) not in edges:missing.append([f['id'],o['id']])
   lost+=len(missing);counts['source_samekind_4neighbor_edges']+=total;records.append(dict(id=block['id'],protected_nodes=len(features),protected_edges=total,missing_edges=missing))
   # All native sourcecentres on each shared row/column form exact matching identities.
   x,y,w,h=block['source_window'];sel=(grid[:,0]==x)|(grid[:,0]==x+w-1)|(grid[:,1]==y)|(grid[:,1]==y+h-1)
   for j in np.flatnonzero(sel):
    key=(domain,int(grid[j,0]),int(grid[j,1]));v=float(height[j]);old=seams.get(key)
    if old is not None and old!=v:seam_fail+=1
    seams[key]=v
 return dict(status='validiert' if lost==0 and seam_fail==0 and len({a['id'] for a in anchors})==6 else 'offen',counts=dict(counts),unexpected_protected_graph_edge_losses=lost,shared_seam_height_mismatches=seam_fail,named_massif_anchor_count=len({a['id'] for a in anchors}),named_massif_anchors=anchors,blocks=records,scope='Allprotected derivedextrema nodes andsamekind4neighbor sourcegrid edges, exact blockseamheightidentities,6fixedmassifanchors. Notacomplete surveyedridge/hydrologicalnetwork.')
def main():
 a=water_metrics();print('water',a['status'],a['coast_lake_directed_geodetic_max_m'],flush=True);b=terrain_metrics();print('terrain',b['status'],b['counts'],b['named_massif_anchor_count'],flush=True);m=dict(revision='gameworld-feature-metrics-v1',reference_version='kit1-landscape-v5/astra-replan-v2',policy=ref(OUT/'feature-protection.json'),status='validiert' if a['status']==b['status']=='validiert' else 'offen',water=a,terrain=b);(ROOT/'runs/kit1-landscape-v5-2026-10-25/gameworld-v1/frozen-feature-measurements.json').write_text(json.dumps(m,indent=2)+'\n')
if __name__=='__main__':main()
