extends Node3D
## Riot game mode: throw the first punch, keep the chamber in uproar and rack up chaos
## points before the session clock runs out, while security tries to remove you.
## Debug capture: Godot --path . -- --shot=<file.png>  (starts the riot by itself)

const SESSION_TIME := 180.0
const MP_COUNT := 72
const MAX_GUARDS := 8
## Points for landing a thrown item (before the combo multiplier). Base points also
## count as XP toward the next level.
const THROW_POINTS := {"body": 100, "chair": 75, "monitor": 60, "plant": 60, "bottle": 25,
	"mic": 20, "paper": 10, "boss_chair": 100, "flag": 90, "desk": 150, "counter": 175,
	"presidium_desk": 200, "tribune": 250}
const FIRST_NAMES := ["Aram", "Narek", "Ani", "Lilit", "Tigran", "Gor", "Mane", "Davit", "Karen", "Hayk",
	"Sona", "Arsen", "Mariam", "Levon", "Anahit", "Vahe", "Nune", "Samvel", "Gayane", "Artur"]
const LAST_NAMES := ["Petrosyan", "Hakobyan", "Sargsyan", "Grigoryan", "Harutyunyan", "Mkrtchyan",
	"Avetisyan", "Vardanyan", "Karapetyan", "Ghazaryan", "Manukyan", "Hovhannisyan"]
const SKIN := [Color(0.93, 0.78, 0.65), Color(0.85, 0.68, 0.53), Color(0.74, 0.56, 0.42), Color(0.6, 0.43, 0.3)]
const HAIR := [Color(0.06, 0.04, 0.03), Color(0.18, 0.11, 0.06), Color(0.45, 0.43, 0.42), Color(0.75, 0.74, 0.72), Color(0.3, 0.18, 0.08)]

@onready var chamber: ParliamentChamber = $ParliamentChamber

var player: PlayerBrawler
var hud: Hud
var npcs: Array[NpcBrawler] = []
var exits: Array[Vector3] = []

var score := 0
var multiplier := 1
var time_left := SESSION_TIME
var chaos := 0.0
var riot := false
var over := false
var knockouts := 0
var throw_hits := 0
var bounties := 0
var bounty: NpcBrawler

var _mult_left := 0.0
var _escalate := 0.0
var _guard_timer := 6.0
var _heavy_msg_cd := 0.0
var _skills: SkillPanel
var _pause: PauseMenu


func _ready() -> void:
	_setup_input()
	exits = [Vector3(7.35, 0.0, -9.2), Vector3(-7.35, 0.0, -9.2), _polar(13.2, 108.75), _polar(13.2, -108.75)]
	_bake_navigation()
	hud = Hud.new()
	add_child(hud)
	if TouchControls.wanted():
		var touch := TouchControls.new()
		touch.game = self
		add_child(touch)
	_spawn_members()
	# Pick a character first, unless there is nothing to pick from, it was already picked
	# (restarting with R keeps it) or this is a debug capture.
	if CharacterRoster.list().size() > 1 and not CharacterRoster.has_selected and _shot_path() == "":
		hud.visible = false
		var select := CharacterSelect.new()
		select.chosen.connect(_begin)
		add_child(select)
	else:
		_begin(CharacterRoster.selected_path)


func _begin(character_path: String) -> void:
	hud.visible = true
	_spawn_player(character_path)
	hud.show_message("The session is in order. For now.\nThrow the first punch.", 6.0)
	if _shot_path() != "":
		_capture(_shot_path())


# --- Setup -------------------------------------------------------------------

func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("jump", [KEY_SPACE])
	_bind("sprint", [KEY_SHIFT])
	_bind("grab", [KEY_E])
	_bind("punch", [KEY_J], MOUSE_BUTTON_LEFT)
	_bind("kick", [KEY_K], MOUSE_BUTTON_RIGHT)
	_bind("restart", [KEY_R])
	_bind("change_character", [KEY_C])
	_bind("skills", [KEY_TAB])


