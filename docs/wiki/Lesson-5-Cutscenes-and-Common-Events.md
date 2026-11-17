# Lesson 5: Cutscenes and common events

In this lesson you make the game's opening scene: a guard walks up to the hero, a balloon pops over the hero's head, and they talk. Then you make a **common event**, a list of commands you can use from anywhere.

## 1. An autorun event

A cutscene is usually an event with the trigger **Autorun**. It starts as soon as its page is active, and the player can't move until it ends.

1. On the starting map, make an invisible event (no graphic) anywhere, ID `intro`.
2. Trigger: **Autorun**.
3. Commands:

   ```
   ◆ Set Move Route: guard  (↑ Up, ↑ Up, ↑ Up, Turn Left)  [Wait until done]
   ◆ Show Balloon Icon: player, exclamation
   ◆ Text: Guard: You there! The captain wants to see you.
   ◆ Text: \N[hero]: Me? What did I do?
   ◆ Control Self Switch: A = ON
   ```

4. Add **page 2** with the condition *Self switch A is ON*, no commands and trigger *Action button*.

**Why page 2?** Autorun repeats for as long as its page is active. Without a way out, the scene would play forever. Turning self switch A ON makes page 2 the active page, and page 2 does nothing. (*Erase Event* also stops it, but only until the player leaves the map.)

## 2. Move routes

**Set Move Route** moves a character: `player`, `this` event or any event by its ID. Build the route with the buttons:

- **Move**: the eight directions, forward, backward, random, toward or away from the player.
- **Turn**: the four directions, 90° left or right, around, random, toward or away from the player.
- **Other**: jump, wait, speed, frequency, graphic, opacity, switch ON/OFF, sound, walking and stepping animation, direction fix, walk through, hide and show.

Options: **Repeat**, **Skip if blocked**, and **Wait until done** (the event waits before the next command). With *Skip if blocked* off, a step whose way is blocked waits for the way to clear, however long that takes — the debug screen shows where a character is waiting. Press **Preview** to watch the route drawn on the map in the editor.

An event's page can have a **Custom route** as its movement too, for guards who patrol — or a *Vertical* / *Horizontal* movement type, when a simple up-and-down patrol is all a guard needs.

A forced route takes over: while it plays, the character's own movement (random, approach, a custom route) is paused, and a custom route resumes where it left off when the forced route ends. If the event's page changes mid-route, the VX Ace style [rule system](Rule-Systems.md) cancels the forced route, as MV does; the classic rules keep it, and a custom route restarts from its first step unless both pages use the same route.

## 3. Screen effects

| Command | What it does |
| --- | --- |
| Fade Out Screen / Fade In Screen | Fades to black and back |
| Tint Screen | Colours the whole screen (red, green, blue %) over some seconds: dusk, night, a flashback |
| Flash Screen | A quick flash (lightning, a hit) |
| Shake Screen | Shakes the screen (an earthquake) |
| Set Weather Effects | None, rain or snow, with a power |
| Show / Move / Erase Picture | Pictures over the map: a letter, a portrait, a title card |
| Scroll Map | Moves the camera away from the player and back |
| Show Animation | A battle animation on a character (a spell on the map) |
| Show Balloon Icon | `!`, `?`, a note, a heart, anger, sweat, frustration, silence, a light bulb, Zzz |
| Wait | Waits some seconds |

Most of them have **Wait until done** (Show Animation calls it *Wait for completion*, and it is off by default).

## 4. Parallel events

An event with the trigger **Parallel** runs over and over in the background while the player moves. Use it for things that keep happening:

```
Parallel event "waves"
◆ Play SE: (a wave sound)
◆ Wait: 4.0
```

A parallel event shouldn't stop the player; avoid messages in it.

While the menu, a shop, the save screen or a battle is open, parallel events and wandering NPCs sleep, and a Wait picks up where it left off when the screen closes — the map is suspended behind those screens, as in RPG Maker. Message boxes don't suspend it. (The Run Scene command can turn this off for an overlay scene, like a HUD, that runs on top of the live map.)

