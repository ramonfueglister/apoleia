#!/usr/bin/env python3
"""Write the A16 NA revision of a local-only derivation-view.json.

usage: apply_na.py RUN_DIR OUT_DIR
RUN_DIR is a full local copy of runs/kit1-landscape-v5-2026-10-25 (the
derivation view is gitignored). Writes OUT_DIR/derivation-view.json with
not-applicable.json added and checks the expected SHA-256.
"""
import hashlib, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE_SHA = '70787790435205de0cb678cbcbb609df10d4d694809473214b766e2d6c96cc88'
RESULT_SHA = 'c1ea9d503f38'

run, out = Path(sys.argv[1]), Path(sys.argv[2])
source = run / 'data-report-errata/release-v2/derivation-view.json'
if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA:
    raise SystemExit('unexpected source derivation-view.json')
view = json.loads(source.read_text())
view['not_applicable'] = json.loads((HERE / 'not-applicable.json').read_text())
raw = (json.dumps(view, indent=2) + '\n').encode()
digest = hashlib.sha256(raw).hexdigest()
if not digest.startswith(RESULT_SHA):
    raise SystemExit('result differs from the recorded revision: ' + digest)
out.mkdir(parents=True, exist_ok=True)
(out / 'derivation-view.json').write_bytes(raw)
print(digest)
