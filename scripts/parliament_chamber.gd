@tool
class_name ParliamentChamber
extends Node3D
## Procedurally builds the debate chamber where the fights happen: a tiered hemicycle of
## desks facing the presidium and speaker's tribune, inside a round walnut-panelled hall
## with glass galleries and a stepped ceiling around a blue-lit dome.
## Everything is generated in code. Change the exports and press "Rebuild chamber".
##
## Layout: the hemicycle is centred on the origin and opens toward -Z, where the presidium
## stands against the flat back wall. Angles are measured from +Z toward +X.

@export_tool_button("Rebuild chamber") var rebuild_action = rebuild

@export_group("Room")
@export var room_radius := 14.0
@export var back_wall_z := -9.8
@export var wall_wood_height := 5.85
@export var ceiling_height := 10.0

@export_group("Hemicycle")
@export var row_count := 6
@export var first_row_radius := 4.2
@export var row_spacing := 1.3
@export var row_rise := 0.32
@export var hemicycle_half_angle := 100.0
@export var aisle_angles := PackedFloat32Array([-50.0, 0.0, 50.0])
@export var aisle_width := 1.1
@export var seat_spacing := 1.0

@export_group("Build")
@export var build_collisions := true
## At runtime the furniture (chairs, desks, monitors, bottles, plants, microphones,
## papers, the flag, counter, presidium desk and tribune) becomes throwable rigid bodies.
@export var physical_props := true
## Off: lighter lighting for integrated GPUs (no SSIL, one shadowed spot, fewer lamps).
@export var high_quality := false
@export var random_seed := 7

const PRESIDIUM_Y := 0.75
const GALLERIES := [Vector2(-94.0, -70.0), Vector2(-28.0, 28.0)]
const ARC_DOORS := [108.75, -108.75]
const CHORD_PILASTERS := [-9.0, -5.7, -2.8, 0.0, 2.8, 5.7, 9.0]
const CHORD_DOORS := [7.35, -7.35]
const WALL_SCREENS := [63.75, -63.75, 123.75, -123.75]
const CEILING_CENTER := Vector3(0.0, 0.0, 0.3)

## Member chairs (position at floor level, +Z facing the chamber floor).
var seat_transforms: Array[Transform3D] = []
## The three presidium chairs plus two secretary chairs.
var presidium_seat_transforms: Array[Transform3D] = []
## Speaker's tribune; the speaker stands on its -Z side.
var tribune_transform := Transform3D.IDENTITY

var _root: Node3D
var _m := {}
var _rng := RandomNumberGenerator.new()
var _corner_deg := 0.0
var _corner_x := 0.0


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	_rng.seed = random_seed
	seat_transforms.clear()
	presidium_seat_transforms.clear()
	_corner_deg = rad_to_deg(acos(clampf(back_wall_z / room_radius, -1.0, 1.0)))
	_corner_x = sqrt(room_radius * room_radius - back_wall_z * back_wall_z)
	_make_materials()
	_build_environment()
	_build_floor()
	_build_hemicycle()
	_build_presidium()
	_build_walls()
	for g in GALLERIES:
		_build_gallery(g.x, g.y)
	_build_ceiling()


# --- Materials ---------------------------------------------------------------

