class_name RPGBattleCore
extends RefCounted
## Turn-based battle logic without any UI. A battle scene drives it:
##
##   var core := RPGBattleCore.new(party, troop_record, rules, rng)
##   core.start()
##   while core.battle_over() == "":
##       core.begin_turn()                       # emits checkpoint("start_of_turn")
##       for i in core.inputs_needed(): core.set_action(i, {...})
##       var r := core.next_action()             # emits checkpoint("after_action")
##       while not r.is_empty(): show(r); r = core.next_action()
##       core.end_turn()                         # emits checkpoint("end_of_turn")
##   "after_change" is emitted before "after_action" / "end_of_turn" when any battler's HP or
##   states changed.
##   core.rewards()
##
## Battle events: connect to `checkpoint`, call eligible_battle_pages(kind) and run the
## returned pages' commands (the battle waits while they run).
## Troop members marked "hidden" ("Appears later") stay out of the battle until appear(index)
## brings them in (the Enemy Appear command).
##
## Actions: {kind: "attack"|"skill"|"item"|"guard"|"escape"|"wait", skill?, item?, target?}
## `target` is an index into the opposing side (enemy scopes) or the user's side (ally
## scopes); -1 or an invalid/dead target picks one automatically.
##
## Time-based battles (battle_system "atb" or "ctb", set before start()):
##
##   core.battle_system = "atb"
##   core.start()
##   core.begin_turn()                            # turn 1; emits checkpoint("start_of_turn")
##   while core.battle_over() == "":
##       var b := core.next_auto_ready()          # a full enemy, or an actor with its action set
##       if b == null and core.next_input_actor() != null:
##           core.set_action(core.party.find(core.next_input_actor()), {...})   # the player picks
##           continue
##       if b == null:
##           core.atb_advance(delta)               # ATB: real time; CTB: core.atb_advance_to_next()
##           continue
##       var r := core.act(b)                      # like next_action(); also ticks b's states
##       if r.get("turn_end", false): core.begin_turn()
##
## Gauges fill at a rate proportional to rules.atb_speed(b) (agility by default) over the battle's
## average, so an average battler fills in ATB_FILL_SECONDS. A battler that cannot act (a state
## with "cannot_act") still fills and loses that turn, so its states wear off as usual.
## Turn counter (troop page and enemy "turn" conditions): a battle turn ends when every battler
## that was active when it began has taken one turn (acted, or lost it to a state or a failed
## escape); "end_of_turn" is emitted then, and begin_turn() starts the next one. State durations
## and slip damage count each battler's own turns.
##
## Extension hooks (docs/ARCHITECTURE.md "Battle hooks"): with `hooks` set (the battle scene sets
## the RPG service) the core reports through hooks.battle_hook(name, args, mode):
##   turn_started(battler)                      a battler's action comes up (each extra action too)
##   action_chosen(user, action, targets)       before it runs; handlers may change the action or
##                                              the targets, or cancel it (mode "action")
##   damage_calculated(user, target, action, value)  each damage roll; a handler may return a new
##                                              value (mode "value", through rules.damage_filter)
##   state_changed(battler, state_id, added)    after actions, state ticks and report_changes()
##   battler_defeated(battler)                  a battler was knocked out
## None of them draws from the RNG, so a seeded battle plays the same with or without handlers
## that change nothing. Troop page conditions of other kinds go to `condition_reader`.

signal checkpoint(kind: String)

## Transform (2003): a member became another enemy record. `old_battler`'s slot, position and
## suffix are now `new_battler`'s; the battle scene rebuilds its sprite.
signal enemy_transformed(old_battler: RPGBattler, new_battler: RPGBattler)

## "turn" (everyone picks, then everyone acts in speed order), "atb" (time gauges fill by
## agility; a full battler acts) or "ctb" (the same gauges, but time jumps straight to the next
## full battler and never runs while a command is chosen, so the order can be shown ahead).
const BATTLE_SYSTEMS := ["turn", "atb", "ctb"]
## Seconds an average-speed battler needs to fill its gauge.
const ATB_FILL_SECONDS := 3.0
## Every gauge starts here plus a random offset of up to ATB_START_SPREAD.
const ATB_START := 0.25
const ATB_START_SPREAD := 0.1

var battle_system := "turn"
## ATB only: "wait" (time stops while a command window is open) or "active". The core only
## records it; the scene decides when to call atb_advance().
var atb_mode := "wait"
## "normal", "preemptive" (the party gets the first move) or "surprise" (the enemies do), or the
## RPG Maker 2003 battle starts (#39): "initiative" and "surround" (party gauges full, enemies
## empty), "back_attack" and "pincer" (enemy gauges full, party empty; a pincer also blocks
## escaping). The scene adds the formations: a back attack mirrors the enemies, a surround packs
## them around the middle, a pincer splits them half and half.
var advantage := "normal"
## The 2003 battle starts, in the order their chances are rolled (encounter_condition).
const START_CONDITIONS := ["initiative", "back_attack", "surround", "pincer"]
## Timed battles: RPGBattler -> gauge 0..1.
var gauges := {}
## Timed battles: battlers whose gauge is full, in the order they filled.
var ready_queue: Array = []

var rules: RPGRuleSystem
var rng: RPGRandom
var troop := {}
var party: Array = []          ## RPGBattler (actors)
var enemies: Array = []        ## RPGBattler (troop members, index = member index)
var turn := 0
var phase := "idle"            ## idle, input, actions, turn_end, over
var can_escape := true
var escape_attempts := 0

## Called with (item_id) when an actor uses an item; return false if none is left.
## Unset: items are not tracked.
var item_consumer: Callable
## Called with (switch_id) -> bool for battle page "switch" conditions.
var switch_reader: Callable
## Called with (switch_id, value) when an enemy action with "switch_on" / "switch_off" runs
## (2003: "turn switch ON/OFF when used"). Unset: the toggles are skipped.
var switch_setter: Callable
## Called with (condition) -> bool for troop page condition kinds the core does not know
## (extension kinds marked "battle": true, see the battle scene). Unset: such a page never runs.
var condition_reader: Callable
## Called with (item_id) to give back an item whose action a hook cancelled or replaced.
var item_refund: Callable
## Called with a Dictionary of Game Data "last used" values ({item, skill, actor, target_actor,
## target_enemy}; only the keys the action fills) after each action that really happens. Wired by
## the battle scene to the game state. Unset: nothing is recorded.
var last_used_recorder: Callable
## The object battle hooks are reported to (has battle_hook(name, args, mode) -> {args, cancel}),
## normally the RPG service. Null: no hooks.
var hooks: Object = null

var _queue: Array = []
var _queue_built := false
var _result := ""
var _rewards := {}
var _page_runs := {}           ## page id -> turn it last ran
var _speeds := {}              ## timed: battler -> rules.atb_speed (refreshed after each turn)
var _atb_base := 1.0           ## timed: average speed at battle start
var _acted := {}               ## timed: battlers that took their turn in this battle turn
var _turn_members: Array = []  ## timed: battlers active when this battle turn began
var _extra := {}               ## timed: battler -> extra actions left ("action_times" traits)
var _known_states := {}        ## hooks: battler -> state ids last reported
var _defeated := {}            ## hooks: battlers reported as defeated (until revived)
var _charged := {}             ## Charge Up: enemy -> damage multiplier waiting for its next attack
var _forced_next := {}         ## battler -> action a battle event forced for its next turn
var _last_target := {}         ## battler -> the first target of its most recent action
var _used_commands := {}       ## actor id -> [{kind, skill}] used this battle turn (command_used)
var _forced := false          ## the result came from force_result()
var _last_action_targets: Array = []  ## targets of the most recently executed action


func _init(p_party: Array = [], p_troop: Dictionary = {}, p_rules: RPGRuleSystem = null, p_rng: RPGRandom = null) -> void:
	party = p_party.duplicate()
	troop = p_troop
	rules = p_rules
	rng = p_rng if p_rng != null else RPGRandom.new()
	if rules != null:
		rules.rng = rng


## Creates the enemies from the troop and resets battle state.
func start() -> void:
	enemies.clear()
	var members: Array = troop.get("members", [])
	var counts := {}
	for m in members:
		counts[m.get("enemy", "")] = int(counts.get(m.get("enemy", ""), 0)) + 1
	var seen := {}
	var rolled_out: Array = []
	for i in members.size():
		var m: Dictionary = members[i]
		var b := rules.new_enemy_battler(str(m.get("enemy", "")))
		if b == null:
			continue
		b.index = i
		var pos: Variant = m.get("position", [0, 0])
		if pos is Array and pos.size() >= 2:
			b.screen_position = Vector2(pos[0], pos[1])
		b.hidden = bool(m.get("hidden", false))
		# Random appearance (RM2003): a member below its Appear % misses this fight. It behaves
		# exactly like "Appears later", so Enemy Appear can still bring it in (#41).
		if not b.hidden:
			var chance := clampf(float(m.get("appear_chance", 100)), 0.0, 100.0)
			if chance < 100.0 and not rng.chance_percent(chance):
				b.hidden = true
				rolled_out.append(b)
		# "Slime A", "Slime B" when an enemy appears more than once.
		if int(counts[b.id]) > 1:
			var n := int(seen.get(b.id, 0))
			seen[b.id] = n + 1
			b.name = "%s %s" % [b.name, char(65 + n % 26)]
		enemies.append(b)
	# At least one member always fights: if every rollable member missed its chance, the first
	# one that missed is brought back (troops that hide every member on purpose keep them).
	if not rolled_out.is_empty() and not enemies.any(func(e): return not e.hidden):
		rolled_out[0].hidden = false
	for i in party.size():
		var a: RPGBattler = party[i]
		a.index = i
		a.guarding = false
		a.action = {}
		a.escaped = false
	# Rule-system battle setup (e.g. starting TP).
	for b in all_battlers():
		rules.start_battle(b)
	can_escape = bool(troop.get("can_escape", true))
	# A pincer attack cannot be escaped (2003); Force Flee still ends the fight, by design.
	if advantage == "pincer":
		can_escape = false
	turn = 0
	escape_attempts = 0
	phase = "idle"
	_result = ""
	_forced = false
	_rewards = {}
	_last_action_targets.clear()
	_page_runs.clear()
	_queue.clear()
	_queue_built = false
	if not BATTLE_SYSTEMS.has(battle_system):
		battle_system = "turn"
	gauges.clear()
	ready_queue.clear()
	_speeds.clear()
	_acted.clear()
	_turn_members.clear()
	_extra.clear()
	_known_states.clear()
	_defeated.clear()
	_forced_next.clear()
	_last_target.clear()
	for b in all_battlers():
		_known_states[b] = b.state_ids()
		if b.is_dead():
			_defeated[b] = true
	if is_timed():
		_atb_setup()


