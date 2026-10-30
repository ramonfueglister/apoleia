extends RefCounted
## Small charts drawn onto any CanvasItem, in the windows' palette: a
## sparkline (a series with a faint area under it and its last value as a
## dot) and the same with a band around it (prices: median, between min
## and max). Used in table cells, tooltips and the windows' charts.
##
## The colours are checked for colour blind readers on the windows'
## background (#14242c): gold, blue, madder, violet, green in this order
## for series; RED for what is bad (hunger), as EU5 shows it.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const SERIES: Array[Color] = [Color("b8893a"), Color("1f9cc4"), Color("cf5f44"), Color("8f6fd0"), Color("6f9a3a")]
const RED := Color("e8846b")
const GRID := Color(1.0, 1.0, 1.0, 0.07)
const CELL := 28.0 # the side of a square of EU5's chart grid
const BAND_REACH := 2.0

## `values` as a line over `rect`, scaled to their own range (or to
## lo..hi when given), with the area under it and a dot on the last.
static func spark(ci: CanvasItem, rect: Rect2, values: PackedFloat64Array, colour: Color,
		band_lo := PackedFloat64Array(), band_hi := PackedFloat64Array()) -> void:
	var n := values.size()
	if n < 2:
		if n == 1:
			ci.draw_circle(Vector2(rect.end.x - 2.0, rect.get_center().y), 2.0, colour)
		return
	var lo := INF
	var hi := -INF
	for v in values + band_lo + band_hi:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 1e-12:
		lo -= 1.0
		hi += 1.0
	var x_of := func(i: int) -> float: return rect.position.x + rect.size.x * float(i) / float(n - 1)
	var y_of := func(v: float) -> float: return rect.end.y - 1.0 - (v - lo) / (hi - lo) * (rect.size.y - 2.0)
	if band_lo.size() == n and band_hi.size() == n:
		var band := PackedVector2Array()
		for i in n:
			band.append(Vector2(x_of.call(i), y_of.call(band_hi[i])))
		for i in range(n - 1, -1, -1):
			band.append(Vector2(x_of.call(i), y_of.call(band_lo[i])))
		if Geometry2D.triangulate_polygon(band).size() > 0:
			ci.draw_colored_polygon(band, Color(colour, 0.18))
	var line := PackedVector2Array()
	for i in n:
		line.append(Vector2(x_of.call(i), y_of.call(values[i])))
	if band_lo.is_empty():
		var area := line.duplicate()
		area.append(Vector2(rect.end.x, rect.end.y))
		area.append(Vector2(rect.position.x, rect.end.y))
		if Geometry2D.triangulate_polygon(area).size() > 0:
			ci.draw_colored_polygon(area, Color(colour, 0.14))
	ci.draw_polyline(line, colour, 1.5, true)
	ci.draw_circle(line[n - 1], 2.2, colour)

## A share 0..1 as a thin bar along the foot of `rect`.
static func share(ci: CanvasItem, rect: Rect2, v: float, colour: Color) -> void:
	var bar := Rect2(rect.position.x, rect.end.y - 4.0, rect.size.x, 3.0)
	ci.draw_rect(bar, GRID)
	bar.size.x *= clampf(v, 0.0, 1.0)
	ci.draw_rect(bar, colour)

## EU5's chart board: dark brown, a grid of squares in darker lines, a
## shadow falling in from the left, in a thin pale line and a black one.
static func board(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, UiStyle.CHART)
	for k in 8:
		ci.draw_rect(Rect2(rect.position.x + k * 4.0, rect.position.y, 4.0, rect.size.y), Color(0, 0, 0, 0.05 * (8 - k)))
	var cols := maxi(1, roundi(rect.size.x / CELL))
	var rows := maxi(1, roundi(rect.size.y / CELL))
	for k in range(1, cols):
		var x := rect.position.x + rect.size.x * k / cols
		ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), UiStyle.CHART_GRID, 1.0)
	for k in range(1, rows):
		var y := rect.position.y + rect.size.y * k / rows
		ci.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), UiStyle.CHART_GRID, 1.0)
	ci.draw_rect(rect.grow(-1.5), UiStyle.CHART_EDGE, false, 1.0)
	ci.draw_rect(rect, UiStyle.EDGE, false, 1.0)

