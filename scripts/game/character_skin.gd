class_name CharacterSkin
extends Node3D
## Dresses a Brawler in an imported model (FBX, glTF...) instead of the blocky body.
##
## The Brawler keeps animating and ragdolling its invisible procedural rig; every frame
## this copies that rig onto the model's skeleton: hips, head, upper/lower arms and legs
## follow their rig joints (or, while knocked down, the ragdoll bodies), and every other
## bone (spine, hands, feet, fingers) rides along with its parent.
##
## When Mixamo clips are present in res://animations/ (see CharacterAnimations), they
## take over while the brawler is on its feet: idle/walk/run blended by speed, the punch
## combo, kick and throw, and the get-up after a knockdown. The rig still drives the arms
## while carrying something overhead, and the ragdoll still owns the body while down.
##
## Works with Mixamo rigs, Godot's humanoid bone names and the usual Blender/Unreal names.
## The model is turned to face -Z, stood upright and scaled to the brawler's height
## automatically. A model without a skeleton is attached rigidly to the hips.

const TARGET_HEIGHT := 1.82

## Rig joint -> accepted bone names (compared lowercase, letters and digits only, with
## prefixes such as "mixamorig:" or "DEF-" removed).
const BONES := {
	"hips": ["hips", "pelvis", "hip", "root_hips"],
	"head": ["head"],
	"arm_l": ["leftarm", "leftupperarm", "upperarml", "lupperarm", "arml", "larm", "upperarmleft"],
	"arm_r": ["rightarm", "rightupperarm", "upperarmr", "rupperarm", "armr", "rarm", "upperarmright"],
	"forearm_l": ["leftforearm", "leftlowerarm", "lowerarml", "forearml", "lforearm", "llowerarm", "elbowl"],
	"forearm_r": ["rightforearm", "rightlowerarm", "lowerarmr", "forearmr", "rforearm", "rlowerarm", "elbowr"],
	"thigh_l": ["leftupleg", "leftupperleg", "thighl", "upperlegl", "lthigh", "lupperleg", "legupperl"],
	"thigh_r": ["rightupleg", "rightupperleg", "thighr", "upperlegr", "rthigh", "rupperleg", "legupperr"],
	"shin_l": ["leftleg", "leftlowerleg", "calfl", "shinl", "lowerlegl", "lcalf", "llowerleg", "kneel", "leglowerl"],
	"shin_r": ["rightleg", "rightlowerleg", "calfr", "shinr", "lowerlegr", "rcalf", "rlowerleg", "kneer", "leglowerr"],
}
const PREFIXES := ["mixamorig", "def", "orgbip", "bip01", "bip001", "armature", "skeleton", "rig", "valvebiped"]

var brawler: Brawler
var model: Node3D
var skeleton: Skeleton3D

## Rig joint (Node3D pivot) for each mapped bone, plus what is needed to pose it.
var _drive := {}           # bone index -> {"pivot", "align": Basis, "rest_g": Transform3D}
var _root_bone := -1       # the hips bone, which also takes its position from the rig
var _root_offset := Transform3D.IDENTITY
var _order: PackedInt32Array = []
var _rest_local: Array[Transform3D] = []
var _sk_in_rig := Transform3D.IDENTITY   # skeleton frame expressed in the rig frame
var _sk_rot := Basis.IDENTITY
var _rest_rig := {}        # pivot -> its rest transform in the rig frame
var _rigid_offset := Transform3D.IDENTITY
var _ok := false

## Clip playback (see _pose_animated).
var _anim := false
## clip name -> {"map": PackedInt32Array (target bone -> clip skeleton slot, -1 none),
##               "fix": Array[Quaternion] (per target bone, see _bind_clips)}
var _bind := {}
var _arm_bones: Array[int] = []
var _rest_q: Array[Quaternion] = []
var _hips_scale := 1.0     # clip hip units -> this skeleton's units
var _idle_t := 0.0
var _phase := 0.0
var _act_clip := ""
var _act_time := 0.0
var _act_w := 0.0
var _loco_w := 0.0
var _run_w := 0.0
var _fight_w := 0.0
## Finger curl (the clips have no finger tracks): [bone, local curl axis, segment 1-3,
## is_thumb, local swing axis]. The swing turns the thumb's base in alongside the fingers
## (in the T-pose it points straight out sideways). _fist blends relaxed (0) to a fist (1).
var _fingers := []
var _fist := 0.0


