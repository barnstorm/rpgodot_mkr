# Following the RPG Maker tutorials in RPG Kit

The official beginner tutorials at <https://www.rpgmakerweb.com/tutorials> are written for RPG Maker VX and VX Ace. RPG Kit follows the same workflow, so you can work through them here. This page says where RPG Kit names or places things differently, and which steps need something extra.

## Setting up

- **New Project:** from the sample's **RPG** tab, choose **Project > New project...**, enter a name, choose a new or empty folder, and press **Create project**. It creates an independent Godot project with the kit and starter data. In an empty Godot project where the kit is already installed, press **Create RPG project** on the **RPG** tab instead. For the VX and VX Ace tutorials, set **Style** to *RPG Maker VX / VX Ace*: the game screen becomes 544×416, and imported VX character and face sheets are cut the VX way. The menus and battle screen are laid out RPG Maker 2000-style and scaled up to fit.
- **Maker view:** while you're on the RPG or Database tab, Godot's own panels are hidden, so the screen looks like RPG Maker's window. Turn this off with *Project > Maker view*.
- **Your RPG Maker art:** the tutorials use RPG Maker's bundled art and sounds (the RTP). If you own RPG Maker, use *Tools > Resources > Import an RPG Maker project or RTP folder…* to copy your RTP or project graphics in. RPG Kit doesn't ship the RTP; check RPG Maker's licence before you publish games that use it.

## Where things are

