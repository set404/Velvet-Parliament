class_name Brawler
extends CharacterBody3D
## Anyone who can throw a punch in the chamber: a blocky procedural body animated in
## code, melee attacks, knockdowns, chair carrying and step climbing for the tiers.
## Knockdowns hand the body to a physics ragdoll (one rigid body per limb segment,
## joined by cone-twist joints); getting up blends from wherever it came to rest.
## Subclasses supply intent through _wish_velocity() and the _on_* hooks.

signal hit_landed(attacker: Node, victim: Brawler, damage: float, kind: String)
signal knocked_down(victim: Brawler, attacker: Node)
## Tried to grab something heavier than this brawler's strength allows.
signal lift_failed(prop: ThrowableProp)

enum Faction { VELVET, IRON, INDEPENDENT, SECURITY, PLAYER }

const LAYER_WORLD := 1
const LAYER_CHARS := 2
const LAYER_RAGDOLL := 8
const GRAVITY := 18.0
const JUMP_SPEED := 6.2
const STEP_HEIGHT := 0.36
const RADIUS := 0.28

## Timing is in seconds; "hit" is the fraction of the move where the blow lands.
const ATTACKS := {
	"punch1": {"time": 0.34, "hit": 0.45, "range": 1.05, "damage": 1.0, "knock": 2.5, "down": false},
	"punch2": {"time": 0.34, "hit": 0.45, "range": 1.05, "damage": 1.0, "knock": 2.5, "down": false},
	"punch3": {"time": 0.5, "hit": 0.5, "range": 1.1, "damage": 1.8, "knock": 5.5, "down": true},
	"kick": {"time": 0.6, "hit": 0.5, "range": 1.3, "damage": 2.0, "knock": 6.5, "down": true},
	"throw": {"time": 0.35, "hit": 9.0, "range": 0.0, "damage": 0.0, "knock": 0.0, "down": false},
}

static var _cache := {}
## Where the camera's attention is (the player); distant bodies animate at half rate.
static var focus := Vector3.ZERO


var faction := Faction.INDEPENDENT
var display_name := "Member"
var max_health := 50.0
var health := 50.0
var move_speed := 3.0
var base_damage := 8.0
## Which furniture this brawler can lift (see ThrowableProp lift values, 1-5).
var strength := 1
## Multiplies throw speed.
var throw_power := 1.0
## How long getting back up takes after a knockdown (a character skin with get-up clips
## lengthens it to fit them), and whether the last one was from lying on the back.
var getup_time := 0.8
var got_up_on_back := false
## Skill effects (the player's Recovery and Iron Chin).
var getup_mult := 1.0
var damage_taken := 1.0
var regen_rate := 4.0
var down := false
var seated := false
var gesturing := false
var held_prop: ThrowableProp
var last_attacker: Node
## Push away from overlapping neighbours, filled in by update_separation().
var separation := Vector3.ZERO

var _attack := ""
var _attack_t := 0.0
var _hit_done := false
var _stagger := 0.0
var _down_left := 0.0
var _cowering := false
var _jump := false
var _face_dir := Vector3.ZERO
var _phase := 0.0
var _time := 0.0

var _rig: Node3D
var _hips: Node3D
var _head: Node3D
var _hold: Node3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _tools := {}
var _meshes := {}

## Ragdoll layout: one entry per joint pivot (see _segment()).
var _segments: Array[Dictionary] = []
var _ragdoll: Node3D
var _torso: RigidBody3D
var _recover := 0.0

## Carrying knocked-out people: the carrier's held_body, and on the victim the carrier
## and, after a throw, who threw them (so impacts count as their hits).
var held_body: Brawler
var carried_by: Brawler
var _thrown_by: Node
var _body_flight := 0.0
var _body_hits := 0


func _ready() -> void:
	add_to_group("brawlers")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.875, 0.0)
	add_child(shape)
	floor_snap_length = 0.4
	_apply_collision()
	_hold = Node3D.new()
	_hold.position = Vector3(0.0, 1.75, 0.0)
	add_child(_hold)


