@tool
extends RPGCommand
## Pause time (lighting plugin): stops or restarts the game clock (saved with the game).


static func descriptor() -> Dictionary:
	return {
		"type": "pause_time", "schema_version": 1, "category": "lighting", "label": "Pause time",
		"fields": [
			{"key": "action", "kind": "choice", "options": ["pause", "resume"], "option_labels": ["Stop the clock", "Start it again"], "default": "pause", "label": "Clock"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Clock: %s" % ("stopped" if str(args.get("action", "pause")) == "pause" else "running")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var l: Object = ctx.rpg.extension("lighting")
	if l == null:
		return RPGResult.error("Pause time: the Lighting plugin is not running.")
	l.set_paused(str(args.get("action", "pause")) == "pause")
	return RPGResult.ok()