func all_battlers() -> Array:
	return party + enemies


func active_party() -> Array:
	return party.filter(func(b): return b.is_active())


func active_enemies() -> Array:
	return enemies.filter(func(b): return b.is_active())


# --------------------------------------------------------------------------------------------
# Turn loop
# --------------------------------------------------------------------------------------------

func begin_turn() -> void:
	if battle_over() != "":
		return
	turn += 1
	phase = "input"
	_used_commands.clear()   # command_used conditions only see the current battle turn
	if is_timed():
		# Timed battles: nobody's action or guard is reset here (that happens per battler, when
		# its gauge fills); only the turn counter moves on.
		_acted.clear()
		_turn_members = all_battlers().filter(func(b): return b.is_active())
		checkpoint.emit("start_of_turn")
		return
	for b in all_battlers():
		b.guarding = false
		b.action = {}
	_queue.clear()
	_queue_built = false
	checkpoint.emit("start_of_turn")


## Party indices that need an action this turn.
func inputs_needed() -> Array:
	var out := []
	if is_timed() or (turn == 1 and advantage in ["surprise", "back_attack", "pincer"]):
		return out
	for i in party.size():
		var b: RPGBattler = party[i]
		if b.is_active() and rules.can_act(b) and not _forced_next.has(b) and not _auto_battle(b) \
				and not _confused(b):
			out.append(i)
	return out


## Stores an actor's action. Returns false if the action is not allowed.
func set_action(actor_index: int, action: Dictionary) -> bool:
	if actor_index < 0 or actor_index >= party.size():
		return false
	var b: RPGBattler = party[actor_index]
	if not b.is_active() or not rules.can_act(b):
		return false
	if is_timed() and not ready_queue.has(b):
		return false
	var kind := str(action.get("kind", ""))
	match kind:
		"attack", "guard", "wait":
			pass
		"escape":
			if not can_escape:
				return false
		"skill":
			if not rules.known_skills(b).has(str(action.get("skill", ""))) or not rules.can_use(b, action):
				return false
		"item":
			if rules.resolve_action(b, action).is_empty():
				return false
		_:
			return false
	b.action = action.duplicate(true)
	return true


## Battle-event forced action (Force Action). With timing "now" the battler performs the
## action at once (outside the turn order; its own pending action is kept) and the result of
## _execute() comes back — {} when it could not act. With timing "turn" the action is stored
## for the battler's next turn and true comes back. A battler that cannot act (dead, hidden,
## restricted) is skipped quietly.
func force(b: RPGBattler, action: Dictionary, timing := "now") -> Variant:
	if b == null or battle_over() != "" or not b.is_active() or not rules.can_act(b):
		return {} if timing == "now" else false
	if timing == "turn":
		_forced_next[b] = action.duplicate(true)
		return true
	var keep := b.action
	b.action = action.duplicate(true)
	var res := _execute(b, _forced_targets(b, b.action))
	b.action = keep
	report_changes()
	res.battle_over = battle_over()
	return res


## Targets a forced action uses: "last" is the first target of the battler's most recent
## action (when it is still on the field). "index" and "random" fall back to the usual scope
## resolution (the action's target index, or a random pick at -1).
func _forced_targets(b: RPGBattler, action: Dictionary) -> Variant:
	if str(action.get("target_mode", "last")) == "last":
		var t: RPGBattler = _last_target.get(b)
		if t != null and t.is_active():
			return [t]
	return null


## Executes the next action of the turn and returns a result for the UI:
## {user, action, kind, name, targets: [RPGBattler], effects: [{target, result}],
##  lines: [String], text, escaped, battle_over}
## Returns {} when every battler has acted (then call end_turn()).
func next_action() -> Dictionary:
	if battle_over() != "":
		phase = "over"
		return {}
	if not _queue_built:
		_build_queue()
	phase = "actions"
	while not _queue.is_empty():
		var b: RPGBattler = _queue.pop_front()
		if not b.is_active() or not rules.can_act(b):
			_forced_next.erase(b)
			continue
		var before := _vitals()
		_hook("turn_started", [b])
		var given: Variant = null
		if _forced_next.has(b):
			b.action = _forced_next[b]
			given = _forced_targets(b, b.action)
			_forced_next.erase(b)
		var result := _execute(b, given)
		# States set to wear off at the battler's action end tick right here (MV's Action End),
		# with the action's result for the UI; the rest wait for end_turn().
		var tick := rules.tick_states(b, "action_end")
		if not tick.lines.is_empty():
			tick.battler = b
			result["ticks"] = [tick]
		_note_command(b, result)
		report_changes()
		if _vitals() != before:
			checkpoint.emit("after_change")
		checkpoint.emit("after_action")
		result.battle_over = battle_over()
		return result
	phase = "turn_end"
	return {}


## Life resource and states of every battler, to detect the "after an HP or state change"
## checkpoint (spec: Event execution semantics, battle events).
func _vitals() -> Array:
	var out := []
	for b in all_battlers():
		out.append([b.get_resource(b.life_resource), b.state_ids()])
	return out


## End-of-turn state processing. Returns [{battler, damage, removed_states, lines}] for
## battlers something happened to.
func end_turn() -> Array:
	if is_timed():
		return []      # timed battles tick each battler's states after its own turn (act())
	var before := _vitals()
	var out := []
	for b in all_battlers():
		if not b.is_active():
			continue
		b.turns_taken += 1   # one battle turn = one of the battler's own turns (#11)
		var r := rules.tick_states(b)
		if not r.lines.is_empty():
			r.battler = b
			out.append(r)
	report_changes()
	if _vitals() != before:
		checkpoint.emit("after_change")
	checkpoint.emit("end_of_turn")
	phase = "over" if battle_over() != "" else "idle"
	return out


## Party-command escape (outside the action queue). {success, chance, lines}
func attempt_escape() -> Dictionary:
	if not can_escape:
		return {"success": false, "chance": 0, "lines": [rules.term("no_escape")]}
	var chance := rules.escape_chance(party, enemies)
	escape_attempts += 1
	if rng.chance_percent(chance):
		_result = "escape"
		for b in active_party():
			b.escaped = true
		return {"success": true, "chance": chance, "lines": [rules.term("escape")]}
	return {"success": false, "chance": chance, "lines": [rules.term("escape_fail")]}


func _build_queue() -> void:
	# A preemptive strike or a surprise attack: the other side does nothing on turn 1. The 2003
	# starts join them: initiative / surround play like a preemptive strike, a back attack and a
	# pincer like a surprise attack.
	var enemies_act := not (turn == 1 and advantage in ["preemptive", "initiative", "surround"])
	var party_acts := not (turn == 1 and advantage in ["surprise", "back_attack", "pincer"])
	if enemies_act:
		for e in enemies:
			if _forced_next.has(e):
				# A battle event forced this enemy's action; it applies even if the enemy
				# cannot act now (the entry is consumed either way, so it cannot go stale).
				e.action = _forced_next[e]
				_forced_next.erase(e)
			elif e.is_active() and rules.can_act(e):
				e.action = choose_enemy_action(e)
	if party_acts:
		for a in party:
			if _forced_next.has(a):
				a.action = _forced_next[a]
				_forced_next.erase(a)
			elif a.is_active() and rules.can_act(a) and a.action.is_empty():
				a.action = _confused_action(a) if _confused(a) \
					else (_auto_battle_action(a) if _auto_battle(a) else {"kind": "attack", "target": -1})
	var entries := []
	var order := 0
	for b in all_battlers():
		if (b.is_actor() and not party_acts) or (b.is_enemy() and not enemies_act):
			order += 1
			continue
		if b.is_active() and not b.action.is_empty():
			entries.append({"b": b, "speed": rules.action_speed(b, b.action), "order": order})
		order += 1
	entries.sort_custom(func(x, y):
		if x.speed != y.speed:
			return x.speed > y.speed
		return x.order < y.order)
	_queue.clear()
	for e in entries:
		# "action_times" traits: the battler repeats its action right after its turn comes up.
		# One-shot actions (escaping, self-destructing, transforming) never repeat.
		var times := 1
		if not ["escape", "self_destruct", "transform"].has(str(e.b.action.get("kind", ""))):
			times = maxi(1, rules.action_times(e.b))
		for k in times:
			_queue.append(e.b)
	_queue_built = true