## People don't physically collide with each other (that doubled the cost of every
## move); update_separation() keeps them apart instead. The layer still lets thrown
## props and ragdolls hit them.
func _apply_collision() -> void:
	collision_layer = 0 if (seated or down) else LAYER_CHARS
	collision_mask = 0 if seated else LAYER_WORLD


## Cheap crowd spacing: bucket standing people into 1 m cells and push overlapping
## neighbours apart. Call once per physics frame.
static func update_separation(brawlers: Array) -> void:
	const SPACE := 0.6
	var grid := {}
	var standing: Array[Brawler] = []
	for node in brawlers:
		var b := node as Brawler
		b.separation = Vector3.ZERO
		if b.down or b.seated:
			continue
		var key := Vector2i(floori(b.global_position.x), floori(b.global_position.z))
		(grid.get_or_add(key, []) as Array).append(b)
		standing.append(b)
	for b in standing:
		var p := b.global_position
		var cx := floori(p.x)
		var cz := floori(p.z)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell: Array = grid.get(Vector2i(cx + dx, cz + dz), [])
				for other: Brawler in cell:
					if other == b:
						continue
					var d := Vector3(p.x - other.global_position.x, 0.0, p.z - other.global_position.z)
					var l := d.length()
					if l < SPACE and absf(p.y - other.global_position.y) < 1.2:
						var away := d / l if l > 0.001 else Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
						b.separation += away * (SPACE - l)


# --- Body --------------------------------------------------------------------

## Builds the jointed body. Forward is -Z; joints rotate +X to swing limbs forward.
func build_body(suit: Color, tie: Color, skin: Color, hair: Color, cap := false, body_scale := 1.0) -> void:
	_rig = Node3D.new()
	_rig.scale = Vector3.ONE * body_scale
	add_child(_rig)
	_hips = _pivot(_rig, Vector3(0.0, 0.95, 0.0))
	_part(_hips, Vector3(0.36, 0.2, 0.22), Vector3(0.0, 0.02, 0.0), suit)
	_part(_hips, Vector3(0.44, 0.56, 0.24), Vector3(0.0, 0.38, 0.0), suit)
	_part(_hips, Vector3(0.16, 0.42, 0.02), Vector3(0.0, 0.45, -0.121), Color(0.93, 0.93, 0.95))
	_part(_hips, Vector3(0.06, 0.36, 0.02), Vector3(0.0, 0.43, -0.132), tie)
	_head = _pivot(_hips, Vector3(0.0, 0.7, 0.0))
	_part(_head, Vector3(0.1, 0.1, 0.1), Vector3(0.0, -0.02, 0.0), skin)
	_ball(_head, 0.125, Vector3(0.0, 0.12, 0.0), skin)
	_ball(_head, 0.13, Vector3(0.0, 0.16, 0.025), hair)
	for side in [-1.0, 1.0]:
		_part(_head, Vector3(0.03, 0.03, 0.02), Vector3(side * 0.045, 0.13, -0.117), Color(0.05, 0.04, 0.04))
	if cap:
		_part(_head, Vector3(0.28, 0.08, 0.28), Vector3(0.0, 0.25, 0.0), suit.darkened(0.3))
		_part(_head, Vector3(0.22, 0.02, 0.1), Vector3(0.0, 0.22, -0.17), Color(0.02, 0.02, 0.02))
	for side in [-1.0, 1.0]:
		var sh := _pivot(_hips, Vector3(side * 0.28, 0.6, 0.0))
		_part(sh, Vector3(0.12, 0.32, 0.13), Vector3(0.0, -0.15, 0.0), suit)
		var el := _pivot(sh, Vector3(0.0, -0.3, 0.0))
		_part(el, Vector3(0.11, 0.28, 0.11), Vector3(0.0, -0.14, 0.0), suit)
		_ball(el, 0.06, Vector3(0.0, -0.31, 0.0), skin)
		var hip := _pivot(_hips, Vector3(side * 0.11, -0.02, 0.0))
		_part(hip, Vector3(0.16, 0.46, 0.17), Vector3(0.0, -0.23, 0.0), suit)
		var knee := _pivot(hip, Vector3(0.0, -0.46, 0.0))
		_part(knee, Vector3(0.14, 0.42, 0.14), Vector3(0.0, -0.21, 0.0), suit)
		_part(knee, Vector3(0.13, 0.08, 0.27), Vector3(0.0, -0.45, -0.05), Color(0.03, 0.03, 0.03))
		_shoulders.append(sh)
		_elbows.append(el)
		_legs.append(hip)
		_knees.append(knee)
	_commit_parts()

	var box := func(x: float, y: float, z: float) -> Shape3D:
		var b := BoxShape3D.new()
		b.size = Vector3(x, y, z) * body_scale
		return b
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.14 * body_scale
	_segment(_hips, -1, box.call(0.42, 0.75, 0.24), Vector3(0.0, 0.3, 0.0), 20.0)
	_segment(_head, 0, head_shape, Vector3(0.0, 0.12, 0.0), 5.0, Vector3.UP, 35.0, 30.0)
	for i in 2:
		_segment(_shoulders[i], 0, box.call(0.12, 0.3, 0.12), Vector3(0.0, -0.15, 0.0), 3.0, Vector3.DOWN, 80.0, 45.0)
		_segment(_elbows[i], _segments.size() - 1, box.call(0.11, 0.36, 0.11), Vector3(0.0, -0.17, 0.0), 2.5, Vector3.DOWN, 65.0, 10.0)
		_segment(_legs[i], 0, box.call(0.16, 0.44, 0.17), Vector3(0.0, -0.23, 0.0), 7.0, Vector3.DOWN, 60.0, 20.0)
		_segment(_knees[i], _segments.size() - 1, box.call(0.14, 0.48, 0.16), Vector3(0.0, -0.24, 0.0), 5.0, Vector3.DOWN, 55.0, 5.0)


