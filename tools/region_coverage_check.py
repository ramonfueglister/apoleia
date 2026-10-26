#!/usr/bin/env python3
"""A02 region coverage check of the bound render data (stdlib only, headless).

Reads data/region.json, data/projection.json and app/renderer-binding.json and
checks, per required sub-region (Reich 117, gesamtes Mittelmeer, England +
Nordpuffer), whether every expected 128-km base tile is present in each bound
layer: clipmap pyramid (height/material/water PNG on every level + shore
sidecars), forest layout (chunk index), atlas, upload domains, coast field and
source rivers. Large payloads usually live only on the build Mac; pass that
checkout with --data-root. Layers whose files are absent are reported as
UNCHECKED, never as covered.

Exit codes: 0 all covered, 1 at least one gap, 3 no gap but something unchecked
(0 with --allow-unchecked). Only metadata/index files are read; PNG content,
NoData inside payloads and runtime rendering are not inspected.
"""
import argparse, hashlib, json, math, struct, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BASE_SPAN = 128.0  # clipmap base tile = forest layout chunk (model km)
SUBREGIONS = [
    ('reich_117', 'imperial_maximum_extent'),
    ('mittelmeer', 'entire_mediterranean'),
    ('england_nordpuffer', 'england_and_northern_context'),
]


def read(path):
    return json.loads(Path(path).read_text())


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


class Projection:
    def __init__(self, p):
        self.r = float(p['radius_m']); self.lat0 = float(p['center_latitude'])
        self.lon0 = float(p['center_longitude']); self.scale = float(p['model_scale'])

    def world(self, lon, lat):
        return (self.scale * self.r * math.cos(math.radians(self.lat0)) * math.radians(lon - self.lon0),
                self.scale * self.r * math.radians(self.lat0 - lat))

    def rect(self, b):
        """Geographic bounds -> model rect (x0, z0, x1, z1); north is smaller z."""
        x0, z0 = self.world(b['west'], b['north']); x1, z1 = self.world(b['east'], b['south'])
        return (x0, z0, x1, z1)


def contains(outer, inner, eps=1e-6):
    return (outer[0] <= inner[0] + eps and outer[1] <= inner[1] + eps
            and outer[2] >= inner[2] - eps and outer[3] >= inner[3] - eps)


def rect_from(world_min, world_size):
    return (world_min[0], world_min[1], world_min[0] + world_size[0], world_min[1] + world_size[1])


def fmt(r):
    return '[%.1f,%.1f..%.1f,%.1f]' % r


def subregions(region, proj):
    geoms = {g['id']: g for g in region['reference_geometries']}
    out = []
    for name, gid in SUBREGIONS:
        b = dict(geoms[gid]['extent'])
        if gid == 'england_and_northern_context':
            # Northern buffer above England, as bound in region.json.
            b['north'] = float(region['england_north_latitude']) + float(region['north_context_degrees'])
        out.append({'name': name, 'reference_id': gid, 'bounds': b, 'rect': proj.rect(b)})
    return out


def base_tiles(rect, origin):
    """Base tiles (index relative to origin) intersecting rect, half-open."""
    x0 = math.floor((rect[0] - origin[0]) / BASE_SPAN); x1 = math.ceil((rect[2] - origin[0]) / BASE_SPAN)
    z0 = math.floor((rect[1] - origin[1]) / BASE_SPAN); z1 = math.ceil((rect[3] - origin[1]) / BASE_SPAN)
    return [(x, z) for z in range(z0, z1) for x in range(x0, x1)]


class Report:
    def __init__(self):
        self.rows = []; self.gaps = 0; self.unchecked = 0

    def add(self, sub, layer, status, detail='', missing=None):
        missing = missing or []
        if status == 'GAP': self.gaps += 1
        if status == 'UNCHECKED': self.unchecked += 1
        self.rows.append({'subregion': sub, 'layer': layer, 'status': status, 'detail': detail,
                          'missing_count': len(missing), 'missing': missing})


def resolve(root, base, rel):
    for cand in (base / rel, root / rel):
        if cand.exists():
            return cand
    return base / rel


def check_static(root, region, coverage, proj, subs, rep):
    ext = proj.rect(region['extent'])
    for s in subs:
        ok = contains(ext, s['rect'])
        rep.add(s['name'], 'region.json extent', 'OK' if ok else 'GAP',
                'reference %s in region extent %s' % (fmt(s['rect']), fmt(ext)))
        comp = {c['id']: c for c in coverage.get('reference_components', [])}.get(s['reference_id'])
        good = comp is not None and comp.get('represented_fraction') == 1 and coverage.get('region_revision') == region['revision']
        rep.add(s['name'], 'coverage.json component', 'OK' if good else 'GAP',
                'run %s, region %s' % (coverage.get('run_id'), coverage.get('region_revision')))