func _execute(b: RPGBattler, given_targets: Variant = null) -> Dictionary:
	var action: Dictionary = b.action
	var kind := str(action.get("kind", "wait"))
	var res := {"user": b, "action": action, "kind": kind, "name": "", "targets": [], "effects": [],
		"lines": [], "text": "", "escaped": false, "battle_over": ""}
	# Acting under an attack-at-random state: the log says which state drove the battler
	# before its attack is reported.
	var rstate := str(action.get("restriction_state", ""))
	if rstate != "":
		res.lines.append(rules.term("acts_under_state", [b.name, rules.state_name(rstate)]))
	if not USABLE_KINDS.has(kind) and hooks != null:
		# Guard, escape and wait have no targets to resolve: the hook runs here.
		var h := _action_hook(b, action, [b] if kind == "guard" else [])
		if h.cancel:
			return _cancelled(res)
		if h.changed:
			action = h.action
			kind = str(action.get("kind", "wait"))
			b.action = action
			res.action = action
			res.kind = kind
			if USABLE_KINDS.has(kind):
				_execute_usable(b, action, res, true, h.targets if h.targets_set else null)
				res.text = "\n".join(PackedStringArray(res.lines))
				return res
	if USABLE_KINDS.has(kind):
		_execute_usable(b, action, res, false, given_targets)
	else:
		_execute_simple(b, kind, res, action)
	# "Turn switch ON/OFF when used" (2003): applied once the action has run, hit or missed.
	if not res.get("cancelled", false):
		_apply_action_switches(action)
	res.text = "\n".join(PackedStringArray(res.lines))
	return res


const USABLE_KINDS := ["attack", "skill", "item", "self_destruct"]


## The switch toggles an action carries ("switch_on" / "switch_off" in the runtime action dict).
func _apply_action_switches(action: Dictionary) -> void:
	if not switch_setter.is_valid():
		return
	for key in ["switch_on", "switch_off"]:
		var id := str(action.get(key, ""))
		if id != "":
			switch_setter.call(id, key == "switch_on")


## Guard, escape and the 2003 basic actions that resolve nothing (anything else waits).
## `p_action` is the runtime action dict (transform reads the enemy to become).
func _execute_simple(b: RPGBattler, kind: String, res: Dictionary, p_action: Dictionary = {}) -> void:
	match kind:
		"guard":
			b.guarding = true
			res.lines.append(rules.term("guard", [b.name]))
			_record_last_used(b, kind, {}, [])
		"escape":
			if b.is_enemy():
				# The monster leaves the fight (2003): out of the battle and its rewards, exactly
				# like Force Flee. The action queue goes on; the battler does not.
				b.escaped = true
				b.action = {}
				res["fled"] = [b]
				res.lines.append(rules.term("flee", [b.name]))
				_prune_ready()
				battle_over()
			else:
				var e := attempt_escape()
				res.escaped = e.success
				res.lines.append_array(e.lines)
		"observe":
			res.lines.append(rules.term("observe", [b.name]))
		"charge":
			_charged[b] = rules.charge_multiplier(b)
			res.lines.append(rules.term("charge", [b.name]))
		"transform":
			var nb := transform_enemy(b.index, str(p_action.get("enemy", "")))
			if nb != null:
				res["transformed"] = nb
				res.lines.append(rules.term("transform", [nb.name]))
			else:
				res.lines.append(rules.term("wait", [b.name]))
		_:
			res.lines.append(rules.term("wait", [b.name]))
	# A guard targets its user; escape and wait target nothing. Neither leaves the last action's
	# targets pointing at an enemy, so the branch check stops holding there.
	_last_action_targets = [b] if kind == "guard" else []


## Reports what an action used and targeted to `last_used_recorder`. Only actions that really
## happen (costs paid) are reported; a guard reports just who guarded.
func _record_last_used(b: RPGBattler, kind: String, u: Dictionary, targets: Array) -> void:
	if not last_used_recorder.is_valid():
		return
	var out := {}
	if (kind == "item" or kind == "skill") and str(u.get("id", "")) != "":
		out[kind] = str(u.id)
	if b.is_actor():
		out["actor"] = b.id
	for t in targets:
		if t.is_actor():
			out["target_actor"] = t.id
			break
	for t in targets:
		if t.is_enemy():
			out["target_enemy"] = t.index
			break
	last_used_recorder.call(out)


# --- hooks ---------------------------------------------------------------------------------------

## Reports one hook to `hooks` (see the class notes). Returns {args, cancel}.
func _hook(hook_name: String, args: Array, mode := "") -> Dictionary:
	if hooks == null or not is_instance_valid(hooks) or not hooks.has_method("battle_hook"):
		return {"args": args, "cancel": false}
	var r: Variant = hooks.battle_hook(hook_name, args, mode)
	return r if r is Dictionary and r.has("args") else {"args": args, "cancel": false}


## action_chosen: {action, targets, cancel, changed (the action is another one), targets_set}.
func _action_hook(b: RPGBattler, action: Dictionary, targets: Array) -> Dictionary:
	var r := _hook("action_chosen", [b, action, targets], "action")
	var args: Array = r.args
	var new_action: Dictionary = args[1] if args.size() > 1 and args[1] is Dictionary else action
	var new_targets: Array = args[2] if args.size() > 2 and args[2] is Array else targets
	return {"action": new_action, "targets": new_targets, "cancel": bool(r.get("cancel", false)),
		"changed": new_action != action, "targets_set": new_targets != targets}


## A cancelled action: nothing happens and nothing is shown, but the turn is used.
func _cancelled(res: Dictionary) -> Dictionary:
	res.action = {"kind": "wait", "silent": true}
	res.kind = "wait"
	res["cancelled"] = true
	res.lines.clear()
	res.effects.clear()
	res.targets = []
	return res


## rules.damage_filter while an action is applied: the damage_calculated hook.
func _damage_hook(user: RPGBattler, target: RPGBattler, action: Dictionary, value: int) -> int:
	var r := _hook("damage_calculated", [user, target, action, value], "value")
	var v: Variant = (r.args as Array)[-1]
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else value


## Reports state changes (state_changed) and knockouts (battler_defeated) since the last call:
## after each action and state tick, and from the battle scene after battle events, which can
## change states too. Does nothing without hooks.
func report_changes() -> void:
	if hooks == null:
		return
	for b in all_battlers():
		var now: Array = b.state_ids()
		var was: Array = _known_states.get(b, [])
		if now != was:
			_known_states[b] = now
			for s in was:
				if not now.has(s):
					_hook("state_changed", [b, str(s), false])
			for s in now:
				if not was.has(s):
					_hook("state_changed", [b, str(s), true])
		if b.is_dead() and not _defeated.has(b):
			_defeated[b] = true
			_hook("battler_defeated", [b])
		elif not b.is_dead() and _defeated.has(b):
			_defeated.erase(b)


## The battle animation for an action: the skill's or item's `animation`, or for an attack the
## weapon's `animation` (actors) or "hit".
func _animation_for(b: RPGBattler, kind: String, u: Dictionary) -> String:
	var a := str(u.get("animation", ""))
	if a != "" or kind != "attack":
		return a
	if b.is_actor():
		var w := str(b.equips.get("weapon", ""))
		var dbx: Variant = rules.db if rules != null else null
		if w != "" and dbx != null and dbx.has_method("has_record") and dbx.has_record("weapons", w):
			a = str(dbx.record("weapons", w).get("animation", ""))
	return a if a != "" else "hit"


