# For programmers

Everything the editor makes is plain data, and everything the game shows is an ordinary Godot scene or script. This page shows where you plug in your own code. The full contracts are in [docs/ARCHITECTURE.md](https://github.com/barnstorm/rpgodot_mkr/blob/main/docs/ARCHITECTURE.md).

## The `RPG` autoload

Game code talks to the runtime through the `RPG` autoload:

```gdscript
RPG.set_switch("door_unlocked", true)
RPG.set_variable("fish_caught", RPG.get_variable("fish_caught") + 1)
RPG.set_self_switch("town", "chest_1", "A", true)
await RPG.run_common_event("full_heal")
RPG.switch_changed.connect(func(id, on): print(id, on))
```

Useful members:

| Member | What it does |
| --- | --- |
| `get_switch`, `set_switch`, `get_variable`, `set_variable`, `get_self_switch`, `set_self_switch` | The game's memory |
| `run_common_event(id)`, `run_commands(commands)` | Run event commands from code (await them) |
| `current_map()` | The map node being played |
| `extension(id)`, `extension_enabled(id)`, `extension_setting(id, key)`, `option(id, key)` | Extensions and their settings |
| `map_overlay_layer("map" / "screen" / "hud")` | A layer to draw on, above the map, the screen or the HUD |
| `attach_to_character("player" / "follower:N" / event_id, node)` | Make a node follow a character |
| `register_text_code`, `register_text_tag`, `register_text_preprocessor` | New message codes |
| `register_condition_kind(kind, check)` | A new condition kind |
| `battle_hook(hook, args, mode)` | Run a battle hook (below) |

Signals: `switch_changed`, `variable_changed`, `self_switch_changed`, `title_shown`, `new_game_started`, `game_loaded`, `map_entered`, `map_left`, `player_stepped(cell, region, terrain)`, `menu_opened`, `menu_closed`, `battle_started`, `battle_ended(outcome, result)`, `actor_levelled`, `quitting`, `option_changed`, `message_opened`, `message_char`, `message_closed`, `autosaved`, `error_reported`, and the battle signals `battle_scene_ready`, `turn_started`, `action_chosen`, `damage_calculated`, `state_changed`, `battler_defeated`, `victory`.

## Custom event commands

A custom command is a script in an extension. Every project has `extensions/project/`.

*Tools > Extensions > New command…* writes a ready-to-edit script and lists it in the manifest. The command then appears in the command picker, with a form built from its fields.

```gdscript
extends RPGCommand

static func descriptor() -> Dictionary:
	return {"type": "shake_camera", "category": "screen", "label": "Shake camera", "fields": [
		{"key": "strength", "kind": "float", "default": 4.0, "min": 0.0, "max": 32.0},
		{"key": "seconds", "kind": "float", "default": 0.5},
		{"key": "wait", "kind": "bool", "default": true}]}

func summary(args: Dictionary) -> String:
	return "Shake camera: %s for %ss" % [args.strength, args.seconds]

func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var done: Signal = ctx.screen.shake(args.strength, args.seconds)
	if args.wait and not (await ctx.wait_signal(done)).ok:
		return RPGResult.cancelled()
	return RPGResult.ok()
```

**Field kinds**: `int`, `float`, `bool`, `text`, `multiline`, `choice` (`options`), `ref` (a switch, variable, item, weapon, armor, actor, skill, state, enemy, troop, map, event, common_event or class), `resource` (a charset, faceset, picture, music, sound, scene, battleback or tile), `location`, `facing`, `sound`, `condition`, `operand`, `list`, `object`, `commands` (a nested command list), `route`. Any field can have `show_if`, `default`, `min`, `max`, `required`, `label` and `help`.

**When things go wrong:**

- Unknown or disabled commands are kept in the data. They show as unavailable and block export, but are never deleted.
- An error in a command stops only that event (according to the manifest's `error_policy`) and always gives the player control back.
- Commands await with `ctx.wait_signal(...)`, so a cancelled event (map change, load) cancels them cleanly.

## Extensions

An extension is a folder `extensions/<id>/` with a `manifest.json`:

```json
{
	"schema_version": 1,
	"id": "my_ext",
	"name": "My extension",
	"version": "1.0.0",
	"api_versions": [1],
	"error_policy": "fail_event",
	"entry_scripts": ["my_ext.gd"],
	"commands": ["commands/do_thing.gd"],
	"settings_schema": [
		{"key": "speed", "kind": "float", "label": "Speed", "default": 1.0}
	]
}
```

Only extensions turned on in *Tools > Extensions* load. What a manifest can declare:

| Key | Gives you |
| --- | --- |
| `commands` | Event commands |
| `entry_scripts` | Scripts made once when the game boots (extend `RPGExtension`, or any Node). They get `on_new_game`, `on_game_loaded`, `on_map_entered(map_id)`, `on_map_left`, `on_player_stepped(cell, region, terrain)`, `on_menu_opened` / `on_menu_closed`, `on_battle_started` / `on_battle_ended`, `on_actor_levelled`, `on_title_shown`, `on_quitting` |
| `settings_schema` | A settings form in *Tools > Extensions*, saved in `rpg/extensions.json`; read with `RPG.extension_setting(id, key)` |
| `save_sections` | `[{namespace, version}]`: data saved, loaded and migrated with the game |
| `menu_entries` | Main-menu entries (a common event, a scene or a method), with show/enable conditions |
| `options` | Rows on the options screen; read with `RPG.option(id, key)` |
| `conditions` | New condition kinds for page conditions and Conditional Branch |
| `custom_fields` | Extra Database fields on existing record types, and on maps and event pages ("Plugin fields") |
| `database_types` | A whole new Database tab, stored in `rpg/database/<type>.json` |
| `requires_capabilities` | What the extension needs from the rule system |

The twelve [kit plugins](Plugins.md) in `addons/rpg/extensions/` are complete examples of every key.

## Message codes

```gdscript
RPG.register_text_code("XY", func(arg, info): return "[" + arg + "]")
```

A code is `\XY[arg]`; a tag is `<name>`, `<name:arg>` or `</name>`. A handler returns a String (inserted, with its own codes read too) or a Dictionary with `text`, `bbcode` (formatting), `action` (a Callable fired when the typewriter reaches it), `wait` (seconds) or `flags` (message-wide settings).

## Run Scene: your own minigames and screens

Any scene with a `start(args, context)` method that emits `finished(result)` or `cancelled(reason)` can be started from an event with **Run Scene**, and its result stored in a variable. The fishing minigame in [`scenes/fishing/`](https://github.com/barnstorm/rpgodot_mkr/tree/main/scenes/fishing) is an example.

## Replacing default screens

The title, menu, shop, save, name input, game over, options, debug and battle screens are scripts in `addons/rpg/runtime/ui/`. Point `rpg/project.json` `"scenes"` at your own to replace any of them. The battle can also be replaced per map (Map properties > Battle scene) or per Battle Processing command.

## Battle hooks

The default battle calls hooks you can use from an entry script (`on_<hook>`) or by connecting to the `RPG` signal of the same name:

| Hook | Can change |
| --- | --- |
| `battle_scene_ready(scene)` | (notify) |
| `turn_started(battler)` | (notify) |
| `action_chosen(user, action, targets)` | Return `{action, targets}` to replace them, or `{cancel: true}` |
| `damage_calculated(user, target, action, value)` | Return a new damage value |
| `state_changed(battler, state_id, added)` | (notify) |
| `battler_defeated(battler)` | (notify) |
| `victory(rewards)` | Return changed rewards |

And three questions the battle asks entry scripts:

- `battle_members(members) -> Array`: who fights (the party formation plugin uses it).
- `victory_scene(info) -> Node`: a node that replaces the reward messages (the victory aftermath plugin).
- `battle_popup(battler, text, style, node) -> Control`: replaces a damage popup (the enemy gauges plugin).

`scene.battler_node(battler)` gives a node that follows a battler in both views, for gauges and effects.

## Rule systems

Stats and formulas live in `rpg/rules/<name>/rules.json`, plus an optional `rules.gd`. See [Rule systems](Rule-Systems.md).

## Schemas and tooling

- **JSON Schema** on the Database tab (or `RPGSchema.write(registry)` from code) writes a JSON Schema for event files, for completion in VS Code.
- `--rpg-smoke` checks a build headless ([Lesson 8](Lesson-8-Playtest-Debug-and-Share.md)).
- The headless tests are described in [Testing the kit](Testing-the-Kit.md).
