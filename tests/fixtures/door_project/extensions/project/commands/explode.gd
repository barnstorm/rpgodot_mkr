@tool
extends RPGCommand
## Test command: waits a frame then fails, to prove an extension error releases the input lock.


static func descriptor() -> Dictionary:
	return {
		"type": "explode", "schema_version": 1, "category": "test", "label": "Explode",
		"fields": [{"key": "message", "kind": "text", "default": "boom"}],
	}


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	await ctx.tree.process_frame
	return RPGResult.error("Explode: %s" % args.message)
