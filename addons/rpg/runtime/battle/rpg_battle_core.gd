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
## "normal", "preemptive" (the party gets the first move) or "surprise" (the enemies do).
var advantage := "normal"
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
## Called with (condition) -> bool for troop page condition kinds the core does not know
## (extension kinds marked "battle": true, see the battle scene). Unset: such a page never runs.
var condition_reader: Callable
## Called with (item_id) to give back an item whose action a hook cancelled or replaced.
var item_refund: Callable
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
var _forced := false          ## the result came from force_result()


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
		# "Slime A", "Slime B" when an enemy appears more than once.
		if int(counts[b.id]) > 1:
			var n := int(seen.get(b.id, 0))
			seen[b.id] = n + 1
			b.name = "%s %s" % [b.name, char(65 + n % 26)]
		enemies.append(b)
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
	turn = 0
	escape_attempts = 0
	phase = "idle"
	_result = ""
	_forced = false
	_rewards = {}
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
	if is_timed() or (turn == 1 and advantage == "surprise"):
		return out
	for i in party.size():
		var b: RPGBattler = party[i]
		if b.is_active() and rules.can_act(b):
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
			if not b.skills.has(str(action.get("skill", ""))) or not rules.can_use(b, action):
				return false
		"item":
			if rules.resolve_action(b, action).is_empty():
				return false
		_:
			return false
	b.action = action.duplicate(true)
	return true


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
			continue
		var before := _vitals()
		_hook("turn_started", [b])
		var result := _execute(b)
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
	# A preemptive strike or a surprise attack: the other side does nothing on turn 1.
	var enemies_act := not (turn == 1 and advantage == "preemptive")
	var party_acts := not (turn == 1 and advantage == "surprise")
	if enemies_act:
		for e in enemies:
			if e.is_active() and rules.can_act(e):
				e.action = choose_enemy_action(e)
	if party_acts:
		for a in party:
			if a.is_active() and rules.can_act(a) and a.action.is_empty():
				a.action = {"kind": "attack", "target": -1}
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
		var times := 1
		if str(e.b.action.get("kind", "")) != "escape":
			times = maxi(1, rules.action_times(e.b))
		for k in times:
			_queue.append(e.b)
	_queue_built = true


func _execute(b: RPGBattler) -> Dictionary:
	var action: Dictionary = b.action
	var kind := str(action.get("kind", "wait"))
	var res := {"user": b, "action": action, "kind": kind, "name": "", "targets": [], "effects": [],
		"lines": [], "text": "", "escaped": false, "battle_over": ""}
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
		_execute_usable(b, action, res)
	else:
		_execute_simple(b, kind, res)
	res.text = "\n".join(PackedStringArray(res.lines))
	return res


const USABLE_KINDS := ["attack", "skill", "item"]


## Guard, escape and wait (anything that is not attack, skill or item waits).
func _execute_simple(b: RPGBattler, kind: String, res: Dictionary) -> void:
	match kind:
		"guard":
			b.guarding = true
			res.lines.append(rules.term("guard", [b.name]))
		"escape":
			var e := attempt_escape()
			res.escaped = e.success
			res.lines.append_array(e.lines)
		_:
			res.lines.append(rules.term("wait", [b.name]))


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
	if given_targets is Array:
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
				_execute_simple(b, res.kind, res)
			return
		targets = (h.targets as Array).filter(func(t): return t is RPGBattler)
	rules.pay_cost(b, action)
	match kind:
		"attack":
			res.lines.append(rules.term("attack", [b.name]))
		"skill":
			res.lines.append(skill_message(b, u, targets))
		"item":
			res.lines.append(rules.term("use_item", [b.name, u.name]))
	res.targets = targets
	var repeats := 1
	if kind == "attack":
		repeats += int(rules.trait_sum(b, "extra_attack"))
	var filtered := hooks != null and "damage_filter" in rules
	if filtered:
		rules.damage_filter = _damage_hook
	for t in targets:
		for k in repeats:
			if k > 0 and not t.is_active():
				break
			var r := rules.apply_action(b, t, action)
			res.effects.append({"target": t, "result": r})
			res.lines.append_array(r.lines)
	if filtered:
		rules.damage_filter = Callable()
	# "Common Event" effects: run once after the action (the battle scene runs them).
	if kind != "attack" and rules.has_method("common_events"):
		var ces: Array = rules.common_events(b, action)
		if not ces.is_empty():
			res["common_events"] = ces


## Targets for a usable (resolved skill/item/attack) by its scope.
func resolve_targets(user: RPGBattler, usable: Dictionary, target_index: int) -> Array:
	var friends: Array = party if user.is_actor() else enemies
	var foes: Array = enemies if user.is_actor() else party
	var alive_foes := foes.filter(func(x): return x.is_active())
	var alive_friends := friends.filter(func(x): return x.is_active())
	var dead_friends := friends.filter(func(x): return x.is_dead() and not x.hidden and not x.escaped)
	match str(usable.get("scope", "one_enemy")):
		"one_enemy":
			if target_index >= 0 and target_index < foes.size() and foes[target_index].is_active():
				return [foes[target_index]]
			return [] if alive_foes.is_empty() else [rng.pick(alive_foes)]
		"all_enemies":
			return alive_foes
		"random_enemy":
			return [] if alive_foes.is_empty() else [rng.pick(alive_foes)]
		"one_ally":
			if target_index >= 0 and target_index < friends.size() and friends[target_index].is_active():
				return [friends[target_index]]
			return [user] if user.is_active() else []
		"all_allies":
			return alive_friends
		"one_dead_ally":
			if target_index >= 0 and target_index < friends.size() and friends[target_index].is_dead():
				return [friends[target_index]]
			return [] if dead_friends.is_empty() else [dead_friends[0]]
		"all_dead_allies":
			return dead_friends
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
	return {"preemptive": 0.05 if quick else 0.03, "surprise": 0.03 if quick else 0.05}


