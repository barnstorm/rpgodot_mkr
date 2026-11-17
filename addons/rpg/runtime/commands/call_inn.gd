@tool
extends RPGCommand
## Call Inn: the whole RPG Maker inn stay as one command. Shows the ask message (one of the two
## System styles, like RM2003's inn patterns), asks Yes/No, and on Yes with enough gold takes the
## price, fades out, plays the inn jingle (ME), recovers the party with Recover All semantics and
## fades back in. "No", cancelling, and not having the price all take the didn't-stay branch, the
## last after the System can't-afford message.


static func descriptor() -> Dictionary:
	return {
		"type": "call_inn", "schema_version": 1, "category": "party", "label": "Call Inn",
		"fields": [
			{"key": "price", "kind": "operand", "default": 0, "min": 0, "label": "Price"},
			{"key": "style", "kind": "choice", "options": ["1", "2"], "option_labels": ["Message style 1", "Message style 2"],
				"default": "1", "label": "Message style", "help": "Which of the System's two inn messages to ask with (Terms > inn_1 / inn_2)."},
			{"key": "message", "kind": "multiline", "default": "", "label": "Ask text",
				"help": "Empty: the System term for the style. %1 is the price, \\G the currency unit."},
			{"key": "no_gold_message", "kind": "multiline", "default": "", "label": "Not enough gold text",
				"help": "Empty: the System term (Terms > inn_no_gold)."},
			{"key": "jingle", "kind": "sound", "res": "music", "res_also": ["sound"],
				"default": {"file": "", "volume": 100, "pitch": 100, "pan": 0}, "label": "Jingle",
				"help": "Empty: the System inn jingle (the inn_rest sound role)."},
			{"key": "gold_window", "kind": "bool", "default": true, "label": "Show gold window while asking"},
			{"key": "stayed", "kind": "commands", "default": [], "label": "When the party stays"},
			{"key": "left", "kind": "commands", "default": [], "label": "When they don't stay"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Inn: %s \\G (style %s)" % [RPGCommand.describe_operand(args.get("price", 0)), str(args.get("style", "1"))]


func child_lists(args: Dictionary) -> Array:
	return [
		{"label": "When the party stays", "key": "stayed", "list": args.get("stayed", [])},
		{"label": "When they don't stay", "key": "left", "list": args.get("left", [])},
	]


## The ask or can't-afford text: a per-call override, else the System term. Either way %1 is
## the price and \G the currency unit.
func _text(ctx: RPGContext, key: String, price: int, override: String) -> String:
	if override != "":
		var t := override.replace("%1", str(price))
		if t.contains("\\G"):
			var unit := "G"
			if ctx.data != null and ctx.data.has_method("currency"):
				unit = str(ctx.data.currency())
			return t.replace("\\G", unit)
		return t
	var rules: Variant = ctx.rpg.rules
	if rules != null and rules.has_method("inn_term"):
		return str(rules.inn_term(key, [price]))
	return override


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var price := int(ctx.operand(args.get("price", 0)))
	var style := str(args.get("style", "1"))
	var box: Control = ctx.ui.message_box

	# The ask message, then the Yes/No choice (cancel counts as No, as at an RM inn).
	var p := {"text": _text(ctx, style, price, str(args.get("message", ""))),
		"gold_window": bool(args.get("gold_window", true))}
	p["_event_map"] = ctx.map_id()
	p["_event_id"] = ctx.event_id()
	box.open_text(p)
	var r := await ctx.wait_signal(box.closed)
	if not r.ok:
		box.force_close()
		return RPGResult.cancelled()
	box.open_choices(["Yes", "No"], {"default": 0, "cancel_index": 1})
	var c := await ctx.wait_signal(box.choice_made)
	box.hide_box()
	if not c.ok:
		return RPGResult.cancelled()
	if int(c.value) != 0:
		return await ctx.run_list(args.get("left", []), "inn left")

	# Staying: the price first, and the System message when it can't be paid.
	if ctx.state.gold < price:
		var sorry := _text(ctx, "no_gold", price, str(args.get("no_gold_message", "")))
		var p2 := {"text": sorry}
		p2["_event_map"] = ctx.map_id()
		p2["_event_id"] = ctx.event_id()
		box.open_text(p2)
		var r2 := await ctx.wait_signal(box.closed)
		if not r2.ok:
			box.force_close()
			return RPGResult.cancelled()
		box.hide_box()
		return await ctx.run_list(args.get("left", []), "inn left")
	if price > 0:
		ctx.state.change_gold("decrease", price)

	# The stay: lights out, jingle, a full recovery (Recover All), lights on.
	ctx.screen.set_meta("hold_fade", true)
	var f := await ctx.wait_signal(ctx.screen.fade_out(0.5, Color.BLACK))
	if not f.ok:
		return RPGResult.cancelled()
	var jingle: Dictionary = args.get("jingle", {})
	if str(jingle.get("file", "")) == "" and not jingle.has("role"):
		jingle = {"role": "inn_rest"}
	var m := await ctx.wait_signal(ctx.audio.play_me(jingle))
	if not m.ok:
		return RPGResult.cancelled()
	var recover: RPGCommand = ctx.rpg.registry.get_command("recover_all")
	if recover == null:
		return RPGResult.error("Call Inn: the Recover All command is unavailable.")
	var rec := await recover.run(ctx, {"target": "party"})
	if rec.is_error():
		return rec
	ctx.screen.set_meta("hold_fade", false)
	var f2 := await ctx.wait_signal(ctx.screen.fade_in(0.5))
	if not f2.ok:
		return RPGResult.cancelled()
	return await ctx.run_list(args.get("stayed", []), "inn stayed")