func _bind(action: StringName, keys: Array, mouse_button := MOUSE_BUTTON_NONE) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	if mouse_button != MOUSE_BUTTON_NONE:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse_button
		InputMap.action_add_event(action, mb)


## Bakes walkable areas (floor, tiers, aisles, presidium steps) from the chamber's colliders.
func _bake_navigation() -> void:
	# Fine 5 cm cells and no ledge filter: with coarser cells the 0.15-0.32 m tier risers
	# were baked as walls and cut the seating rows off from the floor, so nobody could
	# follow the player up between the desks.
	var nav := NavigationMesh.new()
	nav.cell_size = 0.05
	nav.filter_ledge_spans = false
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.05)
	nav.cell_height = 0.05
	# At least the people's own radius (0.28), so paths keep shoulders clear of desk corners.
	nav.agent_radius = 0.3
	nav.agent_height = 1.6
	nav.agent_max_climb = 0.38
	nav.agent_max_slope = 40.0
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Anchored furniture is a frozen rigid body, so it's baked through its stand-in.
	nav.geometry_collision_mask = Brawler.LAYER_WORLD | ThrowableProp.LAYER_NAV
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav.geometry_source_group_name = &"nav_source"
	nav.filter_baking_aabb = AABB(Vector3(-15.0, -0.5, -10.5), Vector3(30.0, 4.0, 26.0))
	chamber.add_to_group("nav_source")
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav
	add_child(region)
	var t0 := Time.get_ticks_msec()
	region.bake_navigation_mesh(true)
	print_verbose("navigation baked in %d ms" % (Time.get_ticks_msec() - t0))


func _spawn_members() -> void:
	var seats := chamber.seat_transforms.duplicate()
	seats.shuffle()
	for i in mini(MP_COUNT, seats.size()):
		var xf: Transform3D = seats[i]
		var fac := Brawler.Faction.VELVET if xf.origin.x < 0.0 else Brawler.Faction.IRON
		if randf() < 0.15:
			fac = Brawler.Faction.INDEPENDENT
		var mp := _make_member(fac)
		mp.seat_at(xf)
		_add_npc(mp)
	for i in mini(3, chamber.presidium_seat_transforms.size()):
		var chair := _make_member(Brawler.Faction.INDEPENDENT)
		chair.aggression = 0.3
		chair.seat_at(chamber.presidium_seat_transforms[i])
		_add_npc(chair)
	var speaker := _make_member(Brawler.Faction.VELVET if randf() < 0.5 else Brawler.Faction.IRON)
	speaker.state = NpcBrawler.State.SPEAK
	speaker.gesturing = true
	speaker.transform = Transform3D(Basis(Vector3.UP, PI), chamber.tribune_transform.origin + Vector3(0.0, 0.05, -0.6))
	_add_npc(speaker)


func _make_member(fac: Brawler.Faction) -> NpcBrawler:
	var mp := NpcBrawler.new()
	mp.faction = fac
	mp.display_name = "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()]
	var suit := Color(0.33, 0.24, 0.16)
	var tie := Color(0.1, 0.45, 0.25)
	if fac == Brawler.Faction.VELVET:
		suit = Color(0.09, 0.12, 0.26)
		tie = Color(0.7, 0.08, 0.12)
	elif fac == Brawler.Faction.IRON:
		suit = Color(0.2, 0.2, 0.22)
		tie = Color(0.88, 0.62, 0.1)
	mp.build_body(suit.lightened(randf() * 0.12), tie, SKIN.pick_random(), HAIR.pick_random(), false, randf_range(0.93, 1.07))
	mp.aggression = randf_range(0.35, 0.95)
	mp.max_health = 45.0
	mp.health = mp.max_health
	mp.move_speed = randf_range(2.8, 3.6)
	mp.base_damage = 6.0
	mp.exits.assign(exits)
	return mp


