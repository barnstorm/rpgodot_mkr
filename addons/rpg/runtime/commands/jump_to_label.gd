@tool
extends RPGCommand
## RPG Maker's "Jump to Label": continues after the Label with this name in the same event
## (searching outwards from the current branch or loop).


static func descriptor() -> Dictionary:
	return {
		"type": "jump_to_label", "schema_version": 1, "category": "flow", "label": "Jump to Label",
		"fields": [{"key": "name", "kind": "text", "default": "", "label": "Label name", "required": true}],
	}


func summary(args: Dictionary) -> String:
	return "Jump to Label: %s" % args.get("name", "")


func run(_ctx: RPGContext, args: Dictionary) -> RPGResult:
	var r := RPGResult.ok()
	r.flow = "jump:" + str(args.get("name", ""))
	return r
