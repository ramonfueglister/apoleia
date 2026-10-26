extends SceneTree
## CPU-only actual direct-API provider. Supervisor owns complete publication.
## Probe <=16 cells; complete mode uses exact full-region suffix for restart.
var config:Dictionary
var repository=""
var output=""
var canonical:RefCounted
var surface:RefCounted
var style:Script
var context:RefCounted
var binding:Dictionary
var frozen:Dictionary={}
var is_probe=true
func _initialize()->void:call_deferred("run")
func emit(value:Dictionary)->void:print(JSON.stringify(value,"",true,true))
func fail(reason:String)->void:push_error(reason);emit({"event":"provider_error","reason":reason});quit(2)
func frozen_valid()->bool:
    for path in frozen:
        if FileAccess.get_sha256(repository.path_join(path))!=str(frozen[path]):return false
    return true
func wait_ack(name:String)->bool:
    var started=Time.get_ticks_msec()
    while not FileAccess.file_exists(output.path_join("acks").path_join(name)):
        if Time.get_ticks_msec()-started>60000:return false
        await create_timer(.025).timeout
    return true
func write_bytes(path:String,bytes:PackedByteArray)->bool:
    if FileAccess.file_exists(path):return false
    var file=FileAccess.open(path,FileAccess.WRITE)
    if file==null:return false
    file.store_buffer(bytes);file.flush();file.close();return true
func hash_bytes(bytes:PackedByteArray)->String:
    if bytes.is_empty():return "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    var hashing=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(bytes);return hashing.finish().hex_encode()
func exact_json_values(left:Variant,right:Variant)->bool:
    if typeof(left) in [TYPE_INT,TYPE_FLOAT]:
        if not typeof(right) in [TYPE_INT,TYPE_FLOAT]:return false
        var a=PackedByteArray();a.resize(8);a.encode_double(0,float(left))
        var b=PackedByteArray();b.resize(8);b.encode_double(0,float(right))
        return a==b
    if typeof(left)!=typeof(right):return false
    if left is Dictionary:
        if left.size()!=right.size():return false
        for key in left:
            if not right.has(key) or not exact_json_values(left[key],right[key]):return false
        return true
    if left is Array:
        if left.size()!=right.size():return false
        for i in range(left.size()):
            if not exact_json_values(left[i],right[i]):return false
        return true
    return left==right