## `hooked`: action_chosen already ran for this action (it replaced a guard, or another action);
## `given_targets`: the targets a hook chose (null: resolve them from the scope).
func _execute_usable(b: RPGBattler, action: Dictionary, res: Dictionary, hooked := false, given_targets: Variant = null) -> void:
	var kind := str(action.kind)
	var u := rules.resolve_action(b, action)
	if u.is_empty():
		res.lines.append(rules.term("nothing"))
		return
	res.name = u.name
	res["animation"] = _animation_for(b, kind, u)
	if not rules.can_use(b, action):
		res.lines.append(rules.term("cannot_use", [b.name, u.name]))
		return
	var consumed := ""
	if kind == "item" and b.is_actor() and item_consumer.is_valid() and bool(u.get("consumable", true)):
		if not item_consumer.call(u.id):
			res.lines.append(rules.term("cannot_use", [b.name, u.name]))
			return
		consumed = str(u.id)
	# Resolved once (random scopes draw from the RNG), before the message that names them. The
	# cost is paid after the action_chosen hook (paying draws nothing, so the order is unchanged).
	var targets: Array = []
	var baked: Variant = action.get("target_battler", null)
	if baked is RPGBattler and (baked as RPGBattler).is_active():
		# A confused battler's pick (attack at random): the target was chosen with the action.
		targets = [baked]
	elif given_targets is Array:
		targets = (given_targets as Array).filter(func(t): return t is RPGBattler)
	else:
		targets = resolve_targets(b, u, int(action.get("target", -1)))
	if not hooked and hooks != null:
		var h := _action_hook(b, action, targets)
		if h.cancel or h.changed:
			if consumed != "" and item_refund.is_valid():
				item_refund.call(consumed)
		if h.cancel:
			_cancelled(res)
			return
		if h.changed:
			b.action = h.action
			res.action = h.action
			res.kind = str(h.action.get("kind", "wait"))
			res.name = ""
			res.erase("animation")
			if USABLE_KINDS.has(res.kind):
				_execute_usable(b, h.action, res, true, h.targets if h.targets_set else null)
			else:
				_execute_simple(b, res.kind, res, h.action)
			return
		targets = (h.targets as Array).filter(func(t): return t is RPGBattler)
	_last_target[b] = targets[0] if not targets.is_empty() else _last_target.get(b)
	rules.pay_cost(b, action)
	_last_action_targets = targets
	_record_last_used(b, kind, u, targets)
	# VX Ace/MV TP Gain: charged once per use — not per target or repeat, and even on a miss —
	# so it is taken from the rules right after the cost is paid.
	var gained := rules.gain_on_use(b, action)
	if not gained.is_empty():
		res["user_changes"] = gained
	match kind:
		"attack":
			res.lines.append(rules.term("attack", [b.name]))
		"skill":
			res.lines.append(skill_message(b, u, targets))
		"item":
			res.lines.append(rules.term("use_item", [b.name, u.name]))
		"self_destruct":
			res.lines.append(rules.term("self_destruct", [b.name]))
	res.targets = targets
	# Repeats (VX Ace/MV "Repeat" 1-9) come from the usable; an explicit action "times" (a forced
	# 2003 double attack) overrides them.
	var repeats := maxi(1, int(action.get("times", int(u.get("repeats", 1)))))
	if kind == "attack":
		repeats += int(rules.trait_sum(b, "extra_attack"))
	# Charge Up (2003): the stored multiplier boosts every hit of this attack, then it is spent
	# (a missed attack spends it too).
	var charge := 1.0
	if kind == "attack" and _charged.has(b):
		charge = float(_charged[b])
		_charged.erase(b)
	# A damage filter wraps the hits when the hooks ask for one, or a stored charge has to be
	# applied (the two compose: the hook sees the un-boosted value, the charge multiplies it).
	var filtered := hooks != null and "damage_filter" in rules
	var wrapped := filtered or charge != 1.0
	if wrapped:
		var base_hook := _damage_hook if filtered else Callable()
		var m := charge
		rules.damage_filter = func(user: RPGBattler, target: RPGBattler, act: Dictionary, value: int) -> int:
			var v := value
			if base_hook.is_valid():
				v = int(base_hook.call(user, target, act, v))
			return int(round(v * m)) if m != 1.0 else v
	# MV repeats: every repeat re-rolls hit and damage (each apply_action is a fresh roll), and a
	# random scope re-picks its targets per repeat. Other scopes keep a target's repeats together
	# (a Repeat 3 skill strikes one foe three times before moving to the next).
	var apply_one := func(t: RPGBattler) -> void:
		if _counter_or_reflect(b, t, action, u, res):
			return
		var covered := _substitute_for(t, u)
		if covered != t:
			res.lines.append(rules.term("substitute", [covered.name, t.name]))
			t = covered
		var r := rules.apply_action(b, t, action)
		res.effects.append({"target": t, "result": r})
		res.lines.append_array(r.lines)
	if str(u.get("scope", "")) == "random_enemies":
		for k in repeats:
			if k > 0:
				targets = resolve_targets(b, u, int(action.get("target", -1)))
			for t in targets:
				if t.is_active():
					apply_one.call(t)
	else:
		for t in targets:
			for k in repeats:
				if k > 0 and not t.is_active():
					break
				apply_one.call(t)
	if wrapped:
		rules.damage_filter = Callable()
	# The Escape effect (VX Ace / MV): whoever it hits leaves the battle — an actor can escape
	# alone, and the fight ends as an escape when the whole party has gone. An enemy target just
	# leaves (no rewards), like the 2003 flee.
	var fled: Array = []
	for fe in res.effects:
		var tb: RPGBattler = fe.get("target", null)
		if tb is RPGBattler and tb.is_active() and bool(fe.get("result", {}).get("escape", false)):
			tb.escaped = true
			tb.action = {}
			_charged.erase(tb)
			fled.append(tb)
	if not fled.is_empty():
		res["fled"] = fled
		for tb in fled:
			res.lines.append(rules.term("flee", [tb.name]))
		_prune_ready()
		battle_over()
	# Self-Destruct (2003): the monster trades its life for the damage — it collapses once the
	# blast has landed.
	if kind == "self_destruct" and b.is_active():
		b.set_resource(rules.life_resource(), 0)
		if not b.has_state(rules.death_state()):
			rules.add_state(b, rules.death_state())
		res.lines.append(rules.term("knockout", [b.name]))
	# "Common Event" effects: run once after the action (the battle scene runs them).
	if kind != "attack" and rules.has_method("common_events"):
		var ces: Array = rules.common_events(b, action)
		if not ces.is_empty():
			res["common_events"] = ces


## Counter Attack and Magic Reflection (the VX Ace / MV Ex-Parameters), checked per hit the
## way MV's invokeAction does — counter first. A physical hit on a target that can still act is
## answered with a normal attack from the target; a magical skill is reflected back onto the
## user unchanged (no second cost). The hit is replaced either way; rules without the fields
## (or a parameter of 0) never draw and the hit lands as before.
func _counter_or_reflect(user: RPGBattler, target: RPGBattler, action: Dictionary, u: Dictionary, res: Dictionary) -> bool:
	var hit_type := str(u.get("hit_type", "certain"))
	if hit_type == "physical" and rules.can_act(target):
		var cnt := rules.trait_field(target, "cnt", 0)
		if cnt > 0 and rng.chance_percent(float(cnt)):
			res.lines.append(rules.term("counter", [target.name]))
			var r := rules.apply_action(target, user, {"kind": "attack"})
			res.effects.append({"target": user, "result": r, "countered_by": target})
			res.lines.append_array(r.lines)
			return true
	if hit_type == "magical" and target.is_alive():
		var mrf := rules.trait_field(target, "mrf", 0)
		if mrf > 0 and rng.chance_percent(float(mrf)):
			res.lines.append(rules.term("magic_reflection", [target.name]))
			var r := rules.apply_action(user, user, action)
			res.effects.append({"target": user, "result": r, "reflected_by": target})
			res.lines.append_array(r.lines)
			return true
	return false


## Whether `b` fights on its own (MV's Auto Battle special flag): it needs no command — its
## action is chosen when its turn comes up.
func _auto_battle(b: RPGBattler) -> bool:
	return b != null and b.is_actor() and rules != null and rules.has_trait(b, "auto_battle")


## Whether `b` is under an attack-at-random restriction (2000/2003's confusion, berserk and
## charm): it needs no command and attacks what the state says.
func _confused(b: RPGBattler) -> bool:
	return b != null and rules != null and rules.is_confused(b)


## The action a battler takes under an attack-at-random restriction (MV's confusionTarget):
## a normal attack on a random foe (berserk), a random battler from either side (confusion)
## or a random ally, never itself (charm). The pick rides on the action as its baked target;
## nothing to attack means the battler waits its turn out.
func _confused_action(b: RPGBattler) -> Dictionary:
	var kind := rules.restriction(b)
	var side: Array = party if b.is_actor() else enemies
	var foes: Array = enemies if b.is_actor() else party
	var pool: Array = []
	match kind:
		"attack_enemy":
			pool = _pick_foe(foes.filter(func(f): return f.is_active()))
		"attack_anyone":
			pool = (side + foes).filter(func(m): return m.is_active())
		"attack_ally":
			pool = side.filter(func(m): return m != b and m.is_active())
	if pool.is_empty():
		return {"kind": "wait"}
	var t: RPGBattler = pool[0] if pool.size() == 1 else rng.pick(pool)
	return {"kind": "attack", "target_battler": t,
		"restriction_state": rules.restriction_state(b, kind)}


## MV's Auto Battle pick, used when an actor with the flag takes its turn: a usable recovery
## skill is scored by the hurt it would mend (friends at half HP or below), an offensive one by
## its formula against the first living foe — no variance, no criticals and, crucially, no draw
## from the RNG, so a seeded battle plays out the same. Nothing scores above zero: a plain
## attack, as MV falls back to.
func _auto_battle_action(a: RPGBattler) -> Dictionary:
	var foes: Array = active_enemies() if a.is_actor() else active_party()
	var friends: Array = active_party() if a.is_actor() else active_enemies()
	var foe: RPGBattler = foes[0] if not foes.is_empty() else null
	var hurt: Array = friends.filter(func(f): return f.is_active() and _hp_percent(f) <= 50.0)
	var best: Dictionary = {}
	var best_score := 0
	for sk in rules.known_skills(a):
		var action := {"kind": "skill", "skill": sk, "target": -1}
		if not rules.can_use(a, action):
			continue
		var u := rules.resolve_action(a, action)
		if u.is_empty():
			continue
		var scope := str(u.get("scope", ""))
		var score := 0
		if scope.contains("enemy"):
			if foe != null:
				score = maxi(0, rules.formula_value(a, foe, action))
		elif scope.contains("ally") and str(u.get("damage_type", "")) == "recover":
			for f in hurt:
				var missing: int = rules.max_resource(f, rules.life_resource()) - f.get_resource(rules.life_resource())
				score += clampi(rules.formula_value(a, f, action), 0, missing)
		if score > best_score:
			best_score = score
			best = action
	return best if not best.is_empty() else {"kind": "attack", "target": -1}


## MV's applySubstitute: a battler with the Substitute special flag covers a friend who is
## dying (HP below a quarter) from a hit that is not certain — counterattacks and reflections
## are settled first, then the covering battler takes the hit in the ally's place.
func _substitute_for(target: RPGBattler, u: Dictionary) -> RPGBattler:
	if str(u.get("hit_type", "certain")) == "certain" or not target.is_alive():
		return target
	if _hp_percent(target) >= 25.0:
		return target
	var side: Array = party if target.is_actor() else enemies
	for m in side:
		if m != target and m.is_active() and rules.can_act(m) and rules.has_trait(m, "substitute"):
			return m
	return target


## A random pick from `foes` as a 0-or-1-element list (MV's randomTarget): weighted by each
## foe's Target Rate Sp-Parameter when the rules have one — 0 takes a foe out of the draw, 300
## triples its odds, and a draw where every weight is 0 picks nobody — and a plain even pick
## otherwise, so rules without it keep the same RNG draws as before.
func _pick_foe(foes: Array) -> Array:
	if foes.is_empty():
		return []
	if rules.has_snapshot_field("tgr"):
		var pool: Array = []
		for f in foes:
			var w := maxi(0, rules.trait_field(f, "tgr", 100))
			if w > 0:
				pool.append({"foe": f, "weight": w})
		if pool.is_empty():
			return []
		return [rng.pick_weighted(pool).foe]
	return [rng.pick(foes)]


