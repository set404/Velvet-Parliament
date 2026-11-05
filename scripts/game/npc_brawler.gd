class_name NpcBrawler
extends Brawler
## A member of parliament (or a security guard) driven by a small riot state machine:
## sit through the session, then fight rivals, settle grudges, flee or cower.

enum State { SEATED, IDLE, SPEAK, FIGHT, FLEE, COWER }

var state := State.IDLE
var target: Brawler
var aggression := 0.7
var is_guard := false
var is_bounty := false
var exits: Array[Vector3] = []

var _agent: NavigationAgent3D
var _think := 0.0
var _attack_cd := 0.0
var _marker: MeshInstance3D


func _ready() -> void:
	super()
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.5
	_agent.target_desired_distance = 0.6
	_agent.radius = 0.3
	_agent.height = 1.7
	_agent.avoidance_enabled = false
	add_child(_agent)
	_think = randf() * 0.5


func seat_at(xf: Transform3D) -> void:
	state = State.SEATED
	sit_at(xf)
	# Knocked out, they're reborn standing at their own seat.
	home = xf.origin + Vector3.UP * 0.05


## Joins the riot: fights a rival, or runs for an exit.
func rouse(fight_chance: float) -> void:
	if down or is_guard or state == State.FIGHT:
		return
	stand_up()
	gesturing = false
	_cowering = false
	if randf() < fight_chance * (0.4 + aggression):
		_fight(_pick_target())
	else:
		_flee()


func set_bounty(on: bool) -> void:
	is_bounty = on
	if on and _marker == null:
		_marker = MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.16
		cone.bottom_radius = 0.0
		cone.height = 0.35
		_marker.mesh = cone
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.1)
		mat.emission_energy_multiplier = 3.0
		_marker.material_override = mat
		add_child(_marker)
	if _marker:
		_marker.visible = on


func _physics_process(delta: float) -> void:
	if _marker and _marker.visible:
		_marker.position = Vector3(0.0, 2.35 + sin(Time.get_ticks_msec() * 0.006) * 0.08, 0.0)
		_marker.rotation.y += delta * 3.0
	if seated:
		return
	_attack_cd -= delta
	_think -= delta
	if _think <= 0.0:
		_think = randf_range(0.3, 0.6)
		_decide()
	super(delta)


func _decide() -> void:
	if down:
		return
	match state:
		State.FIGHT:
			if not _valid(target):
				target = _pick_target()
			if target == null:
				state = State.IDLE
				return
			_agent.target_position = target.global_position
			if held_prop == null and not is_guard and randf() < 0.03:
				try_grab()
		State.FLEE:
			if global_position.distance_to(_agent.target_position) < 1.6:
				state = State.COWER
				_cowering = true
		State.IDLE:
			if randf() < 0.15 * aggression:
				_fight(_pick_target())


func _wish_velocity() -> Vector3:
	match state:
		State.FIGHT:
			if not _valid(target):
				_face_dir = Vector3.ZERO
				return Vector3.ZERO
			var to := target.global_position - global_position
			to.y = 0.0
			var d := to.length()
			_face_dir = to / d if d > 0.01 else Vector3.ZERO
			if held_prop != null and d > 2.5 and d < 9.0 and _attack_cd <= 0.0:
				throw_held((_face_dir + Vector3.UP * 0.12).normalized())
				_attack_cd = 1.5
				return Vector3.ZERO
			if d <= 1.15 and held_prop == null:
				if _attack_cd <= 0.0 and _attack == "":
					var roll := randf()
					start_attack("kick" if roll < 0.2 else ("punch1" if roll < 0.6 else "punch2"))
					_attack_cd = randf_range(0.6, 1.1) if is_guard else randf_range(0.8, 1.6)
				return Vector3.ZERO
			return _nav_dir() * move_speed * 1.2
		State.FLEE:
			_face_dir = Vector3.ZERO
			return _nav_dir() * move_speed * 1.4
	_face_dir = Vector3.ZERO
	return Vector3.ZERO


func _nav_dir() -> Vector3:
	var to := _agent.get_next_path_position() - global_position
	to.y = 0.0
	if to.length() < 0.05:
		to = _agent.target_position - global_position
		to.y = 0.0
	return to.normalized() if to.length() > 0.05 else Vector3.ZERO


func _fight(t: Brawler) -> void:
	if t == null:
		_flee()
		return
	state = State.FIGHT
	target = t
	_cowering = false
	_agent.target_position = t.global_position


func _flee() -> void:
	state = State.FLEE
	_cowering = false
	if exits.is_empty():
		state = State.COWER
		_cowering = true
		return
	var best := exits[0]
	for e in exits:
		if e.distance_to(global_position) < best.distance_to(global_position):
			best = e
	_agent.target_position = best + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))


func _valid(b: Brawler) -> bool:
	return b != null and is_instance_valid(b) and not b.down and b.global_position.distance_to(global_position) < 18.0


## Grudges first, then the nearest rival. Guards break up the nearest MP brawl.
func _pick_target() -> Brawler:
	var grudge := last_attacker as Brawler
	if _valid(grudge) and grudge.global_position.distance_to(global_position) < 14.0:
		return grudge
	var best: Brawler
	var best_d := 9.0
	for node in get_tree().get_nodes_in_group("brawlers"):
		var b := node as Brawler
		if b == null or b == self or b.down or not _is_rival(b):
			continue
		var d := b.global_position.distance_to(global_position)
		if d < best_d:
			best = b
			best_d = d
	return best


func _is_rival(b: Brawler) -> bool:
	# Only rival teams go after the player; guards leave the player alone.
	if b is PlayerBrawler:
		return Brawler.rival_teams(self, b)
	if is_guard:
		return b is NpcBrawler and not (b as NpcBrawler).is_guard and (b as NpcBrawler).state == State.FIGHT
	if b.faction == Faction.SECURITY:
		return false
	# Independents pick on team members; team members on everyone not on their team.
	if team_id < 0:
		return b.team_id >= 0
	return b.team_id != team_id


func in_combat() -> bool:
	return state == State.FIGHT


func _can_hit(other: Brawler) -> bool:
	if other == target:
		return true
	if is_guard or other is PlayerBrawler:
		return false
	return other.faction != Faction.SECURITY and randf() < 0.2


func _on_hit(attacker: Node) -> void:
	var b := attacker as Brawler
	if b == null or b == self:
		return
	gesturing = false
	if is_guard or state == State.FIGHT:
		if randf() < 0.6 or not _valid(target):
			_fight(b)
	elif randf() < aggression + 0.25:
		_fight(b)
	else:
		_flee()


func _on_stood_up() -> void:
	if state == State.SEATED:
		state = State.IDLE
