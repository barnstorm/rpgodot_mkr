@tool
class_name RPGRecordSchemas
extends RefCounted
## Field descriptions for every database record type, as data (same field kinds as command
## descriptors, see docs/ARCHITECTURE.md). Stat fields come from the rule system's stats() and
## resources(); every record gets notes and the project's custom fields
## (rpg/project.json "custom_fields": {type: [{key, kind, label, ...}]}).
## Fields marked "formula": true get a Test button in the Database screen.

const SCOPES := ["none", "one_enemy", "all_enemies", "one_ally", "all_allies", "user", "one_dead_ally", "all_dead_allies"]
const OCCASIONS := ["always", "battle", "menu", "never"]
const DAMAGE_TYPES := ["none", "damage", "recover", "drain"]
const HIT_TYPES := ["certain", "physical", "magical"]
const RESTRICTIONS := ["none", "cannot_act", "attack_enemy", "attack_anyone", "attack_ally"]
const SPANS := ["once_per_battle", "once_per_turn", "every_check"]
## Effect kinds (RPGRuleSystem.apply_action) and their labels.
const EFFECT_KINDS := ["recover", "damage", "add_state", "remove_state", "grow", "learn_skill", "common_event"]
const EFFECT_LABELS := ["Recover", "Damage", "Add State", "Remove State", "Grow (raise a stat)", "Learn Skill", "Common Event"]
## Built-in battle effects (RPGBattleEffects.BUILTIN) an animation field may name.
const BUILTIN_ANIMATIONS := ["hit", "slash", "fire", "ice", "thunder", "heal"]
## Tileset asset profiles and their labels.
const TILESET_PROFILES := ["rm2k", "xp", "vx", "mv"]
const TILESET_PROFILE_LABELS := ["RPG Maker 2000/2003", "RPG Maker XP", "RPG Maker VX / VX Ace", "RPG Maker MV / MZ"]
const ANIMATION_SHEET_HINT := "No animation sheets yet. Sheets are images in a pack's Picture folder (frames of equal size, left to right, then top to bottom): add one with Tools > Resources > Import."
## Vehicle defaults (runtime/rpg_vehicles.gd DEFAULTS): shown in the System form.
const Vehicles := preload("res://addons/rpg/runtime/rpg_vehicles.gd")

## Tab order and labels: [db type or special key, label, singular reference kind].
const TABS := [
	["actors", "Actors", "actor"], ["classes", "Classes", "class"], ["skills", "Skills", "skill"],
	["items", "Items", "item"], ["weapons", "Weapons", "weapon"], ["armors", "Armour", "armor"],
	["enemies", "Enemies", "enemy"], ["troops", "Enemy groups", "troop"], ["states", "States", "state"],
	["animations", "Animations", "animation"], ["tilesets", "Tilesets", "tileset"],
	["common_events", "Common events", "common_event"], ["state", "Switches and variables", ""],
	["system", "System", ""], ["types", "Types", ""], ["terms", "Terms", ""],
]


