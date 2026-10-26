#!/usr/bin/env python3
"""Encode the actual framebuffer journey and graph recorded frame intervals."""
import argparse
import csv
from pathlib import Path
import subprocess
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--timing-only', action='store_true')
    args = parser.parse_args()
    folder = args.directory.resolve()
    rows = list(csv.DictReader((folder / 'frametime.csv').open()))
    time = np.array([float(row['seconds']) for row in rows])
    frame = np.array([float(row['frame_ms']) for row in rows])
    capture = np.array([float(row['capture_previous_ms']) for row in rows])
    active = (time > 0) & (frame > 0)
    normal = active & (capture == 0)
    fig, axes = plt.subplots(2, 1, figsize=(12, 6), sharex=True, layout='constrained')
    axes[0].plot(time, frame, color='#33665a', lw=.6, label='Actual frame interval'+('' if args.timing_only else ', recording included'))
    axes[0].scatter(time[capture > 0], frame[capture > 0], s=5, color='#d58a3d', label='Frame after framebuffer readback / encoding')
    for value in [16.67, 33.33]: axes[0].axhline(value, color='grey', lw=.6, ls='--')
    axes[0].set_ylabel('Milliseconds');axes[0].set_ylim(bottom=0);axes[0].legend(fontsize=8)
    for key, label in [('cpu_bytes', 'CPU tile cache'), ('gpu_bytes', 'GPU tile texture payload')]:
        axes[1].plot(time, [int(row[key]) / 1048576 for row in rows], label=label)
    axes[1].set_ylabel('MiB');axes[1].set_xlabel('Journey seconds');axes[1].legend(fontsize=8)
    fig.suptitle('Apoleia — Britain → Egypt, far / near / far; '+('capture disabled' if args.timing_only else 'live capture'))
    fig.savefig(folder / 'frametime.png', dpi=160);plt.close(fig)
    notes = ['# Clipmap journey', '', 'Status: implemented; visual and smooth-transition acceptance remains open.', '',
             'Framebuffer capture was disabled for this movement run.' if args.timing_only else 'The movie contains actual rendered frames with their recorded timing. Frame intervals include capture overhead; frames after capture are marked in the plot. Noncapture intervals are an observation within this recording, not a separate clean benchmark.', '']
    for mask, label in [(active, 'All recorded frames'), (normal, 'Frames without preceding capture')]:
        values = frame[mask]
        notes.append(f'{label}: median {np.median(values):.2f} ms; p95 {np.quantile(values, .95):.2f} ms; maximum {max(values):.2f} ms.')
    notes += ['', ('No framebuffer readback or image encoding in this run.' if args.timing_only else f'Capture readback + JPEG/keyframe save: median {np.median(capture[capture > 0]):.2f} ms; maximum {max(capture):.2f} ms.'),
              '', 'Cache plot reports tile payload accounting; driver allocations and shared scene resources are not represented by that number.']
    (folder / 'README.md').write_text('\n'.join(notes) + '\n')
    if args.timing_only:
        print('\n'.join(notes));return
    frames = list(csv.reader((folder / 'frames.csv').open()))
    Image.open(folder / 'frames' / frames[-1][1]).save(folder / 'return-far.png')
    concat = []
    for index, (stamp, name) in enumerate(frames):
        concat.append(f"file 'frames/{name}'")
        duration = float(frames[index + 1][0]) - float(stamp) if index + 1 < len(frames) else .125
        concat.append(f'duration {max(duration, .001):.6f}')
    concat.append(f"file 'frames/{frames[-1][1]}'")
    (folder / 'frames.ffconcat').write_text('\n'.join(concat) + '\n')
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-y', '-threads', '2', '-filter_threads', '1', '-f', 'concat', '-safe', '0', '-i', str(folder / 'frames.ffconcat'), '-vf', 'fps=24,scale=1440:-2', '-c:v', 'libx264', '-threads', '2', '-preset', 'fast', '-crf', '23', '-pix_fmt', 'yuv420p', str(folder / 'journey.mp4')], check=True)
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-y', '-threads', '2', '-filter_complex_threads', '1', '-filter_threads', '1', '-i', str(folder / 'journey.mp4'), '-vf', 'fps=8,scale=768:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer', str(folder / 'journey.gif')], check=True)
    print('\n'.join(notes))
    print(f'Video: {folder / "journey.mp4"}')


if __name__ == '__main__': main()
