# RPG Kit: architecture and internal contracts

This is the implementation map for the addon described in `Godot as RPG Maker Design Spec.md`
(revision 1.2). The spec is the source of truth for behaviour; this file fixes the concrete
names, paths and data shapes the code uses so that the parts agree.

Godot baseline: **4.5** (tested with 4.5.1 stable). Language: GDScript only. Indent with tabs.

## Folder layout

```
project.godot                     sample project (the addon is developed in place)
addons/rpg/
  plugin.cfg, plugin.gd           EditorPlugin entry (editor only)
  core/                           shared by editor AND runtime; must never touch EditorInterface/EditorPlugin
    rpg_json.gd        RPGJson        parse/normalise/stable stringify/atomic write
    rpg_ids.gd         RPGIds         ID rules (lowercase ascii, digits, _, starts with letter)
    rpg_project_data.gd RPGProjectData loads every rpg/ file into registries
    rpg_validator.gd   RPGValidator   structure + reference checks -> RPGProblem list
    rpg_formula.gd     RPGFormula     restricted formula language (parser + evaluator)
    rpg_random.gd      RPGRandom      seeded RNG with savable state
    rpg_quick_events.gd RPGQuickEvents template compiler
    rpg_image_map.gd   RPGImageMap    image-backed maps: size checks, limits, review report, validation
    profiles/          profile descriptors (JSON) + RPGProfile loader
  import/                         asset import (pure code, usable by editor tools and at runtime)
    rpg_chipset_2k.gd  RPGChipset2k   RM2000/2003 ChipSet decoder (autotiles, animation, lower/upper)
    rpg_tileset_builder.gd RPGTilesetBuilder  builds a Godot TileSet from a decoded sheet + overrides
    rpg_autotile.gd    RPGAutotile    neighbour masks, 47/48-variant selection, painting helpers
    rpg_charset.gd     RPGCharset     CharSet/FaceSet frame rectangles
    rpg_windowskin.gd  RPGWindowSkin  System graphic -> Theme
  runtime/                        the game; reads exported files only
    rpg_service.gd     (autoload "RPG", no class_name)
    rpg_game_state.gd  RPGGameState   switches, variables, self switches, party, items, gold
    rpg_battler.gd     RPGBattler     actor/enemy runtime data
    rpg_command.gd     RPGCommand     base class for every command (built-in and custom)
    rpg_context.gd     RPGContext     restricted API handed to commands
    rpg_result.gd      RPGResult      typed command result
    rpg_cancel_token.gd RPGCancelToken
    rpg_interpreter.gd RPGInterpreter lifecycle, call stack, budget
    rpg_scheduler.gd   RPGScheduler   main queue + parallel interpreters
    rpg_command_registry.gd RPGCommandRegistry  manifests -> descriptors + command objects
    rpg_extension_host.gd RPGExtensionHost  runs enabled extensions (entry scripts, hooks)
    rpg_extension.gd   RPGExtension   optional base class of extension entry scripts
    rpg_map.gd         RPGMap         map scene root script
    rpg_character.gd   RPGCharacter   grid mover (player, events, followers)
    rpg_event.gd       RPGEvent       map event node (pages, triggers)
    rpg_player.gd      RPGPlayer
    rpg_movement.gd    RPGMovement    passability, occupancy, reservations
    rpg_save_service.gd RPGSaveService
    commands/          built-in commands, listed in commands/manifest.json
    ui/                default systems (message box, title, menu, shop, battle, ...)
    rules/classic/     Classic (XP-style) rule system
  extensions/                     kit plugins (menu_plus, message_plus, letter_sounds, gab,
                                  save_plus, enemy_gauges, victory_aftermath, party_formation,
                                  bestiary); off until a project lists them
  editor/                         editor-only UI (main screens, docks, dialogs)
rpg/                              project data (see spec "Project layout")
assets/                           asset packs (each with pack.json)
extensions/project/               the automatic project extension
scenes/                           custom scenes (run_scene, battles)
tests/                            headless test runner and suites
tools/                            headless build scripts (sample project generator)
```

## Running Godot headless

