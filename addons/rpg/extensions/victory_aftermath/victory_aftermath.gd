extends "res://addons/rpg/runtime/rpg_extension.gd"
## Victory aftermath (kit plugin "victory_aftermath").
## Replaces the battle's reward messages (the battle scene's victory_scene query) with one
## results screen: a row per actor whose EXP bar fills from the old to the new amount ("LEVEL
## UP!" when it crosses a level), the gold and the items found. Then, when the setting is on, one
## level-up screen per actor who went up: old and new stats, new skills and a quote from the
## actor's custom fields "level_up_quotes" / "new_skill_quotes" (one per line).
## In auto battle the results are skipped (setting), so automatic battles stay quick.

const SCREEN := "res://addons/rpg/extensions/victory_aftermath/aftermath_screen.gd"

## The screen shown last (tests and screenshots; freed once the battle closes it).
var last_screen: Node = null
## Aftermaths shown, and the pages of the last one once it finished (tests).
var shown_count := 0
var last_pages: Array = []
var last_info: Dictionary = {}


## The battle scene's replaceable victory step. `info`: the rewards {exp, gold, items} plus
## actors [{actor, id, name, old_level, new_level, old_exp, new_exp, level_ups, old_stats,
## new_stats, gains, learned}], battle (the scene) and auto.
func victory_scene(info: Dictionary) -> Node:
	if bool(info.get("auto", false)) and bool(setting("skip_auto", true)):
		return null
	if rpg.ui == null:
		return null
	var node: Node = rpg.ui.open_scene(SCREEN)
	if node == null:
		return null
	node.setup(self, info)
	last_screen = node
	last_info = info
	last_pages = []
	shown_count += 1
	node.finished.connect(func() -> void: last_pages = node.pages_shown.duplicate())
	var music: Variant = setting("music", {})
	if music is Dictionary and str(music.get("file", "")) != "" and rpg.audio != null:
		rpg.audio.play_bgm(music)
	return node


## The quote for an actor's level-up screen: a new-skill quote when it learned one (and has
## any), else a level-up quote; "" when it has none. `rng`: the chooser (a fresh one if null).
func quote_for(actor_id: String, learned_skill: bool, rng: RandomNumberGenerator = null) -> String:
	var lines: Array = []
	if learned_skill:
		lines = _lines(rpg.extensions.custom_field("actors", actor_id, "new_skill_quotes", ""))
	if lines.is_empty():
		lines = _lines(rpg.extensions.custom_field("actors", actor_id, "level_up_quotes", ""))
	if lines.is_empty():
		return ""
	var r := rng if rng != null else RandomNumberGenerator.new()
	return str(lines[r.randi_range(0, lines.size() - 1)])


static func _lines(v: Variant) -> Array:
	var out := []
	if v is Array:
		for x in v:
			if str(x).strip_edges() != "":
				out.append(str(x).strip_edges())
	elif v != null:
		for x in str(v).split("\n", false):
			if x.strip_edges() != "":
				out.append(x.strip_edges())
	return out
