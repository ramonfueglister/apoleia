extends RefCounted
## Own orthographic camera contract. Source/model geography is never changed.
const REVISION = "orthographic-diorama-display-v4"
const NEAR_WIDTH = 240.0
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
