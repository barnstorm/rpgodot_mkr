@tool
extends RPGCommand
## RPG Maker's "Label": a named place in this event's commands that Jump to Label goes to.


static func descriptor() -> Dictionary:
	return {
		"type": "label", "schema_version": 1, "category": "flow", "label": "Label",
		"fields": [{"key": "name", "kind": "text", "default": "", "label": "Label name", "required": true}],
	}


func summary(args: Dictionary) -> String:
	return "Label: %s" % args.get("name", "")


func run(_ctx: RPGContext, _args: Dictionary) -> RPGResult:
	return RPGResult.ok()
