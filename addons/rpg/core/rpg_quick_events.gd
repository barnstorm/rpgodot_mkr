@tool
class_name RPGQuickEvents
extends RefCounted
## Quick event templates: versioned JSON files that list questions ("asks") and the event to build.
## Shared by editor and tools; never touches EditorInterface.
##
## Templates load from the addon defaults (res://addons/rpg/core/quick_events/*.json) and the
## project folder (res://rpg/quick_events/*.json); a project template with the same "name" wins.
##
## Template format:
##   {schema_version: 1, name, version, author, description?,
##    asks: [{key, type, label, default?, required?, options?, show_if?, kind_from?, min?, max?}],
##    computed?: [{key, when?: {key, equals | not_equals}, format}],
##    variants?: [{when: {key, equals | not_equals}, replace_type, with: {command}}],
##    event: {...}}
##
## Placeholder rules (spec "Quick event templates"):
##  - In most fields a placeholder must be the whole value ("{{price}}"). It is replaced by a typed
##    value (number, checked location object, typed ID, object, list). Text is never pasted into JSON.
##  - Text fields (keys in TEXT_KEYS, e.g. show_text "text", choice "label") may embed placeholders
##    inside a sentence; the answer is inserted as plain text with text codes escaped (\ -> \\).
##  - Dotted paths read inside an answer: {{contents.amount}}, {{read_by.priority}}.
##  - A missing required answer is an error.
##  - Sounds named by role ({"role": "door_open"}) stay as roles when the resolver finds a file; when
##    it returns "" the template needs an answer "sound_<role>" (a file name).
##  - The output is an ordinary event; only "editor_history" remembers the template.

const ADDON_DIR := "res://addons/rpg/core/quick_events"
const PROJECT_DIR := "res://rpg/quick_events"
const SCHEMA_VERSION := 1

## Ask types and the answer shape each one expects.
const ASK_TYPES := ["map_location", "facing", "image", "amount", "item", "text", "choice", "goods", "bool"]
## Keys whose string values are message text (placeholders may sit inside a sentence).
const TEXT_KEYS := ["text", "label", "name", "notes", "message"]
const FACINGS := ["down", "left", "right", "up", "keep"]
const ITEM_KINDS := ["items", "weapons", "armors"]

const PAGE_DEFAULTS := {
	"conditions": [],
	"graphic": null,
	"movement": {"type": "fixed"},
	"options": {"walk_anim": true, "step_anim": false, "direction_fix": false, "through": false},
	"priority": "same",
	"trigger": "action_button",
	"commands": [],
}

static var _placeholder_re: RegEx


static func _re() -> RegEx:
	if _placeholder_re == null:
		_placeholder_re = RegEx.create_from_string("\\{\\{\\s*([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)*)\\s*\\}\\}")
	return _placeholder_re


# --------------------------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------------------------

## Loads every template. Returns {templates: {name: template}, errors: [{file, message}]}.
## Each template gets "_file" (its path) and "_source" ("addon" or "project").
static func load_all(project_dir := PROJECT_DIR, addon_dir := ADDON_DIR) -> Dictionary:
	var out := {}
	var errors := []
	for pair in [[addon_dir, "addon"], [project_dir, "project"]]:
		var dir_path: String = pair[0]
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			if not str(f).ends_with(".json"):
				continue
			var path: String = dir_path.path_join(f)
			var r := RPGJson.parse_file(path)
			if not r.ok:
				errors.append({"file": path, "message": r.error})
				continue
			var problems := check_template(r.data)
			if not problems.is_empty():
				errors.append({"file": path, "message": "; ".join(PackedStringArray(problems))})
				continue
			var t: Dictionary = r.data
			t["_file"] = path
			t["_source"] = pair[1]
			out[str(t.name)] = t
	return {"templates": out, "errors": errors}


## Templates by name (project overrides win).
static func templates(project_dir := PROJECT_DIR) -> Dictionary:
	return load_all(project_dir).templates


static func template_names(project_dir := PROJECT_DIR) -> Array:
	var names: Array = templates(project_dir).keys()
	names.sort()
	return names


