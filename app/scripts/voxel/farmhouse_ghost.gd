extends MeshInstance3D
## The farmhouse a lot would get, as a see-through ghost for the build menu
## (build_menu.gd): the same build, turn, mirror and size that
## people_houses.gdshader gives the house on that lot, so what the player
## places is what then stands there. Green where it can be built, red
## where not (shaders/farmhouse_ghost.gdshader).
##
##   setup(terrain)       once
##   show_at(p, ok)       on the lot under p (world km)
##   visible = false      to put it away
##
## The lot rules mirror people_dots_common.gdshaderinc (DOT_LOT_KM, dot_lot,
## dot_hash, dot_rand2, dot_house_turn) and the build pick in
## people_houses.gdshader; change them together.

const Farmhouse = preload("res://scripts/voxel/farmhouse.gd")
const TileTerrain = preload("res://scripts/tile_terrain.gd")
const GHOST_SHADER = preload("res://shaders/farmhouse_ghost.gdshader")
const LOT_KM := 0.5 # people_dots_common.gdshaderinc DOT_LOT_KM
const OK := Color(0.55, 0.9, 0.45)
const NOT_OK := Color(0.95, 0.35, 0.3)
const MASK := 0xffffffff

var terrain: Node3D
var _meshes: Array[ArrayMesh] = []
var _material := ShaderMaterial.new()
var _lot := Vector2.INF # centre of the lot shown

func setup(terrain_node: Node3D) -> void:
	terrain = terrain_node
	for variant in Farmhouse.VARIANTS:
		_meshes.append(Farmhouse.lods(TileTerrain.HOUSE_M, variant)[1]) # the 0.25 m level: fine enough up close
	_material.shader = GHOST_SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

## Shows the ghost on the lot under p (world km).
func show_at(p: Vector2, ok: bool) -> void:
	var origin: Vector2 = terrain.world_min
	var lot := ((p - origin) / LOT_KM).floor()
	_lot = origin + (lot + Vector2(0.5, 0.5)) * LOT_KM
	var lx := int(lot.x)
	var ly := int(lot.y)
	# the build: people_houses.gdshader `key`
	var key := _hash(_mul(lx, 0x2545f491) ^ _mul(ly, 0x9e3779b9))
	mesh = _meshes[(key >> 12) % Farmhouse.VARIANTS]
	# turn, mirror and size: dot_house_turn
	var turn_key := _hash(_mul(lx, 0x9e3779b1) ^ _mul(ly, 0x85ebca77))
	var r := _rand2(turn_key, 7)
	var a := (0.0 if r.x < 0.5 else 1.0 if r.x < 0.75 else 3.0) * PI * 0.5
	var m := -1.0 if _rand2(turn_key, 8).x < 0.5 else 1.0
	var s: float = TileTerrain.HOUSE_M * TileTerrain.DIORAMA_KM_PER_M * (0.9 + 0.2 * r.y)
	# x' = cos·m·x − sin·z, z' = sin·m·x + cos·z (the shader's mat2 product)
	basis = Basis(Vector3(cos(a) * m, 0.0, sin(a) * m) * s, Vector3(0.0, s, 0.0), Vector3(-sin(a), 0.0, cos(a)) * s)
	_material.set_shader_parameter("tint", OK if ok else NOT_OK)
	_place()
	visible = true

func _process(_delta: float) -> void:
	if visible:
		_place() # the terraces flatten and rise with the zoom (tile_terrain.gd relief_for_width)

func _place() -> void:
	var y: float = terrain.ground_y(_lot)
	position = Vector3(_lot.x, y, _lot.y)

## x · c modulo 2^32 as GLSL's uint, in two halves so the 64-bit product
## never overflows.
static func _mul(x: int, c: int) -> int:
	x &= MASK
	return (x * (c & 0xffff) + (((x * (c >> 16)) & 0xffff) << 16)) & MASK

static func _hash(x: int) -> int:
	x &= MASK
	x ^= x >> 16
	x = _mul(x, 0x7feb352d)
	x ^= x >> 15
	x = _mul(x, 0x846ca68b)
	x ^= x >> 16
	return x

static func _rand2(key: int, k: int) -> Vector2:
	var a := _hash((_mul(key, 0x9e3779b9) + _mul(k, 0x632be5ab)) & MASK)
	var b := _hash(a ^ 0x5bd1e995)
	return Vector2(a & 0xffff, b & 0xffff) / 65535.0
