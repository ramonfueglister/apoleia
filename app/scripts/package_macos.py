#!/usr/bin/env python3
"""Assemble a local runnable Mac bundle using the already installed engine.
No SDK, export template, signing certificate, service, or publication required.
"""
import argparse,hashlib,json,os,pathlib,plistlib,shutil,subprocess
root=pathlib.Path(__file__).resolve().parents[2]
engine=pathlib.Path(shutil.which(os.environ.get('GODOT_BIN','godot'))).resolve()
manifest=json.loads((root/'data/derived/landscape.json').read_text())
parser=argparse.ArgumentParser();parser.add_argument('--output',type=pathlib.Path);args=parser.parse_args()
out=args.output.resolve() if args.output else root/'artifacts/Roma Aeterna.app'
if out.exists():raise SystemExit('Refusing to overwrite an existing bundle; keep verified artifacts distinct.')
mac=out/'Contents/MacOS';world=out/'Contents/Resources/world'
mac.mkdir(parents=True);world.mkdir(parents=True)
shutil.copy2(engine,mac/'godot-runtime')
shutil.copytree(root/'app',world/'app',ignore=shutil.ignore_patterns('.godot','__pycache__','override.cfg'))
(world/'data/derived').mkdir(parents=True)
(world/'artifacts/render-data').mkdir(parents=True)
for name in ['height-packing.json','height-rg8.bin','water-distance-rg8.json','water-distance-rg8.bin']:
 shutil.copy2(root/'artifacts/render-data'/name,world/'artifacts/render-data'/name)
for asset in manifest['assets'].values():
 p=asset['path']
 destination=world/'data/derived'/p
 destination.parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(root/'data/derived'/p,destination)
shutil.copy2(root/'data/derived/landscape.json',world/'data/derived/landscape.json')
for name in ['anchors.json','projection.json','tile-grid.json','sources.json','region.json','transformations.json','geodata_policy.json','protection-rules.json','detail-rules.json','source-accuracy.json','policy-decision.json','source-topology-quality.json','sampling-plan.json','worldcover-inventory.json','etopo15-inventory.json','adm2-selection.json']:
 shutil.copy2(root/'data'/name,world/'data'/name)
(world/'docs/product-renderer').mkdir(parents=True)
for name in ['camera-profile.json','water-distance-policy-v2.json','TECHNICAL_DECISION.md','START.md']:
 shutil.copy2(root/'docs/product-renderer'/name,world/'docs/product-renderer'/name)
shutil.copytree(root/'docs/product-data',world/'docs/product-data')
launcher=mac/'RomaAeterna'
launcher.write_text('''#!/bin/sh
set -eu
LAUNCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$LAUNCH_DIR/godot-runtime" --path "$LAUNCH_DIR/../Resources/world/app" "$@"
''');launcher.chmod(0o755)
with (out/'Contents/Info.plist').open('wb') as f:
 plistlib.dump({'CFBundleName':'Roma Aeterna','CFBundleDisplayName':'Roma Aeterna','CFBundleIdentifier':'local.romaaeterna.landscape','CFBundleVersion':'1','CFBundleShortVersionString':'0.1','CFBundlePackageType':'APPL','CFBundleExecutable':'RomaAeterna','NSHighResolutionCapable':True},f)
license_file=out/'Contents/Resources/GODOT-LICENSE-AND-NOTICES.txt'
subprocess.run([str(engine),'--headless','--path',str(root/'app'),'--log-file',str(root/'artifacts/runtime/package-license.log'),'--script','res://scripts/engine_license.gd','--',str(license_file)],check=True)
build={'schema_version':'local-macos-bundle-v1','dataset_revision':manifest['dataset_revision'],'dataset_manifest_sha256':hashlib.sha256((root/'data/derived/landscape.json').read_bytes()).hexdigest(),'engine_binary_sha256':hashlib.sha256(engine.read_bytes()).hexdigest(),'packaging':'local project bundle with existing Godot binary; unsigned, not notarized, no release published','platform_tested':'Mac only, actual GPU evidence separate'}
(out/'Contents/Resources/build.json').write_text(json.dumps(build,indent=2))
records=[]
for p in sorted(out.rglob('*')):
 if p.is_file():
  with p.open('rb') as f: digest=hashlib.file_digest(f,'sha256').hexdigest()
  records.append({'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':digest})
(out/'Contents/Resources/package-inventory.json').write_text(json.dumps({'revision':'package-inventory-v1','files':records,'mutable_runtime_paths_excluded':['Contents/Resources/world/app/.godot/','Contents/Resources/world/artifacts/runtime/'],'notices':'Engine notices and exact source/data attribution included; no general legal assurance'},indent=2))
print(out)
