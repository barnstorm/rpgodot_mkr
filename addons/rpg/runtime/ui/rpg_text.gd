class_name RPGText
extends RefCounted
## Message text codes (by stable ID, not number):
##   \V[id] variable value      \S[id] switch ON/OFF       \N[actor_id] actor name
##   \P[n] name of party member n (1-based)                \G currency unit
##   \C[n] text colour (0 = default, 1-15 palette)         \\ a backslash
##   \. wait 1/4 s   \| wait 1 s   \! wait for a key   \> \< show the rest instantly / stop
##   \I[n] icon n of the icon sheet (RPG Maker VX/MV; RPGIcons), one character wide; dropped when
##         System "show_icons" is off or the icon does not exist
## expand() returns {bbcode, plain_length, waits: [{at, seconds|key}], icons: [n, ...],
## actions: [{at, call: Callable}], flags: {}}.
##
## Extensions add codes, tags and text passes through the RPG service (register_text_code,
## register_text_tag, register_text_preprocessor). A code is a backslash and a name (letters,
## or one symbol) with an optional [arg]; the longest registered name wins and the built-in
## letters above keep their meaning. A tag is <name>, <name:arg> or </name>. A handler gets
## (arg, info) and returns a String (inserted, its codes read too) or a Dictionary:
##   text: String inserted (escaped; "codes": true reads codes in it), bbcode: formatting
##   (zero width unless "width"), action: Callable fired when the typewriter reaches this point,
##   wait: seconds, flags: merged into the result's flags (message-wide switches).
## info = {rpg, flags: Dictionary shared by the whole message, depth}.

## Icon size (px) of \I[n] in message text (the message font is 11 px).
const ICON_SIZE := 12
const PALETTE := [
	Color.WHITE, Color("#8ab4ff"), Color("#ff8a8a"), Color("#8aff9e"), Color("#ffe08a"),
	Color("#c18aff"), Color("#8affff"), Color("#bbbbbb"), Color("#666666"), Color("#ffb070"),
	Color("#70b0ff"), Color("#ff70b0"), Color("#b0ff70"), Color("#ffd700"), Color("#a0a0ff"), Color("#000000"),
]


## Escapes plain text so it shows literally (used when a quick-event answer is inserted).
static func escape(text: String) -> String:
	return text.replace("\\", "\\\\")


## Codes and tags read inside text a handler inserted are expanded up to this depth (macros
## that name each other stop here instead of looping).
const MAX_DEPTH := 4
## One-character codes the kit owns (extensions cannot register these).
const BUILTIN_CODES := "VSNPGCI\\.|!><$^"


