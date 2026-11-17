@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "if", "schema_version": 1, "category": "flow", "label": "Conditional Branch",
		"fields": [
			{"key": "condition", "kind": "condition", "label": "If", "default": {"kind": "switch", "id": ""}, "required": true},
			{"key": "then", "kind": "commands", "label": "Then", "default": []},
			{"key": "else", "kind": "commands", "label": "Else", "default": []},
		],
	}


## "[this event]", "[chest]" or "[chest] on [town]" for a self switch/variable condition. Blank
## and "this" mean the event (and map) the condition belongs to.
static func _self_owner_text(c: Dictionary) -> String:
	var ev := str(c.get("event", ""))
	var who := "[%s]" % ("this event" if ev == "" or ev == "this" else ev)
	var mp := str(c.get("map", ""))
	if mp != "" and mp != "this":
		who = "%s on [%s]" % [who, mp]
	return who


static func describe_condition(c: Variant) -> String:
	if not (c is Dictionary):
		return "?"
	match c.get("kind", ""):
		"switch": return "Switch [%s] is %s" % [c.get("id", ""), "ON" if c.get("value", true) else "OFF"]
		"variable": return "Variable [%s] %s %s" % [c.get("id", ""), c.get("op", "=="), RPGCommand.describe_operand(c.get("value", 0))]
		"self_switch":
			return "Self Switch %s of %s is %s" % [c.get("id", "A"), _self_owner_text(c), "ON" if c.get("value", true) else "OFF"]
		"self_variable":
			return "Self variable %s.%s %s %s" % [_self_owner_text(c), c.get("name", ""), c.get("op", "=="), RPGCommand.describe_operand(c.get("value", 0))]
		"item": return "Party has [%s]%s" % [c.get("id", ""), (" x%d" % int(c.count)) if typeof(c.get("count")) in [TYPE_INT, TYPE_FLOAT] and int(c.count) > 1 else ""]
		"actor":
			var who := "[%s]" % c.get("id", "")
			match str(c.get("check", "in_party")):
				"name": return "%s is named \"%s\"" % [who, c.get("name", "")]
				"class": return "%s is class [%s]" % [who, c.get("class", "")]
				"skill": return "%s has learned [%s]" % [who, c.get("skill", "")]
				"weapon": return "%s has [%s] equipped" % [who, c.get("weapon", "")]
				"armor": return "%s has [%s] equipped" % [who, c.get("armor", "")]
				"state": return "%s is affected by [%s]" % [who, c.get("state", "")]
				"level": return "%s's level %s %s" % [who, c.get("op", ">="), RPGCommand.describe_operand(c.get("value", 1))]
				"hp", "sp":
					var unit := "%" if c.get("percent", false) else ""
					return "%s's %s %s %s%s" % [who, "HP" if c.get("check") == "hp" else "SP", c.get("op", ">="), RPGCommand.describe_operand(c.get("value", 1)), unit]
			return "%s is %sin the party" % [who, "" if c.get("value", true) else "not "]
		"gold": return "Gold %s %s" % [c.get("op", ">="), RPGCommand.describe_operand(c.get("value", 0))]
		"timer": return "Timer %s %s %s s" % [c.get("timer", "1"), c.get("op", "<="), RPGCommand.describe_operand(c.get("seconds", 0))]
		"vehicle":
			var v := str(c.get("id", c.get("vehicle", "")))
			return "Player is on foot" if v in ["", "none"] else "Player is riding the %s" % v
		"facing":
			var t := str(c.get("target", "player"))
			var subject: String = {"player": "Player", "this": "This event", "": "This event"}.get(t, "[%s]" % t)
			return "%s is facing %s" % [subject, c.get("facing", "down")]
		"button":
			var b := "Button %s" % str(c.get("button", "ok")).to_upper()
			match str(c.get("mode", "held")):
				"pressed": return "%s was just pressed" % b
				"repeated": return "%s is held down (repeating)" % b
			return "%s is held down" % b
		"started_by":
			var labels := {"action_button": "the action button", "player_touch": "the player touching it",
				"event_touch": "it touching the player", "autorun": "autorun", "parallel": "parallel", "call": "Call Event"}
			return "This event was started by %s" % labels.get(str(c.get("by", "action_button")), str(c.get("by", "action_button")))
		"formula": return "Formula: %s" % str(c.get("text", "")).strip_edges()
		"can_pass":
			var cp_t := str(c.get("target", "player"))
			var cp_subject: String = {"player": "Player", "this": "This event", "": "This event"}.get(cp_t, "[%s]" % cp_t)
			return "%s can step %s %d cell%s" % [cp_subject, c.get("facing", "down"), int(c.get("distance", 1)), "s" if int(c.get("distance", 1)) != 1 else ""]
		"turn":
			return ("Turn is %d, then every %d" % [int(c.get("n", 0)), int(c.get("every", 0))]) if int(c.get("every", 0)) > 0 else "Turn is %d" % int(c.get("n", 0))
		"enemy_hp": return "Enemy #%d HP %s %d%%" % [int(c.get("index", 0)) + 1, c.get("op", "<="), int(c.get("percent", 100))]
		"actor_hp": return "[%s] HP %s %d%%" % [c.get("id", ""), c.get("op", "<="), int(c.get("percent", 100))]
		"actor_can_act": return "[%s] can act" % c.get("id", "")
		"enemy_can_act": return "Enemy #%d can act" % (int(c.get("index", 0)) + 1)
		"enemy_is_target": return "Enemy #%d is the target" % (int(c.get("index", 0)) + 1)
		"all": return "All of %d conditions" % c.get("conditions", []).size()
		"any": return "Any of %d conditions" % c.get("conditions", []).size()
		"not": return "Not (%s)" % describe_condition(c.get("condition"))
	return str(c.get("kind", "?"))


func summary(args: Dictionary) -> String:
	return "If: " + describe_condition(args.get("condition"))


func child_lists(args: Dictionary) -> Array:
	return [{"label": "Then", "key": "then", "list": args.get("then", [])}, {"label": "Else", "key": "else", "list": args.get("else", [])}]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var cond: Variant = args.get("condition")
	if not (cond is Dictionary):
		return RPGResult.error("Conditional Branch has no condition.")
	if ctx.check_condition(cond):
		return await ctx.run_list(args.get("then", []), "then")
	return await ctx.run_list(args.get("else", []), "else")
