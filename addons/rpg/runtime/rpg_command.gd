@tool
class_name RPGCommand
extends RefCounted
## Base class for every event command, built-in or custom.
## A command is a descriptor (form + JSON shape) plus a run function. See the spec's Extension API.
##
##   static func descriptor() -> Dictionary   # {type, schema_version, category, label, fields}
##   func summary(args: Dictionary) -> String
##   func run(ctx: RPGContext, args: Dictionary) -> RPGResult   # may await; must honour ctx cancellation

## Filled by the registry from descriptor().
var desc: Dictionary = {}
## The extension that provides this command ("builtin" for the addon's own commands).
var extension_id := "builtin"


static func descriptor() -> Dictionary:
	return {}


func summary(args: Dictionary) -> String:
	return "%s" % desc.get("label", args.get("type", "?"))


func run(_ctx: RPGContext, _args: Dictionary) -> RPGResult:
	return RPGResult.ok()


## Nested command lists this command owns, as [{label, list}] (used by the editor tree and validator).
func child_lists(args: Dictionary) -> Array:
	var out := []
	for f in desc.get("fields", []):
		if f.get("kind", "") == "commands" and args.get(f.key) is Array:
			out.append({"label": f.get("label", f.key), "key": f.key, "list": args[f.key]})
	return out


## Fills missing fields with descriptor defaults (never removes unknown fields).
func with_defaults(args: Dictionary) -> Dictionary:
	return RPGCommand.apply_defaults(desc, args)


static func apply_defaults(d: Dictionary, args: Dictionary) -> Dictionary:
	var out := args.duplicate()
	for f in d.get("fields", []):
		var k: String = f.get("key", "")
		if k != "" and not out.has(k) and f.has("default"):
			out[k] = RPGJson.deep_copy(f.default)
	return out


## Structural checks against the descriptor. Returns an Array of {severity, field, message}.
func validate(args: Dictionary) -> Array:
	var problems := []
	for f in desc.get("fields", []):
		var k: String = f.get("key", "")
		if not _visible(f, args):
			continue
		var has := args.has(k) and args[k] != null
		if f.get("required", false) and not has:
			problems.append({"severity": "error", "field": k, "message": "'%s' is required." % f.get("label", k)})
			continue
		if not has:
			continue
		var v: Variant = args[k]
		match f.get("kind", ""):
			"int", "float":
				if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT and not (v is Dictionary and (v.has("variable") or v.has("random") or v.has("game_data"))):
					problems.append({"severity": "error", "field": k, "message": "'%s' must be a number." % f.get("label", k)})
				elif typeof(v) != TYPE_DICTIONARY:
					if f.has("min") and float(v) < float(f.min):
						problems.append({"severity": "error", "field": k, "message": "'%s' must be at least %s." % [f.get("label", k), f.min]})
					if f.has("max") and float(v) > float(f.max):
						problems.append({"severity": "error", "field": k, "message": "'%s' must be at most %s." % [f.get("label", k), f.max]})
			"bool":
				if typeof(v) != TYPE_BOOL:
					problems.append({"severity": "error", "field": k, "message": "'%s' must be true or false." % f.get("label", k)})
			"text", "multiline":
				if typeof(v) != TYPE_STRING:
					problems.append({"severity": "error", "field": k, "message": "'%s' must be text." % f.get("label", k)})
			"choice":
				if not f.get("options", []).has(v):
					problems.append({"severity": "error", "field": k, "message": "'%s' must be one of %s." % [f.get("label", k), ", ".join(PackedStringArray(f.get("options", [])))]})
			"commands":
				if typeof(v) != TYPE_ARRAY:
					problems.append({"severity": "error", "field": k, "message": "'%s' must be a command list." % f.get("label", k)})
			"location":
				if not (v is Dictionary and v.has("map") and v.get("position") is Array and v.position.size() == 2):
					problems.append({"severity": "error", "field": k, "message": "'%s' must be {map, position: [x, y]}." % f.get("label", k)})
	return problems


static func _visible(f: Dictionary, args: Dictionary) -> bool:
	if not f.has("show_if"):
		return true
	var cond: Dictionary = f.show_if
	var actual: Variant = args.get(cond.get("key", ""))
	if cond.has("equals"):
		if cond.equals is Array:
			return cond.equals.has(actual)
		return actual == cond.equals
	return true


## Helper for summaries: short text for sounds, operands, locations.
static func describe_operand(v: Variant) -> String:
	if v is Dictionary and v.has("variable"):
		return "[%s]" % v.variable
	if v is Dictionary and v.get("random") is Array and v.random.size() == 2:
		return "random %s..%s" % [v.random[0], v.random[1]]
	if v is Dictionary and v.get("game_data") is Dictionary:
		var g: Dictionary = v.game_data
		var bits := PackedStringArray([str(g.get("kind", ""))])
		for k in ["id", "field"]:
			if str(g.get(k, "")) != "":
				bits.append(str(g[k]))
		return "(%s)" % " ".join(bits)
	return str(v)


static func describe_location(v: Variant) -> String:
	if v is Dictionary and v.has("map"):
		var p: Array = v.get("position", [0, 0])
		return "%s (%s, %s)" % [v.map, p[0], p[1]]
	return str(v)
