class_name PlayerBrawler
extends Brawler
## The player's MP: third-person camera, punch combo, kick, and chair grab/throw.

const MOUSE_SENSITIVITY := 0.0025
const SPRINT := 1.5

var camera: Camera3D
var input_enabled := true

var _cam_pivot: Node3D
var _arm: SpringArm3D
var _yaw := 0.0
var _pitch := -0.3
var _combat_t := 0.0
var _queued := ""
var _shake := 0.0
var _regen_delay := 0.0
## On touch devices the look comes from TouchControls; Android also turns touches into
## mouse events, which must not turn the camera a second time.
var _touch := TouchControls.wanted()


func _ready() -> void:
	super()
	add_to_group("player")
	faction = Faction.PLAYER
	display_name = "You"
	_yaw = rotation.y
	_cam_pivot = Node3D.new()
	_cam_pivot.top_level = true
	# Physics runs at 30 Hz with interpolation; the camera updates every rendered frame
	# instead, so mouse look stays immediate.
	_cam_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_cam_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = 4.0
	_arm.collision_mask = LAYER_WORLD
	_arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_arm.position = Vector3(0.45, 0.0, 0.0)
	_arm.add_excluded_object(get_rid())
	_cam_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.current = true
	_arm.add_child(camera)
	if not _touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Camera turn from the touch look area (radians).
func look(delta: Vector2) -> void:
	if not input_enabled:
		return
	_yaw -= delta.x
	_pitch = clampf(_pitch - delta.y, -1.2, 0.45)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _touch:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -1.2, 0.45)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_combat_t = maxf(0.0, _combat_t - delta)
	if input_enabled:
		_read_actions()
	_regen_delay -= delta
	if _regen_delay <= 0.0 and not down:
		health = minf(max_health, health + regen_rate * delta)
	if _attack == "":
		_face_dir = Vector3.ZERO
	super(delta)


func _process(delta: float) -> void:
	_update_camera(delta)


func _read_actions() -> void:
	if Input.is_action_just_pressed("jump"):
		_jump = true
	if Input.is_action_just_pressed("punch"):
		_combat_t = 3.0
		if is_holding():
			throw_held(_aim_dir())
		elif _attack == "":
			_auto_face()
			start_attack("punch1")
		elif _attack == "punch1":
			_queued = "punch2"
		elif _attack == "punch2":
			_queued = "punch3"
	if Input.is_action_just_pressed("kick"):
		_combat_t = 3.0
		if is_holding():
			throw_held(_aim_dir())
		elif _attack == "":
			_auto_face()
			start_attack("kick")
	if Input.is_action_just_pressed("grab"):
		if is_holding():
			throw_held(_aim_dir())
		else:
			# Knocked-out people within reach take priority over furniture.
			if not try_grab_body():
				try_grab()


func _wish_velocity() -> Vector3:
	if not input_enabled:
		return Vector3.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, _yaw) * Vector3(v.x, 0.0, v.y)
	var speed := move_speed * (SPRINT if Input.is_action_pressed("sprint") else 1.0)
	# Hauling a desk over your head slows you down.
	if held_prop != null and held_prop.lift >= 3:
		speed *= 0.7
	return dir * speed


## Swings only connect with rival teams (teammates and bystanders are passed through).
## The player's team_id is the team picked on the select screen: its MPs are teammates,
## every other team's MPs fight the player.
func _can_hit(other: Brawler) -> bool:
	return Brawler.rival_teams(self, other)


func in_combat() -> bool:
	return _combat_t > 0.0


func _on_hit(_attacker: Node) -> void:
	_regen_delay = 4.0
	_combat_t = 3.0
	shake(0.25)


func _on_attack_finished() -> void:
	if _queued != "":
		var next := _queued
		_queued = ""
		_auto_face()
		start_attack(next)


## Soft lock-on: turn toward the closest standing person roughly where the camera looks.
func _auto_face() -> void:
	var look := _camera_forward()
	var best_d := 2.8
	var dir := look
	for node in get_tree().get_nodes_in_group("brawlers"):
		var b := node as Brawler
		if b == null or b == self or b.down:
			continue
		var to := b.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.01 and d < best_d and look.dot(to / d) > 0.2:
			best_d = d
			dir = to / d
	_face_dir = dir
	rotation.y = atan2(-dir.x, -dir.z)


func _aim_dir() -> Vector3:
	var dir := -camera.global_basis.z
	dir.y = clampf(dir.y + 0.15, -0.3, 0.5)
	dir = dir.normalized()
	rotation.y = atan2(-dir.x, -dir.z)
	return dir


func _camera_forward() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3.FORWARD


func _update_camera(delta: float) -> void:
	_cam_pivot.global_position = get_global_transform_interpolated().origin + Vector3(0.0, 1.65, 0.0)
	_cam_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_shake = maxf(0.0, _shake - delta)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.3
