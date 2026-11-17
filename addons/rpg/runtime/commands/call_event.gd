@tool
extends RPGCommand
## Runs a map event's page inline (RPG2000/2003 Call Event): a switchboard event can hold shared
## logic that many events call. While the page runs it is "this event", so its self switches and
## self variables are the called event's. Nested calls (Call Event, Call Common Event) are capped
## at the interpreter's depth limit. For common events use Call Common Event.


static func descriptor() -> Dictionary:
	return {
		"type": "call_event", "schema_version": 1, "category": "flow", "label": "Call Event",
		"fields": [
			{"key": "target", "kind": "choice", "options": ["this", "id", "variable"], "option_labels": ["This event", "Event ID", "From a variable"], "default": "this", "label": "Event"},
			{"key": "id", "kind": "text", "default": "", "label": "Event ID", "help": "an event on this map", "show_if": {"key": "target", "equals": "id"}},
			{"key": "variable", "kind": "ref", "ref": "variable", "label": "Holds the event's id", "required": true, "show_if": {"key": "target", "equals": "variable"}},
			{"key": "page", "kind": "operand", "default": 1, "min": 1, "label": "Page"},
		],
	}


func summary(args: Dictionary) -> String:
	var mode := str(args.get("target", "this"))
	var name := "this" if mode == "this" else str(args.get("id", "?") if mode == "id" else "[%s]" % args.get("variable", "?"))
	return "Call Event: %s, page %s" % [name, RPGCommand.describe_operand(args.get("page", 1))]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var mode := str(args.get("target", "this"))
	var wanted := ""
	if mode == "id":
		wanted = str(args.get("id", ""))
	elif mode == "variable":
		wanted = str(ctx.state.get_variable(str(args.get("variable", ""))))
	var ev: Node = null
	if mode == "this":
		ev = ctx.character("this")
		if ev == null:
			return RPGResult.error("Call Event: there is no this event here (the caller is not a map event).")
	else:
		var m: Node = ctx.map
		ev = m.get_event(wanted) if m != null else null
		if ev == null:
			return RPGResult.error("Call Event: no event '%s' on this map." % wanted)
	var pages: Array = ev.data.get("pages", [])
	var page_no := int(ctx.operand(args.get("page", 1)))
	if page_no < 1 or page_no > pages.size():
		return RPGResult.error("Call Event: '%s' has no page %d (it has %d)." % [ev.event_id, page_no, pages.size()])
	var page: Dictionary = pages[page_no - 1]
	var r: RPGResult = await ctx.run_event_page(ev, page.get("commands", []), "event:%s/%s:%d" % [ev.map_id, ev.event_id, page_no - 1])
	if r.flow == "exit":
		# Exit Event inside the called page ends only the called page.
		return RPGResult.ok()
	if r.flow.begins_with("jump:"):
		return RPGResult.error("Jump to Label: there is no label '%s' in '%s' page %d." % [r.flow.substr(5), ev.event_id, page_no])
	return r
