# Testing the kit

The kit has headless tests for the runtime, the editor's data handling and the importers. Run them before sending a change, and after updating Godot.

## Running the tests

Set `GODOT` to your Godot 4.5 **console** executable, or put its path on one line in `tools/godot_path.local` (git-ignored). Then:

```bash
bash tools/t.sh
```

```bash
bash tools/t.sh sample_project
```

The first runs every suite; the second runs one suite. `t.sh` prints a compact report and exits non-zero when a test fails. You can also call Godot directly:

```bash
godot --headless --path . --script res://tests/run_tests.gd -- --suite=interpreter
```

How the runner treats problems:

- A test that hits a script error fails, even if it never reaches an assertion.
- A test that hangs fails after 60 seconds.
- Godot prints "resources still in use" warnings when a headless run exits. They come from engine teardown and don't affect results.

## The suites

There are 538 tests in 30 suites:

| Suite | What it covers |
| --- | --- |
| `interpreter` | Scheduling, cancellation, call depth, the door example and touch triggers |
| `save` | Save and load, migration, refusing to save during an event |
| `import` | 2000/2003 ChipSet decoding and autotile patterns against fixtures; RPG Maker folder import findings from the real RTPs (water row, palette transparency, JPG, XP/VX/MV window skins, skipped folders, game over, tileset ids) |
| `formula`, `rules` | Safe formulas and the Classic and OSR rule systems |
| `battle_core` | Turn order, AI, rewards and battle events |
| `battle_styles` | Front and side view, turn / ATB / CTB: defaults, side-view placement, the battler graphic chain (MV sheet, 2003 BattleCharSet, walk sprite), motions, ATB fill order, wait and active time, the turn counter for troop pages, preemptive and surprise (encounter rolls, Battle Processing), escape, passing the turn, spacing and mixed-source heights, auto battles in every combination |
| `extension_hooks` | Extension hooks: entry scripts and game signals, settings, save sections, menu and options entries, text codes, condition kinds, custom fields, map overlay layers and character attachments |
| `plugins_wave1` | Kit plugins: menu & options plus, message codes plus, letter sounds, gab window, save & autosave plus (off by default, saves) |
| `plugins_wave2` | Kit plugins: quest journal and tracker, lighting and time of day, item crafting; plugin Database record types and map/event-page plugin fields |
| `plugins_battle` | Battle hooks (determinism, action/damage/victory hooks, battler nodes, member filter) and the enemy gauges, victory aftermath, party formation and bestiary plugins in every battle view and system |
| `map_editor` | Painting, undo (also across map switches), Fill with the eraser, hand-drawn shadows kept, growing a map, events with stable IDs, map files without embedded TileSets |
| `editor_data` | Quick events, validator, forms, command list, database and JSON round trips; RPG and Database tabs not overwriting each other; deleted events not coming back |
| `ui_screens` | Every default screen, plus auto battles |
| `tools` | Event search, resources, extensions, new command, capability checks, rule-system switching, export blocking, new project, write recovery |
| `profiles` | XP, VX/Ace and MV/MZ tile sheets, autotile layouts, character and face sheets, against golden fixtures |
| `tile_settings` | Tileset passability and flag overrides: round trip, rebuild, reset, copy, the dialog |
| `runtime_regressions` | Edge cases from a runtime review: a parallel event that transfers the player, failed transfers and loads, fades after a reset, self switches after a fading transfer, Erase Event across saves, pictures and BGS after a load |
| `commands_maker` | The RPG Maker commands added for the tutorials: Show Animation, Change Actor Graphic / Name / Level / EXP / Skills / Equipment / Class, transparency, battle music, tileset, parallax, battle background, Get Location Info, Stop SE, window skin |
| `vehicles` | Boat, ship and airship: boarding, water rules, landing, riding through save and load |
| `rules_vx_ace` | The VX Ace style rules: stat curves, damage formulas, HIT/EVA/CRI, TP, Features |
| `states_walking` | States while walking: removal after N steps (not in a vehicle), slip damage and regeneration every 20 steps, 2000-style changes every N steps, the 1 HP floor and game over with Knockout by slip damage, damage floors, step counters through save and load, the Database fields and checks |
| `database_ui` | Database forms: vehicles, conditions, operand modes, tile picker, class curves, Autoname, a project with no rpg folder, maker view release; editor-QA fixes: reload after Create, Ctrl+S, per-tab problem checks, type dropdowns, rename blocking, plain starting values, currency hint, title image and start facing |
| `event_editor` | Editor-QA fixes in the event editor and quick events: starter sounds in VX/MV projects, steady form layout, uncommitted new events, 1-based JSON lines, readable event search, dialogs stepping aside for map picks, the character frame preview, new Conditional Branch kinds (with runtime support) |
| `sample_project` | Plays the sample: intro, key, door, Mira joins, a slime fight, the goblin boss, save and load |
| `export_gaps` | Findings from QA of an exported game: mouse and touch everywhere (through the real viewport and UI scaling), gamepad sticks/Start/Back, release builds ignoring playtest hooks, music resuming after battles and loads, OGG loop tags, number input, message skip, window scaling and full screen, local save times, the limiter, clean exits (routes cancelled on unload), compressed tileset caches, Common Event effects run from the menu |
| `midi` | MIDI: the file reader (formats 0/1, tempo maps, running status, SMPTE, CC#111 loop, RMID), the renderer (timing, pitch, envelopes, sustain pedal, pitch bend, exclusive classes, voice limit, no clipping, loop points), the import plugin, sound bank paths and fallback, MIDI in asset lookups and the reverb bus |
| `qa_playthrough` | Engine bugs found by a keys-only QA playthrough of an MV RTP game: MV wall tops, big faces, jingles, shop comparison, knockout HP, save slot names, choice codes, one currency, letterbox, event-opened Save, empty names, label fitting, battle cursor |

## Other checks

```bash
godot --headless --path . --script res://tools/check_scripts.gd
```

compiles every script, including editor scripts the tests never open.

```bash
godot --headless --path . --export-debug "Windows Desktop" build/windows/SampleQuest.exe
```

```bash
build/windows/SampleQuest.console.exe --headless -- --rpg-smoke
```

The export preset leaves out the editor plugins, tests, tools and docs, so the exported sample proves the runtime works without the editor. `--rpg-smoke` starts a new game, runs the start map's events, prints `RPG_SMOKE OK ...` and exits 0 (1 on failure).

## Helper scripts

| Script | What it does |
| --- | --- |
| `tools/build_sample.gd` | Rebuilds the sample's maps and events |
| `tools/generate_starter_assets.gd` | Regenerates the starter art and sounds |
| `tools/generate_icons.gd` | Regenerates the icon sheets and `icons.json`; `-- --preview` writes a preview image |
| `tools/screenshot.gd` | Runs the game and saves screenshots (`--map`, `--battle`, `--script=wait:1,press:rpg_ok,shot:name`) |
| `tools/editor_preview.gd` | Renders the map editor and Tools window to PNG files |
| `tools/plugin_shots.gd` | Turns the kit plugins on for one run and screenshots them |
| `tools/rm_real_import_check.gd` | Imports an RPG Maker folder you own into `user://` and renders a contact sheet |

With the environment variable `RPG_EDITOR_SHOT=<folder>`, the real editor walks through its main screens on start and saves screenshots there.
