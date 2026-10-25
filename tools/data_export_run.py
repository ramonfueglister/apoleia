#!/usr/bin/env python3
"""Freeze product data inside a Kit run: hard links for large immutable inputs.
No symlinks; existing equal hashes accepted; changed files fail rather than overwrite.
"""
import pathlib,sys,os,hashlib,shutil,json
ROOT=pathlib.Path(__file__).resolve().parents[1];RUN=pathlib.Path(sys.argv[1]).resolve()
UPDATE='--update-v3' in sys.argv[2:]
if UPDATE:
 assert json.loads((ROOT/'data/derived/landscape.json').read_text())['dataset_revision']=='landscape-v3'
 assert (RUN/'data-revisions/landscape-v2/data/derived/landscape.json').exists(), 'Preserve v2 before revisionupdate'
 legacy=RUN/'data/raw/ETOPO_2022_v1_60s_N90W180_surface.tif'
 if legacy.exists():legacy.unlink()
def digest(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
for p in (ROOT/'data').rglob('*'):
 if not p.is_file() or p.suffix in ['.log','.headers'] or p.name in ['.gitignore','ETOPO_2022_v1_60s_N90W180_surface.tif']:continue
 dst=RUN/p.relative_to(ROOT);dst.parent.mkdir(parents=True,exist_ok=True)
 if dst.exists():
  if digest(p)==digest(dst):continue
  if not UPDATE:raise RuntimeError('Different frozen existing artifact: '+str(dst))
  dst.unlink()
 try:os.link(p,dst)
 except OSError:shutil.copy2(p,dst)
print('Frozen data artifacts in',RUN/'data')

# Kit resolves artifacts against root manifest directory. Preserve data/... refs.
for name in ['sources','region','coverage','geodata_policy','derivation']:
 src=ROOT/'data'/(name+'.json');dst=RUN/(name+'.json')
 if not src.exists():continue
 if dst.exists():
  old=json.loads(dst.read_text())
  if old.get('revision')=='unbound' or (old.get('kind')=='derivation' and old.get('build_revision') is None and not old.get('level_measurements')) or UPDATE:dst.unlink()
  elif digest(src)!=digest(dst):raise RuntimeError('Existing bound rootmanifest differs: '+str(dst))
 if not dst.exists():os.link(src,dst)
for name in ['docs/product-renderer/camera-profile.json']:
 src=ROOT/name;dst=RUN/name;dst.parent.mkdir(parents=True,exist_ok=True)
 if src.exists():
  if dst.exists() and digest(src)!=digest(dst):
   if not UPDATE:raise RuntimeError('Changed camera profile requires explicitrevisionupdate')
   dst.unlink()
  if not dst.exists():os.link(src,dst)
