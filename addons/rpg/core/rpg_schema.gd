@tool
class_name RPGSchema
extends RefCounted
## Generates JSON Schema (draft 2020-12) for events files from the command descriptors, so code
## editors such as VS Code can check and autocomplete `rpg/maps/*.events.json`.
## Schema covers structure only; RPGValidator.references() checks IDs and links.
##
##   RPGSchema.events_schema(registry) -> Dictionary
##   RPGSchema.write(registry)          -> writes res://rpg/.schema/events.schema.json + README.md

const SCHEMA_DIR := "res://rpg/.schema"
const DRAFT := "https://json-schema.org/draft/2020-12/schema"
const ID_PATTERN := "^[a-z][a-z0-9_]*$"


static func events_schema(registry: RPGCommandRegistry) -> Dictionary:
	var defs := {}
	defs["id"] = {"type": "string", "pattern": ID_PATTERN}
	defs["cell"] = {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2}
	defs["location"] = {
		"type": "object", "required": ["map", "position"],
		"properties": {"map": {"$ref": "#/$defs/id"}, "position": {"$ref": "#/$defs/cell"}},
	}
	defs["operand"] = {"oneOf": [
		{"type": "number"},
		{"type": "object", "required": ["variable"], "properties": {"variable": {"$ref": "#/$defs/id"}}},
		{"type": "object", "required": ["random"], "properties": {"random": {"type": "array", "minItems": 2, "maxItems": 2}}},
		{"type": "object", "required": ["game_data"], "properties": {"game_data": {"type": "object", "required": ["kind"]}}},
	]}
	defs["facing"] = {"enum": ["down", "left", "right", "up", "keep"]}
	defs["sound"] = {
		"type": ["object", "null"],
		"properties": {
			"file": {"type": "string"}, "role": {"type": "string"},
			"volume": {"type": "number", "minimum": 0, "maximum": 100},
			"pitch": {"type": "number", "minimum": 50, "maximum": 150},
			"pan": {"type": "number", "minimum": -100, "maximum": 100},
		},
	}
	defs["condition"] = _condition_schema()
	defs["route_step"] = {
		"type": "object",
		"minProperties": 1,
		"properties": {
			"step": {"type": "string"}, "turn": {"type": "string"},
			"jump": {"$ref": "#/$defs/cell"}, "wait": {"type": "number", "minimum": 0},
			"speed": {"type": "integer", "minimum": 1, "maximum": 6},
			"frequency": {"type": "integer", "minimum": 1, "maximum": 5},
			"graphic": {"$ref": "#/$defs/graphic"}, "opacity": {"type": "integer", "minimum": 0, "maximum": 255},
			"switch": {"$ref": "#/$defs/id"}, "value": {"type": "boolean"}, "sound": {"$ref": "#/$defs/sound"},
			"walk_anim": {"type": "boolean"}, "step_anim": {"type": "boolean"},
			"direction_fix": {"type": "boolean"}, "through": {"type": "boolean"}, "hide": {"type": "boolean"},
		},
	}
	defs["route"] = {"oneOf": [
		{"type": "array", "items": {"$ref": "#/$defs/route_step"}},
		{"type": "object", "properties": {
			"steps": {"type": "array", "items": {"$ref": "#/$defs/route_step"}},
			"repeat": {"type": "boolean"}, "skip_if_blocked": {"type": "boolean"},
		}},
	]}
	defs["graphic"] = {"oneOf": [
		{"type": "null"},
		{"type": "object", "required": ["sheet"], "properties": {
			"sheet": {"type": "string"}, "index": {"type": "integer", "minimum": 0, "maximum": 7},
			"facing": {"$ref": "#/$defs/facing"}, "frame": {"type": "integer", "minimum": 0, "maximum": 3},
		}},
		{"type": "object", "required": ["tile"], "properties": {"tile": {}}},
	]}
	var branches := []
	var known := []
	var descs: Array = registry.all_descriptors() if registry != null else []
	for d in descs:
		var t := str(d.get("type", ""))
		if t == "" or known.has(t):
			continue
		known.append(t)
		branches.append({"$ref": "#/$defs/cmd_" + t})
		defs["cmd_" + t] = command_schema(d)
	# Commands from extensions that are not installed are kept: accept any other type.
	branches.append({
		"title": "Command from another extension (kept as-is)",
		"type": "object", "required": ["type"],
		"properties": {"type": {"type": "string", "not": {"enum": known}}, "skip": {"type": "boolean"}},
	})
	defs["command"] = {"oneOf": branches}
	defs["command_list"] = {"type": "array", "items": {"$ref": "#/$defs/command"}}
	defs["page"] = {
		"type": "object",
		"properties": {
			"conditions": {"type": "array", "items": {"$ref": "#/$defs/condition"}},
			"graphic": {"$ref": "#/$defs/graphic"},
			"movement": {"type": "object", "properties": {
				"type": {"enum": ["fixed", "random", "approach", "custom"]},
				"speed": {"type": "integer", "minimum": 1, "maximum": 6},
				"frequency": {"type": "integer", "minimum": 1, "maximum": 5},
				"route": {"$ref": "#/$defs/route"},
			}},
			"options": {"type": "object", "properties": {
				"walk_anim": {"type": "boolean"}, "step_anim": {"type": "boolean"},
				"direction_fix": {"type": "boolean"}, "through": {"type": "boolean"},
			}},
			"priority": {"enum": ["below", "same", "above"]},
			"trigger": {"enum": ["action_button", "player_touch", "event_touch", "autorun", "parallel"]},
			"commands": {"$ref": "#/$defs/command_list"},
		},
	}
	defs["event"] = {
		"type": "object", "required": ["id", "position", "pages"],
		"properties": {
			"id": {"$ref": "#/$defs/id"}, "name": {"type": "string"}, "notes": {"type": "string"},
			"position": {"$ref": "#/$defs/cell"},
			"pages": {"type": "array", "items": {"$ref": "#/$defs/page"}},
		},
	}
	return {
		"$schema": DRAFT,
		"title": "RPG Kit map events file",
		"description": "Generated from the command descriptors. Do not edit; regenerate from the editor.",
		"type": "object",
		"required": ["schema_version", "events"],
		"properties": {
			"schema_version": {"const": 1},
			"map": {"$ref": "#/$defs/id"},
			"events": {"type": "array", "items": {"$ref": "#/$defs/event"}},
		},
		"$defs": defs,
	}


