# Rule systems

Stats, resources, damage formulas and battle maths are not built into the kit. They come from a **rule system**: a folder `rpg/rules/<name>/` with a `rules.json` (and, optionally, a `rules.gd` for anything JSON can't say). Every Database form, the menus and the battle read their stats from it.

## The rule systems you get

| Rule system | Stats | Resources | In short |
| --- | --- | --- | --- |
| **Classic** (`classic`, the default) | Max HP, Max SP, STR, DEX, AGI, INT, Attack, Physical and Magic Defense | HP, SP | RPG Maker XP style. Hit then evasion from AGI and DEX, a damage formula per skill, an EXP curve per class, escape from the party's AGI against the enemies' |
| **VX Ace style** (`vx_ace`) | MHP, MMP, ATK, DEF, MAT, MDF, AGI, LUK | HP, MP, TP (0–100) | As in RPG Maker VX Ace: class parameter curves from level 1 to 99, damage formulas such as `a.atk * 4 - b.def * 2` with 20% variance and ×3 criticals, HIT/EVA/CRI, the basis/extra/acceleration EXP curve, and Features |
| **OSR example** (`osr_example`, in the sample project) | STR, DEX, CON, INT, WIS, CHA, Max HP, AC, attack bonus | HP | A small old-school example: ability scores, ascending armour class, a d20 to hit, weapon dice for damage, hit dice per level, EXP tables per class |

### VX Ace style: what is covered

- Ace's damage formulas, variance and criticals; HIT, EVA and CRI checks.
- Class parameter curves (level 1 value, level 99 value, a growth shape) with a graph in the Classes tab.
- Features (the kit calls them **Traits**): Element Rate, State Rate, Ex-Parameters, Add/Seal Skill Type, Dual Wield, Seal Equip, Action Times+, HP/MP Regen.
- Actors can use a skill type (Magic, Special) only when their class or actor adds it with an *Add Skill Type* trait, as in Ace.
- Regeneration and each state's damage apply on the map every 20 steps.

Not covered yet: buffs and debuffs, Sp-Parameters other than critical rate, Counter Attack and Magic Reflection, Special Flags, Party Abilities, Fix Equip, Attack State. Action Times+ repeats the same action. Change Class keeps the level (no separate EXP per class). Lowering a level keeps the stats gained on the way up.

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

## Battle speed (ATB and CTB)

ATB gauges and the CTB turn order fill by `atb_speed`: `rules.json` `"atb": {"speed": "<formula>"}`, or else the agility stat (`agi`, or `spd` / `dex` when there is none).

## Capabilities

A battle scene declares what it needs from the rule system (`const CAPABILITIES := [...]`), and so do extensions (`requires_capabilities` in their manifest). The playtest and export checks compare these with the rule system's `capabilities`, so a custom battle that needs, say, turn order doesn't start with rules that lack it.

## Writing your own

Copy a folder in `rpg/rules/`, rename it and its `id`, and edit `rules.json`. The keys are: `stats`, `resources`, `life_resource`, `death_state`, `levels`, `growth`, `exp_curve`, `traits`, `attack`, `hit_check`, `critical`, `damage`, `turn_order`, `escape`, `roll_check` and `capabilities`. The rule system contract is described in [docs/ARCHITECTURE.md](https://github.com/barnstorm/rpgodot_mkr/blob/main/docs/ARCHITECTURE.md#rule-system-contract-runtimerules). The **Roll Check** event command uses the rule system's `roll_check` (a skill check for tabletop-style games).
