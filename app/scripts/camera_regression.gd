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
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.keep_aspect=Camera3D.KEEP_HEIGHT
    camera.near=.001;camera.far=100000
    scene.add_child(camera)
    var count=0
    var max_pick_error=0.0
    var max_anchor_pixel_error=0.0
    for size in [Vector2i(1440,1080),Vector2i(1728,1080),Vector2i(1920,1080),Vector2i(2520,1080)]:
        viewport.size=size
        for width in [10000.,1500.,700.,200.,75.,20.,5.,.5]:
            var profile=Rig.profile(width)
            var angle=deg_to_rad(profile.x)
            var basis=Basis(Vector3.RIGHT,Vector3(0,cos(angle),-sin(angle)),Vector3(0,sin(angle),cos(angle)))
            camera.size=width/(float(size.x)/size.y)
            var target=Vector2(2265.,2223.)
            var distance=maxf(20.0,width/(float(size.x)/size.y)/maxf(sin(angle),.001)+20.0)
            camera.transform=Transform3D(basis,Vector3(target.x,height(target),target.y)+basis.z*distance)
            var footprint=Rig.footprint_offsets(width,float(size.x)/size.y,profile.x,profile.y,height(target))
            for point in [Vector2(size)*.5,Vector2(size)*Vector2(.15,.20),Vector2(size)*Vector2(.83,.87)]:
                var picked=Rig.pick(camera,point,Callable(self,"height"),1.)
                var projected=camera.unproject_position(Vector3(picked.x,height(picked),picked.y))
                max_pick_error=maxf(max_pick_error,projected.distance_to(point))
                check(projected.distance_to(point)<1.0,"ray reprojection %s %s"%[size,width])
                var anchored=Rig.anchored_target(picked,point+Vector2(73,-91),Vector2(size),width,profile.x,Callable(self,"height"),target)
                camera.transform=Transform3D(basis,Vector3(anchored.x,height(anchored),anchored.y)+basis.z*distance)
                projected=camera.unproject_position(Vector3(picked.x,height(picked),picked.y))
                var error=projected.distance_to(point+Vector2(73,-91))
                max_anchor_pixel_error=maxf(max_anchor_pixel_error,error)
                check(error<1.0,"ground anchor %s %s = %f"%[size,width,error])
                camera.transform=Transform3D(basis,Vector3(target.x,height(target),target.y)+basis.z*distance)
                count+=1
            for corner in [Vector2.ZERO,Vector2(size)*Vector2(1,0),Vector2(size)*Vector2(0,1),Vector2(size)]:
                var ray=camera.project_ray_normal(corner)
                var origin=camera.project_ray_origin(corner)
                for altitude in [Rig.MIN_HEIGHT*profile.y,Rig.MAX_HEIGHT*profile.y]:
                    var p=origin+ray*((altitude-origin.y)/ray.y)
                    var relative=Vector2(p.x,p.z)-target
                    check(relative.x>=footprint.position.x-.05 and relative.x<=footprint.end.x+.05 and relative.y>=footprint.position.y-.05 and relative.y<=footprint.end.y+.05,"full corner footprint")
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
