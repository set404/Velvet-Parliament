class_name CharacterSelect
extends Node3D
## Pre-game character pick, shown inside the chamber before the session starts.
## The candidate stands on the floor (same body, animation and skin as in play) and turns
## slowly; drag with the mouse to spin them yourself.
## A / D or arrows (or the buttons) browse, Enter / Space / the button takes the seat.
## The team panel on the left sets how many teams there are, how many members each has,
## their names, and which one the player joins (W / S cycles it); see TeamSetup.

signal chosen(path: String)

const TEXT := Color(1.0, 0.96, 0.88)
const GOLD := Color(1.0, 0.78, 0.25)

## Where the candidate stands (feet) in the chamber.
var stand_at := Vector3(0.0, 0.05, 3.0)

var _roster: Array[Dictionary] = []
var _index := 0
var _preview: Brawler
var _camera: Camera3D
var _name: Label
var _count: Label
var _spin := 0.0
var _dragging := false
var _done := false
var _career: Label
var _skills: SkillPanel
## Team panel: count / size readouts, one row per possible team (hidden past the count).
var _team_count: Label
var _team_size: Label
var _team_limits: Label
var _team_rows: Array[HBoxContainer] = []
var _team_buttons: Array[Button] = []
var _team_edits: Array[LineEdit] = []
var _team_hint: Label


func _ready() -> void:
	_roster = CharacterRoster.list()
	for i in _roster.size():
		if _roster[i].path == CharacterRoster.selected_path:
			_index = i
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera = Camera3D.new()
	_camera.fov = 42.0
	add_child(_camera)
	# Aimed below the waist so the body sits above the name panel at the bottom.
	# Just in front of the tribune, aimed low so the body sits above the name panel.
	_camera.global_position = stand_at + Vector3(0.0, 1.05, -4.0)
	_camera.look_at(stand_at + Vector3(0.0, 0.6, 0.0))
	_camera.make_current()
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.75)
	key.light_energy = 1.6
	key.omni_range = 5.0
	key.shadow_enabled = false
	add_child(key)
	key.global_position = stand_at + Vector3(-1.2, 2.2, -1.6)
	_build_ui()
	_show(_index)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var title := _label(root, 34, 16.0, TEXT)
	title.text = "CHOOSE YOUR MEMBER"
	_label(root, 15, 62.0, GOLD).text = "The chamber is in session. Who throws the first punch?"
	_career = _label(root, 15, 86.0, TEXT)
	_update_career()

	var bar := VBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -330
	bar.offset_right = 330
	bar.offset_top = -210
	bar.offset_bottom = -30
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 12)
	root.add_child(bar)

	_build_team_panel(root)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)
	var prev := _button("◀", 26)
	prev.custom_minimum_size = Vector2(64, 64)
	prev.pressed.connect(func() -> void: _step(-1))
	row.add_child(prev)
	var names := VBoxContainer.new()
	names.custom_minimum_size = Vector2(440, 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(names)
	_name = _plain_label(34, TEXT)
	names.add_child(_name)
	_count = _plain_label(16, GOLD)
	names.add_child(_count)
	var next := _button("▶", 26)
	next.custom_minimum_size = Vector2(64, 64)
	next.pressed.connect(func() -> void: _step(1))
	row.add_child(next)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	bar.add_child(buttons)
	var play := _button("TAKE YOUR SEAT", 24)
	play.custom_minimum_size = Vector2(320, 56)
	play.pressed.connect(_confirm)
	buttons.add_child(play)
	var skills := _button("SKILLS", 20)
	skills.custom_minimum_size = Vector2(140, 56)
	skills.pressed.connect(_open_skills)
	buttons.add_child(skills)
	var hint := _plain_label(14, TEXT)
	hint.text = "Tap ◀ ▶ to browse · drag to turn" if TouchControls.wanted() else "A / D or ← / → browse · W / S team · drag to turn · Tab skills · Enter to play"
	hint.modulate.a = 0.75
	bar.add_child(hint)
	play.grab_focus.call_deferred()


func _label(parent: Control, size: int, top: float, color: Color) -> Label:
	var l := _plain_label(size, color)
	l.anchor_right = 1.0
	l.offset_top = top
	l.offset_bottom = top + size * 1.5
	parent.add_child(l)
	return l


func _plain_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.03, 0.02, 0.85 if state != "hover" else 0.95)
		style.border_color = GOLD if state in ["hover", "focus", "pressed"] else Color(GOLD, 0.45)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		b.add_theme_stylebox_override(state, style)
	return b


