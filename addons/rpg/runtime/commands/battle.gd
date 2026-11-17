@tool
extends RPGCommand
## Starts a battle using the project's battle scene (or one chosen here). Every battle scene follows
## one contract: start(args, context) then finished({outcome: win|lose|escape, rewards}) or
## cancelled(reason). Branches run for win, escape and lose.


static func descriptor() -> Dictionary:
	return {
		"type": "battle", "schema_version": 1, "category": "scenes", "label": "Battle Processing",
		"fields": [
			{"key": "troop_source", "kind": "choice", "options": ["troop", "variable", "encounter"], "option_labels": ["Enemy group", "Enemy group named by a variable", "Random encounter (this map)"], "default": "troop", "label": "Enemy group source"},
			{"key": "troop", "kind": "ref", "ref": "troop", "label": "Enemy group", "required": true, "show_if": {"key": "troop_source", "equals": ["troop", null]}},
			{"key": "variable", "kind": "ref", "ref": "variable", "label": "Variable", "required": true, "show_if": {"key": "troop_source", "equals": "variable"}},
			{"key": "can_escape", "kind": "bool", "default": true, "label": "Can escape"},
			{"key": "can_lose", "kind": "bool", "default": false, "label": "Continue when lost"},
			{"key": "scene", "kind": "resource", "res": "scene", "default": "", "label": "Battle scene (blank = default)"},
			{"key": "background", "kind": "resource", "res": "backdrop", "default": "", "label": "Background (blank = map's)"},
			{"key": "advantage", "kind": "choice", "options": ["normal", "preemptive", "surprise", "initiative", "back_attack", "surround", "pincer"], "option_labels": ["Normal", "Preemptive (party first)", "Surprise (enemies first)", "Initiative (party gauges full, 2003)", "Back attack (enemy gauges full, mirrored, 2003)", "Surround (party gauges full, packed centre, 2003)", "Pincer (enemy gauges full, split, no escape, 2003)"], "default": "normal", "label": "Advantage"},
			{"key": "result", "kind": "ref", "ref": "variable", "default": "", "label": "Store outcome in"},
			{"key": "on_win", "kind": "commands", "default": [], "label": "If won"},
			{"key": "on_escape", "kind": "commands", "default": [], "label": "If escaped", "show_if": {"key": "can_escape", "equals": true}},
			{"key": "on_lose", "kind": "commands", "default": [], "label": "If lost", "show_if": {"key": "can_lose", "equals": true}},
		],
	}


func summary(args: Dictionary) -> String:
	match str(args.get("troop_source", "troop")):
		"variable":
			return "Battle: group V[%s]" % args.get("variable", "?")
		"encounter":
			return "Battle: random encounter"
	return "Battle: %s" % args.get("troop", "?")


func child_lists(args: Dictionary) -> Array:
	var out := [{"label": "If won", "key": "on_win", "list": args.get("on_win", [])}]
	if args.get("can_escape", true):
		out.append({"label": "If escaped", "key": "on_escape", "list": args.get("on_escape", [])})
	if args.get("can_lose", false):
		out.append({"label": "If lost", "key": "on_lose", "list": args.get("on_lose", [])})
	return out