## Registers a ragdoll segment. dir is the limb direction in the pivot's frame,
## which becomes the twist axis of the joint to the parent segment.
func _segment(pivot: Node3D, parent: int, shape: Shape3D, offset: Vector3, mass: float,
		dir := Vector3.DOWN, swing := 0.0, twist := 0.0) -> void:
	_segments.append({"pivot": pivot, "parent": parent, "shape": shape,
		"offset": offset * _rig.scale.x, "mass": mass, "dir": dir, "swing": swing, "twist": twist})


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var key := "box%s" % size
	if not _cache.has(key):
		var box := BoxMesh.new()
		box.size = size
		_cache[key] = box
	_attach(parent, _cache[key], pos, color)


func _ball(parent: Node3D, radius: float, pos: Vector3, color: Color) -> void:
	var key := "ball%s" % radius
	if not _cache.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = 12
		s.rings = 6
		_cache[key] = s
	_attach(parent, _cache[key], pos, color)


## Parts are baked into one vertex-coloured mesh per joint, keeping a body to ~10 draw calls.
func _attach(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> void:
	if not _tools.has(parent):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[parent] = st
	var tool: SurfaceTool = _tools[parent]
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in indices:
		tool.set_color(color)
		tool.set_normal(normals[i])
		tool.add_vertex(verts[i] + pos)


func _commit_parts() -> void:
	if not _cache.has("body_mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.75
		_cache["body_mat"] = m
	for pivot in _tools:
		var mi := MeshInstance3D.new()
		mi.mesh = (_tools[pivot] as SurfaceTool).commit()
		mi.material_override = _cache["body_mat"]
		(pivot as Node3D).add_child(mi)
		_meshes[pivot] = mi
	_tools.clear()


# --- Seating -----------------------------------------------------------------

## Seats the brawler in a chair whose +Z faces the chamber floor.
func sit_at(xf: Transform3D) -> void:
	seated = true
	transform = Transform3D(xf.basis.rotated(Vector3.UP, PI), xf.origin)
	_apply_collision()
	_animate(1.0)


func stand_up() -> void:
	if not seated:
		return
	seated = false
	_apply_collision()
	_on_stood_up()


# --- Combat ------------------------------------------------------------------

func start_attack(kind: String) -> bool:
	if down or seated or _recover > 0.0 or _attack != "" or is_holding():
		return false
	_attack = kind
	_attack_t = 0.0
	_hit_done = false
	return true


func is_attacking() -> bool:
	return _attack != ""


func take_hit(damage: float, knock: Vector3, knockdown: bool, attacker: Node, kind: String) -> void:
	if down:
		# Kicking someone who is already down just shoves the ragdoll around.
		if _torso != null:
			health -= damage * 0.5
			_torso.apply_central_impulse(knock * _torso.mass * 0.6 + Vector3.UP * 30.0)
			_down_left = maxf(_down_left, 0.8)
			hit_landed.emit(attacker, self, damage * 0.5, kind)
		return
	stand_up()
	_cowering = false
	damage *= damage_taken
	health -= damage
	last_attacker = attacker
	velocity += knock
	_stagger = 0.3
	_attack = ""
	hit_landed.emit(attacker, self, damage, kind)
	if health <= 0.0 or knockdown:
		_knock_down(attacker)
	_on_hit(attacker)


func _knock_down(attacker: Node) -> void:
	down = true
	_down_left = 4.5 if health <= 0.0 else 1.8
	_attack = ""
	drop_prop()
	_apply_collision()
	if held_body != null and is_instance_valid(held_body):
		held_body.end_carry(velocity, null)
		held_body = null
	_start_ragdoll(velocity + Vector3.UP * 2.0)
	knocked_down.emit(self, attacker)


func _get_up() -> void:
	_end_ragdoll()
	down = false
	if health <= 0.0:
		health = max_health * 0.5
	_apply_collision()
	_on_got_up()


## Keeps a downed brawler down (e.g. after the player is ejected).
func stay_down() -> void:
	_down_left = INF


## Where the body actually is: the ragdoll's pelvis while down, otherwise the feet.
func body_center() -> Vector3:
	return _torso.global_position if _torso != null else global_position


# --- Ragdoll -----------------------------------------------------------------

## Swaps the animated rig for physics: one rigid body per segment at its current
## pose, the segment's mesh moved onto it, linked to its parent with a cone-twist joint.
func _start_ragdoll(launch: Vector3) -> void:
	if _rig == null or _ragdoll != null:
		return
	_ragdoll = Node3D.new()
	_ragdoll.top_level = true
	add_child(_ragdoll)
	_ragdoll.global_transform = Transform3D.IDENTITY
	var bodies: Array[RigidBody3D] = []
	for seg in _segments:
		var pivot: Node3D = seg.pivot
		var body := RigidBody3D.new()
		body.mass = seg.mass
		body.angular_damp = 1.5
		body.collision_layer = LAYER_RAGDOLL
		body.collision_mask = LAYER_WORLD | LAYER_CHARS | LAYER_RAGDOLL | ThrowableProp.LAYER_PROPS
		body.set_meta("brawler", self)
		var gt := pivot.global_transform
		body.transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
		var cs := CollisionShape3D.new()
		cs.shape = seg.shape
		cs.position = seg.offset
		body.add_child(cs)
		_ragdoll.add_child(body)
		body.body_entered.connect(_on_ragdoll_contact.bind(body))
		(_meshes[pivot] as Node3D).reparent(body, true)
		body.linear_velocity = launch
		bodies.append(body)
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			bodies[i].add_collision_exception_with(bodies[j])
	for i in range(1, _segments.size()):
		var seg := _segments[i]
		var pivot: Node3D = seg.pivot
		var dir: Vector3 = (pivot.global_basis.orthonormalized() * (seg.dir as Vector3)).normalized()
		var joint := ConeTwistJoint3D.new()
		joint.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, dir)), pivot.global_position)
		joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(seg.swing))
		joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(seg.twist))
		_ragdoll.add_child(joint)
		joint.node_a = joint.get_path_to(bodies[seg.parent])
		joint.node_b = joint.get_path_to(bodies[i])
	_torso = bodies[0]
	_torso.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0))