| RPG Maker | RPG Kit |
| --- | --- |
| File > New Project | RPG tab > Project > **New project...** |
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
| Show Choices: *When Cancel* (Disallow, Choice 1-4, Branch); blank choices are not shown | **Show Choices**: *When cancelled* is *Disallow*, *A choice* (its number, counted from 0), *Last choice* (the default of a new command, as RPG Maker's Choice 2 of Yes / No) or *Branch*. A choice with an empty label is not shown. Cancel never takes a hidden or greyed-out choice |
| Control Switches / Variables / Self Switch | Control Switch / Variable / Self Switch |
| Event priority: a new page is *Below Characters*; choosing a character graphic makes it *Same As Characters* | The same. An empty page (the tutorials' "make the event disappear") is walked through. Pages saved by older versions of the kit keep the priority they were saved with |
| Self Switch condition (the event's own A-D) | Leave the condition's *Event* and *Map* blank (or type `this`) for the event the page belongs to; name another event or map to read theirs |
| Common events that run on game moments (plugins: Yanfly Utility Common Events, Galv's Auto Common Events, Hime's Level Up Events) | Built in: a common event's Trigger can be an **engine moment** (map enter/leave, every N steps, region/terrain, level up, state added/removed, knockout, battle start/end, game over, menu, party change, vehicles, new game, load), with filters and the moment's data as Game Data `hook.*` |
| Timer Operations (2000/2003) | **Control Timer**: two timers; Set (time, show on screen, corner), Start, Stop, and what it does in battle (pause, count, or abort at 0); the **Timer** condition checks the time left |
| Key Input Processing (2000/2003) | The same (*message* category); the key codes match 2003's numbering, and the kit's rpg_* actions (menu, debug, through, overlay, or your own) can be accepted too |
| Change Tile (2000/2003) | The same (*screen* category): replaces every tile of a layer matching a key, or sets the single cell at X, Y; **Keep** stores the change in the save (without it the map resets when reloaded, as in RPG Maker) |
| Call Inn (2000/2003) | **Call Inn** (*party* category): the ask message from one of the two System styles (Terms), Yes/No with cancel as No, the can't-afford message, gold, fade, jingle (ME), a full Recover All and branches for stayed / didn't stay |
| Battle commands (2003) | An actor's or class's **Battle commands** list builds the battle menu: Attack, Skill, a **Skill type** (only that type's skills; the VX Ace default menu when skill types are granted), Guard, Item, Escape, **Row** (swap front/back rows mid-battle; row rates scale physical damage dealt and taken) or **Event** (*Link to Event*: a menu entry the troop's battle events answer through the *Command used* condition, by its id or generically) |
| Change HP / MP | Change HP / SP (with the Classic rules; MP with the VX Ace rules). With *Allow knockout*, a change that leaves the whole party down on the map is Game Over and the event stops, as in RPG Maker (a trap that can kill); the same goes for Change State adding the knockout state. A System *Defeat handler* takes the place of that Game Over |
| Change Party Member | Change Party Member |
| Set Vehicle Location, Get On/Off Vehicle | The same commands (*movement* category) |
| Set Event Location; events return to their editor positions when the map loads | The same. A move by Set Event Location or a move route lasts for the visit, a transfer inside the map moves nothing, and a game saved on the map loads with the events where they stood. **Keep** on Set Event Location (not in RPG Maker) makes the event return to that place instead. Older versions of the kit kept every Set Event Location for good |
| Change Encounter, Change Menu Access, Change Save Access | Change Encounter, Change Menu / Save Access |
| Label, Jump to Label | The same (*flow* category). A jump reaches a label anywhere in the event, inside a Conditional Branch, a Loop or a choice too; with several labels of one name the nearest wins (RPG Maker takes the first from the top) |
| Show Animation, Change Actor Graphic, Change Name / Nickname, Change Level / EXP / Skills / Equipment / Class | The same commands |
| Change Transparency, Change Map Name Display, Change Tileset, Change Parallax, Change Battle Back | The same commands |
| Change Battle BGM, Change Victory ME, Stop SE, Change Window Skin, Get Location Info | The same commands |
| Control Variables: Game Data / Random / Other: Timer | The value's mode: **Game data** (items held, gold, steps, play time, party size, an actor's level, EXP or stats, a **Timer**'s seconds left) or **Random** |
| Control Variables: ÷ and % of negative numbers; dividing by zero | As the rule system's RPG Maker: VX Ace rules round down (−7 ÷ 2 = −4, −7 % 2 = 1), Classic rules cut towards zero (−3 and −1). Dividing by zero sets 0 and the event goes on |
| System tab: Boat / Ship / Airship | Database > System > **Vehicles** (graphic, start position with Pick on map, music, speed) |
| Conditional Branch: Vehicle | Condition kind **Vehicle** |
| Troops: Autoname | **Autoname** on the Enemy groups tab |
| Troop battle events: *Turn No. a + b×X* (Turn 0 = before the first command) | Condition **Turn**, with *Then every* for the b×X part. Turn 0 is the battle's opening; turn 1 begins when the first commands are entered, before the first action. With the VX Ace rules a repeating page skips the opening, as in VX Ace and MV; with the Classic rules it can include it, as in 2000/2003. Older versions of the kit ran *Turn 1* as the battle opened |
| Actor Description, Status screen | Actor **Description**; on the Status screen, OK shows it |
| Skill Damage type: HP / MP Damage, HP / MP Recover, HP / MP Drain | **Damage type** (*damage*, *recover* or *drain*) with **Affects** (HP, MP). A drain takes the amount from the target, at most what it has left, and gives it to the user; guarding and critical hits count as for damage |
| A revive item: scope *One Ally (Dead)* with *Recover HP* (VX Ace, MV) | The same under the VX Ace rules: target *One dead ally* (or a *dead or alive* scope) and a **Recover** effect on HP raise the fallen with that HP, in any effect order. Under the Classic rules list **Remove State**: Knockout before the recovery |
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
- Features: Element Rate, State Rate, Ex-Parameters, Sp-Parameters, Attack State, Attack Speed, Add/Seal Skill Type, Add/Seal Skill, Equip Weapon/Armor Type, Dual Wield, Seal Equip, Action Times+, Special Flags (Auto Battle, Guard, Substitute, Preserve TP), Collapse Effect, and HP/MP Regen.
- Party abilities, a trait any member carries for the whole party: Encounter Half, Encounter None, Cancel Surprise, Raise Preemptive, Gold Double, Drop Item Double.
- Item and skill effects *Gain TP* (flat TP, capped at the maximum) and *Special Effect: Escape* (whoever it hits leaves the battle).
- MV/MZ scopes: *N random enemies* (1-4 picks, each re-rolled from the living), the *(dead or alive)* ally scopes, and *Everyone* (both sides).
- The remaining Ex- and Sp-Parameters: *Counter Attack* and *Magic Reflection* in battle; *Target Rate*, *Guard Effect*, *Recovery Effect*, *Pharmacology*, *MP Cost Rate*, *Physical/Magic Damage Rate*, *Floor Damage* rate and *Experience* rate.
- MV invocation fields: *Speed* (joins the turn-order roll), *Repeat* (1-9 hits; a random scope re-picks its targets per repeat) and *TP Gain* (charged to the user once per use — not per target or repeat, and even on a miss).
- The rest of the Features: *Attack State* rides every normal attack, *Attack Speed* speeds them, *Add Skill* / *Seal Skill* change the skill list, *Equip Weapon/Armor Type* widen the class's equip lists, *Auto Battle* picks its own command, *Guard* halves damage without the command, *Substitute* covers a friend under a quarter of HP, and the *Collapse Effect* picks the death animation (normal, boss, instant, none).
- State restrictions: *Attack an Enemy* (berserk), *Attack Anyone* (confusion, itself included), *Attack an Ally* (charm, never itself), *Cannot Use Skills* and *Cannot Act*. The most limiting state wins, a confused battler asks for no command (a monster skips its action list), and the log names the driving state.

Switch with *Database > Rule system…*. The switch shows a preview and makes a backup first.

With VX Ace style rules, actors can only use a skill type (Magic, Special) once their class or actor record adds it with an *Add Skill Type* trait, just as in Ace. When they are granted, the default battle menu follows Ace too: Attack, one command per skill type, Guard, Item — and a per-actor or per-class **Battle commands** list replaces it outright.

Not covered yet: Fix Equip. Action Times+ repeats the same action.

## Things still different

- **Vehicles:** the boat crosses shallow water, the ship crosses any water, and the airship lands only on walkable ground. Water is recognised from the tileset's water autotiles.
- **Tileset tabs:** with VX, VX Ace and MV tilesets the palette has RPG Maker's tabs (A, A5, B, C, D, E); with 2000/2003 tilesets it has A, B, C and Anim. **R** holds region numbers.
- **Tile graphics for events:** pick *Tile* in the event's graphic picker and click a tile of the tileset.
- **RPG Maker passability:** importing an MV or MZ folder reads its `data/Tilesets.json`. You get RPG Maker's own tilesets and each tile's passage, star, ladder, bush, counter, damage floor and terrain tag. Importing an XP project reads its `Data/Tilesets.rxdata` the same way (names, autotiles, passability, priorities and terrain tags). VX and VX Ace keep these in a binary database that RPG Kit doesn't read, and an XP RTP has no database, so their tiles start with guessed settings, which you check in the **Tiles** dialog.
