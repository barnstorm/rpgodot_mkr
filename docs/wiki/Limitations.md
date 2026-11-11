# Limitations

What the kit doesn't do yet, and what hasn't been verified. This list is kept honest on purpose: if something here matters to your game, plan around it or help fix it.

## Not built

- **Character generator** (RPG Maker's face and sprite builder).
- **An *Enemy Appear* command.** An enemy group member marked *Appears later* can't be brought into the battle yet, so it stays hidden.
- **Animation timeline editor.** Battle animations are a sprite sheet with flashes and sounds, or one of the built-in effects (slash, fire, ice, thunder, heal, hit).
- **Converting RPG Maker projects.** The importer copies art and sound; maps, events and databases are not converted.

## Battles

- **Front view draws no actors**, as in RPG Maker 2000 and VX Ace.
- **Side view**: weapon sprites (2003 BattleWeapon, MV weapons) are not drawn. A party mixing sources (MV sheets, 2003 BattleCharSets, walk sprites) is drawn at the tallest figure's height.
- **Preemptive and surprise** rates are a simple form of MV's; traits that change them (Raise Preemptive, Cancel Surprise) are not read.
- **ATB** has no *Auto* party command.
- **VX Ace style rules** don't cover buffs and debuffs, most Sp-Parameters, Counter Attack, Magic Reflection, Special Flags, Party Abilities, Fix Equip or Attack State. Action Times+ repeats the same action. Change Class keeps the level. Lowering a level keeps the stats gained.

## Screens

- **Larger screens**: VX/Ace (544×416) and MV (816×624) projects fill the screen with the map, but the menus, messages and battle screen are laid out for 320×240 and scaled up.
- With menu icons on, some long main-menu labels are cut short.

## Tiles and import

- **RPG Maker 2000/2003 ChipSets** were decoded from public descriptions and tested with the kit's own sheets and the official RTPs. An unusual third-party ChipSet may still show a layout mistake; per-tile overrides in **Tiles** can fix passability.
- **VX/Ace A2 table legs** are not decoded.
- **VX/Ace passability** isn't read (it is in a binary database): check imported tilesets in **Tiles**. An XP RTP (not a project) has no database, so its autotiles are only paired where the file names make it clear.
- **MZ** has not been tried on real files.

## Plugins

- **Lighting**: lights shine through walls (no shadows).
- **Quests**: objectives are done or not done; there are no counted objectives ("3 / 5 wolves").
- **Letter sounds** were checked by measurement, not yet listened to by a person.

## Sound

- **MIDI** is rendered once at import, with a General MIDI bank. Chorus, the bank's filters and LFOs are not rendered, and pan is applied per note. Pitch changes speed too (unlike RPG Maker's MIDI tempo).

## Not verified by hand

- A **physical gamepad** (the mapping was tested with simulated input), and **full screen** on real monitors.
- Some editor parts have only been tested automatically and with scripted screenshots, not by a person: the Classes, Armour, States, Animations, Tilesets, Common events and Types tabs, and the import dialog.
- **macOS and Linux** editors: the kit is pure GDScript and the tests are system-independent, but it has been used mostly on Windows.

## Two tabs, one project

The RPG and Database tabs each keep a copy of the project data. Each re-reads changed files when shown, and saves merge new switches, variables and System fields. If a tab has unsaved changes when the other tab saves the same file, it tells you and you choose with **Reload**; it doesn't merge field by field.
