#!/usr/bin/env python3
"""Encode untouched runtime frames with their actual capture timestamps."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('run',type=pathlib.Path);a=p.parse_args();a.run=a.run.resolve()
r=json.loads((a.run/'runtime.json').read_text());frames=r['captures']
if not frames:raise SystemExit('No real captured frames')
lines=['ffconcat version 1.0']
for i,f in enumerate(frames):
 path=str(a.run/f['file']).replace("'","'\\''")
 duration=((frames[i+1]['t_ms']-f['t_ms'])/1000 if i+1<len(frames) else max(.01,r['duration_seconds']-f['t_ms']/1000))
 lines += [f"file '{path}'",f'duration {max(.001,duration):.9f}']
concat=a.run/'capture.ffconcat';concat.write_text('\n'.join(lines)+'\n')
subprocess.run(['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','concat','-safe','0','-i',str(concat),'-fps_mode','vfr','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(a.run/'zoom-tour.mp4')],check=True)
print(a.run/'zoom-tour.mp4')