## Targets for a usable (resolved skill/item/attack) by its scope. MV/MZ scopes: "random_enemies"
## draws `random_count` (1-4) picks up front, re-rolling from the living each time, so the same
## enemy can be hit twice; the "(dead or alive)" scopes reach dead allies too (reviving with a
## one-ally-any item), and "everyone" hits both sides' living battlers.
func resolve_targets(user: RPGBattler, usable: Dictionary, target_index: int) -> Array:
	var friends: Array = party if user.is_actor() else enemies
	var foes: Array = enemies if user.is_actor() else party
	var alive_foes := foes.filter(func(x): return x.is_active())
	var alive_friends := friends.filter(func(x): return x.is_active())
	var dead_friends := friends.filter(func(x): return x.is_dead() and not x.hidden and not x.escaped)
	var any_friends := friends.filter(func(x): return not x.hidden and not x.escaped)
	match str(usable.get("scope", "one_enemy")):
		"one_enemy":
			if target_index >= 0 and target_index < foes.size() and foes[target_index].is_active():
				return [foes[target_index]]
			return _pick_foe(alive_foes)
		"all_enemies":
			return alive_foes
		"random_enemy":
			return _pick_foe(alive_foes)
		"random_enemies":
			# N picks, each a fresh roll among the living (MV randomTargets).
			var picks: Array = []
			for i in maxi(1, int(usable.get("random_count", 1))):
				if alive_foes.is_empty():
					break
				picks.append_array(_pick_foe(alive_foes))
			return picks
		"one_ally":
			if target_index >= 0 and target_index < friends.size() and friends[target_index].is_active():
				return [friends[target_index]]
			return [user] if user.is_active() else []
		"one_ally_any":
			if target_index >= 0 and target_index < friends.size() and not friends[target_index].hidden and not friends[target_index].escaped:
				return [friends[target_index]]
			return [user] if user.is_active() else (alive_friends[0] if not alive_friends.is_empty() else [])
		"all_allies":
			return alive_friends
		"all_allies_any":
			return any_friends
		"one_dead_ally":
			if target_index >= 0 and target_index < friends.size() and friends[target_index].is_dead():
				return [friends[target_index]]
			return [] if dead_friends.is_empty() else [dead_friends[0]]
		"all_dead_allies":
			return dead_friends
		"everyone":
			return alive_friends + alive_foes
		"self", "user":
			return [user]
	return []


# --------------------------------------------------------------------------------------------
# Time-based battles (ATB / CTB)
# --------------------------------------------------------------------------------------------

func is_timed() -> bool:
	return battle_system == "atb" or battle_system == "ctb"


## Random encounters: "preemptive", "surprise" or "normal" for a roll in [0, 1). A simple form of
## RPG Maker MV's rates: a party at least as quick as the troop (average agility, as atb_speed)
## gets a preemptive strike 5% of the time and is surprised 3%; a slower party 3% and 5%.
## The two chances share one roll (preemptive first).
static func encounter_advantage(p_rules: RPGRuleSystem, party_battlers: Array, troop_rec: Dictionary, roll: float) -> String:
	var r := encounter_rates(p_rules, party_battlers, troop_rec)
	if roll < float(r.preemptive):
		return "preemptive"
	if roll < float(r.preemptive) + float(r.surprise):
		return "surprise"
	return "normal"


## The 2003 battle starts (#39): "initiative", "back_attack", "surround", "pincer" or "normal"
## for a roll in [0, 1) and the chances (0..1, in START_CONDITIONS order) a map or the System
## sets. The chances share the one roll, each covering what came before it, so together they
## cannot pass 100%. When they are all zero this returns "normal" and the caller falls back to
## the preemptive / surprise roll (encounter_advantage).
static func encounter_condition(odds: Dictionary, roll: float) -> String:
	var used := 0.0
	for k in START_CONDITIONS:
		used += clampf(float(odds.get(k, 0)), 0.0, 1.0)
		if roll < used:
			return k
	return "normal"


## {preemptive, surprise} chances (0..1) for encounter_advantage.
static func encounter_rates(p_rules: RPGRuleSystem, party_battlers: Array, troop_rec: Dictionary) -> Dictionary:
	var party_agi := _average_speed(p_rules, party_battlers.filter(func(b): return b is RPGBattler and b.is_alive()))
	var foes := []
	if p_rules != null:
		for m in troop_rec.get("members", []):
			if m is Dictionary and not bool(m.get("hidden", false)):
				var e := p_rules.new_enemy_battler(str(m.get("enemy", "")))
				if e != null:
					foes.append(e)
	var troop_agi := _average_speed(p_rules, foes)
	var quick := party_agi >= troop_agi
	var preemptive := 0.05 if quick else 0.03
	var surprise := 0.03 if quick else 0.05
	# Party abilities (VX Ace / MV): Cancel Surprise removes the ambush chance, Raise Preemptive
	# quadruples the first-strike one. Any party member's trait applies.
	if p_rules != null:
		if p_rules.party_has_trait(party_battlers, "cancel_surprise"):
			surprise = 0.0
		if p_rules.party_has_trait(party_battlers, "raise_preemptive"):
			preemptive *= 4.0
	return {"preemptive": preemptive, "surprise": surprise}


static func _average_speed(p_rules: RPGRuleSystem, list: Array) -> float:
	if list.is_empty() or p_rules == null or not p_rules.has_method("atb_speed"):
		return 0.0
	var total := 0.0
	for b in list:
		total += float(p_rules.atb_speed(b))
	return total / list.size()


## Gauges at battle start: ATB_START plus a small random offset; a preemptive strike, initiative
## or surround fills the party's gauges (the enemies start empty), a surprise attack, back attack
## or pincer the enemies'.
func _atb_setup() -> void:
	var total := 0.0
	var n := 0
	for b in all_battlers():
		_speeds[b] = _speed_of(b)
		if b.is_active():
			total += _speeds[b]
			n += 1
	_atb_base = maxf(1.0, total / maxf(1.0, float(n)))
	var filled := []
	for b in all_battlers():
		var g := ATB_START + rng.randf() * ATB_START_SPREAD
		if advantage in ["preemptive", "initiative", "surround"]:
			g = 1.0 if b.is_actor() else 0.0
		elif advantage in ["surprise", "back_attack", "pincer"]:
			g = 1.0 if b.is_enemy() else 0.0
		gauges[b] = g if b.is_alive() else 0.0
		if g >= 1.0 and b.is_active():
			filled.append(b)
	# Full at the start: the fastest goes first.
	filled.sort_custom(func(x, y): return float(_speeds[x]) > float(_speeds[y]))
	for b in filled:
		_make_ready(b)


func _speed_of(b: RPGBattler) -> float:
	if rules != null and rules.has_method("atb_speed"):
		return maxf(1.0, float(rules.atb_speed(b)))
	return 1.0


## Gauge fill per second for `b`.
func atb_rate(b: RPGBattler) -> float:
	if not _speeds.has(b):
		_speeds[b] = _speed_of(b)
	return float(_speeds[b]) / _atb_base / ATB_FILL_SECONDS


func gauge(b: RPGBattler) -> float:
	return float(gauges.get(b, 0.0))


func _make_ready(b: RPGBattler) -> void:
	gauges[b] = 1.0
	if ready_queue.has(b):
		return
	ready_queue.append(b)
	# A new turn for this battler: its guard from last turn ends, it chooses afresh.
	b.guarding = false
	b.action = {}


## Drops battlers that can no longer take a turn (dead, escaped, hidden) from the ready queue;
## the dead start again from an empty gauge if they are revived.
func _prune_ready() -> void:
	for b in ready_queue.duplicate():
		if not b.is_active():
			ready_queue.erase(b)
			_extra.erase(b)
	for b in all_battlers():
		if b.is_dead():
			gauges[b] = 0.0


## Advances battle time by `seconds`: every active battler whose gauge is not full fills by
## atb_rate(). Battlers that fill join ready_queue in the order they would have filled.
func atb_advance(seconds: float) -> void:
	if not is_timed() or battle_over() != "" or seconds <= 0.0:
		return
	_prune_ready()
	var filled := []
	var all := all_battlers()
	for i in all.size():
		var b: RPGBattler = all[i]
		if not b.is_active() or ready_queue.has(b):
			continue
		var g := gauge(b)
		var rate := atb_rate(b)
		var ng := g + rate * seconds
		if ng >= 1.0 - 0.000001:
			filled.append({"b": b, "t": (1.0 - g) / rate, "i": i})
			ng = 1.0
		gauges[b] = ng
	filled.sort_custom(func(x, y):
		if not is_equal_approx(x.t, y.t):
			return x.t < y.t
		return x.i < y.i)
	for f in filled:
		_make_ready(f.b)


## Seconds until the next gauge fills (INF when nobody is filling).
func atb_time_to_ready() -> float:
	var best := INF
	for b in all_battlers():
		if b.is_active() and not ready_queue.has(b):
			best = minf(best, maxf(0.0, (1.0 - gauge(b)) / atb_rate(b)))
	return best


## CTB (and automatic ATB battles): jumps time to the moment the next gauge fills.
func atb_advance_to_next() -> void:
	_prune_ready()
	if not ready_queue.is_empty():
		return
	var t := atb_time_to_ready()
	if t < INF:
		atb_advance(maxf(t, 0.000001))


## True when actor `b` has a full gauge and waits for the player's command.
func needs_input(b: RPGBattler) -> bool:
	return b != null and b.is_actor() and ready_queue.has(b) and b.is_active() and rules.can_act(b) \
		and b.action.is_empty() and not _forced_next.has(b) and not _auto_battle(b) and not _confused(b)


## Full actors waiting for a command, in ready order.
func input_actors() -> Array:
	_prune_ready()
	return ready_queue.filter(func(b): return needs_input(b))


## ATB: actor `b` lets the next full actor choose first (RPG Maker 2003's Shift / Tab). `b` moves
## behind the other actors waiting for a command; nobody else's place changes. Returns the actor
## that chooses now, or null when no other actor is waiting.
func pass_turn(b: RPGBattler) -> RPGBattler:
	var waiting := input_actors()
	if not waiting.has(b) or waiting.size() < 2:
		return null
	var last: RPGBattler = waiting[-1]
	if last == b:
		return waiting[0]
	ready_queue.erase(b)
	ready_queue.insert(ready_queue.find(last) + 1, b)
	return input_actors()[0]


