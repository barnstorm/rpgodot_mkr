# Kit plugins

Plugins that ship with RPG Kit. Each is an ordinary extension (a folder with a `manifest.json`), written for the kit from scratch. They are **off by default**:

1. Open *Tools > Extensions*.
2. Tick a plugin and press *Apply (writes rpg/project.json)*.
3. Select it to edit its settings, then press *Save settings (writes rpg/extensions.json)*.

A project's own `extensions/<id>/` folder with the same ID takes precedence over a kit plugin. A build made from the Deploy tab with *Leave out unused assets* leaves out the plugins the project does not enable; the game never loads a plugin that is off.

Commands are under the categories shown in the command picker. Each command fails with a clear message if its plugin is off.

## Menu & options plus (`menu_plus`)

The main menu's commands and extra option rows.

**Settings**

| Setting | Meaning |
| --- | --- |
| Command order | Command IDs shown first, in that order. Built-ins: `item`, `skill`, `equip`, `status`, `options`, `save`, `game_end`. |
| Hidden commands | Command IDs not shown. |
| Extra menu entries | ID, label, icon, and a common event (the menu closes, then it runs) or a scene (opened over the menu until it emits `closed`, `finished` or `cancelled`). *Placed after*, *Shown only while switch is ON*, *Usable only while switch is ON*. Without *Placed after* an entry goes before Options. |
| Party of one: skip choosing the actor | Skills, Equip and Status open for the only member straight away (on by default). |
| Extra option rows | Key, label, kind (on/off, choice, slider), choices or range, default, help line. A row's value can be copied into a switch (on/off rows) or a variable (a choice stores its position, 0-based). |

**Command** *Change menu entry*: shows, hides, greys out or enables any menu command for the rest of the game ("As set up" undoes it). Saved with the game.

The same layout can be written without the plugin in `rpg/project.json`: `"menu": {"order": [...], "hidden": [...], "entries": [...], "skip_single_actor": true}`.

## Message codes plus (`message_plus`)

More control over Show Text.

| Code | Effect |
| --- | --- |
| `<wordwrap>` / `<nowrap>` | Word wrap on or off for this message. With word wrap, typed line breaks become spaces and the text flows to the edge of the box. |
| `<br>` | A new line (any message). |
| `\{` `\}` | Text one step bigger / smaller. |
| `\FS[n]` | Text size n; `\FS[]` is the normal size. |
| `<b>` `</b>`, `<i>` `</i>` | Bold, italic (made from the message font when the theme has none). |
| `\M[name]` | A text macro from the settings (it may contain codes). |
| `\NB[left]`, `\NB[center]`, `\NB[right]` | Where the speaker's name sits, for this message. |

**Settings:** word wrap for every message; keywords with a colour each (whole words, upper or lower case); colour actor names too (and their colour); text macros; name box position; a window behind the name; the size step of `\{` and `\}`.

**Command** *Change message style*: word wrap and the name box position for the rest of the game. Saved with the game.

## Letter sounds (`letter_sounds`)

A short sound every few letters while a message types; its pitch and volume vary a little each time. Spaces and punctuation are silent, and text shown at once (OK pressed) makes no sound.

**Settings:** the sound (an empty file means a built-in blip), every N letters, pitch and volume variation (%), silent characters, and whether actors' own sounds are used.

**Per actor:** the plugin adds a *Letter sound* custom field to actors in the Database. It is used when a message's face (or name) is that actor's.

**Codes:** `\LS[off]` and `\LS[on]` silence and resume from that point; `\LS[file]` switches to another sound file; `\LS[pitch:120]` and `\LS[volume:50]` change it; `\LS[]` goes back to the message's own sound.

**Option row:** *Letter Sounds* ON/OFF for the player.

