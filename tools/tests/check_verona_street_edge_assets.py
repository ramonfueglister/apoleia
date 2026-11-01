"""Independent exported geometry contract; does not claim in-game placement QA."""
import argparse
import json
from pathlib import Path
import numpy as np
from check_verona_bridge_assets import read_glb, accessor, primitives, lod_triangles, require
ROOT=Path(__file__).resolve().parents[2]


def audit(slug):
    path=ROOT/'app/assets/environment'/slug/(slug+'.glb');doc,data=read_glb(path)
    require(len(doc.get('materials',[]))==1,'Expected single material')
    require(doc['materials'][0].get('alphaMode','OPAQUE')=='OPAQUE','Opaque material required')
    require(not doc.get('textures'),'Unexpected texture dependency')
    rows=[]
    for tag in ('detail','medium','far'):
        mesh=lod_triangles(doc,data,tag);lo=mesh.min(axis=(0,1));hi=mesh.max(axis=(0,1))
        require(np.allclose(lo,[-.35,-.14,0],atol=1e-6),'Footprint or contact changed')
        require(np.allclose(hi,[.35,.14,.16],atol=1e-6),'Dimensions changed')
        area=np.linalg.norm(np.cross(mesh[:,1]-mesh[:,0],mesh[:,2]-mesh[:,0]),axis=1)*.5
        require(np.all(area>1e-9),'Degenerate exported triangle')
        # Weld exported face-normal/colour seams before checking watertightness.
        verts=mesh.reshape(-1,3);_,ids=np.unique(np.round(verts,6),axis=0,return_inverse=True)
        tri=ids.reshape(-1,3);edges=np.sort(np.concatenate([tri[:,[0,1]],tri[:,[1,2]],tri[:,[2,0]]]),axis=1)
        _,counts=np.unique(edges,axis=0,return_counts=True)
        require(np.all(counts==2),'Open/non-manifold stone surface')
        volume=np.sum(np.einsum('ij,ij->i',mesh[:,0],np.cross(mesh[:,1],mesh[:,2])))/6
        require(volume>.01,'Inverted surface or collapsed stone volume')
        # Ramp ends must be traversable at the declared heights, with no upward
        # spike anywhere beyond the linear envelope (bevels may sit beneath it).
        if slug.endswith('_end'):
            bound=.16-(verts[:,0]+.35)*.14/.7
            require(np.all(verts[:,2]<=bound+1e-6),'Ramp overshoots descending envelope')
            require(abs(verts[verts[:,0]>.34,2].max()-.02)<.003,'Low ramp end too tall')
        node=next(i for i,n in enumerate(doc['nodes']) if n.get('name')=='Model_'+tag)
        parts=list(primitives(doc,node));require(len(parts)==1,'Multiple material batches')
        attrs=parts[0]['attributes'];require('COLOR_0' in attrs,'Missing vertex colour')
        colours=accessor(doc,data,attrs['COLOR_0']);require(np.unique(colours[:,:3],axis=0).shape[0]>=3,'Face tones lost')
        rows.append({'lod':tag,'triangles':len(mesh),'bounds_xyz_m':[lo.tolist(),hi.tolist()],'closed_volume_m3':volume})
    require(rows[0]['triangles']>rows[1]['triangles']>rows[2]['triangles'],'LOD cost does not decrease')
    require('meshes/generate_lods=false' in path.with_suffix('.glb.import').read_text(),'Automatic LOD enabled')
    return {'asset':slug,'lods':rows}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=ROOT/'build/verona-street-edges/asset-validation.json');a=p.parse_args()
    report={'status':'asset_geometry_validated_not_game_validated','assets':[],'failures':[]}
    for slug in ['street_kerb','street_kerb_end']:
        try:report['assets'].append(audit(slug))
        except Exception as e:report['failures'].append(f'{slug}: {e}')
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report));raise SystemExit(bool(report['failures']))
