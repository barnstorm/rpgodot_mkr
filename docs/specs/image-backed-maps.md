# Image-backed maps

Feature specification and user stories.

| | |
| --- | --- |
| Status | Proposed |
| Target | RPG Kit for Godot 4.5 |
| Scope | Game-agnostic map-authoring workflow |

## Summary

Image-backed maps let a maker use one pixel-aligned image as the visual foundation of a map. The maker paints navigation separately from that image. The maker then uses RPG Kit's existing Event mode to add doors, characters, interactions, transfers and cutscenes.

An image-backed map may also have an optional transparent foreground image. It holds wall tops, tree canopies, door frames and other pixels that must render above characters. Ordinary tile layers stay available for animation, effects, corrections, or maps built from both images and tiles.

The feature is for makers who draw environments in an illustration or pixel-art tool and do not want to rebuild them from autotiles.

## Goals

- Let a maker create a playable map from a prepared image without editing a Godot scene by hand.
- Keep the existing RPG Kit event-authoring workflow.
- Keep event cells, navigation cells and image pixels aligned to the map's tile grid.
- Keep visual artwork separate from navigation and interaction data.
- Support an optional foreground layer for basic character occlusion.
- Keep tile layers usable on image-backed maps.
- Validate image alignment before a map becomes hard to repair.
- Keep authored collision, regions and events when artwork is replaced.

## Non-goals for the first release

- Deriving collision from image pixels.
- Converting an image into an autotile set.
- A runtime furniture or level editor.
- Polygon or physics-body navigation.
- Splitting tall objects into background and foreground pixels automatically.
- Streaming very large images, or a seamless multi-map world.
- Runtime background variants, seasons or restoration states.
- Replacing RPG Kit's existing parallax-background feature.

## Terminology

| Term | Meaning |
| --- | --- |
| Image-backed map | A normal RPG Kit map with a world-aligned base image. |
| Base image | The opaque or transparent image drawn beneath map tiles, characters and events. |
| Foreground image | An optional transparent image, the same pixel size as the base image, drawn above map characters during play. |
| Navigation mask | Grid-aligned passability data, authored separately from visible tiles. |
| Map tile size | The size in pixels of one map cell. It is the tile size of the map's tileset, or the project tile size when the map has no tileset. See [Map tile size](#map-tile-size). |
| Project tile size | The logical grid size of the active RPG Kit profile (`rpg/profile.json` `tile_size`): 16, 32 or 48 pixels. |

## Intended user flow

1. The maker chooses **New map** and selects **Image-backed map**.
2. The maker selects a base image.
3. RPG Kit reads the image size and compares it with the map tile size.
4. If the image is aligned, RPG Kit derives the map's width and height in cells.
5. The maker may select a transparent foreground image of the same size.
6. The maker chooses the initial navigation state: all blocked or all walkable.
7. RPG Kit creates the map and opens it in Navigation mode with the mask visible.
8. The maker uses the familiar pencil, rectangle and fill tools to author passability.
9. The maker switches to Region mode when semantic areas are needed.
10. The maker switches to Event mode and places events against the rendered artwork.
11. Playtest draws the same aligned base and foreground images and uses the authored navigation mask.
12. The maker may replace either image later without losing navigation, regions or events.

## Rendering model

The default draw order, from bottom to top:

1. Base image.
2. Ordinary lower tile layers.
3. Characters, events and Y-sorted map objects.
4. Ordinary upper tile content, following existing RPG Kit behaviour.
5. Foreground image.
6. Existing map, screen, lighting, weather, picture and UI overlays, following their current contracts.

Event markers must stay legible in the editor when a foreground image exists. The foreground image therefore needs editor-only visibility and opacity controls.

The base and foreground images are world-aligned. They are not camera-relative parallax images, and they do not loop.

## User stories

### IM-01: Create an image-backed map

As a maker, I want to create a map from an environment image so that I can begin adding gameplay without rebuilding the artwork from tiles.

Acceptance criteria:

- **New map** offers **Tile map** and **Image-backed map** as distinct choices.
- Selecting **Image-backed map** opens a resource picker for the base image.
- RPG Kit reads the image's width and height in pixels.
- RPG Kit shows the map tile size before creation.
- When both image dimensions are exact multiples of the map tile size, RPG Kit calculates and shows the resulting map size in cells.
- The maker can confirm or cancel before any file is written.
- On confirmation, RPG Kit creates the same standard map files as for other maps.
- The new map appears in the map tree and opens in the RPG editor.
- Creation does not require Godot's 2D editor or manual `.tscn` editing.

