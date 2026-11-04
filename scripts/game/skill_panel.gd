class_name SkillPanel
extends CanvasLayer
## Spend skill points. Opened with Tab (in the chamber, from the results card, or on the
## character select screen). In play it pauses the game while open.

signal closed

const TEXT := Color(1.0, 0.96, 0.88)
const GOLD := Color(1.0, 0.78, 0.25)
const DIM := Color(1.0, 0.96, 0.88, 0.45)

var pause_game := false

var _header: Label
var _xp_bar: ProgressBar
var _rows := {}
var _refund: Button
var _reset: Button
var _armed := ""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	Progression.ensure_loaded()
	if pause_game:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.03, 0.02, 0.94)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -300
	panel.offset_bottom = 300
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := _label(30, TEXT)
	title.text = "SKILLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_header = _label(17, GOLD)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_header)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(3)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	_xp_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_xp_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for id in Progression.ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		list.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_l := _label(19, TEXT)
		info.add_child(name_l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		var bfill := StyleBoxFlat.new()
		bfill.bg_color = GOLD
		var bbg := StyleBoxFlat.new()
		bbg.bg_color = Color(1, 1, 1, 0.1)
		bar.add_theme_stylebox_override("fill", bfill)
		bar.add_theme_stylebox_override("background", bbg)
		info.add_child(bar)
		var desc := _label(13, DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		var plus := _button("+")
		plus.custom_minimum_size = Vector2(96, 48)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus.add_theme_font_size_override("font_size", 16)
		plus.pressed.connect(_buy.bind(id))
		row.add_child(plus)
		_rows[id] = {"name": name_l, "desc": desc, "plus": plus, "bar": bar}

	var resets := HBoxContainer.new()
	resets.alignment = BoxContainer.ALIGNMENT_CENTER
	resets.add_theme_constant_override("separation", 12)
	box.add_child(resets)
	_refund = _button("REFUND SKILLS")
	_refund.add_theme_font_size_override("font_size", 15)
	_refund.custom_minimum_size = Vector2(230, 40)
	_refund.pressed.connect(_on_refund)
	resets.add_child(_refund)
	_reset = _button("RESET CAREER")
	_reset.add_theme_font_size_override("font_size", 15)
	_reset.custom_minimum_size = Vector2(230, 40)
	_reset.pressed.connect(_on_reset)
	resets.add_child(_reset)

	var close := _button("DONE  (Tab)")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(220, 46)
	close.pressed.connect(close_panel)
	box.add_child(close)
	_refresh()


func _refresh() -> void:
	var prog := Progression.level_progress()
	_header.text = "Level %d   ·   %d / %d XP   ·   %d skill point%s" % [Progression.level, prog.x, prog.y,
		Progression.points, "" if Progression.points == 1 else "s"]
	_xp_bar.max_value = prog.y
	_xp_bar.value = prog.x
	for id in _rows:
		var spec: Dictionary = Progression.SKILLS[id]
		var lvl := Progression.get_skill(id)
		var r: Dictionary = _rows[id]
		(r.name as Label).text = "%s   %d / %d" % [spec.name, lvl, spec.max]
		(r.bar as ProgressBar).max_value = spec.max
		(r.bar as ProgressBar).value = lvl
		var desc: String = spec.info
		if id == "strength":
			desc += "\n" + Progression.strength_note()
		(r.desc as Label).text = desc
		var plus := r.plus as Button
		if lvl >= spec.max:
			plus.text = "MAX"
		else:
			var c := Progression.cost(id)
			plus.text = "+  %d pt%s" % [c, "" if c == 1 else "s"]
		plus.disabled = not Progression.can_upgrade(id)


## Both need a second click: the first one only arms the button.
func _on_refund() -> void:
	if _armed != "refund":
		_arm("refund")
		return
	_armed = ""
	Progression.refund_skills()
	_reset_labels()
	_refresh()


func _on_reset() -> void:
	if _armed != "reset":
		_arm("reset")
		return
	_armed = ""
	Progression.reset_career()
	_reset_labels()
	_refresh()


func _arm(which: String) -> void:
	_armed = which
	_reset_labels()
	if which == "refund":
		_refund.text = "CLICK AGAIN: REFUND"
	else:
		_reset.text = "CLICK AGAIN: LEVEL 1"


func _reset_labels() -> void:
	_refund.text = "REFUND SKILLS"
	_reset.text = "RESET CAREER"


func _buy(id: String) -> void:
	_armed = ""
	_reset_labels()
	if Progression.upgrade(id):
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skills") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()


func close_panel() -> void:
	if pause_game:
		get_tree().paused = false
	closed.emit()
	queue_free()


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.25))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.07, 0.04, 0.95 if state != "disabled" else 0.4)
		style.border_color = GOLD if state in ["hover", "focus", "pressed"] else Color(GOLD, 0.4)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		b.add_theme_stylebox_override(state, style)
	return b