## The first full actor waiting for a command, or null.
func next_input_actor() -> RPGBattler:
	_prune_ready()
	for b in ready_queue:
		if needs_input(b):
			return b
	return null


## The first full battler that can take its turn without the player: an enemy, an actor whose
## action is set, or one that cannot act (it loses the turn). Null when there is none.
func next_auto_ready() -> RPGBattler:
	_prune_ready()
	for b in ready_queue:
		if not needs_input(b):
			return b
	return null


## Takes battler `b`'s turn (it must be in ready_queue) and returns the same result as
## next_action(), plus `ticks` (its end-of-turn state processing, as end_turn() entries),
## `skipped` (it could not act), `again` (an extra action follows) and `turn_end` (the battle
## turn is over: call begin_turn() after running the end-of-turn pages).
func act(b: RPGBattler) -> Dictionary:
	if battle_over() != "" or not ready_queue.has(b):
		return {}
	ready_queue.erase(b)
	phase = "actions"
	var before := _vitals()
	var skipped := not b.is_active() or not rules.can_act(b)
	var res: Dictionary
	if skipped:
		_forced_next.erase(b)
		res = {"user": b, "action": {"kind": "wait", "silent": true}, "kind": "wait", "name": "", "targets": [],
			"effects": [], "lines": [], "text": "", "escaped": false, "battle_over": ""}
	else:
		_hook("turn_started", [b])
		var given: Variant = null
		if _forced_next.has(b):
			b.action = _forced_next[b]
			given = _forced_targets(b, b.action)
			_forced_next.erase(b)
		elif b.is_enemy():
			b.action = choose_enemy_action(b)
		elif b.action.is_empty():
			b.action = _confused_action(b) if _confused(b) \
				else (_auto_battle_action(b) if _auto_battle(b) else {"kind": "attack", "target": -1})
		if not _extra.has(b):
			_extra[b] = 0 if str(b.action.get("kind", "")) == "escape" else maxi(1, rules.action_times(b)) - 1
		res = _execute(b, given)
		# Action-end states tick after each action (extra actions too, as MV's Action End).
		var tick := rules.tick_states(b, "action_end")
		if not tick.lines.is_empty():
			tick.battler = b
			res["ticks"] = [tick]
		_note_command(b, res)
	res["skipped"] = skipped
	if not res.has("ticks"):
		res["ticks"] = []
	if not skipped and int(_extra.get(b, 0)) > 0 and b.is_active() and rules.can_act(b) and not res.escaped and battle_over() == "":
		# "action_times": another action right away (the player picks it for an actor).
		_extra[b] = int(_extra[b]) - 1
		b.action = {}
		ready_queue.push_front(b)
		res["again"] = true
	else:
		_extra.erase(b)
		if b.is_active():
			b.turns_taken += 1   # one gauge fill = one of the battler's own turns (#11)
			var t := rules.tick_states(b)
			if not t.lines.is_empty():
				t.battler = b
				res.ticks.append(t)
		b.action = {}
		gauges[b] = 0.0
		_speeds[b] = _speed_of(b)
		_acted[b] = true
	report_changes()
	_prune_ready()
	if _vitals() != before:
		checkpoint.emit("after_change")
	checkpoint.emit("after_action")
	res["turn_end"] = _timed_turn_over()
	res.battle_over = battle_over()
	return res


## A failed escape in a timed battle: every party member loses its turn (gauge back to empty),
## as the whole party loses its turn in the turn system. Returns true when that ends the battle
## turn (then call begin_turn()).
func lose_party_turns() -> bool:
	for a in party:
		ready_queue.erase(a)
		_extra.erase(a)
		a.action = {}
		gauges[a] = 0.0
		if a.is_active():
			_acted[a] = true
	return _timed_turn_over()


## Emits "end_of_turn" once every battler that began this battle turn active has had its turn.
func _timed_turn_over() -> bool:
	if battle_over() != "":
		return false
	for b in _turn_members:
		if b.is_active() and not _acted.has(b):
			return false
	phase = "turn_end"
	checkpoint.emit("end_of_turn")
	return true


## The next `n` turns of a timed battle, from the gauges as they are now (speeds and states as
## they are; for the CTB turn-order display). Battlers already full come first.
func turn_order(n: int) -> Array:
	var out := []
	if not is_timed() or n <= 0:
		return out
	_prune_ready()
	var sim := {}
	var all := all_battlers().filter(func(b): return b.is_active())
	for b in all:
		sim[b] = gauge(b)
	for b in ready_queue:
		out.append(b)
		sim[b] = 0.0
	var guard := 0
	while out.size() < n and not all.is_empty() and guard < n * 4:
		guard += 1
		var best: RPGBattler = null
		var best_t := INF
		for b in all:
			var t := (1.0 - float(sim[b])) / atb_rate(b)
			if t < best_t - 0.000001:
				best_t = t
				best = b
		if best == null:
			break
		for b in all:
			sim[b] = float(sim[b]) + atb_rate(b) * best_t
		sim[best] = 0.0
		out.append(best)
	return out.slice(0, n)


# --------------------------------------------------------------------------------------------
# Enemy AI
# --------------------------------------------------------------------------------------------

## Picks an action from the enemy record's "actions": [{skill, rating, condition, ...}]. The
## "skill" names a skill record or one of the 2003 basic actions (see _enemy_action_dict). Among
## usable actions whose condition holds, those rated within 2 of the best are picked, weighted by
## how close they are.
func choose_enemy_action(e: RPGBattler) -> Dictionary:
	# An attack-at-random restriction overrides the action table (2000/2003: a confused or
	# charmed monster attacks whatever the state says).
	if _confused(e):
		return _confused_action(e)
	var rec := rules.battler_record(e)
	var usable := []
	var best := -1000000
	for a in rec.get("actions", []):
		if not (a is Dictionary):
			continue
		var act := _enemy_action_dict(a)
		if not _enemy_condition(e, a.get("condition", {})):
			continue
		if act.kind == "skill" and not rules.can_use(e, act):
			continue
		# Transform needs a real enemy record to become.
		if act.kind == "transform" and not _enemy_exists(str(act.get("enemy", ""))):
			continue
		var rating := int(a.get("rating", 5))
		usable.append({"act": act, "rating": rating})
		best = maxi(best, rating)
	if usable.is_empty():
		return {"kind": "attack", "target": -1}
	var pool := []
	for u in usable:
		if u.rating > best - 3:
			pool.append({"act": u.act, "weight": u.rating - (best - 3)})
	var pick: Variant = rng.pick_weighted(pool)
	return (pick.act as Dictionary).duplicate() if pick != null else {"kind": "attack", "target": -1}


func _enemy_exists(enemy_id: String) -> bool:
	if enemy_id == "" or rules == null or rules.db == null:
		return false
	if rules.db.has_method("has_record"):
		return rules.db.has_record("enemies", enemy_id)
	return not (rules.db.record("enemies", enemy_id) if rules.db.has_method("record") else {}).is_empty()


## An action pattern from the enemy record as the runtime action dict. "skill" names a skill
## record, or one of the 2003 basic actions: attack and double_attack (two hits) attack, guard /
## observe / wait do what they say, charge strengthens the next attack, self_destruct trades the
## monster's life for damage, escape leaves the battle, transform becomes the "enemy" record.
## "switch_on" / "switch_off" ride along and are applied when the action runs.
func _enemy_action_dict(a: Dictionary) -> Dictionary:
	var sk := str(a.get("skill", "attack"))
	var act := {}
	match sk:
		"attack", "guard", "wait", "observe", "charge", "self_destruct":
			act = {"kind": sk, "target": -1}
		"double_attack":
			act = {"kind": "attack", "times": 2, "target": -1}
		"escape":
			act = {"kind": "escape", "target": -1}
		"transform":
			act = {"kind": "transform", "enemy": str(a.get("enemy", "")), "target": -1}
		_:
			act = {"kind": "skill", "skill": sk, "target": -1}
	for key in ["switch_on", "switch_off"]:
		if str(a.get(key, "")) != "":
			act[key] = str(a[key])
	return act


## One action-pattern condition. Shared helpers (_turn_matches, _hp_percent, _mp_percent,
## _compare, _switch_is) keep the semantics the same as the troop page conditions (#9).
func _enemy_condition(e: RPGBattler, c: Variant) -> bool:
	if not (c is Dictionary) or c.is_empty():
		return true
	match str(c.get("kind", "always")):
		"always":
			return true
		"turn":
			return _turn_matches(int(c.get("n", 0)), int(c.get("every", 0)))
		"hp":
			return _compare(_hp_percent(e), str(c.get("op", "<=")), float(c.get("percent", 100)))
		"mp":
			if rules.magic_resource() == "":
				return false
			return _compare(_mp_percent(e), str(c.get("op", "<=")), float(c.get("percent", 50)))
		"state":
			return e.has_state(str(c.get("state", "")))
		"party_level":
			var levels := []
			for a in party:
				if a.is_active():
					levels.append(float(a.level))
			if levels.is_empty():
				return false
			var lv := levels.max()
			if str(c.get("pick", "average")) != "highest":
				lv = levels.reduce(func(s, x): return s + x, 0.0) / levels.size()
			return _compare(lv, str(c.get("op", ">=")), float(c.get("level", 1)))
		"enemies_alive":
			var alive := 0
			for foe in enemies:
				if foe.is_active():
					alive += 1
			return _compare(float(alive), str(c.get("op", ">=")), float(c.get("count", 1)))
		"switch":
			return _switch_is(str(c.get("id", "")), bool(c.get("value", true)))
		"variable":
			# Same variable semantics as page conditions, through condition_reader. The editor
			# stores the ref under "variable" (the condition's "id" is the switch's key), so both
			# spellings are accepted here; "against" is the editor's name for the operand.
			if condition_reader.is_valid():
				var cc := {
					"kind": "variable",
					"id": str(c.get("variable", c.get("id", ""))),
					"op": str(c.get("op", "==")),
					"value": c.get("against", c.get("value", 0)),
				}
				return bool(condition_reader.call(cc))
			return false
	return false