Exit criteria:

- A maker can select a valid image and reach an editable, correctly sized map in one uninterrupted flow.
- Closing and reopening the project keeps the base-image assignment and the calculated map size.

### IM-02: Validate pixel and grid alignment

As a maker, I want RPG Kit to detect incompatible artwork before map creation so that events and collision do not become subtly misaligned.

Acceptance criteria:

- RPG Kit rejects a zero-sized or unreadable image with a specific error.
- RPG Kit detects when either image dimension is not divisible by the map tile size.
- The message reports the image size, the map tile size, and the nearest valid dimensions above and below in each direction.
- RPG Kit never rescales, crops, pads or resamples the source image.
- The maker may cancel and fix the artwork; no partial map is created.
- An image larger than the engine or RPG Kit limit is rejected before creation, and the message shows the limit.
- The feature applies the required image filtering itself; makers do not configure it per map.

Exit criteria:

- Every image the creation flow accepts maps one-to-one from image pixels to map cells.
- Automated tests cover valid, indivisible, unreadable, zero-sized and over-limit inputs.

### IM-03: Render the base image consistently

As a maker, I want the map artwork to look the same in the editor and during play so that I can trust event placement.

Acceptance criteria:

- The base image's top-left corner is at map pixel (0, 0), which is the top-left corner of cell (0, 0).
- The image is drawn at scale 1.0 in map pixels, before the project's normal display scaling.
- Nearest-neighbour filtering is used.
- The image does not loop, drift or move at a different rate from the map.
- The image is visible in Map, Region, Navigation and Event modes.
- The runtime uses the same origin and scale.
- Camera movement causes no subpixel shimmer that comes from this feature.
- Lighting and screen effects affect the image in the same way as ordinary map content.

Exit criteria:

- A reference marker painted at several known grid intersections lines up with the same cells in the editor and in a playtest screenshot.
- Alignment holds at every supported profile and display scale in the test suite.

### IM-04: Add an optional foreground image

As a maker, I want to supply transparent foreground artwork so that characters can walk behind wall tops and other fixed features.

Acceptance criteria:

- Map Properties has an optional foreground-image field.
- The foreground image must be the same pixel size as the base image.
- A foreground image of a different size is rejected, and the message shows both sizes.
- Transparent areas reveal the map and characters beneath them.
- During play, the foreground image is drawn above map characters and events.
- In the editor, the maker can show, hide or dim the foreground. This does not change runtime behaviour.
- Event markers and the selected event stay visible and selectable while the foreground is shown.
- Removing the foreground assignment does not change the base image, navigation, regions, tile layers or events.

Exit criteria:

- A character can walk beneath a transparent foreground test arch and is hidden only by the painted foreground pixels.
- The maker can place and edit an event under foreground artwork without editing the image file.

### IM-05: Author navigation separately from artwork

As a maker, I want to paint where characters may move without painting visible tiles so that finished artwork stays unchanged.

Acceptance criteria:

- Image-backed maps have a clearly named Navigation or Passability mode.
- The maker chooses an initial state, all blocked or all walkable, during map creation.
- The navigation overlay is drawn over the base image and does not change it.
- At minimum, a cell can be fully walkable or fully blocked.
- RPG Kit's existing four-direction passage behaviour stays available where it is supported.
- The existing pencil, rectangle, fill, undo and redo behaviour is reused where practical.
- The overlay distinguishes walkable, blocked and direction-restricted cells.
- The overlay can be hidden without turning navigation off.
- Navigation data is saved separately from the base and foreground image files.
- At runtime, movement uses the navigation data even where no visible tile occupies a cell.
- Event occupancy and event priority still affect movement.

Exit criteria:

- A maker can trace a room's walkable floor and playtest it without placing any visible tile.
- Undo and redo restore both the navigation data and its overlay.
- Saving and reloading gives identical runtime passability.

### IM-06: Keep the normal tile and region workflows

As a maker, I want to mix image artwork with normal RPG Kit tiles and regions so that I can add animated or system-driven map elements.

Acceptance criteria:

- All existing visible tile layers are available on an image-backed map.
- Painting tiles does not change the source base image.
- Animated tiles still animate during play.
- Existing tile flags keep their current behaviour.
- Region mode works across the whole image-backed map.
- Region IDs stay available to events and extension hooks.
- The base image stays visible while painting tiles or regions.
- Layer visibility and layer dimming still work.