static func create(scene: PackedScene, owner_brawler: Brawler) -> CharacterSkin:
	var skin := CharacterSkin.new()
	skin.name = "CharacterSkin"
	skin.brawler = owner_brawler
	skin.model = scene.instantiate() as Node3D
	if skin.model != null:
		# Imported clips would fight the rig for the bones.
		for ap in skin.model.find_children("*", "AnimationPlayer", true, false):
			(ap as AnimationPlayer).autoplay = ""
	return skin


func _ready() -> void:
	if model == null or brawler == null or brawler._rig == null:
		push_warning("CharacterSkin: nothing to dress")
		return
	add_child(model)
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	for at in model.find_children("*", "AnimationTree", true, false):
		(at as AnimationTree).active = false
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	_fit_model()
	_record_rig_rest()
	if skeleton != null and _map_bones():
		_prepare_skeleton()
	else:
		if skeleton != null:
			push_warning("CharacterSkin: couldn't find humanoid bones in %s; attaching it rigidly" % model.scene_file_path)
		skeleton = null
		_prepare_rigid()
	for pivot in brawler._meshes:
		(brawler._meshes[pivot] as Node3D).visible = false
	if skeleton != null:
		_bind_clips()
		_find_fingers()
	_ok = true
	_pose(0.0)


# --- Setup -------------------------------------------------------------------

## Upright, facing -Z, feet on the floor, about TARGET_HEIGHT tall.
func _fit_model() -> void:
	model.transform = Transform3D.IDENTITY
	var basis := Basis.IDENTITY
	if skeleton != null:
		var b := _find_bones()
		if b.has("hips") and b.has("head") and b.has("thigh_l") and b.has("thigh_r"):
			var to_model := _node_in(skeleton, model)
			var up := to_model.basis * (_bone_rest_g(b.head).origin - _bone_rest_g(b.hips).origin)
			var right := to_model.basis * (_bone_rest_g(b.thigh_r).origin - _bone_rest_g(b.thigh_l).origin)
			if up.length() > 0.0001 and right.length() > 0.0001:
				up = up.normalized()
				right = (right - up * right.dot(up)).normalized()
				var back := right.cross(up)
				# Columns are where the model's right/up/back point; rotate them onto +X/+Y/+Z.
				basis = Basis(right, up, back).inverse()
	model.transform = Transform3D(basis, Vector3.ZERO)
	var box := _model_aabb()
	if box.size.y > 0.0001:
		var s := TARGET_HEIGHT / box.size.y
		model.transform = Transform3D(Basis.from_scale(Vector3.ONE * s) * basis, Vector3.ZERO)
		box = _model_aabb()
		var c := box.get_center()
		model.position = Vector3(-c.x, -box.position.y, -c.z)


func _model_aabb() -> AABB:
	var points := PackedVector3Array()
	for node in model.find_children("*", "VisualInstance3D", true, false):
		if not node is GeometryInstance3D:
			continue
		var vi := node as VisualInstance3D
		var mi := vi as MeshInstance3D
		if mi != null and mi.skin != null and mi.mesh != null and skeleton != null:
			_skinned_points(mi, points)
		else:
			var box := _node_in(vi, self) * vi.get_aabb()
			for i in 8:
				points.append(box.get_endpoint(i))
	if points.is_empty():
		return AABB()
	var out := AABB(points[0], Vector3.ZERO)
	for p in points:
		out = out.expand(p)
	return out


## A skinned mesh's own bounds can be far off (bind poses often carry the import scale,
## e.g. x100 for centimetre FBX files), so measure the vertices as the skin places them.
func _skinned_points(mi: MeshInstance3D, points: PackedVector3Array) -> void:
	var skin := mi.skin
	var binds: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(b))
		var rest := skeleton.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		binds.append(rest * skin.get_bind_pose(b))
	var to_self := _node_in(skeleton, self)
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones == null or weights == null or bones.size() == 0:
			continue
		var per := int(bones.size() / verts.size())
		var step := maxi(1, verts.size() / 4000)
		for v in range(0, verts.size(), step):
			# The vertex's heaviest bone is close enough for a bounding box.
			var best := 0
			for k in range(1, per):
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			var bind: int = bones[v * per + best]
			if bind >= 0 and bind < binds.size():
				points.append(to_self * (binds[bind] * verts[v]))