func _make_materials() -> void:
	_m.clear()
	_m.wood = _textured(Color(0.12, 0.055, 0.028), Color(0.3, 0.15, 0.075), Vector3(1.4, 0.12, 1.4), 0.55)
	_m.wood_top = _textured(Color(0.16, 0.08, 0.04), Color(0.34, 0.18, 0.085), Vector3(0.9, 0.9, 0.9), 0.45)
	_m.burl = _textured(Color(0.3, 0.15, 0.065), Color(0.52, 0.3, 0.14), Vector3(1.2, 1.2, 1.2), 0.45, FastNoiseLite.TYPE_CELLULAR)
	if high_quality:
		_m.carpet = _textured(Color(0.6, 0.5, 0.37), Color(0.72, 0.62, 0.47), Vector3(5.0, 5.0, 5.0), 1.0)
		_m.rug = _textured(Color(0.5, 0.36, 0.25), Color(0.62, 0.46, 0.32), Vector3(5.0, 5.0, 5.0), 1.0)
	else:
		_m.carpet = _mat(Color(0.66, 0.56, 0.42), 1.0)
		_m.rug = _mat(Color(0.56, 0.41, 0.28), 1.0)
	_m.gold = _mat(Color(0.86, 0.64, 0.3), 0.3, 1.0)
	_m.leather = _mat(Color(0.55, 0.035, 0.04), 0.42)
	_m.boss_leather = _mat(Color(0.3, 0.05, 0.06), 0.38)
	_m.plaster = _mat(Color(0.93, 0.86, 0.76), 0.92)
	_m.ceiling = _mat(Color(0.95, 0.9, 0.82), 0.9)
	_m.metal = _mat(Color(0.035, 0.035, 0.04), 0.35, 0.4)
	_m.door = _mat(Color(0.05, 0.025, 0.012), 0.6)
	_m.paper = _mat(Color(0.92, 0.92, 0.9), 0.85)
	_m.leaf = _mat(Color(0.1, 0.28, 0.08), 0.7)
	_m.flower = _mat(Color(0.95, 0.93, 0.95), 0.6)
	_m.screen = _emissive(Color(0.16, 0.3, 0.52), 0.9)
	_m.downlight = _emissive(Color(1.0, 0.92, 0.78), 6.0)
	_m.led = _emissive(Color(0.3, 0.6, 1.0), 10.0)
	_m.mic_led = _emissive(Color(1.0, 0.1, 0.05), 3.0)

	var dome := _mat(Color(0.9, 0.94, 1.0), 0.9)
	dome.emission_enabled = true
	dome.emission = Color(0.55, 0.72, 1.0)
	dome.emission_energy_multiplier = 0.35
	_m.dome = dome

	var glass := _mat(Color(0.75, 0.85, 0.9, 0.05), 0.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m.glass = glass

	var bottle := _mat(Color(0.75, 0.88, 1.0, 0.35), 0.1)
	bottle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m.bottle = bottle

	var vote := _mat(Color.WHITE, 1.0)
	vote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vote.albedo_texture = _vote_texture()
	_m.vote = vote

	var stripes := Image.create(1, 3, false, Image.FORMAT_RGBA8)
	stripes.set_pixel(0, 0, Color(0.85, 0.07, 0.12))
	stripes.set_pixel(0, 1, Color(0.0, 0.2, 0.63))
	stripes.set_pixel(0, 2, Color(0.95, 0.66, 0.0))
	var flag := _mat(Color.WHITE, 0.85)
	flag.albedo_texture = ImageTexture.create_from_image(stripes)
	flag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	flag.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m.flag = flag


func _mat(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(Color.BLACK, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Noise-textured material projected in world space, so generated meshes need no UVs.
func _textured(dark: Color, light: Color, scale: Vector3, rough: float, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = kind
	noise.frequency = 0.015
	noise.fractal_octaves = 4
	noise.seed = _rng.randi()
	var grad := Gradient.new()
	grad.set_color(0, dark)
	grad.set_color(1, light)
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	var m := _mat(Color.WHITE, rough)
	m.albedo_texture = tex
	# Triplanar costs three texture reads per pixel; the low profile uses the mesh UVs.
	m.uv1_triplanar = high_quality
	m.uv1_world_triplanar = high_quality
	m.uv1_scale = scale
	return m


## Result board shown on the wall screens: a hemicycle of coloured vote dots.
func _vote_texture() -> ImageTexture:
	var w := 480
	var h := 270
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.05, 0.14))
	img.fill_rect(Rect2i(0, 0, w, 30), Color(0.05, 0.16, 0.38))
	for row in 6:
		var rr := 62.0 + row * 24.0
		var n := 10 + row * 4
		for k in n:
			var f := (k + 0.5) / n
			var a := PI * (1.0 - f)
			var c := Color(0.2, 0.85, 0.35) if f < 0.55 else (Color(0.9, 0.2, 0.2) if f < 0.8 else Color(0.85, 0.85, 0.9))
			_disc(img, w * 0.5 + cos(a) * rr, h - 28.0 - sin(a) * rr, 7.0, c)
	return ImageTexture.create_from_image(img)


func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(floori(cy - r), ceili(cy + r) + 1):
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x - cx, y - cy).length() <= r:
				img.set_pixel(x, y, c)


# --- Environment & lights ----------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.025, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.88, 0.74)
	env.ambient_light_energy = 0.45 if high_quality else 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = high_quality
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = high_quality
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	var world := WorldEnvironment.new()
	world.environment = env
	_root.add_child(world)
	if not high_quality:
		# One shadowless downlight stands in for the ring of ceiling lamps.
		var fill := DirectionalLight3D.new()
		fill.light_color = Color(1.0, 0.9, 0.78)
		fill.light_energy = 0.9
		fill.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(20.0), 0.0)
		_root.add_child(fill)
		if not Engine.is_editor_hint():
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			get_viewport().scaling_3d_scale = 0.8

	var probe := ReflectionProbe.new()
	probe.size = Vector3(30.0, ceiling_height + 3.0, 27.0)
	probe.position = Vector3(0.0, (ceiling_height + 3.0) * 0.5, 2.0)
	probe.box_projection = true
	probe.interior = true
	probe.intensity = 0.6
	_root.add_child(probe)

	# Shadow-casting spots aimed at the benches, the floor and the presidium.
	var spots := [
		[Vector3(-6, 9.6, 6), Vector3(-3, 1, 5)],
		[Vector3(6, 9.6, 6), Vector3(3, 1, 5)],
		[Vector3(0, 9.6, 9), Vector3(0, 0, 0)],
		[Vector3(-4, 9.6, -2), Vector3(-1.5, 1, -6)],
		[Vector3(4, 9.6, -2), Vector3(1.5, 1, -6)],
	]
	for i in spots.size():
		var s: Array = spots[i]
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.9, 0.76)
		spot.light_energy = 3.0
		spot.spot_range = 20.0
		spot.spot_angle = 38.0
		spot.shadow_enabled = high_quality or i == 2
		_root.add_child(spot)
		spot.look_at_from_position(s[0], s[1])