func _make_guard(pos: Vector3) -> NpcBrawler:
	var g := NpcBrawler.new()
	g.faction = Brawler.Faction.SECURITY
	g.is_guard = true
	g.display_name = "Security"
	g.build_body(Color(0.06, 0.08, 0.15), Color(0.02, 0.02, 0.02), SKIN.pick_random(), HAIR[0], true, 1.08)
	g.max_health = 90.0
	g.health = g.max_health
	g.move_speed = 3.9
	g.base_damage = 9.0
	g.position = pos
	g.state = NpcBrawler.State.FIGHT
	return g


func _add_npc(npc: NpcBrawler) -> void:
	add_child(npc)
	npcs.append(npc)
	npc.hit_landed.connect(_on_hit_landed)
	npc.knocked_down.connect(_on_knocked_down)


func _spawn_player(character_path := "") -> void:
	player = PlayerBrawler.new()
	CharacterRoster.dress(player, character_path)
	Progression.apply_to(player)
	player.position = Vector3(0.0, 0.05, 2.6)
	add_child(player)
	player.hit_landed.connect(_on_hit_landed)
	player.knocked_down.connect(_on_knocked_down)
	player.lift_failed.connect(_on_lift_failed)


# --- Riot flow -----------------------------------------------------------------

func _start_riot() -> void:
	if riot:
		return
	riot = true
	hud.show_message("ORDER! ORDER!\nThe chamber erupts!", 3.0)
	for n in _members_near(player.global_position, 7.0):
		n.rouse(0.8)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or _skills != null or _pause != null:
		return
	if event.is_action_pressed("skills"):
		get_viewport().set_input_as_handled()
		_open_skills()
	elif event.is_action_pressed("ui_cancel") and not over:
		get_viewport().set_input_as_handled()
		_open_pause()


func _open_pause() -> void:
	_pause = PauseMenu.new()
	_pause.can_change_character = CharacterRoster.list().size() > 1
	_pause.resumed.connect(func() -> void: _pause = null)
	_pause.skills_requested.connect(_open_skills)
	_pause.restart_requested.connect(func() -> void:
		Progression.save()
		get_tree().reload_current_scene())
	_pause.change_character_requested.connect(func() -> void:
		Progression.save()
		CharacterRoster.has_selected = false
		get_tree().reload_current_scene())
	add_child.call_deferred(_pause)


func _open_skills() -> void:
	if _skills != null:
		return
	_skills = SkillPanel.new()
	# Opened from the pause menu the game is already paused; it stays paused after.
	_skills.pause_game = _pause == null
	_skills.closed.connect(_on_skills_closed)
	if _pause != null:
		_pause.set_covered(true)
	add_child.call_deferred(_skills)


## New skill levels take effect right away, keeping the current share of health.
func _on_skills_closed() -> void:
	_skills = null
	var share := player.health / player.max_health
	var down := player.down
	Progression.apply_to(player)
	if not down:
		player.health = player.max_health * share
	if _pause != null and is_instance_valid(_pause):
		_pause.set_covered(false)
	elif not over:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_lift_failed(prop: ThrowableProp) -> void:
	if _heavy_msg_cd > 0.0:
		return
	_heavy_msg_cd = 1.5
	hud.show_message("Too heavy! The %s needs Strength %d (you have %d)\nLevel up and spend points: Tab" % [
		prop.display_name(), prop.required_strength(), player.strength], 2.5)


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	Brawler.focus = player.global_position
	Brawler.update_separation(get_tree().get_nodes_in_group("brawlers"))