## EU5's economy graph: the brown board with its grid of squares, the
## highest value at the top left and the lowest at the bottom left, the
## first and last date in italics in the corners below. `series` holds
## {values, colour} and may hold lo and hi (a band around the line, the
## price's range), dashed (a level to reach, drawn as a dashed line) and
## hidden (left out, the scale too); all share one scale. `hover` >= 0
## marks that month with a line, dots and each series' value beside its dot.
static func line_chart(ci: CanvasItem, rect: Rect2, series: Array, font: Font, unit := "",
		from := "", to := "", hover := -1) -> void:
	board(ci, rect)
	var plot := Rect2(rect.position + Vector2(0, 4), rect.size - Vector2(0, 30 if from != "" else 8))
	var n := 0
	var lo := INF
	var hi := -INF
	series = series.filter(func(s): return not s.get("hidden", false))
	for s in series:
		var vals: PackedFloat64Array = s.values
		n = maxi(n, vals.size())
		for v in vals:
			lo = minf(lo, v)
			hi = maxf(hi, v)
	# a band reaches at most BAND_REACH times its line's value of that month,
	# so a single dear market (Rome) does not squash the median flat
	for s in series:
		if s.has("lo") and s.has("hi"):
			var vals: PackedFloat64Array = s.values
			var cut_lo := PackedFloat64Array()
			var cut_hi := PackedFloat64Array()
			for i in vals.size():
				cut_lo.append(maxf(float(s.lo[i]), vals[i] / BAND_REACH))
				cut_hi.append(minf(float(s.hi[i]), vals[i] * BAND_REACH))
				lo = minf(lo, cut_lo[i])
				hi = maxf(hi, cut_hi[i])
			s["band_lo"] = cut_lo
			s["band_hi"] = cut_hi
	if n < 2:
		UiStyle.text_at(ci, plot.get_center() - Vector2(80, 0), "Noch zu wenige Monate", UiStyle.DIM, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.italic())
		return
	if lo >= 0.0 and lo < hi * 0.4:
		lo = 0.0 # counts from nothing
	if hi - lo < 1e-9:
		hi = lo + 1.0
	var inner := plot.grow_individual(-4, -18, -4, -6)
	var x_of := func(i: int) -> float: return inner.position.x + inner.size.x * float(i) / float(n - 1)
	var y_of := func(v: float) -> float: return inner.end.y - (v - lo) / (hi - lo) * inner.size.y
	for s in series:
		var vals: PackedFloat64Array = s.values
		var c: Color = s.colour
		if s.has("lo") and s.has("hi"):
			var band := PackedVector2Array()
			for i in vals.size():
				band.append(Vector2(x_of.call(i), y_of.call(s.band_hi[i])))
			for i in range(vals.size() - 1, -1, -1):
				band.append(Vector2(x_of.call(i), y_of.call(s.band_lo[i])))
			if Geometry2D.triangulate_polygon(band).size() > 0:
				ci.draw_colored_polygon(band, Color(c, 0.22))
		var line := PackedVector2Array()
		for i in vals.size():
			line.append(Vector2(x_of.call(i), y_of.call(vals[i])))
		if s.get("dashed", false):
			for dash in _dashes(line, 10.0, 6.0):
				ci.draw_polyline(dash, Color(0, 0, 0, 0.5), 5.0, true)
				ci.draw_polyline(dash, c, 2.5, true)
			continue
		ci.draw_polyline(line, Color(0, 0, 0, 0.4), 5.0, true)
		ci.draw_polyline(line, c, 3.0, true)
	var f := font if font != null else UiStyle.serif()
	UiStyle.text_at(ci, plot.position + Vector2(10, 24), label(hi, unit), UiStyle.VALUE, UiStyle.SIZE_HEAD + 2, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	UiStyle.text_at(ci, Vector2(plot.position.x + 10, plot.end.y - 6), label(lo, unit), UiStyle.VALUE, UiStyle.SIZE_HEAD + 2, HORIZONTAL_ALIGNMENT_LEFT, -1, f)
	if from != "":
		var it := UiStyle.italic()
		UiStyle.text_at(ci, Vector2(rect.position.x + 10, rect.end.y - 8), from, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, it)
		UiStyle.text_at(ci, Vector2(rect.position.x, rect.end.y - 8), to, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 10, it)
	if hover >= 0 and hover < n:
		var x: float = x_of.call(hover)
		ci.draw_dashed_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(UiStyle.TEXT, 0.55), 1.0, 4.0)
		# each value beside its dot at once, on the side with room; the
		# tooltip with the month's details follows after the dwell
		var left := x > plot.get_center().x
		var taken: Array[float] = []
		var marks := series.filter(func(s): return hover < s.values.size())
		marks.sort_custom(func(a, b): return a.values[hover] > b.values[hover]) # top down, labels in the lines' order
		for s in marks:
			var at := Vector2(x, y_of.call(s.values[hover]))
			ci.draw_circle(at, 5.0, UiStyle.EDGE)
			ci.draw_circle(at, 3.5, s.colour)
			var y := at.y + 5.0
			for t in taken: # don't print over a value above
				if absf(y - t) < 17.0:
					y = t + 17.0
			taken.append(y)
			var text := label(s.values[hover], unit)
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x + 10.0
			var box := Rect2(at.x - w - 8.0 if left else at.x + 8.0, y - 14.0, w, 18.0)
			ci.draw_rect(box, Color(UiStyle.TIP_BODY, 0.92))
			ci.draw_rect(box, s.colour, false, 1.0)
			UiStyle.text_at(ci, box.position + Vector2(5, 14), text, UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, f)