func _omni(pos: Vector3, color: Color, energy: float, range_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.position = pos
	_root.add_child(l)
	return l


# --- Floor & hemicycle -------------------------------------------------------

func _build_floor() -> void:
	_add(_ring(0.0, 30.0, 0.0, 360.0, -0.2, 0.0), _m.carpet)
	# The floor collides as one flat box: far cheaper to query than the disc's triangles.
	if build_collisions:
		var floor_body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(60.0, 0.4, 60.0)
		shape.shape = box
		shape.position = Vector3(0.0, -0.2, 0.0)
		floor_body.add_child(shape)
		_root.add_child(floor_body)
	var rug := Transform3D(Basis(), Vector3(0.0, 0.0, 0.9))
	_add(_ring(0.0, 2.1, 0.0, 360.0, 0.0, 0.006), _m.rug, rug)
	_add(_ring(2.1, 2.25, 0.0, 360.0, 0.0, 0.008), _m.wood, rug)


func _row_radius(i: int) -> float:
	return first_row_radius + row_spacing * i


func _row_floor(i: int) -> float:
	return 0.15 + row_rise * i


func _walkway_y() -> float:
	return _row_floor(row_count)


func _build_hemicycle() -> void:
	var h := hemicycle_half_angle
	var monitors := []
	var mics := []
	var bottles := []
	var papers := []
	var panels := []
	var steps := []

	# Stepped platforms: carpet on top, a thin walnut riser facing the floor.
	for i in row_count:
		var r := _row_radius(i)
		var y := _row_floor(i)
		_add(_ring(r - 0.75, r + 0.55, -h, h, 0.0, y), _m.carpet, Transform3D.IDENTITY, true)
		_add(_ring(r - 0.77, r - 0.75, -h, h, 0.0, y + 0.002), _m.wood)
	var rw := _row_radius(row_count - 1) + 0.55
	_add(_ring(rw, room_radius, -h, h, 0.0, _walkway_y()), _m.carpet, Transform3D.IDENTITY, true)
	_add(_ring(rw - 0.02, rw, -h, h, 0.0, _walkway_y() + 0.002), _m.wood)

	var bounds: Array[float] = [-h]
	for a in aisle_angles:
		bounds.append(a)
	bounds.append(h)

	for i in row_count:
		var r := _row_radius(i)
		var y := _row_floor(i)
		var desk_y := y + 0.78
		for s in bounds.size() - 1:
			var a0 := bounds[s] + rad_to_deg((aisle_width * 0.5 if s > 0 else 0.15) / r)
			var a1 := bounds[s + 1] - rad_to_deg((aisle_width * 0.5 if s < bounds.size() - 2 else 0.15) / r)
			if a1 <= a0:
				continue
			var seat_r := r + 0.12
			var n := maxi(1, floori(deg_to_rad(a1 - a0) * seat_r / seat_spacing))
			if _loose_furniture():
				# One liftable desk piece per seat.
				_desk_pieces(r, y, a0, a1, n)
			else:
				# Continuous curved desk for this sector.
				_add(_ring(r - 0.72, r - 0.28, a0, a1, y, y + 0.74), _m.wood, Transform3D.IDENTITY, true)
				_add(_ring(r - 0.77, r - 0.22, a0, a1, y + 0.74, desk_y), _m.wood_top, Transform3D.IDENTITY, true)
				var np := maxi(1, floori(deg_to_rad(a1 - a0) * (r - 0.72) / 1.05))
				for k in np:
					var t := lerpf(a0, a1, (k + 0.5) / np)
					panels.append(Transform3D(_facing(-_polar(1.0, t)), _polar(r - 0.727, t, y + 0.4)))

			for k in n:
				var t := lerpf(a0, a1, (k + 0.5) / n)
				var out := _polar(1.0, t)
				seat_transforms.append(Transform3D(_facing(-out), _polar(seat_r, t, y)))
				monitors.append(Transform3D(_facing(out), _polar(r - 0.5, t, desk_y)))
				mics.append(Transform3D(_facing(out), _polar(r - 0.4, t - rad_to_deg(0.3 / r), desk_y)))
				if _rng.randf() < 0.55:
					bottles.append(Transform3D(Basis(), _polar(r - 0.62, t + rad_to_deg(0.3 / r), desk_y)))
				if _rng.randf() < 0.4:
					var b := _facing(out).rotated(Vector3.UP, _rng.randf_range(-0.4, 0.4))
					papers.append(Transform3D(b, _polar(r - 0.38, t + rad_to_deg(0.25 / r), desk_y + 0.002)))

	# Half-height steps in the aisles between rows.
	var step_size := Vector3(aisle_width * 0.85, row_rise * 0.5, 0.4)
	for a in aisle_angles:
		for i in row_count:
			var pos := _polar(_row_radius(i) + 0.35, a, _row_floor(i) + step_size.y * 0.5)
			steps.append(Transform3D(_facing(-_polar(1.0, a)), pos))

	_multi(_bm(step_size.x, step_size.y, step_size.z), _m.carpet, steps)
	_multi(_bm(0.78, 0.42, 0.012), _m.burl, panels)
	_props("chair", _member_chair(_m.leather), seat_transforms)
	_props("monitor", _monitor(), monitors)
	_props("mic", _mic(), mics)
	_props("bottle", [_part(_cm(0.032, 0.032, 0.22), _m.bottle, Vector3(0.0, 0.11, 0.0))], bottles)
	_props("paper", [_part(_bm(0.21, 0.003, 0.297), _m.paper, Vector3(0.0, 0.0015, 0.0))], papers)


## Desk pieces for one sector of a row, each centred on its seat. The pieces share one
## mesh: a slice of the curved desk (body, top, burl front panel) around local +Z.
func _desk_pieces(r: float, y: float, a0: float, a1: float, n: int) -> void:
	var half := (a1 - a0) / n * 0.5
	var rc := r - 0.495
	var shift := Transform3D(Basis(), Vector3(0.0, 0.0, -rc))
	var panel_w := minf(0.78, deg_to_rad(half * 2.0) * (r - 0.727) - 0.18)
	var parts := [
		[_ring(r - 0.72, r - 0.28, -half, half, 0.0, 0.74), _m.wood, shift],
		[_ring(r - 0.77, r - 0.22, -half, half, 0.74, 0.78), _m.wood_top, shift],
		[_bm(panel_w, 0.42, 0.012), _m.burl, Transform3D(_facing(Vector3.FORWARD), Vector3(0.0, 0.4, (r - 0.727) - rc))],
	]
	var width := 2.0 * sin(deg_to_rad(half)) * (r - 0.22)
	var boxes := [[Vector3(width, 0.78, 0.55), Vector3(0.0, 0.39, 0.0)]]
	var xforms := []
	for k in n:
		var t := lerpf(a0, a1, (k + 0.5) / n)
		xforms.append(Transform3D(Basis(Vector3.UP, deg_to_rad(t)), _polar(rc, t, y)))
	_props("desk", parts, xforms, boxes)


func _loose_furniture() -> bool:
	return physical_props and not Engine.is_editor_hint()


## Grabbable furniture: physics props at runtime, cheap static instances in the editor.
## Anchored kinds (desks, counter...) also get a navigation stand-in.
func _props(kind: String, parts: Array, xforms: Array, boxes: Array = []) -> void:
	if not _loose_furniture():
		_place(parts, xforms)
		return
	var mesh := _merged_model(parts)
	# Untouched items draw through one shared MultiMesh (see ThrowableProp.batch_into).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if kind in ["monitor", "bottle", "mic", "paper"]:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		mm.set_instance_transform(i, xf)
		var prop := ThrowableProp.create(kind, mesh, xf, boxes)
		_root.add_child(prop)
		prop.batch_into(mm, i)
		if prop.anchored:
			_root.add_child(prop.make_nav_blocker())


# --- Presidium & tribune -----------------------------------------------------

func _build_presidium() -> void:
	var py := PRESIDIUM_Y
	var front := -4.4
	var depth := front - back_wall_z
	var forward := Vector3.BACK
	var toward_chairs := Vector3.FORWARD

	# Raised platform with side steps.
	_box(Vector3(10.0, py, depth), Vector3(0.0, py * 0.5, front - depth * 0.5), _m.wood, true)
	_box(Vector3(9.96, 0.012, depth - 0.04), Vector3(0.0, py + 0.006, front - depth * 0.5), _m.carpet)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.45, py * 0.66, 1.6), Vector3(sx * 5.225, py * 0.33, -6.6), _m.carpet, true)
		_box(Vector3(0.45, py * 0.33, 1.6), Vector3(sx * 5.675, py * 0.165, -6.6), _m.carpet, true)

	if _loose_furniture():
		# The counter and presidium desk come apart in liftable sections.
		var counter := [
			_part(_bm(1.5, 0.95, 0.55), _m.wood, Vector3(0.0, 0.475, 0.0)),
			_part(_bm(1.525, 0.04, 0.65), _m.wood_top, Vector3(0.0, 0.97, 0.0)),
			_part(_bm(1.2, 0.55, 0.012), _m.burl, Vector3(0.0, 0.47, 0.281)),
		]
		var counters := []
		for x in [-2.25, -0.75, 0.75, 2.25]:
			counters.append(_at(Vector3(x, 0.0, -3.825)))
		_props("counter", counter, counters)
		# Section origin on the platform at z = -4.95: front panel ahead, work surface behind.
		var desk := [
			_part(_bm(1.36, 1.2, 0.25), _m.wood, Vector3(0.0, 0.6, 0.225)),
			_part(_bm(1.38, 0.05, 0.4), _m.wood_top, Vector3(0.0, 1.225, 0.25)),
			_part(_bm(1.38, 0.03, 0.02), _m.gold, Vector3(0.0, 1.18, 0.365)),
			_part(_bm(1.32, 0.78, 0.7), _m.wood, Vector3(0.0, 0.39, -0.25)),
			_part(_bm(1.34, 0.04, 0.78), _m.wood_top, Vector3(0.0, 0.8, -0.25)),
			_part(_bm(1.0, 0.75, 0.012), _m.burl, Vector3(0.0, 0.58, 0.356)),
		]
		var desk_boxes := [
			[Vector3(1.38, 1.25, 0.4), Vector3(0.0, 0.625, 0.25)],
			[Vector3(1.34, 0.82, 0.78), Vector3(0.0, 0.41, -0.25)],
		]
		var sections := []
		for x in [-2.72, -1.36, 0.0, 1.36, 2.72]:
			sections.append(_at(Vector3(x, py, -4.95)))
		_props("presidium_desk", desk, sections, desk_boxes)
	else:
		# Staff counter on the floor in front of the platform.
		_box(Vector3(6.0, 0.95, 0.55), Vector3(0.0, 0.475, -3.825), _m.wood, true)
		_box(Vector3(6.1, 0.04, 0.65), Vector3(0.0, 0.97, -3.825), _m.wood_top)
		for x in [-2.25, -0.75, 0.75, 2.25]:
			_box(Vector3(1.2, 0.55, 0.012), Vector3(x, 0.47, -3.544), _m.burl)

		# Presidium desk: a tall panelled front with a lower working surface behind it.
		_box(Vector3(6.8, 1.2, 0.25), Vector3(0.0, py + 0.6, -4.725), _m.wood, true)
		_box(Vector3(6.9, 0.05, 0.4), Vector3(0.0, py + 1.225, -4.7), _m.wood_top)
		_box(Vector3(6.9, 0.03, 0.02), Vector3(0.0, py + 1.18, -4.585), _m.gold)
		_box(Vector3(6.6, 0.78, 0.7), Vector3(0.0, py + 0.39, -5.2), _m.wood, true)
		_box(Vector3(6.7, 0.04, 0.78), Vector3(0.0, py + 0.8, -5.2), _m.wood_top, true)
		for x in [-2.6, -1.3, 0.0, 1.3, 2.6]:
			_box(Vector3(1.0, 0.75, 0.012), Vector3(x, py + 0.58, -4.594), _m.burl)

	var bosses := []
	var secretaries := []
	var monitors := []
	var mics := []
	for x in [-1.5, 0.0, 1.5]:
		bosses.append(Transform3D(_facing(forward), Vector3(x, py, -6.15)))
	for x in [-2.85, 2.85]:
		secretaries.append(Transform3D(_facing(forward), Vector3(x, py, -6.0)))
	for x in [-2.85, -1.5, 0.0, 1.5, 2.85]:
		monitors.append(Transform3D(_facing(toward_chairs), Vector3(x, py + 0.82, -5.1)))
		mics.append(Transform3D(_facing(toward_chairs), Vector3(x + 0.35, py + 0.82, -5.15)))
	presidium_seat_transforms.assign(bosses + secretaries)
	_props("boss_chair", _boss_chair(), bosses)
	_props("chair", _member_chair(_m.leather), secretaries)
	_props("monitor", _monitor(), monitors)
	_props("mic", _mic(), mics)

	# Speaker's tribune on a round dais.
	_add(_cm(1.3, 1.35, 0.12, 48), _m.rug, Transform3D(Basis(), Vector3(0.0, 0.06, -1.6)), true)
	tribune_transform = Transform3D(_facing(forward), Vector3(0.0, 0.12, -1.6))
	if _loose_furniture():
		_props("tribune", _tribune(), [tribune_transform])
	else:
		_place(_tribune(), [tribune_transform])
		_box(Vector3(1.06, 1.1, 0.68), tribune_transform.origin + Vector3(0.0, 0.55, 0.0), null, true).visible = false

	_plant(Vector3(-0.95, 0.12, -2.3))
	_plant(Vector3(0.95, 0.12, -2.3))
	_plant(Vector3(-3.45, 0.0, -3.3))
	_plant(Vector3(3.45, 0.0, -3.3))
	_flag(Vector3(-4.3, py, -8.9))


