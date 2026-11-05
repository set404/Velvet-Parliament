class_name ThrowableProp
extends RigidBody3D
## Chamber furniture that can be picked up, thrown, or kicked across the room: chairs,
## monitors, bottles, plants, microphones, papers, the flag, and the big pieces (desks,
## the staff counter, the presidium desk, the speaker's tribune).
## Each kind has a "lift" tier (1-5); LIFT_STRENGTH says how much Strength a tier needs.
## Loose items only collide with the world and other props at rest, so people walk
## through them; while flying they also hit people. Anchored items (the big furniture)
## stand frozen and solid, like the building, until someone strong enough rips them out.

const LAYER_WORLD := 1
const LAYER_CHARS := 2
const LAYER_PROPS := 4
const LAYER_RAGDOLL := 8
## Strength needed per lift tier (index = tier), and what each tier covers.
const LIFT_STRENGTH := [0, 1, 4, 7, 11, 15]
const TIER_NAMES := ["", "chairs and small items", "presidium chairs and the flag", "desks",
	"the staff counter and presidium desk", "the speaker's tribune"]
## Invisible stand-ins for anchored furniture that only the navigation bake sees.
const LAYER_NAV := 16
const REST_MASK := LAYER_WORLD | LAYER_PROPS | LAYER_RAGDOLL

## Per kind: mass, damage on hit, whether a hit knocks people down, throw speed,
## collision box size and centre, how it sits on the carrier's hold point, the Strength
## needed to lift it, and whether it starts anchored in place. "one_hand" items (bottle,
## microphone, paper) are carried in the right fist instead of over the head; their
## "hold" is relative to the hand (+Y up, -Z forward while the arm is in its carry pose).
## Kinds built from several pieces of different sizes pass their own boxes to create().
const KINDS := {
	"chair": {"mass": 9.0, "damage": 30.0, "knockdown": true, "speed": 14.0,
		"size": Vector3(0.58, 1.1, 0.56), "center": Vector3(0.0, 0.57, -0.04),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 1.15, 0.05))},
	"monitor": {"mass": 6.0, "damage": 22.0, "knockdown": true, "speed": 15.0,
		"size": Vector3(0.46, 0.46, 0.18), "center": Vector3(0.0, 0.23, -0.02),
		"hold": Transform3D(Basis(), Vector3(0.0, 0.05, 0.0))},
	"bottle": {"mass": 0.6, "damage": 8.0, "knockdown": false, "speed": 19.0,
		"size": Vector3(0.07, 0.22, 0.07), "center": Vector3(0.0, 0.11, 0.0),
		# Small items sit in the right fist, gripped round the middle.
		"one_hand": true, "hold": Transform3D(Basis(), Vector3(0.0, -0.11, 0.0))},
	"plant": {"mass": 8.0, "damage": 20.0, "knockdown": true, "speed": 13.0,
		"size": Vector3(0.5, 1.05, 0.5), "center": Vector3(0.0, 0.52, 0.0),
		"hold": Transform3D(Basis(), Vector3(0.0, 0.05, 0.0))},
	"mic": {"mass": 0.8, "damage": 6.0, "knockdown": false, "speed": 19.0,
		"size": Vector3(0.09, 0.4, 0.2), "center": Vector3(0.0, 0.18, 0.08),
		"one_hand": true, "hold": Transform3D(Basis(), Vector3(0.0, -0.12, -0.08))},
	"paper": {"mass": 0.1, "damage": 1.0, "knockdown": false, "speed": 12.0,
		"size": Vector3(0.21, 0.012, 0.297), "center": Vector3(0.0, 0.006, 0.0),
		# Held up by its top edge, like a sheet being waved at the chamber.
		"one_hand": true, "hold": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, -0.13, -0.02))},
	"boss_chair": {"mass": 16.0, "damage": 40.0, "knockdown": true, "speed": 12.0, "lift": 2,
		"size": Vector3(0.82, 1.85, 0.72), "center": Vector3(0.0, 0.92, -0.08),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 1.9, 0.05))},
	"flag": {"mass": 6.0, "damage": 32.0, "knockdown": true, "speed": 16.0, "lift": 2,
		"size": Vector3(0.36, 3.0, 0.36), "center": Vector3(0.0, 1.5, 0.0),
		# Carried like a lance, pointing ahead.
		"hold": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, -0.3, 1.1))},
	"desk": {"mass": 45.0, "damage": 55.0, "knockdown": true, "speed": 10.0, "lift": 3, "anchored": true,
		"size": Vector3(1.0, 0.78, 0.55), "center": Vector3(0.0, 0.39, 0.0),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 0.85, 0.0))},
	"counter": {"mass": 60.0, "damage": 60.0, "knockdown": true, "speed": 9.0, "lift": 4, "anchored": true,
		"size": Vector3(1.525, 0.99, 0.65), "center": Vector3(0.0, 0.495, 0.0),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 1.05, 0.0))},
	"presidium_desk": {"mass": 70.0, "damage": 65.0, "knockdown": true, "speed": 8.5, "lift": 4, "anchored": true,
		"size": Vector3(1.38, 1.25, 1.2), "center": Vector3(0.0, 0.625, 0.0),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 1.3, 0.0))},
	"tribune": {"mass": 80.0, "damage": 75.0, "knockdown": true, "speed": 8.0, "lift": 5, "anchored": true,
		"size": Vector3(1.12, 1.12, 0.74), "center": Vector3(0.0, 0.56, 0.0),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 1.2, 0.0))},
}

