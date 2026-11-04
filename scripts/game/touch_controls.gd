class_name TouchControls
extends CanvasLayer
## On-screen controls for phones and tablets (shown on mobile builds, or on desktop
## with the --touch command-line argument for testing).
##   Left half:  a floating move stick (appears under your thumb); pushed all the way
##               it also sprints.
##   Right half: swipe to look around.
##   Buttons:    punch, kick, grab/throw, jump; pause and skills at the top; restart
##               and character at the end of a session.
## Buttons press the same input actions as the keyboard, so the game code doesn't change.

const TEXT := Color(1.0, 0.96, 0.88)
const GOLD := Color(1.0, 0.78, 0.25)
const STICK_RADIUS := 110.0
const LOOK_SPEED := 0.0055

var game: Node

var _root: Control
var _buttons: Array[Dictionary] = []    # {"rect", "action", "node", "finger", "when"}
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_finger := -1
var _stick_base: Control
var _stick_knob: Control


static func wanted() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")


func _ready() -> void:
	layer = 4
	# Keeps seeing fingers lift while a menu has the game paused (no stuck buttons).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_stick_base = _circle(STICK_RADIUS, Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.35))
	_stick_knob = _circle(48.0, Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.6))
	_stick_base.visible = false
	_stick_knob.visible = false
	_root.add_child(_stick_base)
	_root.add_child(_stick_knob)
	# Bottom right action cluster (offsets from the bottom-right corner).
	_add_button("PUNCH", "punch", Vector2(-150, -150), 78.0, "play")
	_add_button("KICK", "kick", Vector2(-300, -110), 58.0, "play")
	_add_button("GRAB", "grab", Vector2(-120, -320), 58.0, "play")
	_add_button("JUMP", "jump", Vector2(-280, -260), 50.0, "play")
	# Top right menu buttons.
	_add_button("II", "ui_cancel", Vector2(-70, 0), 40.0, "play", true)
	_add_button("SKILLS", "skills", Vector2(-190, 0), 40.0, "play", true)
	# End of session.
	_add_button("RESTART", "restart", Vector2(-170, -150), 70.0, "over")
	_add_button("CHARACTER", "change_character", Vector2(-350, -150), 70.0, "over")
	get_viewport().size_changed.connect(_layout)
	_layout()


func _circle(radius: float, fill: Color, border: Color) -> Panel:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(int(radius))
	p.add_theme_stylebox_override("panel", s)
	p.size = Vector2.ONE * radius * 2.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _add_button(text: String, action: String, offset: Vector2, radius: float, when: String, top := false) -> void:
	var node := _circle(radius, Color(0.06, 0.03, 0.02, 0.55), Color(GOLD, 0.8))
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", int(clampf(radius * 0.36, 15, 26)))
	label.add_theme_color_override("font_color", TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	_root.add_child(node)
	_buttons.append({"node": node, "action": action, "offset": offset, "radius": radius,
		"top": top, "when": when, "finger": -1})


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	# Scale everything for the screen (designed for 1080 px tall).
	var k := clampf(size.y / 1080.0, 0.6, 1.6) * 1.15
	for b in _buttons:
		var r: float = b.radius * k
		var corner := Vector2(size.x, 30.0 * k + r) if b.top else size
		var center: Vector2 = corner + (b.offset as Vector2) * k
		var node: Control = b.node
		node.size = Vector2.ONE * r * 2.0
		node.position = center - Vector2.ONE * r
		(node.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(int(r))
		b["center"] = center
		b["r"] = r


func _process(_delta: float) -> void:
	var state := _state()
	for b in _buttons:
		var show: bool = state == b.when
		(b.node as Control).visible = show
		if not show and b.finger >= 0:
			_release(b)
	if state != "play" and _stick_finger >= 0:
		_end_stick()
	visible = state != "none"


## "play" during a session, "over" on the results card, "none" otherwise (select
## screen, menus open; their own buttons take taps then).
func _state() -> String:
	if game == null or game.get("player") == null or get_tree().paused:
		return "none"
	if game.get("over"):
		return "over"
	return "play"


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		_touch_up((event as InputEventScreenTouch).index)
		return
	if _state() == "none":
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			_move_stick(d.position)
			get_viewport().set_input_as_handled()
		elif d.index == _look_finger:
			var p = game.get("player")
			if p != null:
				p.look(d.relative * LOOK_SPEED * (1080.0 / get_viewport().get_visible_rect().size.y))
			get_viewport().set_input_as_handled()


func _touch_down(finger: int, pos: Vector2) -> void:
	for b in _buttons:
		if (b.node as Control).visible and pos.distance_to(b.center) <= b.r * 1.15:
			b.finger = finger
			if b.action == "ui_cancel" or b.action == "skills":
				# Menus open from input events, not polling: send one tap.
				for down in [true, false]:
					var ev := InputEventAction.new()
					ev.action = b.action
					ev.pressed = down
					Input.parse_input_event(ev)
			else:
				Input.action_press(b.action)
			(b.node as Control).modulate = Color(1.4, 1.3, 1.0)
			get_viewport().set_input_as_handled()
			return
	if _state() != "play":
		return
	var size := get_viewport().get_visible_rect().size
	if pos.x < size.x * 0.45 and _stick_finger < 0:
		_stick_finger = finger
		_stick_origin = pos
		_stick_base.visible = true
		_stick_knob.visible = true
		_move_stick(pos)
		get_viewport().set_input_as_handled()
	elif pos.x >= size.x * 0.45 and _look_finger < 0:
		_look_finger = finger
		get_viewport().set_input_as_handled()


func _touch_up(finger: int) -> void:
	for b in _buttons:
		if b.finger == finger:
			_release(b)
	if finger == _stick_finger:
		_end_stick()
	if finger == _look_finger:
		_look_finger = -1


func _release(b: Dictionary) -> void:
	b.finger = -1
	if b.action != "ui_cancel" and b.action != "skills":
		Input.action_release(b.action)
	(b.node as Control).modulate = Color.WHITE


func _move_stick(pos: Vector2) -> void:
	var v := pos - _stick_origin
	if v.length() > STICK_RADIUS:
		# Drag the base along so the stick never "runs out".
		_stick_origin = pos - v.normalized() * STICK_RADIUS
		v = v.normalized() * STICK_RADIUS
	_stick_vec = v / STICK_RADIUS
	_stick_base.position = _stick_origin - _stick_base.size * 0.5
	_stick_knob.position = _stick_origin + v - _stick_knob.size * 0.5
	_set_axis("move_left", maxf(0.0, -_stick_vec.x))
	_set_axis("move_right", maxf(0.0, _stick_vec.x))
	_set_axis("move_forward", maxf(0.0, -_stick_vec.y))
	_set_axis("move_back", maxf(0.0, _stick_vec.y))
	if _stick_vec.length() > 0.92:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func _set_axis(action: String, strength: float) -> void:
	if strength > 0.08:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _end_stick() -> void:
	_stick_finger = -1
	_stick_vec = Vector2.ZERO
	_stick_base.visible = false
	_stick_knob.visible = false
	for a in ["move_left", "move_right", "move_forward", "move_back", "sprint"]:
		Input.action_release(a)
