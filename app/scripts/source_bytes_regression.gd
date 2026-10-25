extends SceneTree
func _initialize() -> void:
    var scene=load("res://scripts/landscape.gd").new()
    var path=ProjectSettings.globalize_path("res://../data/derived/height-detail.f32")
    scene.native_elevation_bytes=FileAccess.get_file_as_bytes(path)
    scene.elevation_width=13680;scene.elevation_height=8880
    scene.world_min=Vector2.ZERO;scene.world_size=Vector2(13680,8880)
    scene.water_width=1;scene.water_height=1;scene.render_waters=PackedByteArray([0])
    var count=scene.native_elevation_bytes.size()/4
    var indices=[67415109,48098025,87672566]
    for i in range(4096): indices.append(posmod(i*104729,count-13681))
    var negative=0
    for index in indices:
        var original=scene.native_elevation_bytes.slice(index*4,index*4+4).to_float32_array()[0]
        assert(scene._source_height_cell(index)==original)
        if original<0: negative+=1
        var x=mini(index%13680,13678)
        var y=mini(index/13680,8878)
        var point=Vector2(x+0.37109375,y+0.6484375)+Vector2(0.5,0.5)
        var uv=(point/scene.world_size)*Vector2(13680,8880)-Vector2(0.5,0.5)
        x=clampi(int(floor(uv.x)),0,13678);y=clampi(int(floor(uv.y)),0,8878)
        var fx=clampf(uv.x-x,0.0,1.0);var fy=clampf(uv.y-y,0.0,1.0)
        var values=[]
        for offset in [0,1,13680,13681]:
            var at=(y*13680+x+offset)*4
            values.append(scene.native_elevation_bytes.slice(at,at+4).to_float32_array()[0])
        var old_value=lerpf(lerpf(values[0],values[1],fx),lerpf(values[2],values[3],fx),fy)*0.001
        assert(scene._height(point)==old_value)
        var q=[]
        for value in values: q.append(floor((value+8192.0)*4.0+0.5)*0.25-8192.0)
        var gpu_reference=lerpf(lerpf(q[0],q[1],fx),lerpf(q[2],q[3],fx),fy)*0.001
        assert(scene._packed_height(point)==gpu_reference)
    print("PASS4099 bit-exact Float32LE samples and source/packed four-corner-before-bilinear queries including global extrema and ",negative," signed negative samples; one resident native byte buffer")
    scene.camera.free();scene.forest.free();scene.free()
    quit()
