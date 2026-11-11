@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "input_number", "schema_version": 1, "category": "message", "label": "Input Number",
		"fields": [
			{"key": "variable", "kind": "ref", "ref": "variable", "label": "Store in", "required": true},
			{"key": "digits", "kind": "int", "default": 3, "min": 1, "max": 8, "label": "Digits"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Input Number: [%s], %d digits" % [args.get("variable", "?"), int(args.get("digits", 3))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var box: Control = ctx.ui.message_box
	var initial := 0
	if ctx.state.variable_type(args.variable) == "int":
		initial = int(ctx.state.get_variable(args.variable))
	box.open_number(int(args.digits), initial)
	var r := await ctx.wait_signal(box.number_entered)
	box.hide_box()
	if not r.ok:
		return RPGResult.cancelled()
	ctx.state.set_variable(args.variable, int(r.value))
	return RPGResult.ok()
