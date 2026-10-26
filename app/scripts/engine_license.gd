extends SceneTree
func _initialize():
    var args=OS.get_cmdline_user_args()
    if args.is_empty(): quit(2); return
    var f=FileAccess.open(args[0],FileAccess.WRITE)
    f.store_string(Engine.get_license_text()+"\n\nThird-party notices embedded in this exact engine:\n"+JSON.stringify(Engine.get_license_info(),"  ")+"\n\n"+JSON.stringify(Engine.get_copyright_info(),"  "))
    quit()
