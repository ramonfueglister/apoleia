#!/usr/bin/env python3
"""Run one native Godot tour and record process RSS independently of engine allocators."""
import argparse, json, pathlib, subprocess, time
p=argparse.ArgumentParser()
p.add_argument('--out',required=True,type=pathlib.Path)
p.add_argument('--renderer',default='mobile',choices=['mobile','forward_plus'])
p.add_argument('--duration',type=float,default=48)
p.add_argument('--capture',action='store_true')
p.add_argument('--fixture',type=pathlib.Path)
a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
a.out=a.out.resolve(); a.out.mkdir(parents=True,exist_ok=True)
cmd=[str(root/'scripts/run-landscape'),'--rendering-method',a.renderer,'--resolution','1920x1080','--','--tour','--duration',str(a.duration),'--telemetry-dir',str(a.out)]
if a.capture: cmd+=['--capture-dir',str(a.out)]
if a.fixture: cmd+=['--fixture',str(a.fixture.resolve())]
rows=[]
with (a.out/'launch.log').open('w') as log:
    started=time.monotonic()
    child=subprocess.Popen(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT)
    while child.poll() is None:
        probe=subprocess.run(['ps','-p',str(child.pid),'-o','rss=,pcpu='],capture_output=True,text=True)
        parts=probe.stdout.split()
        if len(parts)==2:
            rows.append({'t_ms':(time.monotonic()-started)*1000,'rss_bytes':int(parts[0])*1024,'cpu_percent':float(parts[1])})
        if time.monotonic()-started>a.duration+120:
            child.terminate(); child.wait(timeout=10); raise SystemExit('Own runtime exceeded bounded test timeout')
        time.sleep(.1)
    code=child.returncode
result={'schema_version':'process-rss-v1','command':cmd,'pid':child.pid,'exit_code':code,'wall_seconds':time.monotonic()-started,'sample_period_target_seconds':.1,'rss_method':'macOS ps -p PID -o rss= (KiB converted to bytes), includes child Godot process only','peak_rss_bytes':max((r['rss_bytes']for r in rows),default=None),'samples':rows}
(a.out/'process-rss.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:result[k]for k in ['exit_code','wall_seconds','peak_rss_bytes']}))
raise SystemExit(code)