Exit criteria:

- A test map combines a base image, at least one visible tile, at least one animated tile, a region and navigation data, with no rendering or saving conflict.

### IM-07: Place and edit events against the image

As a maker, I want Event mode to work unchanged on an image-backed map so that I can keep the familiar RPG Maker-style workflow.

Acceptance criteria:

- The event grid lines up with the base image from the first cell to the last.
- Double-clicking an empty cell creates an event at that cell.
- The existing quick-event templates are available.
- Event graphics, pages, triggers, movement routes and conditions behave normally.
- Transfer and location pickers show the base image when the maker picks a destination cell.
- Move-route previews are drawn above the base image and stay legible.
- Event search and jump-to-event open the correct image-backed map and cell.
- **Playtest from here** starts at the selected image-aligned cell.

Exit criteria:

- A maker can create a door, a transfer, a talking character and an autorun scene without leaving the RPG editor.
- Every event is on the same cell in the editor and at runtime.

### IM-08: Replace artwork without losing authored gameplay

As a maker, I want to revise a map image while keeping events and navigation so that visual iteration does not destroy gameplay work.

Acceptance criteria:

- Map Properties lets the maker replace the base or foreground image.
- A replacement of the same size keeps the map size, navigation, regions, tile layers, events and start positions.
- The editor shows the new image without a restart.
- If the replacement has a different size, RPG Kit shows a blocking review dialog before applying the change.
- The review dialog reports which data may fall outside the new bounds.
- A smaller replacement cannot silently delete out-of-bounds events, regions, tiles, navigation cells or the player start position.
- A larger replacement offers an explicit map-resize operation that uses the existing map-growth behaviour.
- Cancelling the review leaves the map and its assignments unchanged.

Exit criteria:

- Reimporting an edited PNG of the same size updates the artwork, and a checksum or fixture confirms that the event and navigation files are unchanged.
- Replacements that change the size have deterministic, tested resize and cancel behaviour.

### IM-09: Save, recover and export image-backed maps

As a maker, I want image-backed maps to take part in RPG Kit's normal safety and deployment checks so that they are as reliable as tile-built maps.

Acceptance criteria:

- Base and foreground assignments are stored in normal project data as project-relative resource paths.
- Image-backed map metadata takes part in atomic writes and interrupted-write recovery.
- Validation reports missing base or foreground images.
- Invalid sizes are reported before playtest and export.
- Export includes every referenced base and foreground image.
- Export with unused-asset removal keeps images that only image-backed maps reference.
- A release build draws and navigates an image-backed map without editor-only code.
- External file changes trigger the same reload or conflict handling as other map data, where that applies.

Exit criteria:

- A clean exported build can start on, transfer into, save on, load on and leave an image-backed map.
- Deleting a referenced image causes a clear deploy error that names the map and the missing path.

### IM-10: Stay compatible with existing projects

As an existing RPG Kit maker, I want the feature to leave my current maps unchanged so that upgrading the addon is safe.

Acceptance criteria:

- Maps without image-backed-map metadata render and edit exactly as before.
- Existing map files need no migration.
- Parallax-background behaviour is unchanged.
- Passability on tile-built maps is unchanged.
- Image-backed maps and tile-built maps can coexist in one project.
- Turning off or removing the foreground assignment does not change the map type or rewrite unrelated map data.

Exit criteria:

- The existing automated test suite passes with no fixture rewrites caused only by this feature.
- Regression tests compare representative legacy maps before and after the feature is enabled.

### IM-11: Document the workflow

As a new maker, I want a short guided lesson so that I can create an interactive image-backed room without understanding Godot scene internals.

Acceptance criteria:

- The documentation explains how base images, foreground images, tiles, navigation and parallax backgrounds differ.
- It states the image sizing and tile-grid requirements.
- A walkthrough creates a map, paints navigation, places a transfer, adds a talking event and playtests.
- A sample foreground shows walking behind a fixed object.
- Troubleshooting covers blurred artwork, wrong dimensions, misaligned events, missing assets and foreground occlusion.
- The documentation states that runtime decoration and automatic collision extraction are out of scope.

Exit criteria:

- A tester who does not know the implementation can complete the documented flow without opening Godot's 2D editor.
- Every screenshot and menu label in the guide matches the released interface.

