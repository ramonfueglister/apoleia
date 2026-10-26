extends RefCounted
## Effective resource identity, not an evidence-only file inventory.
const REVISION="v19-compact-sampling-identity-r4"
const DEPENDENCIES=["source_sampler_sha256","ground_sampler_sha256","sampling_callbacks_sha256","identity_contract_sha256"]
const STRIDES=[0,1,2,4,8,16,32,64,128]
static func effective_binding(geometry_binding:Dictionary,sampling_dependencies:Dictionary)->Dictionary:
    var bound=geometry_binding.duplicate(true)
    var code={}
    for key in DEPENDENCIES:
        var digest=str(sampling_dependencies.get(key,""))
        if digest.length()!=64 or not digest.is_valid_hex_number(false):return {}
        code[key]=digest
    bound["sampling_contract_revision"]=REVISION
    bound["sampling_implementations"]=code
    return bound
static func representation_id(bound:Dictionary)->String:
    if str(bound.get("sampling_contract_revision",""))!=REVISION:return ""
    var dependencies=bound.get("sampling_implementations",{})
    for key in DEPENDENCIES:
        if str(dependencies.get(key,"")).length()!=64:return ""
    return JSON.stringify(bound,"",true,true).sha256_text()
static func support_id(representation:String,stride:int)->String:
    if representation.length()!=64 or not stride in STRIDES:return ""
    return JSON.stringify({"representation":representation,"stride":stride,"ground_contract":"flat_ground_zero" if stride==0 else "rendered_height_same_G_triangle_support_then_displayY","contract_revision":REVISION},"",true,true).sha256_text()
