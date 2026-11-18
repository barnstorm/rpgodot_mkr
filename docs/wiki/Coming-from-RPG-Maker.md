# Coming from RPG Maker

The kit follows RPG Maker's way of working: maps painted from tilesets, events with pages and commands, a database, playtest. Most of what you know carries over. This page says where things are and what is different.

## The big differences

- **IDs are names, not numbers.** Switch `talked_to_king`, not 0012; item `potion`, not 0001. There is no *Change Maximum*: press **New**. IDs of deleted records are never reused.
- **Text codes use IDs:** `\V[talked_count]`, `\N[hero]`.
- **Features are called Traits**, Troops are **Enemy groups**, and skill/weapon/armour types live on the **Types** tab.
- **Stats depend on the rule system.** *Classic* has XP-style stats (HP, SP, STR, DEX, AGI, INT); *VX Ace style* has Ace's (MHP, MMP, ATK, DEF, MAT, MDF, AGI, LUK, TP). See [Rule systems](Rule-Systems.md).
- **It is Godot.** Anything the kit doesn't do can be added with GDScript: a custom command, a plugin, or a whole scene. See [For programmers](For-Programmers.md).
- **No RTP is included.** Import your own ([Importing RPG Maker resources](Importing-RPG-Maker-Resources.md)) or use the CC0 starter art.
- **RPG Maker projects are not converted.** The importer brings art and sound; maps, events and databases are not read (except tileset settings from MV/MZ and XP).

## Where things are

