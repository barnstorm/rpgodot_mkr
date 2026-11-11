# Following the RPG Maker tutorials in RPG Kit

The official beginner tutorials at <https://www.rpgmakerweb.com/tutorials> are written for RPG Maker VX and VX Ace. RPG Kit follows the same workflow, so you can work through them here. This page says where RPG Kit names or places things differently, and which steps need something extra.

## Setting up

- **New Project:** make an empty Godot project, copy `addons/rpg` and `addons/rpg_database` into it, and enable *RPG Kit* in *Project > Project Settings > Plugins*. Then press **Create RPG project** on the **RPG** tab. For the VX and VX Ace tutorials, set **Style** to *RPG Maker VX / VX Ace*: the game screen becomes 544×416, and imported VX character and face sheets are cut the VX way. The menus and battle screen are laid out RPG Maker 2000-style and scaled up to fit.
- **Maker view:** while you're on the RPG or Database tab, Godot's own panels are hidden, so the screen looks like RPG Maker's window. Turn this off with *Project > Maker view*.
- **Your RPG Maker art:** the tutorials use RPG Maker's bundled art and sounds (the RTP). If you own RPG Maker, use *Tools > Resources > Import an RPG Maker project or RTP folder…* to copy your RTP or project graphics in. RPG Kit doesn't ship the RTP; check RPG Maker's licence before you publish games that use it.

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
| Terms tab: skill, weapon and armour types | Database > **Types** |
| Change Maximum… | **New** (IDs are names like `potion`, and are never reused) |
| Switch/Variable 0001 | Named switches and variables, e.g. `talked_to_king` |
| `\V[1]`, `\N[1]` | `\V[talked_count]`, `\N[hero]` (an ID instead of a number) |
| `\I[n]` (VX/MV message icon), the Icon field of items, skills and states | The same: `\I[64]` and the **Icon** field (a grid of the icon sheet, searchable by name). The starter icons are the kit's own (CC0), so their numbers differ from RPG Maker's IconSet |
| Control Switches / Variables / Self Switch | Control Switch / Variable / Self Switch |
| Change HP / MP | Change HP / SP (with the Classic rules; MP with the VX Ace rules) |
| Change Party Member | Change Party Member |
| Set Vehicle Location, Get On/Off Vehicle | The same commands (*movement* category) |
| Change Encounter, Change Menu Access, Change Save Access | Change Encounter, Change Menu / Save Access |
| Label, Jump to Label | The same (*flow* category) |
| Show Animation, Change Actor Graphic, Change Name / Nickname, Change Level / EXP / Skills / Equipment / Class | The same commands |
| Change Transparency, Change Map Name Display, Change Tileset, Change Parallax, Change Battle Back | The same commands |
| Change Battle BGM, Change Victory ME, Stop SE, Change Window Skin, Get Location Info | The same commands |
| Control Variables: Game Data / Random | The value's mode: **Game data** (items held, gold, steps, play time, party size, an actor's level, EXP or stats) or **Random** |
| System tab: Boat / Ship / Airship | Database > System > **Vehicles** (graphic, start position with Pick on map, music, speed) |
| Conditional Branch: Vehicle | Condition kind **Vehicle** |
| Troops: Autoname | **Autoname** on the Enemy groups tab |
| Actor Description, Status screen | Actor **Description**; on the Status screen, OK shows it |
| Class parameter curves | Classes: each stat is **Per level** or **Curve** (level 1 / level 99 values and a shape), with a graph |
| Battle Test (party, levels) | **Game > Battle test…** (choose the enemy group, the party and their levels), or Battle test on the Enemy groups tab |
| Auto-change BGM / BGS | Map properties: Music and Background sound, each "(keep playing)", "(stop)" or a file |
| F9 debug, Ctrl walk-through | The same in playtest |

## Rule systems: VX vs VX Ace stats

The **Classic** rule system uses XP-style stats: HP, SP, STR, DEX, AGI, INT. The **VX Ace style** rule system uses the stats the Ace tutorials talk about: MHP, MMP, ATK, DEF, MAT, MDF, AGI, LUK and TP (0–100). It also has:

- Ace's damage formulas, with 20% variance and ×3 critical hits.
- HIT, EVA and CRI checks.
- Class parameter curves (level 1 value, level 99 value and a growth shape).
- The basis/extra/acceleration EXP curve.
- Features: Element Rate, State Rate, Ex-Parameters, Add/Seal Skill Type, Dual Wield, Seal Equip, Action Times+, and HP/MP Regen.

Switch with *Database > Rule system…*. The switch shows a preview and makes a backup first.

With VX Ace style rules, actors can only use a skill type (Magic, Special) once their class or actor record adds it with an *Add Skill Type* trait, just as in Ace.

Not covered yet: buffs and debuffs; Sp-Parameters other than critical rate; Counter Attack and Magic Reflection; Special Flags; Party Abilities; Fix Equip; and Attack State. Action Times+ repeats the same action.

## Things still different

- **Vehicles:** the boat crosses shallow water, the ship crosses any water, and the airship lands only on walkable ground. Water is recognised from the tileset's water autotiles.
- **Tileset tabs:** with VX, VX Ace and MV tilesets the palette has RPG Maker's tabs (A, A5, B, C, D, E); with 2000/2003 tilesets it has A, B, C and Anim. **R** holds region numbers.
- **Tile graphics for events:** pick *Tile* in the event's graphic picker and click a tile of the tileset.
- **RPG Maker passability:** importing an MV or MZ folder reads its `data/Tilesets.json`. You get RPG Maker's own tilesets and each tile's passage, star, ladder, bush, counter, damage floor and terrain tag. VX, VX Ace and XP keep these in a binary database that RPG Kit doesn't read, so their tiles start with guessed settings, which you check in the **Tiles** dialog.
