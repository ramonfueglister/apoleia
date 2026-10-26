#!/usr/bin/env python3
"""Reacquire original physical inputs using frozen source manifest URLs/hashes."""
import pathlib,json,subprocess,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
for s in json.loads((ROOT/'data/sources.json').read_text())['sources']:
 if s['id'] not in ['ne-land','ne-rivers','ne-lakes']:continue
 p=ROOT/s['artifact_path'];p.parent.mkdir(parents=True,exist_ok=True)
 if not p.exists():subprocess.run(['curl','-fLsS','--max-time','180','-o',str(p),s['url']],check=True)
 actual=hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
 if actual!=s['sha256']:raise RuntimeError('Source hash changed: '+s['id'])
 print(s['id'],actual)