## stats/resources: Arrays of {id, label} (from RPGRuleSystem.stats()/resources()).
## rule_def: the rule system's rules.json (RPGRuleSystem.definition), for the class growth
## shapes and the experience curve parameters.
## type_lists: the Types records by ID ({"elements": {name, entries}, ...}, see type_lists()):
## skill types, elements, weapon and armour types become dropdowns of those entries.
static func fields_for(type: String, stats: Array = [], resources: Array = [], trait_kinds: Array = [], custom_fields: Dictionary = {}, equip_slots: Array = [], rule_def: Dictionary = {}, type_lists: Dictionary = {}) -> Array:
	var f := []
	match type:
		"actors":
			f = [
				_t("name", "Name"), _t("nickname", "Nickname"),
				_m("description", "Description", "Shown on the Status screen."),
				_ref("class", "class", "Class"),
				_i("initial_level", "Starting level", 1, 1, 999), _i("max_level", "Max level", 99, 1, 999),
				_res("charset", "charset", "Walk sprite"), _i("charset_index", "Sprite #", 0, 0, 7),
				_res("face", "faceset", "Face").merged({"index_from": "face_index"}), _i("face_index", "Face #", 0, 0, 15),
				_res("battler", "battler", "Battler"),
				_res("sv_battler", "sv_battler", "Side-view battler").merged({"help": "Drawn in side-view battles: an MV/MZ sv_actors sheet or a 2003 BattleCharSet (BattleCharSet folder). Empty: the walk sprite, facing left."}),
				_obj("equips", "Starting equipment", _equip_fields(equip_slots)),
				{"key": "skills", "kind": "list", "item_ref": "skill", "default": [], "label": "Extra skills"},
				_obj("base_stats", "Stat bonuses", _stat_fields(stats, 0)),
				_traits(trait_kinds, type_lists, stats),
			]
		"classes":
			var growth := []
			var shapes := growth_shapes(rule_def)
			var max_level := int(rule_def.get("levels", {}).get("max", 99)) if rule_def.get("levels") is Dictionary else 99
			for s in stats:
				growth.append({"key": str(s.id), "kind": "growth", "default": {}, "label": str(s.get("label", s.id)),
					"shapes": shapes, "max_level": max_level,
					"help": "Per level: base + per level x (level - 1). Curve: the value at level 1 and at level 99, with a shape."})
			f = [
				_t("name", "Name"),
				_obj("exp_curve", "Experience curve", _exp_curve_fields(rule_def)),
				_obj("growth", "Stat growth", growth),
				{"key": "learnings", "kind": "list", "default": [], "label": "Skills learned", "item_fields": [
					_i("level", "Level", 1, 1, 999), _ref("skill", "skill", "Skill")]},
				_obj("equip", "Can equip", [
					_type_list_field("weapon_types", "Weapon types", type_lists, "weapon_types"),
					_type_list_field("armor_types", "Armour types", type_lists, "armor_types")]),
				_traits(trait_kinds, type_lists, stats),
			]
		"skills":
			f = [
				_t("name", "Name"), _m("description", "Description"), _icon_field(),
				_type_field("skill_type", "Skill type", type_lists, "skill_types"),
				_obj("cost", "Cost", _resource_fields(resources)),
				_c("scope", "Target", SCOPES, "one_enemy"), _c("occasion", "Usable", OCCASIONS, "always"),
				_c("damage_type", "Damage type", DAMAGE_TYPES, "damage"),
				_c("resource", "Affects", _ids(resources), "hp"),
				_type_field("element", "Element", type_lists, "elements"),
				{"key": "formula", "kind": "text", "default": "", "label": "Damage formula", "formula": true,
					"help": "a = user, b = target, v.<variable>. Helpers: min, max, clamp, roll(\"1d6\"), mod(x)..."},
				_i("hit", "Hit %", 100, 0, 100), _c("hit_type", "Hit type", HIT_TYPES, "certain"),
				_i("variance", "Variance %", 15, 0, 100), _b("critical", "Can be critical", false),
				_animation_field(), _t("message", "Message (%1 = user)"),
				_effects(resources, stats),
			]
		"items":
			f = [
				_t("name", "Name"), _m("description", "Description"), _icon_field(),
				_i("price", "Price", 0, 0, 9999999), _b("consumable", "Consumed when used", true), _b("key_item", "Key item", false),
				_c("scope", "Target", SCOPES, "one_ally"), _c("occasion", "Usable", OCCASIONS, "always"),
				_animation_field(),
				_effects(resources, stats),
			]
		"weapons":
			f = [
				_t("name", "Name"), _m("description", "Description"), _icon_field(),
				_type_field("weapon_type", "Weapon type", type_lists, "weapon_types"), _i("price", "Price", 0, 0, 9999999),
				_obj("params", "Stat changes", _stat_fields(stats, 0)), _animation_field(), _traits(trait_kinds, type_lists, stats),
			]
		"armors":
			f = [
				_t("name", "Name"), _m("description", "Description"), _icon_field(),
				_type_field("armor_type", "Armour type", type_lists, "armor_types"), _armor_slot_field(equip_slots),
				_i("price", "Price", 0, 0, 9999999),
				_obj("params", "Stat changes", _stat_fields(stats, 0)), _traits(trait_kinds, type_lists, stats),
			]
		"enemies":
			f = [
				_t("name", "Name"), _res("battler", "battler", "Battler"), _i("battler_hue", "Hue", 0, 0, 360),
				_i("level", "Level", 1, 1, 999),
				_obj("stats", "Stats", _stat_fields(stats, 1)),
				_i("exp", "Experience", 0, 0, 9999999), _i("gold", "Gold", 0, 0, 9999999),
				{"key": "drops", "kind": "list", "default": [], "label": "Item drops", "item_fields": [
					_c("kind", "Kind", ["item", "weapon", "armor"], "item"),
					{"key": "id", "kind": "ref", "ref": "item", "ref_from": "kind", "label": "Item"},
					_i("chance", "Chance %", 10, 0, 100)]},
				{"key": "actions", "kind": "list", "default": [], "label": "Action patterns", "item_fields": [
					{"key": "skill", "kind": "ref", "ref": "skill", "allow": ["attack", "guard", "wait", "escape"], "default": "attack", "label": "Skill"},
					_i("rating", "Rating", 5, 1, 10),
					{"key": "condition", "kind": "object", "default": {"kind": "always"}, "label": "Condition", "fields": _enemy_condition_fields()}]},
				_traits(trait_kinds, type_lists, stats),
			]
		"troops":
			f = [
				_t("name", "Name"), _b("can_escape", "Can escape", true),
				{"key": "battle_view", "kind": "choice", "options": ["", "front", "side"], "option_labels": ["As in System", "Front view", "Side view"], "default": "", "label": "Battle view"},
				{"key": "battle_system", "kind": "choice", "options": ["", "turn", "atb", "ctb"], "option_labels": ["As in System", "Turn based", "Active time (ATB)", "Turn order (CTB)"], "default": "", "label": "Battle system"},
				{"key": "members", "kind": "troop_members", "default": [], "label": "Enemies", "item_fields": [
					_ref("enemy", "enemy", "Enemy"),
					{"key": "position", "kind": "point", "default": [160, 120], "min": 0, "max": 9999, "label": "Position (pixels)",
						"help": "The enemy's centre on the 320x240 battle screen. Drag it in the picture above."},
					_b("hidden", "Appears later", false)]},
				{"key": "pages", "kind": "list", "default": [], "label": "Battle events", "item_fields": [
					_t("id", "Page ID"), _t("name", "Name"),
					{"key": "conditions", "kind": "list", "item_kind": "condition", "battle": true, "default": [], "label": "Conditions"},
					_c("span", "Span", SPANS, "once_per_battle"), _i("priority", "Priority", 0, -99, 99),
					{"key": "commands", "kind": "commands", "default": [], "label": "Commands"}]},
			]
		"states":
			f = [
				_t("name", "Name"), _icon_field(), _i("priority", "Priority", 50, 0, 100),
				_c("restriction", "Restriction", RESTRICTIONS, "none"),
				_b("remove_at_battle_end", "Remove at battle end", false),
				# "duration" is not stored: it shows whether the state has turns_min/turns_max
				# (RPGRecordTab: "virtual" fields; hidden "drop_hidden" fields are removed).
				{"key": "duration", "kind": "choice", "virtual": true, "options": ["until_removed", "turns"],
					"option_labels": ["Until removed (no turn limit)", "For a number of turns"], "default": "until_removed", "label": "Lasts",
					"help": "Until removed: only an effect, an event or the end of battle (if set) removes it. For a number of turns: it wears off after a random number of turns between the two values."},
				_i("turns_min", "At least (turns)", 1, 0, 999).merged({"show_if": {"key": "duration", "equals": "turns"}, "drop_hidden": true, "not_above": "turns_max",
					"help": "0 also counts as 1: the state then ends at the end of the turn it was added in."}),
				_i("turns_max", "At most (turns)", 1, 1, 999).merged({"show_if": {"key": "duration", "equals": "turns"}, "drop_hidden": true, "not_below": "turns_min"}),
				_i("remove_on_damage", "Chance removed by damage %", 0, 0, 100),
				_obj("messages", "Messages (%1 = name)", [_t("added", "When added"), _t("removed", "When removed")]),
				{"key": "slip", "kind": "object", "default": null, "off_value": {}, "toggle_label": "Takes damage at the end of each turn", "label": "Damage each turn", "fields": [
					_c("resource", "Resource", _ids(resources) if not resources.is_empty() else ["hp"], "hp").merged({"option_labels": _labels(resources)}),
					_i("percent", "% of maximum", 10, 0, 100), _i("amount", "Plus a fixed amount", 0, 0, 999999),
					_b("can_kill", "Can knock out", false)]},
				# Map walking (RPGRuleSystem.walk_state_steps / map_step_changes).
				_b("remove_by_walking", "Removed by walking", false).merged({
					"help": "The state wears off after the actor walks a number of steps on the map (counted from when it was added; steps in a vehicle or an event's move route don't count)."}),
				_i("steps_to_remove", "Steps to remove", 100, 1, 9999).merged({"show_if": {"key": "remove_by_walking", "equals": true}, "drop_hidden": true}),
				{"key": "map_hp_change", "kind": "object", "default": null, "off_value": {}, "toggle_label": "Changes HP or MP while walking (RPG Maker 2000 style)", "label": "Change while walking",
					"help": "Every N steps on the map, each actor with this state loses or gains the amount. Damage leaves at least 1 HP unless System > Knockout by slip damage is on. (VX Ace style rules also apply Damage each turn and regeneration every 20 steps.)",
					"fields": [
					_c("resource", "Resource", _ids(resources) if not resources.is_empty() else ["hp"], "hp").merged({"option_labels": _labels(resources)}),
					_c("effect", "Effect", ["damage", "recover"], "damage").merged({"option_labels": ["Damage", "Recover"]}),
					_c("kind", "Amount is", ["flat", "percent"], "flat").merged({"option_labels": ["A fixed amount", "% of maximum"]}),
					_i("value", "Amount", 1, 0, 999999), _i("steps", "Every N steps", 1, 1, 999)]},
				_traits(trait_kinds, type_lists, stats),
			]
		"animations":
			f = [
				_t("name", "Name"),
				_res("sheet", "picture", "Sprite sheet").merged({"empty_hint": ANIMATION_SHEET_HINT,
					"help": "An image in a pack's Picture folder (Tools > Resources > Import adds one). Without a sheet, battles show a built-in effect chosen by the animation's ID."}),
				_i("frame_width", "Frame width", 96, 1, 4096), _i("frame_height", "Frame height", 96, 1, 4096),
				{"key": "fps", "kind": "float", "default": 12.0, "min": 1.0, "max": 60.0, "label": "Frames per second"},
				{"key": "frames", "kind": "list", "default": [], "label": "Frames (cell shown in each frame)",
					"item_field": {"kind": "int", "default": 0, "min": 0, "max": 9999, "label": "Frame %d shows cell"},
					"help": "Cells are numbered from 0, left to right, then top to bottom (the strip in the preview shows the numbers). No frames: every cell in order."},
				{"key": "flashes", "kind": "list", "default": [], "label": "Flashes", "item_fields": [
					_i("frame", "Frame", 0, 0, 999), {"key": "color", "kind": "color", "default": [255, 255, 255, 170], "label": "Colour"}]},
				{"key": "sounds", "kind": "list", "default": [], "label": "Sounds", "item_fields": [
					_i("frame", "Frame", 0, 0, 999), {"key": "sound", "kind": "sound", "res": "sound", "default": {"file": "", "volume": 100, "pitch": 100, "pan": 0}, "label": "Sound"}]},
			]
		"tilesets":
			f = [
				_t("name", "Name"),
				_c("profile", "Asset profile", TILESET_PROFILES, "rm2k").merged({"option_labels": TILESET_PROFILE_LABELS}),
				_sheet_field("sheet", "Sheet").merged({"show_if": {"key": "profile", "equals": ["rm2k", "xp", null]},
					"help": "2000/2003: the ChipSet (480x256). XP: the tileset image (8 tiles wide)."}),
				{"key": "autotiles", "kind": "list", "default": [], "label": "Autotiles (up to 7)", "item_field": _sheet_field("", "Autotile %d"),
					"show_if": {"key": "profile", "equals": "xp"}, "help": "One 96x128 (or wider, animated) image per autotile slot."},
				{"key": "sheets", "kind": "object", "default": {}, "label": "Sheets", "show_if": {"key": "profile", "equals": ["vx", "mv"]},
					"help": "One image per sheet; leave unused sheets empty.", "fields": [
					_sheet_field("a1", "A1 (animated water)"), _sheet_field("a2", "A2 (ground)"), _sheet_field("a3", "A3 (buildings)"),
					_sheet_field("a4", "A4 (walls)"), _sheet_field("a5", "A5 (plain ground)"), _sheet_field("b", "B"),
					_sheet_field("c", "C"), _sheet_field("d", "D"), _sheet_field("e", "E")]},
				{"key": "tiles_note", "kind": "note", "label": "Passability",
					"text": "Passability, terrain, counters and other per-tile settings: RPG tab > Tiles (with a map that uses this tileset open). They are kept in rpg/tileset_overrides/<tileset ID>.json."},
			]
		"types":
			f = types_fields("", type_lists)
		"terms":
			f = [_t("name", "Name"), _t("category", "Category"), _m("text", "Text", "Use %1, %2 for values.")]
		"common_events":
			f = [
				_t("name", "Name"),
				_c("trigger", "Trigger", ["none", "autorun", "parallel"], "none"),
				{"key": "switch", "kind": "ref", "ref": "switch", "default": "", "label": "Condition switch", "show_if": {"key": "trigger", "equals": ["autorun", "parallel"]}},
			]
		"switches":
			f = [_t("label", "Label"), _t("folder", "Folder"), _m("description", "Description")]
		"variables":
			f = [_t("label", "Label"), _c("type", "Type", ["int", "float", "bool", "string"], "int"),
				# A plain value field: the record tab turns the text into the variable's type.
				{"key": "default", "kind": "text", "default": 0, "label": "Starting value", "coerce_by": "type",
					"help": "A whole number for int, a number for float, true or false for bool, any text for string."},
				_t("folder", "Folder"), _m("description", "Description")]
		"system":
			return [
				_t("title", "Game title"),
				_res("title_image", "title", "Title screen image").merged({"help": "Shown behind the title menu (Title folder). Empty: a gradient with the game title."}),
				_t("currency", "Currency unit").merged({"help": "Shown after amounts of gold. While this is set, Terms > gold_unit is not used."}),
				_i("starting_gold", "Starting gold", 0, 0, 9999999),
				{"key": "starting_party", "kind": "list", "item_ref": "actor", "default": [], "label": "Starting party"},
				{"key": "start", "kind": "location", "default": null, "label": "Start position"},
				# Stored as start.facing; the System tab maps it (see RPGDatabaseScreen.system_edited).
				{"key": "start_facing", "kind": "facing", "allow_keep": false, "default": "down", "label": "Start facing"},
				{"key": "starting_items", "kind": "count_map", "ref": "item", "default": {}, "min": 1, "max": 99, "label": "Starting items"},
				_obj("music", "Music", [_res("title", "music", "Title"), _res("battle", "music", "Battle"), _res("victory", "music", "Victory"), _res("defeat", "music", "Defeat")]),
				_res("window_skin", "system", "Window style"),
				_res("icon_sheet", "iconset", "Icon sheet").merged({"help": "Icons for items, skills, equipment and states: an IconSet-style sheet (16 square icons per row) from a pack's System folder. Empty: the starter icons (24 px, 32 px for MV/MZ projects)."}),
				_b("show_icons", "Show icons", true).merged({"help": "Off: menus, shops, battle and messages show no icons (the RPG Maker 2000 look)."}),
				_b("auto_save", "Auto-save", false),
				_b("slip_death", "Knockout by slip damage", false).merged({
					"help": "On: damage while walking (poison and other slip damage, a state's change while walking) can knock actors out, and the game is over when the whole party is knocked out. Off: it leaves at least 1 HP."}),
				_i("damage_floor", "Damage floor (HP per step)", 5, 0, 9999).merged({
					"help": "HP each actor loses per step on a damage floor tile (RPG tab > Tiles). A damage floor never knocks anyone out."}),
				_obj("vehicles", "Vehicles", _vehicle_fields()),
				{"key": "default_battle_scene", "kind": "resource", "res": "scene", "default": "", "label": "Default battle scene"},
				{"key": "battle_view", "kind": "choice", "options": ["front", "side"], "option_labels": ["Front view (2000, VX Ace)", "Side view (2003, MV/MZ)"], "default": "front", "label": "Battle view",
					"help": "Side view draws the party on the right with their side-view battler (or walk sprite). Enemy groups and maps can override it."},
				{"key": "battle_system", "kind": "choice", "options": ["turn", "atb", "ctb"], "option_labels": ["Turn based (everyone picks, then acts)", "Active time (ATB: gauges fill by agility)", "Turn order (CTB: one battler at a time)"], "default": "turn", "label": "Battle system",
					"help": "Turn based is the 2000/VX Ace battle. ATB is 2003 / MZ Time Progress. CTB shows the coming turn order on screen."},
				{"key": "atb_mode", "kind": "choice", "options": ["wait", "active"], "option_labels": ["Wait (time stops while choosing)", "Active (time keeps running)"], "default": "wait", "label": "ATB mode",
					"show_if": {"key": "battle_system", "equals": "atb"}},
			]
	if type in ["switches", "variables"]:
		return f
	f.append(_m("notes", "Notes"))
	var custom: Array = custom_fields.get(type, [])
	if not custom.is_empty():
		var cf := []
		for c in custom:
			if c is Dictionary and c.has("key"):
				var d: Dictionary = c.duplicate(true)
				if not d.has("kind"):
					d["kind"] = "text"
				cf.append(d)
		f.append({"key": "custom", "kind": "object", "default": {}, "label": "Custom fields", "fields": cf})
	return f