**Command** *Change letter sound*: on or off for the game, one sound for every message (over actors' sounds), or the interval. Saved with the game.

## Gab window (`gab`)

Short lines ("Brr, it's cold.") in a strip at the top or bottom of the screen. They slide in, stay a moment and fade, and never stop the player or the event that showed them. Gabs queue up and play in order. With anti-repeat on, a gab equal to the one showing or waiting is skipped. The strip draws above menus, messages and battles.

**Settings:** position, seconds shown (base plus per letter), fade time, sound, anti-repeat, the most gabs waiting, window opacity.

**Commands**

- *Show gab*: the text (with codes), a speaker name, a face, a sound, and a switch turned ON when it has faded.
- *Clear gabs*.
- *Wait for gabs*: the event waits until the queue is empty.

**From code** (battle hooks, other plugins): `RPG.extension("gab").show_gab("Ouch!", {"name": "Alex", "face": {"sheet": "hero_face", "index": 0}})`.

## Save & autosave plus (`save_plus`)

**Settings**

- Autosave after a map transfer (not on the first map of a new game or a load).
- Autosave after a battle won or escaped.
- Autosave when the menu opens.
- Players can turn autosave off (an *Autosave* options row).
- An "Autosaved" note: on or off, its text and how long it shows.
- The number of save slots. The last slot is the *Auto* slot.

Autosaves wait for a safe point (no event running), as System > *Auto-save* does.

**Commands**

- *Set save description*: a line shown on the save screen for later saves, in place of the map name. It is saved with the game; empty text removes it.
- *Request autosave*: autosaves once the event has finished.
- *Change autosave*: turns autosaving off or on for the rest of the game, for example during a cutscene.

## Enemy HP gauges and popups (`enemy_gauges`)

An HP bar under each enemy in the default battle scene, in both battle views. It slides to the new value when the enemy is hit; the part just lost stays a moment in its own colour, then drains away. The bar fades out when the enemy falls.

**Settings**

| Setting | Meaning |
| --- | --- |
| Show the gauges | *Always*; *While targeted* (and a moment after a hit); or *Once that enemy type has been defeated* (in any battle of this game, this one included). |
| Width, height | In pixels of the 320×240 layout. |
| Numbers | None, HP, HP / max HP, or percent, drawn over the bar. |
| Colours | Healthy, low (the bar shifts towards it below half), HP being lost, background. |
| Styled damage popups | Critical hits are bigger, in their own colour, with a tag above (*Critical!*) and a small shake; misses drift sideways; recovery is green with a +; numbers pop in (grow, settle, hop up and fade). Colours and texts can be set. |

**Per enemy:** the plugin adds *Hide HP gauge* to enemies in the Database (for bosses).

**Saved with the game:** which enemy types were seen and defeated (section `enemy_records`, shared with the bestiary: while the bestiary is on, it keeps the counts).

## Victory aftermath (`victory_aftermath`)

After a won battle, one results screen instead of the reward messages: a row per actor with its face, level and an EXP bar that fills from the old to the new amount (*LEVEL UP!* when it crosses a level, with the level-up sound), the gold, and the items found. OK (or a click) fills the bars at once, then goes on. Then, for each actor who went up, a level-up screen: the old and new level, every stat old → new (+change), the skills learned, and a quote.

**Settings:** the results title; the seconds the bars take to fill; level-up screens on or off; the level-up tag; music during the results (empty keeps the victory jingle; the map music comes back after the battle as usual); skip the results in auto battle (on by default, so automatic battles stay quick; the reward messages show instead).

**Per actor:** *Level-up quotes* and *New skill quotes* (custom fields, one quote per line). One is picked at random; a new-skill quote is used when the actor learned a skill. Text codes such as `\N[hero]` work.

## Party formation (`party_formation`)

Battle and reserve members. Only the battle members fight; the party order on the map and in the menu is the battle row, then the reserve, so the leader is the first battle member. A member who joins goes into the battle row while it has room, else into the reserve; when a battle member leaves the party, the first reserve member takes the place.

**Formation screen** (a *Formation* main-menu entry, and the *Open formation* command): the battle row on the left, the reserve on the right, details of the chosen member below. Pick a member with OK, then OK on another member to swap them, on an empty battle slot to bring a member into battle, or on the reserve's empty slot to send one out. Locked members (lock icon) cannot be picked or swapped with; required members (star icon) cannot go to the reserve; the battle row always keeps one member. Mouse: hover a slot to move the cursor, click it again for OK.

**Settings:** battle members (1–4); whether members can be sent to the reserve without a swap; EXP for reserve members (% of the battle's EXP); the menu entry, its label and icon; the lock and required icons.

**Commands**

- *Open formation*.
- *Change formation member*: lock or unlock, make required or not, move to the battle row or the reserve (an event may move a locked member; a required member cannot be moved to the reserve).
- *Change battle members*: 1 to 4, or 0 for the setting again.

Saved with the game: the rows, locks, required members and the number of battle members.

## Bestiary (`bestiary`)

An enemy book (a *Bestiary* main-menu entry, and the *Open bestiary* command). Enemies count as seen when they appear in a battle and as defeated when they fall. Category tabs along the top (left/right), with the completion of the tab (defeated / total and a percentage); the list on the left (a check icon for defeated enemies); and on the right the picture, the stats, EXP and gold, weaknesses and resistances (element rates from the rule system, with element icons), drops with their chance, the number defeated, and the lore.

**Settings**

| Setting | Meaning |
| --- | --- |
| Categories | Tabs after *All*: an ID and a label each. |
| A seen enemy shows / A defeated enemy shows | Name only; name and picture; name, picture and stats; everything (EXP, gold, weaknesses, drops, lore). Defaults: name and picture when seen, everything when defeated. |
| Enemies never seen | A dark silhouette and ??????; ?????? only; or not listed until seen (completion still counts them). |
| Menu entry, label, icon | The main-menu entry. |

**Per enemy:** *Bestiary category* (a category ID), *Bestiary lore*, *Leave out of the bestiary*.

**Commands:** *Open bestiary*; *Reveal enemy* (one enemy or every enemy, as seen or defeated).

**Saved with the game:** section `enemy_records` `{seen, defeated}`, shared with the HP gauges plugin.

## Quest journal (`quests`)

Quests the player can follow, with a journal in the main menu and a tracker on the map. Events decide when a quest starts, finishes or fails; the plugin only keeps and shows the state.

**Database:** the plugin adds a *Quests* tab (`rpg/database/quests.json`). A quest has a name, a category, an icon, who gave it, where, a description, objectives and a rewards text. Each objective has an ID, a text and *Hidden until shown by an event*. Quest IDs are renamed with *Rename ID* like any record; commands and conditions that name the quest follow.

**States:** a quest is *Not started*, *Active*, *Completed* or *Failed*. Each objective is *Hidden*, *Shown* (open), *Completed* or *Failed*. When a quest starts its objectives are shown, except the hidden ones.

**Journal:** *Quests* in the main menu (or *Open quest journal*): Active, Completed and Failed tabs (left/right or a click), the quests of the tab, and the chosen quest's icon, name, category, giver, location, description, objectives (a check mark when completed, a cross when failed, an empty box while open) and rewards. OK on an active quest tracks it; OK again stops tracking. The mouse works as on the other screens.

**Tracker:** the tracked quest's name and open objectives in a corner of the map. It hides under menus and messages and fades while the player walks under it. An options row *Quest Tracker* lets players turn it off.

**Notes:** "New quest: ...", "Quest completed: ...", "Objective complete: ..." and the like appear at the top of the screen (under the tracker when it sits at the top).

**Settings:** the menu entry (on/off, label), categories in journal order, the tracker (on/off, corner, how many objectives, fade under the player), tracking a quest when it starts, notes (on/off, seconds, sound).

**Condition** *Quest* (event pages and Conditional Branch): a quest's status, or an objective's state.

**Commands:** *Set quest status*, *Set objective state*, *Track quest* (empty: none), *Open quest journal*.

**Saved with the game:** section `quests` `{quests: {id: {status, objectives: {id: state}}}, tracked}`.

## Lighting and time of day (`lighting`)

Dark maps with soft lights, and a clock that tints outdoor maps from dawn to dusk to night.

**Darkness:** in *Map properties* > *Plugin fields*, tick *Dark map* and choose a colour and a strength (%). *Set darkness* makes the current map dark, not dark, or as its properties say, for the rest of the game.

**Lights:** an event page's *Plugin fields* > *Gives off light*: radius (tiles), colour, brightness and *Flickers*. The light belongs to the page, so a page change can light a torch. Around the player: a light (radius and colour in the settings) and, if turned on, a flashlight cone in the direction the player faces. Lights show as much as it is dark: fully on a dark map or at night, about half at dusk, not at all in daylight.

**Flicker:** lights set to flicker only flicker when the player turns *Light Flicker* on in Options (off by default).

**Time of day** (turn it on in the settings): a clock with *Real minutes per game hour* and the hour a new game starts. Outdoor maps are tinted by the *Outdoor colour by hour* table (hours in between blend smoothly; white is no tint). Maps whose properties say *Indoor* are not tinted. The clock stops in menus and battles (a setting), can be copied into a variable each hour, and can be shown in a corner of the map.

**Condition** *Time of day*: from an hour until another (not included), across midnight when needed (18 until 6 is the night).

**Commands:** *Set darkness*, *Set player light* (on/off, radius, flashlight), *Set event light* (on with a radius and colour, off, or as its page says), *Set time of day*, *Advance time* (hours and minutes, also back), *Pause time*.

**Drawing:** one rectangle on a canvas layer above the map and its characters (under pictures, weather and every window) that follows the camera, with a shader that multiplies the picture by the darkness and the tint and lights it up around each light (up to 48 at once). It works in map pixels, so it fits 320x240, 544x416 and 816x624 screens and the zoomed 16 px art of 32 and 48 px projects.

**Saved with the game:** section `lighting` `{minutes, day, paused, darkness, player, events}`.

## Item crafting (`crafting`)

Make items, weapons and armour from other ones.

**Recipes:** in the Database, an item, weapon or armour's *Custom fields* > *Can be crafted*: the ingredients (items, weapons or armour, each with an amount), how many one craft makes, a crafting category and *Listed only while switch is ON*. Ingredient references are checked and follow renames.

**Screen:** *Crafting* in the main menu, or *Open crafting* with all recipes or only some categories (a forge, a kitchen). The list shows each recipe and how many the party owns; on the right, every ingredient with have/need (red when short) and what one craft makes. Recipes the party cannot make now are greyed out. OK asks how many (up/down 1, left/right 10), OK again makes them with a sound (the setting, else the chest sound). The mouse works as on the other screens.

**Unknown recipes:** a recipe is known once the party has held every ingredient (equipment worn counts) or has made it before. Until then it is shown as `??????`, greyed out with its name, left out, or shown like the others (a setting). Ingredients never held show as `??????` too.

**Settings:** the menu entry (on/off, label), unknown recipes, the sound, the most made at once.

**Command:** *Open crafting* (categories, empty for all).

**Saved with the game:** section `crafting` `{crafted: {"items:id": count}, seen: {"items:id": true}}`.