## Cross-story product requirements

### Data integrity

- Replacing artwork never silently discards gameplay data.
- Base and foreground image files stay external assets. RPG Kit never rewrites them.
- Map resize operations have the same undo, validation and recovery behaviour as existing map resize operations.

### Editor usability

- Image-backed-map controls use maker-facing language and do not expose scene-node details.
- The main workflow is available from the RPG tab.
- Common tasks do not need the Inspector, the FileSystem dock or the 2D scene editor.
- Navigation and event overlays stay readable over both bright and dark artwork.

### Runtime behaviour

- The feature uses the existing grid movement and event-trigger model.
- Base and foreground images follow the map camera exactly.
- Saves store only image assignments and normal map state, never image pixels.

### Performance

- The editor warns when an image approaches the configured or engine texture-size limit.
- The documentation explains that texture memory depends on the decoded image size, not the PNG file size.
- A representative map at each supported profile opens, pans, edits and playtests without materially degrading the map editor's current responsiveness.
- Performance limits and representative test sizes are written down, not left implicit.

### Accessibility

- Navigation overlays do not rely on colour alone. They also use patterns, icons or cell markings.
- Foreground visibility and opacity controls work from the keyboard.
- Every new control has a tooltip and takes part in normal keyboard focus order.

## Feature-level exit criteria

The feature is ready for release when all of these are true:

1. A maker can create a valid image-backed map, paint navigation, place events and playtest it without opening Godot's general-purpose scene editor.
2. Base-image alignment is identical in the RPG editor and at runtime across supported profiles.
3. Foreground artwork produces correct fixed occlusion and can be hidden or dimmed while editing.
4. Navigation works without visible tiles and survives save, reload, transfer and exported-game load.
5. Visible tiles, regions, event pages, quick events, location picking, move-route previews and playtest-from-here work on image-backed maps.
6. Art revisions of the same size keep all gameplay data.
7. Art revisions that change the size cannot silently discard gameplay data.
8. Missing, invalid, oversized and misaligned assets produce actionable validation errors.
9. Debug and release exports include the image assets, also when unused assets are left out.
10. Existing tile-built maps and parallax backgrounds behave exactly as before.
11. Automated tests cover creation, validation, rendering alignment, foreground behaviour, navigation, event alignment, replacement, save and load, export validation and legacy compatibility.
12. A first-time tester can complete the documented tutorial without help.

## Suggested implementation slices

**Slice A: base image and creation flow**

- Map metadata and resource loading.
- Image-backed-map option in New Map.
- Size validation and automatic map sizing.
- Editor and runtime base-image rendering.

**Slice B: navigation authoring**

- Navigation data representation.
- Navigation overlay and editing mode.
- Runtime integration with existing grid movement.
- Undo, redo, save and reload.

**Slice C: events and foreground**

- Event-mode alignment checks.
- Foreground image rendering.
- Editor foreground visibility and opacity controls.
- Location picker and route-preview compatibility.

**Slice D: iteration and production readiness**

- Safe image replacement and resize review.
- Validation and export integration.
- Performance limits and warnings.
- Documentation, sample project and regression coverage.

## Fit with the current codebase

This section records how the feature meets the code as it stands, so that the open decisions below rest on facts. Paths are relative to the repository root.

### Map files and loading

- A map is three files plus an entry in `rpg/map_index.json`: `<id>.tscn` (painted cells), `<id>.map.json` (properties) and `<id>.events.json` (events). `RPGMapFiles.create_map` (`addons/rpg/editor/map/rpg_map_files.gd`) writes them.
- `RPGMapFiles.save_scene` packs the map node. Child nodes without an `owner` are not packed. Image nodes built at load time are therefore never written into the `.tscn`.
- The editor loads a map with `RPGMapFiles.load_map`. The runtime starts it with `RPGMap.start` (`addons/rpg/runtime/rpg_map.gd`). The parallax background is built from properties in `_setup_parallax` in the same way, on a `ParallaxBackground` at canvas layer -10.

### Map tile size

- `RPGMap.start` takes `tile_size` from the map's TileSet when it has one, else from the project. `RPGMap.display_scale()` is the project tile size divided by the TileSet's. For example, 16 px tiles in a 48 px MV-style project are drawn at 3×.
- The editor does the same in `RPGMapView.open_map`.
- One map cell is therefore not always the project tile size. The image must be checked against the map tile size, so this spec uses that term.