## The System's defeat handler (#39): a common event (and optional transfer) that takes the place
## of Game Over when the party loses. "" when the game has none, or it names no common event.
static func defeat_event_id(ctx: RPGContext) -> String:
	return RPGPartyUtil.defeat_event_id(ctx)


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	# Where the group comes from (#38): picked here, named by a variable, or the same roll a
	# random encounter on this map would make.
	var troop := ""
	match str(args.get("troop_source", "troop")):
		"variable":
			troop = str(ctx.state.get_variable(str(args.get("variable", ""))))
			if troop == "":
				return RPGResult.error("Battle: variable '%s' holds no enemy group." % args.get("variable", "?"))
		"encounter":
			if ctx.map == null or ctx.map.player == null:
				return RPGResult.error("Battle: no map is running, so there is no encounter list to roll from.")
			var g: Dictionary = RPGPlayer.pick_encounter_group(ctx.map.props, ctx.map.region_at(ctx.map.player.cell), ctx.rpg.rng)
			if g.is_empty():
				return RPGResult.error("Battle: map '%s' has no encounter group here." % ctx.map_id())
			troop = str(g.troop)
		_:
			troop = str(args.get("troop", ""))
	if not ctx.data.has_record("troops", troop):
		return RPGResult.error("Battle: enemy group '%s' does not exist." % troop)
	var scene := str(args.get("scene", ""))
	if scene == "" and ctx.map != null:
		scene = str(ctx.map.props.get("battle_scene", ""))
	if scene == "":
		scene = str(ctx.data.system.get("battle_scene", ctx.data.system.get("default_battle_scene", "")))
	if scene == "" or not ResourceLoader.exists(scene):
		scene = ctx.ui.scene_path("battle")
	var bg := str(args.get("background", ""))
	if bg == "" and ctx.map != null:
		var mb: Variant = ctx.map.props.get("battle_background", "auto")
		if mb is String and mb != "auto":
			bg = mb
		elif mb is Dictionary:
			bg = str(mb.get("image", ""))
	var bargs := {"troop": troop, "can_escape": args.get("can_escape", true), "can_lose": args.get("can_lose", false), "background": bg}
	var adv := str(args.get("advantage", "normal"))
	if adv in ["preemptive", "surprise"] + RPGBattleCore.START_CONDITIONS:
		bargs["advantage"] = adv
	# The map's music and background sound are saved with their positions and come back where
	# they were after the battle (MV's saveBgmAndBgs / replayBgmAndBgs). The scene gets them as
	# context.map_bgm so it can bring the map music back during the victory jingle.
	var saved_bgm: Dictionary = ctx.audio.save_bgm() if ctx.audio.has_method("save_bgm") else ctx.audio.current_bgm.duplicate()
	var saved_bgs: Dictionary = ctx.audio.save_bgs() if ctx.audio.has_method("save_bgs") else {}
	var context := {"rpg": ctx.rpg, "state": ctx.state, "rules": ctx.rpg.rules, "interpreter": ctx.interpreter, "map_bgm": saved_bgm, "map_bgs": saved_bgs}
	ctx.audio.play_role("battle_start")
	if not saved_bgs.is_empty() and ctx.audio.has_method("stop_bgs"):
		ctx.audio.stop_bgs()
	# Extension hooks (RPG.battle_started / battle_ended): emitted here, outside the battle scene,
	# so they work with any battle scene.
	ctx.state.bump_counter("battles")
	if ctx.rpg.has_signal("battle_started"):
		ctx.rpg.battle_started.emit(bargs.duplicate())
	# The battle moment hooks run right here (a queued run would only get its turn after the
	# battle): each hooked common event finishes before the scene starts (issue #52).
	if ctx.rpg.has_method("run_hook_common_events"):
		await ctx.rpg.run_hook_common_events("on_battle_start", {"troop": troop, "map": ctx.map_id()})
	var r: Dictionary = await ctx.ui.run_contract_scene(scene, bargs, context, ctx.token, 0.0, true, "battle")
	var res0: Variant = r.get("value")
	if ctx.rpg.has_signal("battle_ended"):
		var oc := ""
		if r.status == "finished":
			oc = str(res0.get("outcome", "win")) if res0 is Dictionary else str(res0)
		ctx.rpg.battle_ended.emit(oc, res0)
	if ctx.rpg.has_method("check_levels"):
		ctx.rpg.check_levels()
	# After the level-up hooks (the party grows, then the battle is officially over), the battle
	# end moment runs its hooked common events (issue #52).
	if ctx.rpg.has_method("run_hook_common_events"):
		var oc2 := ""
		if r.status == "finished":
			oc2 = str(res0.get("outcome", "win")) if res0 is Dictionary else str(res0)
		await ctx.rpg.run_hook_common_events("on_battle_end", {"outcome": oc2, "map": ctx.map_id()})
	var lost: bool = r.status == "finished" and (str(res0.get("outcome", "")) if res0 is Dictionary else str(res0)) == "lose"
	var defeat_ev := defeat_event_id(ctx)
	if lost and not bool(args.get("can_lose", false)) and defeat_ev == "":
		# Game over follows: the defeat jingle plays on, and no map music comes back.
		ctx.audio.stop_bgm()
	elif ctx.audio.has_method("replay_bgm"):
		ctx.audio.replay_bgm(saved_bgm)
		ctx.audio.replay_bgs(saved_bgs)
	elif not saved_bgm.is_empty():
		ctx.audio.play_bgm(saved_bgm)
	if r.status == "error":
		return RPGResult.error("Battle scene error: %s" % str(r.value))
	if r.status != "finished":
		return RPGResult.cancelled() if ctx.is_cancelled() else RPGResult.ok()
	var res: Variant = r.value
	var outcome := str(res.get("outcome", "win")) if res is Dictionary else str(res)
	# Game Data play counters: one battle resolved, and how it ended (RM2000's Other: wins, defeats,
	# escapes). A battle that was cancelled mid-run counts as fought but not as any outcome.
	match outcome:
		"win":
			ctx.state.bump_counter("victories")
		"lose":
			ctx.state.bump_counter("defeats")
		"escape":
			ctx.state.bump_counter("escapes")
	if str(args.get("result", "")) != "":
		ctx.state.set_variable(str(args.result), outcome)
	match outcome:
		"win":
			return await ctx.run_list(args.get("on_win", []), "on_win")
		"escape":
			return await ctx.run_list(args.get("on_escape", []), "on_escape")
		"lose":
			if args.get("can_lose", false):
				return await ctx.run_list(args.get("on_lose", []), "on_lose")
			# The defeat handler (2003) takes the place of Game Over: the party is sent to the
			# map the System names (if any), the common event runs (an inn, a "you blacked out
			# and crawled back" scene), and the game goes on.
			if defeat_ev != "":
				return await RPGPartyUtil.run_defeat_handler(ctx, defeat_ev)
			if ctx.rpg.game != null:
				ctx.rpg.game.game_over.call_deferred()
			return RPGResult.flow_exit()
	return RPGResult.ok()
