extends SceneTree
func _initialize() -> void:
    var scene=load("res://scripts/landscape.gd").new()
    var press=InputEventMouseButton.new()
    press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=Vector2(800,448)
    assert(scene._pan_delta(press)==Vector2.ZERO)
    var motion=InputEventMouseMotion.new()
    motion.position=Vector2(1200,714.666687)
    assert(scene._pan_delta(motion).is_equal_approx(Vector2(400,266.666687)))
    motion.position+=Vector2(20,30);motion.relative=Vector2(5,7)
    assert(scene._pan_delta(motion)==Vector2(5,7))
    press.pressed=false
    scene._pan_delta(press)
    motion.position+=Vector2(20,30);motion.relative=Vector2.ZERO
    assert(scene._pan_delta(motion)==Vector2.ZERO)
    press.pressed=true;scene._pan_delta(press)
    scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    assert(scene.pan_down_mask==0 and not scene.pan_position_valid)
    print("PASS positional fallback, valid relative not doubled, release and focus reset")
    scene.camera.free()
    scene.forest.free()
    scene.free()
    quit()
