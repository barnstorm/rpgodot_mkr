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


static func describe_condition(c: Variant) -> String:
	if not (c is Dictionary):
		return "?"
	match c.get("kind", ""):
		"switch": return "Switch [%s] is %s" % [c.get("id", ""), "ON" if c.get("value", true) else "OFF"]
		"variable": return "Variable [%s] %s %s" % [c.get("id", ""), c.get("op", "=="), RPGCommand.describe_operand(c.get("value", 0))]
		"self_switch": return "Self Switch %s is %s" % [c.get("id", "A"), "ON" if c.get("value", true) else "OFF"]
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
			return "%s is %sin the party" % [who, "" if c.get("value", true) else "not "]
		"gold": return "Gold %s %s" % [c.get("op", ">="), RPGCommand.describe_operand(c.get("value", 0))]
		"vehicle":
			var v := str(c.get("id", c.get("vehicle", "")))
			return "Player is on foot" if v in ["", "none"] else "Player is riding the %s" % v
		"facing":
			var t := str(c.get("target", "player"))
			var subject: String = {"player": "Player", "this": "This event", "": "This event"}.get(t, "[%s]" % t)
			return "%s is facing %s" % [subject, c.get("facing", "down")]
		"button": return "Button %s is held down" % str(c.get("button", "ok")).to_upper()
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
