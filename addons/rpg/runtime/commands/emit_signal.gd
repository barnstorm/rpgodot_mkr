@tool
extends RPGCommand
## For programmers: emits RPG.event_signal(name, args), which any script can connect to:
##   RPG.event_signal.connect(func(name, args): ...)


static func descriptor() -> Dictionary:
	return {
		"type": "emit_signal", "schema_version": 1, "category": "godot", "label": "Emit Signal",
		"fields": [
			{"key": "signal", "kind": "text", "default": "", "label": "Signal name", "required": true},
			{"key": "args", "kind": "object", "default": {}, "label": "Arguments", "fields": []},
		],
	}


func summary(args: Dictionary) -> String:
	return "Emit Signal: %s" % args.get("signal", "?")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	ctx.rpg.event_signal.emit(str(args.get("signal", "")), args.get("args", {}))
	return RPGResult.ok()
