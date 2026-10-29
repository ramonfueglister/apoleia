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
