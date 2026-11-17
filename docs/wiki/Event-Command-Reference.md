# Event command reference

Every built-in event command, by the category it has in the command picker. Each is edited in a form; the fields are listed here. Plugins add more commands under their own ★ categories (see [Plugins](Plugins.md)), and you can write your own ([For programmers](For-Programmers.md#custom-event-commands)).

There are 94 built-in commands. The *ID* is the command's `type` in the event JSON files.

## Message

| Command | ID | Fields |
| --- | --- | --- |
| **Input Number** | `input_number` | Store in, Digits |
| **Key Input Processing** | `key_input` | Store in, Wait until pressed, Accepted keys, Store time in, Extra actions |
| **Select Item** | `select_item` | Store in, Which items |
| **Show Balloon Icon** | `show_balloon` | Character, Balloon, Wait until done |
| **Show Choices** | `show_choices` | Choices (one with an empty label is not shown), Cursor starts on, When cancelled (*Disallow*, *A choice* with its number, *Last choice* or *Branch*; a new command starts on *Last choice*), On cancel |
| **Show Scrolling Text** | `show_scrolling_text` | Text, Speed, No fast forward |
| **Show Text** | `show_text` | Face, Speaker name, Text, Position, Background, Show gold window |


**Key Input Processing** stores these codes — RPG Maker 2003's numbering, so games port over.
`Menu`, `Debug`, `Through` and `Overlay` are this kit's own actions; actions you list in
**Extra actions** count from 100 in the order you list them.

| Key | Code | Key | Code |
| --- | --- | --- | --- |
| Down | 1 | Digits 0-9 | 10-19 |
| Left | 2 | `+` `-` `*` `/` `.` | 20-24 |
| Right | 3 | Menu | 30 |
| Up | 4 | Debug | 31 |
| Confirm | 5 | Through | 32 |
| Cancel | 6 | Overlay | 33 |
| Shift (Dash) | 7 | Extra actions | 100, 101, ... |

When two accepted keys land in the same frame, RPG Maker 2003's priority decides: `.` `/` `*`
`-` `+` first, then digits 9 to 0, then Shift, Cancel, Confirm, Up, Right, Left, Down; the kit's
actions follow, then the ones you listed. Without **Wait until pressed**, a held key counts and
"nothing held" stores 0. With it, the variable reads 0 for the whole wait and **Store time in**
records how long the wait took, in tenths of a second.

## Flow

| Command | ID | Fields |
| --- | --- | --- |
| **Break Loop** | `break_loop` |  |
| **Call Common Event** | `call_common_event` | Common event |
| **Call Event** | `call_event` | Event (This event / Event ID / From a variable), Event ID, Holds the event's id, Page |
| **Comment** | `comment` | Comment |
| **Conditional Branch** | `if` | If, Then, Else |
| **Despawn Event** | `despawn_event` | Event (an ID, this, or a variable holding an ID) |
| **Erase Event** | `erase_event` |  |
| **Exit Event Processing** | `exit_event` |  |
| **Jump to Label** | `jump_to_label` | Label name. The label can be anywhere in the same event page or common event, inside a branch, a loop or a choice too |
| **Label** | `label` | Label name |
| **Loop** | `loop` | Repeat |
| **Spawn Event** | `spawn_event` | Template event, Template map, Cell, Store its ID in |
| **Wait** | `wait` | Seconds |

## Switches and variables

| Command | ID | Fields |
| --- | --- | --- |
| **Control Self Switch** | `set_self_switch` | Action, Self switch, ON, Event (blank = this event), Map (blank = this map) |
| **Control Switch** | `set_switch` | Switch, Set to |
| **Control Variable** | `set_variable` | Target (One variable / Range / Indirect / Self variable), Variable, From, To, Holds the target's id, Name, Event (blank = this event), Map (blank = this map), Operation, Value |
| **Control Timer** | `control_timer` | Timer (1 / 2), Operation (Set / Start / Stop), Time (seconds), Show on screen, Position, In battle (Pause / Keep counting / Abort at 0) |
| **Get Location Info** | `get_location_info` | Store in, Info, Layer, X, Y |

## Party

| Command | ID | Fields |
| --- | --- | --- |
| **Call Inn** | `call_inn` | Price, Message style (1 / 2), Ask text, Not enough gold text, Jingle, Gold window, When the party stays, When they don't stay |
| **Change Actor Graphic** | `change_actor_graphic` | Actor, Map sprite sheet (blank = keep), Sprite index, Face sheet (blank = keep), Face index, Battler image (blank = keep) |
| **Change Encounter** | `change_encounter` | Random encounters on |
| **Change Gold** | `change_gold` | Operation, Amount |
| **Change HP / SP** | `change_hp_mp` | Target (actors, or in a battle *Entire troop* / *Enemy #*), Enemy #, Resource, Operation, Amount, Allow knockout (on the map, the whole party down is Game Over, or the System's defeat handler) |
| **Change Items** | `change_items` | Kind, Item, Operation, Amount |
| **Change Name** | `change_name` | Actor, Name |
| **Change Nickname** | `change_nickname` | Actor, Nickname |
| **Change Party Member** | `change_party` | Actor, Operation, Initialize (reset level and equipment), Only for this battle |
| **Change State** | `change_state` | Target (actors, or in a battle *Entire troop* / *Enemy #*), Enemy #, State, Operation, Ignore resist rates |
| **Recover All** | `recover_all` | Target (actors, or in a battle *Entire troop* / *Enemy #*), Enemy # |

**Call Inn** runs the whole inn stay: it asks with one of the System's two inn messages (Terms records `inn_1` / `inn_2`; the *Message style* field picks between them, as in RPG Maker 2003) beside a Yes/No — cancelling counts as No. **Yes** without the price shows the System's can't-afford message (Terms `inn_no_gold`), and both that and **No** run the *When they don't stay* branch. **Yes** with the gold takes the price, fades out, plays the inn jingle (ME — the `inn_rest` sound role, or the *Jingle* field), recovers the party exactly as **Recover All** would, fades back in and runs *When the party stays*. In every message `%1` is the price and `\G` the currency unit, and the *Ask text* / *Not enough gold text* fields replace the System messages for this call alone. The *Price* is an operand, so it can come from a variable.

## Actors and rules

| Command | ID | Fields |
| --- | --- | --- |
| **Change Class** | `change_class` | Target, Class, Keep EXP |
| **Change EXP** | `change_exp` | Target, Operation, EXP, Show level up |
| **Change Equipment** | `change_equipment` | Actor, Slot, Item kind, Item (blank = remove) |
| **Change Level** | `change_level` | Target, Operation, Levels, Show level up |
| **Change Skills** | `change_skills` | Target, Operation, Skill |
| **Change Stat** | `change_stat` | Target, Stat, Operation, Amount |
| **Roll Check** | `roll_check` | Who rolls, Stat, Difficulty, Store success in, Store the roll in (optional) |

## Movement

| Command | ID | Fields |
| --- | --- | --- |
| **Change Player Followers** | `toggle_followers` | Followers visible |
| **Change Transparency** | `change_transparency` | Player is transparent |
| **Change Vehicle Graphic** | `change_vehicle_graphic` | Vehicle, Graphic, Music while riding (blank = keep) |
| **Get On/Off Vehicle** | `get_on_off_vehicle` |  |
| **Memorize Place** | `memorize_place` | Store map in, Store x in, Store y in |
| **Scroll Map** | `scroll_map` | Direction, Tiles, Speed, Wait until done |
| **Set Event Location** | `set_event_location` | Event, Mode, Cell [x, y], Swap with event, Facing, Keep (off, as in RPG Maker: the event is back at its editor position the next time the map loads; on: it returns to this place instead) |
| **Set Move Route** | `move_route` | Character, Route, Repeat, Skip if blocked, Wait until done |
| **Set Vehicle Location** | `set_vehicle_location` | Vehicle, Location, Facing |
| **Transfer Player** | `transfer_player` | Destination, Facing, Fade, If occupied, use the nearest free cell within |

## Screen

| Command | ID | Fields |
| --- | --- | --- |
| **Change Map Name Display** | `change_map_name_display` | Show map names |
| **Change Parallax Background** | `change_parallax` | Image (blank = none), Loop, Horizontal scroll (0 = fixed, 1 = with the map), Vertical scroll (0 = fixed, 1 = with the map) |
| **Change Tileset** | `change_tileset` | Tileset |
| **Change Tile** | `change_tile` | Layer, Change (every matching tile / one cell), From tile, To tile, X, Y, Keep |
| **Change Window Skin** | `change_windowskin` | Window skin (blank = default) |
| **Fade In Screen** | `fade_in` | Seconds |
| **Fade Out Screen** | `fade_out` | Seconds, Colour |
| **Flash Screen** | `flash_screen` | Colour (r, g, b, strength), Seconds, Wait until done |
| **Set Weather Effects** | `set_weather` | Weather, Power |
| **Shake Screen** | `shake_screen` | Power, Seconds, Wait until done |
| **Show Animation** | `show_animation` | Character, Animation, Wait for completion |
| **Tint Screen** | `tint_screen` | Red %, Green %, Blue %, Seconds, Wait until done |

**Change Tile** replaces tiles by their key (`lower_17`, `water_a`…) on one layer — every cell holding the *From* key, or just the cell at X, Y (the coordinates are operands, so they can come from variables). The map redraws immediately and passability follows the new tile. The exact tile you pick is painted; autotiles do not re-shape around it. Like RPG Maker 2000/2003, a change lasts until the map is reloaded (a transfer to another map and back restores the saved tiles); **Keep** also stores it in the save, so it survives reloads and loading.

## Pictures

| Command | ID | Fields |
| --- | --- | --- |
| **Erase Picture** | `erase_picture` | Number |
| **Move Picture** | `move_picture` | Number, X (pixels), Y (pixels), Scale %, Opacity, Seconds, Wait until done |
| **Show Picture** | `show_picture` | Number, Picture, X (pixels), Y (pixels), Origin, Scale %, Opacity |

## Music and sound

| Command | ID | Fields |
| --- | --- | --- |
| **Change Battle BGM** | `change_battle_bgm` | Battle music |
| **Change Victory ME** | `change_victory_me` | Victory jingle |
| **Fade Out BGM** | `fade_music` | Seconds |
| **Play BGM** | `play_music` | Music |
| **Play ME** | `play_jingle` | Jingle, Wait until done |
| **Play SE** | `play_sound` | Sound |
| **Stop Sound** | `stop_sound` | Stop |

## Scenes

| Command | ID | Fields |
| --- | --- | --- |
| **Battle Processing** | `battle` | Enemy group source (Enemy group / Enemy group named by a variable / Random encounter on this map), Enemy group, Variable, Can escape, Continue when lost, Battle scene (blank = default), Background (blank = map's), Advantage (normal / preemptive / surprise / initiative / back attack / surround / pincer — a pincer also blocks escaping; see [Lesson 7](Lesson-7-Battles.md)), Store outcome in, If won, If escaped, If lost |
| **Change Battle Background** | `change_battle_back` | Background (blank = map default) |
| **Change Menu / Save Access** | `change_access` | Access to, Allowed |
| **Enemy Appear** | `enemy_appear` | Enemy, Enemy # (1 = first in the group) |
| **Transform Enemy** | `transform_enemy` | Enemy # (1 = first in the group), Transform into, HP (keep / percent / refill), Remove its states |
| **Force Flee** | `force_flee` | Who flees (Enemy # / Every enemy / The party), Enemy # (1 = first in the group) |
| **Force Action** | `force_action` | Subject (Enemy # / Actor), Enemy #, Actor, Uses (skill / item), Skill, Item, Target (last / random / #), Target #, Timing (right now / at its next turn) |
| **End Battle** | `abort_battle` | Result (abort / win / lose), Give victory rewards |
| **Game Over** | `game_over` |  |
| **Name Input Processing** | `name_input` | Actor, Max characters |
| **Open Menu Screen** | `open_menu` |  |
| **Open Save Screen** | `open_save` |  |
| **Return to Title Screen** | `return_to_title` |  |
| **Run Scene** | `run_scene` | Scene, Arguments, Store result in, Timeout (0 = none), If cancelled |
| **Shop Processing** | `shop` | Goods, Buy only |

## Godot

| Command | ID | Fields |
| --- | --- | --- |
| **Call Method** | `call_method` | Node, Method, Arguments, Store return value in |
| **Emit Signal** | `emit_signal` | Signal name, Arguments |

*This page is generated from the command scripts in `addons/rpg/runtime/commands/` (each command's `descriptor()`).*