## Structural checks for a template. Returns readable problems (empty = fine).
static func check_template(t: Variant) -> Array:
	var p := []
	if not (t is Dictionary):
		return ["A template must be a JSON object."]
	if int(t.get("schema_version", 0)) != SCHEMA_VERSION:
		p.append("schema_version must be %d" % SCHEMA_VERSION)
	if str(t.get("name", "")) == "":
		p.append("'name' is missing")
	if not (t.get("asks", null) is Array):
		p.append("'asks' must be a list")
	else:
		var keys := {}
		for a in t.asks:
			if not (a is Dictionary) or str(a.get("key", "")) == "":
				p.append("every ask needs a key")
				continue
			if keys.has(a.key):
				p.append("ask '%s' is listed twice" % a.key)
			keys[a.key] = true
			if not ASK_TYPES.has(str(a.get("type", ""))):
				p.append("ask '%s' has unknown type '%s'" % [a.key, a.get("type", "")])
			if a.get("type", "") == "choice" and not (a.get("options") is Array and not a.options.is_empty()):
				p.append("choice ask '%s' needs options" % a.key)
	if not (t.get("event", null) is Dictionary):
		p.append("'event' must be an object")
	elif not (t.event.get("pages", null) is Array) or t.event.pages.is_empty():
		p.append("'event' needs at least one page")
	return p


# --------------------------------------------------------------------------------------------
# Compiling
# --------------------------------------------------------------------------------------------

## Builds an event from a template and the answers.
## answers: {ask_key: value} (dotted keys like "contents.kind" may also be nested: {contents: {kind}}).
## sound_roles_resolver: role -> file name ("" when the pack has no file for it). Optional.
## data: optional RPGProjectData used to check IDs and locations and to name items.
## Returns {ok, event, errors: [{key, message}]}.
static func compile(template: Dictionary, answers: Dictionary, sound_roles_resolver: Callable = Callable(), data: Variant = null) -> Dictionary:
	var errors := []
	var tproblems := check_template(template)
	if not tproblems.is_empty():
		for m in tproblems:
			errors.append({"key": "", "message": "Template problem: %s" % m})
		return {"ok": false, "event": {}, "errors": errors}
	var values := {}
	var asks: Dictionary = {}
	for a in template.asks:
		asks[a.key] = a
	# 1. Read and type every answer.
	for a in template.asks:
		var key: String = a.key
		if not _ask_visible(a, answers, values):
			values[key] = null
			continue
		var raw: Variant = lookup_answer(answers, key)
		if _is_blank(raw):
			if a.has("default"):
				raw = RPGJson.deep_copy(a.default)
			elif bool(a.get("required", true)):
				errors.append({"key": key, "message": "Please answer \"%s\"." % a.get("label", key)})
				values[key] = null
				continue
			else:
				values[key] = null
				continue
		var typed := _typed(a, raw, values, data)
		if typed.has("error"):
			errors.append({"key": key, "message": typed.error})
			values[key] = null
		else:
			values[key] = typed.value
	# 2. Computed values (first entry whose "when" holds, per key).
	var done_computed := {}
	for c in template.get("computed", []):
		var ck: String = str(c.get("key", ""))
		if ck == "" or done_computed.has(ck):
			continue
		if lookup_answer(answers, ck) != null:
			values[ck] = lookup_answer(answers, ck)
			done_computed[ck] = true
			continue
		if c.has("when") and not _when(c.when, values, answers):
			continue
		var r := _interpolate(str(c.get("format", "")), values, asks, data, false)
		if r.has("error"):
			errors.append({"key": ck, "message": r.error})
		else:
			values[ck] = r.value
		done_computed[ck] = true
	if not errors.is_empty():
		return {"ok": false, "event": {}, "errors": errors}
	# 3. Variants replace whole commands before substitution.
	var ev: Dictionary = RPGJson.deep_copy(template.event)
	for v in template.get("variants", []):
		if v.has("when") and _when(v.when, values, answers):
			_replace_commands(ev, str(v.get("replace_type", "")), v.get("with", {}))
	# 4. Substitute placeholders.
	var sub := _substitute(ev, "", values, asks, data, errors)
	if not errors.is_empty():
		return {"ok": false, "event": {}, "errors": errors}
	ev = sub
	# 5. Sounds by role.
	if sound_roles_resolver.is_valid():
		_resolve_sounds(ev, sound_roles_resolver, answers, errors)
		if not errors.is_empty():
			return {"ok": false, "event": {}, "errors": errors}
	complete_event(ev)
	ev["editor_history"] = {
		"template": str(template.get("name", "")),
		"version": template.get("version", 1),
		"author": str(template.get("author", "")),
	}
	return {"ok": true, "event": ev, "errors": []}