## Where every rig joint sits before any animation (joints are built unrotated).
func _record_rig_rest() -> void:
	var rig := brawler._rig
	for pivot in brawler._meshes:
		var p := pivot as Node3D
		var pos := Vector3.ZERO
		var n: Node = p
		while n != null and n != rig:
			pos += (n as Node3D).position
			n = n.get_parent()
		_rest_rig[p] = Transform3D(Basis.IDENTITY, pos)


func _find_bones() -> Dictionary:
	var by_name := {}
	for i in skeleton.get_bone_count():
		for variant in _name_variants(skeleton.get_bone_name(i)):
			if not by_name.has(variant):
				by_name[variant] = i
	var out := {}
	for slot in BONES:
		for candidate in BONES[slot]:
			if by_name.has(candidate):
				out[slot] = by_name[candidate]
				break
	return out


func _map_bones() -> bool:
	var b := _find_bones()
	for need in ["hips", "arm_l", "arm_r", "forearm_l", "forearm_r", "thigh_l", "thigh_r", "shin_l", "shin_r"]:
		if not b.has(need):
			return false
	var pivots := {
		"hips": brawler._hips, "head": brawler._head,
		"arm_l": brawler._shoulders[0], "arm_r": brawler._shoulders[1],
		"forearm_l": brawler._elbows[0], "forearm_r": brawler._elbows[1],
		"thigh_l": brawler._legs[0], "thigh_r": brawler._legs[1],
		"shin_l": brawler._knees[0], "shin_r": brawler._knees[1],
	}
	# The rig's limbs hang straight down and its torso stands straight up; each bone is
	# turned so that its rest direction matches (T-pose arms come down to the sides).
	var aim := {
		"hips": [b.get("head", -1), Vector3.UP],
		"arm_l": [b.forearm_l, Vector3.DOWN], "arm_r": [b.forearm_r, Vector3.DOWN],
		"forearm_l": [_first_child(b.forearm_l), Vector3.DOWN], "forearm_r": [_first_child(b.forearm_r), Vector3.DOWN],
		"thigh_l": [b.shin_l, Vector3.DOWN], "thigh_r": [b.shin_r, Vector3.DOWN],
		"shin_l": [_first_child(b.shin_l), Vector3.DOWN], "shin_r": [_first_child(b.shin_r), Vector3.DOWN],
	}
	_sk_in_rig = _node_in(skeleton, brawler._rig)
	_sk_rot = _sk_in_rig.basis.orthonormalized()
	for slot in b:
		var bone: int = b[slot]
		var align := Basis.IDENTITY
		if aim.has(slot) and int(aim[slot][0]) >= 0:
			var from := _bone_rest_g(int(aim[slot][0])).origin - _bone_rest_g(bone).origin
			var to: Vector3 = _sk_rot.inverse() * (aim[slot][1] as Vector3)
			if from.length() > 0.0001 and from.normalized().dot(to) > -0.999:
				align = Basis(Quaternion(from.normalized(), to.normalized()))
		_drive[bone] = {"pivot": pivots[slot], "align": align}
	_root_bone = b.hips
	# The hips bone is glued to the hips joint (rest pose to rest pose).
	var hips_rest_rig: Transform3D = _rest_rig[brawler._hips]
	var bone_rest_rig := _sk_in_rig * _bone_rest_g(_root_bone)
	_root_offset = hips_rest_rig.affine_inverse() * bone_rest_rig
	return true


func _prepare_skeleton() -> void:
	var count := skeleton.get_bone_count()
	_rest_local.resize(count)
	var depth := PackedInt32Array()
	depth.resize(count)
	for i in count:
		_rest_local[i] = skeleton.get_bone_rest(i)
		var d := 0
		var p := skeleton.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = skeleton.get_bone_parent(p)
		depth[i] = d
	var idx: Array[int] = []
	for i in count:
		idx.append(i)
	idx.sort_custom(func(a: int, c: int) -> bool: return depth[a] < depth[c])
	_order = PackedInt32Array(idx)
	# Skinned meshes can get culled by their (rest pose) bounds while the body flies around.
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).extra_cull_margin = 2.0