func _plant(pos: Vector3) -> void:
	var parts := [_part(_cm(0.24, 0.18, 0.42), _m.wood, Vector3(0.0, 0.21, 0.0))]
	for i in 10:
		var o := Vector3(_rng.randf_range(-0.22, 0.22), _rng.randf_range(0.5, 0.85), _rng.randf_range(-0.22, 0.22))
		parts.append(_part(_sm(_rng.randf_range(0.12, 0.2)), _m.leaf, o))
	for i in 7:
		var o := Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0.85, 1.05), _rng.randf_range(-0.2, 0.2))
		parts.append(_part(_sm(0.05), _m.flower, o))
	_props("plant", parts, [Transform3D(Basis(), pos)])


func _flag(base: Vector3) -> void:
	var pole_h := 2.9
	var parts := [
		_part(_cm(0.022, 0.022, pole_h), _m.gold, Vector3(0.0, pole_h * 0.5, 0.0)),
		_part(_sm(0.055), _m.gold, Vector3(0.0, pole_h + 0.04, 0.0)),
		_part(_cm(0.14, 0.18, 0.08), _m.gold, Vector3(0.0, 0.04, 0.0)),
	]

	# Gently drooping cloth: a rippled grid, red/blue/orange stripes top to bottom.
	var cols := 18
	var rows := 3
	var grid := []
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / cols
			var v := float(j) / rows
			var p := Vector3(u * 1.25, -v * 0.62 - u * u * 0.32, sin(u * PI * 2.3) * 0.09 * u)
			grid.append([p, Vector2(u, v)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			for idx in [a, a + 1, a + cols + 2, a, a + cols + 2, a + cols + 1]:
				st.set_uv(grid[idx][1])
				st.add_vertex(grid[idx][0])
	st.generate_normals()
	parts.append([st.commit(), _m.flag, Transform3D(_facing(Vector3(-0.25, 0.0, -1.0)), Vector3(0.0, pole_h - 0.08, 0.0))])
	_props("flag", parts, [_at(base)])


# --- Walls -------------------------------------------------------------------

func _build_walls() -> void:
	var wh := wall_wood_height
	_band(-180.0, 180.0, -0.3, 0.0, 0.0, wh, _m.wood, true)
	# Carved cornice: walnut frieze with gilded fillets and dentils, capped by a moulding.
	_band(-180.0, 180.0, 0.0, 0.26, wh, wh + 0.45, _m.wood)
	_band(-180.0, 180.0, 0.26, 0.272, wh + 0.03, wh + 0.07, _m.gold)
	_band(-180.0, 180.0, 0.26, 0.272, wh + 0.38, wh + 0.42, _m.gold)
	_band(-180.0, 180.0, 0.0, 0.42, wh + 0.45, wh + 0.57, _m.wood)
	_multi(_bm(0.14, 0.2, 0.04), _m.gold, _along_wall(0.32, 0.28, wh + 0.225))
	for span in _complement(GALLERIES):
		_band(span.x, span.y, -0.3, 0.0, wh + 0.57, ceiling_height, _m.plaster)

	# Pilasters every 7.5 degrees on the curved wall, plus fixed spots on the back wall.
	var pil: Array[float] = []
	for k in range(ceili((1.0 - _corner_deg) / 7.5), floori((_corner_deg - 1.0) / 7.5) + 1):
		pil.append(k * 7.5)
	pil.append(-_corner_deg)
	pil.append(_corner_deg)
	for x in CHORD_PILASTERS:
		pil.append(_chord_phi(x))
	pil.sort()

	var shafts := []
	var plinths := []
	var capitals := []
	var corbels := []
	var ornaments := []
	for f in pil:
		var p := _loop_point(f)
		var n := _loop_normal(f)
		var b := _facing(n)
		var fy := _floor_at(f)
		var top := wh - 0.5
		shafts.append(Transform3D(b.scaled_local(Vector3(1.0, top - fy, 1.0)), p + n * 0.06 + Vector3(0.0, (fy + top) * 0.5, 0.0)))
		plinths.append(Transform3D(b, p + n * 0.08 + Vector3(0.0, fy + 0.125, 0.0)))
		capitals.append(Transform3D(b, p + n * 0.08 + Vector3(0.0, top - 0.04, 0.0)))
		corbels.append(Transform3D(b, p + n * 0.13 + Vector3(0.0, top + 0.25, 0.0)))
		ornaments.append(Transform3D(b, p + n * 0.275 + Vector3(0.0, top + 0.25, 0.0)))
	_multi(_bm(0.38, 1.0, 0.12), _m.wood, shafts)
	_multi(_bm(0.44, 0.25, 0.16), _m.wood, plinths)
	_multi(_bm(0.44, 0.08, 0.16), _m.gold, capitals)
	_multi(_bm(0.42, 0.5, 0.26), _m.wood, corbels)
	_multi(_bm(0.26, 0.3, 0.03), _m.gold, ornaments)

	# Raised panels (or doors) between pilasters: a tall upper panel and a low dado panel.
	var doors := []
	doors.append_array(ARC_DOORS)
	for x in CHORD_DOORS:
		doors.append(_chord_phi(x))
	var frames := []
	var burls := []
	for i in pil.size():
		var a := pil[i]
		var b := pil[i + 1] if i + 1 < pil.size() else pil[0] + 360.0
		var p0 := _loop_point(a)
		var p1 := _loop_point(b)
		var width := p0.distance_to(p1)
		var mid := (p0 + p1) * 0.5
		var seg := p1 - p0
		var n := Vector3(-seg.z, 0.0, seg.x).normalized()
		if n.dot(mid) > 0.0:
			n = -n
		var fy := maxf(_floor_at(a), _floor_at(b))
		var is_door := false
		for d in doors:
			is_door = is_door or _between(d, a, b)
		if is_door:
			_door(mid, n, fy, minf(1.6, width - 0.62))
			continue
		if width < 1.0:
			continue
		var w := (width - 0.38) * 0.8
		var pb := _facing(n)
		for rect in [Vector2(fy + 1.55, wh - 0.75), Vector2(fy + 0.3, fy + 1.25)]:
			var ph: float = rect.y - rect.x
			if ph < 0.6:
				continue
			var c := mid + Vector3(0.0, (rect.x + rect.y) * 0.5, 0.0)
			frames.append(Transform3D(pb.scaled_local(Vector3(w, ph, 1.0)), c + n * 0.02))
			burls.append(Transform3D(pb.scaled_local(Vector3(w - 0.16, ph - 0.16, 1.0)), c + n * 0.045))
	_multi(_bm(1.0, 1.0, 0.04), _m.wood, frames)
	_multi(_bm(1.0, 1.0, 0.02), _m.burl, burls)

	# Vote result screens high on the panelling.
	for f in WALL_SCREENS:
		var n := _loop_normal(f)
		var xf := Transform3D(_facing(n), _loop_point(f) + n * 0.1 + Vector3(0.0, 4.35, 0.0))
		_add(_bm(2.5, 1.45, 0.08), _m.metal, xf)
		var quad := QuadMesh.new()
		quad.size = Vector2(2.38, 1.33)
		_add(quad, _m.vote, xf * Transform3D(Basis(), Vector3(0.0, 0.0, 0.041)))

	# Air vents in the plaster.
	var vents := []
	for f in range(-180, 180, 15):
		var blocked := false
		for g in GALLERIES:
			blocked = blocked or _between(f, g.x - 3.0, g.y + 3.0)
		if not blocked:
			var n := _loop_normal(f)
			vents.append(Transform3D(_facing(n), _loop_point(f) + n * 0.01 + Vector3(0.0, 8.3, 0.0)))
	_multi(_bm(0.8, 0.22, 0.02), _m.metal, vents)


func _door(pos: Vector3, n: Vector3, fy: float, w: float) -> void:
	var xf := Transform3D(_facing(n), pos + Vector3(0.0, fy, 0.0))
	var h := 2.5
	var r := w * 0.5
	var arch := xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, h, 0.0))
	_add(_bm(w, h, 0.03), _m.door, xf * _at(Vector3(0.0, h * 0.5, 0.015)))
	_add(_ring(0.0, r, -90.0, 90.0, -0.03, 0.0), _m.door, arch)
	_add(_ring(0.0, r - 0.05, -90.0, 90.0, -0.05, -0.03), _m.burl, arch)
	for sx in [-1.0, 1.0]:
		_add(_bm(r - 0.03, h - 0.06, 0.03), _m.burl, xf * _at(Vector3(sx * r * 0.5, h * 0.5, 0.045)))
		_add(_bm(0.03, 0.25, 0.03), _m.gold, xf * _at(Vector3(sx * 0.08, 1.05, 0.075)))
		_add(_bm(0.12, h, 0.12), _m.wood, xf * _at(Vector3(sx * (r + 0.06), h * 0.5, 0.06)))
	_add(_ring(r, r + 0.12, -90.0, 90.0, -0.12, 0.0), _m.wood, arch)
	_add(_ring(r + 0.12, r + 0.22, -90.0, 90.0, -0.07, 0.0), _m.gold, arch)
	_add(_bm(0.16, 0.26, 0.1), _m.gold, xf * _at(Vector3(0.0, h + r + 0.12, 0.08)))