## The Types tab's fields for one record: every list has ID and Name per entry; Equipment slots
## also have the slot's kind and the armour types it takes. Entry IDs are renamed with the
## tab's "Rename entry ID…" (references follow).
static func types_fields(record_id: String, type_lists: Dictionary = {}) -> Array:
	var entry := [_t("id", "ID").merged({"help": "Lowercase letters, digits and _. To change an ID that records already use, use Rename entry ID…"}), _t("name", "Name")]
	if record_id == "equip_slots":
		entry.append(_c("kind", "Holds", ["weapon", "armor"], "armor").merged({"option_labels": ["Weapons", "Armour"]}))
		var at := _type_list_field("armor_types", "Armour types it takes", type_lists, "armor_types")
		at["show_if"] = {"key": "kind", "equals": ["armor", null]}
		at["help"] = "Empty: any armour whose own Slot is this one."
		entry.append(at)
	return [_t("name", "Name"), {"key": "entries", "kind": "list", "default": [], "label": "Entries", "item_fields": entry}]


## A new record of a type, with defaults for every described field. Fields hidden by their
## show_if for those defaults, "virtual" fields and notes are left out.
## "name" and "notes" are added only when the fields have them (or no fields are given).
static func new_record(type: String, id: String, fields: Array) -> Dictionary:
	var r := {"id": id}
	var keys := fields.map(func(f): return str(f.get("key", "")))
	if fields.is_empty() or keys.has("name"):
		r["name"] = ""
	var shown := {}
	for f in fields:
		if f.has("default") and f.default != null:
			shown[str(f.get("key", ""))] = f.default
	for f in fields:
		if f.get("virtual", false) or str(f.get("kind", "")) == "note":
			continue
		if f.has("show_if") and not RPGCommand._visible(f, shown):
			continue
		if f.has("default") and f.default != null and not r.has(f.key):
			r[f.key] = RPGJson.deep_copy(f.default)
	if fields.is_empty() or keys.has("notes"):
		r["notes"] = ""
	return r