## Prepares each clip for this skeleton. Clips move bones as rotations away from the
## clip skeleton's rest pose (a perfect T-pose); those are applied, in world space, to this
## skeleton's own rest pose. Bone axes differ between rigs (Tripo hands especially), so
## copying local rotations straight across twists wrists; this doesn't care about axes.
## Each bone's rest direction is also lined up with the clip's first, so arms that rest
## angled down (a loose T-pose) still end up where the clip puts them.
func _bind_clips() -> void:
	CharacterAnimations.ensure_loaded()
	if CharacterAnimations.clips.is_empty():
		return
	var count := skeleton.get_bone_count()
	_rest_q.resize(count)
	var tgt_rest_g: Array[Quaternion] = []
	tgt_rest_g.resize(count)
	for i in count:
		_rest_q[i] = _rest_local[i].basis.get_rotation_quaternion()
		tgt_rest_g[i] = _bone_rest_g(i).basis.orthonormalized().get_rotation_quaternion()
	for n in CharacterAnimations.clips:
		var clip: CharacterAnimations.Clip = CharacterAnimations.clips[n]
		var by_name := {}
		for k in clip.src_names.size():
			for v in _name_variants(clip.src_names[k]):
				if not by_name.has(v):
					by_name[v] = k
		var map := PackedInt32Array()
		map.resize(count)
		var matched := 0
		for i in count:
			map[i] = -1
			for v in _name_variants(skeleton.get_bone_name(i)):
				if by_name.has(v):
					map[i] = by_name[v]
					break
			# Only bones the clip animates are retargeted; the rest (fingers, ends) keep
			# this model's own shape relative to their parent. Lining fingers up with the
			# clip skeleton's wide-spread T-pose fingers made hands claw-like.
			if map[i] >= 0 and clip.src_track[map[i]] < 0:
				map[i] = -1
			if map[i] >= 0:
				matched += 1
		if matched < 10:
			continue
		var fix: Array[Quaternion] = []
		fix.resize(count)
		for i in count:
			fix[i] = Quaternion.IDENTITY
			var k := map[i]
			if k < 0:
				continue
			# Line this bone's rest direction up with the clip's (toward a matching child).
			var align := Quaternion.IDENTITY
			var child := _aim_child(i, map, clip)
			if child >= 0:
				var mine := (_bone_rest_g(child).origin - _bone_rest_g(i).origin).normalized()
				var theirs := (clip.src_rest_pos[map[child]] - clip.src_rest_pos[k]).normalized()
				if mine.length() > 0.5 and theirs.length() > 0.5 and mine.dot(theirs) > -0.99:
					align = Quaternion(mine, theirs)
			# Posed = clip's posed global * fix, where fix = clip rest^-1 * align * my rest.
			fix[i] = clip.src_rest_global[k].inverse() * align * tgt_rest_g[i]
		_bind[n] = {"map": map, "fix": fix}
	_anim = _bind.has("idle") or _bind.has("idle_fight")
	if not _anim:
		return
	# Arms the rig keeps while something is carried overhead.
	for bone in _drive:
		var pivot: Node3D = _drive[bone].pivot
		if pivot in brawler._shoulders or pivot in brawler._elbows:
			_arm_bones.append(bone)
	# Hip height of this skeleton (above its lowest bone, about the soles) vs the clips'.
	var low := INF
	for i in skeleton.get_bone_count():
		low = minf(low, _bone_rest_g(i).origin.y)
	var mine := _bone_rest_g(_root_bone).origin.y - low
	if CharacterAnimations.hip_height > 0.001 and mine > 0.001:
		_hips_scale = mine / CharacterAnimations.hip_height
	if _bind.has("getup_back") or _bind.has("getup_front"):
		brawler.getup_time = 1.3