### Draw order today

| Content | `z_index` |
| --- | --- |
| Tile layers `Layer1` to `Layer4`, `Layer1Base`, `Shadows` | 0 |
| Events with priority *below* | 1 |
| Player, followers, boats, events with priority *same* | 2 |
| Star-flag tiles (`RPGTilesetBuilder.STAR_Z_INDEX`) | 3 |
| Events with priority *above* | 4 |
| Airship | 5 |
| `Regions` (editor only; hidden at runtime) | 80 |
| Debug overlay | 90 |
| `MapOverlay` attachment space | 100 |
| Editor overlay (grid, passability, event markers) | 200 |

RPG Kit has no separate upper tile layer. "Upper" content is any tile with the star flag, at z 3.

### Passability today

`RPGMovement.passage` (`addons/rpg/runtime/rpg_movement.gd`) walks the tile layers from top to bottom. It skips empty cells and star tiles, and the first remaining cell's `passage` bitmask decides (1 down, 2 left, 4 right, 8 up). If every layer is empty at a cell, the cell is blocked. If the map has no tiles at all, every cell is open. An image-backed map with no tiles would therefore be fully walkable today.

The editor's passability overlay (`RPGMapView._draw_passability`) already marks blocked cells with an X, open cells with a dot and partial cells with arrows. It does not rely on colour alone.

### Resize, external changes and export

- Map Properties allows 1 to 500 cells per side. Shrinking a map (`RPGMainScreen._apply_props`) lists the events it will delete and asks first. It is not undoable. Growing calls `rejoin_edges` so autotiles on the old edge join the new space.
- External edits are detected by content hash of watched files, when Godot regains focus or rescans (`remember_disk`, `check_disk_changes`).
- `RPGDeploy.unused_asset_excludes` leaves out files under `res://assets` that no project string mentions. `RPGProjectSearch.asset_usage` matches the full `res://` path. A path stored in `<id>.map.json` therefore keeps its image in the build with no change to the deploy code. Files outside `res://assets` are never excluded.
- Mode shortcuts F5, F6 and F7 are Map, Event and Region. F8 opens the Database and F9 playtests.

## Recommended resolutions of the open decisions

The original spec lists six decisions to settle before coding. Each recommendation below keeps the user-facing behaviour in the stories unchanged.

### 1. Navigation storage: a dedicated mask layer

Store navigation as a new `TileMapLayer` named `Navigation` in the map's `.tscn`. It uses a small generated TileSet, like `Regions` and `Shadows`. Atlas x is the passage bitmask, 0 to 15, so one tile per bitmask. It is not one of `RPGMap.tile_layers`.

Reasons:

- It is a dedicated mask, not invisible tiles mixed into the visible layers. Star flags, autotiling, the eyedropper and layer dimming never see it.
- Painting, rectangle, fill, undo snapshots, `shift_contents` and `resize` already work on every `TileMapLayer` child. They cover the mask with little or no new code.
- It saves with the scene and so is separate from the image files (IM-05).

Runtime rule: when a map has a `Navigation` layer, `RPGMovement.passage` returns the mask's bitmask for the cell, and a cell without a mask tile is blocked. Visible tiles still supply flags (bush, counter, ladder, damage floor) and terrain tags, but not passage. Makers then get exactly what they painted in Navigation mode. Maps without the layer use today's rule unchanged (IM-10).

Name the mode **Passability** in the interface. The overlay and the Tiles dialog already use that word, and "Navigation" is also the name of an unrelated Godot system. Suggested shortcut: F4, which is free.

### 2. Where the image paths live: a nested block in map properties

Add one optional key to `<id>.map.json`:

```json
"image_map": {
	"version": 1,
	"base": "res://assets/maps/harbour.png",
	"foreground": "res://assets/maps/harbour_fg.png"
}
```

- `foreground` is optional and may be `null`.
- A map is image-backed exactly when `image_map` is a Dictionary with a non-empty `base`.
- A missing key means a tile map, so existing files need no migration.
- The nested `version` lets the block change later without raising the file's `schema_version`.
- Atomic writes, recovery, external-change detection and asset-usage tracking already cover this file.

### 3. Size limits