static func _average_speed(p_rules: RPGRuleSystem, list: Array) -> float:
	if list.is_empty() or p_rules == null or not p_rules.has_method("atb_speed"):
		return 0.0
	var total := 0.0
	for b in list:
		total += float(p_rules.atb_speed(b))
	return total / list.size()


## Gauges at battle start: ATB_START plus a small random offset; a preemptive strike fills the
## party's gauges (the enemies start empty), a surprise attack the enemies'.
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
		if advantage == "preemptive":
			g = 1.0 if b.is_actor() else 0.0
		elif advantage == "surprise":
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
	return b != null and b.is_actor() and ready_queue.has(b) and b.is_active() and rules.can_act(b) and b.action.is_empty()


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
		res = {"user": b, "action": {"kind": "wait", "silent": true}, "kind": "wait", "name": "", "targets": [],
			"effects": [], "lines": [], "text": "", "escaped": false, "battle_over": ""}
	else:
		_hook("turn_started", [b])
		if b.is_enemy():
			b.action = choose_enemy_action(b)
		elif b.action.is_empty():
			b.action = {"kind": "attack", "target": -1}
		if not _extra.has(b):
			_extra[b] = 0 if str(b.action.get("kind", "")) == "escape" else maxi(1, rules.action_times(b)) - 1
		res = _execute(b)
	res["skipped"] = skipped
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

## Picks an action from the enemy record's "actions": [{skill, rating, condition}].
## skill "attack" / "guard" / "wait" are the basic commands. Among usable actions whose
## condition holds, those rated within 2 of the best are picked, weighted by how close they are.
func choose_enemy_action(e: RPGBattler) -> Dictionary:
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


func _enemy_action_dict(a: Dictionary) -> Dictionary:
	var sk := str(a.get("skill", "attack"))
	match sk:
		"attack", "guard", "wait":
			return {"kind": sk, "target": -1}
	return {"kind": "skill", "skill": sk, "target": -1}


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
		"switch":
			return _switch_is(str(c.get("id", "")), bool(c.get("value", true)))
	return false


# --------------------------------------------------------------------------------------------
# Battle events
# --------------------------------------------------------------------------------------------

## Troop battle pages eligible at this checkpoint, highest priority first, then page order.
## Page: {id, conditions: [...], span: "once_per_battle"|"once_per_turn"|"every_check",
##        priority, commands, at?: [checkpoint kinds]}
## Conditions (all must hold; a page with no conditions never runs):
##   {kind: "turn", n, every}            turn == n, or turn >= n and (turn - n) % every == 0
##   {kind: "enemy_hp", index, op, percent}
##   {kind: "actor_hp", id, op, percent}
##   {kind: "switch", id, value?: true}
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
		if not page_conditions_met(p):
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


func page_conditions_met(p: Dictionary) -> bool:
	var conds: Array = p.get("conditions", [])
	if conds.is_empty():
		return false
	for c in conds:
		if not _page_condition(c):
			return false
	return true


func _page_condition(c: Dictionary) -> bool:
	match str(c.get("kind", "")):
		"turn":
			return _turn_matches(int(c.get("n", 0)), int(c.get("every", 0)))
		"enemy_hp":
			var idx := int(c.get("index", 0))
			for e in enemies:
				if e.index == idx:
					return not e.hidden and _compare(_hp_percent(e), str(c.get("op", "<=")), float(c.get("percent", 100)))
			return false
		"actor_hp":
			for a in party:
				if a.id == str(c.get("id", "")):
					return _compare(_hp_percent(a), str(c.get("op", "<=")), float(c.get("percent", 100)))
			return false
		"switch":
			return _switch_is(str(c.get("id", "")), bool(c.get("value", true)))
	# Other kinds (extension kinds marked "battle": true): the battle scene asks the game state.
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


func _switch_is(id: String, value: bool) -> bool:
	if not switch_reader.is_valid():
		return false
	return bool(switch_reader.call(id)) == value


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
	for e in enemies:
		if not e.is_dead() or e.hidden:
			continue
		var rec := rules.battler_record(e)
		exp_total += int(rec.get("exp", 0))
		gold += int(rec.get("gold", 0))
		for d in rec.get("drops", []):
			if rng.chance_percent(float(d.get("chance", 100))):
				var kind := str(d.get("kind", "item"))
				var id := str(d.get("id", ""))
				var merged := false
				for it in items:
					if it.kind == kind and it.id == id:
						it.count += 1
						merged = true
				if not merged:
					items.append({"kind": kind, "id": id, "count": 1})
	_rewards = {"exp": exp_total, "gold": gold, "items": items}
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