## A "virtual" field's value for a record (it is not stored; see RPGRecordTab).
## States: "duration" is "turns" when the state lasts at most one turn or more.
static func virtual_value(type: String, key: String, rec: Dictionary) -> Variant:
	if type == "states" and key == "duration":
		var hi: Variant = rec.get("turns_max", rec.get("turns_min"))
		return "turns" if typeof(hi) in [TYPE_INT, TYPE_FLOAT] and int(hi) > 0 else "until_removed"
	return null


## Writes what a "virtual" field's new value means into the record. Returns the keys it set
## (the form shows them). Fields it hides with drop_hidden are removed by the tab.
static func apply_virtual(type: String, key: String, value: Variant, rec: Dictionary) -> Array:
	if type == "states" and key == "duration" and str(value) == "turns":
		var lo := int(rec.get("turns_min", 1)) if typeof(rec.get("turns_min")) in [TYPE_INT, TYPE_FLOAT] else 1
		var hi := int(rec.get("turns_max", 0)) if typeof(rec.get("turns_max")) in [TYPE_INT, TYPE_FLOAT] else 0
		rec["turns_min"] = lo
		rec["turns_max"] = maxi(maxi(hi, lo), 1)
		return ["turns_min", "turns_max"]
	return []


## The Types records by ID: {"elements": {"name": "Elements", "entries": [{id, name}, ...]}}.
static func type_lists(data: RPGProjectData) -> Dictionary:
	var out := {}
	for r in data.records("types"):
		if r is Dictionary and r.get("entries") is Array:
			out[str(r.get("id", ""))] = {"name": str(r.get("name", r.get("id", ""))), "entries": r.entries}
	return out


