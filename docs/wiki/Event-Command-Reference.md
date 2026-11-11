# Event command reference

Every built-in event command, by the category it has in the command picker. Each is edited in a form; the fields are listed here. Plugins add more commands under their own ★ categories (see [Plugins](Plugins.md)), and you can write your own ([For programmers](For-Programmers.md#custom-event-commands)).

There are 78 built-in commands. The *ID* is the command's `type` in the event JSON files.

## Message

| Command | ID | Fields |
| --- | --- | --- |
| **Input Number** | `input_number` | Store in, Digits |
| **Show Balloon Icon** | `show_balloon` | Character, Balloon, Wait until done |
| **Show Choices** | `show_choices` | Choices, Cursor starts on, When cancelled, On cancel |
| **Show Scrolling Text** | `show_scrolling_text` | Text, Speed, No fast forward |
| **Show Text** | `show_text` | Face, Speaker name, Text, Position, Background, Show gold window |

## Flow

| Command | ID | Fields |
| --- | --- | --- |
| **Break Loop** | `break_loop` |  |
| **Call Common Event** | `call_common_event` | Common event |
| **Comment** | `comment` | Comment |
| **Conditional Branch** | `if` | If, Then, Else |
| **Erase Event** | `erase_event` |  |
| **Exit Event Processing** | `exit_event` |  |
| **Jump to Label** | `jump_to_label` | Label name |
| **Label** | `label` | Label name |
| **Loop** | `loop` | Repeat |
| **Wait** | `wait` | Seconds |

## Switches and variables

| Command | ID | Fields |
| --- | --- | --- |
| **Control Self Switch** | `set_self_switch` | Self switch, ON, Event (blank = this event) |
| **Control Switch** | `set_switch` | Switch, Set to |
| **Control Variable** | `set_variable` | Variable, Operation, Value |
| **Get Location Info** | `get_location_info` | Store in, Info, Layer, X, Y |

## Party

| Command | ID | Fields |
| --- | --- | --- |
| **Change Actor Graphic** | `change_actor_graphic` | Actor, Map sprite sheet (blank = keep), Sprite index, Face sheet (blank = keep), Face index, Battler image (blank = keep) |
| **Change Encounter** | `change_encounter` | Random encounters on |
| **Change Gold** | `change_gold` | Operation, Amount |
| **Change HP / SP** | `change_hp_mp` | Target, Resource, Operation, Amount, Allow knockout |
| **Change Items** | `change_items` | Kind, Item, Operation, Amount |
| **Change Name** | `change_name` | Actor, Name |
| **Change Nickname** | `change_nickname` | Actor, Nickname |
| **Change Party Member** | `change_party` | Actor, Operation, Initialize (reset level and equipment) |
| **Change State** | `change_state` | Target, State, Operation |
| **Recover All** | `recover_all` | Target |

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
| **Scroll Map** | `scroll_map` | Direction, Tiles, Speed, Wait until done |
| **Set Event Location** | `set_event_location` | Event, Mode, Cell [x, y], Swap with event, Facing |
| **Set Move Route** | `move_route` | Character, Route, Repeat, Skip if blocked, Wait until done |
| **Set Vehicle Location** | `set_vehicle_location` | Vehicle, Location, Facing |
| **Transfer Player** | `transfer_player` | Destination, Facing, Fade, If occupied, use the nearest free cell within |

## Screen

| Command | ID | Fields |
| --- | --- | --- |
| **Change Map Name Display** | `change_map_name_display` | Show map names |
| **Change Parallax Background** | `change_parallax` | Image (blank = none), Loop, Horizontal scroll (0 = fixed, 1 = with the map), Vertical scroll (0 = fixed, 1 = with the map) |
| **Change Tileset** | `change_tileset` | Tileset |
| **Change Window Skin** | `change_windowskin` | Window skin (blank = default) |
| **Fade In Screen** | `fade_in` | Seconds |
| **Fade Out Screen** | `fade_out` | Seconds, Colour |
| **Flash Screen** | `flash_screen` | Colour (r, g, b, strength), Seconds, Wait until done |
| **Set Weather Effects** | `set_weather` | Weather, Power |
| **Shake Screen** | `shake_screen` | Power, Seconds, Wait until done |
| **Show Animation** | `show_animation` | Character, Animation, Wait for completion |
| **Tint Screen** | `tint_screen` | Red %, Green %, Blue %, Seconds, Wait until done |

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
| **Battle Processing** | `battle` | Enemy group, Can escape, Continue when lost, Battle scene (blank = default), Background (blank = map's), Advantage, Store outcome in, If won, If escaped, If lost |
| **Change Battle Background** | `change_battle_back` | Background (blank = map default) |
| **Change Menu / Save Access** | `change_access` | Access to, Allowed |
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
