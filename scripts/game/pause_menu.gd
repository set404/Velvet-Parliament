class_name PauseMenu
extends CanvasLayer
## Esc during a session: freezes the chamber and offers Resume, Skills, Restart,
## Change character and Quit. Esc again (or Resume) carries on.

signal resumed
signal skills_requested
signal restart_requested
signal change_character_requested

const TEXT := Color(1.0, 0.96, 0.88)
const GOLD := Color(1.0, 0.78, 0.25)

var can_change_character := false

var _box: VBoxContainer
var _first: Button
var _confirm_quit := false
var _quit_button: Button


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.03, 0.02, 0.94)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(_box)

	var title := Label.new()
	title.text = "RECESS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", TEXT)
	_box.add_child(title)
	var sub := Label.new()
	sub.text = "The session is suspended."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", GOLD)
	_box.add_child(sub)

	_first = _add("RESUME", _resume)
	_add("SKILLS", func() -> void: skills_requested.emit())
	_add("RESTART SESSION", func() -> void:
		_unpause()
		restart_requested.emit())
	if can_change_character:
		_add("CHARACTER & TEAMS", func() -> void:
			_unpause()
			change_character_requested.emit())
	_quit_button = _add("QUIT GAME", _quit)
	var hint := Label.new()
	hint.text = "Esc to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(TEXT, 0.6))
	_box.add_child(hint)
	_first.grab_focus.call_deferred()


func _add(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.12, 0.07, 0.04, 0.95)
		s.border_color = GOLD if state != "normal" else Color(GOLD, 0.4)
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		s.set_content_margin_all(8)
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(action)
	_box.add_child(b)
	return b


## Hidden while the skills panel is open on top of it.
func set_covered(covered: bool) -> void:
	visible = not covered
	if not covered:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_first.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_resume()


func _resume() -> void:
	_unpause()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()
	queue_free()


func _quit() -> void:
	# A second click confirms, so a stray click doesn't end the game.
	if not _confirm_quit:
		_confirm_quit = true
		_quit_button.text = "CLICK AGAIN TO QUIT"
		return
	Progression.save()
	get_tree().quit()


func _unpause() -> void:
	get_tree().paused = false
