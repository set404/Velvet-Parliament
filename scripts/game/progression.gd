class_name Progression
extends RefCounted
## The player's career between sessions: XP, levels, skill points and eight skills.
## Saved to user://progress.cfg. Built to take many sessions:
##   - XP is a quarter of the base score points (no combo multiplier), plus a bonus at
##     the end of a session that grows with the rank reached.
##   - Each level needs more XP than the last (300, 450, 630, 840, 1080 ...).
##   - Every level gives 1 skill point, every 5th level gives 2.
##   - Upgrading costs more the higher a skill already is: 1 point up to level 5,
##     2 points up to 10, 3 points up to 15.
##
## Furniture by Strength needed (see ThrowableProp.LIFT_STRENGTH):
##   1 chairs, monitors, bottles, plants, mics, papers
##   4 presidium chairs, the flag
##   7 desks
##   11 staff counter, presidium desk
##   15 the speaker's tribune

const SAVE_PATH := "user://progress.cfg"
const VERSION := 2
## Share of base score points that become XP.
const XP_RATE := 0.25

const SKILLS := {
	"strength": {"name": "Strength", "max": 15, "start": 1,
		"info": "Lift heavier furniture; +4% throw power per level."},
	"toughness": {"name": "Toughness", "max": 15, "start": 0,
		"info": "+8 health per level."},
	"fists": {"name": "Fists", "max": 15, "start": 0,
		"info": "+6% punch and kick damage per level."},
	"speed": {"name": "Speed", "max": 10, "start": 0,
		"info": "+3% running speed per level."},
	"recovery": {"name": "Recovery", "max": 10, "start": 0,
		"info": "+15% health regeneration and 4% faster getting up per level."},
	"iron_chin": {"name": "Iron Chin", "max": 10, "start": 0,
		"info": "-4% damage taken per level."},
	"showman": {"name": "Showman", "max": 10, "start": 0,
		"info": "Combo multiplier lasts +0.3 s longer per level."},
	"charisma": {"name": "Charisma", "max": 10, "start": 0,
		"info": "+5% XP from everything per level."},
}
const ORDER := ["strength", "toughness", "fists", "speed", "recovery", "iron_chin", "showman", "charisma"]

static var xp := 0
static var level := 1
static var points := 0
static var skills := {}
## Set when an old save was converted to these rules (shown once on the select screen).
static var converted := false
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for id in SKILLS:
		skills[id] = SKILLS[id].start
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	xp = cfg.get_value("career", "xp", 0)
	if cfg.get_value("career", "version", 1) < VERSION:
		# Earlier saves used the old, much faster rules: keep the XP, recount the level
		# from it and hand back fresh skill points to spend under the new costs.
		converted = xp > 0
		level = 1
		points = 0
		while xp >= xp_for_level(level):
			level += 1
			points += points_for_reaching(level)
		save()
		return
	level = cfg.get_value("career", "level", 1)
	points = cfg.get_value("career", "points", 0)
	for id in SKILLS:
		skills[id] = clampi(cfg.get_value("skills", id, SKILLS[id].start), SKILLS[id].start, SKILLS[id].max)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("career", "version", VERSION)
	cfg.set_value("career", "xp", xp)
	cfg.set_value("career", "level", level)
	cfg.set_value("career", "points", points)
	for id in skills:
		cfg.set_value("skills", id, skills[id])
	cfg.save(SAVE_PATH)


## XP needed to go from level n to n + 1.
static func xp_step(n: int) -> int:
	var m := n - 1
	return 300 + 135 * m + 15 * m * m


## Total XP needed to reach the level after `lvl`.
static func xp_for_level(lvl: int) -> int:
	var total := 0
	for i in range(1, lvl + 1):
		total += xp_step(i)
	return total


static func points_for_reaching(lvl: int) -> int:
	return 2 if lvl % 5 == 0 else 1


## Turns base score points into XP (with Charisma); returns levels gained.
static func earn(score_points: int) -> int:
	ensure_loaded()
	var amount := int(round(score_points * XP_RATE * (1.0 + 0.05 * get_skill("charisma"))))
	return add_xp(amount)


static func add_xp(amount: int) -> int:
	ensure_loaded()
	xp += maxi(0, amount)
	var gained := 0
	while xp >= xp_for_level(level):
		level += 1
		points += points_for_reaching(level)
		gained += 1
	if gained > 0:
		save()
	return gained


static func get_skill(id: String) -> int:
	ensure_loaded()
	return skills.get(id, 0)


## Points needed for the skill's next level.
static func cost(id: String) -> int:
	return 1 + get_skill(id) / 5


static func can_upgrade(id: String) -> bool:
	return get_skill(id) < SKILLS[id].max and points >= cost(id)


static func upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	points -= cost(id)
	skills[id] += 1
	save()
	return true


## XP gathered within the current level, and the size of that level.
static func level_progress() -> Vector2i:
	ensure_loaded()
	var start := xp_for_level(level - 1) if level > 1 else 0
	return Vector2i(xp - start, xp_for_level(level) - start)


## Applies the skills to a player's body.
static func apply_to(p: Brawler) -> void:
	ensure_loaded()
	p.strength = get_skill("strength")
	p.throw_power = 1.0 + 0.04 * (p.strength - 1)
	p.max_health = 100.0 + 8.0 * get_skill("toughness")
	p.health = p.max_health
	p.base_damage = 12.0 * (1.0 + 0.06 * get_skill("fists"))
	p.move_speed = 4.4 * (1.0 + 0.03 * get_skill("speed"))
	p.regen_rate = 4.0 * (1.0 + 0.15 * get_skill("recovery"))
	p.getup_mult = 1.0 - 0.04 * get_skill("recovery")
	p.damage_taken = 1.0 - 0.04 * get_skill("iron_chin")


static func combo_window() -> float:
	return 4.0 + 0.3 * get_skill("showman")


## What the current and next Strength levels lift, for the skills panel.
static func strength_note() -> String:
	var s := get_skill("strength")
	var now := []
	var next := ""
	for tier in range(1, ThrowableProp.LIFT_STRENGTH.size()):
		var need: int = ThrowableProp.LIFT_STRENGTH[tier]
		if s >= need:
			now.append(ThrowableProp.TIER_NAMES[tier])
		elif next == "":
			next = "%s at Strength %d" % [ThrowableProp.TIER_NAMES[tier], need]
	return "Lifts: %s" % ", ".join(now) + ("\nNext: %s" % next if next != "" else "")