```
GODOT="path/to/Godot_v4.5.1-stable_win64_console.exe"   # or put the path in tools/godot_path.local for tools/t.sh
"$GODOT" --headless --path . --import          # refresh class cache after adding class_name scripts
"$GODOT" --headless --path . --script res://tests/run_tests.gd   # all suites
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- --suite=formula
```

Test suites live in `tests/suites/test_*.gd`, extend `res://tests/rpg_test_case.gd`, and define
`func test_*()` methods (may be coroutines). Use `assert_eq(a, b, msg)`, `assert_true(c, msg)`,
`assert_false`, `assert_ne`. The runner prints PASS/FAIL per test and exits non-zero on failure.

## Data shapes (canonical)

All top-level JSON files carry `"schema_version": 1`. IDs match `^[a-z][a-z0-9_]*$`.
Numbers that are whole are normalised to `int` on load (`RPGJson.parse_file`).

* `rpg/project.json`: `{schema_version, project_id, name, profile_ref, rules, extensions: ["project"], scenes: {title, message_box, menu, shop, save, battle, name_input, game_over, options}}`
* `rpg/profile.json`: `{schema_version, profile: "rm2k", tile_size: 16}`
* `rpg/state.json`: `{schema_version, switches: [{id, label, folder, description}], variables: [{id, type: "int"|"float"|"bool"|"string", default, label, folder, description}]}`
* `rpg/map_index.json`: `{schema_version, maps: [{id, name, parent, order, scene, properties, events}], favourites: []}`
* `rpg/maps/<id>.map.json`: `{schema_version, id, display_name, tileset, width, height, scroll: "none"|"loop_v"|"loop_h"|"loop_both", music, bgs, battle_background, disable_dash, parallax, encounters: {steps, groups: [{troop, weight, regions: []}]}, notes, custom, image_map?}`
  - optional `image_map: {version: 1, base: "res://...png", foreground: "res://...png" | null}`. A map is
    **image-backed** exactly when `image_map` is a Dictionary with a non-empty `base`; no key means a
    tile map (old files need no migration). See *Image-backed maps* below.
* `rpg/maps/<id>.events.json`: as the spec's canonical example.
* `rpg/common_events.json`: `{schema_version, common_events: [{id, name, trigger: "none"|"autorun"|"parallel", switch, commands}]}`
* `rpg/database/<type>.json`: `{schema_version, records: [ {id, name, notes, custom: {}, ...} ]}`
  types: actors, classes, skills, items, weapons, armors, enemies, troops, states, animations, tilesets, types, terms.
  `rpg/database/system.json`: `{schema_version, system: {...}}`.
* Tileset record: `{id, name, profile: "rm2k", sheet: "res://assets/<pack>/ChipSet/<file>.png"}`;
  user overrides in `rpg/tileset_overrides/<tileset_id>.json`: `{schema_version, tiles: {"<tile_key>": {passage, flags, terrain}}}`.

Conditions: `{kind: "switch", id, value?: true}`, `{kind: "variable", id, op, value}` (value may be
`{"variable": id}`), `{kind: "self_switch", id: "A".."D", value?: true}`, `{kind: "item", id, count?: 1}`,
`{kind: "actor", id}`, `{kind: "gold", op, value}`. Ops: `==` (also `=`), `!=`, `<`, `<=`, `>`, `>=`.

Commands: `{type, ...fields}`; an optional `"skip": true` switches a line off (Toggle skip).
Branches nest lists: `if.then/else`, `loop.commands`, `show_choices.choices[].then`, `show_choices.cancel`.

## TileSet contract (generated by import/, read by runtime and editor)

A map scene (`rpg/maps/<id>.tscn`) has a root `Node2D` with script `res://addons/rpg/runtime/rpg_map.gd`
and `@export var map_id: String`. Its tile children are `TileMapLayer` nodes named
`Layer1`, `Layer2`, `Layer3`, `Layer4` (the 2000/2003 profile uses Layer1 = lower, Layer2 = upper),
plus `Regions` and `Shadows`. A map may also have `Layer1Base`, drawn just below `Layer1`: it holds
the hidden base of VX/MV overlay autotiles (the sea under deep sea, the ground under a bush), is
written by `RPGAutotile` painting on `Layer1`, and is not one of `RPGMap.tile_layers` (passability
reads the visible layers). 2000/2003 TileSets have a source 4 with the deep/shallow water blend
pieces; painting switches water cells to it (TileSet meta `rpg_autotile_blend`). Generated
TileSets carry these **custom data layers**:

