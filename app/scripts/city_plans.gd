extends RefCounted
## The city plans (docs/kit2/CITY_PLANS.md, baked by tools/city_plans.py
## --bake into artifacts/render-data/city-plans-r1): what stands on every
## 0.25 km parcel of a city, the parcels being the tile terrain's quarter
## tiles (one house lot each), aligned to its world_min.
##
## The map is paged: pages of page_parcels x page_parcels parcels, those that
## hold part of a city stored as slots of one RGB8 atlas. `page_tex` has a
## texel per page: 0 where no city is, else the slot + 1 in R (low byte) and
## G (high byte). A shader finds a parcel's texel with two texelFetch:
##
##     ivec2 page = parcel / page_parcels;
##     vec2 s = texelFetch(city_page_tex, page, 0).rg * 255.0;
##     int slot = int(s.r + 0.5) + 256 * int(s.g + 0.5) - 1;   // -1: no plan
##     ivec2 at = ivec2(slot % atlas_slots, slot / atlas_slots) * page_parcels + parcel % page_parcels;
##     vec3 texel = texelFetch(city_atlas_tex, at, 0).rgb * 255.0;
##
## R is the kind (CODES; 0 = no plan, the old town rule), G the street
## (surface, rank, links N/E/S/W), B the storeys or the model and the side
## the front faces; the bake's JSON says it bit by bit. Colours, models and
## terraces are the renderer's.

const DIR := "artifacts/render-data/city-plans-r1"
const CODES := ["none", "house", "insula", "domus", "building", "plaza", "garden", "street", "wall", "gate",
	"bridge", "tombs", "land", "water"]

var info: Dictionary
var page_parcels := 64
var atlas_slots := 32
var parcel_km := 0.25
var world_min := Vector2.ZERO
var page_size := Vector2i.ZERO
var page_tex: ImageTexture
var atlas_tex: ImageTexture
var _pages: Image
var _atlas: Image

## Loads the plans baked at `scale` (1 = the diorama scale); false when
## they are missing (then every town keeps the old rule).
func load_plans(root: String, scale := 1.0, world_size := Vector2(10322.15905608411, 4781.388450041915)) -> bool:
	var dir := root.path_join(DIR)
	var text := FileAccess.get_file_as_string(dir.path_join("city-plans-x%s.json" % str(scale).trim_suffix(".0")))
	if text == "":
		push_warning("city plans missing in %s (run tools/city_plans.py --bake)" % dir)
		return false
	info = JSON.parse_string(text)
	page_parcels = int(info.page_parcels)
	atlas_slots = int(info.atlas_slots_per_row)
	parcel_km = float(info.parcel_km)
	world_min = Vector2(info.world_min[0], info.world_min[1])
	var page_km := parcel_km * page_parcels
	page_size = Vector2i(ceili(world_size.x / page_km), ceili(world_size.y / page_km))
	var bytes := PackedByteArray()
	bytes.resize(page_size.x * page_size.y * 2)
	for entry: Array in info.page_slots:
		var i := int(entry[0])
		var j := int(entry[1])
		if i < 0 or j < 0 or i >= page_size.x or j >= page_size.y:
			continue
		var v := int(entry[2]) + 1
		bytes[(j * page_size.x + i) * 2] = v & 255
		bytes[(j * page_size.x + i) * 2 + 1] = v >> 8
	_pages = Image.create_from_data(page_size.x, page_size.y, false, Image.FORMAT_RG8, bytes)
	page_tex = ImageTexture.create_from_image(_pages)
	_atlas = Image.load_from_file(dir.path_join(info.atlas))
	_atlas.convert(Image.FORMAT_RGB8)
	atlas_tex = ImageTexture.create_from_image(_atlas)
	return true

## The parcel under a world point (km).
func parcel_at(x_km: float, z_km: float) -> Vector2i:
	return Vector2i(floori((x_km - world_min.x) / parcel_km), floori((z_km - world_min.y) / parcel_km))

## R, G, B of a parcel (0, 0, 0 where no city is).
func texel(parcel: Vector2i) -> Vector3i:
	if _pages == null or parcel.x < 0 or parcel.y < 0:
		return Vector3i.ZERO
	var page := parcel / page_parcels
	if page.x >= page_size.x or page.y >= page_size.y:
		return Vector3i.ZERO
	var p := _pages.get_pixelv(page)
	var slot := roundi(p.r * 255.0) + 256 * roundi(p.g * 255.0) - 1
	if slot < 0:
		return Vector3i.ZERO
	var at := Vector2i(slot % atlas_slots, slot / atlas_slots) * page_parcels + Vector2i(parcel.x % page_parcels, parcel.y % page_parcels)
	var c := _atlas.get_pixelv(at)
	return Vector3i(roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0))

## What stands on a parcel: "house", "street", "building" ... ("none" where
## no city is).
func kind(parcel: Vector2i) -> String:
	var r := texel(parcel).x
	return CODES[r] if r < CODES.size() else "none"

## The uniforms a shader needs (names as in the comment above).
func uniforms() -> Dictionary:
	return {
		"city_page_tex": page_tex, "city_atlas_tex": atlas_tex,
		"city_page_parcels": page_parcels, "city_atlas_slots": atlas_slots,
	}