## A type or element field: a dropdown of the Types list `list_id` (plus "(none)"), or a text
## field when the project has no such list.
static func _type_field(key: String, label: String, lists: Dictionary, list_id: String) -> Dictionary:
	var l: Variant = lists.get(list_id)
	if not (l is Dictionary):
		return _t(key, label)
	var opts := [""]
	var names := ["(none)"]
	for e in l.entries:
		if e is Dictionary and e.has("id"):
			opts.append(str(e.id))
			names.append(str(e.get("name", e.id)))
	return {"key": key, "kind": "choice", "options": opts, "option_labels": names, "default": "", "label": label,
		"help": "Edit the list in Types > %s." % l.name}


static func _t(key: String, label: String) -> Dictionary:
	return {"key": key, "kind": "text", "default": "", "label": label}


static func _m(key: String, label: String, help := "") -> Dictionary:
	var d := {"key": key, "kind": "multiline", "default": "", "label": label}
	if help != "":
		d["help"] = help
	return d


static func _i(key: String, label: String, def: int, lo: int, hi: int) -> Dictionary:
	return {"key": key, "kind": "int", "default": def, "min": lo, "max": hi, "label": label}


static func _b(key: String, label: String, def: bool) -> Dictionary:
	return {"key": key, "kind": "bool", "default": def, "label": label}


