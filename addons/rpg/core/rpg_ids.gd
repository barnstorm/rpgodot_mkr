@tool
class_name RPGIds
extends RefCounted
## Stable ID rules: lowercase ASCII letters, digits and underscores, starting with a letter.

const SELF_SWITCHES := ["A", "B", "C", "D"]


static func is_valid(id: Variant) -> bool:
	if typeof(id) != TYPE_STRING:
		return false
	var s: String = id
	if s.is_empty() or s.length() > 64:
		return false
	var c0 := s.unicode_at(0)
	if c0 < 97 or c0 > 122:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return true


## Turns any display name into a valid ID candidate ("House Door" -> "house_door").
static func slug(text: String) -> String:
	var out := ""
	var last_us := false
	for ch in text.to_lower():
		var c := ch.unicode_at(0)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			out += ch
			last_us = false
		elif not last_us and out != "":
			out += "_"
			last_us = true
	out = out.rstrip("_")
	if out == "" or not (out.unicode_at(0) >= 97 and out.unicode_at(0) <= 122):
		out = "id_" + out
	return out.left(64)


## Returns `base` or `base_2`, `base_3`... so that it is not in `taken` (Array or Dictionary).
## IDs listed in `retired` (deleted IDs) are never reused.
static func unique(base: String, taken: Variant, retired: Array = []) -> String:
	var b := base if is_valid(base) else slug(base)
	if not taken.has(b) and not retired.has(b):
		return b
	var n := 2
	var root := b
	var m := RegEx.create_from_string("^(.*)_(\\d+)$").search(b)
	if m:
		root = m.get_string(1)
		n = int(m.get_string(2)) + 1
	while taken.has("%s_%d" % [root, n]) or retired.has("%s_%d" % [root, n]):
		n += 1
	return "%s_%d" % [root, n]


static func self_switch_key(map_id: String, event_id: String, letter: String) -> String:
	return "%s/%s/%s" % [map_id, event_id, letter]