static func expand(text: String, rpg: Node, info: Dictionary = {}) -> Dictionary:
	var out := ""
	var plain := 0
	var waits := []
	var actions := []
	var i := 0
	var color_open := false
	var icons := []
	var codes: Dictionary = _ext(rpg, "text_codes")
	var tags: Dictionary = _ext(rpg, "text_tags")
	if not info.has("flags"):
		info["flags"] = {}
	info["rpg"] = rpg
	var depth := int(info.get("depth", 0))
	if rpg != null and depth <= MAX_DEPTH:
		var pre: Variant = rpg.get("text_preprocessors")
		if pre is Array:
			for fn in pre:
				if fn is Callable and fn.is_valid():
					text = str(fn.call(text, info))
	while i < text.length():
		var ch := text[i]
		# Extension codes and tags (longest registered name first).
		if (ch == "\\" and not codes.is_empty()) or (ch == "<" and not tags.is_empty()):
			var hit := _ext_match(text, i, codes, tags)
			if not hit.is_empty() and depth <= MAX_DEPTH:
				var res: Variant = (hit.handler as Callable).call(hit.arg, info)
				var sub := _ext_result(res, rpg, info, plain)
				out += sub.bbcode
				waits.append_array(sub.waits)
				actions.append_array(sub.actions)
				icons.append_array(sub.icons)
				plain += int(sub.plain_length)
				i += int(hit.length)
				continue
		if ch == "\\" and i + 1 < text.length():
			var code := text[i + 1].to_upper()
			var arg := ""
			var consumed := 2
			if i + 2 < text.length() and text[i + 2] == "[":
				var close := text.find("]", i + 3)
				if close != -1:
					arg = text.substr(i + 3, close - i - 3)
					consumed = close - i + 1
			var insert := ""
			match code:
				"\\":
					insert = "\\"
					consumed = 2
				"V":
					insert = str(rpg.state.get_variable(arg)) if rpg else "0"
				"S":
					insert = ("ON" if rpg.state.get_switch(arg) else "OFF") if rpg else "OFF"
				"N":
					insert = _actor_name(rpg, arg)
				"P":
					var idx := arg.to_int() - 1
					if rpg and idx >= 0 and idx < rpg.state.party.size():
						insert = _actor_name(rpg, rpg.state.party[idx])
				"G":
					insert = rpg.data.currency() if rpg else "G"
					consumed = 2
				"C":
					if color_open:
						out += "[/color]"
						color_open = false
					var n := arg.to_int()
					if n > 0 and n < PALETTE.size():
						out += "[color=#%s]" % PALETTE[n].to_html(false)
						color_open = true
					i += consumed
					continue
				"I":
					var tag := _icon_tag(rpg, arg)
					if tag != "":
						out += tag
						icons.append(arg.to_int())
						plain += 1
					i += consumed
					continue
				".":
					waits.append({"at": plain, "seconds": 0.25})
					i += 2
					continue
				"|":
					waits.append({"at": plain, "seconds": 1.0})
					i += 2
					continue
				"!":
					waits.append({"at": plain, "key": true})
					i += 2
					continue
				">", "<", "$", "^":
					i += 2
					continue
				_:
					insert = "\\" + text[i + 1]
					consumed = 2
			out += _bb_escape(insert)
			plain += insert.length()
			i += consumed
			continue
		out += _bb_escape(ch)
		if ch != "\n":
			plain += 1
		else:
			plain += 1
		i += 1
	if color_open:
		out += "[/color]"
	return {"bbcode": out, "plain_length": plain, "waits": waits, "icons": icons, "actions": actions, "flags": info.flags}


static func _ext(rpg: Node, key: String) -> Dictionary:
	if rpg == null:
		return {}
	var d: Variant = rpg.get(key)
	return d if d is Dictionary else {}


## The extension code or tag at text[i]: {handler, arg, length} or {}.
static func _ext_match(text: String, i: int, codes: Dictionary, tags: Dictionary) -> Dictionary:
	if text[i] == "\\" and i + 1 < text.length():
		var best := ""
		for name in codes:
			var n: String = name
			if n.length() > best.length() and text.substr(i + 1, n.length()).to_upper() == n:
				best = n
		# The built-in one-character codes cannot be replaced.
		if best == "" or (best.length() == 1 and BUILTIN_CODES.contains(best)):
			return {}
		var end := i + 1 + best.length()
		var arg := ""
		if end < text.length() and text[end] == "[":
			var close := text.find("]", end + 1)
			if close != -1:
				arg = text.substr(end + 1, close - end - 1)
				end = close + 1
		return {"handler": codes[best], "arg": arg, "length": end - i}
	if text[i] == "<":
		var close2 := text.find(">", i + 1)
		if close2 == -1 or close2 - i > 64:
			return {}
		var inner := text.substr(i + 1, close2 - i - 1)
		var tname := inner.get_slice(":", 0).strip_edges().to_lower()
		if not tags.has(tname):
			return {}
		var targ := inner.substr(inner.find(":") + 1).strip_edges() if inner.contains(":") else ""
		return {"handler": tags[tname], "arg": targ, "length": close2 - i + 1}
	return {}


