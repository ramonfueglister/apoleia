extends SceneTree
## People in big PortraitViews (rendered at 672 x 840, shown at 336 x 420).
## Args after --: persons.json out.png idx,idx,...

const PortraitView = preload("res://scripts/ui/portrait_view.gd")

var frames := 0
var out := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var people: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	out = args[1]
	var pick: Array = Array(args[2].split(",")).map(func(s): return int(s))
	var c = load("/home/claude/work/gdtest/pc_big.gd").new()
	c.name = "PortraitCache"
	root.set_meta("portrait_cache", c)
	root.add_child.call_deferred(c)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.12)
	bg.size = Vector2(2120, 870)
	layer.add_child(bg)
	for k in pick.size():
		var p: Dictionary = people[pick[k]]
		p.dna = PackedByteArray(p.dna)
		var v = PortraitView.new()
		v.scale = Vector2(3, 3)
		v.position = Vector2((k % 6) * 350 + 8, 10 + (k / 6) * 430)
		layer.add_child(v)
		v.show_person.call_deferred(p)

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 40:
		root.get_texture().get_image().save_png(out)
		return true
	return false
