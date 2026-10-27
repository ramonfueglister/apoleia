#!/usr/bin/env python3
"""Capture A08/A16 evidence frames with a provenance manifest.

One --snapshot per pose and weather variant in a 640x360 window (never larger,
never fullscreen), each run under the shared perf lock. Per frame the evidence
directory gets:
  <id>.png                 the app capture as full RGB PNG (lossless, no palette)
  crops/<id>-1to1.png      a 1:1 centre crop of the capture (256x256)
  excerpts/<id>.json       clipmap state at the capture frame (clipmap_frames),
                           startup timeline, coverage gate and pipeline counts
  runtime/<id>.json.gz     the runtime.json trimmed to the fields above plus the
                           last samples, for recomputation
and manifest.json lists command, pose, camera, weather arguments, the hashes of
renderer-binding.json, dataset manifest, renderer source and geodata policy.

usage: tools/kit1_capture_evidence.py {a08,a16} OUT_DIR [--variants weather,control]
"""
import argparse
import gzip
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOCK = Path.home() / 'Coding/.romaaeterna-perf-lock'
LOCK_STALE_S = 600
RUN_TIMEOUT_S = 150
WINDOW = ['--windowed', '--resolution', '640x360', '--position', '0,0']
VARIANTS = {
    'weather': ['--weather=fair', '--weather-seed=1'],
    'control': ['--weather=clear', '--weather-seed=1'],
}
ROME = (12.45, 42.0)
ALPS = (8.991666, 46.008335)
# (id, lon, lat, legacy zoom for --view, optional --width-source-m, pose source)
POSES = {
    'a08': [
        ('overview', 17.5, 39.5, 0.0, None, 'fixture state-overview'),
        ('alps-012', *ALPS, 0.12, None, 'fixture state-alps-012'),
        ('alps-out', *ALPS, 0.35, None, 'fixture state-alps-out'),
        ('alps-mid', *ALPS, 0.5, None, 'fixture state-alps-mid'),
        ('alps-near', *ALPS, 1.0, None, 'fixture state-alps-near'),
        ('england-mid', -1.5, 54.0, 0.35, None, 'fixture state-england-mid'),
        # Zoom 0.0 clamps the camera to the region overview, so a Rome-centred
        # far pose needs an explicit width below the overview width.
        ('rome-far', *ROME, 0.0, 3000000, 'Rome-centred far (3000 km view width)'),
        ('rome-mid', *ROME, 0.5, None, 'Rome mid'),
        ('rome-near', *ROME, 1.0, None, 'Rome near (legacy 240 km)'),
        ('rome-40km', *ROME, 1.0, 40000, 'Rome at NEAR_WIDTH'),
        ('alps-40km', *ALPS, 1.0, 40000, 'Alps at NEAR_WIDTH'),
    ],
    'a16': [(f'rome-zoom-{z:.1f}', *ROME, z, None, 'legacy zoom step') for z in [i / 10 for i in range(11)]]
           + [(f'rome-width-{w // 1000}km', *ROME, 1.0, w, 'width step to NEAR_WIDTH')
              for w in (200000, 160000, 120000, 90000, 60000, 40000)],
}
TRIM_KEYS = ['startup_timeline', 'frame_count', 'frame_intervals_ms', 'pipeline_events', 'pipeline_counts_final',
             'clipmap_frames', 'clipmap_frame_fields', 'clipmap_limits', 'product_renderer_binding',
             'manifest_sha256', 'renderer_source_sha256', 'rendering_method', 'gpu', 'cloud_layer_binding']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def acquire_lock():
    while True:
        try:
            fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, f'{os.getpid()} {int(time.time())} kit1-integration\n'.encode())
            os.close(fd)
            return
        except FileExistsError:
            if time.time() - LOCK.stat().st_mtime > LOCK_STALE_S:
                LOCK.unlink(missing_ok=True)
                continue
            time.sleep(5)


def release_lock():
    if LOCK.exists() and 'kit1-integration' in LOCK.read_text():
        LOCK.unlink()


def capture(pose, variant, work):
    ident, lon, lat, zoom, width, _ = pose
    out = work / f'{ident}-{variant}'
    out.mkdir(parents=True)
    app_args = ['--snapshot', '--view', str(lon), str(lat), str(zoom)]
    if width:
        app_args += ['--width-source-m', str(width)]
    app_args += VARIANTS[variant] + ['--capture-dir', str(out)]
    command = [os.environ.get('GODOT_BIN', 'godot'), *WINDOW, '--path', str(ROOT / 'app'), '--', *app_args]
    acquire_lock()
    try:
        with (out / 'log.txt').open('w') as log:
            rc = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=RUN_TIMEOUT_S,
                                start_new_session=True).returncode
    finally:
        release_lock()
    shown = ['godot', *WINDOW, '--path', 'app', '--', *app_args[:-1], '<out>']
    return out, rc, ' '.join(shown)