| RPG Maker | RPG Kit |
| --- | --- |
| File > New Project | Godot project + **Create RPG project** |
| Mode: Map / Event / Region | **Mode** menu, or F5 / F6 / F7 |
| Draw: Pencil, Rectangle, Ellipse, Flood Fill, Shadow Pen | **Draw** menu or toolbar |
| Scale | **Scale** menu, or Ctrl+= / Ctrl+− / Ctrl+0 |
| Tools > Database (F8 / F9) | **Tools > Database** (F8), or the Database tab |
| Game > Playtest | **Game > Playtest** (F9), or Ctrl+R |
| Map tree right-click: Shift, Load Sample Map, Generate Dungeon | The same items on the map tree's right-click menu |
| Event right-click: Set Starting Position > Player / Boat / Ship / Airship | The same, in Event mode |
| Quick Event Creation > Door / Treasure / Inn / Transfer | Right-click a tile > **Quick events** |
| Database > Troops | Database > **Enemy groups** |
| Features | **Traits** |
| Tilesets tab: passability (○/×, ☆, directions) | The **Tiles** button on the RPG tab |
| Parallax mapping (a map drawn as one picture, with a plugin or blank tiles for collision) | Built in: [Image-backed maps](Image-Backed-Maps.md), with a foreground picture and painted navigation |
| Terms tab: skill, weapon and armour types | Database > **Types** |
| Change Maximum… | **New** (IDs are names like `potion`, and are never reused) |
| Switch/Variable 0001 | Named switches and variables, e.g. `talked_to_king` |
| `\V[1]`, `\N[1]` | `\V[talked_count]`, `\N[hero]` (an ID instead of a number) |
| `\I[n]` (VX/MV message icon), the Icon field of items, skills and states | The same: `\I[64]` and the **Icon** field (a grid of the icon sheet, searchable by name). The starter icons are the kit's own (CC0), so their numbers differ from RPG Maker's IconSet |
| Control Switches / Variables / Self Switch | Control Switch / Variable / Self Switch — and they reach further: a self switch can be set on any event on any map (and reset per event or per map), and events have **self variables** (Control Variable's *Self variable* target, `\E[name]` in text) |
| Change HP / MP | Change HP / SP (with the Classic rules; MP with the VX Ace rules) |
| Select Item (VX Ace/MV/MZ) | Select Item: key items, regular items or both; the chosen id lands in a text variable (ids are names, so 0/"none" on cancel) |
| Change Party Member | Change Party Member |
| Set Vehicle Location, Get On/Off Vehicle | The same commands (*movement* category) |
| Change Encounter, Change Menu Access, Change Save Access | Change Encounter, Change Menu / Save Access |
| Label, Jump to Label | The same (*flow* category). A jump reaches a label anywhere in the event, inside a Conditional Branch, a Loop or a choice too; with several labels of one name the nearest wins (RPG Maker takes the first from the top) |
| Call Event (RM2000/2003) | **Call Event** runs a map event's page inline — this event, by ID, or the ID from a variable; the page's self switches belong to the called event. The common-event tab is **Call Common Event** |
| Common events on game moments (plugins: Yanfly Utility Common Events, Galv's Auto Common Events, Hime's Level Up Events, run-on-map-load) | Built in: a common event's Trigger can be an **engine moment** — new game, load, map enter/leave, every N steps, region/terrain enter, level up, state added/removed, knockout, battle start/end, game over, menu, party change, vehicles — narrowed by filters (only map, actor, state, region, outcome, vehicle), with the moment's data as Game Data `hook.*` ([Lesson 5](Lesson-5-Cutscenes-and-Common-Events.md)) |
| Show Animation, Change Actor Graphic, Change Name / Nickname, Change Level / EXP / Skills / Equipment / Class | The same commands |
| Change Transparency, Change Map Name Display, Change Tileset, Change Parallax, Change Battle Back | The same commands |
| Change Battle BGM, Change Victory ME, Stop SE, Change Window Skin, Get Location Info | The same commands |
| Control Variables: Game Data / Random / Other: Timer | The value's mode: **Game data** (items held, gold, steps, play time, party size, an actor's level, EXP or stats, a **Timer**'s seconds left) or **Random** |
| Control Variables: ÷ and % of negative numbers; dividing by zero | As the rule system's RPG Maker: VX Ace rules round down (−7 ÷ 2 = −4, −7 % 2 = 1), Classic rules cut towards zero (−3 and −1). Dividing by zero sets 0 and the event goes on |
| System tab: Boat / Ship / Airship | Database > System > **Vehicles** (graphic, start position with Pick on map, music, speed) |
| Conditional Branch: Vehicle | Condition kind **Vehicle** |
| Timer Operations (2000/2003) | **Control Timer**: two timers; Set (time in seconds, show on screen, which corner), Start, Stop, and what it does in battle (pause, keep counting, or abort at 0 — no rewards, the escape branch). The **Timer** condition (pages and branches) checks the time left, any comparison |
| Conditional Branch: the actor's HP / MP / level | Condition kind **Actor**: level, HP or SP (SP is MP), as a value or a percentage of the max, with any comparison |
| Conditional Branch: Script (VX Ace/MV/MZ) | Condition kind **Formula**: the kit's formula language, e.g. `v.treasures >= 3` (no Ruby/JavaScript) |
| Conditional Branch: what started the event / collision checks | **Started by** (action button, a touch, autorun, parallel, Call Event) and **Can pass** (a character can step N cells a direction), branch-only kinds |
| Troops: Autoname | **Autoname** on the Enemy groups tab |
| Actor Description, Status screen | Actor **Description**; on the Status screen, OK shows it |
| Skill Damage type: HP / MP Damage, HP / MP Recover, HP / MP Drain | **Damage type** (*damage*, *recover* or *drain*) with **Affects** (HP, MP). A drain takes the amount from the target, at most what it has left, and gives it to the user; guarding and critical hits count as for damage |
| A revive item: scope *One Ally (Dead)* with *Recover HP* (VX Ace, MV) | The same under the VX Ace rules: target *One dead ally* (or a *dead or alive* scope) and a **Recover** effect on HP raise the fallen with that HP, in any effect order. Under the Classic rules list **Remove State**: Knockout before the recovery |
| Enemy action conditions: *HP a% ~ b%*, *MP a% ~ b%*, *Party Level ≥ N* | Condition **Own HP %** / **Own MP %** with **From %** and **To %** (both ends count), and **Party level** (*Highest*, ≥ by default; *Average* for 2000 / 2003) |
| Class parameter curves | Classes: each stat is **Per level** or **Curve** (level 1 / level 99 values and a shape), with a graph |
| Battle Test (party, levels) | **Game > Battle test…** (choose the enemy group, the party and their levels), or Battle test on the Enemy groups tab |
| Auto-change BGM / BGS | Map properties: Music and Background sound, each "(keep playing)", "(stop)" or a file |
| F9 debug, Ctrl walk-through | The same in playtest |

## Following the official tutorials

The official beginner tutorials at <https://www.rpgmakerweb.com/tutorials> are written for RPG Maker VX and VX Ace, and you can follow them in the kit:

1. Create the project with the **Style** *RPG Maker VX / VX Ace* (544×416) ([Installation](Installation.md)).
2. Import the VX Ace RTP you own with *Tools > Resources > Import an RPG Maker project or RTP folder…*
3. Switch to the *VX Ace style* rule system (*Database > Rule system…*) if the tutorial talks about ATK, MAT and TP.
4. Check the imported tilesets' passability with **Tiles**: VX/Ace keep it in a database file the kit doesn't read.

The menus, messages and battle screen are laid out for 320×240 and scaled up on the larger VX and MV screens.

## Things still different

- **Vehicles**: the boat crosses shallow water, the ship any water, and the airship lands only on walkable ground. Water is recognised from the tileset's water autotiles.
- **Tile graphics for events**: pick *Tile* in the event's graphic picker and click a tile.
- **MIDI tempo**: a sound's pitch changes speed and pitch together ([MIDI music](MIDI-Music.md)).
- **Battle**: no weapon sprites in side view, no buffs/debuffs, no *Auto* party command. See [Limitations](Limitations.md).
