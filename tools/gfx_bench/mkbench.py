"""Bench shader for the graphics benches (docs/handover/grafik.md): the terrain
shader without vertex(), fragment() and light(), as a canvas_item, with a
top-down fragment of your own appended, so its functions run on real data in
a 2D viewport (lavapipe cannot draw the 3D terrain in the cloud).

    python3 tools/gfx_bench/mkbench.py tools/gfx_bench/fragment_water_q.glsl _bench_q
    -> app/shaders/_bench_q.gdshader (git-excluded, see .git/info/exclude)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
frag, name = sys.argv[1], sys.argv[2]
src = (ROOT / "app/shaders/tile_terrain.gdshader").read_text()


def drop(fn, s):
    i = s.index("\nvoid %s()" % fn)
    k = s.index("{", i)
    depth = 0
    while True:
        if s[k] == "{":
            depth += 1
        elif s[k] == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return s[:i] + s[k + 1:]


for fn in ("vertex", "fragment", "light"):
    src = drop(fn, src)
src = src.replace("shader_type spatial;", "shader_type canvas_item;")
src = re.sub(r"render_mode [^;]*;", "render_mode blend_disabled, unshaded;", src, count=1)
src += Path(frag).read_text()
(ROOT / "app/shaders" / (name + ".gdshader")).write_text(src)
print("app/shaders/%s.gdshader" % name)
