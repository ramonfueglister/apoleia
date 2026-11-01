#!/usr/bin/env python3
"""Order the actual-GPU baseline stream; report rises without treating them as a pass.

Usage: python tools/tests/analyze_verona_river_profile.py [GPU report.json]
The direction is a documented source/topography inference, not GeoJSON metadata.
This analyzes painted-terrain baseline only; a replacement mesh needs its own audit.
"""
import collections
import json
import sys
from pathlib import Path


def analyze(report):
    segments = report['segments']
    adjacency = collections.defaultdict(list)
    def key(point):
        return tuple(round(v, 5) for v in point)
    for index, segment in enumerate(segments):
        for sample in [segment['samples'][0], segment['samples'][-1]]:
            adjacency[key(sample['xz'])].append(index)
    endpoints = [point for point, links in adjacency.items() if len(links) == 1]
    if len(endpoints) != 2 or any(len(links) > 2 for links in adjacency.values()):
        raise ValueError('Expected one unbranched Verona reach; cannot assume ordering')
    # Main Adige source_id1217 runs from alpine1692m node to terminal0m node.
    # In this local reach its source order runs NW to SE.
    node = min(endpoints)
    used, ordered, points = set(), [], []
    while len(used) < len(segments):
        candidates = [i for i in adjacency[node] if i not in used]
        if len(candidates) != 1:
            raise ValueError('Disconnected or ambiguous stream')
        index = candidates[0]
        used.add(index)
        segment = segments[index]
        samples = segment['samples']
        if key(samples[0]['xz']) != node:
            samples = list(reversed(samples))
        ordered.append(dict(segment_index=index, parcel=segment['parcel'],
                            start=samples[0]['xz'], end=samples[-1]['xz'],
                            start_height=samples[0]['height'], end_height=samples[-1]['height']))
        points.extend(samples if not points else samples[1:])
        node = key(samples[-1]['xz'])
    differences = [b['height'] - a['height'] for a, b in zip(points, points[1:])]
    return dict(direction='Inferred NW upstream to SE downstream from source Adige endpoint elevations1692m to0m; not flow metadata',
                ordered_segments=ordered, samples=points,
                rise_count=sum(v > 1e-5 for v in differences),
                fall_count=sum(v < -1e-5 for v in differences),
                total_rise_km=sum(v for v in differences if v > 1e-5),
                total_fall_km=-sum(v for v in differences if v < -1e-5),
                max_cross_km=max(s['transverse_range_km'] for s in segments))


if __name__ == '__main__':
    source = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/verona-river/baseline/report.json')
    result = analyze(json.loads(source.read_text()))
    target = source.with_name('ordered-profile.json')
    target.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('ordered_segments', 'samples')}, indent=2))
    print(target)
