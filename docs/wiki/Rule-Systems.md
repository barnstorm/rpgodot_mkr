# Rule systems

Stats, resources, damage formulas and battle maths are not built into the kit. They come from a **rule system**: a folder `rpg/rules/<name>/` with a `rules.json` (and, optionally, a `rules.gd` for anything JSON can't say). Every Database form, the menus and the battle read their stats from it.

## The rule systems you get

| Rule system | Stats | Resources | In short |
| --- | --- | --- | --- |
| **Classic** (`classic`, the default) | Max HP, Max SP, STR, DEX, AGI, INT, Attack, Physical and Magic Defense | HP, SP | RPG Maker XP style. Hit then evasion from AGI and DEX, a damage formula per skill, an EXP curve per class, escape from the party's AGI against the enemies' |
| **VX Ace style** (`vx_ace`) | MHP, MMP, ATK, DEF, MAT, MDF, AGI, LUK | HP, MP, TP (0–100) | As in RPG Maker VX Ace: class parameter curves from level 1 to 99, damage formulas such as `a.atk * 4 - b.def * 2` with 20% variance and ×3 criticals, HIT/EVA/CRI, the basis/extra/acceleration EXP curve, and Features |
| **OSR example** (`osr_example`, in the sample project) | STR, DEX, CON, INT, WIS, CHA, Max HP, AC, attack bonus | HP | A small old-school example: ability scores, ascending armour class, a d20 to hit, weapon dice for damage, hit dice per level, EXP tables per class |

### VX Ace style: what is covered

- Ace's damage formulas, variance and criticals.
- HIT, EVA and CRI checks. As in VX Ace a class starts from *Hit Rate 95%*, *Evasion Rate 5%* and *Critical Rate 4%* (an enemy from 95% and 5%), and every other trait adds to that: a shirt with *Evasion Rate +3%* gives 8%, a Blind state with *Hit Rate -60%* leaves 35%. A class or enemy made with **New** lists the three traits so you can edit them; one that lists none uses the same values. A class or enemy that lists one of them itself uses its own value as the base.
- Class parameter curves (level 1 value, level 99 value, a growth shape) with a graph in the Classes tab.
- Features (the kit calls them **Traits**): Element Rate, State Rate, Ex-Parameters, Sp-Parameters, Attack State, Attack Speed, Add/Seal Skill Type, Add/Seal Skill, Equip Weapon/Armor Type, Dual Wield, Seal Equip, Fix Equip, Action Times+, Special Flags (Auto Battle, Guard, Substitute, Preserve TP), Collapse Effect, HP/MP Regen.
- Party abilities, a trait any member carries for the whole party: Encounter Half, Encounter None, Cancel Surprise, Raise Preemptive, Gold Double, Drop Item Double.
- Actors can use a skill type (Magic, Special) only when their class or actor adds it with an *Add Skill Type* trait, as in Ace.
- Regeneration and each state's damage apply on the map every 20 steps.
- Item and skill **effects** *Gain TP* (flat TP, capped at the maximum) and *Special Effect: Escape* (whoever it hits leaves the battle — an enemy just goes; a whole party escaping ends the fight as an escape).
- MV/MZ **scopes**: *N random enemies* (1-4 picks, each re-rolled from the living), the *(dead or alive)* ally scopes, and *Everyone* (both sides).
- MV **invocation fields**: *Speed* (joins the turn-order roll), *Repeat* (1-9 hits; a random scope re-picks its targets per repeat) and *TP Gain* (charged to the user once per use — not per target or repeat, and even on a miss — through the rules' `gain_on_use`).
- Buffs and debuffs: the *Add Buff* / *Add Debuff* / *Remove Buff* / *Remove Debuff* effects step a stat ±25% per level (two levels max), roll debuff chances against Debuff Rate traits and the user's luck, and wear off after their turns or at battle's end. As in VX Ace the turns count down at the end of each battle turn and the buff goes at the end of the battler's next action after they run out, so *ATK up, 3 turns* covers the caster's next three actions. States set to wear off at the *End of the battler's action* work the same way: a 1-turn state a skill puts on its user lasts until that battler's next action has ended. Classic has none — its halve/double stat changes are states.
- The remaining Ex- and Sp-Parameters: *Counter Attack* answers a physical hit with the target's own attack and *Magic Reflection* sends a magical skill back to its caster (checked per hit, counter first); *Target Rate* weights random enemy picks (0 drops a foe from the draw), *Guard Effect* divides guarded damage, *Recovery Effect* scales healing received (an item's also by the user's *Pharmacology*), and *MP Cost Rate*, *Physical/Magic Damage Rate*, *Floor Damage* rate and *Experience* rate scale their totals.
- The rest of the trait list: *Attack State* rides every normal attack (its chance, times the target's State Rate) and *Attack Speed* joins the attack's turn-order roll; *Add Skill* / *Seal Skill* widen and hole the skill list the menus, battle input and events read; *Equip Weapon/Armor Type* say what an actor can equip, together with the class's **Can equip** lists (the types either one names; a class with no lists and no such trait equips nothing under these rules, and the shop's marks, the Equip menu and Change Equipment all use the one check), which the equipment menu and the Change Equipment command consult. The special flags: *Auto Battle* asks for no command and picks its own (a hurting friend is mended, else the strongest hit — no dice rolled), *Guard* halves damage without a guard command, *Substitute* steps in front of a friend under a quarter of HP ("Bruno covers Eric!"; a certain hit cannot be covered) and *Preserve TP* keeps TP between battles. The *Collapse Effect* picks how a side-view sprite dies: normal fade, boss, instant or none.
- *Seal Equip*, *Dual Wield* and *Fix Equip* count from any source, a weapon or a piece of armour included. A two-handed sword with *Seal Equip: Shield* empties and locks the shield slot: the shield goes back to the bag as the sword is equipped, in the Equip menu and with Change Equipment alike. A weapon with *Dual Wield* turns the shield slot into a second weapon slot while it is worn. Whatever a change leaves unwearable comes off the same way (the second weapon when the Dual Wield piece is removed, the armour whose type a removed piece allowed). A seal from a state leaves the item in place: it stops counting until the state ends. *Fix Equip* greys the slot out in the Equip menu (a cursed ring that fixes its own slot cannot be taken off there); leave its slot blank to fix every slot, as VX's actor option *Fix Equipment*. The Change Equipment command is not held back by it, as in RPG Maker.
- State **restrictions**: *Attack an Enemy* (berserk — a random foe, weighted by Target Rate), *Attack Anyone* (confusion — anyone on the field, itself included), *Attack an Ally* (charm — a random ally, never itself), *Cannot Use Skills* (only the Attack command) and *Cannot Act*. When several apply, the most limiting state wins, MV's ranking. A confused battler asks for no command — a monster skips its action list — and the log names the state ("Eric is driven by Confusion!"); with nobody left to attack, the battler waits out the turn.

Not covered yet: Action Times+ repeats the same action. Change Class keeps the level (no separate EXP per class). Lowering a level keeps the stats gained on the way up.

## Switching

On the Database tab press **Rule system: … ** at the top. The dialog:

1. Lists every stat, resource, formula and command that the switch affects.
2. Writes a backup of the project's data first.
3. Adds the new system's missing stats to records. Nothing is deleted, and old stat **values are kept as they are, not converted** (a Classic `str` of 20 does not become an `atk`).

Switch early in a project, before you have balanced many numbers.

## Formulas

Damage formulas, and the formulas in `rules.json`, use a small, safe expression language (`RPGFormula`). A formula can:

- do arithmetic `+ - * / %` (whole numbers stay whole; division rounds down) and compare `== != < <= > >=`;
- combine with `and`, `or`, `not`, and choose with `if c then x else y` or `c ? x : y`;
- read `a` (the user), `b` (the target), `v` (variables) and `s` (the skill or item used): `a.atk`, `b.mdef`, `v.apples`;
- roll dice (`2d6`) and call `min`, `max`, `clamp`, `abs`, `floor`, `ceil`, `round`, `roll`, `rand`, `stat`, `resource` and `has_state`.

It can't call methods or run other code, so a formula can't break the game or the editor. A formula with a mistake reports what is wrong; it never quietly gives 0.

The **Formula** condition kind (pages and Conditional Branch) evaluates a formula with `a` and `b` empty and `v` the project's variables: `v.apples >= 3` is "the party has picked at least 3 apples". A `true` result or any non-zero number passes.

## Battle speed (ATB and CTB)

ATB gauges and the CTB turn order fill by `atb_speed`: `rules.json` `"atb": {"speed": "<formula>"}`, or else the agility stat (`agi`, or `spd` / `dex` when there is none).

## Capabilities

A battle scene declares what it needs from the rule system (`const CAPABILITIES := [...]`), and so do extensions (`requires_capabilities` in their manifest). The playtest and export checks compare these with the rule system's `capabilities`, so a custom battle that needs, say, turn order doesn't start with rules that lack it.

## Writing your own

Copy a folder in `rpg/rules/`, rename it and its `id`, and edit `rules.json`. The keys are: `stats`, `resources`, `life_resource`, `death_state`, `levels`, `growth`, `exp_curve`, `traits`, `buffs`, `attack`, `hit_check`, `critical`, `damage`, `turn_order`, `escape`, `roll_check` and `capabilities`. The rule system contract is described in [docs/ARCHITECTURE.md](https://github.com/barnstorm/rpgodot_mkr/blob/main/docs/ARCHITECTURE.md#rule-system-contract-runtimerules). The **Roll Check** event command uses the rule system's `roll_check` (a skill check for tabletop-style games). A `buffs` block (`params`, `step`, `max_levels`, `luck_stat`) turns the buff effects on; without one they do nothing. A `rows` block (`back_attack`, `back_defence` — 1.0 each by default) scales physical damage dealt and taken from the back row when an actor's battle commands include *Row*. `variable_division` says how **Control Variable** divides whole numbers: `"truncate"` (the default, RPG Maker 2000/2003) cuts towards zero and the remainder keeps the variable's sign, `"floor"` (VX Ace) rounds down and the remainder takes the divisor's sign. `class_equip_default` says what a class record with no **Can equip** entry at all may equip: `"any"` (the default, the Classic rules) or `"none"` (VX Ace: only the types that *Equip Weapon/Armor Type* traits name). A class that has the entry allows the types its lists name under every rule set, and the traits add to them. `state_countdown` says when the turns of states and buffs count down: `"own_timing"` (the default) counts a state at its own timing, the end of the turn or the end of its battler's action, and removes it at 0, with buffs wearing off at the end of the turn; `"turn_end"` (VX Ace, MV) counts everything down at the end of the turn and removes Action End states and buffs at the end of the battler's next action once they are at 0. `recover_revives` says whether restoring HP raises a fallen target: `true` (VX Ace, MV) for any skill or item whose target is a dead ally, `false` (the default, RPG Maker 2000/2003) leaves that to *Remove State*. `turn_repeat` says how a repeating battle turn condition (*Turn a, then every b*) treats the battle's opening, turn 0: `"from_start"` (the default, RPG Maker 2000/2003) lets it match there, `"from_first_turn"` (VX Ace, MV) never does.
