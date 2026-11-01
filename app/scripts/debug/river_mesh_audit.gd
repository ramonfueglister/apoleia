extends RefCounted
## Independent water geometry checks. Feed the actual uploaded water mesh,
## not its source profile. Water must have no shader vertical displacement.

static func faces_of(mesh: Mesh, transform: Transform3D) -> PackedVector3Array:
	var faces:=PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays:=mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for p in vertices:faces.append(transform*p)
		else:
			for i in indices:faces.append(transform*vertices[i])
	return faces

static func heights_at(faces: PackedVector3Array, point: Vector2) -> Array[float]:
	var heights: Array[float]=[]
	for i in range(0,faces.size(),3):
		var a:=faces[i];var b:=faces[i+1];var c:=faces[i+2]
		var ab:=Vector2(b.x-a.x,b.z-a.z);var ac:=Vector2(c.x-a.x,c.z-a.z)
		var delta:=point-Vector2(a.x,a.z);var determinant:=ab.cross(ac)
		if absf(determinant)<1e-12:continue
		var u:=delta.cross(ac)/determinant;var v:=ab.cross(delta)/determinant
		if u>=-.0001 and v>=-.0001 and u+v<=1.0001:
			heights.append(a.y+u*(b.y-a.y)+v*(c.y-a.y))
	return heights

static func profile(faces: PackedVector3Array, points: Array[Vector2], cross_half: float=.04) -> Dictionary:
	var failures: Array[String]=[];var samples: Array=[]
	var previous: float=NAN;var max_rise:=0.0;var max_cross:=0.0;var max_overlap:=0.0
	for i in points.size():
		var p:=points[i];var hits:=heights_at(faces,p)
		if hits.is_empty():
			failures.append("Water mesh gap at sample %d"%i);continue
		var h: float=hits[0]
		for other in hits:max_overlap=maxf(max_overlap,absf(h-other))
		if is_finite(previous):max_rise=maxf(max_rise,h-previous)
		previous=h
		# Caller should pass one straight segment at a time for cross-sections;
		# the direction at bends otherwise needs a separately specified miter.
		var tangent: Vector2=points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]
		var normal:=Vector2(-tangent.y,tangent.x).normalized()
		var cross_heights: Array[float]=[]
		for offset in [-cross_half,0.0,cross_half]:
			var cross_hits:=heights_at(faces,p+normal*offset)
			if cross_hits.is_empty():failures.append("Water cross-section gap at sample %d"%i)
			else:cross_heights.append(cross_hits[0])
		if cross_heights.size()==3:
			max_cross=maxf(max_cross,cross_heights.max()-cross_heights.min())
		samples.append({"xz":[p.x,p.y],"height":h})
	if max_rise>.0001:failures.append("Rendered water rises downstream")
	if max_cross>.0001:failures.append("Rendered water tilts across channel")
	if max_overlap>.0001:failures.append("Overlapping water triangles have different heights")
	return {"failures":failures,"samples":samples,"maximum_rise_km":max_rise,"maximum_cross_difference_km":max_cross,"maximum_overlap_difference_km":max_overlap}