func run()->void:
    var args=OS.get_cmdline_user_args()
    if args.size()!=2 or args[0]!="--config":fail("expected --config path");return
    var parsed=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
    if not parsed is Dictionary:fail("config JSON");return
    config=parsed
    is_probe=config.get("mode","")=="incomplete-probe"
    if not is_probe and config.get("mode","")!="complete-build":fail("unknown build mode");return
    if not config.get("cells",[]) is Array:fail("cell array required");return
    var resume_from=int(config.get("resume_from_ordinal",0))
    if is_probe:
        if config.cells.is_empty() or config.cells.size()>16 or resume_from!=0:fail("bounded explicit probe required");return
    elif resume_from<0 or resume_from>3116 or config.cells.size()!=3116-resume_from:fail("complete coverage suffix required");return
    repository=str(config.repository_root);output=str(config.output);frozen=config.frozen_files
    if not frozen_valid():fail("input freeze mismatch before configure");return
    var visited={}
    for ordinal in range(config.cells.size()):
        var cell=config.cells[ordinal]
        if not is_probe:
            var full_ordinal=ordinal+resume_from
            if int(cell[0])!= -42+full_ordinal%82 or int(cell[1])!= -18+int(full_ordinal/82):fail("complete cell order/coverage");return
        if cell.size()!=2 or int(cell[0])< -42 or int(cell[0])>=40 or int(cell[1])< -18 or int(cell[1])>=20:fail("invalid full-region cell");return
        var key=str(int(cell[0]))+"_"+str(int(cell[1]))
        if visited.has(key):fail("duplicate probe cell");return
        visited[key]=true
    var product=JSON.parse_string(FileAccess.get_file_as_string("res://renderer-binding.json"))
    if FileAccess.get_sha256(repository.path_join(product.source.path))!=product.source.sha256:fail("source manifest mismatch");return
    var start=Time.get_ticks_usec()
    canonical=load("res://scripts/canonical_domains_v2.gd").new()
    if not canonical.configure(repository,repository.path_join(product.upload.path),product.source.sha256,product.upload.sha256):fail("canonical configure rejected");return
    var source_usec=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
    if FileAccess.get_sha256(repository.path_join(product.atlas.path))!=product.atlas.sha256:fail("atlas manifest mismatch");return
    surface=load("res://scripts/fixed_display_surface.gd").new()
    if not surface.configure(repository.path_join(product.atlas.path),product.source.sha256):fail("surface configure rejected");return
    var surface_usec=Time.get_ticks_usec()-start
    style=load("res://scripts/style/landscape_style.gd")
    var policy:Dictionary=style.diorama_representation_policy()
    var display_scale=float(style.landform_vertical_scale(3400.0))
    # Only this tiny shared template is prepared; no expanded forest vertices.
    var templates:Array=load("res://scripts/cache/compact_forest_poses.gd").variants(style.prepare_diorama_crown_arrays())
    var snapshot={"canonical":canonical,"surface":surface,"style":style,"policy":policy,"templates":templates,"world_min":canonical.domains.context.height.rect.position,"world_size":canonical.domains.context.height.rect.size,"display_height_scale":display_scale,"source_manifest_sha256":product.source.sha256,"projection_sha256":FileAccess.get_sha256(repository.path_join("data/projection.json"))}
    var binding_script=load("res://scripts/cache/fixed_forest_layout.gd")
    if binding_script==null:fail("shared layout binding API unavailable");return
    binding=binding_script.binding(snapshot)
    if binding.is_empty():fail("shared layout binding rejected snapshot");return
    context=load("res://scripts/cache/fixed_forest_build_context.gd").new()
    var context_snapshot=snapshot.duplicate();context_snapshot["crown_arrays"]=[];context_snapshot["representation"]="expanded";context_snapshot["identity"]=binding
    if not context.configure(context_snapshot):fail("actual Context configure rejected");return
    emit({"event":"warmup_ready","pid":OS.get_process_id(),"binding":binding,"source_configure_usec":source_usec,"surface_configure_usec":surface_usec,"source_field_payload_bytes":source_resident_bytes(),"surface_payload_bytes":surface.bytes.size(),"context_classes_rect":str(canonical.domains.context.classes.rect),"context_height_rect":str(canonical.domains.context.height.rect),"provider_sha256":FileAccess.get_sha256(get_script().resource_path)})
    if not (await wait_ack("warmup")):fail("warmup acknowledgement timeout");return
    var canonical_binding_raw=FileAccess.get_file_as_bytes(output.path_join("binding.json"))
    var bound_sha=hash_bytes(canonical_binding_raw)
    var check_binding=JSON.parse_string(canonical_binding_raw.get_string_from_utf8())
    # Python canonicalization may use escaped JSON strings; compare semantic values.
    var normalized_expected=JSON.parse_string(JSON.stringify(binding,"",true,true))
    var normalized_received=JSON.parse_string(JSON.stringify(check_binding,"",true,true))
    if JSON.stringify(normalized_received,"",true,true)!=JSON.stringify(normalized_expected,"",true,true):fail("supervisor binding semantic mismatch");return
    for ordinal in range(config.cells.size()):
        if not frozen_valid():fail("input freeze changed before cell");return
        var cell=Vector2i(config.cells[ordinal][0],config.cells[ordinal][1])
        var folder=output.path_join("cells").path_join("."+str(cell.x)+"_"+str(cell.y)+".tmp")
        if DirAccess.dir_exists_absolute(folder):fail("partial spool already exists");return
        DirAccess.make_dir_recursive_absolute(folder)
        var sampler=context.request_samples(0)
        var started=Time.get_ticks_usec()
        var dto:Dictionary=style.build_diorama_forest_records(Vector2(cell)*128.,Vector2.ONE*128.,Callable(sampler,"sample"),Callable(sampler,"land"),Callable(sampler,"forest"),{"surface_grid_origin":surface.world_min,"surface_grid_spacing":surface.spacing,"forest_geometry_mode":str(policy.forest_geometry_mode)})
        var build_usec=Time.get_ticks_usec()-started
        if dto.get("cancelled",false) or dto.has("error") or dto.records.size()>1369:fail("direct API failed/bounded count exceeded");return
        var rows=PackedByteArray();rows.resize(dto.records.size()*64)
        var oracle=PackedByteArray()
        if is_probe:oracle.resize(dto.records.size()*72)
        var roundtrip=true
        for i in range(dto.records.size()):
            var record:Array=dto.records[i]
            if record.size()!=10 or float(record[7])!=0.:fail("invalid stride0 direct record");return
            rows.encode_s32(i*64,int(record[0]));rows.encode_s32(i*64+4,int(record[1]))
            if is_probe:
                oracle.encode_s32(i*72,int(record[0]));oracle.encode_s32(i*72+4,int(record[1]))
            var field=0
            for j in range(2,10):
                if is_probe:oracle.encode_double(i*72+8+(j-2)*8,float(record[j]))
                if j==7:continue
                rows.encode_double(i*64+8+field*8,float(record[j]));field+=1
            var restored=[rows.decode_s32(i*64),rows.decode_s32(i*64+4),rows.decode_double(i*64+8),rows.decode_double(i*64+16),rows.decode_double(i*64+24),rows.decode_double(i*64+32),rows.decode_double(i*64+40),0.,rows.decode_double(i*64+48),rows.decode_double(i*64+56)]
            roundtrip=roundtrip and var_to_bytes(restored)==var_to_bytes(record)
        var metadata={"legacy_ground_support":0,"resource_name":dto.resource_name,"legacy_metadata":dto.metadata}
        var metadata_raw=JSON.stringify(metadata,"",true,true).to_utf8_buffer()
        if metadata_raw.size()>4096 or not roundtrip:fail("metadata limit/bitwise engine record roundtrip");return
        var metadata_roundtrip=JSON.parse_string(metadata_raw.get_string_from_utf8())
        if not exact_json_values(metadata,metadata_roundtrip):fail("full-precision metadata binary64 value roundtrip");return
        if not write_bytes(folder.path_join("records.bin"),rows) or not write_bytes(folder.path_join("metadata.json"),metadata_raw):fail("spool write");return
        if is_probe and not write_bytes(folder.path_join("oracle-records.bin"),oracle):fail("probe oracle spool write");return
        if not frozen_valid():fail("input freeze changed during cell");return
        var response={"event":"cell_ready","ordinal":ordinal,"cell":[cell.x,cell.y],"folder":folder,"binding_sha256":bound_sha,"records":{"path":"records.bin","bytes":rows.size(),"count":dto.records.size(),"sha256":hash_bytes(rows)},"oracle_records":{"path":"oracle-records.bin","bytes":oracle.size(),"sha256":hash_bytes(oracle)},"metadata":{"path":"metadata.json","bytes":metadata_raw.size(),"sha256":hash_bytes(metadata_raw)},"build_usec":build_usec,"engine_record_roundtrip_bit_exact":roundtrip,"metadata_full_precision_roundtrip":true,"request_sampling":sampler.counts.duplicate()}
        if not is_probe:response.erase("oracle_records")
        emit(response)
        dto.clear();sampler=null;rows=PackedByteArray();oracle=PackedByteArray()
        if not (await wait_ack("cell_"+str(ordinal))):fail("cell durable acknowledgement timeout");return
        if not is_probe:continue
        # Read the durably published bytes, then compare to a fresh actual API job.
        var final_folder=output.path_join("cells").path_join(str(cell.x)+"_"+str(cell.y))
        var disk_rows=FileAccess.get_file_as_bytes(final_folder.path_join("records.bin"))
        var loaded_records:Array=[]
        for i in range(disk_rows.size()/64):
            loaded_records.append([disk_rows.decode_s32(i*64),disk_rows.decode_s32(i*64+4),disk_rows.decode_double(i*64+8),disk_rows.decode_double(i*64+16),disk_rows.decode_double(i*64+24),disk_rows.decode_double(i*64+32),disk_rows.decode_double(i*64+40),0.,disk_rows.decode_double(i*64+48),disk_rows.decode_double(i*64+56)])
        var replay_sampler=context.request_samples(0)
        var replay_started=Time.get_ticks_usec()
        var replay:Dictionary=style.build_diorama_forest_records(Vector2(cell)*128.,Vector2.ONE*128.,Callable(replay_sampler,"sample"),Callable(replay_sampler,"land"),Callable(replay_sampler,"forest"),{"surface_grid_origin":surface.world_min,"surface_grid_spacing":surface.spacing,"forest_geometry_mode":str(policy.forest_geometry_mode)})
        var replay_usec=Time.get_ticks_usec()-replay_started
        var replay_metadata={"legacy_ground_support":0,"resource_name":replay.resource_name,"legacy_metadata":replay.metadata}
        if var_to_bytes(loaded_records)!=var_to_bytes(replay.records):fail("disk layout differs from fresh direct API records");return
        if FileAccess.get_file_as_bytes(final_folder.path_join("metadata.json"))!=JSON.stringify(replay_metadata,"",true,true).to_utf8_buffer():fail("disk metadata differs from fresh direct API metadata");return
        emit({"event":"cell_verified","ordinal":ordinal,"cell":[cell.x,cell.y],"disk_vs_fresh_direct_records_bit_exact":true,"disk_vs_fresh_direct_metadata_bytes_exact":true,"replay_build_usec":replay_usec})
        loaded_records.clear();replay.clear();replay_sampler=null;disk_rows=PackedByteArray()
    emit({"event":"probe_complete" if is_probe else "generation_complete","cells":config.cells.size(),"resume_from_ordinal":resume_from,"binding_sha256":bound_sha,"coverage":"incomplete-probe" if is_probe else "complete-build-not-published","input_freeze_unchanged":frozen_valid()})
    quit(0)
func source_resident_bytes()->int:
    var bytes=0
    for domain in canonical.domains.values():
        for field in domain.values():bytes+=field.bytes.size()
    return bytes
