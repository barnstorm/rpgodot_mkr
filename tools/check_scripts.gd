extends SceneTree
## Loads every GDScript under addons/, extensions/, scenes/ and tools/ and reports the ones that do
## not compile. Editor scripts are not exercised by every test, so this catches parse errors there.
##   godot --headless --path . --script res://tools/check_scripts.gd

const ROOTS := ["res://addons", "res://extensions", "res://scenes", "res://tests"]


func _initialize() -> void:
	var files: Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	var bad := 0
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			bad += 1
			print("BROKEN ", f)
	print("%d scripts checked, %d broken" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), out)
