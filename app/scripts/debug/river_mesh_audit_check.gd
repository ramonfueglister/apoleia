extends SceneTree
const Audit=preload("res://scripts/debug/river_mesh_audit.gd")
var failures: Array[String]=[]
func check(ok: bool, message: String) -> void:
	if not ok:failures.append(message);push_error(message)
func plane(rise: float, tilt: float) -> PackedVector3Array:
	# Match actual Verona coordinate magnitude, including float32 mesh storage.
	var a:=Vector3(-672,.6,-495.05)
	var b:=Vector3(-671.5,.6+rise,-495.05)
	var c:=Vector3(-671.5,.6+rise+tilt,-494.95)
	var d:=Vector3(-672,.6+tilt,-494.95)
	return PackedVector3Array([a,b,c,a,c,d])
func _initialize() -> void:
	var points: Array[Vector2]=[Vector2(-671.95,-495),Vector2(-671.75,-495),Vector2(-671.55,-495)]
	check(Audit.profile(plane(-.01,0),points).failures.is_empty(),"Valid downstream slope rejected")
	check(not Audit.profile(plane(.01,0),points).failures.is_empty(),"Upstream slope escaped audit")
	check(not Audit.profile(plane(0,.01),points).failures.is_empty(),"Cross-channel tilt escaped audit")
	check(not Audit.profile(PackedVector3Array(),points).failures.is_empty(),"Missing geometry escaped audit")
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in plane(-.01,0):st.add_vertex(vertex)
	var uploaded:=st.commit()
	var extracted: PackedVector3Array=Audit.faces_of(uploaded,Transform3D.IDENTITY)
	check(extracted.size()==6,"Non-indexed uploaded triangle extraction failed")
	check(Audit.profile(extracted,points).failures.is_empty(),"Uploaded geometry audit failed")
	print("RIVER_MESH_AUDIT_CHECK failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