# --------------------------------------------------------------------------------------------
# Battle events
# --------------------------------------------------------------------------------------------

## Troop battle pages eligible at this checkpoint, highest priority first, then page order.
## Page: {id, conditions: [...], span: "once_per_battle"|"once_per_turn"|"every_check",
##        priority, commands, at?: [checkpoint kinds]}
## Conditions (all must hold; a page with no conditions never runs):
##   {kind: "turn", n, every}            turn == n, or turn >= n and (turn - n) % every == 0
##   {kind: "enemy_hp"|"enemy_mp", index, op, percent}
##   {kind: "actor_hp"|"actor_mp", id, op, percent}
##   {kind: "enemy_turns", index, op, n}   the enemy's own turns (taken or lost)
##   {kind: "actor_turns", id, op, n}      the actor's own turns (taken or lost)
##   {kind: "command_used", id, command, skill?}   the actor used this command this battle turn
##   {kind: "switch", id, value?: true}
##   {kind: "turn_end"}                 only true at the end_of_turn checkpoint
## Other kinds (variable, item, gold, extension kinds marked "battle": true) are answered by
## condition_reader, which the battle scene wires to rpg.state.check_condition.
## With `consume` (default) the returned pages are recorded as run, so their span is honoured.
func eligible_battle_pages(checkpoint_kind: String, consume: bool = true) -> Array:
	var pages: Array = troop.get("pages", [])
	var found := []
	for i in pages.size():
		var p: Dictionary = pages[i]
		var pid := page_id(p, i)
		if p.has("at") and not (p.at as Array).has(checkpoint_kind):
			continue
		match str(p.get("span", "once_per_battle")):
			"once_per_battle":
				if _page_runs.has(pid):
					continue
			"once_per_turn":
				if int(_page_runs.get(pid, -1)) == turn:
					continue
		if not page_conditions_met(p, checkpoint_kind):
			continue
		found.append({"page": p, "i": i, "priority": int(p.get("priority", 0)), "id": pid})
	found.sort_custom(func(x, y):
		if x.priority != y.priority:
			return x.priority > y.priority
		return x.i < y.i)
	var out := []
	for f in found:
		if consume:
			_page_runs[f.id] = turn
		out.append(f.page)
	return out


static func page_id(p: Dictionary, i: int) -> String:
	return str(p.get("id", "page_%d" % i))


func page_conditions_met(p: Dictionary, checkpoint_kind := "") -> bool:
	var conds: Array = p.get("conditions", [])
	if conds.is_empty():
		return false
	for c in conds:
		if not _page_condition(c, checkpoint_kind):
			return false
	return true


func _page_condition(c: Dictionary, checkpoint_kind := "") -> bool:
	match str(c.get("kind", "")):
		"turn":
			return _turn_matches(int(c.get("n", 0)), int(c.get("every", 0)))
		"enemy_hp":
			var idx := int(c.get("index", 0))
			for e in enemies:
				if e.index == idx:
					return not e.hidden and _compare(_hp_percent(e), str(c.get("op", "<=")), float(c.get("percent", 100)))
			return false
		"enemy_mp":
			if rules.magic_resource() == "":
				return false
			var mp_idx := int(c.get("index", 0))
			for e in enemies:
				if e.index == mp_idx:
					return not e.hidden and _compare(_mp_percent(e), str(c.get("op", "<=")), float(c.get("percent", 50)))
			return false
		"actor_hp":
			for a in party:
				if a.id == str(c.get("id", "")):
					return _compare(_hp_percent(a), str(c.get("op", "<=")), float(c.get("percent", 100)))
			return false
		"actor_mp":
			if rules.magic_resource() == "":
				return false
			for mp_a in party:
				if mp_a.id == str(c.get("id", "")):
					return _compare(_mp_percent(mp_a), str(c.get("op", "<=")), float(c.get("percent", 50)))
			return false
		"enemy_turns":
			var t_idx := int(c.get("index", 0))
			for e in enemies:
				if e.index == t_idx:
					return not e.hidden and _compare(float(e.turns_taken), str(c.get("op", ">=")), float(c.get("n", 1)))
			return false
		"actor_turns":
			for t_a in party:
				if t_a.id == str(c.get("id", "")):
					return _compare(float(t_a.turns_taken), str(c.get("op", ">=")), float(c.get("n", 1)))
			return false
		"command_used":
			for u in _used_commands.get(str(c.get("id", "")), []):
				if str(u.get("kind", "")) != str(c.get("command", "")):
					continue
				var want := str(c.get("skill", ""))
				if want == "" or str(u.get("skill", "")) == want:
					return true
			return false
		"switch":
			return _switch_is(str(c.get("id", "")), bool(c.get("value", true)))
		"turn_end":
			return checkpoint_kind == "end_of_turn"
	# Other kinds (variable, item, gold, extension kinds marked "battle": true): the battle
	# scene asks the game state through condition_reader.
	if condition_reader.is_valid():
		return bool(condition_reader.call(c))
	push_warning("Battle page condition kind '%s' is not supported" % str(c.get("kind", "")))
	return false


func _turn_matches(n: int, every: int) -> bool:
	if every > 0:
		return turn >= n and (turn - n) % every == 0
	return turn == n


func _hp_percent(b: RPGBattler) -> float:
	var res := rules.life_resource()
	var m := rules.max_resource(b, res)
	if m <= 0:
		return 0.0
	return 100.0 * float(b.get_resource(res)) / float(m)


## MP percent for the enemy_mp/actor_mp conditions; only called when magic_resource() != ""
## (a ruleset with no spell resource never matches an MP condition).
func _mp_percent(b: RPGBattler) -> float:
	var res := rules.magic_resource()
	var m := rules.max_resource(b, res)
	if m <= 0:
		return 0.0
	return 100.0 * float(b.get_resource(res)) / float(m)


## command_used conditions: remember the command an actor used this battle turn (a cancelled
## action counts as none). skill is only set for skill commands.
func _note_command(b: RPGBattler, res: Dictionary) -> void:
	if not b.is_actor() or bool(res.get("cancelled", false)):
		return
	var used := {"kind": str(res.get("kind", "")), "skill": str(res.action.get("skill", ""))}
	if not _used_commands.has(b.id):
		_used_commands[b.id] = []
	(_used_commands[b.id] as Array).append(used)


func _switch_is(id: String, value: bool) -> bool:
	if not switch_reader.is_valid():
		return false
	return bool(switch_reader.call(id)) == value


## A Conditional Branch battle check (RM2000/2003): whether an actor in the party or an enemy
## by its 0-based member index can act (present and not held back by a state), and whether an
## enemy is the target of the action that just ran (true only for a single-enemy action).
## Battlers that are not in the fight give false. The game state routes these kinds here
## through the battle facade while a battle runs.
func branch_check(kind: String, cond: Dictionary) -> bool:
	match kind:
		"actor_can_act":
			for a in party:
				if a.id == str(cond.get("id", "")):
					return a.is_active() and rules.can_act(a)
			return false
		"enemy_can_act", "enemy_is_target":
			var e: RPGBattler = null
			for x in enemies:
				if x.index == int(cond.get("index", 0)):
					e = x
					break
			if e == null:
				return false
			if kind == "enemy_can_act":
				return e.is_active() and rules.can_act(e)
			return _last_action_targets.size() == 1 and _last_action_targets[0] == e
	return false


static func _compare(a: float, op: String, b: float) -> bool:
	match op:
		"==", "=":
			return is_equal_approx(a, b)
		"!=":
			return not is_equal_approx(a, b)
		"<":
			return a < b
		"<=":
			return a <= b
		">":
			return a > b
		">=":
			return a >= b
	return false


# --------------------------------------------------------------------------------------------
# Outcome
# --------------------------------------------------------------------------------------------

## "" while the fight goes on, else "win", "lose" or "escape".
func battle_over() -> String:
	if _result != "":
		return _result
	if party.is_empty() or party.all(func(a): return a.is_dead()):
		_result = "lose"
	elif active_party().is_empty() and party.any(func(a): return a.escaped):
		# The Escape effect emptied the party's side one member at a time.
		_result = "escape"
	elif active_enemies().is_empty() and enemies.any(func(e): return not e.hidden):
		_result = "win"
	elif enemies.is_empty():
		_result = "win"
	if _result != "":
		phase = "over"
	return _result


## Ends the battle from outside (e.g. an event command "abort battle").
func force_result(result: String) -> void:
	_result = result
	_forced = true
	phase = "over"


## Enemy Appear: brings troop member `member_index` into the battle if it is hidden ("Appears
## later"); -1 brings every hidden member. Returns the battlers that appeared, in troop order.
## Timed battles: a new enemy starts from an empty-ish gauge (ATB_START). A win that was only
## seen because every visible enemy fell (a battle event "enemy HP 0%" calling reinforcements)
## is taken back, so the battle goes on.
func appear(member_index: int) -> Array:
	var out := []
	for e in enemies:
		if not e.hidden or (member_index >= 0 and e.index != member_index):
			continue
		e.hidden = false
		out.append(e)
		_known_states[e] = e.state_ids()
		if is_timed():
			_speeds[e] = _speed_of(e)
			gauges[e] = ATB_START if e.is_alive() else 0.0
	if not out.is_empty() and _result == "win" and not _forced and not active_enemies().is_empty():
		_result = ""
		phase = "actions"
	return out


