# Project files and git

A kit game is **plain files**: JSON you can read, diff and merge, and Godot scenes for the tiles. There is no single binary database, so it works well with git and other version control.

## What is where

```
rpg/
  project.json          game settings: style, rule system, enabled extensions, scenes, menu…
  state.json            switch and variable definitions (names, labels, types, starting values)
  common_events.json    common events
  map_index.json        the map tree (order, parents, favourites)
  profile.json          the project's style (2000/2003, VX/Ace or MV)
  extensions.json       plugin and extension settings (when any are set)
  database/
    actors.json  classes.json  skills.json  items.json  weapons.json  armors.json
    enemies.json  troops.json  states.json  tilesets.json  system.json  types.json  terms.json
    (and plugin record types, such as quests.json)
  maps/
    <id>.tscn           the map's tiles (TileMapLayers only)
    <id>.map.json       the map's properties
    <id>.events.json    the map's events
  rules/<name>/         rule systems (rules.json, optional rules.gd)
  tileset_overrides/    your passability and flag changes to tilesets
  generated/            caches the kit rebuilds by itself (tileset textures)
assets/<pack>/          art and sound, one folder per pack, with a pack.json (licence)
extensions/<id>/        your own extensions (manifest.json, commands, scripts)
```

- IDs are names everywhere (`town`, `elder`, `potion`), so references read clearly and survive reordering.
- All JSON is written with **stable key order** and tabs, so a change shows up as a small, readable diff.
- Every file is written safely: to a temporary file first, then moved into place. If Godot stops halfway, the editor offers to recover on the next start.

## Working with git

- Commit `rpg/`, `assets/`, `extensions/`, `addons/` and `project.godot`.
- Ignore `.godot/` (Godot's import cache) and your build folder.
- If you import RPG Maker files, think about whether they belong in a public repository: they are under RPG Maker's licence. The kit's own `.gitignore` keeps RPG Maker data files, `gm.dls` and soundfonts out.
- When files change on disk while the editor is open (a `git pull`, a checkout), the RPG tab reloads them. If you have unsaved changes to the same map, it asks which version wins.
- Two people editing **different maps** never conflict: each map is three files of its own. Edits to the same database file merge like any JSON file.

## Players' files

The game writes to Godot's user folder (`user://`), never next to the game:

| File | What |
| --- | --- |
| `user://saves/` | Save slots. Each save carries a version number and is migrated when an older one is loaded |
| `user://rpg_options.json` | The player's options (volume, text speed, plugin rows) |

On Windows, `user://` is `%APPDATA%\Godot\app_userdata\<project name>\` unless the project sets its own folder.

## Editing JSON by hand

You can. The editor notices and reloads. **Open JSON** in the event editor shows the event's data, and the Database's **JSON Schema** button writes a schema so VS Code can complete and check event files. The command shapes are listed on the [Event command reference](Event-Command-Reference.md).