# --- Galleries & ceiling -----------------------------------------------------

## Glass-fronted visitor gallery recessed into the upper wall between angles a and b.
func _build_gallery(a: float, b: float) -> void:
	var r := room_radius
	var rg := r + 2.6
	var fy := wall_wood_height + 0.57
	var top := ceiling_height - 0.45
	_add(_ring(r, rg, a, b, fy - 0.2, fy), _m.carpet, Transform3D.IDENTITY, true)
	_add(_ring(r + 1.25, rg, a + 0.5, b - 0.5, fy, fy + 0.3), _m.carpet)
	_add(_ring(rg, rg + 0.3, a - 1.5, b + 1.5, fy - 0.2, ceiling_height), _m.plaster)
	_add(_ring(r, rg + 0.3, a - 1.5, b + 1.5, top, ceiling_height), _m.plaster)
	_add(_ring(r, rg, a - 1.5, a, fy - 0.2, top), _m.plaster)
	_add(_ring(r, rg, b, b + 1.5, fy - 0.2, top), _m.plaster)
	_add(_ring(r - 0.14, r, a, b, fy, fy + 0.85), _m.wood)
	_add(_ring(r - 0.16, r + 0.02, a, b, fy + 0.85, fy + 0.9), _m.gold)
	_add(_ring(r - 0.06, r - 0.05, a, b, fy + 0.9, top), _m.glass)

	var mullions := []
	var count := maxi(1, floori((b - a) / 6.0))
	var mh := top - fy - 0.9
	for k in count + 1:
		mullions.append(Transform3D(_facing(-_polar(1.0, lerpf(a, b, float(k) / count))), _polar(r - 0.055, lerpf(a, b, float(k) / count), fy + 0.9 + mh * 0.5)))
	_multi(_bm(0.05, mh, 0.06), _m.metal, mullions)

	var chairs := []
	for row in [[r + 0.7, fy], [r + 1.85, fy + 0.3]]:
		var cr: float = row[0]
		var n := floori(deg_to_rad(b - a - 2.0) * cr / 0.75)
		for k in n:
			var t := lerpf(a + 1.0, b - 1.0, (k + 0.5) / n)
			chairs.append(Transform3D(_facing(-_polar(1.0, t)), _polar(cr, t, row[1])))
	_props("chair", _member_chair(_m.leather), chairs)
	_omni(_polar(r + 1.3, (a + b) * 0.5, top - 0.3), Color(1.0, 0.85, 0.65), 0.6, 5.0)