## Finds the finger bones and, per bone, the axis that curls it toward the palm.
## Fingers otherwise stay frozen straight out as in the T-pose, thumb sticking sideways.
func _find_fingers() -> void:
	if _rest_local.is_empty():
		return
	for side in ["left", "right"]:
		var hand := -1
		var index1 := -1
		var pinky1 := -1
		var middle1 := -1
		var bones := []
		for i in skeleton.get_bone_count():
			for v in _name_variants(skeleton.get_bone_name(i)):
				if v == side + "hand":
					hand = i
				elif v.begins_with(side + "hand"):
					var rest := v.substr((side + "hand").length())
					for f in ["thumb", "index", "middle", "ring", "pinky"]:
						if rest.begins_with(f) and rest.length() == f.length() + 1:
							var seg := rest.right(1).to_int()
							if seg >= 1 and seg <= 3:
								bones.append([i, seg, f == "thumb"])
							if f == "index" and seg == 1:
								index1 = i
							if f == "pinky" and seg == 1:
								pinky1 = i
							if f == "middle" and seg == 1:
								middle1 = i
		if hand < 0 or index1 < 0:
			continue
		var h := _bone_rest_g(hand).origin
		# One-chain hands (Tripo) have no pinky to find the palm from: T-pose palms face down.
		var n := Vector3.DOWN
		if pinky1 >= 0:
			n = (_bone_rest_g(index1).origin - h).cross(_bone_rest_g(pinky1).origin - h).normalized()
		# T-pose palms face the floor.
		if n.y > 0.0:
			n = -n
		var mid_dir := Vector3.ZERO
		if middle1 >= 0 and not skeleton.get_bone_children(middle1).is_empty():
			mid_dir = (_bone_rest_g(skeleton.get_bone_children(middle1)[0]).origin - _bone_rest_g(middle1).origin).normalized()
		var index_kids := skeleton.get_bone_children(index1)
		var finger_dir := (_bone_rest_g(index_kids[0]).origin - _bone_rest_g(index1).origin).normalized() if not index_kids.is_empty() else Vector3.ZERO
		for entry in bones:
			var bone: int = entry[0]
			var kids := skeleton.get_bone_children(bone)
			if kids.is_empty():
				continue
			var g := _bone_rest_g(bone)
			var dir := (_bone_rest_g(kids[0]).origin - g.origin).normalized()
			var axis := dir.cross(n)
			if axis.length() < 0.001:
				continue
			var inv := g.basis.orthonormalized().inverse()
			var local_axis := (inv * axis.normalized()).normalized()
			var swing := Vector3.ZERO
			var swing_angle := 0.0
			if entry[2] and entry[1] == 1 and finger_dir != Vector3.ZERO:
				var s_axis := dir.cross(finger_dir)
				if s_axis.length() > 0.001:
					swing = (inv * s_axis.normalized()).normalized()
					swing_angle = 1.0
			elif not entry[2] and entry[1] == 1 and mid_dir != Vector3.ZERO:
				# Fingers modelled spread apart are drawn in alongside the middle finger.
				var a_axis := dir.cross(mid_dir)
				var gap := dir.angle_to(mid_dir)
				if a_axis.length() > 0.001 and gap > 0.02:
					swing = (inv * a_axis.normalized()).normalized()
					swing_angle = -gap * 0.85
			# One chain carrying all four fingers can't fold as far without creasing.
			var reach := 1.0 if pinky1 >= 0 else 0.55
			_fingers.append([bone, local_axis, entry[1], entry[2], swing, swing_angle, reach])


## Curl angle for a finger segment: relaxed hands at 0, a fist at 1.
func _curl(segment: int, thumb: bool, fist: float) -> float:
	if thumb:
		return lerpf([0.0, 0.15, 0.25, 0.25][segment], [0.0, 0.45, 0.6, 0.5][segment], fist)
	return lerpf([0.0, 0.3, 0.45, 0.35][segment], [0.0, 1.35, 1.55, 1.1][segment], fist)


## The finger segment's local rotation from the rest pose.
func _finger_turn(f: Array, fist: float) -> Quaternion:
	var angle := _curl(f[2], f[3], fist * float(f[6]))
	if float(f[6]) < 1.0 and int(f[2]) == 3:
		angle *= 0.4   # one-chain fingertips crease into a hook if folded fully
	var q := Quaternion(f[1] as Vector3, angle)
	if f[4] != Vector3.ZERO:
		if f[3]:
			# Thumb: turned in toward the fingers, further for a fist.
			q = Quaternion(f[4] as Vector3, lerpf(0.5, 0.8, fist)) * q
		else:
			q = Quaternion(f[4] as Vector3, -float(f[5])) * q
	return q


