@tool
class_name RPGPartyUtil
extends RefCounted
## Helpers shared by party commands: resolve targets and touch battler resources through the rule
## system when one is loaded.


## target: "party" | "leader" | actor id, or in a battle "troop" (every enemy) | "enemy" (one
## member of the troop, 1-based `enemy_index`). Returns Array of [id, battler]; enemies use ["", b].
static func targets(ctx: RPGContext, target: String, enemy_index := 1) -> Array:
	if target == "troop" or target == "enemy":
		return _battle_targets(ctx, target, enemy_index)
	var out := []
	var ids: Array = []
	if target == "party" or target == "":
		ids = ctx.state.party.duplicate()
	elif target == "leader":
		if not ctx.state.party.is_empty():
			ids = [ctx.state.party[0]]
	else:
		ids = [target]
	for id in ids:
		var b: Variant = ctx.state.actor(id)
		if b != null:
			out.append([id, b])
	return out


## Enemy targets of the party commands (Change HP/SP, Change State, Recover All) while a battle
## runs. Outside a battle (or with an enemy number the troop does not have) nothing happens and
## a playtest warning says why; the validator flags both cases when the project is checked.
static func _battle_targets(ctx: RPGContext, target: String, enemy_index: int) -> Array:
	var facade: RPGBattleFacade = ctx.battle
	var core: RPGBattleCore = facade.core() if facade != null else null
	if core == null:
		push_warning("Enemy targets need a running battle; nothing happens.")
		return []
	if target == "troop":
		var all := []
		for e in core.enemies:
			all.append(["", e])
		return all
	if enemy_index < 1 or enemy_index > core.enemies.size():
		push_warning("The enemy group has no enemy #%d; nothing happens." % enemy_index)
		return []
	return [["", core.enemies[enemy_index - 1]]]


static func resource_max(ctx: RPGContext, b: Variant, res: String) -> int:
	var rules: Variant = ctx.rpg.rules
	if rules != null and rules.has_method("max_resource"):
		return int(rules.max_resource(b, res))
	return 9999


static func get_res(b: Variant, res: String) -> int:
	if b is Object and "resources" in b:
		return int(b.resources.get(res, 0))
	if b is Dictionary:
		return int(b.get(res, 0))
	return 0


static func set_res(ctx: RPGContext, b: Variant, res: String, value: int) -> void:
	var v := clampi(value, 0, resource_max(ctx, b, res))
	if b is Object and "resources" in b:
		b.resources[res] = v
	elif b is Dictionary:
		b[res] = v


static func states_of(b: Variant) -> Array:
	if b is Object and "states" in b:
		return b.states
	return []


## "" when `target` ("party", "leader" or an actor id) names something that exists, otherwise an
## error message starting with `label`.
static func check_target(ctx: RPGContext, target: String, label: String) -> String:
	if target == "party" or target == "leader" or target == "":
		return ""
	if not ctx.data.has_record("actors", target):
		return "%s: actor '%s' does not exist." % [label, target]
	return ""


## True when the rule system has `method` taking `argc` arguments (so a rule system that names a
## method differently, or not at all, falls back to the commands' own state changes).
static func rules_has(ctx: RPGContext, method: String, argc: int) -> bool:
	var rules: Variant = ctx.rpg.rules
	if rules == null or not (rules is Object) or not rules.has_method(method):
		return false
	for m in rules.get_method_list():
		if str(m.get("name", "")) == method:
			var n: int = (m.get("args", []) as Array).size()
			var defaults: int = (m.get("default_args", []) as Array).size()
			return argc <= n and argc >= n - defaults
	return false


## Field of a battler that may be an RPGBattler or a plain Dictionary (no rule system).
static func get_field(b: Variant, key: String, fallback: Variant = null) -> Variant:
	if b is Object and key in b:
		return b.get(key)
	if b is Dictionary:
		return b.get(key, fallback)
	return fallback


static func set_field(b: Variant, key: String, value: Variant) -> void:
	if b is Object and key in b:
		b.set(key, value)
	elif b is Dictionary:
		b[key] = value


## Keeps resources inside their (possibly new) maximums after a level/class/equipment change.
static func clamp_after_change(ctx: RPGContext, b: Variant) -> void:
	var rules: Variant = ctx.rpg.rules
	if rules != null and b is RPGBattler and rules.has_method("clamp_resources"):
		rules.clamp_resources(b)


## Shows "X is now level N!" lines in the message box (Change Level / EXP "Show level up").
static func show_level_ups(ctx: RPGContext, b: Variant, ups: Array) -> bool:
	if ups.is_empty() or ctx.ui == null or not ("message_box" in ctx.ui) or ctx.ui.message_box == null:
		return true
	var rules: Variant = ctx.rpg.rules
	var nm := str(get_field(b, "name", ""))
	var lines := []
	for u in ups:
		var lv: int = int(u.get("level", 0)) if u is Dictionary else int(u)
		var text := "%s is now level %d!" % [nm, lv]
		if rules != null and rules.has_method("term"):
			text = str(rules.term("level_up", [nm, lv]))
		lines.append(text)
	var box: Control = ctx.ui.message_box
	box.open_text({"text": "\n".join(PackedStringArray(lines))})
	var r := await ctx.wait_signal(box.closed)
	if not r.ok:
		box.force_close()
		return false
	box.hide_box()
	return true


## Lowers `b`'s level until its experience reaches it, then raises it (with stat gains and
## skills, through the rule system's gain_exp) as far as the experience allows. Returns the
## level-up entries gain_exp reported.
static func sync_level_to_exp(ctx: RPGContext, b: Variant) -> Array:
	var rules: Variant = ctx.rpg.rules
	if not (b is RPGBattler) or rules == null or not rules.has_method("exp_for_level"):
		return []
	while b.level > 1 and b.exp < int(rules.exp_for_level(b.class_id, b.level)):
		b.level -= 1
	var ups: Array = rules.gain_exp(b, 0) if rules.has_method("gain_exp") else []
	clamp_after_change(ctx, b)
	return ups