func _build_ceiling() -> void:
	var c := Transform3D(Basis(), CEILING_CENTER)
	var y0 := ceiling_height
	var y1 := y0 + 0.6
	var y2 := y1 + 0.55
	var y3 := y2 + 1.25
	# Concentric steps rising toward a dome, with a blue LED cove hidden behind the last lip.
	_add(_ring(10.0, 26.0, 0.0, 360.0, y0, y1), _m.ceiling, c)
	_add(_ring(8.0, 10.0, 0.0, 360.0, y1, y2), _m.ceiling, c)
	_add(_ring(6.6, 8.0, 0.0, 360.0, y2, y3), _m.ceiling, c)
	_add(_ring(6.0, 6.6, 0.0, 360.0, y2, y2 + 0.1), _m.ceiling, c)
	_add(_ring(6.25, 6.5, 0.0, 360.0, y2 + 0.1, y2 + 0.12), _m.led, c)
	_add(_ring(0.0, 6.8, 0.0, 360.0, y3, y3 + 0.1), _m.dome, c)
	for edge in [Vector2(10.0, y0), Vector2(8.0, y1), Vector2(6.0, y2)]:
		_add(_ring(edge.x - 0.04, edge.x + 0.02, 0.0, 360.0, edge.y - 0.05, edge.y), _m.gold, c)
	if high_quality:
		for k in 8:
			_omni(CEILING_CENTER + _polar(6.2, k * 45.0, y2 + 0.5), Color(0.35, 0.6, 1.0), 3.0, 4.0)

	# Recessed downlights; every third one on the inner rings is a real light.
	var lights := []
	for ring in [Vector2(12.2, y0), Vector2(11.0, y0), Vector2(9.0, y1), Vector2(7.3, y2)]:
		var n := roundi(TAU * ring.x / 1.5)
		for k in n:
			var p := CEILING_CENTER + _polar(ring.x, 360.0 * k / n, ring.y - 0.012)
			if not _inside_room(p, 0.5):
				continue
			lights.append(Transform3D(Basis(), p))
			if high_quality and k % 3 == 0 and ring.x < 12.0:
				_omni(p - Vector3(0.0, 0.5, 0.0), Color(1.0, 0.86, 0.68), 1.3, 8.0)
	_multi(_cm(0.1, 0.1, 0.02, 12), _m.downlight, lights)


# --- Furniture models (front faces +Z) ----------------------------------------

func _member_chair(red: Material) -> Array:
	return [
		_part(_bm(0.54, 0.12, 0.5), red, Vector3(0.0, 0.47, 0.03)),
		_part(_bm(0.52, 0.7, 0.12), red, Vector3(0.0, 0.9, -0.25), Vector3(-10.0, 0.0, 0.0)),
		_part(_bm(0.08, 0.07, 0.44), red, Vector3(-0.3, 0.68, 0.0)),
		_part(_bm(0.08, 0.07, 0.44), red, Vector3(0.3, 0.68, 0.0)),
		_part(_bm(0.035, 0.18, 0.035), _m.metal, Vector3(-0.3, 0.56, 0.05)),
		_part(_bm(0.035, 0.18, 0.035), _m.metal, Vector3(0.3, 0.56, 0.05)),
		_part(_cm(0.035, 0.035, 0.36), _m.metal, Vector3(0.0, 0.23, 0.0)),
		_part(_cm(0.27, 0.3, 0.05, 5), _m.metal, Vector3(0.0, 0.035, 0.0)),
	]