| name        | type | meaning |
|-------------|------|---------|
| `passage`   | int  | bitmask of directions that may be crossed: 1 down, 2 left, 4 right, 8 up (15 = open, 0 = wall) |
| `flags`     | int  | 1 bush, 2 counter, 4 ladder, 8 damage floor, 16 star (drawn above characters, ignored for passage), 32 wall (casts auto shadow) |
| `terrain`   | int  | terrain tag |
| `autotile`  | int  | autotile group index, or -1 for plain tiles |
| `tile_key`  | String | stable key used by overrides, e.g. `water_a`, `terrain_3`, `lower_17`, `upper_5`, `anim_1` |

Passability rule (runtime `RPGMovement`): walk the tile layers from top to bottom, skip empty
cells and cells whose `flags` has *star*; the first remaining cell's `passage` decides; if every
layer is empty, the cell is blocked.

Region layer: a generated TileSet (`RPGTilesetBuilder.region_tileset()`), atlas coords `(n % 16, n / 16)`
is region `n` (1..255). Shadow layer: a 16-tile TileSet, atlas x = quarter mask
(1 TL, 2 TR, 4 BL, 8 BR). Navigation layer (image-backed maps): a 16-tile TileSet
(`RPGTilesetBuilder.navigation_tileset()`), atlas x = passage bitmask 0..15 (custom data `passage`).

Passability on a map **with a `Navigation` layer**: the layer's mask decides, and a cell without a
mask tile is blocked (bitmask 0 is stored as no tile). Visible tiles still supply `flags` (bush,
counter, ladder, damage floor) and `terrain`, but not passage. Maps without the layer use the rule
above unchanged (including "a map with no tiles at all is open everywhere").

## Image-backed maps