## Hands the body back to the rig, lying where the ragdoll stopped, ready to get up.
func _end_ragdoll() -> void:
	if _ragdoll == null:
		return
	var pelvis := _torso.global_transform
	var head_dir := pelvis.basis.y
	head_dir.y = 0.0
	head_dir = head_dir.normalized() if head_dir.length() > 0.05 else global_basis.z
	var on_back := (-pelvis.basis.z).y > 0.0
	var from := pelvis.origin + Vector3.UP * 0.5
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var floor_y: float = hit.position.y if hit else pelvis.origin.y - 0.15

	for seg in _segments:
		var mesh: Node3D = _meshes[seg.pivot]
		mesh.reparent(seg.pivot, false)
		mesh.transform = Transform3D.IDENTITY
	_ragdoll.queue_free()
	_ragdoll = null
	_torso = null
	carried_by = null
	_thrown_by = null

	# Stand up around the pelvis: start the rig lying flat and let _animate lift it.
	global_position = Vector3(pelvis.origin.x, floor_y + 0.02, pelvis.origin.z)
	velocity = Vector3.ZERO
	rotation.y = atan2(head_dir.x, head_dir.z) if on_back else atan2(-head_dir.x, -head_dir.z)
	var reach := 0.95 * _rig.scale.x
	_rig.rotation.x = 1.45 if on_back else -1.45
	_rig.position = Vector3(0.0, 0.13, -reach if on_back else reach)
	_recover = getup_time * getup_mult
	got_up_on_back = on_back
	reset_physics_interpolation()