func _boss_chair() -> Array:
	var c: Material = _m.boss_leather
	return [
		_part(_bm(0.72, 0.16, 0.62), c, Vector3(0.0, 0.5, 0.04)),
		_part(_bm(0.74, 1.15, 0.2), c, Vector3(0.0, 1.15, -0.3), Vector3(-8.0, 0.0, 0.0)),
		_part(_bm(0.78, 0.16, 0.26), c, Vector3(0.0, 1.75, -0.38), Vector3(-8.0, 0.0, 0.0)),
		_part(_bm(0.13, 0.26, 0.6), c, Vector3(-0.42, 0.68, 0.02)),
		_part(_bm(0.13, 0.26, 0.6), c, Vector3(0.42, 0.68, 0.02)),
		_part(_cm(0.04, 0.04, 0.4), _m.metal, Vector3(0.0, 0.22, 0.0)),
		_part(_cm(0.32, 0.34, 0.05, 5), _m.metal, Vector3(0.0, 0.035, 0.0)),
	]


func _monitor() -> Array:
	var tilt := Vector3(-12.0, 0.0, 0.0)
	var head := Vector3(0.0, 0.3, -0.02)
	var screen_pos := head + Basis.from_euler(tilt * (PI / 180.0)) * Vector3(0.0, 0.0, 0.0135)
	return [
		_part(_bm(0.2, 0.015, 0.15), _m.metal, Vector3(0.0, 0.008, -0.02)),
		_part(_bm(0.035, 0.2, 0.025), _m.metal, Vector3(0.0, 0.11, -0.04)),
		_part(_bm(0.46, 0.3, 0.025), _m.metal, head, tilt),
		_part(_bm(0.42, 0.26, 0.004), _m.screen, screen_pos, tilt),
	]


func _mic() -> Array:
	var a := deg_to_rad(35.0)
	var lean := Vector3(35.0, 0.0, 0.0)
	return [
		_part(_cm(0.035, 0.045, 0.025), _m.metal, Vector3(0.0, 0.0125, 0.0)),
		_part(_cm(0.006, 0.006, 0.36), _m.metal, Vector3(0.0, cos(a) * 0.18, sin(a) * 0.18), lean),
		_part(_cm(0.013, 0.011, 0.06), _m.metal, Vector3(0.0, cos(a) * 0.39, sin(a) * 0.39), lean),
		_part(_cm(0.0135, 0.0135, 0.008), _m.mic_led, Vector3(0.0, cos(a) * 0.355, sin(a) * 0.355), lean),
	]


func _tribune() -> Array:
	var a := deg_to_rad(35.0)
	var lean := Vector3(-35.0, 0.0, 0.0)
	var mic_base := Vector3(0.3, 1.12, 0.12)
	return [
		_part(_bm(1.0, 1.05, 0.62), _m.wood, Vector3(0.0, 0.525, 0.0)),
		_part(_bm(1.06, 0.08, 0.68), _m.wood, Vector3(0.0, 0.04, 0.0)),
		_part(_bm(0.7, 0.62, 0.012), _m.burl, Vector3(0.0, 0.55, 0.316)),
		_part(_bm(0.74, 0.03, 0.014), _m.gold, Vector3(0.0, 0.9, 0.318)),
		_part(_bm(1.12, 0.05, 0.74), _m.wood_top, Vector3(0.0, 1.08, -0.02), Vector3(-9.0, 0.0, 0.0)),
		_part(_cm(0.006, 0.006, 0.4), _m.metal, mic_base + Vector3(0.0, cos(a) * 0.2, -sin(a) * 0.2), lean),
		_part(_cm(0.013, 0.011, 0.06), _m.metal, mic_base + Vector3(0.0, cos(a) * 0.43, -sin(a) * 0.43), lean),
	]


# --- Wall loop: arc of radius room_radius closed by the straight back wall ----
# A wall position is a single angle phi: |phi| <= corner is the curved wall,
# anything else maps linearly along the straight wall behind the presidium.

func _loop_point(phi: float) -> Vector3:
	var p := wrapf(phi, -180.0, 180.0)
	if absf(p) <= _corner_deg:
		return _polar(room_radius, p)
	var u := ((p if p > 0.0 else p + 360.0) - _corner_deg) / (360.0 - 2.0 * _corner_deg)
	return Vector3(lerpf(_corner_x, -_corner_x, u), 0.0, back_wall_z)


func _loop_normal(phi: float) -> Vector3:
	var p := wrapf(phi, -180.0, 180.0)
	if absf(absf(p) - _corner_deg) < 0.05:
		return (-_polar(1.0, p) + Vector3.BACK).normalized()
	return -_polar(1.0, p) if absf(p) < _corner_deg else Vector3.BACK


func _chord_phi(x: float) -> float:
	return _corner_deg + (_corner_x - x) / (2.0 * _corner_x) * (360.0 - 2.0 * _corner_deg)


func _floor_at(phi: float) -> float:
	var p := wrapf(phi, -180.0, 180.0)
	if absf(p) <= hemicycle_half_angle:
		return _walkway_y()
	var pt := _loop_point(phi)
	if absf(pt.z - back_wall_z) < 0.01 and absf(pt.x) < 5.0:
		return PRESIDIUM_Y
	return 0.0


func _between(phi: float, a: float, b: float) -> bool:
	var v := a + fposmod(phi - a, 360.0)
	return v > a and v < b


func _inside_room(p: Vector3, margin: float) -> bool:
	return p.z > back_wall_z + margin and Vector2(p.x, p.z).length() < room_radius - margin


func _complement(gaps: Array) -> Array:
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(l, r): return l.x < r.x)
	var out := []
	for i in sorted.size():
		var start: float = sorted[i].y
		var stop: float = sorted[(i + 1) % sorted.size()].x
		if stop <= start:
			stop += 360.0
		out.append(Vector2(start, stop))
	return out


