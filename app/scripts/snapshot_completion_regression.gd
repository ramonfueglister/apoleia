extends SceneTree
const CameraRig=preload("res://scripts/landscape_camera.gd")
var completions=0
func _initialize() -> void:
    assert(DisplayServer.get_name()=="headless","This regression is the non-rendering completion path; real GPU proof is separately captured")
    CameraRig.finish_after_final_frame(Callable(self,"completed"))
    call_deferred("verify")
func completed() -> void: completions+=1
func verify() -> void:
    assert(completions==1,"Headless completion must run once without waiting for unavailable post-draw")
    print("PASS static headless snapshot completion without a render frame; GPU static completion separately verified by actual framebuffer capture")
    quit()