## The child bone used to line a bone's rest direction up with the clip's: one that
## exists in both skeletons, preferring the spine for the hips and the middle or index
## finger for hands.
func _aim_child(bone: int, map: PackedInt32Array, clip: CharacterAnimations.Clip) -> int:
	var best := -1
	var best_rank := 99
	for c in skeleton.get_bone_children(bone):
		if map[c] < 0 or clip.src_parent[map[c]] != map[bone]:
			continue
		var nm := skeleton.get_bone_name(c).to_lower()
		var rank := 5
		for j in ["spine", "neck", "head", "middle", "index"].size():
			if nm.contains(["spine", "neck", "head", "middle", "index"][j]):
				rank = j
				break
		if nm.contains("thumb"):
			rank = 9
		if rank < best_rank:
			best = c
			best_rank = rank
	return best


func _prepare_rigid() -> void:
	model.top_level = true
	var hips_rest: Transform3D = _rest_rig[brawler._hips]
	_rigid_offset = hips_rest.affine_inverse() * _node_in(model, brawler._rig)


# --- Every frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	if _ok:
		_pose(delta)


func _pose(delta: float) -> void:
	if _anim and brawler._ragdoll == null and not brawler.seated and not brawler._cowering:
		_pose_animated(delta)
		return
	var rig_g := brawler._rig.get_global_transform_interpolated()
	var rig_inv := rig_g.affine_inverse()
	if skeleton == null:
		var src := _source(brawler._hips)
		model.global_transform = src.get_global_transform_interpolated() * _rigid_offset
		return
	var sk_inv_rot := _sk_rot.inverse()
	var globals: Array[Transform3D] = []
	globals.resize(_rest_local.size())
	for bone in _order:
		var parent := skeleton.get_bone_parent(bone)
		var parent_g := globals[parent] if parent >= 0 else Transform3D.IDENTITY
		var g := parent_g * _finger_rest(bone, 0.0)
		if _drive.has(bone):
			var d: Dictionary = _drive[bone]
			var pivot: Node3D = d.pivot
			# The joint's current transform in the rig frame (rest = unrotated).
			var now := rig_inv * _source(pivot).get_global_transform_interpolated()
			var turn := sk_inv_rot * now.basis.orthonormalized() * _sk_rot
			g.basis = turn * (d.align as Basis) * _bone_rest_g(bone).basis
			if bone == _root_bone:
				g.origin = _sk_in_rig.affine_inverse() * (now.orthonormalized() * _root_offset).origin
		globals[bone] = g
		var local := parent_g.affine_inverse() * g
		skeleton.set_bone_pose_position(bone, local.origin)
		skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone, local.basis.get_scale())


