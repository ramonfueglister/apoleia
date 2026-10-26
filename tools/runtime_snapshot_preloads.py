#!/usr/bin/env python3
"""Exact local preload closure added to snapshot copy includes, never a full asset resolver."""
from pathlib import Path
import argparse
import hashlib
import json
import re

PATTERN = re.compile(r'\bpreload\s*\(\s*[\"\']res://([^\"\']+)[\"\']\s*\)')

def closure(app: Path, entry='scripts/landscape.gd'):
    app = app.resolve()
    pending, files, edges = [entry], {}, []
    while pending:
        relative = pending.pop()
        if relative in files:
            continue
        path = (app / relative).resolve()
        if not path.is_relative_to(app) or not path.is_file():
            raise ValueError('missing or escaping runtime preload: ' + relative)
        raw = path.read_bytes()
        files[relative] = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)}
        if path.suffix != '.gd':
            continue
        for target in PATTERN.findall(raw.decode('utf-8')):
            edges.append([relative, target])
            pending.append(target)
    return {'files': files, 'edges': edges,
            'contract': 'Union these actual transitive preloads into copy includes; retain separately inventoried shaders, scenes, dynamic resources and assets. Missing preload aborts before publishing a snapshot.'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-app', type=Path, required=True)
    parser.add_argument('--entry', default='scripts/landscape.gd')
    args = parser.parse_args()
    print(json.dumps(closure(args.source_app, args.entry), indent=2))
