extends RefCounted
## Small charts drawn onto any CanvasItem, in the windows' palette: a
## sparkline (a series with a faint area under it and its last value as a
## dot) and the same with a band around it (prices: median, between min
## and max). Used in table cells, tooltips and the windows' charts.
##
## The colours are checked for colour blind readers on the windows'
## background (#14242c): gold, blue, madder, violet, green in this order
## for series; RED for what is bad (hunger), as EU5 shows it.

const SERIES: Array[Color] = [Color("b8893a"), Color("1f9cc4"), Color("cf5f44"), Color("8f6fd0"), Color("6f9a3a")]
const RED := Color("e8846b")
const GRID := Color(1.0, 1.0, 1.0, 0.07)
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

## EU5's economy graph: a dark field with a faint grid, the highest value
## at the top left and the lowest at the bottom left, the first and last
## date in the corners below. `series` holds {values, colour} and may hold
## lo and hi (a band around the line, the price's range); all share one
## scale. `hover` >= 0 marks that month with a line and dots.
static func line_chart(ci: CanvasItem, rect: Rect2, series: Array, font: Font, unit := "",
		from := "", to := "", hover := -1) -> void:
	ci.draw_rect(rect, Color(0, 0, 0, 0.28))
	var plot := Rect2(rect.position + Vector2(0, 4), rect.size - Vector2(0, 26 if from != "" else 8))
	for k in 5:
		var y := plot.position.y + plot.size.y * k / 4.0
		ci.draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)
	for k in 9:
		var x := plot.position.x + plot.size.x * k / 8.0
		ci.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), GRID, 1.0)
	var n := 0
	var lo := INF
	var hi := -INF
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
		ci.draw_string(font, plot.get_center() - Vector2(70, 0), "Noch zu wenige Monate", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
		return
	if lo >= 0.0 and lo < hi * 0.4:
		lo = 0.0 # counts from nothing
	if hi - lo < 1e-9:
		hi = lo + 1.0
	var inner := plot.grow_individual(-6, -20, -6, -4)
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
				ci.draw_colored_polygon(band, Color(c, 0.2))
		var line := PackedVector2Array()
		for i in vals.size():
			line.append(Vector2(x_of.call(i), y_of.call(vals[i])))
		ci.draw_polyline(line, c, 2.0, true)
		ci.draw_circle(line[line.size() - 1], 3.0, c)
	var ink := Color("e6dcc6")
	ci.draw_string(font, plot.position + Vector2(6, 15), label(hi, unit), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	ci.draw_string(font, Vector2(plot.position.x + 6, plot.end.y - 5), label(lo, unit), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	if from != "":
		var dim := Color("9aa3a6")
		ci.draw_string(font, Vector2(rect.position.x + 4, rect.end.y - 5), from, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
		ci.draw_string(font, Vector2(rect.position.x, rect.end.y - 5), to, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 4, 12, dim)
	if hover >= 0 and hover < n:
		var x: float = x_of.call(hover)
		ci.draw_dashed_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(ink, 0.5), 1.0, 4.0)
		for s in series:
			if hover < s.values.size():
				ci.draw_circle(Vector2(x, y_of.call(s.values[hover])), 4.5, Color("10161d"))
				ci.draw_circle(Vector2(x, y_of.call(s.values[hover])), 3.2, s.colour)

## The month under `local_x` of a line chart drawn into `rect` over n months.
static func month_at(rect: Rect2, n: int, local_x: float) -> int:
	if n < 2:
		return -1
	var inner := rect.grow_individual(-6, 0, -6, 0)
	return clampi(roundi((local_x - inner.position.x) / inner.size.x * (n - 1)), 0, n - 1)

## A ring of shares, each a slice with a small gap, as EU5's culture ring.
## `hover` >= 0 pulls that slice out a little.
static func donut(ci: CanvasItem, centre: Vector2, radius: float, width: float, values: PackedFloat64Array,
		colours: Array, hover := -1) -> void:
	var total := 0.0
	for v in values:
		total += maxf(v, 0.0)
	ci.draw_arc(centre, radius - width * 0.5, 0.0, TAU, 96, Color(0, 0, 0, 0.3), width + 4.0, true)
	if total <= 0.0:
		return
	var gap := 0.02 if values.size() > 1 else 0.0
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
		text = "%.2f" % v if a >= 0.01 or a == 0.0 else "%.3f" % v
	return text if unit == "" else "%s %s" % [text, unit]
