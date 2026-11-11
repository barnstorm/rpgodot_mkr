@tool
extends RPGCommand


static func descriptor() -> Dictionary:
	return {"type": "fancy_effect", "schema_version": 1, "category": "test", "label": "Fancy effect", "fields": []}


func run(_ctx: RPGContext, _args: Dictionary) -> RPGResult:
	return RPGResult.ok()
