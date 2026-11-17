@tool
extends RPGCommand
## Show Choices. Each choice may be hidden while a switch is OFF ("show_switch") and greyed out
## while another is OFF ("enable_switch"); in JSON also by any condition ("show_if",
## "enable_if"). Choices without them always show, as before. A choice with an empty label is
## not shown, as in RPG Maker. Branches belong to the choices as listed; "When cancelled" is
## Disallow, one choice of the list ("choice" + "cancel_choice", 0 = the first), the last choice
## that is shown, or a branch of its own. Cancel never takes a choice that is hidden or greyed
## out: it does nothing then, as with Disallow.


static func descriptor() -> Dictionary:
	return {
		"type": "show_choices", "schema_version": 1, "category": "message", "label": "Show Choices",
		"fields": [
			{"key": "choices", "kind": "list", "label": "Choices", "default": [{"label": "Yes", "then": []}, {"label": "No", "then": []}],
				"item_fields": [{"key": "label", "kind": "text", "label": "Label"}, {"key": "then", "kind": "commands", "label": "When chosen"},
					{"key": "show_switch", "kind": "ref", "ref": "switch", "default": "", "label": "Shown only while switch is ON", "help": "Empty: always shown."},
					{"key": "enable_switch", "kind": "ref", "ref": "switch", "default": "", "label": "Can be picked only while switch is ON", "help": "Empty: always enabled. Otherwise the choice is greyed out and buzzes."}]},
			{"key": "default", "kind": "int", "default": 0, "min": 0, "max": 9, "label": "Cursor starts on"},
			# A missing "cancel" still means disallow (stored commands keep their behaviour); a
			# command inserted in the editor starts on the last choice, RPG Maker's default.
			{"key": "cancel", "kind": "choice", "options": ["disallow", "choice", "last_choice", "branch"], "option_labels": ["Disallow", "A choice", "Last choice", "Branch"], "default": "disallow", "new_default": "last_choice", "label": "When cancelled"},
			{"key": "cancel_choice", "kind": "int", "default": 0, "min": 0, "max": 9, "label": "Cancel picks choice (0 = first)", "show_if": {"key": "cancel", "equals": "choice"}},
			{"key": "cancel_then", "kind": "commands", "default": [], "label": "On cancel", "show_if": {"key": "cancel", "equals": "branch"}},
		],
	}


func summary(args: Dictionary) -> String:
	# Each label in brackets, so a comma inside a label cannot be mistaken for a separator.
	var labels := PackedStringArray()
	for c in args.get("choices", []):
		labels.append("[%s]" % (str(c.get("label", "")) if c is Dictionary else str(c)))
	return "Choices: " + " ".join(labels)


func child_lists(args: Dictionary) -> Array:
	var out := []
	var choices: Array = args.get("choices", [])
	for i in choices.size():
		out.append({"label": "When [%s]" % choices[i].get("label", ""), "key": "choices/%d/then" % i, "list": choices[i].get("then", [])})
	if args.get("cancel", "disallow") == "branch":
		out.append({"label": "When cancelled", "key": "cancel_then", "list": args.get("cancel_then", [])})
	return out


## True when choice `c` is shown (`what` = "show") or can be picked ("enable").
static func choice_allowed(ctx: RPGContext, c: Variant, what: String) -> bool:
	if not (c is Dictionary):
		return true
	var sw := str(c.get(what + "_switch", ""))
	if sw != "" and not ctx.state.get_switch(sw):
		return false
	var cond: Variant = c.get(what + "_if")
	if cond is Dictionary and not cond.is_empty():
		return ctx.check_condition(cond)
	return true


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var choices: Array = args.get("choices", [])
	if choices.is_empty():
		return RPGResult.ok()
	# Shown choices: their labels, original indices and which are disabled.
	var labels := []
	var shown := []
	var disabled := []
	for i in choices.size():
		var c: Variant = choices[i]
		# RPG Maker does not show a choice whose text is empty.
		if (str(c.get("label", "")) if c is Dictionary else str(c)) == "":
			continue
		if not choice_allowed(ctx, c, "show"):
			continue
		if not choice_allowed(ctx, c, "enable"):
			disabled.append(shown.size())
		labels.append(str(c.get("label", "")) if c is Dictionary else str(c))
		shown.append(i)
	if shown.is_empty():
		return RPGResult.ok()
	var cancel: String = args.get("cancel", "disallow")
	var cancel_index := -1
	if cancel == "last_choice":
		cancel_index = shown.size() - 1
	elif cancel == "choice":
		cancel_index = shown.find(int(args.get("cancel_choice", 0)))
	elif cancel == "branch":
		cancel_index = shown.size()
	if disabled.has(cancel_index):
		cancel_index = -1
	var default_pos := maxi(shown.find(int(args.get("default", 0))), 0)
	var box: Control = ctx.ui.message_box
	var params := {"default": default_pos, "cancel_index": cancel_index}
	# The running event rides along so \E[name] in a label can read this event's self variable.
	params["_event_map"] = ctx.map_id()
	params["_event_id"] = ctx.event_id()
	if not disabled.is_empty():
		params["disabled"] = disabled
	box.open_choices(labels, params)
	var r := await ctx.wait_signal(box.choice_made)
	box.hide_box()
	if not r.ok:
		return RPGResult.cancelled()
	var pos: int = int(r.value)
	var idx: int = shown[pos] if pos >= 0 and pos < shown.size() else (choices.size() if pos == shown.size() else -1)
	if idx >= 0 and idx < choices.size():
		return await ctx.run_list(choices[idx].get("then", []), "choice %d" % idx)
	if idx == choices.size():
		return await ctx.run_list(args.get("cancel_then", []), "cancel")
	return RPGResult.ok()
