@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {
		"type": "comment", "schema_version": 1, "category": "flow", "label": "Comment",
		"fields": [{"key": "text", "kind": "multiline", "default": "", "label": "Comment"}],
	}


func summary(args: Dictionary) -> String:
	return "// " + str(args.get("text", "")).replace("\n", " / ")


func run(_ctx: RPGContext, _args: Dictionary) -> RPGResult:
	return RPGResult.ok()