## Force Flee (RM2003): the whole party runs — the battle ends as an escape, no chance roll —
## or enemies run: every enemy, or the member with index `member_index` (0-based; -1: every
## enemy). A fled enemy leaves the turn order and targeting and gives no rewards; when no enemy
## is left the battle ends as a win. Returns the battlers that fled, in order.
func force_flee(target: String, member_index := -1) -> Array:
	var out := []
	if target == "party":
		for b in active_party():
			b.escaped = true
			b.action = {}
			out.append(b)
		if not out.is_empty():
			_result = "escape"
			phase = "over"
		return out
	for e in enemies:
		if member_index >= 0 and e.index != member_index:
			continue
		if e.is_active():
			e.escaped = true
			e.action = {}
			_charged.erase(e)
			out.append(e)
	if not out.is_empty():
		_prune_ready()
		battle_over()
	return out


## Transform (2003, #3): the member at `member_index` (0-based) becomes the enemy record
## `enemy_id`, keeping its slot, screen position and "A/B" suffix. `hp_mode`: "keep" carries the
## resources over clamped to the new maxima, "percent" carries their shares over, "refill" starts
## full. States are kept unless `clear_states`. Stats, actions, traits and rewards come from the
## new record. Returns the new battler, or null when the member or the enemy record does not exist.
func transform_enemy(member_index: int, enemy_id: String, hp_mode := "keep", clear_states := false) -> RPGBattler:
	var old: RPGBattler = null
	for e in enemies:
		if e.index == member_index:
			old = e
			break
	if old == null or not _enemy_exists(enemy_id):
		return null
	var nb: RPGBattler = rules.new_enemy_battler(enemy_id)
	if nb == null:
		return null
	nb.index = old.index
	nb.screen_position = old.screen_position
	nb.hidden = old.hidden
	nb.escaped = old.escaped
	nb.guarding = old.guarding
	nb.action = old.action
	# "Slime A" keeps its letter when the troop fielded more than one of the old enemy (counted
	# from the troop, so members that already transformed away do not lose their suffix).
	var crowd := 0
	for m in troop.get("members", []):
		if m is Dictionary and str(m.get("enemy", "")) == old.id:
			crowd += 1
	if crowd > 1 and old.name.length() >= 2 \
			and old.name[old.name.length() - 2] == " " and old.name[old.name.length() - 1] >= "A" \
			and old.name[old.name.length() - 1] <= "Z":
		nb.name = "%s %s" % [nb.name, old.name[old.name.length() - 1]]
	# Resources: the values (clamped to the new maxima), their shares, or a fresh start
	# (new_enemy_battler recovered all: every resource is at its maximum).
	var old_values := old.resources.duplicate()
	var shares := {}
	for rid in old_values:
		var m: int = rules.max_resource(old, rid)
		shares[rid] = clampf(float(old_values[rid]) / float(m), 0.0, 1.0) if m > 0 else 1.0
	match hp_mode:
		"percent":
			for rid in shares:
				nb.set_resource(rid, roundi(float(shares[rid]) * rules.max_resource(nb, rid)))
		"refill":
			pass
		_:
			for rid in old_values:
				nb.set_resource(rid, clampi(int(old_values[rid]), 0, rules.max_resource(nb, rid)))
	if not clear_states:
		for s in old.states:
			nb.add_state(str(s.id), int(s.get("turns", -1)))
	var at := enemies.find(old)
	enemies[at] = nb
	_known_states.erase(old)
	_known_states[nb] = nb.state_ids()
	_defeated.erase(old)
	_charged.erase(old)
	if nb.is_dead():
		_defeated[nb] = true
	# Timed battles: the new battler inherits the slot's gauge and pending turn.
	if is_timed():
		_speeds.erase(old)
		_speeds[nb] = _speed_of(nb)
		gauges[nb] = gauges.get(old, 0.0)
		gauges.erase(old)
		for i in ready_queue.size():
			if ready_queue[i] == old:
				ready_queue[i] = nb
		if _acted.has(old):
			_acted[nb] = _acted[old]
			_acted.erase(old)
		if _extra.has(old):
			_extra[nb] = _extra[old]
			_extra.erase(old)
		if _turn_members.has(old):
			_turn_members[_turn_members.find(old)] = nb
	_rewards.clear()  # the spoils follow the new record (rewards() reads battler_record(e))
	enemy_transformed.emit(old, nb)
	return nb


## A reinforcement beyond the troop's members: a new enemy built from `enemy_id` at `position`
## (pixels on the 320x240 battle screen). The battle facade calls this (rpg.battle.add_enemy).
## Returns the battler, or null when the enemy record does not exist.
func add_enemy(enemy_id: String, position := Vector2(160, 120)) -> RPGBattler:
	var b: RPGBattler = rules.new_enemy_battler(enemy_id)
	if b == null:
		return null
	b.index = enemies.size()
	b.screen_position = position
	enemies.append(b)
	_known_states[b] = b.state_ids()
	rules.start_battle(b)
	if is_timed():
		_speeds[b] = _speed_of(b)
		gauges[b] = ATB_START if b.is_alive() else 0.0
	# A win that was only seen because every visible enemy fell is taken back, like appear().
	if _result == "win" and not _forced and not active_enemies().is_empty():
		_result = ""
		phase = "actions"
	return b

## Change Party Member during the battle: brings `party` in step with `wanted` (actor battlers;
## the battle scene passes the state's party through battle_members()). Added actors join with a
## fresh gauge in timed battles; removed actors leave the turn order and targeting, and victory
## and defeat are re-checked. Returns {"added": [...], "removed": [...]}.
func refresh_party(wanted: Array) -> Dictionary:
	var added := []
	var removed := []
	for b in party.duplicate():
		if wanted.has(b):
			continue
		removed.append(b)
		party.erase(b)
		b.action = {}
		b.guarding = false
		_acted.erase(b)
		_extra.erase(b)
		_charged.erase(b)
		_turn_members.erase(b)
		_known_states.erase(b)
		_defeated.erase(b)
		gauges.erase(b)
		_speeds.erase(b)
	for b in wanted:
		if party.has(b):
			continue
		added.append(b)
		party.append(b)
		b.guarding = false
		b.action = {}
		b.escaped = false
		rules.start_battle(b)
		_known_states[b] = b.state_ids()
		if b.is_dead():
			_defeated[b] = true
		if is_timed():
			_speeds[b] = _speed_of(b)
			gauges[b] = ATB_START if b.is_alive() else 0.0
	for i in party.size():
		party[i].index = i
	_queue.clear()
	_queue_built = false
	_prune_ready()
	# A defeat that was only seen because the last actor left is taken back.
	if not _forced and _result == "lose" and not party.is_empty() and party.any(func(a): return a.is_alive()):
		_result = ""
		phase = "actions"
	battle_over()
	return {"added": added, "removed": removed}


## Timed battles (ATB / CTB): sets a battler's gauge, 0 (empty) to 1 (full). A full actor then
## waits for its command; a full enemy keeps its normal turn order. rpg.battle.set_gauge.
func set_gauge(b: RPGBattler, value: float) -> void:
	if not is_timed() or b == null:
		return
	gauges[b] = clampf(value, 0.0, 1.0)
	if gauges[b] >= 1.0:
		_make_ready(b)
	else:
		_prune_ready()


## Spoils from defeated enemies: {exp, gold, items: [{kind, id, count}]}. Drops are rolled
## once and cached. Enemy drops: [{kind: "item"|"weapon"|"armor", id, chance (percent)}].
func rewards() -> Dictionary:
	if not _rewards.is_empty():
		return _rewards
	var exp_total := 0
	var gold := 0
	var items := []
	# Party abilities (VX Ace / MV): Gold Double and Drop Item Double multiply the take. The
	# traits of the members alive at the victory count.
	var gold_rate := 1.0
	var drop_rate := 1.0
	if rules != null:
		var living := party.filter(func(b): return b is RPGBattler and b.is_alive())
		gold_rate = rules.party_trait_rate(living, "gold_double")
		drop_rate = rules.party_trait_rate(living, "drop_double")
	for e in enemies:
		# Fled enemies (Force Flee) leave without rewards, like ones never revealed.
		if not e.is_dead() or e.hidden or e.escaped:
			continue
		var rec := rules.battler_record(e)
		exp_total += int(rec.get("exp", 0))
		gold += int(rec.get("gold", 0))
		for d in rec.get("drops", []):
			if rng.chance_percent(clampf(float(d.get("chance", 100)) * drop_rate, 0.0, 100.0)):
				var kind := str(d.get("kind", "item"))
				var id := str(d.get("id", ""))
				var merged := false
				for it in items:
					if it.kind == kind and it.id == id:
						it.count += 1
						merged = true
				if not merged:
					items.append({"kind": kind, "id": id, "count": 1})
	_rewards = {"exp": exp_total, "gold": int(gold * gold_rate), "items": items}
	return _rewards


## Gives the reward experience (or `amount` when it is >= 0, e.g. rewards changed by the victory
## hook) to every living actor. Returns [{actor, level_ups}].
func award_exp(amount := -1) -> Array:
	var out := []
	if amount < 0:
		amount = int(rewards().exp)
	for a in party:
		if a.is_alive():
			out.append({"actor": a, "level_ups": rules.gain_exp(a, amount)})
	return out


## Battle cleanup on every battler (battle-only states and flags).
func finish() -> String:
	for b in all_battlers():
		rules.end_battle(b)
	return battle_over()


## A skill's own message: %1 the user, %2 the target (its name, or "everyone" for several),
## %3 the skill. Without a message, the "use_skill" term.
func skill_message(b: RPGBattler, u: Dictionary, targets: Array) -> String:
	var msg := str(u.get("message", ""))
	if msg == "":
		return rules.term("use_skill", [b.name, u.name])
	var who := ""
	if targets.size() == 1:
		who = str(targets[0].name)
	elif targets.size() > 1:
		who = "everyone"
	return msg.replace("%1", b.name).replace("%2", who).replace("%3", str(u.get("name", "")))
