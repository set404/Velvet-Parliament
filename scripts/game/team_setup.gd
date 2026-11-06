class_name TeamSetup
extends RefCounted
## The session's teams, set up on the select screen: how many teams, how many members
## each has (the player counts as one of their own team's members), what they're called
## and which one the player joins. Kept across restarts and saved to user://teams.cfg.
##
## Teams are numbered 0..count-1 (Brawler.team_id); -1 means no team (independents,
## security). Every team fights every other team; only rival teams fight the player.

const MIN_TEAMS := 2
const MAX_TEAMS := 6
const MIN_MEMBERS := 1
const MAX_MEMBERS := 40
const NAME_MAX_LENGTH := 16
const SAVE_PATH := "user://teams.cfg"

## Per team slot: default name, suit, tie, and the accent used on buttons and messages.
const STYLES := [
	{"name": "VELVET", "suit": Color(0.09, 0.12, 0.26), "tie": Color(0.7, 0.08, 0.12), "accent": Color(0.85, 0.15, 0.2)},
	{"name": "IRON", "suit": Color(0.2, 0.2, 0.22), "tie": Color(0.88, 0.62, 0.1), "accent": Color(0.95, 0.68, 0.15)},
	{"name": "JADE", "suit": Color(0.06, 0.18, 0.14), "tie": Color(0.2, 0.75, 0.4), "accent": Color(0.25, 0.8, 0.45)},
	{"name": "AZURE", "suit": Color(0.5, 0.55, 0.62), "tie": Color(0.15, 0.5, 0.95), "accent": Color(0.3, 0.6, 1.0)},
	{"name": "VIOLET", "suit": Color(0.2, 0.1, 0.24), "tie": Color(0.7, 0.35, 0.95), "accent": Color(0.75, 0.45, 1.0)},
	{"name": "COPPER", "suit": Color(0.36, 0.2, 0.12), "tie": Color(0.95, 0.45, 0.15), "accent": Color(1.0, 0.5, 0.2)},
]

## Difficulty levels (index = TeamSetup.difficulty). Multipliers apply to every MP and
## guard; "guards" is the most security in the chamber at once, "focus" the chance a
## rival MP picking a fight goes for the player, "xp" scales the end-of-session bonus.
const DIFFICULTIES := [
	{"name": "EASY", "health": 0.7, "damage": 0.6, "speed": 0.9, "aggression": -0.15, "guards": 5, "guard_wait": 1.4, "focus": 0.15, "xp": 0.75},
	{"name": "NORMAL", "health": 1.0, "damage": 1.0, "speed": 1.0, "aggression": 0.0, "guards": 8, "guard_wait": 1.0, "focus": 0.35, "xp": 1.0},
	{"name": "HARD", "health": 1.4, "damage": 1.5, "speed": 1.12, "aggression": 0.15, "guards": 11, "guard_wait": 0.7, "focus": 0.6, "xp": 1.5},
]

static var difficulty := 1
static var count := 2
## Members per team slot (index = team number; only the first `count` are used). The
## player counts as one member of their own team.
static var sizes: Array[int] = [30, 30, 30, 30, 30, 30]
static var player_team := 0
static var names: Array[String] = []
## Member seats in the chamber; set by the game before the select screen opens.
static var seats := 126

static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	names.clear()
	for s in STYLES:
		names.append(s.name)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		count = cfg.get_value("teams", "count", count)
		# Older saves had one size for every team.
		var legacy: int = cfg.get_value("teams", "members", 30)
		var saved_sizes: Array = cfg.get_value("teams", "sizes", [])
		for i in sizes.size():
			sizes[i] = int(saved_sizes[i]) if i < saved_sizes.size() else legacy
		player_team = cfg.get_value("teams", "player_team", player_team)
		difficulty = cfg.get_value("game", "difficulty", difficulty)
		var saved: Array = cfg.get_value("teams", "names", [])
		for i in mini(saved.size(), names.size()):
			names[i] = clean_name(str(saved[i]), i)
	clamp_all()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("teams", "count", count)
	cfg.set_value("teams", "sizes", sizes)
	cfg.set_value("teams", "player_team", player_team)
	cfg.set_value("teams", "names", names)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.save(SAVE_PATH)


## The current difficulty's settings (see DIFFICULTIES).
static func diff() -> Dictionary:
	return DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)]


static func set_difficulty(n: int) -> void:
	difficulty = n
	clamp_all()


## Members of team `team` (the player included if it's theirs).
static func members_of(team: int) -> int:
	return sizes[team] if team >= 0 and team < count else 0


## Most members the active teams can have together: every NPC needs a seat; the player
## doesn't (and the speaker at the tribune frees one more).
static func total_capacity() -> int:
	return seats + 1


## Most members `team` can have, given the other teams' sizes.
static func max_members(team: int) -> int:
	var others := 0
	for t in count:
		if t != team:
			others += sizes[t]
	return clampi(total_capacity() - others, MIN_MEMBERS, MAX_MEMBERS)


## Keeps every team within MIN..MAX and all of them within the chamber's seats; when
## they don't fit, the later teams give up members first.
static func clamp_all() -> void:
	count = clampi(count, MIN_TEAMS, MAX_TEAMS)
	var budget := total_capacity()
	for t in count:
		var reserve := (count - 1 - t) * MIN_MEMBERS
		sizes[t] = clampi(sizes[t], MIN_MEMBERS, maxi(MIN_MEMBERS, mini(MAX_MEMBERS, budget - reserve)))
		budget -= sizes[t]
	player_team = clampi(player_team, 0, count - 1)
	difficulty = clampi(difficulty, 0, DIFFICULTIES.size() - 1)


static func set_count(n: int) -> void:
	count = n
	clamp_all()


## Resizes one team, within what the seats left over allow.
static func set_members(team: int, n: int) -> void:
	sizes[team] = clampi(n, MIN_MEMBERS, max_members(team))
	clamp_all()


## Gives every active team the same size (as far as the seats allow).
static func set_all_members(n: int) -> void:
	n = clampi(n, MIN_MEMBERS, mini(MAX_MEMBERS, total_capacity() / count))
	for t in count:
		sizes[t] = n
	clamp_all()


## Trimmed and shortened; an empty name falls back to the slot's default.
static func clean_name(text: String, team: int) -> String:
	var t := text.strip_edges().left(NAME_MAX_LENGTH)
	return t if t != "" else String(STYLES[team].name)


static func rename_team(team: int, text: String) -> void:
	ensure_loaded()
	names[team] = clean_name(text, team)


static func team_name(team: int) -> String:
	ensure_loaded()
	return names[team] if team >= 0 and team < names.size() else "INDEPENDENT"


static func style(team: int) -> Dictionary:
	return STYLES[team]


## "A", "A and B", "A, B and C".
static func list_names(teams: Array) -> String:
	var parts: Array[String] = []
	for t in teams:
		parts.append(team_name(t))
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]


static func rivals_of(team: int) -> Array:
	var out := []
	for t in count:
		if t != team:
			out.append(t)
	return out