## Sound roles used by a template that the resolver cannot map to a file.
static func missing_sound_roles(template: Dictionary, sound_roles_resolver: Callable) -> Array:
	var roles := []
	if not sound_roles_resolver.is_valid():
		return roles
	_collect_roles(template.get("event", {}), roles)
	for v in template.get("variants", []):
		_collect_roles(v.get("with", {}), roles)
	var missing := []
	for r in roles:
		if str(sound_roles_resolver.call(r)) == "" and not missing.has(r):
			missing.append(r)
	return missing


## Fills page fields a template may leave out so the result is a complete event.
static func complete_event(ev: Dictionary) -> Dictionary:
	if not ev.has("name"):
		ev["name"] = ""
	if not ev.has("notes"):
		ev["notes"] = ""
	if not (ev.get("pages") is Array):
		ev["pages"] = []
	for i in ev.pages.size():
		if ev.pages[i] is Dictionary:
			ev.pages[i] = complete_page(ev.pages[i])
	return ev


static func complete_page(p: Dictionary) -> Dictionary:
	for k in PAGE_DEFAULTS:
		if not p.has(k):
			p[k] = RPGJson.deep_copy(PAGE_DEFAULTS[k])
	if p.options is Dictionary:
		for k in PAGE_DEFAULTS.options:
			if not p.options.has(k):
				p.options[k] = PAGE_DEFAULTS.options[k]
	return p


## Reads an answer by key: flat ("contents.kind") or nested ({contents: {kind}}).
static func lookup_answer(answers: Dictionary, key: String) -> Variant:
	if answers.has(key):
		return answers[key]
	var parts := key.split(".")
	var cur: Variant = answers
	for p in parts:
		if cur is Dictionary and cur.has(p):
			cur = cur[p]
		else:
			return null
	return cur


## Escapes text so codes show literally (\ becomes \\).
static func escape_text(s: String) -> String:
	return s.replace("\\", "\\\\")


## Form-builder field descriptions for a template's questions (used by the quick event dialog).
static func form_fields(template: Dictionary) -> Array:
	var out := []
	for a in template.get("asks", []):
		var f := {"key": a.key, "label": a.get("label", a.key)}
		if a.has("default"):
			f["default"] = RPGJson.deep_copy(a.default)
		if a.has("help"):
			f["help"] = a.help
		f["required"] = bool(a.get("required", true)) and not a.has("default")
		match str(a.type):
			"map_location":
				f["kind"] = "location"
			"facing":
				f["kind"] = "facing"
			"image":
				f["kind"] = "image"
				f["res"] = str(a.get("res", "charset"))
			"amount":
				f["kind"] = "int"
				f["min"] = a.get("min", 0)
				if a.has("max"):
					f["max"] = a.max
			"item":
				f["kind"] = "ref"
				f["ref"] = "item"
				if a.has("kind_from"):
					f["ref_from"] = a.kind_from
			"text":
				f["kind"] = "multiline" if a.get("multiline", true) else "text"
			"choice":
				f["kind"] = "choice"
				var ids := []
				var labels := []
				for o in a.options:
					if o is Dictionary:
						ids.append(str(o.get("id", "")))
						labels.append(str(o.get("label", o.get("id", ""))))
					else:
						ids.append(str(o))
						labels.append(str(o))
				f["options"] = ids
				f["option_labels"] = labels
			"goods":
				f["kind"] = "list"
				f["item_fields"] = [
					{"key": "kind", "kind": "choice", "options": ITEM_KINDS, "default": "items", "label": "Kind"},
					{"key": "id", "kind": "ref", "ref": "item", "ref_from": "kind", "label": "Item"},
					{"key": "price", "kind": "int", "default": null, "min": 0, "label": "Price (blank = database)"},
				]
			"bool":
				f["kind"] = "bool"
		if a.has("show_if"):
			f["show_if"] = a.show_if
		out.append(f)
	return out


