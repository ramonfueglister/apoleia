#!/usr/bin/env python3
"""Close the exposed marine sides of existing clipmap tiles at their SDF contour.

Only small segment sidecars are written; height, material and water PNGs stay intact.
Segments are tile-local float32 (ax,az,bx,bz), with marine water on their right.
"""
import argparse
from pathlib import Path
import time
import numpy as np
from PIL import Image


def segments(path):
    water = np.asarray(Image.open(path).convert('RGBA'))
    sdf = (water[..., 0].astype(np.float64) * 256 + water[..., 1]) * .125 - 4096
    role = water[..., 2]
    corners = [sdf[:-1, :-1], sdf[:-1, 1:], sdf[1:, 1:], sdf[1:, :-1]]
    wet = [(corners[i] > 0) for i in range(4)]
    mixed = np.logical_or.reduce(wet) & ~np.logical_and.reduce(wet)
    marine = np.logical_or.reduce([
        wet[0] & (role[:-1, :-1] == 1), wet[1] & (role[:-1, 1:] == 1),
        wet[2] & (role[1:, 1:] == 1), wet[3] & (role[1:, :-1] == 1)])
    zs, xs = np.nonzero(mixed & marine)
    result = []
    offsets = np.array([[0., 0.], [1., 0.], [1., 1.], [0., 1.]])
    for z, x in zip(zs, xs):
        values = [float(v[z, x]) for v in corners]
        roots = {}
        for edge in range(4):
            nxt = (edge + 1) % 4
            if (values[edge] > 0) != (values[nxt] > 0):
                t = values[edge] / (values[edge] - values[nxt])
                roots[edge] = offsets[edge] + (offsets[nxt] - offsets[edge]) * t
        if len(roots) == 2:
            pairs = [list(roots)]
        elif len(roots) == 4:
            # Bilinear asymptotic decider: centre connectivity preserves wet bays.
            centre_wet = sum(values) > 0
            pairs = [[0, 1], [2, 3]] if ((values[1] > 0) != centre_wet) else [[0, 3], [1, 2]]
        else:
            continue
        for a, b in pairs:
            start, end = roots[a].copy(), roots[b].copy()
            midpoint = (start + end) * .5
            gx = (values[1] - values[0]) * (1 - midpoint[1]) + (values[2] - values[3]) * midpoint[1]
            gz = (values[3] - values[0]) * (1 - midpoint[0]) + (values[2] - values[1]) * midpoint[0]
            direction = end - start
            if direction[1] * gx - direction[0] * gz < 0:
                start, end = end, start
            start = (start + [x - .5, z - .5]) / 256.
            end = (end + [x - .5, z - .5]) / 256.
            # Clip halo segments to this tile; neighbours own their own half.
            delta = end - start
            lo, hi = 0., 1.
            for axis in range(2):
                if delta[axis] == 0:
                    if start[axis] < 0 or start[axis] > 1: hi = -1; break
                else:
                    t0, t1 = -start[axis] / delta[axis], (1 - start[axis]) / delta[axis]
                    lo, hi = max(lo, min(t0, t1)), min(hi, max(t0, t1))
            if hi > lo:
                result.append(np.r_[start + delta * lo, start + delta * hi])
    return np.asarray(result, dtype='<f4').reshape((-1, 4))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tiles', default='artifacts/render-data/clipmap-tiles-r3')
    args = parser.parse_args()
    directory = Path(args.tiles)
    started = time.monotonic()
    count = 0
    for index, path in enumerate(sorted(directory.glob('*/*/*-water.png'))):
        destination = path.with_name(path.name.replace('-water.png', '-shore.bin'))
        data = segments(path)
        temporary = destination.with_suffix('.tmp')
        temporary.write_bytes(data.tobytes())
        temporary.replace(destination)
        count += len(data)
        if index % 250 == 0: print(f'{index + 1} tiles, {count} shore segments, {time.monotonic() - started:.1f}s', flush=True)
    print(f'complete: {index + 1} tiles, {count} segments, {time.monotonic() - started:.1f}s', flush=True)


if __name__ == '__main__': main()
