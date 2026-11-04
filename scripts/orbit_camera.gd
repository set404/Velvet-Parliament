class_name OrbitCamera
extends Camera3D
## Inspection camera for the chamber.
## Left/right drag: orbit · Middle drag or WASD + Q/E: pan · Wheel: zoom · 1-4: preset views.

const PRESETS := [
	{"target": Vector3(0.0, 0.5, -3.0), "yaw": 0.0, "pitch": -26.0, "distance": 19.0},  # public gallery
	{"target": Vector3(2.0, 0.5, -2.0), "yaw": -76.5, "pitch": -27.0, "distance": 18.0},  # side gallery
	{"target": Vector3(1.5, 1.0, 2.5), "yaw": -148.0, "pitch": -12.0, "distance": 10.5},  # presidium corner
	{"target": Vector3(0.0, 1.4, -5.5), "yaw": 6.0, "pitch": -10.0, "distance": 11.0},  # member's seat
]

@export var orbit_speed := 0.25
@export var pan_speed := 6.0
@export var zoom_step := 1.12
@export var smoothing := 10.0

var target := Vector3.ZERO
var yaw := 0.0
var pitch := -30.0
var distance := 19.0

var _target := Vector3.ZERO
var _yaw := 0.0
var _pitch := -30.0
var _distance := 19.0


func _ready() -> void:
	apply_preset(0, true)


func apply_preset(index: int, snap := false) -> void:
	var p: Dictionary = PRESETS[clampi(index, 0, PRESETS.size() - 1)]
	target = p.target
	yaw = _yaw + wrapf(p.yaw - _yaw, -180.0, 180.0)
	pitch = p.pitch
	distance = p.distance
	if snap:
		_target = target
		_yaw = yaw
		_pitch = pitch
		_distance = distance
		_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
			yaw -= motion.relative.x * orbit_speed
			pitch = clampf(pitch - motion.relative.y * orbit_speed, -85.0, -2.0)
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var s := distance * 0.0015
			target += global_basis.x * -motion.relative.x * s + global_basis.y * motion.relative.y * s
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(2.0, distance / zoom_step)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(40.0, distance * zoom_step)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_4:
			apply_preset(key - KEY_1)


func _process(delta: float) -> void:
	var move := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if move != Vector3.ZERO:
		target += Basis(Vector3.UP, deg_to_rad(yaw)) * move * pan_speed * delta * (distance / 15.0)

	var k := 1.0 - exp(-smoothing * delta)
	_target = _target.lerp(target, k)
	_yaw = lerpf(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_distance = lerpf(_distance, distance, k)
	_update_transform()


func _update_transform() -> void:
	var rot := Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(_pitch))
	global_transform = Transform3D(rot, _target + rot * Vector3(0.0, 0.0, _distance))
