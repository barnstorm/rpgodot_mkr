class_name RPGExtension
extends Node
## Base class for extension entry scripts (manifest "entry_scripts"). One instance per script is
## made when the game boots and lives as long as the game. Extending this class is optional: any
## Node or RefCounted script works, and gets `rpg`, `extension_id` and `manifest` set when it
## declares them.
##
## The host calls these methods when the script defines them (all optional):
##   _extension_ready()                         after every entry script exists
##   on_title_shown(), on_new_game(), on_game_loaded(), on_quitting()
##   on_map_entered(map_id), on_map_left(map_id), on_player_stepped(cell, region, terrain)
##   on_menu_opened(menu), on_menu_closed()
##   on_battle_started(args), on_battle_ended(outcome, result)
##   on_actor_levelled(actor_id, old_level, new_level)
##   on_option_changed(key, value)              one of this extension's option rows changed
##   on_message_opened(params), on_message_char(character, index, instant), on_message_closed()
##   on_autosaved(slot, ok, reason)
## Save sections (manifest "save_sections"; without these the host saves section(ns) itself):
##   save_section(ns) -> Dictionary, load_section(ns, data) (data is {} for a new game),
##   migrate_section(ns, data, from_version) -> Dictionary
## Main menu and options:
##   adjust_menu(layout: Array, config: Dictionary)  reorder, hide or add entries in place
##   option_entries() -> Array                     option rows made at run time (from settings)
## Condition kinds (manifest "conditions": [{kind, label, fields, method}]): method(cond, where).

## The RPG service (the `RPG` autoload in a game, a test instance in tests).
var rpg: Node
var extension_id := ""
## The extension's manifest.json (with "_dir").
var manifest: Dictionary = {}


## A setting from Tools > Extensions (rpg/extensions.json), or the manifest default.
func setting(key: String, fallback: Variant = null) -> Variant:
	return rpg.extension_setting(extension_id, key, fallback) if rpg != null else fallback


## The player's value of one of this extension's option rows.
func option(key: String, fallback: Variant = null) -> Variant:
	return rpg.option(extension_id, key, fallback) if rpg != null else fallback


## The live Dictionary of a save section the host keeps for this extension ("" = the
## extension's ID). Saved with the game, emptied by a new game, replaced by a load.
func section(ns := "") -> Dictionary:
	if rpg == null or rpg.extensions == null:
		return {}
	return rpg.extensions.section(ns if ns != "" else extension_id)
