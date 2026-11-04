class_name CharacterAnimations
extends RefCounted
## Mixamo clips shared by every imported character (all Mixamo-rigged, so the bone names
## match). Loaded once from res://animations/<name>.fbx; any missing clip is simply
## skipped and that motion falls back to the code-driven animation.
##
##   idle, idle_fight      standing still (calm / in a fight)
##   walk, run             locomotion, exported "in place"
##   jab, cross, hook      the punch combo (left, right, big right)
##   kick                  the kick
##   throw                 two-handed overhead throw
##   getup_back/front      getting up after a knockdown

const ROOT := "res://animations/"
const NAMES := ["idle", "idle_fight", "walk", "run", "jab", "cross", "hook", "kick", "throw", "getup_back", "getup_front"]

## Where each strike lands in its clip (seconds), measured from the clips; the game
## lines this up with the moment its own hit is counted.
const IMPACT := {"jab": 0.57, "cross": 0.37, "hook": 0.37, "kick": 0.73, "throw": 1.45}
## Which clip plays for each attack in Brawler.ATTACKS.
const FOR_ATTACK := {"punch1": "cross", "punch2": "jab", "punch3": "hook", "kick": "kick", "throw": "throw"}

class Clip:
	var anim: Animation
	var length := 1.0
	## bone name -> rotation track
	var rot := {}
	## The clip's own skeleton, parents first: bone names, parent list index (-1 for
	## the root), rest local and rest global rotations, rotation track (-1 if none).
	var src_names: Array[String] = []
	var src_parent: PackedInt32Array = []
	var src_rest_local: Array[Quaternion] = []
	var src_rest_global: Array[Quaternion] = []
	var src_rest_pos: Array[Vector3] = []
	var src_track: PackedInt32Array = []
	var hips_name := ""
	var hips_pos := -1

	func hips_at(t: float) -> Vector3:
		return anim.position_track_interpolate(hips_pos, t) if hips_pos >= 0 else Vector3.ZERO


static var clips := {}
## Standing hips height in clip units (from the idle clip), to scale hip movement.
static var hip_height := 0.0
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for n in NAMES:
		var path: String = ROOT + n + ".fbx"
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var players := root.find_children("*", "AnimationPlayer", true, false)
		var skeletons := root.find_children("*", "Skeleton3D", true, false)
		if players.is_empty() or skeletons.is_empty():
			root.free()
			continue
		var ap := players[0] as AnimationPlayer
		var sk := skeletons[0] as Skeleton3D
		var list := ap.get_animation_list()
		if list.is_empty():
			root.free()
			continue
		var clip := Clip.new()
		clip.anim = ap.get_animation(list[0])
		clip.length = maxf(clip.anim.length, 0.01)
		for i in clip.anim.get_track_count():
			var bone := str(clip.anim.track_get_path(i)).get_slice(":", 1)
			var idx := sk.find_bone(bone)
			if idx < 0:
				continue
			match clip.anim.track_get_type(i):
				Animation.TYPE_ROTATION_3D:
					clip.rot[bone] = i
				Animation.TYPE_POSITION_3D:
					if sk.get_bone_parent(idx) < 0 or bone.to_lower().ends_with("hips"):
						clip.hips_pos = i
						clip.hips_name = bone
		_read_skeleton(clip, sk)
		clips[n] = clip
		root.free()
	if clips.has("idle") and (clips.idle as Clip).hips_pos >= 0:
		hip_height = (clips.idle as Clip).hips_at(0.0).y


static func _read_skeleton(clip: Clip, sk: Skeleton3D) -> void:
	var count := sk.get_bone_count()
	var depth := PackedInt32Array()
	depth.resize(count)
	for i in count:
		var d := 0
		var p := sk.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = sk.get_bone_parent(p)
		depth[i] = d
	var order: Array[int] = []
	for i in count:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return depth[a] < depth[b])
	var slot := {}
	for i in order:
		slot[i] = clip.src_names.size()
		var bone_name := sk.get_bone_name(i)
		clip.src_names.append(bone_name)
		var parent := sk.get_bone_parent(i)
		clip.src_parent.append(slot[parent] if parent >= 0 else -1)
		var rest := sk.get_bone_rest(i)
		clip.src_rest_local.append(rest.basis.orthonormalized().get_rotation_quaternion())
		clip.src_rest_global.append(sk.get_bone_global_rest(i).basis.orthonormalized().get_rotation_quaternion())
		clip.src_rest_pos.append(sk.get_bone_global_rest(i).origin)
		clip.src_track.append(clip.rot.get(bone_name, -1))


static func has(n: String) -> bool:
	ensure_loaded()
	return clips.has(n)
