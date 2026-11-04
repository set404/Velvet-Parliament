class_name ThrowableProp
extends RigidBody3D
## Chamber furniture that can be picked up, thrown, or kicked across the room:
## chairs, desk monitors, water bottles and potted plants.
## At rest it only collides with the world and other props, so people walk through
## parked items; while flying it also collides with people and hurts them.

const LAYER_WORLD := 1
const LAYER_CHARS := 2
const LAYER_PROPS := 4
const LAYER_RAGDOLL := 8
const REST_MASK := LAYER_WORLD | LAYER_PROPS | LAYER_RAGDOLL

## Per kind: mass, damage on hit, whether a hit knocks people down, throw speed,
## collision box size and centre, and how it sits on the carrier's hold point.
const KINDS := {
	"chair": {"mass": 9.0, "damage": 30.0, "knockdown": true, "speed": 14.0,
		"size": Vector3(0.58, 1.1, 0.56), "center": Vector3(0.0, 0.57, -0.04),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 1.15, 0.05))},
	"monitor": {"mass": 6.0, "damage": 22.0, "knockdown": true, "speed": 15.0,
		"size": Vector3(0.46, 0.46, 0.18), "center": Vector3(0.0, 0.23, -0.02),
		"hold": Transform3D(Basis(), Vector3(0.0, 0.05, 0.0))},
	"bottle": {"mass": 0.6, "damage": 8.0, "knockdown": false, "speed": 19.0,
		"size": Vector3(0.07, 0.22, 0.07), "center": Vector3(0.0, 0.11, 0.0),
		"hold": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.1, -0.1))},
	"plant": {"mass": 8.0, "damage": 20.0, "knockdown": true, "speed": 13.0,
		"size": Vector3(0.5, 1.05, 0.5), "center": Vector3(0.0, 0.52, 0.0),
		"hold": Transform3D(Basis(), Vector3(0.0, 0.05, 0.0))},
}

var kind := "chair"
var damage := 30.0
var knockdown := true
var throw_speed := 14.0
var hold_offset := Transform3D.IDENTITY
var holder: Node3D
var thrower: Node
var thrown := false

var _flight := 0.0
var _home: Node
var _exception: PhysicsBody3D


static func create(prop_kind: String, mesh: Mesh, xf: Transform3D) -> ThrowableProp:
	var spec: Dictionary = KINDS[prop_kind]
	var prop := ThrowableProp.new()
	prop.kind = prop_kind
	prop.transform = xf
	prop.mass = spec.mass
	prop.damage = spec.damage
	prop.knockdown = spec.knockdown
	prop.throw_speed = spec.speed
	prop.hold_offset = spec.hold
	prop.continuous_cd = prop_kind == "bottle"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# Hundreds of small desk items aren't worth a pass in the shadow map.
	if prop_kind == "monitor" or prop_kind == "bottle":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prop.add_child(mi)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = spec.size
	shape.shape = box
	shape.position = spec.center
	prop.add_child(shape)
	return prop


func _ready() -> void:
	add_to_group("props")
	collision_layer = LAYER_PROPS
	collision_mask = REST_MASK
	contact_monitor = true
	max_contacts_reported = 4
	sleeping = true
	body_entered.connect(_on_body_entered)
	# Only items in flight need a per-frame check; hundreds sit idle on desks.
	set_physics_process(false)


func can_pick() -> bool:
	return holder == null and not thrown


## Lifts the item over the holder's head (chairs go upside-down).
func pick_up(by: Node3D, hold: Node3D) -> void:
	_land()
	holder = by
	_home = get_parent()
	freeze = true
	collision_layer = 0
	collision_mask = 0
	reparent(hold, false)
	transform = hold_offset


func throw(dir: Vector3, speed: float, by: Node) -> void:
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
	if holder != null:
		return
	sleeping = false
	linear_velocity += push
	angular_velocity += Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
	if push.length() > 4.0:
		_launch(by)


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
	victim.take_hit(dmg, push, knockdown, thrower, kind)
	_land()