func _strike(a: Dictionary) -> void:
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var reach: float = a.range
	var knock: float = a.knock
	var dmg: float = base_damage * float(a.damage)
	for node in get_tree().get_nodes_in_group("brawlers"):
		var b := node as Brawler
		if b == null or b == self or not _can_hit(b):
			continue
		var to := b.body_center() - global_position
		if absf(to.y) > 1.0:
			continue
		to.y = 0.0
		var d := to.length()
		if d < 0.001 or d > reach + RADIUS or fwd.dot(to / d) < 0.3:
			continue
		b.take_hit(dmg, fwd * knock, a.down, self, _attack)
	for node in get_tree().get_nodes_in_group("props"):
		var p := node as ThrowableProp
		if p == null or p.holder != null:
			continue
		var to := p.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.001 and d < reach + 0.4 and fwd.dot(to / d) > 0.3:
			p.knock(fwd * knock * 1.4 + Vector3.UP * 1.5, self)


# --- Chairs ------------------------------------------------------------------

func try_grab() -> bool:
	if is_holding() or down or seated or _attack != "":
		return false
	# Reach is measured flat, so items on a desk count as close; prefer what's in front.
	# Big furniture counts from near its edge rather than its middle, but loose items
	# still win when both are in reach (clear the desk, then lift it).
	var best: ThrowableProp
	var best_d := 1.5
	var too_heavy: ThrowableProp
	var heavy_d := 1.5
	var fwd := -global_basis.z
	for node in get_tree().get_nodes_in_group("props"):
		var p := node as ThrowableProp
		if p == null or not p.can_pick():
			continue
		var to := p.global_position - global_position
		if to.y < -0.9 or to.y > 1.4:
			continue
		to.y = 0.0
		var flat := to.length()
		if p.anchored or p.lift > 1:
			flat = maxf(0.0, flat - 0.25)
		var d := flat - maxf(0.0, fwd.dot(to.normalized())) * 0.4
		if not p.can_lift(strength):
			if d < heavy_d:
				too_heavy = p
				heavy_d = d
			continue
		if d < best_d:
			best = p
			best_d = d
	if best == null:
		if too_heavy != null:
			lift_failed.emit(too_heavy)
		return false
	best.pick_up(self, _hold)
	held_prop = best
	return true


func is_holding() -> bool:
	if held_body != null and not is_instance_valid(held_body):
		held_body = null
	return held_prop != null or held_body != null


func throw_held(dir: Vector3) -> void:
	if held_body != null and is_instance_valid(held_body):
		var body := held_body
		held_body = null
		# From over the head a body needs a flat, slightly downward heave to plough into
		# people instead of sailing over them.
		var flat := Vector3(dir.x, clampf(dir.y, -0.3, -0.05), dir.z).normalized()
		body.end_carry(flat * 10.0 + Vector3.UP * 0.3, self)
	elif held_prop != null:
		var prop := held_prop
		held_prop = null
		prop.throw(dir, prop.throw_speed * throw_power, self)
	else:
		return
	_attack = "throw"
	_attack_t = 0.0
	_hit_done = true