## Clip-driven pose: a base of idle (calm or fighting) blended toward walk and run by
## speed, an attack clip on top, or the get-up clip while recovering from a knockdown.
func _pose_animated(delta: float) -> void:
	var b := brawler
	var speed := Vector3(b.velocity.x, 0.0, b.velocity.z).length()
	var k := clampf(delta * 8.0, 0.0, 1.0)
	_loco_w = lerpf(_loco_w, clampf(speed / 1.4, 0.0, 1.0), k)
	_run_w = lerpf(_run_w, clampf((speed - 2.4) / 2.0, 0.0, 1.0), k)
	_fight_w = lerpf(_fight_w, 1.0 if (b.in_combat() and _bind.has("idle_fight")) else 0.0, k)
	_idle_t += delta
	# One shared stride phase, so walk and run stay in step while blending.
	var cycle := lerpf(1.75, 3.1, _run_w)
	_phase = fposmod(_phase + delta * speed / cycle, 1.0)

	# Attack layer: map the game's attack progress onto the clip so the impacts coincide.
	var target_act := 0.0
	if b._attack != "" and CharacterAnimations.FOR_ATTACK.has(b._attack):
		var clip_name: String = CharacterAnimations.FOR_ATTACK[b._attack]
		if _bind.has(clip_name):
			var spec: Dictionary = Brawler.ATTACKS[b._attack]
			var p := b._attack_t / float(spec.time)
			var clip: CharacterAnimations.Clip = CharacterAnimations.clips[clip_name]
			var impact: float = CharacterAnimations.IMPACT.get(clip_name, clip.length * 0.4)
			var window := float(spec.time) * 1.7
			var hit := float(spec.hit) if b._attack != "throw" else 0.0
			_act_clip = clip_name
			_act_time = clampf(impact + (p - hit) * window, 0.0, clip.length)
			target_act = 1.0
	_act_w = move_toward(_act_w, target_act, delta * (14.0 if target_act > 0.0 else 7.0))

	# Getting up after a knockdown overrides everything.
	var getup := ""
	var getup_t := 0.0
	if b._recover > 0.0:
		var g_name := "getup_back" if b.got_up_on_back else "getup_front"
		if _bind.has(g_name):
			getup = g_name
			var gclip: CharacterAnimations.Clip = CharacterAnimations.clips[g_name]
			# The clips end with a long settle; play their active part over the recovery.
			var prog := 1.0 - b._recover / maxf(b.getup_time * b.getup_mult, 0.01)
			getup_t = prog * gclip.length * 0.62

	var holding := b.is_holding() and b._attack != "throw"
	_fist = lerpf(_fist, 1.0 if (b.in_combat() or b._attack != "" or b.is_holding()) else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	var count := _rest_q.size()
	var local_q: Array[Quaternion] = []
	local_q.resize(count)
	for i in count:
		local_q[i] = _rest_q[i]
	if getup != "":
		_sample_into(local_q, getup, getup_t, 1.0)
	else:
		var base := "idle" if _bind.has("idle") else "idle_fight"
		_sample_into(local_q, base, fmod(_idle_t, (CharacterAnimations.clips[base] as CharacterAnimations.Clip).length), 1.0)
		if base == "idle" and _fight_w > 0.01:
			_sample_into(local_q, "idle_fight", fmod(_idle_t, (CharacterAnimations.clips.idle_fight as CharacterAnimations.Clip).length), _fight_w)
		if _bind.has("walk") and _loco_w > 0.01:
			_sample_into(local_q, "walk", _phase * (CharacterAnimations.clips.walk as CharacterAnimations.Clip).length, _loco_w)
		if _bind.has("run") and _run_w > 0.01 and _loco_w > 0.01:
			_sample_into(local_q, "run", _phase * (CharacterAnimations.clips.run as CharacterAnimations.Clip).length, _run_w * _loco_w)
		if _act_clip != "" and _act_w > 0.01:
			_sample_into(local_q, _act_clip, _act_time, _act_w)

	for f in _fingers:
		local_q[f[0]] = local_q[f[0]] * _finger_turn(f, _fist)

	# Hips height follows the clips (crouches, bobbing), scaled to this skeleton.
	var hips_local := _rest_local[_root_bone]
	var hips_pos := hips_local.origin
	if getup != "":
		var gc: CharacterAnimations.Clip = CharacterAnimations.clips[getup]
		hips_pos += (gc.hips_at(getup_t) - gc.hips_at(gc.length)) * _hips_scale
	elif CharacterAnimations.hip_height > 0.0:
		var dy := 0.0
		if _act_clip != "" and _act_w > 0.01:
			var ac: CharacterAnimations.Clip = CharacterAnimations.clips[_act_clip]
			dy = (ac.hips_at(_act_time).y - CharacterAnimations.hip_height) * _act_w
		hips_pos.y += dy * _hips_scale

	# Procedural pieces: overhead arms while carrying, and while getting up the rig's own
	# lying-down tilt is cancelled so the clip alone stands the body up.
	var rig_g := b._rig.get_global_transform_interpolated()
	var rig_inv := rig_g.affine_inverse()
	var sk_inv_rot := _sk_rot.inverse()
	var cancel := Transform3D.IDENTITY
	if getup != "":
		cancel = _sk_in_rig.affine_inverse() * b._rig.transform.affine_inverse() * _sk_in_rig
	var globals: Array[Transform3D] = []
	globals.resize(count)
	for bone in _order:
		var parent := skeleton.get_bone_parent(bone)
		var parent_g := globals[parent] if parent >= 0 else cancel
		var origin := hips_pos if bone == _root_bone else _rest_local[bone].origin
		var g := parent_g * Transform3D(Basis(local_q[bone]), origin)
		if holding and bone in _arm_bones:
			var d: Dictionary = _drive[bone]
			var now := rig_inv * _source(d.pivot as Node3D).get_global_transform_interpolated()
			var turn := sk_inv_rot * now.basis.orthonormalized() * _sk_rot
			g.basis = turn * (d.align as Basis) * _bone_rest_g(bone).basis
		globals[bone] = g
		var local := parent_g.affine_inverse() * g
		skeleton.set_bone_pose_position(bone, local.origin)
		skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone, local.basis.get_scale())


