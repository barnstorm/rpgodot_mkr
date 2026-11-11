@tool
extends RPGCommand
## Test command of the probe extension: records a mark on the probe.


static func descriptor() -> Dictionary:
	return {"type": "probe_mark", "schema_version": 1, "category": "flow", "label": "Probe mark", "fields": [{"key": "mark", "kind": "text", "default": "x"}]}


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var p: Object = ctx.rpg.extension("probe")
	if p != null:
		p.calls.append(["probe_mark", [str(args.get("mark", ""))]])
	return RPGResult.ok()
