# Lesson 9: Image-backed maps

Some makers draw a whole room or town in a paint program instead of building it from tiles. An **image-backed map** uses one such picture as the map's ground. You then paint where characters can walk, and add doors, people and cutscenes with the same Event mode as in the earlier lessons. An optional **foreground** picture lets the player walk behind wall tops, tree crowns and arches.

In this lesson you build a small room from a picture, mark its floor, add a door out and someone to talk to, and play it. You never need Godot's 2D editor.

## 1. Pictures, tiles, passability and parallax

An image-backed map can mix five kinds of content. Each does a different job:

| What | Where it comes from | What it does |
| --- | --- | --- |
| **Base image** | One PNG you draw | The ground and everything fixed under the characters. It sits under every tile, lines up with the map grid, and moves exactly with the map. |
| **Foreground image** (optional) | A second PNG, the same size, mostly transparent | Drawn **above** the characters: wall tops, tree crowns, door frames. Transparent pixels show what is under them. |
| **Tiles** | The tileset, as in Lesson 1 | Still available on top of the image: animated water, effects, corrections, or a map built from both. |
| **Passability** | Painted in **Passability** mode | Where characters can walk. It is stored with the map, not in the pictures, and is never drawn in the game. |
| **Parallax background** | Map Properties, as before | A backdrop that scrolls at its own speed **behind** the map and can loop. It only shows through transparent pixels of the base image. |

The base and foreground images never scroll on their own and never loop.

## 2. Prepare the pictures

Every map cell is one tile of the **map tile size**: the tile size of the map's tileset (16 px for 2000/2003 tilesets, 32 for XP and VX/Ace, 48 for MV), or the project's tile size when the map has no tileset. The picture must be a whole number of those tiles on each side.

- A room 20 × 15 cells with 16 px tiles is a 320 × 240 picture. With 48 px tiles it is 960 × 720.
- RPG Kit never stretches, crops or pads the picture. If the size is wrong it tells you the nearest sizes that work, above and below, and you fix the canvas in your paint program.
- The largest picture accepted is **8192 pixels** on a side, and a map can have at most 500 cells per side. Above **4096 pixels** the editor warns you: some web and mobile devices cannot show pictures that big. (These limits are still being confirmed on each kind of export.)
- Memory depends on the picture's pixel size, not on how small the PNG file is: a 4096 × 4096 picture takes 64 MiB on the graphics card whatever its file size.
- Draw the foreground on a transparent canvas of exactly the same size as the base.

Save both as PNG files inside the project, for example `assets/maps/cellar.png` and `assets/maps/cellar_fg.png`. Godot imports them when you switch back to it.

To follow along without drawing, make any 320 × 240 PNG (16 px tiles) with a floor and some walls, and a transparent 320 × 240 PNG with an arch painted across the top of a doorway.

## 3. Create the map

1. Right-click a map in the map tree (or the empty space below it) and choose **New image-backed map…**. (**New map…** still makes an ordinary tile map.)
2. Type a **Map ID**, for example `cellar`, and a **Name**.
3. **Tileset**: keep the project's tileset if you want to add tiles later, or pick *(none)*. The dialog shows the **map tile size** and where it comes from.
4. **Base image**: press **Browse…** and pick `cellar.png`. The dialog shows the picture's size and the map size in cells, or what is wrong with it. **Create** stays off until the picture fits.
5. **Foreground image (optional)**: pick `cellar_fg.png`, or leave it empty.
6. **Start with**: *All blocked (paint the floor)* suits a room with lots of wall; *All walkable (paint the walls)* suits an open field.
7. Press **Create**. Nothing is written before this; **Cancel** leaves the project as it was.

The new map opens in **Passability** mode, with the picture under a grid of marks.

## 4. Paint where characters can walk

Passability mode (F4, or the **Passability** button; only offered on image-backed maps) shows every cell's passability over the picture:

- a **dot**: walkable;
- an **X** on a shaded cell: blocked;
- **arrows**: walkable only across the edges the arrows point to.

The marks have a dark outline so they show on bright and dark art alike.