## Blends a clip's pose at time t into the per-bone local rotations by weight w.
func _sample_into(local_q: Array[Quaternion], clip_name: String, t: float, w: float) -> void:
	var clip: CharacterAnimations.Clip = CharacterAnimations.clips[clip_name]
	var bind: Dictionary = _bind[clip_name]
	var map: PackedInt32Array = bind.map
	var fix: Array[Quaternion] = bind.fix
	# The clip skeleton's posed global rotations.
	var n := clip.src_names.size()
	var src_g: Array[Quaternion] = []
	src_g.resize(n)
	for k in n:
		var track := clip.src_track[k]
		var lq := clip.anim.rotation_track_interpolate(track, t).normalized() if track >= 0 else clip.src_rest_local[k]
		var parent := clip.src_parent[k]
		src_g[k] = src_g[parent] * lq if parent >= 0 else lq
	# This skeleton's locals that reproduce them.
	var count := _rest_q.size()
	var my_g: Array[Quaternion] = []
	my_g.resize(count)
	for bone in _order:
		var parent := skeleton.get_bone_parent(bone)
		var parent_g := my_g[parent] if parent >= 0 else Quaternion.IDENTITY
		var lq: Quaternion
		var k := map[bone]
		if k >= 0:
			var g := (src_g[k] * fix[bone]).normalized()
			lq = (parent_g.inverse() * g).normalized()
			my_g[bone] = g
		else:
			lq = _rest_q[bone]
			my_g[bone] = parent_g * lq
		local_q[bone] = lq if w >= 0.999 else local_q[bone].slerp(lq, w)


## A bone's rest transform, with finger bones curled (used by the rig-driven pose).
func _finger_rest(bone: int, fist: float) -> Transform3D:
	var t := _rest_local[bone]
	for f in _fingers:
		if f[0] == bone:
			t.basis = t.basis * Basis(_finger_turn(f, fist))
			break
	return t


## The node that carries a joint: its (hidden) mesh follows the joint while standing and
## is moved onto the matching ragdoll body while knocked down.
func _source(pivot: Node3D) -> Node3D:
	return brawler._meshes.get(pivot, pivot) as Node3D


# --- Helpers -------------------------------------------------------------------

func _bone_rest_g(bone: int) -> Transform3D:
	return skeleton.get_bone_global_rest(bone)


func _first_child(bone: int) -> int:
	var kids := skeleton.get_bone_children(bone)
	return kids[0] if not kids.is_empty() else -1


## A node's transform relative to an ancestor, from local transforms (no tree queries).
func _node_in(node: Node3D, ancestor: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## "mixamorig1:LeftArm" -> ["leftarm"], "DEF-upper_arm.L" -> ["defupperarml", "upperarml"].
## The plain cleaned name always comes first, so "RightArm" isn't mistaken for "rig" + "htarm".
static func _name_variants(bone_name: String) -> Array[String]:
	var s := bone_name.to_lower()
	var colon := s.rfind(":")
	if colon >= 0:
		s = s.substr(colon + 1)
	var clean := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			clean += ch
	var out: Array[String] = [clean]
	for p in PREFIXES:
		if clean.begins_with(p) and clean.length() > p.length():
			var rest := clean.substr(p.length())
			while rest.length() > 0 and rest[0] >= "0" and rest[0] <= "9":
				rest = rest.substr(1)
			if rest != "" and not rest in out:
				out.append(rest)
	return out