# --------------------------------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------------------------------

static func _is_blank(v: Variant) -> bool:
	return v == null or (typeof(v) == TYPE_STRING and str(v) == "")


static func _ask_visible(a: Dictionary, answers: Dictionary, values: Dictionary) -> bool:
	if not a.has("show_if"):
		return true
	return _when(a.show_if, values, answers)


static func _when(cond: Dictionary, values: Dictionary, answers: Dictionary) -> bool:
	var k: String = str(cond.get("key", ""))
	var v: Variant = _raw_value(k, values, answers)
	if v is Dictionary and v.has("id") and not (cond.get("equals") is Dictionary):
		v = v.id
	if cond.has("equals"):
		if cond.equals is Array:
			return cond.equals.has(v)
		return _eq(v, cond.equals)
	if cond.has("not_equals"):
		if cond.not_equals is Array:
			return not cond.not_equals.has(v)
		return not _eq(v, cond.not_equals)
	return true


static func _eq(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


static func _raw_value(k: String, values: Dictionary, answers: Dictionary) -> Variant:
	if values.has(k):
		return values[k]
	var r := _resolve_path(k, values, {}, null)
	if r.has("value"):
		return r.value
	return lookup_answer(answers, k)


## Converts one raw answer to its typed value. Returns {value} or {error}.
static func _typed(a: Dictionary, raw: Variant, values: Dictionary, data: Variant) -> Dictionary:
	var label: String = str(a.get("label", a.key))
	match str(a.type):
		"amount":
			var n: Variant = raw
			if typeof(n) == TYPE_STRING and str(n).is_valid_int():
				n = int(n)
			if typeof(n) == TYPE_FLOAT and n == floorf(n):
				n = int(n)
			if typeof(n) != TYPE_INT:
				return {"error": "\"%s\" must be a whole number." % label}
			if a.has("min") and n < int(a.min):
				return {"error": "\"%s\" must be at least %s." % [label, a.min]}
			if a.has("max") and n > int(a.max):
				return {"error": "\"%s\" must be at most %s." % [label, a.max]}
			return {"value": n}
		"bool":
			if typeof(raw) != TYPE_BOOL:
				return {"error": "\"%s\" must be yes or no." % label}
			return {"value": raw}
		"text":
			if typeof(raw) != TYPE_STRING:
				return {"error": "\"%s\" must be text." % label}
			return {"value": raw}
		"facing":
			if not FACINGS.has(str(raw)) or (str(raw) == "keep" and a.get("allow_keep", true) == false):
				return {"error": "\"%s\" must be one of down, left, right, up or keep." % label}
			return {"value": str(raw)}
		"map_location":
			if not (raw is Dictionary) or not RPGIds.is_valid(raw.get("map")) or not (raw.get("position") is Array) or raw.position.size() != 2:
				return {"error": "\"%s\" must be a map and a cell." % label}
			var pos: Array = raw.position
			for c in pos:
				if typeof(c) != TYPE_INT and not (typeof(c) == TYPE_FLOAT and c == floorf(c)):
					return {"error": "\"%s\": the cell must be whole numbers." % label}
			var loc := {"map": str(raw.map), "position": [int(pos[0]), int(pos[1])]}
			if data != null:
				if not data.maps.has(loc.map):
					return {"error": "\"%s\": map '%s' does not exist." % [label, loc.map]}
				if not data.cell_in_map(loc.map, loc.position):
					return {"error": "\"%s\": cell (%d, %d) is outside map '%s'." % [label, loc.position[0], loc.position[1], loc.map]}
			return {"value": loc}
		"image":
			var sheet := ""
			var index := 0
			if raw is Dictionary:
				sheet = str(raw.get("sheet", ""))
				index = int(raw.get("index", 0))
			elif typeof(raw) == TYPE_STRING:
				sheet = raw
			if sheet == "":
				if bool(a.get("required", true)) and not a.has("default"):
					return {"error": "Please choose an image for \"%s\"." % label}
				return {"value": null}
			if index < 0 or index > 7:
				return {"error": "\"%s\": the character index must be 0 to 7." % label}
			return {"value": {"sheet": sheet, "index": index}}
		"item":
			var id: Variant = raw.get("id") if raw is Dictionary else raw
			if not RPGIds.is_valid(id):
				return {"error": "\"%s\" must be an item ID." % label}
			var kind := "items"
			if a.has("kind_from"):
				var kv: Variant = _raw_value(str(a.kind_from), values, {})
				if kv is Dictionary:
					kv = kv.get("id", "items")
				if ITEM_KINDS.has(str(kv)):
					kind = str(kv)
			elif raw is Dictionary and ITEM_KINDS.has(str(raw.get("kind", ""))):
				kind = raw.kind
			elif ITEM_KINDS.has(str(a.get("item_kind", ""))):
				kind = a.item_kind
			if data != null and not data.has_record(kind, id):
				return {"error": "\"%s\": '%s' is not in the %s database." % [label, id, kind]}
			return {"value": str(id)}
		"choice":
			var key: Variant = raw.get("id") if raw is Dictionary else raw
			for o in a.options:
				var oid: Variant = o.get("id") if o is Dictionary else o
				if str(oid) == str(key):
					return {"value": RPGJson.deep_copy(o)}
			return {"error": "\"%s\" must be one of the listed choices." % label}
		"goods":
			if not (raw is Array):
				return {"error": "\"%s\" must be a list of goods." % label}
			if raw.is_empty() and bool(a.get("required", true)):
				return {"error": "\"%s\": add at least one item for sale." % label}
			var goods := []
			for g in raw:
				if not (g is Dictionary):
					return {"error": "\"%s\": every entry needs a kind and an item." % label}
				var gk := str(g.get("kind", "items"))
				if not ITEM_KINDS.has(gk) or not RPGIds.is_valid(g.get("id")):
					return {"error": "\"%s\": every entry needs a kind and an item." % label}
				if data != null and not data.has_record(gk, g.id):
					return {"error": "\"%s\": '%s' is not in the %s database." % [label, g.id, gk]}
				var entry := {"kind": gk, "id": str(g.id)}
				var price: Variant = g.get("price")
				if price != null and not (typeof(price) == TYPE_STRING and price == ""):
					if typeof(price) == TYPE_FLOAT and price == floorf(price):
						price = int(price)
					if typeof(price) != TYPE_INT or price < 0:
						return {"error": "\"%s\": prices must be whole numbers of 0 or more." % label}
					entry["price"] = price
				goods.append(entry)
			return {"value": goods}
	return {"error": "Unknown answer type '%s'." % a.type}


## The value a choice answer stands for when used whole: its "value", else its id.
static func _choice_whole(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("value"):
			return v.value
		return v.get("id")
	return v


## Resolves a placeholder path. Returns {value} or {error}.
static func _resolve_path(path: String, values: Dictionary, asks: Dictionary, data: Variant) -> Dictionary:
	if values.has(path):
		var v: Variant = values[path]
		if asks.has(path) and str(asks[path].get("type", "")) == "choice":
			v = _choice_whole(v)
		return {"value": v}
	# Longest prefix that is a known value, then walk into it.
	var parts := path.split(".")
	for n in range(parts.size() - 1, 0, -1):
		var prefix := ".".join(parts.slice(0, n))
		if not values.has(prefix):
			continue
		var cur: Variant = values[prefix]
		var rest := parts.slice(n)
		# Item answers: ".name" looks the record up.
		if asks.has(prefix) and str(asks[prefix].get("type", "")) == "item" and rest.size() == 1 and rest[0] == "name":
			return {"value": _item_name(asks[prefix], cur, values, data)}
		for p in rest:
			if cur is Dictionary and cur.has(p):
				cur = cur[p]
			elif cur is Array and str(p).is_valid_int() and int(p) < cur.size():
				cur = cur[int(p)]
			else:
				return {"error": "The answer for '%s' has no '%s'." % [prefix, p]}
		return {"value": cur}
	if asks.has(path):
		return {"value": null}
	return {"error": "Unknown placeholder {{%s}}." % path}


static func _item_name(a: Dictionary, id: Variant, values: Dictionary, data: Variant) -> String:
	if id == null:
		return ""
	var kind := "items"
	if a.has("kind_from"):
		var kv: Variant = _raw_value(str(a.kind_from), values, {})
		if kv is Dictionary:
			kv = kv.get("id", "items")
		if ITEM_KINDS.has(str(kv)):
			kind = str(kv)
	if data != null:
		var rec: Dictionary = data.record(kind, str(id))
		if rec.has("name"):
			return str(rec.name)
	return str(id)


static func _text_of(v: Variant) -> String:
	if v == null:
		return ""
	if v is Dictionary:
		return str(v.get("label", v.get("id", "")))
	if typeof(v) == TYPE_FLOAT and v == floorf(v):
		return str(int(v))
	return str(v)


## Replaces placeholders inside a sentence. `escape` doubles backslashes in inserted answers.
static func _interpolate(s: String, values: Dictionary, asks: Dictionary, data: Variant, escape := true) -> Dictionary:
	var out := ""
	var last := 0
	for m in _re().search_all(s):
		out += s.substr(last, m.get_start() - last)
		var r := _resolve_path(m.get_string(1), values, asks, data)
		if r.has("error"):
			return r
		var t := _text_of(r.value)
		out += escape_text(t) if escape else t
		last = m.get_end()
	out += s.substr(last)
	return {"value": out}


static func _substitute(v: Variant, key: String, values: Dictionary, asks: Dictionary, data: Variant, errors: Array) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _substitute(v[k], str(k), values, asks, data, errors)
			return d
		TYPE_ARRAY:
			var arr := []
			for x in v:
				arr.append(_substitute(x, key, values, asks, data, errors))
			return arr
		TYPE_STRING:
			var s: String = v
			if s.find("{{") == -1:
				return s
			var is_text := TEXT_KEYS.has(key)
			var whole := _re().search(s)
			if whole != null and whole.get_start() == 0 and whole.get_end() == s.length() and not is_text:
				var r := _resolve_path(whole.get_string(1), values, asks, data)
				if r.has("error"):
					errors.append({"key": whole.get_string(1), "message": r.error})
					return null
				return RPGJson.deep_copy(r.value)
			if not is_text:
				errors.append({"key": key, "message": "Field '%s': a placeholder must be the whole value (\"%s\")." % [key, s]})
				return s
			var r2 := _interpolate(s, values, asks, data, true)
			if r2.has("error"):
				errors.append({"key": key, "message": r2.error})
				return s
			return r2.value
	return v


static func _replace_commands(v: Variant, type: String, with: Variant) -> void:
	if v is Dictionary:
		for k in v:
			_replace_commands(v[k], type, with)
	elif v is Array:
		for i in v.size():
			if v[i] is Dictionary and str(v[i].get("type", "")) == type and type != "":
				v[i] = RPGJson.deep_copy(with)
			else:
				_replace_commands(v[i], type, with)


static func _collect_roles(v: Variant, out: Array) -> void:
	if v is Dictionary:
		if v.has("role") and v.size() == 1 and typeof(v.role) == TYPE_STRING:
			if not out.has(v.role):
				out.append(v.role)
			return
		for k in v:
			_collect_roles(v[k], out)
	elif v is Array:
		for x in v:
			_collect_roles(x, out)


static func _resolve_sounds(v: Variant, resolver: Callable, answers: Dictionary, errors: Array) -> void:
	if v is Dictionary:
		for k in v.keys():
			var x: Variant = v[k]
			if x is Dictionary and x.has("role") and x.size() == 1 and typeof(x.role) == TYPE_STRING:
				if str(resolver.call(x.role)) != "":
					continue
				var chosen: Variant = lookup_answer(answers, "sound_" + str(x.role))
				if chosen is Dictionary and str(chosen.get("file", "")) != "":
					v[k] = chosen.duplicate(true)
				elif typeof(chosen) == TYPE_STRING and chosen != "":
					v[k] = {"file": chosen, "volume": 100, "pitch": 100, "pan": 0}
				else:
					errors.append({"key": "sound_" + str(x.role), "message": "The asset pack has no sound for '%s'. Please choose one." % x.role})
			else:
				_resolve_sounds(x, resolver, answers, errors)
	elif v is Array:
		for x in v:
			_resolve_sounds(x, resolver, answers, errors)
