#!/usr/bin/env python3
"""Source-free r2→r3 exact existing-vertex Parentstar edge-noding migration."""
import pathlib,json,struct,hashlib,os,copy
import numpy as np
from terrain_mesh_topology import node_existing_edges,topology
ROOT=pathlib.Path(__file__).resolve().parents[1]
def enc(x):return json.dumps(x,separators=(',',':'),ensure_ascii=False).encode()
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
    source=ROOT/'artifacts/render-data/terrain-blocks-source-v2-r2';out=ROOT/'artifacts/render-data/terrain-blocks-source-v2-r3'
    if out.exists():raise RuntimeError('refuse existing revision')
    manifest=json.loads((source/'tree.json').read_text());old_manifest_sha=sha(source/'tree.json');out.mkdir();(out/'blocks').mkdir();results=[];changed=[]
    origin=np.array(manifest['world_min']);spacing=np.array(manifest['spacing']);anchors=manifest['atlas_identity']['anchors']
    for id,b in manifest['blocks'].items():
        begin=np.array(b['grid_begin']);end=np.array(b['grid_end']);stride=b['stride'];regular=int(np.prod(np.ceil((end-begin)/stride).astype(int)+1));stars=set()
        for a in anchors:
            cell=np.floor((np.array([a['world_x'],a['world_z']])-origin)/spacing).astype(int)
            if np.all(cell>=begin) and np.all(cell<end):stars.add(tuple((cell-begin)//stride))
        src=source/b['payload']['path'];dst=out/b['payload']['path']
        if b['vertex_count']<=regular+len(stars):os.link(src,dst);continue
        data=src.read_bytes();assert hashlib.sha256(data).hexdigest()==b['payload']['sha256'];n=struct.unpack_from('<I',data,4)[0];h=json.loads(data[8:8+n]);offset=8+n
        def field(name,dtype,components=1):
            s=h['sections'][name];a=np.frombuffer(data,dtype,s['bytes']//np.dtype(dtype).itemsize,offset+s['offset']);return a.reshape(-1,components) if components>1 else a
        original=field('vertices','<f4',3);old_ix=field('indices','<i4');old_norm=field('normals','<f4',3);old_parent=field('parent_y','<f4')
        v,norm,py,ix,gids,stats=node_existing_edges(original,old_norm,old_parent,old_ix);check=topology(v,ix,gids)
        assert check['Euler']==1 and check['inner_unpaired_edges']==0 and check['nonmanifold_edges']==0,(id,check)
        assert v[:len(original)].tobytes()==original.tobytes() and norm[:len(old_norm)].tobytes()==old_norm.tobytes() and py[:len(old_parent)].tobytes()==old_parent.tobytes()
        old_points={p.tobytes() for p in original};assert all(p.tobytes() in old_points for p in v)
        sections={};body=bytearray()
        for name,array in [('vertices',v),('normals',norm),('parent_y',py),('indices',ix),('geometry_ids',gids)]:
            raw=np.asarray(array).tobytes();sections[name]={'offset':len(body),'bytes':len(raw),'components':3 if name in ('vertices','normals') else 1};body.extend(raw)
        s=h['sections']['atlas_rg8'];raw=data[offset+s['offset']:offset+s['offset']+s['bytes']];sections['atlas_rg8']={'offset':len(body),'bytes':len(raw),'components':2};body.extend(raw)
        h['sections']=sections;h['vertex_count']=len(v);h['index_count']=len(ix);h['topology_revision']='existing-f32-edge-noding-r1';hb=enc(h);newdata=b'TBL1'+struct.pack('<I',len(hb))+hb+body;dst.write_bytes(newdata)
        b['vertex_count']=len(v);b['index_count']=len(ix);b['geometry_bytes']=len(body);b['decoded_bytes']=len(body)+b['material_bytes'];b['payload']={'path':b['payload']['path'],'bytes':len(newdata),'sha256':sha(dst)};b['topology_revision']='existing-f32-edge-noding-r1';changed.append(id);results.append({'id':id,**stats,**check})
    for b in manifest['blocks'].values():
        if b['parent'] is not None:b['parent_payload_sha256']=manifest['blocks'][b['parent']]['payload']['sha256']
    manifest['dataset_revision']='terrain-blocks-source-v2-r3';manifest['topology_revision']='existing-f32-edge-noding-r1';manifest['derivation_parent_manifest_sha256']=old_manifest_sha;manifest['contracts']['geometry_ids']='exact existing F32 XZ + bit-identical child/parent Y; separate normal corner instances; adjacent original faces noded without vertex displacement';manifest['payload_bytes']=sum(b['payload']['bytes'] for b in manifest['blocks'].values());(out/'tree.json').write_bytes(enc(manifest)+b'\n');digest=sha(out/'tree.json');(out/'READY.json').write_bytes(enc({'manifest_sha256':digest,'blocks':len(manifest['blocks']),'complete':True})+b'\n')
    (out/'TOPOLOGY-REPAIR.json').write_text(json.dumps({'status':'validated actual raw geometric topology; active LOD/render validation pending','source_manifest_sha256':old_manifest_sha,'manifest_sha256':digest,'changed_blocks':changed,'checks':results,'normal_contract':'existing corners unchanged; inserted corners interpolate original-face edge normals; geometric IDs independent','source_reads':0,'vertex_displacements':0},indent=2)+'\n');print(json.dumps({'manifest_sha256':digest,'changed_blocks':len(changed),'payload_bytes':manifest['payload_bytes'],'new_physical_payload_bytes':sum(manifest['blocks'][i]['payload']['bytes'] for i in changed),'path':str(out/'tree.json')}))
if __name__=='__main__':main()