- Maximum: 8192 pixels on each side. Almost all desktop GPUs support it. A 500-cell map at 16 px (8000 px) fits.
- Warning threshold: 4096 pixels on either side. Web and mobile GPUs may support only 4096, or as little as 2048. A 4096 × 4096 image decodes to 64 MiB of texture memory, and 8192 × 8192 to 256 MiB.
- The limits must be confirmed on each export target before release; the 8192 figure is an assumption, not a measured value.
- Keep both values as constants in one core script, with the test sizes recorded beside them, so the Performance requirement has a single source.

### 4. Foreground and upper tiles

The foreground is drawn above all tile content, star tiles included. Give the foreground node `z_index` 5 and raise the airship from 5 to 6, so that an airship in flight stays above roofs and canopies. This keeps the relative order of every existing element and changes nothing on maps without a foreground.

The base image is a `Sprite2D` at `z_index` -1 in the map node, under the tile layers and above the parallax layer. The parallax background then shows only through transparent base pixels.

### 5. Undo for a replacement that resizes the map

Follow the existing resize behaviour. Resizing is not undoable today, so a replacement that changes the size is applied as one confirmed operation outside the undo history. Before it writes anything, it saves copies of the map's three files to `rpg/.backup/`, as the rule-system switch does. The review dialog says so. A replacement of the same size changes only map properties and needs no resize.

### 6. When reimported images refresh

Refresh on the existing triggers: focus return and filesystem rescan, through `check_disk_changes`. Godot reimports the PNG at that moment, and a `Sprite2D` holding the texture resource shows the new pixels without a restart. After a reimport, RPG Kit checks the image size again. If the size changed, it opens the IM-08 review dialog instead of applying the change silently.

## Further decisions found in the code

These are not in the original list but need an answer before coding.

1. **Map tile size versus project tile size.** Check images against the map tile size (see [Map tile size](#map-tile-size)). The creation dialog shows that size and says where it comes from.
2. **Looping maps.** The `scroll` property can make a map loop. A world-aligned image that does not loop would show a seam. Recommendation: image-backed maps are created with `scroll` set to `none`, Map Properties disables the loop choices for them, and the validator reports a looping image-backed map as an error.
3. **Tileset on image-backed maps.** Tile layers need a TileSet (IM-06). Recommendation: the creation dialog preselects the project's first tileset and allows "(none)". With no tileset, tile painting is off and the map tile size is the project tile size.
4. **Shrinking with regions, tiles, navigation and start positions.** The current shrink dialog names only the events it deletes. IM-08 also requires regions, tiles, navigation cells and the player and vehicle start positions. Extend the same dialog for every resize rather than adding a second one.
5. **Texture filtering and import settings.** The editor viewport already uses nearest filtering, and the project default is nearest. Recommendation: set `texture_filter` to nearest on both image nodes, so a project that changes its default still draws pixel art sharply. The validator also warns when an image is imported with mipmaps or VRAM compression. RPG Kit does not rewrite `.import` files.
6. **One builder for editor and runtime.** Build both image nodes in one `RPGMap` method that the editor and the runtime both call. Then IM-03's "same origin and scale" holds by construction, and the release build has no editor-only code (IM-09).

## Implementation pointers

| Story | Main places to change |
| --- | --- |
| IM-01, IM-02 | New-map dialog in `rpg_main_screen.gd`; `RPGMapFiles.create_map` and `default_props`; a size check in a core script shared by the dialog, the validator and the tests. |
| IM-03, IM-04 | `RPGMap`: a method that builds the base and foreground nodes from `props.image_map`, called from `start` and from `RPGMapFiles.load_map`; airship `z_index` in `rpg_player.gd`. Editor show, hide and dim controls in `RPGMapView`. |
| IM-05 | `Navigation` layer in `RPGMapFiles.new_map_node` (image maps only); a generated TileSet beside `RPGTilesetBuilder.region_tileset()`; a new mode in `RPGMapView`; `RPGMovement.passage`. |
| IM-06, IM-07 | Mostly verification: location picker, route preview, event search and playtest-from-here already go through `RPGMapView` and `RPGMap`. |
| IM-08 | `rpg_map_properties.gd` image fields; `RPGMainScreen._apply_props` review dialog; `RPGMapFiles.resize`. |
| IM-09 | `RPGValidator` (missing, misaligned, oversized and looping image maps); export check before deploy. |
| IM-10 | Regression tests in `tests/suites/test_map_editor.gd` and `test_runtime_regressions.gd` on the sample maps. |
| IM-11 | A new wiki lesson in `docs/wiki/`, linked from `_Sidebar.md`. |