def record(pose, variant, out, rc, command, dest):
    ident = f'{pose[0]}-{variant}'
    png = sorted(out.glob('*.png'))[-1]
    runtime = json.loads((out / 'runtime.json').read_text())
    log = (out / 'log.txt').read_text()
    image = Image.open(png).convert('RGB')
    image.save(dest / f'{ident}.png', optimize=True, compress_level=9)
    w, h = image.size
    (dest / 'crops').mkdir(exist_ok=True)
    image.crop((w // 2 - 128, h // 2 - 128, w // 2 + 128, h // 2 + 128)).save(dest / 'crops' / f'{ident}-1to1.png')
    fields = runtime.get('clipmap_frame_fields', [])
    last = dict(zip(fields, runtime['clipmap_frames'][-1])) if runtime.get('clipmap_frames') else None
    excerpt = {'capture_frame_clipmap': last, 'startup_timeline': runtime.get('startup_timeline'),
               'coverage_gate': 'snapshot waits for root_ready, missing==0, refining==0 (120 s cap)',
               'coverage_cap_hit': 'coverage incomplete' in log,
               'pipeline_counts_final': runtime.get('pipeline_counts_final'), 'exit_code': rc}
    (dest / 'excerpts').mkdir(exist_ok=True)
    (dest / 'excerpts' / f'{ident}.json').write_text(json.dumps(excerpt, indent=1) + '\n')
    trimmed = {k: runtime[k] for k in TRIM_KEYS if k in runtime}
    trimmed['samples_last'] = runtime['samples'][-3:]
    (dest / 'runtime').mkdir(exist_ok=True)
    with gzip.GzipFile(dest / 'runtime' / f'{ident}.json.gz', 'wb', mtime=0) as f:
        f.write(json.dumps(trimmed, separators=(',', ':')).encode())
    sample = runtime['samples'][-1]
    return {
        'id': ident, 'file': f'{ident}.png', 'sha256': sha(dest / f'{ident}.png'),
        'source_capture_sha256': sha(png), 'runtime_json_sha256': sha(out / 'runtime.json'),
        'size_px': [w, h], 'command': command, 'exit_code': rc,
        'pose': {'lon': pose[1], 'lat': pose[2], 'legacy_zoom': pose[3], 'width_source_m': pose[4], 'source': pose[5]},
        'weather': {'variant': variant, 'arguments': VARIANTS[variant]},
        'zoom': sample['zoom'], 'view_width_source_m': sample.get('visible_width_source_m'),
        'camera': {'azimuth_degrees': sample['azimuth_degrees'], 'elevation_degrees': sample['elevation_degrees'],
                   'fov_degrees_vertical': sample['camera_fov_degrees'], 'basis': sample['camera_basis'],
                   'position_model': sample['camera_position']},
        'coverage': 'incomplete (120 s cap)' if excerpt['coverage_cap_hit'] else 'complete',
        'hashes': {'renderer_binding_sha256': runtime['product_renderer_binding']['sha256'],
                   'dataset_manifest_sha256': runtime['manifest_sha256'],
                   'renderer_source_sha256': runtime['renderer_source_sha256']},
        'crop': f'crops/{ident}-1to1.png', 'excerpt': f'excerpts/{ident}.json', 'runtime': f'runtime/{ident}.json.gz',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('set', choices=sorted(POSES))
    parser.add_argument('out_dir', type=Path)
    parser.add_argument('--variants', default='weather,control')
    args = parser.parse_args()
    dest = args.out_dir.resolve()
    dest.mkdir(parents=True, exist_ok=True)
    commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    frames = []
    with tempfile.TemporaryDirectory(prefix='kit1-capture-') as tmp:
        for pose in POSES[args.set]:
            for variant in args.variants.split(','):
                out, rc, command = capture(pose, variant, Path(tmp))
                frames.append(record(pose, variant, out, rc, command, dest))
                print(frames[-1]['id'], 'exit', rc, frames[-1]['coverage'], flush=True)
    manifest = {
        'set': args.set, 'commit': commit,
        'geodata_policy_sha256': sha(ROOT / 'data/geodata_policy.json'),
        'resolution': '640x360 window (small-window rule)', 'png': 'full RGB, lossless (no palette reduction)',
        'sha256_note': 'source_capture_sha256 = PNG written by the app; sha256 = same pixels re-encoded as RGB PNG',
        'coverage_gate': 'snapshot after root_ready, missing==0, refining==0; excerpts read clipmap_frames at the capture frame',
        'variants': {k: VARIANTS[k] for k in args.variants.split(',')},
        'review': 'image assessment by an independent reviewer', 'frames': frames,
    }
    (dest / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return 0 if all(f['exit_code'] == 0 for f in frames) else 1


if __name__ == '__main__':
    sys.exit(main())
