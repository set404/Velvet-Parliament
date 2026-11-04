extends Node3D
## Entry scene: the chamber plus an inspection camera.
## Debug capture: Godot --path . -- --shot=<file.png> [--view=<0-3>]

@onready var camera: OrbitCamera = $Camera


func _ready() -> void:
	var shot := ""
	var view := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--view="):
			view = arg.trim_prefix("--view=").to_int()
	camera.apply_preset(view, true)
	if shot.is_empty():
		_add_help()
	else:
		_capture(shot)


func _add_help() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "VELVET PARLIAMENT · chamber preview\n" \
		+ "Drag: orbit   Middle drag / WASD / Q E: pan   Wheel: zoom\n" \
		+ "1 Public gallery   2 Side gallery   3 Presidium corner   4 Member's seat"
	label.position = Vector2(16, 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	layer.add_child(label)
	add_child(layer)


func _capture(path: String) -> void:
	# Give the noise textures time to generate.
	for i in 180:
		await get_tree().process_frame
	print("PREVIEW fps=", Engine.get_frames_per_second())
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
