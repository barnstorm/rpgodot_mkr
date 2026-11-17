@tool
extends RPGCommand
## RPG Maker 2003's "Control Timer": sets one of the two countdown timers — the time and the
## display options — starts it counting down, or stops it (it holds where it is). The timer runs
## on the map, the Timer condition checks the time left, and what it does in a battle is one of
## the Set options: pause, keep counting, or end the battle (no rewards) when it reaches 0.


static func descriptor() -> Dictionary:
	return {
		"type": "control_timer", "schema_version": 1, "category": "state", "label": "Control Timer",
		"fields": [
			{"key": "timer", "kind": "choice", "default": "1", "options": ["1", "2"],
				"option_labels": ["Timer 1", "Timer 2"], "label": "Timer"},
			{"key": "operation", "kind": "choice", "default": "set", "options": ["set", "start", "stop"],
				"option_labels": ["Set", "Start", "Stop"], "label": "Operation"},
			{"key": "seconds", "kind": "operand", "default": 60, "min": 0, "max": 5999, "label": "Time (seconds)",
				"show_if": {"key": "operation", "equals": "set"}},
			{"key": "visible", "kind": "bool", "default": true, "label": "Show on screen",
				"show_if": {"key": "operation", "equals": "set"}},
			{"key": "position", "kind": "choice", "default": "top_right",
				"options": ["top_right", "top_left", "bottom_left", "bottom_right"],
				"option_labels": ["Top right", "Top left", "Bottom left", "Bottom right"], "label": "Position",
				"show_if": {"key": "operation", "equals": "set"}},
			{"key": "battle", "kind": "choice", "default": "pause", "options": ["pause", "count", "abort"],
				"option_labels": ["Pause in battle", "Keep counting in battle", "Abort battle at 0"],
				"label": "In battle", "show_if": {"key": "operation", "equals": "set"}},
		],
	}


func summary(args: Dictionary) -> String:
	var t := "Timer %s" % str(args.get("timer", "1"))
	match str(args.get("operation", "set")):
		"start":
			return "%s: Start" % t
		"stop":
			return "%s: Stop" % t
	var shown := "" if args.get("visible", true) else ", hidden"
	return "%s: Set %s s%s" % [t, RPGCommand.describe_operand(args.get("seconds", 60)), shown]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("timer", "1"))
	match str(args.get("operation", "set")):
		"start":
			ctx.state.start_timer(id)
		"stop":
			ctx.state.stop_timer(id)
		_:
			var secs: Variant = ctx.operand(args.get("seconds", 60))
			ctx.state.set_timer(id, float(secs), bool(args.get("visible", true)),
				str(args.get("position", "top_right")), str(args.get("battle", "pause")))
	return RPGResult.ok()
