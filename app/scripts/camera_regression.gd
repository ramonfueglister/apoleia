extends SceneTree
const Rig=preload("res://scripts/landscape_camera.gd")
var failures: Array=[]
var camera: Camera3D

func check(condition: bool, label: String) -> void:
    if not condition: failures.append(label);push_error(label)

func height(p: Vector2) -> float:
    return 1.2+sin(p.x*0.7)*0.15+sin(p.y*0.6)*0.24

func flat(_p: Vector2) -> float: return 0.0

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var viewport=SubViewport.new()
    root.add_child(viewport)
    var scene=Node3D.new()
    viewport.add_child(scene)
    camera=Camera3D.new()
    camera.projection=Camera3D.PROJECTION_PERSPECTIVE
    camera.keep_aspect=Camera3D.KEEP_HEIGHT
    scene.add_child(camera)
    var count=0
    var max_pick_error=0.0
    var max_anchor_pixel_error=0.0
    for size in [Vector2i(1440,1080),Vector2i(1728,1080),Vector2i(1920,1080),Vector2i(2520,1080)]:
        viewport.size=size
        var aspect=float(size.x)/size.y
        # Perspective contract covers the app zoom range (NEAR_WIDTH and up).
        for width in [10000.,1500.,700.,400.,200.,Rig.NEAR_WIDTH]:
            var profile=Rig.profile(width)
            var fov=Rig.perspective_fov(profile.y)
            var angle=deg_to_rad(profile.x)
            var basis=Basis(Vector3.RIGHT,Vector3(0,cos(angle),-sin(angle)),Vector3(0,sin(angle),cos(angle)))
            var distance=Rig.perspective_distance(width,aspect,fov)
            camera.fov=fov;camera.near=distance*.002;camera.far=distance*24.0
            var target=Vector2(2265.,2223.)
            var place=func(t:Vector2):camera.transform=Transform3D(basis,Vector3(t.x,height(t),t.y)+basis.z*distance)
            place.call(target)
            var footprint=Rig.perspective_footprint_offsets(width,aspect,profile.x,fov,profile.y,height(target))
            for point in [Vector2(size)*.5,Vector2(size)*Vector2(.15,.20),Vector2(size)*Vector2(.83,.87)]:
                var picked=Rig.pick(camera,point,Callable(self,"height"),1.)
                var projected=camera.unproject_position(Vector3(picked.x,height(picked),picked.y))
                max_pick_error=maxf(max_pick_error,projected.distance_to(point))
                check(projected.distance_to(point)<1.0,"ray reprojection %s %s"%[size,width])
                # Same fixed point as landscape._anchored_target.
                var goal=point+Vector2(73,-91)
                var pick_at=func(px:Vector2):return Rig.pick(camera,px,Callable(self,"height"),1.)
                var anchored=Rig.solve_anchor(picked,goal,target,place,pick_at,maxf(width*.002,.001))
                place.call(anchored)
                projected=camera.unproject_position(Vector3(picked.x,height(picked),picked.y))
                var error=projected.distance_to(goal)
                max_anchor_pixel_error=maxf(max_anchor_pixel_error,error)
                # The wavy synthetic surface can be hit twice by one ray; 1.5 px bound.
                check(error<1.5,"ground anchor %s %s = %f"%[size,width,error])
                place.call(target)
                count+=1
            for corner in [Vector2.ZERO,Vector2(size)*Vector2(1,0),Vector2(size)*Vector2(0,1),Vector2(size)]:
                var ray=camera.project_ray_normal(corner)
                var origin=camera.project_ray_origin(corner)
                for altitude in [Rig.MIN_HEIGHT*profile.y,Rig.MAX_HEIGHT*profile.y]:
                    if ray.y>-0.0001:continue
                    var p=origin+ray*((altitude-origin.y)/ray.y)
                    var relative=Vector2(p.x,p.z)-target
                    var slack=maxf(.05,width*.001)
                    check(relative.x>=footprint.position.x-slack and relative.x<=footprint.end.x+slack and relative.y>=footprint.position.y-slack and relative.y<=footprint.end.y+slack,"full corner footprint %s %s"%[size,width])
    var state=Vector2.ZERO
    for i in range(15): state=Rig.damp(state.x,state.y,1.,1./60.)
    check(absf(state.x-.95)<.00001,"95 percent at 250ms")
    var variable=Vector2.ZERO
    for dt in [.01,.025,.015,.07,.04,.09]: variable=Rig.damp(variable.x,variable.y,1.,dt)
    check(state.distance_to(variable)<.00001,"framerate independent damping")
    var previous=Vector2(90,0)
    for i in range(10001):
        var p=Rig.profile(exp(lerpf(log(10000.),log(.5),float(i)/10000)))
        check(p.x<=previous.x+.00001 and p.y>=previous.y-.00001,"monotonic camera profile")
        previous=p
    print(JSON.stringify({"revision":Rig.REVISION,"ground_cases":count,"max_pick_error_px":max_pick_error,"max_anchor_error_px":max_anchor_pixel_error,"damping_250ms":state.x,"failures":failures}))
    viewport.queue_free()
    quit(0 if failures.is_empty() else 1)
