@tool
extends RPGCommand
## RPG Maker's "End Battle" / "Abort Battle": ends the battle that is running from a battle
## event (an enemy group's battle events, or a common event they call). Battle events only;
## anywhere else nothing happens and the validator warns. The Battle Processing command that
## started the fight continues down the branch that matches the result.


static func descriptor() -> Dictionary:
	return {
		"type": "abort_battle", "schema_version": 1, "category": "scenes", "label": "End Battle",
		"battle_only": true,
		"fields": [
			{"key": "result", "kind": "choice", "options": ["abort", "win", "lose"],
				"option_labels": ["Abort (no rewards, like an escape)", "Win", "Lose"],
				"default": "abort", "label": "Result"},
			{"key": "award_rewards", "kind": "bool", "default": true, "label": "Give victory rewards",
				"show_if": {"key": "result", "equals": "win"}},
		],
	}


func summary(args: Dictionary) -> String:
	match str(args.get("result", "abort")):
		"win":
			return "End Battle: win%s" % ("" if args.get("award_rewards", true) else " (no rewards)")
		"lose":
			return "End Battle: lose"
	return "End Battle: abort"


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var facade: RPGBattleFacade = ctx.battle
	if facade == null or not facade.valid():
		push_warning("End Battle: no battle is running; nothing happens.")
		return RPGResult.ok()
	match str(args.get("result", "abort")):
		"win":
			facade.end("win", bool(args.get("award_rewards", true)))
		"lose":
			facade.end("lose")
		_:
			facade.end("escape")
	return RPGResult.ok()