func _loop_samples(a: float, b: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(1, ceili((b - a) / 2.5))
	for i in n + 1:
		out.append(lerpf(a, b, float(i) / n))
	for k in range(-2, 3):
		for c in [_corner_deg, -_corner_deg]:
			var v: float = c + 360.0 * k
			if v > a + 0.05 and v < b - 0.05:
				out.append(v)
	out.sort()
	return out


func _along_wall(spacing: float, inset: float, y: float) -> Array:
	var out := []
	var prev := _loop_point(-180.0)
	var acc := spacing * 0.5
	var f := -180.0
	while f < 180.0:
		f += 0.1
		var p := _loop_point(f)
		acc += p.distance_to(prev)
		prev = p
		if acc >= spacing:
			acc -= spacing
			var n := _loop_normal(f)
			out.append(Transform3D(_facing(n), p + n * inset + Vector3(0.0, y, 0.0)))
	return out


## Extrudes a horizontal band following the wall between angles a and b.
## Insets are measured inward from the wall line; the visible face sits at in1.
func _band(a: float, b: float, in0: float, in1: float, y0: float, y1: float, mat: Material, collide := false) -> void:
	var pts: Array[Vector3] = []
	for f in _loop_samples(a, b):
		var p := _loop_point(f)
		if pts.is_empty() or pts[-1].distance_to(p) > 0.01:
			pts.append(p)
	var closed := b - a >= 359.99
	var seg_n: Array[Vector3] = []
	for i in pts.size() - 1:
		var d := pts[i + 1] - pts[i]
		var n := Vector3(-d.z, 0.0, d.x).normalized()
		if n.dot(pts[i] + pts[i + 1]) > 0.0:
			n = -n
		seg_n.append(n)
	var last := seg_n.size() - 1
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	var vn: Array[Vector3] = []
	for i in pts.size():
		var n_prev := seg_n[i - 1] if i > 0 else (seg_n[last] if closed else seg_n[0])
		var n_next := seg_n[i] if i <= last else (seg_n[0] if closed else seg_n[last])
		var n := (n_prev + n_next).normalized()
		var miter := 1.0 / maxf(0.35, n.dot(n_next))
		vn.append(n)
		inner.append(pts[i] + n * in1 * miter)
		outer.append(pts[i] + n * in0 * miter)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3(0.0, y1, 0.0)
	var dn := Vector3(0.0, y0, 0.0)
	for i in pts.size() - 1:
		_quad(st, inner[i] + dn, inner[i + 1] + dn, inner[i + 1] + up, inner[i] + up, vn[i], vn[i + 1], vn[i + 1], vn[i])
		_quad(st, outer[i] + up, outer[i + 1] + up, inner[i + 1] + up, inner[i] + up, Vector3.UP)
		_quad(st, outer[i] + dn, outer[i + 1] + dn, inner[i + 1] + dn, inner[i] + dn, Vector3.DOWN)
	if not closed:
		var e := last + 1
		_quad(st, outer[0] + dn, inner[0] + dn, inner[0] + up, outer[0] + up, (pts[0] - pts[1]).normalized())
		_quad(st, outer[e] + dn, inner[e] + dn, inner[e] + up, outer[e] + up, (pts[e] - pts[e - 1]).normalized())
	_add(st.commit(), mat, Transform3D.IDENTITY, collide)


# --- Geometry helpers --------------------------------------------------------

func _polar(r: float, deg: float, y := 0.0) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(sin(a) * r, y, cos(a) * r)


## Upright basis whose +Z points along dir (flattened to the floor plane).
func _facing(dir: Vector3) -> Basis:
	var z := Vector3(dir.x, 0.0, dir.z).normalized()
	return Basis(Vector3.UP.cross(z), Vector3.UP, z)


func _at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(), pos)


## Solid annular sector around the local Y axis.
func _ring(r0: float, r1: float, a0: float, a1: float, y0: float, y1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := a1 - a0
	var seg := maxi(2, ceili(absf(span) / 2.5))
	for i in seg:
		var d0 := _polar(1.0, a0 + span * i / seg)
		var d1 := _polar(1.0, a0 + span * (i + 1) / seg)
		_quad(st, d0 * r0 + Vector3(0, y1, 0), d1 * r0 + Vector3(0, y1, 0), d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0), Vector3.UP)
		_quad(st, d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0), d1 * r1 + Vector3(0, y0, 0), d0 * r1 + Vector3(0, y0, 0), Vector3.DOWN)
		_quad(st, d0 * r1 + Vector3(0, y0, 0), d1 * r1 + Vector3(0, y0, 0), d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0), d0, d1, d1, d0)
		if r0 > 0.001:
			_quad(st, d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y1, 0), d0 * r0 + Vector3(0, y1, 0), -d0, -d1, -d1, -d0)
	if absf(span) < 359.9:
		for end in [Vector2(a0, -1.0), Vector2(a1, 1.0)]:
			var d := _polar(1.0, end.x)
			var t: Vector3 = Vector3(d.z, 0.0, -d.x) * end.y * signf(span)
			_quad(st, d * r0 + Vector3(0, y0, 0), d * r1 + Vector3(0, y0, 0), d * r1 + Vector3(0, y1, 0), d * r0 + Vector3(0, y1, 0), t)
	return st.commit()


## Adds a quad, flipping the winding so its front face points along the given normal(s).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb := Vector3.ZERO, nc := Vector3.ZERO, nd := Vector3.ZERO) -> void:
	if nb == Vector3.ZERO:
		nb = na
		nc = na
		nd = na
	var vs := [a, b, c, d]
	var ns := [na, nb, nc, nd]
	# Godot treats clockwise triangles as front-facing.
	var order := [0, 1, 2, 0, 2, 3]
	if (c - a).cross(d - b).dot(na + nb + nc + nd) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		var v: Vector3 = vs[i]
		st.set_normal(ns[i])
		st.set_uv(Vector2(v.x + v.z, v.y))
		st.add_vertex(v)


func _add(mesh: Mesh, mat: Material, xf := Transform3D.IDENTITY, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	_root.add_child(mi)
	if collide and build_collisions:
		mi.create_trimesh_collision()
	return mi


func _box(size: Vector3, center: Vector3, mat: Material, collide := false) -> MeshInstance3D:
	return _add(_bm(size.x, size.y, size.z), mat, _at(center), collide)


func _multi(mesh: Mesh, mat: Material, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	_root.add_child(mmi)


## Instances a multi-part model (from _part) at every transform.
func _place(parts: Array, xforms: Array) -> void:
	for p in parts:
		var local: Transform3D = p[2]
		var list := []
		for t in xforms:
			list.append(t * local)
		_multi(p[0], p[1], list)


## Bakes a multi-part model into one mesh with a surface per material.
func _merged_model(parts: Array) -> ArrayMesh:
	var tools := {}
	for p in parts:
		var mat: Material = p[1]
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(p[0], 0, p[2])
	var mesh := ArrayMesh.new()
	for mat in tools:
		(tools[mat] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> Array:
	return [mesh, mat, Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)]


func _bm(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _cm(top: float, bottom: float, height: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = seg
	c.rings = 1
	return c


func _sm(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s
