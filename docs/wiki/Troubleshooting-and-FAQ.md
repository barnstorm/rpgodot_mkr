# Troubleshooting and FAQ

## Setting up

**The RPG and Database tabs don't appear.**
Open *Project > Project Settings > Plugins* and tick **RPG Kit**. It turns on the Database plugin by itself. If it's ticked and still missing, look at Godot's *Output* panel for a script error, and check that `addons/rpg/` and `addons/rpg_database/` are both in the project, at those exact paths.

**Godot's docks disappeared.**
That is **Maker view**: while you are on the RPG or Database tab, Godot's own docks are hidden. Switch to *2D* or *Script* to get them back, or turn Maker view off in *Project > Maker view* on the RPG tab.

**Playtest says "No main scene".**
*Create RPG project* sets the kit's game scene as the main scene when there is none. If your project already had a main scene, set *Project Settings > Application > Run > Main Scene* to `res://addons/rpg/runtime/game.tscn` (or start the game from your own scene).

**Which Godot version?**
4.5.1. Earlier versions aren't tested; the test runner needs 4.5.

## Maps

**I can walk through walls (or can't walk on the floor).**
Turn on *Overlays > Passability* to see what the tileset says, then fix the tiles with **Tiles** ([Lesson 1](Lesson-1-Your-First-Map.md#5-check-where-the-player-can-walk)). Imported VX/Ace tilesets start with guessed settings. In a playtest, holding **Ctrl** walks through walls on purpose.

**My tree is drawn under the player / over the player's head.**
That is the **Star** flag in the tile settings: a star tile is drawn above characters.

**Autotiles don't join up.**
Hold **Shift** while painting to place an autotile *without* joining it to its neighbours; without Shift they join.

## Events

**My event does nothing.**
In a playtest, face it and press **F9**. The debug screen's *Events* page shows the event's pages and **which condition keeps each page off**. Also check the trigger: *Action button* needs the player to face it and press OK; with *Same as characters* priority, the player can't stand on it.

**My autorun event repeats forever and the player is stuck.**
An autorun page runs again as long as it is active. End it with **Control Self Switch** A = ON and a second page with the condition *Self switch A* ([Lesson 5](Lesson-5-Cutscenes-and-Common-Events.md#1-an-autorun-event)).

**A command shows a warning sign.**
It has a mistake (a missing reference, an empty required field) or belongs to an extension that is off. Open it to see what's wrong, or press **Check** in the event editor.

**I renamed a switch and now the events are broken.**
Rename with **Rename ID…** on the Database tab: it updates every reference. Editing the ID in a JSON file by hand doesn't.

## Battles

**Battle test does nothing.**
Save the Database first. Battle test runs the game in a separate window, which reads the saved files.

**The side-view party is drawn as walk sprites.**
That's what happens when an actor has no *Side-view battler*. Import an MV `sv_actors` sheet or a 2003 BattleCharSet you own and pick it on the Actors tab.

## Sound

**MIDI music sounds different on another computer.**
The sound bank is probably missing there (for example `gm.dls` on Linux), so the built-in instruments were used. Use an SF2 soundfont with **Copy into project**, then **Re-render all MIDI** ([MIDI music](MIDI-Music.md)).

**MIDI files take a while to import.**
Each song is rendered to audio once, a few seconds per song. After that it's an ordinary audio file.

## Building

**The Build button on Tools > Deploy is greyed out.**
There is no export preset yet. In Godot open *Project > Export…*, press **Add…**, choose a platform, and install the export templates if Godot asks ([Lesson 8](Lesson-8-Playtest-Debug-and-Share.md#5-build-the-game)).

**The build is blocked.**
The export checks found errors. They are listed on the Deploy page; double-click one to jump to it.

**F9 and Ctrl walk-through don't work in my exported game.**
They are playtest-only and turned off in release builds, on purpose.

## Licences

**Can I sell a game made with the kit?**
The kit's code is MIT and the starter art and sounds are CC0, so yes, as far as the kit is concerned. Anything you import (RPG Maker RTPs, music rendered with Windows' `gm.dls`, third-party soundfonts) has its own terms: check them.

**Is RPG Maker art included?**
No. The repository has no RPG Maker files. You import art from RPG Maker you own, into your own project.