func _process(delta: float) -> void:
	if player == null:
		return
	_heavy_msg_cd -= delta
	var prog := Progression.level_progress()
	hud.update_progress(Progression.level, prog.x, prog.y, Progression.points)
	if over:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		elif Input.is_action_just_pressed("change_character") and CharacterRoster.list().size() > 1:
			CharacterRoster.has_selected = false
			get_tree().reload_current_scene()
		return
	if riot:
		time_left -= delta
		if time_left <= 0.0:
			_end("SESSION ADJOURNED")
			return
		_mult_left -= delta
		if _mult_left <= 0.0:
			multiplier = 1
		_escalate -= delta
		if _escalate <= 0.0:
			_escalate = lerpf(3.0, 1.0, chaos / 100.0)
			_rouse_random(1 + int(chaos / 40.0))
		_update_chaos(delta)
		_update_guards(delta)
		_update_bounty()
	var bounty_text := "BOUNTY: Hon. %s  +500" % bounty.display_name if bounty else ""
	hud.update_stats(score, multiplier, time_left, riot, chaos, player.health / player.max_health, bounty_text)


func _update_chaos(delta: float) -> void:
	var active := 0
	var members := 0
	for n in npcs:
		if n.is_guard:
			continue
		members += 1
		if n.down or n.state in [NpcBrawler.State.FIGHT, NpcBrawler.State.FLEE, NpcBrawler.State.COWER]:
			active += 1
	chaos = lerpf(chaos, 100.0 * active / maxi(1, members), clampf(delta, 0.0, 1.0))


func _update_guards(delta: float) -> void:
	if chaos < 25.0:
		return
	_guard_timer -= delta
	if _guard_timer > 0.0:
		return
	_guard_timer = lerpf(20.0, 10.0, chaos / 100.0)
	var alive := 0
	for n in npcs:
		if n.is_guard:
			alive += 1
	var count := mini(2, MAX_GUARDS - alive)
	if count <= 0:
		return
	var door: Vector3 = exits.pick_random()
	for i in count:
		_add_npc(_make_guard(door + Vector3(randf_range(-0.8, 0.8), 0.05, randf_range(-0.8, 0.8))))
	hud.show_message("SECURITY ENTERS THE CHAMBER", 2.0)


func _update_bounty() -> void:
	if bounty and (not is_instance_valid(bounty) or bounty.down):
		if is_instance_valid(bounty):
			bounty.set_bounty(false)
		bounty = null
	if bounty == null:
		var candidates := npcs.filter(func(n): return not n.is_guard and not n.down)
		if not candidates.is_empty():
			bounty = candidates.pick_random()
			bounty.set_bounty(true)


func _rouse_random(count: int) -> void:
	var calm := npcs.filter(func(n): return n.state in [NpcBrawler.State.SEATED, NpcBrawler.State.SPEAK, NpcBrawler.State.IDLE])
	calm.shuffle()
	for i in mini(count, calm.size()):
		calm[i].rouse(0.75)


func _members_near(pos: Vector3, radius: float) -> Array[NpcBrawler]:
	var out: Array[NpcBrawler] = []
	for n in npcs:
		if not n.is_guard and n.global_position.distance_to(pos) < radius:
			out.append(n)
	return out


# --- Scoring -------------------------------------------------------------------

func _on_hit_landed(attacker: Node, victim: Brawler, _damage: float, kind: String) -> void:
	if over:
		return
	if victim == player:
		hud.flash_damage()
	if attacker == player:
		_start_riot()
		player.shake(0.12)
		if THROW_POINTS.has(kind):
			throw_hits += 1
			var label := "BODY SLAM" if kind == "body" else "%s SHOT" % ThrowableProp.NAMES.get(kind, kind).to_upper()
			_add_score(THROW_POINTS[kind], label)
		else:
			_add_score(10)
	if riot:
		for n in _members_near(victim.global_position, 6.0):
			if n != victim and randf() < 0.3:
				n.rouse(0.75)