static func _c(key: String, label: String, options: Array, def: String) -> Dictionary:
	return {"key": key, "kind": "choice", "options": options, "default": def, "label": label}


static func _ref(key: String, ref: String, label: String) -> Dictionary:
	return {"key": key, "kind": "ref", "ref": ref, "default": "", "label": label}


static func _res(key: String, res: String, label: String) -> Dictionary:
	return {"key": key, "kind": "resource", "res": res, "default": "", "label": label}


static func _obj(key: String, label: String, fields: Array) -> Dictionary:
	return {"key": key, "kind": "object", "default": {}, "label": label, "fields": fields}


static func _ids(list: Array) -> Array:
	var out := []
	for x in list:
		if x is Dictionary and x.has("id"):
			out.append(str(x.id))
	return out


static func _labels(list: Array) -> Array:
	var out := []
	for x in list:
		if x is Dictionary and x.has("id"):
			out.append(str(x.get("label", x.id)))
	return out


static func _stat_fields(stats: Array, def: int) -> Array:
	var out := []
	for s in stats:
		out.append({"key": str(s.id), "kind": "int", "default": def, "label": str(s.get("label", s.id)),
			"min": -999999, "max": 999999})
	return out


static func _resource_fields(resources: Array) -> Array:
	var out := []
	for r in resources:
		out.append({"key": str(r.id), "kind": "int", "default": 0, "min": 0, "max": 999999, "label": str(r.get("label", r.id))})
	return out


static func _equip_fields(slots: Array) -> Array:
	if slots.is_empty():
		slots = [{"id": "weapon", "kind": "weapon"}, {"id": "shield", "kind": "armor"}, {"id": "body", "kind": "armor"}, {"id": "accessory", "kind": "armor"}]
	var out := []
	for s in slots:
		out.append({"key": str(s.id), "kind": "ref", "ref": "weapon" if str(s.get("kind", "armor")) == "weapon" else "armor", "default": "", "label": str(s.get("name", s.id)),
			"equip_slot": str(s.id)})
	return out


## Traits: the rule system's trait kinds (rules.json "traits"). "Of" is picked by what the kind
## names (its id_ref: a state, an element, a stat...), and Value shows only for kinds with one.
static func _traits(trait_kinds: Array, type_lists: Dictionary = {}, stats: Array = []) -> Dictionary:
	var defs := trait_kinds.filter(func(t): return t is Dictionary and t.has("kind"))
	if defs.is_empty():
		for k in ["element_rate", "state_rate", "state_resist", "stat_rate", "attack_element", "extra_attack"]:
			defs.append({"kind": k, "label": k.capitalize(), "id_ref": str(RPGValidator.TRAIT_REFS.get(k, "")),
				"value": "int" if k == "extra_attack" else ("" if k in ["state_resist", "attack_element"] else "percent"),
				"default": 1 if k == "extra_attack" else 100})
	var kinds := []
	var labels := []
	var of_cases := {}
	var value_cases := {}
	for t in defs:
		var k := str(t.kind)
		kinds.append(k)
		labels.append(str(t.get("label", k.capitalize())))
		var of := _of_field(str(t.get("id_ref", "")), type_lists, stats)
		if not of.is_empty():
			of_cases[k] = of
		match str(t.get("value", "")):
			"percent":
				value_cases[k] = {"kind": "int", "default": int(t.get("default", 100)), "min": -9999, "max": 9999, "label": "Rate %"}
			"int":
				value_cases[k] = {"kind": "int", "default": int(t.get("default", 1)), "min": -9999, "max": 9999, "label": "Value"}
			"":
				pass
			_:
				value_cases[k] = {"kind": "int", "default": int(t.get("default", 0)), "min": -9999, "max": 9999, "label": "Value"}
	return {"key": "traits", "kind": "list", "default": [], "label": "Traits", "item_fields": [
		{"key": "kind", "kind": "choice", "options": kinds, "option_labels": labels, "default": kinds[0], "label": "Kind"},
		{"key": "id", "kind": "variant", "by": "kind", "default": "", "label": "Of", "cases": of_cases},
		{"key": "value", "kind": "variant", "by": "kind", "default": null, "label": "Value", "cases": value_cases}]}


