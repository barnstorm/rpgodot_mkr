# Make your first RPG in 15 minutes

*Open this guide from the RPG tab: **Tools > Maker guide**.*

This guide is for anyone who has never made a game before. You only need the mouse and a little typing. No programming!

## 1. Open the project

Open this folder in Godot. At the top of the window, click the **RPG** tab. (In a brand-new Godot project the tab says *Start a new RPG*: type your game's name and press **Create RPG project**.) On the left you see little squares of grass, water and walls. These are your **tiles**. Below them is a list of your **maps**.

> Tip: the sample game *Sample Quest* is already here. Press **▶ Playtest** (top right) to play it first!

## 2. Make a map

1. Right-click **Sample Quest** in the map list and choose **New map...**.
2. Give it a name like `My Forest`, a size (try 20 × 15), and press OK.
3. Your new map is empty. Let's paint!

## 3. Paint

- Click a tile in the palette (tab **A**), then click or drag on the map.
- Grass and water **join up by themselves** (these are called *autotiles*).
- **Rect** draws a box, **Fill** pours paint into an area like a bucket.
- Tab **B** and **C** have trees, houses and furniture. They go *on top* of the ground automatically.
- Made a mistake? Press **Ctrl+Z**.
- Right-click a tile on the map to pick it up again.

Want to see where the player can walk? Open **Overlays > Passability**. Red means "can't walk here".

## 4. Add a character who talks

1. Click **Event** on the toolbar (or press F6).
2. Right-click a grass tile and choose **Quick event > Sign**. Type a message like `Welcome to my forest!` and press OK.
3. Now try a person: double-click an empty tile. The **event editor** opens.
   - Pick a **Graphic** (click the picture box and choose a character).
   - In the command list, double-click the **◆** line, choose **Show text**, and type what they say.
   - Press OK.

## 5. Add a treasure chest

Still in **Event** mode, right-click a tile, choose **Quick event > Treasure**, and pick what is inside (a Potion, or some gold). The chest opens only once, and remembers that it was opened even after you save the game.

## 6. Connect your map to the town

1. Open the **Town** map. Right-click a tile at the edge and choose **Quick event > Transfer**.
2. Choose **My Forest** and the tile where the player should arrive.
3. Do the same in **My Forest** to get back.

## 7. Playtest

In **Event** mode, right-click a tile and choose **▶ Playtest from here** to start right there, or press **▶ Playtest** (top right) to start from the title screen.

| Key | What it does |
| --- | --- |
| Arrow keys or WASD | Walk |
| Shift | Run |
| Z, Enter or Space | Talk, open, choose |
| X or Esc | Back, open the menu |
| F9 (playtest only) | Debug screen |

## 8. Change the game's data

Click the **Database** tab at the top. You can rename the hero, change what a Potion heals, make the Slime stronger, or add a new item to the shop. Press **Save all** when you are done.

## 9. Share your game

When you are ready, open **Tools > Deploy** and press **Run export checks**. If it says *Ready to export*, use Godot's **Project > Export** to make a game anyone can play.

## Words you will see

| Word | Meaning |
| --- | --- |
| **Tile** | One little square of the map |
| **Event** | Anything on the map that does something: people, doors, chests, signs |
| **Page** | An event can have several pages; the last page whose conditions are true is used |
| **Switch** | An on/off light the game remembers ("door unlocked?") |
| **Variable** | A number the game remembers ("how many fish caught?") |
| **Self switch** | A switch that belongs to just one event (A, B, C, D), like "this chest is open" |
| **Common event** | Commands you can use from many places, like "heal the party" |