## 5. Common events

A **common event** is a command list that belongs to the whole game, not to a map. Make them on the Database's **Common events** tab.

![Database > Common events](images/editor_db_common_events.png)

Each one has a **Name**, its commands, and a **Trigger**:

| Trigger | Runs… |
| --- | --- |
| None | only when called with **Call Common Event**, or used by an item or skill |
| Autorun | while its **Condition switch** is ON, like an autorun event on every map |
| Parallel | in the background while its **Condition switch** is ON, on every map |

Example: a `full_heal` common event

```
◆ Play SE: heal
◆ Recover All: whole party
◆ Text: Your party feels refreshed!
```

Now any event can do `◆ Call Common Event: full_heal`. An item can run one too (Lesson 6): a *Tent* that calls `full_heal`.

### Engine moments

The Trigger list has a third kind: **engine moments**. Instead of polling in a Parallel event, a common event can simply *be* the reaction to something the engine already knows: the moment happens, the common event runs. No switches, no waiting loops.

| Moment | Runs when… |
| --- | --- |
| New game starts | a new game begins (before the first map's intro events) |
| A game is loaded | a save file finishes loading |
| Entering / leaving a map | the player arrives on a map / leaves one — *Only map* narrows it to one map |
| Every N steps | each Nth step of the player (set *N* in *Every N steps*) |
| Entering / leaving a region | the player steps into / out of a region painted on the RPG tab's Regions — *Region* narrows it to one |
| Entering a terrain | the player steps onto a terrain tag — *Terrain* narrows it to one |
| An actor levels up | right after the level-up message — *Only actor* narrows it to one |
| A state is added / removed | an actor gains or loses a state — *Only state* and *Only actor* narrow it |
| An actor is knocked out | the actor falls (battle defeat, map HP-to-zero, poison slip damage) |
| A battle starts / ends | before the scene opens, and after the outcome — *Only outcome* (victory, escape, defeat) narrows the end |
| Game over | before the Game Over screen, while the world is still up |
| Menu opened / closed | the menu comes up / goes away |
| The party changes | an actor joins or leaves |
| Boarding / leaving a vehicle | the player gets on / off — *Only vehicle* narrows it |

Each moment has a **Condition switch** too, like the classic triggers. The moment's own data — which actor, which region, which map, the outcome — is readable in the event's commands under **Game Data** as `hook.*`: `hook.actor`, `hook.state`, `hook.region`, `hook.terrain`, `hook.map`, `hook.outcome`, `hook.vehicle`, `hook.x`, `hook.y`, `hook.old_level` / `hook.new_level`.

A common event hooked to a moment queues like a called event: several moments happening at once run in order, and a moment that repeats quickly (steps) waits for the running pass instead of piling up.

To react to *several* moments with one common event, open `rpg/common_events.json` and set its `trigger` to a list, for example `["on_step", "on_region_enter"]`.

Example: a poison swampland. Paint region 4 over the marsh on the RPG tab's Regions, then make a common event with Trigger *Moment: enter a region*, *Region* 4:

```
◆ Text: The marsh air burns your lungs…
◆ Change HP: entire party, −5
◆ Play SE: poison
```

## 6. Moving between maps in a cutscene

**Transfer Player** with *Fade* set moves the player and fades on the way. To take other characters along, give them the same story switch as a page condition on the new map, or place them with **Set Event Location**.

## Try it yourself

- Make the guard walk *with* the player to the castle: **Set Move Route** for both, without *Wait until done* on the first so they move together.
- Start a rainstorm when the player enters the forest: a common event with Trigger *Moment: enter a map* and *Only map* the forest, that runs `Set Weather Effects: rain`. (The classic way still works: a Parallel event with a Condition switch, plus **Erase Event**.)
- Show the map's name differently: **Change Map Name Display** turns the name box on and off.

Next: [Lesson 6: The database](Lesson-6-The-Database.md).