# --- Carrying knocked-out people -----------------------------------------------

## Picks up the nearest ragdolled person within reach and hoists them overhead.
func try_grab_body() -> bool:
	if is_holding() or down or seated or _attack != "":
		return false
	var best: Brawler
	var best_d := 1.7
	for node in get_tree().get_nodes_in_group("brawlers"):
		var b := node as Brawler
		if b == null or b == self or not b.can_be_carried():
			continue
		var to := b.body_center() - global_position
		to.y = 0.0
		if to.length() < best_d:
			best = b
			best_d = to.length()
	if best == null:
		return false
	best.begin_carry(self)
	held_body = best
	return true


func can_be_carried() -> bool:
	return down and _torso != null and carried_by == null


## The torso is pinned kinematically above the carrier's head; arms and legs keep
## swinging under physics.
func begin_carry(by: Brawler) -> void:
	carried_by = by
	_thrown_by = null
	_torso.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_torso.freeze = true
	for body in _ragdoll.get_children():
		if body is RigidBody3D:
			(body as RigidBody3D).add_collision_exception_with(by)


func _follow_carrier() -> void:
	if not is_instance_valid(carried_by) or carried_by.down:
		end_carry(Vector3.ZERO, null)
		return
	# Draped across the shoulders: head to the carrier's left, belly up.
	var hold := carried_by._hold.global_transform
	var drape := (hold.basis * Basis(Vector3.BACK, PI * 0.5)).orthonormalized()
	var center := hold.origin + Vector3.UP * 0.15
	_torso.global_transform = Transform3D(drape, center + hold.basis.x.normalized() * 0.3)
	_down_left = maxf(_down_left, 1.0)


## Lets go: the whole ragdoll takes the throw velocity. A thrown body hits whoever it
## lands on, and those hits are credited to the thrower.
func end_carry(launch: Vector3, thrower: Node) -> void:
	var carrier := carried_by
	carried_by = null
	if _torso == null:
		return
	_torso.freeze = false
	for node in _ragdoll.get_children():
		var body := node as RigidBody3D
		if body == null:
			continue
		body.linear_velocity = launch
		if thrower != null:
			body.contact_monitor = true
			body.max_contacts_reported = 2
	if thrower != null:
		_thrown_by = thrower
		_body_flight = 0.0
		_body_hits = 0
		health -= 10.0
		_down_left = maxf(_down_left, 1.5)
	# Keep ignoring the carrier briefly so the body doesn't clip their head on release.
	if is_instance_valid(carrier):
		get_tree().create_timer(0.4).timeout.connect(_forget_carrier.bind(carrier))


func _forget_carrier(carrier: Brawler) -> void:
	if _ragdoll == null or not is_instance_valid(carrier):
		return
	for body in _ragdoll.get_children():
		if body is RigidBody3D:
			(body as RigidBody3D).remove_collision_exception_with(carrier)


func _on_ragdoll_contact(other: Node, part: RigidBody3D) -> void:
	if _thrown_by == null or _body_hits >= 3 or part.linear_velocity.length() < 4.0:
		return
	var victim := other as Brawler
	if victim == null and other.has_meta("brawler"):
		victim = other.get_meta("brawler") as Brawler
	if victim == null or victim == self or victim == _thrown_by:
		return
	_body_hits += 1
	var push := Vector3(part.linear_velocity.x, 0.0, part.linear_velocity.z).normalized() * 5.0
	victim.take_hit(25.0, push, true, _thrown_by, "body")


func _tick_body_flight(delta: float) -> void:
	if _thrown_by == null:
		return
	_body_flight += delta
	if _body_flight > 2.5 or _torso == null:
		_thrown_by = null
		if _ragdoll != null:
			for node in _ragdoll.get_children():
				if node is RigidBody3D:
					node.set_deferred("contact_monitor", false)


func drop_prop() -> void:
	if held_prop == null:
		return
	var prop := held_prop
	held_prop = null
	prop.throw(-global_basis.z, 1.5, self)


