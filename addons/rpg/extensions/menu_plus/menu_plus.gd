extends "res://addons/rpg/runtime/rpg_extension.gd"
## Menu & options plus (kit plugin "menu_plus").
## - Main menu: the settings' command order, hidden commands and extra entries are applied to the
##   menu layout (adjust_menu); events can show, hide, enable or disable any entry with the
##   "Change menu entry" command (saved with the game).
## - A party of one skips choosing the actor (menu_config).
## - Extra option rows from the settings (option_entries); a row's value can be copied into a
##   switch or variable so events can read it.

const SECTION := "menu_plus"


## Settings "order"/"hidden" lists hold {id} rows (or plain strings in hand-written JSON).
static func ids_of(list: Variant) -> Array:
	var out := []
	if list is Array:
		for x in list:
			var id := str(x.get("id", "")) if x is Dictionary else str(x)
			if id.strip_edges() != "":
				out.append(id.strip_edges())
	return out


func adjust_menu(layout: Array, _config: Dictionary) -> void:
	var host: Node = rpg.extensions
	for e in setting("entries", []):
		if not (e is Dictionary) or str(e.get("id", "")).strip_edges() == "":
			continue
		var entry: Dictionary = e.duplicate(true)
		entry["id"] = str(e.id).strip_edges()
		if entry.get("icon") == null:
			entry.erase("icon")
		for k in ["common_event", "scene", "after", "show_switch", "enable_switch"]:
			if str(entry.get(k, "")) == "":
				entry.erase(k)
		host._insert_entry(layout, entry, extension_id)
	host._apply_order(layout, ids_of(setting("order", [])), ids_of(setting("hidden", [])))
	# Changes made by events (Change menu entry).
	var access: Dictionary = section(SECTION).get("access", {})
	for item in layout:
		var a: Variant = access.get(str(item.id))
		if not (a is Dictionary):
			continue
		if a.has("visible"):
			item["hidden"] = not bool(a.visible)
		if a.has("enabled"):
			item["enabled"] = bool(a.enabled)


func menu_config() -> Dictionary:
	return {"skip_single_actor": bool(setting("skip_single_actor", true))}


## Shows/hides or enables/disables a menu entry for the rest of the game ("keep" leaves it).
func set_access(entry_id: String, visible: String, enabled: String) -> void:
	var s := section(SECTION)
	var access: Dictionary = s.get("access", {})
	var a: Dictionary = access.get(entry_id, {})
	match visible:
		"show": a["visible"] = true
		"hide": a["visible"] = false
		"reset": a.erase("visible")
	match enabled:
		"enable": a["enabled"] = true
		"disable": a["enabled"] = false
		"reset": a.erase("enabled")
	if a.is_empty():
		access.erase(entry_id)
	else:
		access[entry_id] = a
	s["access"] = access


# --- option rows ------------------------------------------------------------------------------

## The settings' option rows as host option rows.
func option_entries() -> Array:
	var out := []
	for r in setting("option_rows", []):
		if not (r is Dictionary) or str(r.get("key", "")).strip_edges() == "":
			continue
		var kind := str(r.get("kind", "bool"))
		var row := {"key": str(r.key).strip_edges(), "kind": kind, "label": str(r.get("label", r.key)), "help": str(r.get("help", ""))}
		var d := str(r.get("default", ""))
		match kind:
			"bool":
				row["default"] = d.to_lower() in ["true", "on", "1", "yes"]
			"choice":
				var opts := []
				for c in str(r.get("choices", "")).split(",", false):
					if c.strip_edges() != "":
						opts.append(c.strip_edges())
				if opts.is_empty():
					continue
				row["options"] = opts
				row["default"] = d if opts.has(d) else opts[0]
			_:
				row["kind"] = "slider"
				row["min"] = int(r.get("min", 0))
				row["max"] = int(r.get("max", 100))
				row["step"] = maxi(1, int(r.get("step", 10)))
				row["default"] = clampi(d.to_int() if d.is_valid_int() else int(r.get("max", 100)), row.min, row.max)
		out.append(row)
	return out


func _row_def(key: String) -> Dictionary:
	for r in setting("option_rows", []):
		if r is Dictionary and str(r.get("key", "")).strip_edges() == key:
			return r
	return {}


func on_option_changed(key: String, value: Variant) -> void:
	_mirror(key, value)


## Copies an option row's value into its switch or variable (choice rows store the choice's
## position, 0-based, in the variable).
func _mirror(key: String, value: Variant) -> void:
	var r := _row_def(key)
	if r.is_empty() or rpg.state == null:
		return
	var sw := str(r.get("switch", ""))
	if sw != "" and str(r.get("kind", "bool")) == "bool":
		rpg.state.set_switch(sw, bool(value))
	var v := str(r.get("variable", ""))
	if v != "":
		var n: Variant = value
		if str(r.get("kind", "")) == "choice":
			var opts := []
			for c in str(r.get("choices", "")).split(",", false):
				opts.append(c.strip_edges())
			n = opts.find(str(value))
		elif value is bool:
			n = 1 if value else 0
		rpg.state.set_variable(v, n)


func _mirror_all() -> void:
	for row in option_entries():
		_mirror(str(row.key), option(str(row.key), row.get("default")))


func on_new_game() -> void:
	_mirror_all()


func on_game_loaded() -> void:
	_mirror_all()
