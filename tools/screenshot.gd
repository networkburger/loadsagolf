extends Node
## Render a scene offscreen at a fixed size and save a PNG, independent of the
## window manager (tiling WMs resize the real window).
##
##   godot res://tools/screenshot.tscn -- --scene=res://scenes/game.tscn \
##       --size=1280x800 --seconds=1.5 --out=/tmp/shot.png [--demo-aim | --demo-win]
##
## --size is in *screen* pixels; the scene is laid out like the real game
## (1024x768 safe area, 'expand' aspect).

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var size_parts: PackedStringArray = args.get("size", "1280x800").split("x")
	var screen := Vector2i(int(size_parts[0]), int(size_parts[1]))
	var seconds := float(args.get("seconds", "1.5"))
	var out: String = args.get("out", "/tmp/shot.png")

	var vp := SubViewport.new()
	vp.size = screen
	# Emulate canvas_items + expand: scale so 1024x768 fits, extra space shows more world.
	var scale := minf(screen.x / 1024.0, screen.y / 768.0)
	vp.size_2d_override = Vector2i(roundi(screen.x / scale), roundi(screen.y / scale))
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var scene: PackedScene = load(args.get("scene", "res://scenes/game.tscn"))
	vp.add_child(scene.instantiate())
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	var err := vp.get_texture().get_image().save_png(out)
	print("saved %s (%s) err=%d" % [out, screen, err])
	get_tree().quit()