`RPGImageMap` (core) holds the rules shared by the new-map dialog, Map Properties, the validator and
the tests: the **map tile size** (the map tileset's profile tile size, else `data.tile_size()`),
`check_size` / `check_image` (zero, unreadable, not a multiple of the tile size with the nearest
sizes above and below, over `MAX_SIDE` = 8192 px, more than 500 cells; warning over `WARN_SIDE` =
4096 px; both limits still to be confirmed per export target), the foreground size check, the
`outside_report` used by the resize review, and `problems()` for the validator.

- **Scene.** `RPGMapFiles.create_image_map` checks the image, then `create_map(..., {image_map, walkable})`
  writes the standard three files with a hidden `TileMapLayer` named `Navigation` (not in
  `RPGMap.tile_layers`; saved with the scene, TileSet assigned in `RPGMap.assign_tilesets` like
  `Regions` and `Shadows`), filled with 15 or left empty, and `scroll` = `none`.
- **Images.** `RPGMap.apply_image_map(props)` builds `ImageBase` (`Sprite2D`, z -1, `centered = false`,
  nearest filter, at (0, 0), scale 1) and the optional `ImageForeground` (z 5). It is called from
  `RPGMap.start` (game) and `RPGMapFiles.load_map` (editor), so origin and scale match by
  construction. The sprites have no `owner`, so `save_scene` never packs them. Saves hold no image data.
- **Editor.** Passability mode (`RPGMapView.mode == "passability"`, F4) paints the mask with the brush
  `{kind: "passage", passage: bits}` (pencil, rect, ellipse, fill, eyedropper; undo snapshots include
  the layer); the passability overlay is always on there. The foreground can be shown, dimmed or hidden
  (editor only). "Shift contents" is off. A size change goes through `RPGMainScreen._resize_review`
  (refuses while a start position would fall outside; otherwise backs up the three files to
  `rpg/.backup/map_<id>_<time>/` with `RPGMapFiles.backup_map`, then resizes). `check_disk_changes`
  reloads changed images and re-checks their size.
- **Checks.** `RPGValidator.image_map_problems` (part of `full`, so playtest and export run it):
  missing images, misaligned or oversized images, a base that no longer matches the map size, a
  foreground of another size, looping; warnings for mipmaps / lossy import. `RPGDeploy.unused_asset_excludes`
  keeps the images because their paths appear in the map properties.

## Draw order (z_index)

| Content | `z_index` |
| --- | --- |
| Parallax background (`ParallaxBackground`, canvas layer -10) | — |
| Image-backed map base image (`ImageBase`) | -1 |
| Tile layers `Layer1` to `Layer4`, `Layer1Base`, `Shadows` | 0 |
| Events with priority *below* | 1 |
| Player, followers, boats, events with priority *same* | 2 |
| Star-flag tiles (`RPGTilesetBuilder.STAR_Z_INDEX`) | 3 |
| Events with priority *above* | 4 |
| Image-backed map foreground (`ImageForeground`) | 5 |
| Airship | 6 |
| `Regions` (editor only; hidden at runtime) | 80 |
| Debug overlay | 90 |
| `MapOverlay` attachment space | 100 |
| Editor overlay (grid, passability, event markers) | 200 |

`Navigation` is never drawn (hidden at runtime and in the editor; the passability overlay shows it).

## Asset profiles and decoders

| Profile | Tile | Decoder | Tileset record | Tile keys |
| --- | --- | --- | --- | --- |
| `rm2k` (2000/2003) | 16 | `import/rpg_chipset_2k.gd` | `{sheet}` (ChipSet 480×256) | `water_a..c`, `terrain_0..11`, `anim_0..2`, `lower_i`, `upper_i` |
| `xp` | 32 | `import/rpg_tilesheet_xp.gd` | `{sheet, autotiles: [7 paths]}` | `autotile_0..6`, `tile_i` |
| `vx` (VX/Ace), `mv` (MV/MZ) | 32 / 48 | `import/rpg_tilesheet_vx.gd` | `{sheets: {a1..a5, b..e}}` | per-sheet keys, see the decoder header |

- All decoders feed one generic layout (`RPGTilesetBuilder.new_layout`). The builder then makes the
  TileSet with the same custom data layers as above, so the runtime and editor never branch on the
  profile.
- `import/rpg_autotile_layout.gd` holds the quarter-tile tables:
  - the 2000/2003 47-variant table
  - the XP 3×4 table
  - the VX/MV floor (2×3), wall (2×2) and waterfall tables
- For non-rm2k TileSets, `RPGTilesetBuilder.atlas_for_key(key, tile_set)` must be given the TileSet;
  the generated sources are listed in its metadata. Tile size comes from the TileSet everywhere:
  map view, palette, runtime map, characters and message faces.
- Each decoder file's header documents its sheet layout and the cases it does not decode.
- The tests in `tests/suites/test_profiles.gd` build synthetic sheets with one colour per quarter
  tile and check every variant against hand-written expected tables.

## Tile settings (passability overrides)

`rpg/tileset_overrides/<tileset_id>.json` = `{"schema_version": 1, "tiles": {"<tile_key>": {"passage", "flags", "terrain"}}}`.
`RPGTileSettings` (editor/tileset) reads and writes it, and the builder applies it after
defaults and `pack.json` metadata. A value equal to the default is dropped, except for tiles
whose default was guessed: an explicit value there records that someone reviewed it. Unknown keys
are kept.

## Editor safety nets

- **Atomic writes.** `RPGJson.write_atomic` writes `X.tmp`, then renames `X` to `X.bak`, `X.tmp`
  to `X`, and deletes `X.bak`. `RPGJson.recover_interrupted` resolves any leftovers. The plugin
  offers recovery on startup.
- **Outside edits.** `RPGMainScreen.remember_disk` / `check_disk_changes` compare file modification
  times when Godot regains focus or rescans the filesystem.
- **Capabilities.** `RPGExportCheck.capability_problems` compares battle scene `CAPABILITIES` and
  extension `requires_capabilities` with the rule system's `capabilities`. It runs before
  playtest and export.
- **Rule switching.** `RPGRuleMigration.preview` / `apply` write a backup to `rpg/.backup/` first.

## Runtime command contract

```gdscript
@tool
extends RPGCommand
static func descriptor() -> Dictionary   # {type, schema_version, category, label, fields: [...]}
func summary(args: Dictionary) -> String
func run(ctx: RPGContext, args: Dictionary) -> RPGResult   # may await
```

Field kinds: `int`, `float`, `bool`, `text`, `multiline`, `choice` (`options`), `ref` (`ref`: switch,
variable, item, weapon, armor, actor, skill, state, enemy, troop, map, event, common_event, class),
`resource` (`res`: charset, faceset, picture, music, sound, scene, battleback, tile), `location`,
`facing`, `sound`, `condition`, `operand` (number or `{variable: id}`), `list` (`item_fields`),
`object` (`fields`), `commands` (nested command list), `route` (move route). Any field may carry
`show_if: {key, equals}`, `default`, `min`, `max`, `required`, `label`, `help`.

## Extension hooks

An extension is `extensions/<id>/manifest.json` (or a kit plugin in `addons/rpg/extensions/<id>/`,
used when the project has no folder of that name). Only IDs listed in `project.json`
`"extensions"` (and not in `"disabled_extensions"`) load. `RPGCommandRegistry` reads the
manifests (editor and game); `RPGExtensionHost` (child of the `RPG` service, `RPG.extensions`)
runs them in a game. `RPG.reload_extensions(settings := {})` reloads both after
`data.project` changes (tests, `tools/plugin_shots.gd`). Manifest keys:

| Key | Shape | Wired to |
| --- | --- | --- |
| `commands` | script paths | command picker and interpreter (unchanged) |
| `entry_scripts` | script paths | one instance each at boot; Node scripts become children of the host |
| `settings_schema` | `[field]` or `{fields: [field]}` (form-builder kinds) | Tools > Extensions form, `rpg/extensions.json`, `RPG.extension_setting(id, key)` |
| `save_sections` | `[{namespace, version}]` or `["ns"]` | `RPGSaveService.extension_hooks` |
| `menu_entries` | `[{id, label, icon?, after?, before?, show_*, enable_*, common_event / scene / method, needs_actor?, args?}]` | default main menu |
| `options` | `[{key, kind: bool/choice/slider, label, default, options?, option_labels?, min?, max?, step?, help?, show_method?}]` | default options screen, `RPG.option(id, key)` |
| `conditions` | `[{kind, label, fields, method, battle?, branch_only?}]` | condition editor, validator, `RPGGameState.check_condition` |
| `custom_fields` | `{record_type: [field]}`; also `maps` and `event_pages` | Database forms (merged after the project's `custom_fields`), `RPG.extensions.custom_field(type, id, key)`; Map properties and event pages ("Plugin fields", stored in their `custom`) |
| `database_types` | `[{type, label, ref?, fields}]` | a Database tab per type (`rpg/database/<type>.json`), `RPG.data` records, `ref` fields of kind `ref`, reference checks and renames |

**Entry scripts** (`RPGExtension`, optional base): the host sets `rpg`, `extension_id` and
`manifest` when the script declares them, calls `_extension_ready()` once every entry script
exists, then relays the lifecycle signals of the `RPG` service as method calls when the script
defines them:

| `RPG` signal | Entry-script method | Emitted by |
| --- | --- | --- |
| `title_shown()` | `on_title_shown()` | `RPGGame.show_title` |
| `new_game_started()` | `on_new_game()` (after save sections are emptied) | `RPGGame.new_game`, playtest start, battle test |
| `game_loaded()` | `on_game_loaded()` | `RPGSaveService.load_data`, after the map is up |
| `map_left(map_id)` / `map_entered(map_id)` | `on_map_left` / `on_map_entered` | `RPGGame.transfer` (left only once the new map is certain; entered at the end). `RPGGame.is_first_map()` is true during the first `map_entered` after a new game or a load |
| `player_stepped(cell, region, terrain)` | `on_player_stepped` | `RPGPlayer._on_step_finished` |
| `menu_opened(menu)` / `menu_closed()` | `on_menu_opened` / `on_menu_closed` | `RPGGame.open_menu` |
| `battle_started(args)` / `battle_ended(outcome, result)` | `on_battle_started` / `on_battle_ended` | the Battle Processing command (`runtime/commands/battle.gd`), around the battle scene; outcome `""` when cancelled |
| `actor_levelled(id, old, new)` | `on_actor_levelled` | `RPG.check_levels()`: on `actor_changed`, `party_changed` and after each battle |
| `quitting()` | `on_quitting` | `RPGGame.quit_game` |
| `option_changed(key, value)` | `on_option_changed(key, value)` (own rows; key without the prefix) | options screen |
| `message_opened(params)` / `message_char(char, index, instant)` / `message_closed()` | `on_message_*` | `RPGMessageBox` (`params.flags` holds the text-code flags) |
| `autosaved(slot, ok, reason)` | `on_autosaved` | `RPGSaveService.autosave` |

`RPG.extension(id)` returns an extension's first entry script (null when off), so battle code
and other extensions can call it.

**Settings.** `rpg/extensions.json` = `{"schema_version": 1, "settings": {id: {key: value}}}`,
written by Tools > Extensions (`RPGExtensionHost.save_settings`). Missing keys use the field's
`default`.

**Save sections.** Each namespace is registered in `RPGSaveService.extension_hooks` with the
manifest version. Saving calls the entry script's `save_section(ns)`, or the host saves its own
Dictionary (`RPGExtension.section(ns)`). Loading calls `load_section(ns, data)` or replaces the
host's Dictionary; a section missing from the save gets `{}` (a save made before the extension
was on). Older versions go through `migrate_section(ns, data, from_version)`. A new game empties
every section first.

**Main menu.** `RPGExtensionHost.menu_layout(builtins, labels)` builds
`[{id, label, enabled, builtin, icon, entry, ext}]`:

1. The built-ins.
2. Manifest `menu_entries`, placed by `after` / `before`, else before `options`.
3. The `project.json` `"menu"` block: `entries`, then `order` (listed IDs first), then `hidden`.
4. Each entry script's `adjust_menu(layout, config)`.
5. Visibility and enabling: `show_switch` / `enable_switch` (switch IDs), `show_if` / `enable_if` (a condition, `{switch}` or a switch ID), `show_method` / `enable_method` (an entry-script method returning bool).

`menu_config()` merges `skip_single_actor` from the block and entry scripts' `menu_config()`.
The default menu (`ui/main_menu.gd`, `menu_items`, `command_ids()`) runs non-built-in entries
with `RPGExtensionHost.run_menu_entry`. Those entries can call a `method(menu)` (or
`method(menu, actor)` with `needs_actor`), open a scene over the menu until it emits `closed`,
`finished` or `cancelled`, or reserve a common event and close the menu. A method returning
`"close"` closes the menu.

**Options.** `option_rows()` = manifest `options` + entry scripts' `option_entries()`, each with
`id = "<ext>.<key>"`. The default options screen puts them between the built-in rows and *Done*
(scrolling past 10 rows) and keeps their values in `user://rpg_options.json` under the same id
(`load_options()` keeps every dotted key). `RPG.option(ext, key)` returns the player's value or
the row default; `RPG.extensions.set_option(id, value)` sets it from code.

**Message text.** `RPGText.expand(text, rpg, info)`:

1. Runs `RPG.text_preprocessors` (at every nesting depth; inserted text is read again up to `MAX_DEPTH`).
2. At a backslash, tries the longest registered `RPG.text_codes` name (case-insensitive). The built-in one-character codes `V S N P G C I \ . | ! > < $ ^` cannot be replaced.
3. At `<`, tries `RPG.text_tags` (`<name>`, `<name:arg>`, `</name>` registered as `"/name"`).

A handler `(arg, info)` returns:

- a String, inserted and read for codes;
- or a Dictionary `{text, codes?, bbcode, bbcode_after, width, action: Callable, wait: seconds, flags}`;
- or null.

`info = {rpg, flags, depth, params?}`; `flags` is shared by the whole message and returned as
`expand(...).flags`. `actions` come back as `[{at, call}]`. The default message box calls each
one when the typewriter reaches `at` (`_reveal_to`), also when the page is skipped.
`expand_plain` (choice labels) expands extension codes and drops all formatting.

**Conditions and fields.** Manifest `conditions` reach the editor through
`RPGCommandRegistry.condition_kinds()` (the condition editor adds them to its kind list with their
`fields`). They reach the validator through the static
`RPGCommandRegistry.declared_condition_kinds`, refreshed by every `load_all`: the kind is
accepted and its `ref` fields are reference-checked. The host binds `method` on an entry script
with `RPG.register_condition_kind(kind, Callable(cond, where) -> bool)`, where
`where = {map_id, event_id, ctx, state}`. Troop (battle) page conditions of kinds the battle
core does not know go to `RPGBattleCore.condition_reader`; the default battle scene passes them
to `rpg.state.check_condition`, but an extension kind only when its manifest entry says
`"battle": true` (otherwise a warning, and the page does not run). `RPGCommandRegistry.merged_custom_fields`
feeds the Database screen. Two more `custom_fields` targets: `maps` adds "Plugin fields" to
Map properties (`RPGMapPropertiesDialog.custom_fields`, saved as the map's `custom`, read with
`RPG.data.map_props(id).custom`), and `event_pages` adds them to every event page
(`RPGEventEditor.page_fields`, saved as the page's `custom`, read at run time from
`RPGEvent.page.custom`, so a page change switches them). The validator walks extension custom
fields of records, so their `ref` fields are checked and follow renames.

**Record types** (`database_types`). `RPGCommandRegistry.database_types()` lists them
(`[{type, label, ref, fields, extension}]`; `ref` defaults to the type without its last "s");
a type must be a new valid ID, not a built-in one. Every `load_all` refreshes the static
`RPGCommandRegistry.declared_database_types` (ref -> declaration) for the validator and the ref
picker. `RPGProjectData.add_db_types(types)` loads `database/<type>.json` (empty when missing)
into `db` like the built-in types and keeps them across `reload()`; the extension host calls it
at start, the Database screen after loading its registry (its tab goes before Common events,
with the declared fields, notes and custom fields; New, Delete, Rename ID and the problem list
work as for built-in tabs). `RPGValidator.db_kinds()` = `DB_KIND` plus the declared kinds:
references of kind `ref` (e.g. `{"kind": "ref", "ref": "quest"}`) are checked once the type's
records are loaded, and `rename_id(data, registry, "quest", old, new)` renames the record and
every reference, as for items.

**Layers and attachments** (made by `RPGGame`, not by the map):

| Space | Node | Notes |
| --- | --- | --- |
| `map` | `Node2D` "MapOverlay" in `RPGGame.world` | map coordinates, `z_index` 100, above characters, moves with the camera |
| `screen` | `CanvasLayer` "ScreenOverlay", layer 10 | screen space, under the UI (layer 20) |
| `hud` | `Control` "Root" (320×240) in `CanvasLayer` "HudOverlay", layer 21 | above menus, messages and battle scenes; copies the UI's scale-to-fit transform each frame |

Layers are made on first use and kept across transfers. `attach_to_character(id, node)` reparents
`node` under the player, `follower:N` or a map event; attachments to events go away with their
map.

**Autosave.** `RPGGame.request_autosave(reason)` marks one for the next safe point;
`RPGSaveService.autosave(reason)` writes `autosave_slot()` (= `slot_count()`, `max_slots`,
default 16). `autosave_allowed` (a Callable) can veto it, `header_providers` add fields to the
save's `"header"` (shown by `describe()`), and `autosave_labelled` names the slot "Auto" without
System Auto-save.

**Show Choices** (core): a choice may carry `show_switch` / `enable_switch` (form fields) or
`show_if` / `enable_if` (conditions, JSON). Hidden choices are left out. Disabled ones are drawn
grey and buzz (`open_choices(labels, {disabled: [...]})`). The branch taken is still the
choice's own index.

**Battle hooks.** `RPG.battle_hook(hook, args, mode) -> {args, cancel}` calls each entry
script's `on_<hook>(...args)` in load order (`RPGExtensionHost.run_hook`), then emits the `RPG`
signal `hook` with the final arguments. `mode` `""` only notifies; `"value"`: a non-null return
replaces the last argument for the next script; `"action"`: a return `{action?, targets?,
cancel?}` replaces the action and targets, and `cancel: true` stops there. Signal listeners see
the final values (and may still change Dictionaries in place).

| Hook (signal / `on_` method) | Mode | Called by |
| --- | --- | --- |
| `battle_scene_ready(scene)` | | `battle_scene.gd` `start()`, once the stage is built |
| `turn_started(battler)` | | `RPGBattleCore`, when a battler's action comes up (each extra action too; a battler that cannot act is skipped as before) |
| `action_chosen(user, action, targets)` | action | `RPGBattleCore._execute*`: after the targets are resolved, before the cost is paid. Guard, escape and wait get `[user]` / `[]`. A cancelled action does nothing and shows nothing (`result.cancelled`); a consumed item is given back (`core.item_refund`). A new action is checked and paid like the old one; without new targets they are resolved for it |
| `damage_calculated(user, target, action, value)` | value | the rule system's `damage()` through `RPGRuleSystem.damage_filter`, which the core sets only while it applies an action: every damage roll (not recovery), after variance, critical and guard. The new value is applied, logged and popped up |
| `state_changed(battler, state_id, added)` | | `RPGBattleCore.report_changes()`: after each action, state tick and battle-event page (diffs of every battler's states, so Change State in a troop page counts) |
| `battler_defeated(battler)` | | the same, when a battler becomes dead (after its death-state `state_changed`); again after a revival |
| `victory(rewards)` | value | `battle_scene.gd` `_victory()`, before EXP, gold and items are given; `RPGBattleCore.award_exp(amount)` takes the changed EXP |

Entry-script queries of the default battle scene (not signals; `run_hook(method, args, "value")`
or the first non-null answer):

- `battle_members(members: Array) -> Array`: who fights, from the party's battlers (filters chain; an empty answer is ignored; at most 4 are used).
- `victory_scene(info) -> Node`: the first node returned replaces the reward messages. `info` = the rewards `{exp, gold, items}` plus `actors: [{actor, id, name, old_level, new_level, old_exp, new_exp, level_ups, old_stats, new_stats, gains, learned}]` (living battle members; the stats only when some script offers `victory_scene`, as a stat formula may draw from the RNG), `battle` and `auto`. A node without a parent is added over the battle; the battle waits for its `finished`, `closed` or `cancelled` signal, then frees it (or closes it, when it was opened with `rpg.ui.open_scene`).
- `battle_popup(battler, text, style, node) -> Control`: replaces a damage popup; `style` is `damage`, `critical`, `miss`, `heal`, `resource_up`, `resource_down` or `slip`, `node` what an earlier script returned. The scene sets the node's position to the battler's popup point before adding it to `scene.popups`; the node animates and frees itself.

`scene.battler_node(battler) -> Node2D` makes (once) a node that follows the battler every frame
in both views: its origin is the bottom centre of `scene.battler_rect(battler)`, which is an
enemy's image, a side-view actor's figure (stepping included) or a front-view actor's status row.
It is hidden with the battler (not yet appeared, collapsed, escaped) and, for front-view actors,
fades with the status window. The nodes live in `scene.battler_layer`, above the windows and under
the target arrow, the popups and the message box. Battle Processing still calls
`RPG.check_levels()` after the battle.

None of the hooks draws from the RNG, so a seeded battle plays exactly as before when no
extension is on, or when handlers return what they got (`tests/suites/test_plugins_battle.gd`).

**Shared enemy records.** `enemy_gauges` and `bestiary` both declare the save section
`enemy_records` = `{seen: {enemy_id: battles}, defeated: {enemy_id: count}}`, so the host keeps
one Dictionary that both read (`RPG.extensions.section("enemy_records")`). Only one writes: the
bestiary when it is on, else the gauges plugin. Either plugin works alone, and a game saved with
one keeps its records when the other is turned on.

## Rule system contract (runtime/rules)

`RPGRuleSystem` (RefCounted) is loaded from `rpg/rules/<name>/rules.json` (+ optional `rules.gd`).
Methods: `setup(definition, db)`, `stats()`, `resources()`, `capabilities()`,
`new_actor_battler(actor_id, level)`, `new_enemy_battler(enemy_id)`, `effective_stat(b, stat)`,
`max_resource(b, res)`, `hit_check(user, target, action)`, `damage(user, target, action)`,
`apply_action(user, target, action) -> Dictionary`, `exp_for_level(class_id, level)`,
`gain_exp(b, amount) -> Array (level ups)`, `escape_chance(party, enemies)`,
`roll_check(b, check) -> {success, roll, target}`, `evaluate_formula(text, user, target)`.