## Turns a handler's result into {bbcode, plain_length, waits, actions, icons}, positions moved
## past `at` (the plain characters already written).
static func _ext_result(res: Variant, rpg: Node, info: Dictionary, at: int) -> Dictionary:
	var r := {"bbcode": "", "plain_length": 0, "waits": [], "actions": [], "icons": []}
	if res == null:
		return r
	if res is String:
		res = {"text": res, "codes": true}
	if not (res is Dictionary):
		return r
	if res.get("flags") is Dictionary:
		info.flags.merge(res.flags, true)
	if res.get("action") is Callable:
		r.actions.append({"at": at, "call": res.action})
	if res.has("wait"):
		r.waits.append({"at": at, "seconds": float(res.wait)})
	r.bbcode += str(res.get("bbcode", ""))
	r.plain_length += int(res.get("width", 0))
	var t := str(res.get("text", ""))
	if t != "":
		if bool(res.get("codes", false)):
			var sub_info := {"flags": info.flags, "depth": int(info.get("depth", 0)) + 1}
			var sub := expand(t, rpg, sub_info)
			r.bbcode += sub.bbcode
			for w in sub.waits:
				w.at = int(w.at) + at + int(r.plain_length)
				r.waits.append(w)
			for a in sub.actions:
				a.at = int(a.at) + at + int(r.plain_length)
				r.actions.append(a)
			r.icons.append_array(sub.icons)
			r.plain_length += int(sub.plain_length)
		else:
			r.bbcode += _bb_escape(t)
			r.plain_length += t.length()
	r.bbcode += str(res.get("bbcode_after", ""))
	return r


## BBCode of \I[n]'s icon, or "" (icons off, no such icon).
static func _icon_tag(rpg: Node, arg: String) -> String:
	if not arg.strip_edges().is_valid_int():
		return ""
	var p: RPGProjectData = rpg.get("data") if rpg != null and rpg.get("data") is RPGProjectData else null
	if p != null and not RPGIcons.enabled(p):
		return ""
	return RPGIcons.bbcode(arg.strip_edges().to_int(), ICON_SIZE, p)


static func _actor_name(rpg: Node, id: String) -> String:
	if rpg == null:
		return id
	var b: Variant = rpg.state.actors.get(id)
	if b != null:
		if b is Dictionary:
			return str(b.get("name", id))
		if "name" in b and str(b.name) != "":
			return str(b.name)
	return str(rpg.data.record("actors", id).get("name", id))


static func _bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


## Plain text for labels (choices): value codes (\V \S \N \P \G and \\) are expanded, formatting
## and wait codes (\C, \., \|, \! ...) are dropped.
static func expand_plain(text: String, rpg: Node) -> String:
	if not _ext(rpg, "text_codes").is_empty() or not _ext(rpg, "text_tags").is_empty():
		# Extension codes in a label: expand fully, then drop the formatting.
		var bb := str(expand(text, rpg).bbcode).replace("[lb]", "\u0001")
		bb = RegEx.create_from_string("\\[[^\\]]*\\]").sub(bb, "", true)
		return bb.replace("\u0001", "[")
	var re := RegEx.create_from_string("\\\\(\\\\|[A-Za-z](\\[[^\\]]*\\])?|[.|!><$^])")
	var out := ""
	var last := 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		last = m.get_end()
		var code := m.get_string(1)
		if code == "\\":
			out += "\\"
			continue
		var letter := code.substr(0, 1).to_upper()
		var arg := m.get_string(2).trim_prefix("[").trim_suffix("]")
		match letter:
			"V":
				out += str(rpg.state.get_variable(arg)) if rpg else "0"
			"S":
				out += ("ON" if rpg.state.get_switch(arg) else "OFF") if rpg else "OFF"
			"N":
				out += _actor_name(rpg, arg)
			"P":
				var idx := arg.to_int() - 1
				if rpg and idx >= 0 and idx < rpg.state.party.size():
					out += _actor_name(rpg, rpg.state.party[idx])
			"G":
				out += rpg.data.currency() if rpg else "G"
	return out + text.substr(last)


static func strip_codes(text: String) -> String:
	var re := RegEx.create_from_string("\\\\[A-Za-z](\\[[^\\]]*\\])?|\\\\[.|!><$^]")
	return re.sub(text, "", true)