func _on_knocked_down(victim: Brawler, attacker: Node) -> void:
	if over:
		return
	if victim == player:
		if player.health <= 0.0:
			_end("EJECTED FROM THE CHAMBER")
		return
	var npc := victim as NpcBrawler
	if attacker == player:
		knockouts += 1
		_add_score(150 if npc.is_guard else 50, "SECURITY DOWN" if npc.is_guard else "KNOCKDOWN")
		multiplier = mini(multiplier + 1, 8)
		if npc == bounty:
			bounties += 1
			_add_score(500, "BOUNTY CLAIMED  +20s")
			time_left += 20.0
	if npc.is_guard and npc.health <= 0.0:
		npcs.erase(npc)
		get_tree().create_timer(5.0).timeout.connect(npc.queue_free)


func _add_score(points: int, label := "") -> void:
	var gained := points * multiplier
	score += gained
	_mult_left = Progression.combo_window()
	hud.popup(("%s  +%d" % [label, gained]) if label != "" else "+%d" % gained)
	var levels := Progression.earn(points)
	if levels > 0:
		hud.show_message("LEVEL UP!  Level %d\nPress Tab to spend your skill point%s" % [
			Progression.level, "s" if Progression.points > 1 else ""], 3.5)


func _end(title: String) -> void:
	over = true
	Progression.save()
	player.input_enabled = false
	if player.down:
		player.stay_down()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rank := "Backbencher"
	if score >= 15000:
		rank = "Legend of the Chamber"
	elif score >= 8000:
		rank = "Firebrand"
	elif score >= 3000:
		rank = "Agitator"
	# Finishing a session pays a bonus by rank; the multiplier never counts toward XP.
	var bonus := {"Backbencher": 40, "Agitator": 100, "Firebrand": 200, "Legend of the Chamber": 350}[rank] as int
	var before := Progression.level
	Progression.add_xp(int(bonus * (1.0 + 0.05 * Progression.get_skill("charisma"))))
	Progression.save()
	var career := "\n\nSession bonus  +%d XP   ·   Level %d" % [bonus, Progression.level]
	if Progression.level > before:
		career += "  (LEVEL UP!)"
	hud.show_results(title, "Chaos score  %d\nKnockdowns  %d\nThrow hits  %d\nBounties  %d\n\nRank: %s%s" % [score, knockouts, throw_hits, bounties, rank, career], CharacterRoster.list().size() > 1)


# --- Helpers -------------------------------------------------------------------