## One oneOf branch: {"type": {"const": t}, fields...}. Unknown extra fields are allowed (kept).
static func command_schema(d: Dictionary) -> Dictionary:
	var props := {"type": {"const": str(d.get("type", ""))}, "skip": {"type": "boolean"}}
	var required := ["type"]
	for f in d.get("fields", []):
		var k := str(f.get("key", ""))
		if k == "":
			continue
		props[k] = field_schema(f)
		if f.get("required", false) and not f.has("show_if"):
			required.append(k)
	var s := {"type": "object", "required": required, "properties": props}
	if d.has("label"):
		s["title"] = str(d.label)
	return s


static func field_schema(f: Dictionary) -> Dictionary:
	var s := {}
	match str(f.get("kind", "")):
		"int":
			s = {"type": "integer"}
			if f.has("min"):
				s["minimum"] = f.min
			if f.has("max"):
				s["maximum"] = f.max
		"float":
			s = {"type": "number"}
			if f.has("min"):
				s["minimum"] = f.min
			if f.has("max"):
				s["maximum"] = f.max
		"bool":
			s = {"type": "boolean"}
		"text", "multiline":
			s = {"type": "string"}
		"choice":
			s = {"enum": f.get("options", []).duplicate()}
		"ref":
			s = {"type": "string"}
		"resource":
			s = {"type": ["string", "null"]}
		"location":
			s = {"$ref": "#/$defs/location"}
		"facing":
			s = {"$ref": "#/$defs/facing"}
		"sound":
			s = {"$ref": "#/$defs/sound"}
		"condition":
			s = {"$ref": "#/$defs/condition"}
		"operand":
			s = {"$ref": "#/$defs/operand"}
		"operand_pair":
			s = {"type": "array", "items": {"$ref": "#/$defs/operand"}, "minItems": 2, "maxItems": 2}
		"color":
			s = {"type": "array", "items": {"type": "integer", "minimum": 0, "maximum": 255}, "minItems": 3, "maxItems": 4}
		"commands":
			s = {"$ref": "#/$defs/command_list"}
		"route":
			s = {"$ref": "#/$defs/route"}
		"list":
			var item := {}
			if f.get("item_kind", "") == "condition":
				item = {"$ref": "#/$defs/condition"}
			elif not f.get("item_fields", []).is_empty():
				var p := {}
				for sf in f.item_fields:
					p[str(sf.key)] = field_schema(sf)
				item = {"type": "object", "properties": p}
			s = {"type": "array", "items": item}
		"object":
			s = {"type": "object"}
			if not f.get("fields", []).is_empty():
				var p2 := {}
				for sf in f.fields:
					p2[str(sf.key)] = field_schema(sf)
				s["properties"] = p2
		_:
			s = {}
	if f.has("default") and f.default == null and s.has("type") and typeof(s.type) == TYPE_STRING:
		s.type = [s.type, "null"]
	if f.has("label") or f.has("help"):
		s["description"] = str(f.get("help", f.get("label", "")))
	return s