func _update_career() -> void:
	Progression.ensure_loaded()
	var pts := Progression.points
	_career.text = "Level %d   ·   Strength %d%s" % [Progression.level, Progression.get_skill("strength"),
		("   ·   %d skill point%s to spend" % [pts, "" if pts == 1 else "s"]) if pts > 0 else ""]
	if Progression.converted:
		_career.text += "\nSkills were reset for the new progression rules; your XP was kept."


func _open_skills() -> void:
	if _skills != null or _done:
		return
	_skills = SkillPanel.new()
	_skills.closed.connect(func() -> void:
		_skills = null
		_update_career())
	add_child.call_deferred(_skills)


func _unhandled_input(event: InputEvent) -> void:
	if _done or _skills != null:
		return
	if event.is_action_pressed("skills"):
		get_viewport().set_input_as_handled()
		_open_skills()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_release_name_focus()
	elif event is InputEventMouseMotion and _dragging:
		_spin = 0.0
		_preview.rotation.y += (event as InputEventMouseMotion).relative.x * 0.01
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_step(1)
	elif event.is_action_pressed("move_forward") or event.is_action_pressed("ui_up") \
			or event.is_action_pressed("move_back") or event.is_action_pressed("ui_down"):
		var up := event.is_action_pressed("move_forward") or event.is_action_pressed("ui_up")
		_set_team(wrapi(TeamSetup.player_team + (-1 if up else 1), 0, TeamSetup.count))
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("jump"):
		_confirm()


func _process(delta: float) -> void:
	if _preview == null:
		return
	if not _dragging:
		_spin = minf(_spin + delta, 1.0)
		_preview.rotation.y += delta * 0.5 * _spin


func _step(dir: int) -> void:
	if _done or _roster.size() < 2:
		return
	_show(wrapi(_index + dir, 0, _roster.size()))


func _show(i: int) -> void:
	_index = i
	var entry := _roster[i]
	_name.text = entry.name
	_count.text = "%d / %d" % [i + 1, _roster.size()]
	var facing := _preview.rotation.y if _preview else 0.0
	if _preview:
		_preview.queue_free()
	_preview = Brawler.new()
	# The turntable rotates every frame, so skip physics interpolation for it.
	_preview.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	CharacterRoster.dress(_preview, entry.path)
	_preview.position = stand_at
	_preview.rotation.y = facing
	_preview.gesturing = true
	add_child(_preview)
	_preview.remove_from_group("brawlers")


# --- Teams ---------------------------------------------------------------------

func _build_team_panel(root: Control) -> void:
	TeamSetup.ensure_loaded()
	var frame := PanelContainer.new()
	frame.anchor_top = 0.0
	frame.anchor_bottom = 0.0
	frame.offset_left = 16
	frame.offset_right = 268
	frame.offset_top = 114
	# Below the title lines and left of the name bar, even with all six teams listed.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.03, 0.02, 0.78)
	bg.border_color = Color(GOLD, 0.45)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", bg)
	root.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	frame.add_child(box)

	var head := _plain_label(17, GOLD)
	head.text = "TEAMS"
	box.add_child(head)
	_team_count = _stepper(box, "Teams", func(d: int) -> void:
		TeamSetup.set_count(TeamSetup.count + d)
		_teams_changed())
	_team_size = _stepper(box, "Members", func(d: int) -> void:
		TeamSetup.set_members(TeamSetup.members + d)
		_teams_changed(), true)
	_team_limits = _plain_label(11, TEXT)
	_team_limits.modulate.a = 0.7
	box.add_child(_team_limits)

	for i in TeamSetup.MAX_TEAMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var join := _button("JOIN", 12)
		join.custom_minimum_size = Vector2(58, 32)
		join.toggle_mode = true
		# Kept out of keyboard focus so Enter always takes the seat (W / S cycle teams).
		join.focus_mode = Control.FOCUS_NONE
		var team := i
		join.pressed.connect(func() -> void: _set_team(team))
		row.add_child(join)
		var edit := LineEdit.new()
		edit.text = TeamSetup.team_name(i)
		edit.max_length = TeamSetup.NAME_MAX_LENGTH
		edit.placeholder_text = String(TeamSetup.style(i).name)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.add_theme_font_size_override("font_size", 14)
		edit.add_theme_color_override("font_color", TEXT)
		var accent: Color = TeamSetup.style(i).accent
		var es := StyleBoxFlat.new()
		es.bg_color = Color(0.02, 0.01, 0.01, 0.8)
		es.border_color = accent
		es.border_width_left = 6
		es.border_width_bottom = 1
		es.set_corner_radius_all(4)
		es.set_content_margin_all(4)
		es.content_margin_left = 12
		edit.add_theme_stylebox_override("normal", es)
		edit.add_theme_stylebox_override("focus", es)
		edit.text_changed.connect(func(t: String) -> void:
			TeamSetup.rename_team(team, t)
			_update_team_hint())
		# Leaving the field tidies the name (empty -> the default) and hands Enter back.
		var settle := func() -> void:
			edit.text = TeamSetup.team_name(team)
			_update_team_hint()
		edit.text_submitted.connect(func(_t: String) -> void:
			edit.release_focus())
		edit.focus_exited.connect(settle)
		row.add_child(edit)
		_team_rows.append(row)
		_team_buttons.append(join)
		_team_edits.append(edit)

	_team_hint = _plain_label(12, GOLD)
	_team_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_team_hint.custom_minimum_size = Vector2(228, 0)
	box.add_child(_team_hint)
	_refresh_teams()