## Human-readable names for messages and score popups.
const NAMES := {"chair": "chair", "monitor": "monitor", "bottle": "bottle", "plant": "plant",
	"mic": "microphone", "paper": "paperwork", "boss_chair": "presidium chair", "flag": "flag",
	"desk": "desk", "counter": "staff counter", "presidium_desk": "presidium desk", "tribune": "tribune"}

var kind := "chair"
var damage := 30.0
var knockdown := true
var throw_speed := 14.0
var hold_offset := Transform3D.IDENTITY
## Small enough to carry in one hand (see KINDS).
var one_hand := false
## Lift tier (see LIFT_STRENGTH).
var lift := 1
var anchored := false
## The navigation stand-in of an anchored item (freed once it's ripped out).
var nav_blocker: Node3D
var holder: Node3D
var thrower: Node
var thrown := false

var _flight := 0.0
## While an item sits untouched where the chamber placed it, it's drawn as one instance
## of a shared MultiMesh (hundreds of items, a handful of draw calls); the first time it
## moves it switches to its own mesh.
var _batch: MultiMesh
var _batch_index := -1
var _mesh: MeshInstance3D
var _home: Node
var _exception: PhysicsBody3D


## boxes: optional [[size, center], ...] collision boxes replacing the kind's default.
static func create(prop_kind: String, mesh: Mesh, xf: Transform3D, boxes: Array = []) -> ThrowableProp:
	var spec: Dictionary = KINDS[prop_kind]
	var prop := ThrowableProp.new()
	prop.kind = prop_kind
	prop.transform = xf
	prop.mass = spec.mass
	prop.damage = spec.damage
	prop.knockdown = spec.knockdown
	prop.throw_speed = spec.speed
	prop.hold_offset = spec.hold
	prop.one_hand = spec.get("one_hand", false)
	prop.lift = spec.get("lift", 1)
	prop.anchored = spec.get("anchored", false)
	prop.continuous_cd = prop_kind in ["bottle", "mic", "paper"]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# Hundreds of small desk items aren't worth a pass in the shadow map.
	if prop_kind in ["monitor", "bottle", "mic", "paper"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prop.add_child(mi)
	prop._mesh = mi
	if boxes.is_empty():
		boxes = [[spec.size, spec.center]]
	for b in boxes:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b[0]
		shape.shape = box
		shape.position = b[1]
		prop.add_child(shape)
	return prop


## A static copy of an anchored item's collision on LAYER_NAV, so the navigation bake
## routes people around the furniture (the frozen rigid body itself isn't parsed).
func make_nav_blocker() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_NAV
	body.collision_mask = 0
	body.transform = transform
	for child in get_children():
		if child is CollisionShape3D:
			var cs := CollisionShape3D.new()
			cs.shape = (child as CollisionShape3D).shape
			cs.position = (child as CollisionShape3D).position
			body.add_child(cs)
	nav_blocker = body
	return body


## Hands drawing over to instance `index` of a shared MultiMesh until the item moves.
func batch_into(mm: MultiMesh, index: int) -> void:
	_batch = mm
	_batch_index = index
	_mesh.visible = false


func _unbatch() -> void:
	if _batch == null:
		return
	_batch.set_instance_transform(_batch_index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -100.0, 0.0)))
	_batch = null
	_mesh.visible = true


func display_name() -> String:
	return NAMES.get(kind, kind)


