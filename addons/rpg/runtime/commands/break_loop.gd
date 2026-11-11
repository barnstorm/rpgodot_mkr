@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {"type": "break_loop", "schema_version": 1, "category": "flow", "label": "Break Loop", "fields": []}


func summary(_args: Dictionary) -> String:
	return "Break Loop"


func run(_ctx: RPGContext, _args: Dictionary) -> RPGResult:
	return RPGResult.flow_break()