The palette's **P** tab is the brush: **Walkable**, **Blocked**, or tick only some of the **Up**, **Down**, **Left** and **Right** boxes to close a cell's other edges (a railing along one side, a bridge you can't step off sideways). Then use the usual tools:

- **Pencil** for single cells, **Rect** and **Ellipse** for areas, **Fill** for a connected area with the same passability.
- Right-click a cell to pick up its passability as the brush.
- Ctrl+Z and Ctrl+Y undo and redo each stroke.

Trace the floor of the room. Leave the walls, furniture and the space under the arch's pillars blocked.

Passability is saved with the map (Ctrl+S), separately from the pictures. In the game, a cell you left blocked stays blocked even if no tile is drawn there; tiles you paint on top still give their bush, counter, ladder and damage-floor effects and terrain tags, but no longer decide passability. Events with *Same as characters* priority still block the way.

You can hide the passability marks in the other modes with **Overlays > Passability**; that only hides the marks, it does not switch passability off.

## 5. Add a door out

1. Switch to **Event** mode (F6). The grid lines up with the picture from the first cell to the last.
2. Right-click the cell in the doorway and choose **Quick events > Transfer** (or **Door**, as in Lesson 3).
3. For **Where to?**, press **Pick on map…** and click a cell on another map. Pickers show the base image too, so you can see where you click.
4. Make the way back on the other map the same way, pointing at a walkable cell of the cellar.

## 6. Add someone to talk to

1. Double-click a walkable cell in the room to make a new event.
2. Give it a character graphic, keep the priority *Same as characters* and the trigger *Action button*.
3. Add **Show Text**: "Mind the arch, it's lower than it looks."

Everything from Lessons 2 to 5 works the same: pages, conditions, move routes and their **Preview**, autorun cutscenes, Event search and jump-to-event.

## 7. Walk behind the arch

With a foreground image, characters walk *under* its painted pixels. In the editor you sometimes need to see what is under it: the toolbar's **Foreground** list (it appears on maps that have one) can **show**, **dim** or **hide** it while you edit. It is a normal list: Tab to it, press Enter or Space, and pick with the arrow keys. The game always draws the foreground fully. Event markers and the selected event are always drawn on top, so you can click them through the foreground.

## 8. Playtest

Press **Playtest** (F9), or in Event mode right-click a cell > **▶ Playtest from here**. The game draws the same picture at the same place and scale as the editor, uses the passability you painted, and draws the foreground above the hero. Walk under the arch: the hero disappears only behind the painted parts. The airship always flies above the foreground.

Saved games store only which map you are on and the usual game state; the pictures are never copied into a save.

## 9. Changing the art later

Open **Map Properties** (right-click the map > **Properties…**). On an image-backed map it shows **Base image** and **Foreground image**:

- **The same size**: pick the new picture and press **Save**. The map shows it at once; passability, regions, tiles, events and start positions are untouched. If you simply save over the old PNG in your paint program, RPG Kit notices when you return to Godot and shows the new pixels.
- **Another size**: RPG Kit opens a review first. It lists what would fall outside the new size: events, tiles, regions, passability cells, and the player and vehicle start positions.
  - While a start position would fall outside, it refuses; move the start inside first.
  - Otherwise **Resize map** first copies the map's three files to `rpg/.backup/`, then resizes. Resizing cannot be undone (the backup is your way back). New cells of a larger map start blocked.
  - **Cancel** changes nothing at all.
- **Clear** next to the foreground removes it; nothing else changes and the map stays image-backed.

Width and height are set by the picture, and the loop choices of *Scroll type* are off: a picture that does not repeat would show a seam. **Shift contents** is off too, because the picture cannot move with the events and tiles.

## 10. Checks before playtest and export

The checks that run before playtest and in **Tools > Deploy** report, naming the map and the file:

- a base or foreground picture that is missing;
- a picture that is not a whole number of tiles, is over the size limit, or no longer matches the map's size;
- a foreground of a different size from the base;
- an image-backed map set to loop;
- (warnings) a picture over 4096 pixels, or imported with mipmaps or lossy compression.

Exports keep every picture an image-backed map uses, also when Deploy leaves unused assets out.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| The art looks **blurry** | RPG Kit always draws map pictures with sharp pixels. If it still looks soft, select the PNG in Godot's FileSystem dock and in the Import dock turn **Mipmaps** off and set **Compress** to *Lossless*, then Reimport. The checks warn about both. |
| "Not a whole number of map tiles" | The picture's width or height is not a multiple of the map tile size. Resize the *canvas* (not the image) in your paint program to one of the sizes the message suggests. Check which tile size applies: a 16 px tileset in a 48 px project means 16 px cells. |
| **Events look off by a cell** | The picture was probably drawn for another tile size, or has a border. Turn on **Overlays > Grid** and compare it with the art; fix the art, then replace it in Map Properties. |
| "The base image … is missing" | The PNG was moved or renamed. Pick it again in Map Properties. |
| **The hero is hidden in the wrong places** (or not hidden) | The foreground hides the hero wherever it has non-transparent pixels. Erase stray pixels to full transparency, and paint everything the hero should pass behind. |
| The hero walks through walls / can't move | Passability is what you painted, not what the picture shows. Open Passability mode (F4) and check the marks. |

## What image-backed maps don't do (yet)

- Passability is never worked out from the picture's pixels; you paint it.
- Pictures are not turned into tiles or autotiles.
- There is no in-game decorating or level editing, and no streaming of huge pictures or seamless multi-map worlds.
- The foreground is one fixed layer: objects are not split into front and back halves automatically.

## Try it yourself

- Add a lit candle with an animated tile from the **Anim** tab on top of the picture.
- Paint region 1 over a dark corner in Region mode (F7), and use it for random encounters (Lesson 7).
- Make a narrow bridge: a row of cells open only left and right, so the hero can't step off its sides.

Back to [Home](Home.md).