func _ready() -> void:
	add_to_group("props")
	collision_layer = LAYER_PROPS
	collision_mask = REST_MASK
	if anchored:
		# Solid like the building (people and the camera collide with it) until lifted.
		freeze = true
		collision_layer = LAYER_WORLD | LAYER_PROPS
	contact_monitor = true
	max_contacts_reported = 4
	sleeping = true
	body_entered.connect(_on_body_entered)
	sleeping_state_changed.connect(func() -> void:
		if not sleeping:
			_unbatch())
	# Only items in flight need a per-frame check; hundreds sit idle on desks.
	set_physics_process(false)


func can_pick() -> bool:
	return holder == null and not thrown


func required_strength() -> int:
	return LIFT_STRENGTH[clampi(lift, 0, LIFT_STRENGTH.size() - 1)]


func can_lift(strength: int) -> bool:
	return strength >= required_strength()


## Attaches the item to `hold`: the holder's overhead point (chairs go upside-down), or
## their right fist for one-handed items (see Brawler.hold_point()).
func pick_up(by: Node3D, hold: Node3D) -> void:
	_unbatch()
	if anchored:
		_unanchor()
	_land()
	holder = by
	_home = get_parent()
	freeze = true
	collision_layer = 0
	collision_mask = 0
	reparent(hold, false)
	transform = hold_offset


func throw(dir: Vector3, speed: float, by: Node) -> void:
	_unbatch()
	reparent(_home if is_instance_valid(_home) else get_tree().current_scene, true)
	holder = null
	freeze = false
	collision_layer = LAYER_PROPS
	sleeping = false
	linear_velocity = dir * speed + Vector3.UP * (2.0 if speed > 4.0 else 0.5)
	angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	if speed > 4.0:
		_launch(by)
	else:
		collision_mask = REST_MASK


## Punches and kicks shove parked chairs; a hard enough hit sends one flying into people.
func knock(push: Vector3, by: Node) -> void:
	if holder != null or anchored:
		return
	# Heavy things barely budge from a punch.
	push *= minf(1.0, 9.0 / mass)
	_unbatch()
	sleeping = false
	linear_velocity += push
	angular_velocity += Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
	if push.length() > 4.0:
		_launch(by)


## Ripped out of its place: becomes an ordinary loose prop, and whatever stood on it
## (monitors, bottles, papers) wakes up and falls.
func _unanchor() -> void:
	anchored = false
	collision_layer = LAYER_PROPS
	if is_instance_valid(nav_blocker):
		nav_blocker.queue_free()
	nav_blocker = null
	var here := global_position
	for node in get_tree().get_nodes_in_group("props"):
		var p := node as ThrowableProp
		if p == null or p == self or p.anchored or p.holder != null:
			continue
		var d := p.global_position - here
		if absf(d.x) < 1.6 and absf(d.z) < 1.6 and d.y > -0.2 and d.y < 2.0:
			p.sleeping = false


func _launch(by: Node) -> void:
	thrown = true
	thrower = by
	_flight = 0.0
	set_physics_process(true)
	collision_mask = REST_MASK | LAYER_CHARS
	if by is PhysicsBody3D:
		_exception = by
		add_collision_exception_with(by)


func _land() -> void:
	thrown = false
	set_physics_process(false)
	collision_mask = REST_MASK
	if is_instance_valid(_exception):
		remove_collision_exception_with(_exception)
	_exception = null


func _physics_process(delta: float) -> void:
	if not thrown:
		return
	_flight += delta
	if (_flight > 0.3 and linear_velocity.length() < 2.5) or _flight > 3.0:
		_land()


func _on_body_entered(body: Node) -> void:
	# Ragdoll segments carry their owner in metadata, so props also hit people who are down.
	var victim := body as Brawler
	if victim == null and body.has_meta("brawler"):
		victim = body.get_meta("brawler") as Brawler
	if not thrown or victim == null or victim == thrower or linear_velocity.length() < 3.0:
		return
	var push := Vector3(linear_velocity.x, 0.0, linear_velocity.z).normalized() * (5.0 if knockdown else 2.0)
	# Stray throws from the crowd shouldn't end the player's run on their own.
	var dmg := damage * (0.6 if victim is PlayerBrawler else 1.0)
	# The thrower may have been removed from the chamber while the item was in the air.
	victim.take_hit(dmg, push, knockdown, thrower if is_instance_valid(thrower) else null, kind)
	_land()
