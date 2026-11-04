class_name CharacterRoster
extends RefCounted
## Finds the playable characters: every model file under res://characters/ (FBX, glTF
## or Blender), including sub-folders, so each character can keep its textures beside it.
## The display name comes from the file name: "davit_kirakosyan.fbx" -> "Davit Kirakosyan".
## The first entry is always the built-in blocky MP (path "").

const ROOT := "res://characters/"
const EXTENSIONS := ["fbx", "glb", "gltf", "blend"]
const DEFAULT_NAME := "The Honourable Member"

## The character picked on the select screen; kept across restarts (R).
static var selected_path := ""
static var has_selected := false


static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"name": DEFAULT_NAME, "path": ""}]
	var found: Array[String] = []
	_scan(ROOT, found)
	found.sort()
	for path in found:
		out.append({"name": pretty_name(path), "path": path})
	return out


static func pretty_name(path: String) -> String:
	var base := path.get_file().get_basename()
	var words := base.replace("_", " ").replace("-", " ").replace(".", " ").split(" ", false)
	var parts: Array[String] = []
	for w in words:
		parts.append(w.capitalize())
	return " ".join(parts) if not parts.is_empty() else base


static func load_scene(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


static func _scan(dir: String, found: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	# list_directory also works in exported builds, where only .import/.remap files remain.
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			_scan(dir + entry, found)
		elif entry.get_extension().to_lower() in EXTENSIONS:
			found.append(dir + entry)


## Gives a brawler the player's body: the classic suit, plus the chosen model on top.
static func dress(b: Brawler, path: String) -> void:
	b.build_body(Color(0.78, 0.76, 0.72), Color(0.75, 0.05, 0.08), Color(0.87, 0.7, 0.56), Color(0.1, 0.07, 0.05))
	var scene := load_scene(path)
	if scene != null:
		b._rig.add_child(CharacterSkin.create(scene, b))
