#!/usr/bin/env python3
"""Six actual source-protected massif windows, same frozen scene and renderer."""
import argparse,hashlib,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--out',required=True,type=pathlib.Path);a=p.parse_args();a.out=a.out.resolve();a.out.mkdir(parents=True,exist_ok=True)
root=pathlib.Path(__file__).resolve().parents[2];protection=root/'data/protection-rules.json';control=json.loads(protection.read_text());rows=[]
plan={'revision':'ridge-windows-v1','source_protection_sha256':hashlib.file_digest(protection.open('rb'),'sha256').hexdigest(),'windows':[{'anchor_id':f'protected-ridge-{i}','longitude':q[0],'latitude':q[1],'zoom':.7,'viewport':[1920,1080],'frames':30}for i,q in enumerate(control['ridges']['anchors'])],'method':'same actual native scene; each protected source anchor receives its own 30-frame near-regional window, then an unretouched PNG plus actual camera/ridge/LOD records; no terrain modification'}
(a.out/'plan.json').write_text(json.dumps(plan,indent=2))
for w in plan['windows']:
 out=a.out/w['anchor_id'];out.mkdir(exist_ok=True)
 cmd=[str(root/'scripts/run-landscape'),'--rendering-method','mobile','--resolution','1920x1080','--','--snapshot','--view',str(w['longitude']),str(w['latitude']),str(w['zoom']),'--capture-dir',str(out)]
 with(out/'launch.log').open('w')as log:result=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT)
 if result.returncode:raise SystemExit(f'Ridge window failed: {w["anchor_id"]}')
 runtime=json.loads((out/'runtime.json').read_text());sample=runtime['samples'][-1];probe=next(q for q in sample['ridge_probes']if q['anchor_id']==w['anchor_id']);rows.append({'anchor_id':w['anchor_id'],'command':cmd,'exit_code':result.returncode,'runtime_sha256':hashlib.file_digest((out/'runtime.json').open('rb'),'sha256').hexdigest(),'image':str(out/'frame_000030.png'),'in_viewport':probe['in_viewport'],'source_height_m':probe['source_surface_height_m'],'rendered_height_model':probe['rendered_height_model'],'renderer_asset_sha256':runtime['renderer_asset_sha256'],'dataset_manifest_sha256':runtime['manifest_sha256']})
 if not probe['in_viewport']:raise SystemExit('Protected ridge anchor missing from its planned actual viewport')
(a.out/'ridge-windows.json').write_text(json.dumps({'plan':plan,'windows':rows},indent=2));print(json.dumps({'window_count':len(rows),'all_visible':all(r['in_viewport']for r in rows)}))