static func _condition_schema() -> Dictionary:
	var op := {"enum": ["==", "=", "!=", "≠", "<", "<=", "≤", ">", ">=", "≥"]}
	var branches := [
		{"properties": {"kind": {"const": "switch"}, "id": {"$ref": "#/$defs/id"}, "value": {"type": "boolean"}}, "required": ["kind", "id"]},
		{"properties": {"kind": {"const": "variable"}, "id": {"$ref": "#/$defs/id"}, "op": op, "value": {"oneOf": [{"$ref": "#/$defs/operand"}, {"type": "string"}, {"type": "boolean"}]}}, "required": ["kind", "id"]},
		{"properties": {"kind": {"const": "self_switch"}, "id": {"enum": ["A", "B", "C", "D"]}, "value": {"type": "boolean"}}, "required": ["kind", "id"]},
		{"properties": {"kind": {"const": "item"}, "id": {"$ref": "#/$defs/id"}, "item_kind": {"enum": ["items", "weapons", "armors"]}, "count": {"type": "integer", "minimum": 1}}, "required": ["kind", "id"]},
		{"properties": {"kind": {"const": "actor"}, "id": {"$ref": "#/$defs/id"}, "check": {"enum": ["in_party", "name", "class", "skill", "weapon", "armor", "state"]}, "value": {"type": "boolean"}, "name": {"type": "string"}}, "required": ["kind", "id"]},
		{"properties": {"kind": {"const": "facing"}, "target": {"type": "string"}, "facing": {"enum": ["down", "left", "right", "up"]}}, "required": ["kind", "facing"]},
		{"properties": {"kind": {"const": "button"}, "button": {"enum": ["ok", "cancel", "dash", "up", "down", "left", "right"]}}, "required": ["kind", "button"]},
		{"properties": {"kind": {"const": "gold"}, "op": op, "value": {"$ref": "#/$defs/operand"}}, "required": ["kind"]},
		{"properties": {"kind": {"const": "vehicle"}, "id": {"enum": ["none", "boat", "ship", "airship"]}}, "required": ["kind", "id"]},
		{"properties": {"kind": {"enum": ["all", "any"]}, "conditions": {"type": "array", "items": {"$ref": "#/$defs/condition"}}}, "required": ["kind", "conditions"]},
		{"properties": {"kind": {"const": "not"}, "condition": {"$ref": "#/$defs/condition"}}, "required": ["kind", "condition"]},
		{"properties": {"kind": {"enum": ["turn", "enemy_hp", "actor_hp"]}}, "required": ["kind"]},
	]
	for b in branches:
		b["type"] = "object"
	return {"oneOf": branches}


## Writes the schema and a README next to it. Returns OK or an error code.
static func write(registry: RPGCommandRegistry, dir := SCHEMA_DIR) -> Error:
	var err := RPGJson.save_file(dir.path_join("events.schema.json"), events_schema(registry))
	if err != OK:
		return err
	var readme := """# Generated JSON Schema

`events.schema.json` describes `rpg/maps/*.events.json`. It is generated from the event command
descriptors by the RPG Kit editor (RPGSchema.write) and is overwritten whenever commands change.

## VS Code

Add this to `.vscode/settings.json` in the project folder:

```json
{
	"json.schemas": [
		{ "fileMatch": ["rpg/maps/*.events.json"], "url": "./rpg/.schema/events.schema.json" }
	]
}
```

The schema checks structure only. IDs, map cells, assets and extension availability are checked
by the editor's validator (references and full project checks).
"""
	return RPGJson.write_atomic(dir.path_join("README.md"), readme)