## The "Of" field for an id_ref: a record picker (state, skill, common event), a Types dropdown
## (element, skill type, equipment slot...) or a stat dropdown. {} for none.
static func _of_field(id_ref: String, type_lists: Dictionary, stats: Array) -> Dictionary:
	match id_ref:
		"":
			return {}
		"state", "skill", "common_event", "item", "weapon", "armor", "actor", "class", "enemy":
			return {"kind": "ref", "ref": id_ref, "default": "", "label": id_ref.replace("_", " ").capitalize()}
		"stat":
			if stats.is_empty():
				return {"kind": "text", "default": "", "label": "Stat"}
			return {"kind": "choice", "options": _ids(stats), "option_labels": _labels(stats), "default": str(stats[0].id), "label": "Stat"}
	var list_id := str(RPGValidator.TYPE_LISTS.get(id_ref, ""))
	if list_id != "":
		var f := _type_field("id", id_ref.replace("_", " ").capitalize(), type_lists, list_id)
		f.erase("key")
		return f
	return {"kind": "text", "default": "", "label": id_ref.capitalize()}


## A list of Types entries (Classes > Can equip): one dropdown per row, or text rows when the
## project has no such Types list.
static func _type_list_field(key: String, label: String, lists: Dictionary, list_id: String) -> Dictionary:
	var f := _type_field("value", "Type %d", lists, list_id)
	f.erase("key")
	if str(f.kind) == "choice":
		f["options"] = f.options.slice(1)
		f["option_labels"] = f.option_labels.slice(1)
		f["default"] = f.options[0] if not f.options.is_empty() else ""
	return {"key": key, "kind": "list", "default": [], "label": label, "item_field": f, "help": f.get("help", "")}


## Skills, items and weapons: an Animations record or a built-in effect.
static func _animation_field() -> Dictionary:
	var names := {}
	for b in BUILTIN_ANIMATIONS:
		names[b] = "Built-in: %s" % b
	return {"key": "animation", "kind": "ref", "ref": "animation", "default": "", "label": "Battle animation",
		"allow": BUILTIN_ANIMATIONS, "allow_labels": names,
		"help": "An Animations record, or a built-in effect (hit, slash, fire, ice, thunder, heal). Empty: none (an attack uses the weapon's animation)."}


## The icon: an index into the project's icon sheet (System > Icon sheet, else the starter set),
## chosen from a grid of the sheet (RPGIconPicker). Old data kept the sheet's name here; it reads
## as no icon (RPGIcons.icon_index).
static func _icon_field() -> Dictionary:
	return {"key": "icon", "kind": "icon", "default": 0, "label": "Icon",
		"help": "Shown beside the name in menus, shops and battle (and as \\I[n] in messages). Click to pick from the icon sheet; search by name. The sheet is System > Icon sheet, else the starter icons."}


## An image file a tileset uses, stored as its res:// path, picked from the ChipSet images or
## any image in the project.
static func _sheet_field(key: String, label: String) -> Dictionary:
	return {"key": key, "kind": "resource", "res": "chipset", "store_path": true, "default": "", "label": label}


## Armour slots: the equipment slots that hold armour (Types > Equipment slots).
static func _armor_slot_field(equip_slots: Array) -> Dictionary:
	var ids := []
	var names := []
	for s in equip_slots:
		if s is Dictionary and s.has("id") and str(s.get("kind", "weapon" if str(s.id) == "weapon" else "armor")) != "weapon":
			ids.append(str(s.id))
			names.append(str(s.get("name", s.id)))
	if ids.is_empty():
		ids = ["shield", "body", "accessory"]
		names = ["Shield", "Body", "Accessory"]
	return {"key": "slot", "kind": "choice", "options": ids, "option_labels": names, "default": "body" if ids.has("body") else ids[0], "label": "Slot",
		"help": "Which equipment slot this armour goes in (Types > Equipment slots)."}


static func _ids_of_kind(list: Array) -> Array:
	var out := []
	for x in list:
		if x is Dictionary and x.has("kind"):
			out.append(str(x.kind))
	return out


## Growth shape name -> exponent: the runtime's built-in shapes plus rules.json "growth_shapes".
static func growth_shapes(rule_def: Dictionary) -> Dictionary:
	var out := {"linear": 1.0, "early": 0.75, "late": 1.5}
	var extra: Variant = rule_def.get("growth_shapes", {})
	if extra is Dictionary:
		for k in extra:
			if typeof(extra[k]) in [TYPE_INT, TYPE_FLOAT]:
				out[str(k)] = float(extra[k])
	return out


## A class's own experience curve parameters (override the rules.json "exp_curve").
## basis_extra_acceleration (RPG Maker VX Ace): basis, extra, acc_a, acc_b;
## basis_inflation (XP, the default): basis, inflation.
static func _exp_curve_fields(rule_def: Dictionary) -> Array:
	var curve: Dictionary = rule_def.get("exp_curve", {}) if rule_def.get("exp_curve") is Dictionary else {}
	match str(curve.get("type", "basis_inflation")):
		"basis_extra_acceleration":
			return [
				_i("basis", "Base value", int(curve.get("basis", 30)), 10, 50),
				_i("extra", "Extra value", int(curve.get("extra", 20)), 0, 40),
				_i("acc_a", "Acceleration A", int(curve.get("acc_a", 30)), 10, 50),
				_i("acc_b", "Acceleration B", int(curve.get("acc_b", 30)), 10, 50),
			]
		"basis_inflation":
			return [_i("basis", "Basis", int(curve.get("basis", 25)), 1, 100), _i("inflation", "Inflation", int(curve.get("inflation", 30)), 1, 100)]
	# Tables and formulas are edited in rules.json.
	return []


