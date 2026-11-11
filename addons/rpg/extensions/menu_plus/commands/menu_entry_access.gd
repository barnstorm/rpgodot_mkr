@tool
extends RPGCommand
## Change menu entry (menu_plus): shows, hides, enables or disables a main-menu command for the
## rest of the game. Works for built-in commands (item, skill, equip, status, options, save,
## game_end) and extra entries. Saved with the game.


static func descriptor() -> Dictionary:
	return {
		"type": "menu_entry_access", "schema_version": 1, "category": "scenes", "label": "Change menu entry",
		"fields": [
			{"key": "entry", "kind": "text", "label": "Menu command ID", "default": "", "required": true,
				"help": "item, skill, equip, status, options, save, game_end, or an extra entry's ID."},
			{"key": "visible", "kind": "choice", "options": ["keep", "show", "hide", "reset"], "option_labels": ["Keep", "Show", "Hide", "As set up"], "default": "keep", "label": "Shown"},
			{"key": "enabled", "kind": "choice", "options": ["keep", "enable", "disable", "reset"], "option_labels": ["Keep", "Usable", "Greyed out", "As set up"], "default": "keep", "label": "Usable"},
		],
	}


func summary(args: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(args.get("visible", "keep")) != "keep":
		parts.append(str(args.visible))
	if str(args.get("enabled", "keep")) != "keep":
		parts.append(str(args.enabled))
	return "Menu entry %s: %s" % [args.get("entry", "?"), ", ".join(parts) if not parts.is_empty() else "no change"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var mp: Object = ctx.rpg.extension("menu_plus")
	if mp == null:
		return RPGResult.error("Change menu entry: the Menu & options plus plugin is not running.")
	if str(args.get("entry", "")).strip_edges() == "":
		return RPGResult.error("Change menu entry: no menu command ID.")
	mp.set_access(str(args.entry).strip_edges(), str(args.get("visible", "keep")), str(args.get("enabled", "keep")))
	return RPGResult.ok()