func _polar(r: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(sin(a) * r, 0.0, cos(a) * r)


func _shot_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			return arg.trim_prefix("--shot=")
	return ""


func _capture(path: String) -> void:
	for i in 30:
		await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--ragtest"):
		await _ragdoll_test(path)
		return
	if OS.get_cmdline_user_args().has("--proptest"):
		await _prop_test(path)
		return
	if OS.get_cmdline_user_args().has("--bodytest"):
		await _body_test(path)
		return
	_start_riot()
	_rouse_random(40)
	player.max_health = 1e6
	player.health = 1e6
	for i in 300:
		await get_tree().process_frame
	if path != "bench":
		get_viewport().get_texture().get_image().save_png(path)
	print("SHOT down=%d chaos=%.0f score=%d fps=%d draw_calls=%d" % [npcs.filter(func(n): return n.down).size(), chaos, score, Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()


## Debug: knock an MP out, pick them up (<path>_held.png), throw them into two more MPs
## (<path>_thrown.png) and print what the throw hit.
func _body_test(path: String) -> void:
	player.max_health = 1e6
	player.health = 1e6
	player.global_position = Vector3(2.6, 0.05, 1.2)
	player.rotation.y = PI * 0.5
	var victim := _make_member(Brawler.Faction.VELVET)
	victim.position = Vector3(1.8, 0.05, 1.2)
	_add_npc(victim)
	for i in 8:
		await get_tree().physics_frame
	victim.take_hit(60.0, Vector3(-1.0, 0.0, 0.0), true, null, "kick")
	for i in 30:
		await get_tree().physics_frame
	var spot := victim.body_center()
	player.global_position = Vector3(spot.x + 0.9, 0.05, spot.z)
	player.reset_physics_interpolation()
	await get_tree().physics_frame
	var grabbed := player.try_grab_body()
	var targets: Array[NpcBrawler] = []
	for z in [0.9, 1.5]:
		var t := _make_member(Brawler.Faction.IRON)
		t.position = Vector3(-0.8, 0.05, z)
		_add_npc(t)
		targets.append(t)
	for i in 25:
		await get_tree().physics_frame
	var base := path.trim_suffix(".png")
	get_viewport().get_texture().get_image().save_png(base + "_held.png")
	print("BODYTEST holding_victim=%s torso_height=%.2f" % [player.held_body == victim, victim.body_center().y])
	var before := score
	player.rotation.y = PI * 0.5
	player.throw_held(Vector3(-1.0, 0.12, 0.0).normalized())
	for i in 12:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png(base + "_thrown.png")
	for i in 30:
		await get_tree().physics_frame
	print("BODYTEST grabbed=%s carried_ok=%s score_gain=%d targets_down=%d" % [grabbed, victim.carried_by == null,
		score - before, targets.filter(func(t): return t.down).size()])
	get_tree().quit()


## Debug: the player grabs the nearest monitor, bottle and plant in turn and throws each
## at an MP; saves <path>_<kind>.png while holding it and prints whether it hit.
func _prop_test(path: String) -> void:
	player.max_health = 1e6
	player.health = 1e6
	for kind in ["monitor", "bottle", "plant"]:
		var pick: ThrowableProp
		for node in get_tree().get_nodes_in_group("props"):
			var p := node as ThrowableProp
			if p.kind == kind and (pick == null or Vector2(p.position.x, p.position.z).length() < Vector2(pick.position.x, pick.position.z).length()):
				pick = p
		# Hand the hero this exact item, then throw it across the open floor at an MP.
		player.global_position = Vector3(2.6, 0.05, 1.2)
		player.rotation.y = PI * 0.5
		for i in 10:
			await get_tree().physics_frame
		pick.pick_up(player, player._hold)
		player.held_prop = pick
		var grabbed := pick.holder == player
		var target := _make_member(Brawler.Faction.IRON)
		target.position = Vector3(-0.6, 0.05, 1.2)
		_add_npc(target)
		for i in 15:
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [path.trim_suffix(".png"), kind])
		var before := score
		var aim := (target.global_position + Vector3.UP * 0.8 - (player.global_position + Vector3.UP * 1.8)).normalized()
		player.throw_held((aim + Vector3.UP * 0.05).normalized())
		for i in 60:
			await get_tree().physics_frame
		print("PROPTEST %s grabbed=%s held_kind_ok=%s hit=%s target_down=%s" % [kind, grabbed, pick.holder == null, score > before, target.down])
	get_tree().quit()


## Debug: knock a row of MPs down in front of the camera, capture mid-fall and at rest
## (<path>_a.png, <path>_b.png), then after getting up (<path>_c.png).
func _ragdoll_test(path: String) -> void:
	var victims: Array[NpcBrawler] = []
	for i in 4:
		var mp := _make_member(Brawler.Faction.VELVET if i % 2 == 0 else Brawler.Faction.IRON)
		mp.position = Vector3(-1.5 + i, 0.05, 0.4)
		_add_npc(mp)
		victims.append(mp)
	for i in 20:
		await get_tree().physics_frame
	for i in victims.size():
		var push := Vector3(randf_range(-2.0, 2.0), 0.0, -6.0 if i % 2 == 0 else 5.0)
		victims[i].take_hit(5.0, push, true, player, "kick")
	var base := path.trim_suffix(".png")
	# Wait (in physics frames) before each capture: mid-fall, at rest, back on their feet.
	for step in [["a", 12], ["b", 80], ["c", 200]]:
		for i in step[1]:
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, step[0]])
	print("RAGTEST down=%d" % victims.filter(func(v): return v.down).size())
	get_tree().quit()
