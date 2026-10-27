"""Renders a density map PNG from a sim leaves snapshot (sim/out/leaves-YEAR.csv).

Usage: python3 tools/sim_render.py sim/out/leaves-680.csv out.png [--px-per-km 0.1]
Colour = people per km² of land (log scale); thin outlines show tiles below level 3.
"""
import csv
import math
import sys

from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
scale = float(sys.argv[sys.argv.index("--px-per-km") + 1]) / 1000 if "--px-per-km" in sys.argv else 0.1 / 1000

rows = list(csv.DictReader(open(src)))
x0 = min(float(r["x0_m"]) for r in rows)
z0 = min(float(r["z0_m"]) for r in rows)
x1 = max(float(r["x0_m"]) + float(r["size_m"]) for r in rows)
z1 = max(float(r["z0_m"]) + float(r["size_m"]) for r in rows)
w, h = int((x1 - x0) * scale) + 1, int((z1 - z0) * scale) + 1
img = Image.new("RGB", (w, h), (24, 32, 48))
d = ImageDraw.Draw(img)


def colour(density):
    # 0.5 .. 500 people/km² mapped on a log ramp from pale sand to deep red.
    t = min(1.0, max(0.0, (math.log10(max(density, 0.5)) + 0.3) / 3.0))
    return (int(240 - 60 * t), int(225 - 190 * t), int(170 - 140 * t))


for r in rows:
    land = float(r["land_km2"])
    if land <= 0:
        continue
    s = float(r["size_m"])
    # Row grows south in the tile scheme, so z maps straight to image y.
    left = (float(r["x0_m"]) - x0) * scale
    top = (float(r["z0_m"]) - z0) * scale
    side = max(s * scale - 1, 0)
    box = [left, top, left + side, top + side]
    d.rectangle(box, fill=colour(float(r["p"]) / land), outline=(60, 20, 20) if int(r["level"]) > 3 and s * scale >= 4 else None)

img.save(dst)
print(f"{dst}: {w}x{h} px, {len(rows)} tiles")
