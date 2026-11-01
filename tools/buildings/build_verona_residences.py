"""Five original, human-scale infill houses/shops for existing Verona parcels.

Blender --background --factory-startup --python this_file -- --all
or -- --model=verona_courtyard_house. Blender Z up; street front is -Y.
No accepted Roman-series asset is rebuilt or modified by this script.
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roman_asset_kit as k
import build_houses_crafts as h


def role(value, group=None):
    k.ROLE = value
    k.GROUP = group or {"structure": "Architecture", "roof": "Roof", "detail": "DomesticProps"}[value]


def init(slug, footprint=(9.2, 9.2)):
    h.init(slug)
    h.ROOF_SEGMENTS = 4 if footprint[0] < 3 else 6
    k.material("Warm_ochre", "C9A370", texture=True)
    k.material("Soft_linen", "C2B69A")
    k.material("Dry_earth", "806C51")
    role("structure", "Paving")
    width, depth = footprint
    k.box((0, 0, .10), (width, depth, .20), k.stone, .04)
    role("detail", "Paving")
    nx, ny = max(1, round(width / .51)), max(1, round(depth / .51))
    sx, sy = width / nx, depth / ny
    for j in range(ny):
        for i in range(nx):
            k.box((-width / 2 + (i + .5) * sx, -depth / 2 + (j + .5) * sy, .225),
                  (sx - .024, sy - .024, .10), "Paving_" + str((i * 5 + j * 7) % 4), 0)
    role("structure")


def roof(x0, x1, y0, y1, z, height):
    role("roof")
    h.roof(x0, x1, y0, y1, z, height)
    role("structure")


def canopy(x0, x1, front, back, low, high):
    role("roof")
    h.lean_roof(x0, x1, front, back, low, high)
    role("structure")


def window(origin, normal, u, z, width=.8, height=1.3, opened=True, balcony=False):
    role("detail", "Joinery")
    h.shutter(origin, normal, u, z, width, height, opened, balcony)
    role("structure")


def facade(origin, normal, span, z0, height, count=3, width=.82,
           opening_height=1.35, mat=None, balconies=()):
    """Actual wall piers and bands around each hole; no solid backing wall."""
    role("structure")
    mat = mat or k.plaster
    opening_height = min(opening_height, height * .57)
    centre_z = z0 + height * .55
    bottom, top = centre_z - opening_height / 2, centre_z + opening_height / 2
    centers = [-span / 2 + (i + .5) * span / count for i in range(count)]
    h.plane_box(origin, normal, 0, (z0 + bottom) / 2, span, bottom - z0, .28, mat)
    h.plane_box(origin, normal, 0, (z0 + height + top) / 2, span, z0 + height - top, .28, mat)
    left = -span / 2
    for i, u in enumerate(centers):
        right = u - width / 2
        h.plane_box(origin, normal, (left + right) / 2, centre_z, right - left, opening_height, .28, mat)
        window(origin, normal, u, centre_z, width, opening_height, i % 2 == 0, i in balconies)
        left = u + width / 2
    h.plane_box(origin, normal, (left + span / 2) / 2, centre_z, span / 2 - left, opening_height, .28, mat)
    for z, thick, depth in [(z0 + .06, .12, .38), (z0 + height - .025, .13, .40)]:
        h.plane_box(origin, normal, 0, z, span + .1, thick, depth, k.lightstone)


def room_walls(x0, x1, y0, y1, z, height, count=2, mat=None, opening_height=1.3, front_door=False):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if front_door:
        for a, b in [(x0, cx - .8), (cx + .8, x1)]:
            facade(((a + b) / 2, y0, 0), (0, -1, 0), b - a, z, height, 1,
                   mat=mat, opening_height=opening_height)
        wall_with_door(cx - .8, cx + .8, y0, z, height, cx, 1.05, mat)
    else:
        facade((cx, y0, 0), (0, -1, 0), x1 - x0, z, height, count, mat=mat, opening_height=opening_height)
    facade((cx, y1, 0), (0, 1, 0), x1 - x0, z, height, count, mat=mat, opening_height=opening_height)
    facade((x0, cy, 0), (-1, 0, 0), y1 - y0, z, height, max(1, count - 1), mat=mat, opening_height=opening_height)
    facade((x1, cy, 0), (1, 0, 0), y1 - y0, z, height, max(1, count - 1), mat=mat, opening_height=opening_height)


def corner_stones(x0, x1, y0, y1, height):
    role("structure")
    for x in [x0, x1]:
        for y in [y0, y1]:
            for j in range(int((height - .3) / .45)):
                k.box((x, y, .52 + j * .45), (.33, .33, .42), k.stone, .014)


def entrance(origin, normal, u, width=1.1, height=2.35):
    role("detail", "Joinery")
    h.door(origin, normal, u, .3, width, height)
    role("structure")


def wall_with_door(x0, x1, y, z0, height, door_x, width, mat=None, door_height=2.35):
    """A real entrance aperture, framed separately from its recessed door."""
    role("structure")
    mat = mat or k.plaster
    door_top = z0 + door_height
    for a, b in [(x0, door_x - width / 2), (door_x + width / 2, x1)]:
        if b > a:
            k.box(((a + b) / 2, y, z0 + height / 2), (b - a, .28, height), mat)
    k.box(((x0 + x1) / 2, y, (door_top + z0 + height) / 2),
          (x1 - x0, .28, z0 + height - door_top), mat)
    role("detail", "Joinery")
    h.door((0, y + .10, 0), (0, -1, 0), -door_x, z0, width, door_height)
    role("structure")


def pot(x, y, z=.28, scale=.55, variant=0):
    role("detail")
    k.pot(x, y, z, scale, variant)
    role("structure")


def planter(x, y, z, width=.8):
    role("detail", "Planting")
    k.box((x, y, z + .13), (width, .38, .26), "Clay_1")
    k.box((x, y, z + .27), (width - .1, .28, .04), "Dry_earth", 0)
    for i in range(7):
        px = x - width * .37 + i * width * .74 / 6
        k.leaf((px, y, z + .29), i * 1.3, .19, "Leaf_" + str(i % 4))
    role("structure")


def rail(x0, x1, y, z, height=.75):
    role("structure", "Balcony")
    k.beam((x0, y, z + height), (x1, y, z + height), .075, .09, k.wood)
    n = max(2, math.ceil((x1 - x0) / .35))
    for j in range(n + 1):
        k.box((x0 + (x1 - x0) * j / n, y, z + height / 2), (.055, .055, height), k.wood)
    role("structure")


def shop_front(x, y, width, spring=1.95, cap=3.25, stocked=True):
    role("structure")
    h.arch((x, y, 0), (0, -1, 0), width, spring, .20, .34, cap=cap)
    # The room itself is recessed, with a real counter at the back of the arcade.
    k.box((x, y + 1.45, 1.62), (width, .12, 2.6), k.dark)
    if not stocked:
        return
    k.box((x, y + .60, .84), (width * .87, .55, 1.05), k.wood)
    k.box((x, y + .60, 1.40), (width * .93, .64, .10), k.woodlight)
    role("detail")
    for i in range(4):
        k.pot(x - width * .30 + i * width * .2, y + .60, 1.46, .25, i % 3, False)
    role("structure")


def bench(x, y, floor, height=.73, width=1.3):
    role("detail")
    top = floor + height
    k.box((x, y, top), (width, .50, .10), k.woodlight)
    for xx in [x - width * .4, x + width * .4]:
        for yy in [y - .16, y + .16]:
            k.box((xx, yy, floor + height / 2), (.085, .085, height), k.wood)
    role("structure")


def courtyard_house():
    slug = "verona_courtyard_house"
    init(slug)
    # L-shaped plan: high rear dwelling / loft, low west shop, open front court.
    room_walls(-3.72, 3.72, 1.45, 3.63, .30, 2.65, 2, mat="Warm_ochre", opening_height=1.15, front_door=True)
    room_walls(-3.72, 3.72, 1.45, 3.63, 2.95, 1.90, 3, opening_height=.82)
    k.box((0, 2.54, 2.96), (7.16, 1.94, .15), k.wood)
    roof(-4.0, 4.0, 1.17, 3.92, 4.98, 1.20)
    # Left wing has solid side piers around real windows, but an open shop front.
    facade((-3.72, -.97, 0), (-1, 0, 0), 4.84, .3, 2.7, 2, opening_height=1.0)
    facade((-1.45, -.97, 0), (1, 0, 0), 4.84, .3, 2.7, 2, mat="Warm_ochre", opening_height=1.0)
    shop_front(-2.585, -3.45, 1.62, 1.88, 3.08)
    for x in [-3.72, -1.45]:
        k.box((x, -3.45, 1.67), (.30, .34, 2.72), k.stone)
    roof(-3.98, -1.20, -3.72, 1.70, 3.19, .78)
    # The low enclosure frames a courtyard rather than occupying it.
    k.box((3.72, -.97, 1.1), (.25, 4.84, 1.6), k.plaster)
    k.box((3.72, -.97, 1.94), (.34, 4.90, .12), k.lightstone)
    for x, w in [(-.62, 1.42), (2.72, 1.98)]:
        k.box((x, -3.45, .99), (w, .25, 1.38), k.red)
        k.box((x, -3.45, 1.72), (w + .06, .34, .12), k.lightstone)
    h.arch((.78, -3.45, 0), (0, -1, 0), 1.55, 1.93, .18, .34)
    canopy(-1.2, 3.4, .2, 1.6, 2.93, 3.24)
    for x in [-1.0, 3.15]:
        h.column(x, .35, .28, 2.58, .15, True)
    # Bench, washing basin, plants and amphorae stay inside the courtyard.
    role("detail")
    bench(2.75, -1.05, .28, .45, 1.3)
    h.water_pool(-.4, -1.25, .34, .85, .75)
    role("structure")
    pot(2.9, -.15, scale=.6)
    planter(2.8, -2.85, .3, .85)
    planter(-.8, 2.01, 3.02, .65)
    finish(slug, 6.5, "L-shaped courtyard house with low shop wing and rear loft")


def townhouse():
    slug = "verona_townhouse"
    init(slug)
    # Tall two-storey volume; its front upper wall is recessed behind a loggia.
    for x, normal in [(-3.50, (-1, 0, 0)), (3.50, (1, 0, 0))]:
        facade((x, 0, 0), normal, 7.10, .3, 3.22, 3, mat="Warm_ochre")
    facade((0, 3.55, 0), (0, 1, 0), 7.0, .3, 3.22, 3, mat="Warm_ochre")
    for x in [-1.75, 1.75]:
        shop_front(x, -3.55, 2.50, 1.8, 3.40, stocked=x > 0)
    for x in [-3.50, 0, 3.50]:
        k.box((x, -3.55, 1.87), (.56, .38, 3.14), k.stone)
    # One arcade is the household entrance, the other a small domestic shop.
    entrance((-1.75, -2.27, 0), (0, -1, 0), 0, 1.05)
    k.box((0, 0, 3.52), (6.9, 7.0, .20), k.stone)
    room_walls(-3.5, 3.5, -2.45, 3.55, 3.62, 2.95, 3, front_door=True)
    corner_stones(-3.5, 3.5, -2.45, 3.55, 6.6)
    # Wide timber-and-stone loggia, distinctly different from the low court.
    for x in [-3.13, -.1, 3.13]:
        h.column(x, -3.50, 3.62, 2.75, .16)
    rail(-3.15, 3.15, -3.72, 3.63, .78)
    for y in [-3.55, -3.2, -2.85]:
        k.beam((-3.2, y, 3.64), (3.2, y, 3.64), .08, .10, k.woodlight)
    canopy(-3.82, 3.82, -3.96, -2.15, 6.53, 6.89)
    roof(-3.85, 3.85, -2.75, 3.90, 6.74, 1.75)
    planter(-2.2, -3.58, 3.66, .82)
    planter(2.15, -3.58, 3.66, .82)
    pot(3.94, -3.25, scale=.6, variant=1)
    role("detail")
    bench(.6, -3.0, 3.62, .73, 1.25)
    # A folded cloth is a quiet indication of use, not a billboard or sign.
    k.mesh([(.1, -3.73, 4.39), (.8, -3.73, 4.39), (.8, -3.73, 3.97), (.1, -3.73, 4.02)], [(0, 1, 2, 3)], "Soft_linen")
    role("structure")
    finish(slug, 9.0, "Two-storey townhouse with recessed upper loggia and broad hipped roof")


def terrace_house():
    slug = "verona_terrace_house"
    init(slug)
    # Compact ring of rooms around a real open lightwell; upper roof terrace south.
    for z, height, mat in [(.3, 2.95, k.red), (3.25, 3.12, "Warm_ochre")]:
        for x, normal in [(-3.6, (-1, 0, 0)), (3.6, (1, 0, 0))]:
            facade((x, 0, 0), normal, 7.2, z, height, 3, mat=mat)
        facade((0, 3.6, 0), (0, 1, 0), 7.2, z, height, 3, mat=mat)
        if z > 1:
            facade((0, -3.6, 0), (0, -1, 0), 7.2, z, height, 3, mat=mat, balconies=(0,))
        else:
            # Street wall has a tall framed door and two rectangular shop windows.
            wall_with_door(-1.05, 1.05, -3.6, .3, 2.95, 0, 1.25, k.red)
            for x in [-2.34, 2.34]:
                facade((x, -3.6, 0), (0, -1, 0), 2.52, .3, 2.95, 1,
                       width=1.30, opening_height=1.3, mat=k.red)
        # Floor perimeter preserves the open 2.4 x 1.8 m inner court.
        for x in [-2.4, 2.4]:
            k.box((x, 0, z + .04), (2.4, 7.0, .14), k.wood)
        for y, depth in [(-2.1, 3.0), (2.4, 2.4)]:
            k.box((0, y, z + .04), (2.4, depth, .14), k.wood)
        for x, normal in [(-1.2, (1, 0, 0)), (1.2, (-1, 0, 0))]:
            facade((x, .3, 0), normal, 1.8, z, height, 1, width=.60, opening_height=1.05)
        for y, normal in [(-.6, (0, 1, 0)), (1.2, (0, -1, 0))]:
            facade((0, y, 0), normal, 2.4, z, height, 1, width=.70, opening_height=1.05)
    corner_stones(-3.6, 3.6, -3.6, 3.6, 6.4)
    # Three tiled wings border the lightwell; no hidden full slab closes it.
    for x in [-2.575, 2.575]:
        roof(x - 1.375, x + 1.375, -.60, 3.95, 6.59, 1.70)
    roof(-1.25, 1.25, 1.20, 3.95, 6.59, 1.70)
    # South roof terrace is supported by the front room, not suspended over the court.
    k.box((0, -2.1, 6.47), (7.2, 3.0, .20), k.stone)
    k.box((0, -3.63, 6.91), (7.46, .25, .72), k.plaster)
    k.box((0, -3.63, 7.31), (7.55, .37, .13), k.lightstone)
    for x in [-3.61, 3.61]:
        k.box((x, -2.12, 6.91), (.25, 3.0, .72), k.plaster)
        k.box((x, -2.12, 7.31), (.37, 3.1, .13), k.lightstone)
    rail(-1.13, 1.13, -.66, 6.57, .70)
    # A pergola, herb boxes and seating give the terrace a domestic silhouette.
    role("structure", "Pergola")
    for x in [-3.05, -.45]:
        for y in [-3.05, -1.20]:
            k.box((x, y, 7.45), (.11, .11, 1.70), k.wood)
        k.beam((x, -3.17, 8.31), (x, -1.07, 8.31), .13, .17, k.wood)
    for j in range(8):
        y = -3.05 + j * 1.85 / 7
        k.beam((-3.18, y, 8.40), (-.32, y, 8.40), .09, .11, k.woodlight)
    role("detail")
    bench(-1.7, -2.2, 6.58, .67, 1.35)
    h.water_pool(0, .3, .35, .9, .65)
    role("structure")
    planter(2.5, -2.9, 6.59, 1.0)
    pot(2.6, -1.5, 6.58, .55, 2)
    pot(.75, .65, .30, .48, 1)
    finish(slug, 9.0, "Two-storey lightwell house with roof terrace, pergola and three tiled wings")


def street_house():
    slug = "verona_street_house"
    init(slug, (2.8, 2.8))
    # This is a narrow house drawn at human scale, not a shrunken large building.
    wall_with_door(-1.06, 1.06, -1.06, .30, 2.4, 0, 1.0, k.red, 2.1)
    for x, normal in [(-1.06, (-1, 0, 0)), (1.06, (1, 0, 0))]:
        facade((x, 0, 0), normal, 2.12, .30, 2.4, 1, width=.58, opening_height=.9, mat=k.red)
    facade((0, 1.06, 0), (0, 1, 0), 2.12, .30, 2.4, 1, width=.62, opening_height=.9, mat=k.red)
    k.box((0, 0, 2.70), (2.12, 2.12, .16), k.wood)
    room_walls(-1.06, 1.06, -1.06, 1.06, 2.78, 2.37, 1, mat="Warm_ochre", opening_height=1.15)
    roof(-1.23, 1.23, -1.23, 1.23, 5.25, .90)
    for x in [-1.06, 1.06]:
        for y in [-1.06, 1.06]:
            k.box((x, y, .58), (.21, .21, .56), k.stone)
    pot(.97, -1.05, .28, .38, 1)
    finish(slug, 6.5, "Narrow two-storey street house with full human-scale doorway", (2.8, 2.8))


def street_shop():
    slug = "verona_street_shop"
    init(slug, (2.8, 2.0))
    # Open front bay; the right half remains a usable approximately 1m passage.
    k.box((0, .72, 1.47), (2.30, .19, 2.34), "Warm_ochre")
    for x in [-1.10, 1.10]:
        k.box((x, -.02, 1.47), (.18, 1.48, 2.34), k.plaster)
        k.box((x, -.02, .75), (.19, 1.50, .90), k.red)
    role("structure")
    # Rectangular timber lintel keeps a full-height access beside the counter.
    for x in [-1.08, 1.08]:
        k.box((x, -.79, 1.44), (.16, .22, 2.28), k.wood)
    k.box((0, -.79, 2.64), (2.40, .25, .22), k.woodlight)
    roof(-1.23, 1.23, -.83, .83, 2.79, .64)
    # Small counter and shelves fit into the left half; no pavement obstructions.
    k.box((-.57, -.47, .81), (.76, .48, 1.02), k.wood)
    k.box((-.57, -.47, 1.36), (.81, .54, .10), k.woodlight)
    for z in [1.38, 1.93]:
        k.box((0, .49, z), (1.8, .32, .08), k.woodlight)
        role("detail")
        for i in range(5):
            k.pot(-.68 + i * .34, .49, z + .05, .25, i % 3, False)
        role("structure")
    pot(-.60, -.47, 1.42, .25, 2)
    finish(slug, 3.7, "Single-storey open street shop with recessed counter and a human-scale access bay", (2.8, 2.0))


def finish(slug, height_cap, design, footprint=(9.2, 9.2)):
    role("structure")
    k.finish(slug)
    path = k.ROOT / "app/assets/buildings" / slug / "model.json"
    metadata = json.loads(path.read_text())
    lo, hi = metadata["source_bounds_xyz"]
    assert hi[0] - lo[0] <= footprint[0] + .00001 and hi[1] - lo[1] <= footprint[1] + .00001, (slug, lo, hi)
    assert hi[2] - lo[2] <= height_cap + .00001, (slug, hi[2], height_cap)
    metadata["design"] = {
        "status": "implementiert", "front": "south", "height_cap_m": height_cap, "footprint_cap_m": list(footprint),
        "placement": "existing residential or decorative street slot; no nonuniform scaling",
        "description": design,
        "provenance": "Original procedural geometry; typological artistic infill, not a historical reconstruction",
    }
    path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")


MODELS = {
    "verona_courtyard_house": courtyard_house,
    "verona_townhouse": townhouse,
    "verona_terrace_house": terrace_house,
    "verona_street_house": street_house,
    "verona_street_shop": street_shop,
}
if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    selected = next((a.split("=", 1)[1] for a in args if a.startswith("--model=")), None)
    for slug in ([selected] if selected else list(MODELS)):
        if slug not in MODELS:
            raise ValueError("Unknown Verona residence: " + slug)
        print("BUILDING " + slug, flush=True)
        MODELS[slug]()