# --- Movement ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if seated:
		return
	_time += delta
	_tick(delta)
	if _torso != null:
		if carried_by != null:
			_follow_carrier()
		_tick_body_flight(delta)
		# The ragdoll owns the body; keep the (non-colliding) capsule on top of it.
		global_position = _torso.global_position
		return
	_recover = maxf(0.0, _recover - delta)
	var wish := Vector3.ZERO if (down or _cowering) else _wish_velocity()
	if _recover > 0.0:
		wish = Vector3.ZERO
	if _attack != "" or _stagger > 0.0:
		wish *= 0.2
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var accel := 30.0 if is_on_floor() else 8.0
	if down:
		accel = 6.0
	hv = hv.move_toward(wish + separation * 8.0, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if _jump and not down:
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	_jump = false
	_move_with_steps(delta)

	var face := _face_dir
	if face == Vector3.ZERO and wish.length() > 0.3:
		face = wish
	if face != Vector3.ZERO and not down:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), clampf(delta * 12.0, 0.0, 1.0))
	# Bodies far from the action animate every other frame (with a double step).
	if global_position.distance_squared_to(focus) > 144.0:
		if (Engine.get_physics_frames() + get_instance_id()) % 2 == 0:
			_animate(delta * 2.0)
	else:
		_animate(delta)


func _tick(delta: float) -> void:
	_stagger = maxf(0.0, _stagger - delta)
	if _attack != "":
		var a: Dictionary = ATTACKS[_attack]
		_attack_t += delta
		var p: float = _attack_t / float(a.time)
		if not _hit_done and p >= float(a.hit):
			_hit_done = true
			_strike(a)
		if p >= 1.0:
			_attack = ""
			_on_attack_finished()
	if down:
		_down_left -= delta
		# Wait for the body to settle, but never lie there more than 3 s extra.
		var settled := _torso == null or _torso.linear_velocity.length() < 0.8
		if _down_left <= 0.0 and (settled or _down_left < -3.0):
			_get_up()


## move_and_slide plus a step-up pass so people can climb the 0.32 m seating tiers.
func _move_with_steps(_delta: float) -> void:
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	var grounded := is_on_floor()
	# Standing still on the floor needs no collision sweep (nobody pushes people around),
	# and in a brawl most fighters stand still. This is the single biggest physics saving.
	if grounded and dir.length_squared() < 0.0004 and velocity.y <= 0.0:
		velocity = Vector3.ZERO
		return
	var start := global_transform
	move_and_slide()
	if not grounded or dir.length_squared() < 0.01 or not is_on_wall() or velocity.y > 0.1:
		return
	# Only try stepping up onto architecture, not onto the people jostling around us.
	var blocked_by_world := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if absf(c.get_normal().y) < 0.5 and c.get_collider() is StaticBody3D:
			blocked_by_world = true
			break
	if not blocked_by_world:
		return
	var up := Vector3(0.0, STEP_HEIGHT, 0.0)
	var ahead := dir.normalized() * (RADIUS + 0.04)
	if test_move(start, up):
		return
	var raised := start.translated(up)
	if test_move(raised, ahead):
		return
	var probe := KinematicCollision3D.new()
	var over := raised.translated(ahead)
	if test_move(over, -up * 1.2, probe) and probe.get_normal().y > 0.7:
		global_position = over.origin + probe.get_travel()
		velocity.y = 0.0


# --- Animation ---------------------------------------------------------------

