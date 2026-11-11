@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {"type": "exit_event", "schema_version": 1, "category": "flow", "label": "Exit Event Processing", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Exit Event Processing"


func run(_ctx: RPGContext, _args: Dictionary) -> RPGResult:
	return RPGResult.flow_exit()
