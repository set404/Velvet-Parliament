class_name Hud
extends CanvasLayer
## On-screen counters for the riot: chaos score and multiplier, session clock,
## chaos meter, health, current bounty, event messages and the results card.

const TEXT := Color(1.0, 0.96, 0.88)
const GOLD := Color(1.0, 0.78, 0.25)

var _score: Label
var _mult: Label
var _timer: Label
var _chaos: ProgressBar
var _health: ProgressBar
var _level: Label
var _xp: ProgressBar
var _bounty: Label
var _message: Label
var _popup: Label
var _hint: Label
var _flash: ColorRect
var _results: PanelContainer
var _results_text: Label

var _msg_left := 0.0
var _popup_left := 0.0
var _hint_left := 12.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	_score = _label(root, 38, HORIZONTAL_ALIGNMENT_LEFT, 14.0)
	_mult = _label(root, 28, HORIZONTAL_ALIGNMENT_LEFT, 62.0, false, GOLD)
	_timer = _label(root, 34, HORIZONTAL_ALIGNMENT_CENTER, 10.0)
	_label(root, 13, HORIZONTAL_ALIGNMENT_CENTER, 54.0).text = "CHAOS"
	_chaos = _bar(root, 0.5, 74.0, 320.0, 12.0, Color(0.95, 0.3, 0.1))
	_bounty = _label(root, 20, HORIZONTAL_ALIGNMENT_RIGHT, 18.0, false, GOLD)
	_message = _label(root, 34, HORIZONTAL_ALIGNMENT_CENTER, 150.0)
	_popup = _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER, 250.0, false, GOLD)
	_label(root, 14, HORIZONTAL_ALIGNMENT_LEFT, -70.0, true).text = "HEALTH"
	_health = _bar(root, 0.0, -48.0, 300.0, 18.0, Color(0.25, 0.8, 0.35), true)
	_level = _label(root, 14, HORIZONTAL_ALIGNMENT_LEFT, -116.0, true, GOLD)
	_xp = _bar(root, 0.0, -92.0, 300.0, 6.0, GOLD, true)
	_hint = _label(root, 15, HORIZONTAL_ALIGNMENT_RIGHT, -120.0, true)
	_hint.visible = not TouchControls.wanted()
	_hint.text = "WASD move · Shift sprint · Space jump\nLMB punch (tap for combo) · RMB kick\nE grab / throw (anything in the chamber; big furniture needs Strength) · Tab skills · Esc pause"

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.6)
	dot.anchor_left = 0.5
	dot.anchor_right = 0.5
	dot.anchor_top = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_left = -2
	dot.offset_right = 2
	dot.offset_top = -2
	dot.offset_bottom = 2
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)

	_results = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.03, 0.02, 0.88)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	_results.add_theme_stylebox_override("panel", style)
	_results.anchor_left = 0.5
	_results.anchor_right = 0.5
	_results.anchor_top = 0.5
	_results.anchor_bottom = 0.5
	_results.offset_left = -280
	_results.offset_right = 280
	_results.offset_top = -170
	_results.offset_bottom = 170
	_results.visible = false
	root.add_child(_results)
	_results_text = Label.new()
	_results_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_results_text.add_theme_font_size_override("font_size", 24)
	_results_text.add_theme_color_override("font_color", TEXT)
	_results.add_child(_results_text)


func _label(parent: Control, size: int, align: HorizontalAlignment, top: float, from_bottom := false, color := TEXT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 1.0 if from_bottom else 0.0
	l.anchor_bottom = l.anchor_top
	l.offset_left = 24.0
	l.offset_right = -24.0
	l.offset_top = top
	l.offset_bottom = top + size * 1.5
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, anchor_x: float, top: float, width: float, height: float, color: Color, from_bottom := false) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.anchor_left = anchor_x
	bar.anchor_right = anchor_x
	bar.anchor_top = 1.0 if from_bottom else 0.0
	bar.anchor_bottom = bar.anchor_top
	var left := -width * 0.5 if anchor_x == 0.5 else 24.0
	bar.offset_left = left
	bar.offset_right = left + width
	bar.offset_top = top
	bar.offset_bottom = top + height
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func update_stats(score: int, mult: int, time_left: float, riot: bool, chaos: float, health_pct: float, bounty: String) -> void:
	_score.text = "CHAOS  %d" % score
	_mult.text = "x%d COMBO" % mult if mult > 1 else ""
	var t := maxi(0, ceili(time_left))
	_timer.text = ("%d:%02d" % [t / 60, t % 60]) if riot else "IN SESSION"
	_chaos.value = chaos
	_health.value = health_pct * 100.0
	_bounty.text = bounty


func update_progress(level: int, xp_into: int, xp_needed: int, points: int) -> void:
	_level.text = "LEVEL %d" % level + ("   ·   %d skill point%s  (Tab)" % [points, "" if points == 1 else "s"] if points > 0 else "")
	_xp.max_value = xp_needed
	_xp.value = xp_into


func show_message(text: String, seconds := 2.5) -> void:
	_message.text = text
	_msg_left = seconds


func popup(text: String) -> void:
	_popup.text = text
	_popup_left = 0.9


func flash_damage() -> void:
	_flash.color.a = 0.28


func show_results(title: String, body: String, can_change_character := false) -> void:
	if TouchControls.wanted():
		_results_text.text = "%s\n\n%s" % [title, body]
	else:
		_results_text.text = "%s\n\n%s\n\nPress R to start a new session · Tab for skills" % [title, body]
		if can_change_character:
			_results_text.text += "\nPress C to choose another character"
	_results.offset_top = -250
	_results.offset_bottom = 250
	_results.visible = true
	_message.text = ""


func _process(delta: float) -> void:
	_msg_left -= delta
	_message.modulate.a = clampf(_msg_left, 0.0, 1.0)
	_popup_left -= delta
	_popup.modulate.a = clampf(_popup_left * 2.0, 0.0, 1.0)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.8)
	_hint_left -= delta
	_hint.modulate.a = clampf(_hint_left / 2.0, 0.0, 1.0)