func _animate(delta: float) -> void:
	if _rig == null or _ragdoll != null:
		return
	var k := clampf(delta * 16.0, 0.0, 1.0)
	var arm := [0.08, 0.08]
	var elbow := [0.15, 0.15]
	var leg := [0.0, 0.0]
	var knee := [0.0, 0.0]
	var spread := 0.12
	var rig_x := 0.0
	var rig_y := 0.0
	var lean := 0.0

	if down:
		rig_x = 1.45
		rig_y = 0.13
		arm = [2.6, 2.3]
		spread = 0.6
		leg = [0.15, -0.1]
	elif seated:
		leg = [1.57, 1.57]
		knee = [-1.57, -1.57]
		rig_y = -0.43
		arm = [0.5, 0.5]
		elbow = [0.9, 0.9]
	elif _cowering:
		leg = [1.4, 1.4]
		knee = [-2.2, -2.2]
		rig_y = -0.45
		arm = [2.5, 2.5]
		elbow = [1.9, 1.9]
		lean = 0.4
	else:
		var speed := Vector3(velocity.x, 0.0, velocity.z).length()
		_phase += delta * speed * 2.8
		var amt := clampf(speed / 4.0, 0.0, 1.0)
		var s := sin(_phase) * amt
		leg = [s * 0.75, -s * 0.75]
		knee = [-(0.15 + 0.8 * maxf(0.0, cos(_phase))) * amt, -(0.15 + 0.8 * maxf(0.0, -cos(_phase))) * amt]
		arm = [0.08 - s * 0.7, 0.08 + s * 0.7]
		if in_combat():
			arm = [1.0, 1.0]
			elbow = [1.9, 1.9]
			spread = 0.05
		if gesturing:
			arm[1] = 1.3 + sin(_time * 2.3) * 0.35
			elbow[1] = 0.9
		if is_holding():
			arm = [2.9, 2.9]
			elbow = [0.3, 0.3]
		if _attack != "":
			var a: Dictionary = ATTACKS[_attack]
			_attack_pose(_attack, _attack_t / float(a.time), arm, elbow, leg, knee)
			spread = 0.1
		if _stagger > 0.0:
			rig_x = _stagger
		if not is_on_floor():
			knee = [-0.9, -0.5]

	# Slower blend while getting up from the floor after a ragdoll.
	var rk := k * (0.22 if _recover > 0.0 else 0.6)
	_rig.rotation.x = lerp_angle(_rig.rotation.x, rig_x, rk)
	_rig.position = _rig.position.lerp(Vector3(0.0, rig_y, 0.0), rk if _recover > 0.0 else k)
	_hips.rotation.x = lerp_angle(_hips.rotation.x, lean, k)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_shoulders[i].rotation.x = lerp_angle(_shoulders[i].rotation.x, arm[i], k)
		_shoulders[i].rotation.z = lerp_angle(_shoulders[i].rotation.z, spread * side, k)
		_elbows[i].rotation.x = lerp_angle(_elbows[i].rotation.x, elbow[i], k)
		_legs[i].rotation.x = lerp_angle(_legs[i].rotation.x, leg[i], k)
		_knees[i].rotation.x = lerp_angle(_knees[i].rotation.x, knee[i], k)


## Writes attack poses into the joint target arrays ([left, right]).
func _attack_pose(kind: String, p: float, arm: Array, elbow: Array, leg: Array, knee: Array) -> void:
	var wind := p < 0.35
	var hit := p < 0.65
	match kind:
		"punch1", "punch2":
			var i := 1 if kind == "punch1" else 0
			arm[1 - i] = 1.0
			elbow[1 - i] = 1.9
			arm[i] = 0.9 if wind else (1.6 if hit else 1.2)
			elbow[i] = 2.0 if wind else (0.05 if hit else 1.2)
		"punch3":
			arm[0] = 1.0
			elbow[0] = 1.9
			arm[1] = 0.4 if wind else (2.8 if hit else 1.5)
			elbow[1] = 2.2 if wind else (0.5 if hit else 1.2)
		"kick":
			leg[1] = 0.9 if wind else (1.55 if hit else 0.5)
			knee[1] = -1.4 if wind else (-0.05 if hit else -0.6)
			arm[0] = 0.6
			arm[1] = -0.3
		"throw":
			arm[0] = lerpf(2.9, 1.0, p)
			arm[1] = arm[0]
			elbow[0] = 0.2
			elbow[1] = 0.2


# --- Hooks for subclasses ----------------------------------------------------

## Desired horizontal velocity this frame.
func _wish_velocity() -> Vector3:
	return Vector3.ZERO


func in_combat() -> bool:
	return false


func _can_hit(_other: Brawler) -> bool:
	return true


func _on_hit(_attacker: Node) -> void:
	pass


func _on_got_up() -> void:
	pass


func _on_stood_up() -> void:
	pass


func _on_attack_finished() -> void:
	pass