## Boat, ship and airship (system.vehicles.<kind>); defaults are what the runtime uses when a
## value is not set, so an untouched vehicle writes nothing.
static func _vehicle_fields() -> Array:
	var out := []
	for kind in Vehicles.KINDS:
		var d: Dictionary = Vehicles.DEFAULTS.get(kind, {})
		out.append(_obj(kind, str(kind).capitalize(), [
			{"key": "name", "kind": "text", "default": str(d.get("name", kind.capitalize())), "label": "Name"},
			{"key": "graphic", "kind": "graphic", "default": RPGJson.deep_copy(d.get("graphic")), "label": "Graphic"},
			{"key": "start", "kind": "location", "default": null, "label": "Start position",
				"help": "Where it waits when a new game starts. The RPG tab's \"Set starting position\" menu sets it too."},
			{"key": "bgm", "kind": "sound", "res": "music", "default": null, "label": "Music while riding"},
			_i("speed", "Speed", int(d.get("speed", 4)), 1, 6),
		]))
	return out


## Enemy action pattern conditions (RPGBattleCore._enemy_condition).
static func _enemy_condition_fields() -> Array:
	return [
		{"key": "kind", "kind": "choice", "options": ["always", "turn", "hp", "switch"], "option_labels": ["Always", "Turn", "Own HP %", "Switch"], "default": "always", "label": "When"},
		{"key": "n", "kind": "int", "default": 1, "min": 0, "max": 9999, "label": "Turn", "show_if": {"key": "kind", "equals": "turn"}},
		{"key": "every", "kind": "int", "default": 0, "min": 0, "max": 9999, "label": "Then every (0 = once)", "show_if": {"key": "kind", "equals": "turn"}},
		{"key": "op", "kind": "choice", "options": ["<=", "<", ">=", ">", "==", "!="], "option_labels": ["≤", "<", "≥", ">", "=", "≠"], "default": "<=", "label": "HP %", "show_if": {"key": "kind", "equals": "hp"}},
		{"key": "percent", "kind": "int", "default": 50, "min": 0, "max": 100, "label": "Percent", "show_if": {"key": "kind", "equals": "hp"}},
		{"key": "id", "kind": "ref", "ref": "switch", "default": "", "label": "Switch", "show_if": {"key": "kind", "equals": "switch"}},
		{"key": "value", "kind": "bool", "default": true, "label": "is ON", "show_if": {"key": "kind", "equals": "switch"}},
	]


## Effects of skills and items (RPGRuleSystem.apply_action), each kind with its own fields:
## Recover / Damage: resource, % of its maximum and a flat amount; Add / Remove State: the state
## and a chance %; Grow: a stat and how much; Learn Skill: the skill; Common Event: the common
## event (run after the item or skill is used).
static func _effects(resources: Array = [], stats: Array = []) -> Dictionary:
	var res_ids := _ids(resources)
	var res_labels := _labels(resources)
	if res_ids.is_empty():
		res_ids = ["hp"]
		res_labels = ["HP"]
	var amounts := {"kind": "int", "default": 0, "min": 0, "max": 999999, "label": "Plus a flat amount"}
	return {"key": "effects", "kind": "list", "default": [], "label": "Effects", "item_fields": [
		{"key": "kind", "kind": "choice", "options": EFFECT_KINDS, "option_labels": EFFECT_LABELS, "default": "recover", "label": "Kind"},
		{"key": "resource", "kind": "choice", "options": res_ids, "option_labels": res_labels, "default": res_ids[0], "label": "Resource",
			"show_if": {"key": "kind", "equals": ["recover", "damage"]}},
		{"key": "percent", "kind": "int", "default": 0, "min": 0, "max": 100, "label": "% of maximum",
			"show_if": {"key": "kind", "equals": ["recover", "damage"]}},
		{"key": "amount", "kind": "variant", "by": "kind", "default": 0, "label": "Amount", "cases": {
			"recover": amounts, "damage": amounts,
			"grow": {"kind": "int", "default": 1, "min": -9999, "max": 9999, "label": "Raise by"}}},
		{"key": "chance", "kind": "int", "default": 100, "min": 0, "max": 100, "label": "Chance %",
			"show_if": {"key": "kind", "equals": ["add_state", "remove_state"]}},
		{"key": "id", "kind": "variant", "by": "kind", "default": "", "label": "Of", "cases": {
			"add_state": {"kind": "ref", "ref": "state", "default": "", "label": "State"},
			"remove_state": {"kind": "ref", "ref": "state", "default": "", "label": "State"},
			"learn_skill": {"kind": "ref", "ref": "skill", "default": "", "label": "Skill"},
			"common_event": {"kind": "ref", "ref": "common_event", "default": "", "label": "Common event",
				"help": "Runs after the item or skill is used (in battle: after the action; from the menu: the menu closes first)."},
			"grow": _of_field("stat", {}, stats)}}]}