def check_rect_layer(root, rel, expected_sha, label, extract, subs, rep):
    path = root / rel
    if not path.is_file():
        for s in subs: rep.add(s['name'], label, 'UNCHECKED', 'missing ' + rel)
        return None
    note = ''
    if expected_sha and sha(path) != expected_sha: note = ' (sha256 differs from binding)'
    data = read(path)
    for name, rect in extract(data, path):
        for s in subs:
            ok = contains(rect, s['rect'])
            rep.add(s['name'], label + name, 'OK' if ok else 'GAP',
                    'layer %s%s' % (fmt(rect), note) if ok else
                    'layer %s does not contain %s%s' % (fmt(rect), fmt(s['rect']), note))
    return data


def check_clipmap(root, binding, subs, rep):
    cfg = binding.get('clipmap') or {}
    if not cfg.get('enabled'):
        for s in subs: rep.add(s['name'], 'clipmap', 'N/A', 'clipmap disabled in binding')
        return None
    path = root / cfg['path']
    if not path.is_file():
        for s in subs: rep.add(s['name'], 'clipmap', 'UNCHECKED', 'missing ' + cfg['path'])
        return None
    m = read(path); d = path.parent
    origin = m['origin']; counts = m['tile_counts']; maxlevel = int(m['max_level'])
    world = rect_from(m['world_min'], m['world_size'])
    ready = (d / 'READY').read_text().strip() if (d / 'READY').is_file() else None
    total = sum(math.ceil(counts[0] / 2 ** l) * math.ceil(counts[1] / 2 ** l) for l in range(maxlevel + 1))
    for s in subs:
        if not contains(world, s['rect']):
            rep.add(s['name'], 'clipmap world', 'GAP', 'pyramid world %s does not contain %s' % (fmt(world), fmt(s['rect'])))
        tiles = [t for t in base_tiles(s['rect'], origin) if 0 <= t[0] < counts[0] and 0 <= t[1] < counts[1]]
        outside = len(base_tiles(s['rect'], origin)) - len(tiles)
        missing = {}; shores = []
        for level in range(maxlevel + 1):
            ids = sorted({(x >> level, z >> level) for x, z in tiles})
            for x, z in ids:
                tid = '%d/%d/%d' % (level, x, z)
                absent = [f for f in m['fields'] if not (d / str(level) / str(x) / ('%d-%s.png' % (z, f))).is_file()]
                if absent: missing.setdefault(level, []).append(tid + ':' + '+'.join(absent))
                elif not (d / str(level) / str(x) / ('%d-shore.bin' % z)).is_file(): shores.append(tid)
        flat = [t for level in sorted(missing) for t in missing[level]]
        by_level = ', '.join('L%d=%d' % (l, len(v)) for l, v in sorted(missing.items())) or 'none'
        rep.add(s['name'], 'clipmap terrain tiles', 'GAP' if flat or outside else 'OK',
                '%d base tiles (all %d levels, pyramid %d tiles), READY=%r, missing by level: %s%s'
                % (len(tiles), maxlevel + 1, total, ready, by_level,
                   ', %d base tiles outside tile_counts' % outside if outside else ''), flat)
        rep.add(s['name'], 'clipmap shore sidecars', 'GAP' if shores else 'OK',
                'present tiles without -shore.bin: %d' % len(shores), shores)
    if ready != 'complete':
        for s in subs: rep.add(s['name'], 'clipmap READY', 'GAP', 'READY=%r (build_clipmap_tiles writes "complete" only for an unrestricted full build)' % ready)
    return m