## A "Label  ◀◀ ◀ value ▶ ▶▶" row; big steps (±5) only when `big` is set.
func _stepper(parent: Control, title: String, step: Callable, big := false) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var l := _plain_label(14, TEXT)
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var value := _plain_label(16, GOLD)
	value.custom_minimum_size = Vector2(28, 0)
	if big:
		row.add_child(_step_button("◀◀", step, -5))
	row.add_child(_step_button("◀", step, -1))
	row.add_child(value)
	row.add_child(_step_button("▶", step, 1))
	if big:
		row.add_child(_step_button("▶▶", step, 5))
	return value


func _step_button(text: String, step: Callable, d: int) -> Button:
	var b := _button(text, 11)
	b.custom_minimum_size = Vector2(30, 28)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		if not _done:
			step.call(d))
	return b


func _teams_changed() -> void:
	_refresh_teams()
	TeamSetup.save()
	var game := get_parent()
	if game != null and game.has_method("preview_teams"):
		game.preview_teams()


func _set_team(team: int) -> void:
	if _done:
		return
	TeamSetup.player_team = team
	TeamSetup.clamp_all()
	_teams_changed()


func _refresh_teams() -> void:
	_team_count.text = str(TeamSetup.count)
	_team_size.text = str(TeamSetup.members)
	_team_limits.text = "%d–%d teams · %d–%d members each\n(you count as one of yours)" % [TeamSetup.MIN_TEAMS,
		TeamSetup.MAX_TEAMS, TeamSetup.MIN_MEMBERS, TeamSetup.max_members()]
	for i in _team_rows.size():
		_team_rows[i].visible = i < TeamSetup.count
		var on := i == TeamSetup.player_team
		var b := _team_buttons[i]
		b.set_pressed_no_signal(on)
		b.text = "YOU" if on else "JOIN"
		var accent: Color = TeamSetup.style(i).accent
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
			style.bg_color = Color(accent.darkened(0.5), 0.95) if on else Color(0.06, 0.03, 0.02, 0.85)
			style.border_color = accent if on else Color(accent, 0.4)
			style.set_border_width_all(3 if on else 2)
			b.add_theme_stylebox_override(state, style)
		b.add_theme_color_override("font_color", TEXT if on else Color(TEXT, 0.65))
		b.add_theme_color_override("font_pressed_color", TEXT)
	_update_team_hint()


func _update_team_hint() -> void:
	var others := TeamSetup.rivals_of(TeamSetup.player_team)
	_team_hint.text = "You join %s. %s will fight you, and only they will feel your fists." % [
		TeamSetup.team_name(TeamSetup.player_team), TeamSetup.list_names(others)]


func _release_name_focus() -> void:
	for e in _team_edits:
		if e.has_focus():
			e.release_focus()


func _confirm() -> void:
	if _done or _skills != null:
		return
	_done = true
	var path: String = _roster[_index].path
	CharacterRoster.selected_path = path
	CharacterRoster.has_selected = true
	chosen.emit(path)
	queue_free()