## The dashes along a polyline, `on` px drawn and `off` px left out, the
## pattern running on over the corners (months are only a few px apart).
static func _dashes(line: PackedVector2Array, on: float, off: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var dash := PackedVector2Array()
	var left := on # px left of the current dash or gap
	var drawing := true
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var length := a.distance_to(b)
		var done := 0.0
		if drawing and dash.is_empty():
			dash.append(a)
		while length - done > left:
			done += left
			var p := a.lerp(b, done / length)
			if drawing:
				dash.append(p)
				out.append(dash)
				dash = PackedVector2Array()
			else:
				dash.append(p)
			drawing = not drawing
			left = on if drawing else off
		left -= length - done
		if drawing:
			dash.append(b)
	if dash.size() > 1:
		out.append(dash)
	return out

## The month under `local_x` of a line chart drawn into `rect` over n months.
static func month_at(rect: Rect2, n: int, local_x: float) -> int:
	if n < 2:
		return -1
	var inner := rect.grow_individual(-4, 0, -4, 0)
	return clampi(roundi((local_x - inner.position.x) / inner.size.x * (n - 1)), 0, n - 1)

## A ring of shares, each a slice with a small gap, as EU5's culture ring.
## `hover` >= 0 pulls that slice out a little.
static func donut(ci: CanvasItem, centre: Vector2, radius: float, width: float, values: PackedFloat64Array,
		colours: Array, hover := -1) -> void:
	var total := 0.0
	for v in values:
		total += maxf(v, 0.0)
	# EU5's ring: a black disc, the slices without gaps, a dark middle
	ci.draw_circle(centre, radius + 4.0, UiStyle.EDGE)
	ci.draw_circle(centre, radius + 2.0, Color("2b2a26"))
	ci.draw_circle(centre, radius, UiStyle.EDGE)
	ci.draw_circle(centre, radius - width - 1.0, Color("1a2026"))
	if total <= 0.0:
		return
	var gap := 0.0
	var a := -PI / 2.0
	for i in values.size():
		var sweep := maxf(values[i], 0.0) / total * TAU
		if sweep > gap * 1.5:
			var r := radius - width * 0.5 + (3.0 if i == hover else 0.0)
			var steps := maxi(4, int(sweep / TAU * 96.0))
			ci.draw_arc(centre, r, a + gap * 0.5, a + sweep - gap * 0.5, steps, colours[i % colours.size()], width, true)
		a += sweep

## The slice of a donut under `local`, or -1.
static func slice_at(centre: Vector2, radius: float, width: float, values: PackedFloat64Array, local: Vector2) -> int:
	var d := local - centre
	if d.length() > radius + 4.0 or d.length() < radius - width - 4.0:
		return -1
	var total := 0.0
	for v in values:
		total += maxf(v, 0.0)
	if total <= 0.0:
		return -1
	var angle := fposmod(d.angle() + PI / 2.0, TAU)
	var a := 0.0
	for i in values.size():
		a += maxf(values[i], 0.0) / total * TAU
		if angle <= a:
			return i
	return values.size() - 1

## A value with its unit, short: 1.2 Mio, 34k, 512, 0.23.
static func label(v: float, unit := "") -> String:
	var a := absf(v)
	var text := ""
	if a >= 1.0e6:
		text = "%.1f Mio" % (v / 1.0e6)
	elif a >= 1.0e4:
		text = "%dk" % roundi(v / 1000.0)
	elif a >= 100.0:
		text = "%d" % roundi(v)
	elif a >= 1.0:
		text = "%.1f" % v
	else:
		text = "0" if a == 0.0 else ("%.2f" % v if a >= 0.01 else "%.3f" % v)
	return text if unit == "" else "%s %s" % [text, unit]
