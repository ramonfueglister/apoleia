extends RefCounted
## Own camera contract. Source/model geography is never changed.
## Perspective since v5: view width is the visible ground width at the focus.
const REVISION = "perspective-diorama-display-v5"
const PERSPECTIVE_FOV = 25.0
const OVERVIEW_FOV = 8.0
# A07: closest view about 80 km of ground (3x closer than 240).
const NEAR_WIDTH = 80.0
const MIN_HEIGHT = -1.0
const MAX_HEIGHT = 9.0
const SETTLE_OMEGA = 18.9755 # (1+w*t)*exp(-w*t)=0.05 at t=0.25 s.
const WIDTHS = [1500.0, 200.0, 20.0, 5.0]
const PITCHES = [90.0, 65.0, 45.0, 35.2643897]
const RELIEFS = [0.0, 0.45, 0.88, 1.0]

static func profile(width: float, overview_width: float=7606.0) -> Vector2:
    # The regional reference is a continental diorama, not the outermost flat
    # endpoint. Width anchors are own render-profile choices, not engine parity.
    var regional_width=3400.0
    if width<=regional_width: return Vector2(35.2643897,1.0)
    if width>=overview_width: return Vector2(90.0,0.0)
    var t=clampf(log(overview_width/width)/log(overview_width/regional_width),0.0,1.0)
    t=t*t*(3.0-2.0*t)
    return Vector2(lerpf(90.0,35.2643897,t),t)

static func damp(value: float, velocity: float, goal: float, delta: float) -> Vector2:
    var offset = value-goal
    var impulse = velocity+SETTLE_OMEGA*offset
    var decay = exp(-SETTLE_OMEGA*delta)
    return Vector2(goal+(offset+impulse*delta)*decay,(velocity-SETTLE_OMEGA*impulse*delta)*decay)

static func finish_after_final_frame(callback: Callable) -> void:
    if DisplayServer.get_name()=="headless":
        callback.call_deferred()
    else:
        # Let the normal frame submit camera, clipping and material updates
        # together. A synchronous force_draw from inside _process can render
        # the new shallow end frustum against the preceding camera transform.
        RenderingServer.frame_post_draw.connect(callback,CONNECT_ONE_SHOT)

static func footprint_offsets(width: float, aspect: float, pitch: float, relief: float, focus_height: float, height_range: Vector2=Vector2(MIN_HEIGHT,MAX_HEIGHT)) -> Rect2:
    # All intersections of four orthographic corner rays with the conservative
    # height interval. Thus every intervening heightfield point is contained.
    var angle = deg_to_rad(pitch)
    var half_depth = width/(2.0*aspect*sin(angle))
    var low_shift = (height_range.x*relief-focus_height)/tan(angle)
    var high_shift = (height_range.y*relief-focus_height)/tan(angle)
    return Rect2(Vector2(-width*0.5,-half_depth+low_shift),Vector2(width,2.0*half_depth+high_shift-low_shift))

static func target_limits(core: Rect2, context: Rect2, footprint: Rect2, freedom: float) -> Rect2:
    var minimum = context.position-footprint.position
    var maximum = context.end-footprint.end
    var opening = core.size*0.5*clampf(freedom,0.0,1.0)
    minimum = minimum.max(core.get_center()-opening)
    maximum = maximum.min(core.get_center()+opening)
    # Insufficient data coverage is reported by the caller, never shrunk/cropped.
    return Rect2(minimum,maximum-minimum)

static func pick(camera: Camera3D, pixel: Vector2, height: Callable, relief: float, height_interval: Vector2=Vector2(MIN_HEIGHT,MAX_HEIGHT)) -> Vector2:
    var ray = camera.project_ray_normal(pixel)
    var origin = camera.project_ray_origin(pixel)
    var a = (height_interval.y*relief-origin.y)/ray.y
    var b = (height_interval.x*relief-origin.y)/ray.y
    for i in range(42):
        var middle = (a+b)*0.5
        var p = origin+ray*middle
        if p.y > float(height.call(Vector2(p.x,p.z))): a=middle
        else: b=middle
    var p = origin+ray*((a+b)*0.5)
    return Vector2(p.x,p.z)

