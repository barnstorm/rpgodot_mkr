@tool
class_name ShakeCamera
extends RPGCommand
## The custom command example from the design spec. It appears in the command picker under
## "screen" next to the built-ins, and in JSON as
## {"type": "shake_camera", "strength": 4.0, "seconds": 0.5, "wait": true}.


static func descriptor() -> Dictionary:
	return {
		"type": "shake_camera",
		"schema_version": 1,
		"category": "screen",
		"label": "Shake camera",
		"fields": [
			{"key": "strength", "kind": "float", "default": 4.0, "min": 0.0, "max": 32.0},
			{"key": "seconds", "kind": "float", "default": 0.5, "min": 0.05, "max": 10.0},
			{"key": "wait", "kind": "bool", "default": true},
		],
	}


func summary(args: Dictionary) -> String:
	return "Shake camera: %s for %s s" % [args.strength, args.seconds]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var done: Signal = ctx.screen.shake(args.strength, args.seconds)
	if args.wait:
		# Every wait goes through the context so it can be cancelled.
		var r := await ctx.wait_signal(done)
		if not r.ok:
			return RPGResult.cancelled()
	return RPGResult.ok()