def check_forest_layout(root, binding, clip, subs, rep):
    fr = binding.get('forest_rendering', {})
    entry = fr.get('streaming_layout') if binding.get('clipmap', {}).get('enabled') and fr.get('streaming_layout') else fr.get('layout')
    if not entry:
        for s in subs: rep.add(s['name'], 'forest layout', 'N/A', 'no layout bound')
        return
    d = root / entry['path']; mp = d / 'manifest.json'
    label = 'forest layout ' + Path(entry['path']).name
    if not mp.is_file():
        for s in subs: rep.add(s['name'], label, 'UNCHECKED', 'missing %s/manifest.json' % entry['path'])
        return
    m = read(mp); cb = m.get('chunk_bounds') or [-42, -18, 40, 20]
    note = '' if sha(mp) == entry.get('manifest_sha256') else ' (manifest sha256 differs from binding)'
    width = cb[2] - cb[0]; full = width * (cb[3] - cb[1])
    index = {}
    lref = m.get('layout') or {}
    lpath = resolve(root, d, lref['path']) if isinstance(lref, dict) and lref.get('path') else None
    if lpath and lpath.is_file():
        with open(lpath, 'rb') as f:
            head = f.read(128)
            if head[:8] == b'V19LAY01':
                raw = f.read(128 * full)
                for i in range(len(raw) // 128):
                    index[(cb[0] + i % width, cb[1] + i // width)] = struct.unpack_from('<I', raw, i * 128 + 12)[0]
    complete = m.get('coverage', 'complete') == 'complete' and m.get('chunk_count') == full
    ready = (d / 'READY').is_file()
    origin = [0.0, 0.0]  # layout cell = floor(model/128)
    if clip:
        off = [int(clip['origin'][0] / BASE_SPAN), int(clip['origin'][1] / BASE_SPAN)]
        if off != [cb[0], cb[1]]: note += ' (clipmap origin %s differs from layout chunk_bounds %s)' % (off, cb[:2])
    for s in subs:
        cells = base_tiles(s['rect'], origin)
        if index:
            miss = ['%d,%d' % c for c in cells if c not in index]
            records = sum(index.get(c, 0) for c in cells)
            src = 'layout.bin index'
        else:
            miss = ['%d,%d' % c for c in cells if not (cb[0] <= c[0] < cb[2] and cb[1] <= c[1] < cb[3])]
            records = None; src = 'manifest chunk_bounds only (layout.bin absent)'
        if not complete: miss = miss or ['manifest coverage=%r chunk_count=%r' % (m.get('coverage'), m.get('chunk_count'))]
        if not ready: miss.append('READY missing')
        rep.add(s['name'], label, 'GAP' if miss else ('OK' if index else 'UNCHECKED'),
                '%d cells via %s, %s records%s' % (len(cells), src, records if records is not None else '?', note), miss)


def check_rivers(root, source_path, subs, rep, proj):
    src = root / source_path
    if not src.is_file():
        for s in subs: rep.add(s['name'], 'rivers', 'UNCHECKED', 'missing ' + source_path)
        return
    m = read(src); rel = m.get('rivers_path')
    path = resolve(root, src.parent, rel) if rel else None
    if not path or not path.is_file():
        for s in subs: rep.add(s['name'], 'rivers', 'UNCHECKED', 'rivers_path %r not found' % rel)
        return
    feats = read(path).get('features', [])
    boxes = []
    for f in feats:
        pts = []
        def walk(c):
            if c and isinstance(c[0], (int, float)): pts.append(c)
            else:
                for k in c: walk(k)
        walk(f.get('geometry', {}).get('coordinates', []))
        if pts: boxes.append((min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts)))
    for s in subs:
        b = s['bounds']
        n = sum(1 for x0, y0, x1, y1 in boxes if x1 >= b['west'] and x0 <= b['east'] and y1 >= b['south'] and y0 <= b['north'])
        rep.add(s['name'], 'rivers', 'OK' if n else 'GAP', '%d of %d source river features intersect' % (n, len(feats)))


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--data-root', default=str(REPO), help='checkout holding artifacts/ and data/ (e.g. the build Mac)')
    p.add_argument('--binding', default='app/renderer-binding.json')
    p.add_argument('--json', help='write machine-readable result here')
    p.add_argument('--max-list', type=int, default=20, help='missing tiles listed per row')
    p.add_argument('--allow-unchecked', action='store_true')
    a = p.parse_args()
    root = Path(a.data_root).resolve()
    region = read(root / 'data/region.json'); proj = Projection(read(root / 'data/projection.json'))
    coverage = read(root / 'data/coverage.json'); binding = read(root / a.binding)
    subs = subregions(region, proj); rep = Report()
    check_static(root, region, coverage, proj, subs, rep)
    clip = check_clipmap(root, binding, subs, rep)
    check_forest_layout(root, binding, clip, subs, rep)
    check_rect_layer(root, binding['atlas']['path'], binding['atlas'].get('sha256'), 'atlas',
                     lambda m, _: [('', rect_from(m['world_min'], m['world_size']))], subs, rep)
    check_rect_layer(root, binding['coast']['path'], binding['coast'].get('sha256'), 'coast distance',
                     lambda m, _: [('', rect_from(m['world_min'], m['world_size']))], subs, rep)

    def upload_rects(m, _):
        out = []
        for dom in ('context', 'fine'):  # 'local' is an intentional small native-detail patch
            for field, v in sorted((m.get('domains', {}).get(dom) or {}).items()):
                if isinstance(v, dict) and 'world_min' in v:
                    out.append((' %s.%s' % (dom, field), rect_from(v['world_min'], v['world_size'])))
        return out
    check_rect_layer(root, binding['upload']['path'], binding['upload'].get('sha256'), 'upload', upload_rects, subs, rep)
    check_rivers(root, binding['source']['path'], subs, rep, proj)

    print('A02 region coverage, data root %s' % root)
    for s in subs:
        b = s['bounds']
        print('\n== %s (%s) lon %.2f..%.2f lat %.2f..%.2f, model %s' % (s['name'], s['reference_id'], b['west'], b['east'], b['south'], b['north'], fmt(s['rect'])))
        for r in rep.rows:
            if r['subregion'] != s['name']: continue
            print('  %-9s %-34s %s' % (r['status'], r['layer'], r['detail']))
            if r['missing']:
                more = r['missing_count'] - a.max_list
                print('            missing: ' + ', '.join(r['missing'][:a.max_list]) + (' ... +%d' % more if more > 0 else ''))
    print('\nsummary: %d gap rows, %d unchecked rows' % (rep.gaps, rep.unchecked))
    if a.json:
        Path(a.json).write_text(json.dumps({'revision': 'region-coverage-check-r1', 'data_root': str(root), 'subregions': subs,
                                            'gaps': rep.gaps, 'unchecked': rep.unchecked, 'rows': rep.rows}, indent=2) + '\n')
    if rep.gaps: return 1
    if rep.unchecked and not a.allow_unchecked: return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())
