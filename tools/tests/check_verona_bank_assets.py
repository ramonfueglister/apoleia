"""Independent exported-buffer checks for the two native bank asset families.
Does not establish terrain placement or visual quality; use the GPU runner too.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from check_verona_bridge_assets import read_glb, accessor, primitives, lod_triangles, require

ROOT=Path(__file__).resolve().parents[2]
TAGS=('detail','medium','far')
SLUGS=('bank_stones','bank_grass')

def audit(slug):
    path=ROOT/'app/assets/environment'/slug/(slug+'.glb')
    doc,data=read_glb(path)
    require(len(doc.get('materials',[]))==1,slug+': one material required')
    require(doc['materials'][0].get('alphaMode','OPAQUE')=='OPAQUE',slug+': opaque surface required')
    require(not doc.get('textures'),slug+': no textures expected')
    rows=[]
    for tag in TAGS:
        node=next(i for i,n in enumerate(doc['nodes']) if n.get('name')=='Model_'+tag)
        parts=list(primitives(doc,node));require(len(parts)==1,slug+'/'+tag+': one surface required')
        attrs=parts[0]['attributes'];require('COLOR_0' in attrs,slug+'/'+tag+': vertex colours missing')
        colour=accessor(doc,data,attrs['COLOR_0'])
        require(np.unique(colour[:,:3],axis=0).shape[0]>=3,slug+'/'+tag+': colour family collapsed')
        mesh=lod_triangles(doc,data,tag)
        low=mesh.min(axis=(0,1));high=mesh.max(axis=(0,1));span=high-low
        area=np.linalg.norm(np.cross(mesh[:,1]-mesh[:,0],mesh[:,2]-mesh[:,0]),axis=1)*.5
        require(np.all(area>1e-10),slug+'/'+tag+': degenerate faces')
        require(abs(low[2])<.015,slug+'/'+tag+': authored root off ground')
        require(high[2]<.8,slug+'/'+tag+': bank detail too tall')
        require(max(span[:2])<3,slug+'/'+tag+': detail footprint too wide')
        require(len(mesh)<4000,slug+'/'+tag+': excessive detail budget')
        rows.append({'lod':tag,'triangles':len(mesh),'bounds_min_xyz_m':low.tolist(),'bounds_max_xyz_m':high.tolist()})
    counts=[r['triangles'] for r in rows]
    require(counts[0]>counts[1]>counts[2],slug+': LOD cost does not decrease')
    # Clusters must not lose their outer footprint or height in far meshes.
    reference=np.array(rows[0]['bounds_max_xyz_m'])-rows[0]['bounds_min_xyz_m']
    for row in rows[1:]:
        span=np.array(row['bounds_max_xyz_m'])-row['bounds_min_xyz_m']
        require(np.all(span/reference>.70),slug+'/'+row['lod']+': cluster shrinks when zooming')
    imp=path.with_suffix('.glb.import')
    require(imp.exists() and 'meshes/generate_lods=false' in imp.read_text(),slug+': automatic Godot LOD enabled')
    return {'asset':slug,'lods':rows}

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=ROOT/'build/verona-bank/asset-validation.json');a=p.parse_args()
    report={'test':'verona_bank_assets','assets':[],'failures':[]}
    for slug in SLUGS:
        try: report['assets'].append(audit(slug))
        except Exception as err: report['failures'].append(str(err))
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'assets':len(report['assets']),'failures':report['failures']}))
    return bool(report['failures'])
if __name__=='__main__': raise SystemExit(main())
