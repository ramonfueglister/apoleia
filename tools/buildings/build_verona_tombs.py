"""Original typological burial gardens for Verona's existing cemetery parcels.

Blender --background --factory-startup --python this_file -- --all
or -- --model=verona_tombs_altar. Metres; Z up; front is negative Blender Y.
No historical names, copied inscriptions, human figures or terrain alterations.
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roman_asset_kit as k
import build_civic as civic


def role(value, group="Architecture"):
    k.ROLE = value
    k.GROUP = group


def initialize(slug):
    k.configure(slug)
    k.material("Garden_earth", "9D9879", 1.0)
    k.material("Quiet_turf", "83906B", 1.0)
    k.material("Dry_turf", "969A75", 1.0)
    k.material("Incised_stone", "81745D", 1.0)
    k.material("Brick_mortar", "AFA085", 1.0)
    k.material("Cypress_deep", "435C43", .95)
    k.material("Cypress_middle", "536B46", .95)
    k.material("Cypress_light", "607B4C", .95)


def ground():
    # Thin earth slab conceals terrace joins, without a solid paved platform.
    role("structure", "Foundation")
    k.box((0, 0, .055), (9.2, 9.2, .11), "Garden_earth", .035)
    # The full southern 1.15m strip is an unobstructed public-facing footpath.
    role("structure", "Paving")
    k.box((0, -4.025, .13), (9.2, 1.15, .06), "Paving_1", .012)
    role("detail", "Paving")
    for j in range(2):
        for i in range(12):
            k.box((-4.6 + (i + .5) * 9.2 / 12, -4.575 + (j + .5) * .55, .175),
                  (9.2 / 12 - .025, .525, .04), "Paving_" + str((i + j * 3) % 4), 0)
    role("structure", "Planting")
    for x, y, rx, ry, mat in [(-2.45, 2.25, 1.55, 1.75, "Quiet_turf"),
                              (2.4, 2.35, 1.6, 1.65, "Dry_turf"),
                              (0, 3.45, 1.5, .76, "Quiet_turf")]:
        n = 16
        vertices = [(x + rx * math.cos(i * math.tau / n), y + ry * math.sin(i * math.tau / n), .12) for i in range(n)]
        k.mesh(vertices, [tuple(range(n))], mat)
    role("detail", "Paving")
    for x, y in [(-.3, -.6), (.1, .2), (-.15, 1.0), (.08, 1.8), (-.1, 2.6)]:
        k.box((x, y, .15), (.82, .61, .06), "Paving_2", .035)
    role("structure")


def cypress(x, y, height=6.35, radius=.60):
    """Continuous tapered foliage lobes; no stacked voxel blocks."""
    role("structure", "Planting")
    k.lathe((x, y, .12), [(0, 0), (.12, 0), (.105, .78), (.06, 1.25), (0, 1.3)], k.wood, 10)
    # Overlapping asymmetric spindles produce a natural, narrow silhouette.
    profile = [(0, 0), (.38, .03), (.76, .15), (1.0, .34), (.96, .46),
               (.79, .62), (.66, .75), (.38, .89), (.13, .97), (0, 1.0)]
    for dx, dy, size, start, hfactor, mat in [
        (0, 0, 1, .62, 1, "Cypress_middle"),
        (-.17, .08, .62, .78, .85, "Cypress_deep"),
        (.15, -.10, .60, .66, .89, "Cypress_light"),
    ]:
        h = (height - start) * hfactor
        k.lathe((x + dx, y + dy, start), [(r * radius * size, z * h) for r, z in profile], mat, 16)
    # The collar is low and does not compete with the memorial architecture.
    role("detail", "Planting")
    k.lathe((x, y, .12), [(.48, 0), (.51, .07), (.50, .14), (.38, .14), (.37, .05)], k.stone, 14)
    role("structure")


def shrub(x, y, radius=.35):
    role("detail", "Planting")
    for dx, dy, scale, mat in [(0, 0, 1, "Leaf_0"), (-.15, .08, .70, "Leaf_2"), (.14, -.06, .65, "Leaf_1")]:
        k.lathe((x + dx, y + dy, .12), [(0, 0), (radius * scale, .08), (radius * scale * .83, .32 * scale), (0, .5 * scale)], mat, 10)
    role("structure")


def steps(x, y, width, depth, top=.56):
    role("structure")
    k.box((x, y, .20), (width, depth, .18), k.stone, .035)
    k.box((x, y + .10, .38), (width - .22, depth - .22, .18), k.lightstone, .025)
    k.box((x, y + .18, top - .06), (width - .44, depth - .44, .16), k.stone, .018)


def tablet(x, y, z, width=1.1, height=.7):
    role("structure", "Relief")
    k.box((x, y, z), (width, .06, height), k.lightstone, .018)
    for sx in [-1, 1]:
        k.box((x + sx * (width / 2 + .04), y - .035, z), (.055, .04, height + .13), k.stone, .008)
    for sz in [-1, 1]:
        k.box((x, y - .035, z + sz * (height / 2 + .04)), (width + .12, .04, .055), k.stone, .008)
    # Deliberately abstract horizontal cuts: no names or invented Latin text.
    role("detail", "Relief")
    for j, fraction in enumerate([.68, .82, .53, .73]):
        k.box((x, y - .04, z + height * (.27 - j * .17)), (width * fraction, .012, .018), "Incised_stone", 0)
    role("structure")


def wreath(x, y, z, radius=.27):
    role("detail", "Relief")
    points = [(x + radius * math.cos(i * math.tau / 24), y, z + radius * math.sin(i * math.tau / 24)) for i in range(25)]
    k.tube(points, .018, k.stone, 5)
    for i in range(14):
        a = i * math.tau / 14
        px, pz = x + radius * math.cos(a), z + radius * math.sin(a)
        tx, tz = -math.sin(a), math.cos(a)
        ox, oz = math.cos(a), math.sin(a)
        v = [(px - tx * .025, y, pz - tz * .025),
             (px + ox * .10 + tx * .025, y - .025, pz + oz * .10 + tz * .025),
             (px + tx * .13 + ox * .07, y, pz + tz * .13 + oz * .07),
             (px + tx * .10 - ox * .025, y - .015, pz + tz * .10 - oz * .025)]
        k.mesh(v, [(0, 1, 2), (0, 2, 3)], k.lightstone)
    role("structure")


def urn(x, y, z, size=1, bronze=False):
    role("structure", "Urns")
    material = k.bronze if bronze else k.lightstone
    profile = [(0, 0), (.21, 0), (.24, .06), (.17, .12), (.14, .20),
               (.28, .29), (.34, .43), (.30, .60), (.22, .69), (.21, .75),
               (.28, .78), (.29, .83), (.21, .88), (.10, .92), (.06, 1.00), (0, 1.04)]
    k.lathe((x, y, z), [(r * size, h * size) for r, h in profile], material, 20, preserve_profile=True)
    role("detail", "Urns")
    for side in [-1, 1]:
        k.tube([(x + side * r * size, y, z + h * size) for r, h in [(.26, .62), (.42, .62), (.44, .45), (.32, .38)]], .035 * size, material, 8)
    role("structure")


def altar(x, y, size=1, high=True):
    s = size
    steps(x, y, 2.35 * s, 2.10 * s, .56)
    role("structure")
    body_h = 1.85 * s if high else 1.25 * s
    base = .60
    k.box((x, y + .12, base + .10), (1.69 * s, 1.57 * s, .21), k.lightstone)
    k.box((x, y + .12, base + .22 + body_h / 2), (1.45 * s, 1.33 * s, body_h), k.stone)
    top = base + .22 + body_h
    for dz, w, d, height in [(.04, 1.57, 1.45, .14), (.19, 1.80, 1.67, .16), (.34, 1.72, 1.60, .16)]:
        k.box((x, y + .12, top + dz), (w * s, d * s, height), k.lightstone)
    # Rolled bolsters and a recessed offering tray distinguish the altar.
    for side in [-1, 1]:
        k.tube([(x + side * .65 * s, y - .47 * s, top + .47),
                (x + side * .65 * s, y + .68 * s, top + .47)], .15 * s, k.lightstone, 14)
    k.box((x, y + .12, top + .42), (.95 * s, .95 * s, .07), k.stone)
    tablet(x, y + .12 - .68 * s, base + .22 + body_h * .48, .94 * s, .69 * s)
    if high:
        wreath(x, y + .12 - .70 * s, top - .32 * s, .20 * s)
    for side in [-1, 1]:
        # Shallow side recesses finish the monument when the camera turns.
        k.box((x + side * .73 * s, y + .12, base + .22 + body_h / 2), (.025, .74 * s, body_h * .53), k.lightstone)
    return top + .56


def stele(x, y, height=2.55):
    steps(x, y, 1.55, 1.15, .48)
    role("structure")
    k.box((x, y + .10, .48 + (height - .94) / 2), (.98, .34, height - .94), k.stone)
    # Closed rounded top from an extruded half-circle, not a painted silhouette.
    r = .49
    poly = [(x - r, height - .46), (x + r, height - .46)]
    poly += [(x + r * math.cos(i * math.pi / 16), height - .46 + r * math.sin(i * math.pi / 16)) for i in range(17)]
    civic.extrude(poly, y -.07, y + .27, k.stone)
    tablet(x, y - .085, 1.38, .65, .62)
    wreath(x, y - .095, height - .43, .18)


def aedicula(x, y, size=1, brick=False):
    s = size
    steps(x, y, 3.35 * s, 3.10 * s, .60)
    role("structure")
    wall_mat = k.red if brick else k.stone
    bottom, wall_h = .65, 3.15 * s
    for xx in [x - 1.18 * s, x + 1.18 * s]:
        k.box((xx, y + .24 * s, bottom + wall_h / 2), (.27 * s, 2.30 * s, wall_h), wall_mat)
    k.box((x, y + 1.24 * s, bottom + wall_h / 2), (2.50 * s, .26 * s, wall_h), wall_mat)
    k.box((x, y + .26 * s, bottom + .06), (2.48 * s, 2.28 * s, .13), k.lightstone)
    # The portico and urn room are genuinely open in front.
    for xx in [x - 1.02 * s, x + 1.02 * s]:
        civic.column(xx, y - 1.02 * s, bottom, 2.92 * s, .16 * s)
    top = bottom + wall_h
    k.box((x, y + .12 * s, top + .02), (2.76 * s, 2.57 * s, .19), k.lightstone)
    k.box((x, y + .55 * s, bottom + .30), (.80 * s, .80 * s, .58), k.stone)
    urn(x, y + .55 * s, bottom + .60, .88 * s)
    tablet(x, y + 1.09 * s, bottom + 2.28 * s, 1.00 * s, .44 * s)
    # Gabled terracotta roof and stone pediment face the approach.
    role("roof", "Roof")
    civic.gable_roof(3.02 * s, 2.94 * s, top + .20, 1.02 * s, (x, y + .12 * s), True)
    role("detail", "Masonry")
    if brick:
        # Thin mortar courses articulate red masonry without voxel stairs.
        for j in range(max(2, round(wall_h / .24))):
            z = bottom + .11 + j * .24
            for xx in [x - 1.325 * s, x + 1.325 * s]:
                k.box((xx, y + .24 * s, z), (.014, 2.18 * s, .018), "Brick_mortar", 0)
            k.box((x, y + 1.38 * s, z), (2.47 * s, .014, .018), "Brick_mortar", 0)
    role("structure")


def round_memorial(x, y):
    role("structure")
    profile = [(0, 0), (1.30, 0), (1.30, .18), (1.20, .25), (1.20, .36),
               (1.04, .44), (1.04, 1.72), (1.12, 1.80), (1.21, 1.87),
               (1.21, 2.03), (1.12, 2.10), (0, 2.10)]
    k.lathe((x, y, .13), profile, k.stone, 40, preserve_profile=True)
    # Repeated shallow pilasters, a modest central tablet and a stepped top.
    for i in range(10):
        a = i * math.tau / 10
        k.lathe((x + 1.025 * math.cos(a), y + 1.025 * math.sin(a), .62), [(.065, 0), (.065, 1.15)], k.lightstone, 8)
    tablet(x, y - 1.07, 1.28, .78, .61)
    k.lathe((x, y, 2.23), [(0, 0), (.94, 0), (.94, .15), (.70, .15), (.70, .30), (.42, .30), (.42, .46), (0, .46)], k.lightstone, 32, preserve_profile=True)
    urn(x, y, 2.69, .90)


def exedra(x, y, radius=1.95):
    """Closed stone seat and low curved back, opening towards the front path."""
    role("structure", "Bench")
    segments = k.lod_count(24, 14, 10)
    for j in range(segments):
        a = j * math.pi / segments
        b = (j + 1) * math.pi / segments
        for r0, r1, bottom, top, mat in [(radius - .46, radius + .05, .15, .61, k.stone),
                                         (radius - .52, radius + .11, .61, .76, k.lightstone),
                                         (radius - .03, radius + .11, .76, 1.28, k.stone),
                                         (radius - .07, radius + .15, 1.28, 1.39, k.lightstone)]:
            vertices = [(x + r * math.cos(t), y + r * math.sin(t), z)
                        for z in [bottom, top] for r, t in [(r0, a), (r1, a), (r1, b), (r0, b)]]
            k.mesh(vertices, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mat)
    for side in [-1, 1]:
        k.box((x + side * (radius - .20), y, .91), (.40, .42, .49), k.stone)
    role("structure")


def altar_garden():
    ground()
    top = altar(-1.80, -1.42, 1, True)
    urn(-1.80, -1.30, top, .70)
    stele(1.58, -1.82, 2.58)
    role("structure")
    steps(2.28, .48, 1.28, 1.28, .50)
    k.box((2.28, .58, .96), (.78, .78, .86), k.red)
    k.box((2.28, .58, 1.42), (.94, .94, .15), k.lightstone)
    urn(2.28, .58, 1.50, .68)
    cypress(-3.40, 2.62, 6.60, .64)
    cypress(3.42, 2.78, 5.92, .57)
    for x, y in [(-2.1, 2.85), (1.8, 3.5), (-.8, 3.7), (3.5, .7)]:
        shrub(x, y)


def shrine_garden():
    ground()
    aedicula(.05, -.45, 1, True)
    altar(-2.83, -1.92, .60, False)
    stele(2.88, -1.90, 2.30)
    cypress(-3.42, 2.72, 6.35, .58)
    cypress(3.40, 2.67, 6.65, .62)
    for x, y in [(-2.05, 3.5), (1.8, 3.50), (-.25, 3.8)]:
        shrub(x, y, .34)
    role("structure", "Bench")
    k.box((0, 3.28, .60), (1.8, .53, .16), k.lightstone)
    for x in [-.65, .65]:
        k.box((x, 3.28, .33), (.30, .39, .40), k.stone)


def quiet_garden():
    ground()
    round_memorial(-2.06, -1.62)
    aedicula(2.25, -1.32, .64, False)
    exedra(0, 1.25, 1.92)
    cypress(-3.46, 2.72, 6.18, .57)
    cypress(3.42, 2.78, 5.74, .54)
    cypress(.20, 3.83, 6.68, .50)
    for x, y in [(-2.85, .45), (2.85, .65), (-1.0, 3.8)]:
        shrub(x, y, .29)


MODELS = {
    "verona_tombs_altar": altar_garden,
    "verona_tombs_shrine": shrine_garden,
    "verona_tombs_garden": quiet_garden,
}


def build(slug):
    initialize(slug)
    draw = MODELS[slug]
    draw()
    # A second pass retains closed solids while lowering curve segment counts.
    k.finish(slug, rebuilder=draw)
    path = k.ROOT / "app/assets/buildings" / slug / "model.json"
    data = json.loads(path.read_text())
    lo, hi = data["source_bounds_xyz"]
    assert hi[0] - lo[0] <= 9.20001 and hi[1] - lo[1] <= 9.20001, (slug, lo, hi)
    assert hi[2] - lo[2] <= 7.00001, (slug, lo, hi)
    data["design"] = {
        "status": "implementiert", "front": "south", "height_cap_m": 7,
        "footprint_cap_m": [9.2, 9.2], "clear_front_path_m": 1.15,
        "description": "Original typological memorial garden; quiet planted rear, southern approach and abstract nonverbal tablets",
        "provenance": "Original geometry; no claimed historical identity, copied inscription or terrain modification",
    }
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    selected = next((a.split("=", 1)[1] for a in args if a.startswith("--model=")), None)
    for slug in ([selected] if selected else list(MODELS)):
        if slug not in MODELS:
            raise ValueError("Unknown cemetery model: " + slug)
        print("BUILDING " + slug, flush=True)
        build(slug)