static func anchored_target(anchor: Vector2, pixel: Vector2, viewport: Vector2, width: float, pitch: float, height: Callable, initial: Vector2, height_interval: Vector2=Vector2(MIN_HEIGHT,MAX_HEIGHT)) -> Vector2:
    var angle = deg_to_rad(pitch)
    var screen_offset = (pixel-viewport*0.5)*(width/viewport.x)
    var anchor_height = float(height.call(anchor))
    var result = initial
    result.x = anchor.x-screen_offset.x
    # Solve the implicit terrain focus with a bounded root instead of fixed
    # point iteration, which can diverge on slopes steeper than the camera.
    var low=anchor.y-screen_offset.y/sin(angle)-(anchor_height-height_interval.x)/tan(angle)
    var high=anchor.y-screen_offset.y/sin(angle)-(anchor_height-height_interval.y)/tan(angle)
    for i in range(48):
        var middle=(low+high)*0.5
        result.y=middle
        var residual=(anchor.y-middle)*sin(angle)-(anchor_height-float(height.call(result)))*cos(angle)-screen_offset.y
        if absf(residual)<maxf(width/viewport.x*0.01,0.0000001): break
        if residual>0: low=middle
        else: high=middle
    return result

# Vertical field of view: the regional/near views use a narrow perspective,
# the flat overview narrows further so the map reads cartographic.
static func perspective_fov(relief: float) -> float:
    var t=clampf(relief,0.0,1.0)
    return lerpf(OVERVIEW_FOV,PERSPECTIVE_FOV,t*t*(3.0-2.0*t))

# Focus distance at which the visible ground width at the focus is `width`.
static func perspective_distance(width: float, aspect: float, fov_degrees: float) -> float:
    return width/(2.0*aspect*tan(deg_to_rad(fov_degrees)*0.5))

# Ground footprint (offsets from the target) of the four perspective corner
# rays intersected with the conservative height interval; rays at or above the
# horizon are clamped to a long distance.
static func perspective_footprint_offsets(width: float, aspect: float, pitch: float, fov_degrees: float, relief: float, focus_height: float, height_range: Vector2=Vector2(MIN_HEIGHT,MAX_HEIGHT)) -> Rect2:
    var angle=deg_to_rad(pitch)
    var distance=perspective_distance(width,aspect,fov_degrees)
    var back=Vector3(0,sin(angle),cos(angle));var up=Vector3(0,cos(angle),-sin(angle))
    var position=back*distance+Vector3(0,focus_height,0)
    var tv=tan(deg_to_rad(fov_degrees)*0.5);var th=tv*aspect
    var low=Vector2(INF,INF);var high=Vector2(-INF,-INF)
    for sx in [-1.0,1.0]:
        for sy in [-1.0,1.0]:
            var direction=(Vector3.RIGHT*sx*th+up*sy*tv-back).normalized()
            for plane in [height_range.x*relief,height_range.y*relief]:
                var t=distance*20.0
                if direction.y< -0.0001:t=minf((plane-position.y)/direction.y,distance*20.0)
                var p=position+direction*maxf(t,0.0)
                low=low.min(Vector2(p.x,p.z));high=high.max(Vector2(p.x,p.z))
    return Rect2(low,high-low)

# Target keeping `anchor` under `pixel`. place(t) positions the camera for
# target t, pick_at(pixel) returns the ground point under the pixel. A camera
# translation moves the picked point by the same amount up to terrain height,
# so fixed-point passes converge.
static func solve_anchor(anchor: Vector2, pixel: Vector2, initial: Vector2, place: Callable, pick_at: Callable, _step: float=0.0) -> Vector2:
    var t=initial
    for iteration in range(5):
        place.call(t)
        var picked=Vector2(pick_at.call(pixel))
        if not picked.is_finite():break
        t+=anchor-picked
    return t
