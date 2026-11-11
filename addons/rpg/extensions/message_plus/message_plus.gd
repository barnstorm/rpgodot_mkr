extends "res://addons/rpg/runtime/rpg_extension.gd"
## Message codes plus (kit plugin "message_plus"). Adds to Show Text:
##   word wrap       setting, or <wordwrap> / <nowrap> per message; <br> starts a new line
##   \{  \}          text one step bigger / smaller; \FS[n] sets the size (\FS[] = normal)
##   <b> </b>        bold;   <i> </i>  italic
##   \M[name]        a text macro from the settings
##   keywords        words from the settings (and actor names) drawn in their colour
##   \NB[pos]        name box at left, center or right for this message (setting otherwise)
## The "Change message style" command changes word wrap and the name box for the rest of the
## game (saved).

const SECTION := "message_plus"
## The message box's font size (RPGMessageBox: 11 px).
const BASE_SIZE := 11
const NAME_BOX_X := {"left": 0.0, "center": 0.5, "right": 1.0}

var _name_panel: Panel = null
var _keyword_re: RegEx = null
var _keyword_colours: Dictionary = {}
var _keyword_key := ""


func _extension_ready() -> void:
	rpg.register_text_preprocessor(_wrap_pass)
	rpg.register_text_preprocessor(_keyword_pass)
	rpg.register_text_code("M", _macro)
	rpg.register_text_code("{", func(_a: String, info: Dictionary) -> Variant: return _set_size(info, int(info.flags.get("_fs", BASE_SIZE)) + _step()))
	rpg.register_text_code("}", func(_a: String, info: Dictionary) -> Variant: return _set_size(info, int(info.flags.get("_fs", BASE_SIZE)) - _step()))
	rpg.register_text_code("FS", func(a: String, info: Dictionary) -> Variant: return _set_size(info, a.to_int() if a.strip_edges().is_valid_int() else BASE_SIZE))
	rpg.register_text_code("KC", _key_colour)
	rpg.register_text_code("NB", func(a: String, _info: Dictionary) -> Variant: return {"flags": {"name_box": a.strip_edges().to_lower()}})
	rpg.register_text_tag("b", func(_a: String, _i: Dictionary) -> Variant: return {"bbcode": "[b]"})
	rpg.register_text_tag("/b", func(_a: String, _i: Dictionary) -> Variant: return {"bbcode": "[/b]"})
	rpg.register_text_tag("i", func(_a: String, _i: Dictionary) -> Variant: return {"bbcode": "[i]"})
	rpg.register_text_tag("/i", func(_a: String, _i: Dictionary) -> Variant: return {"bbcode": "[/i]"})
	# Read by _wrap_pass; left in macro text they just disappear.
	rpg.register_text_tag("wordwrap", func(_a: String, _i: Dictionary) -> Variant: return null)
	rpg.register_text_tag("nowrap", func(_a: String, _i: Dictionary) -> Variant: return null)
	rpg.register_text_tag("br", func(_a: String, _i: Dictionary) -> Variant: return {"text": "\n"})


func _step() -> int:
	return clampi(int(setting("size_step", 2)), 1, 8)


# --- word wrap -----------------------------------------------------------------------------------

## Word wrap for the whole game: the setting, unless "Change message style" changed it.
func word_wrap_default() -> bool:
	var s := section(SECTION)
	if s.has("word_wrap"):
		return bool(s.word_wrap)
	return bool(setting("word_wrap", false))


func _wrap_pass(text: String, info: Dictionary) -> String:
	var on := word_wrap_default()
	if int(info.get("depth", 0)) > 0:
		on = bool(info.flags.get("word_wrap", on))
	var low := text.to_lower()
	if low.contains("<nowrap>"):
		on = false
	elif low.contains("<wordwrap>"):
		on = true
	info.flags["word_wrap"] = on
	if on:
		text = text.replace("\r\n", "\n").replace("\n", " ")
		while text.contains("  "):
			text = text.replace("  ", " ")
	return RegEx.create_from_string("(?i)<br\\s*/?>").sub(text, "\n", true)


# --- font size -----------------------------------------------------------------------------------

func _set_size(info: Dictionary, size: int) -> Dictionary:
	size = clampi(size, 6, 48)
	var out := ""
	if bool(info.flags.get("_fs_open", false)):
		out += "[/font_size]"
	info.flags["_fs"] = size
	info.flags["_fs_open"] = size != BASE_SIZE
	if size != BASE_SIZE:
		out += "[font_size=%d]" % size
	return {"bbcode": out}


# --- macros --------------------------------------------------------------------------------------

func _macro(arg: String, _info: Dictionary) -> Variant:
	var want := arg.strip_edges().to_lower()
	for m in setting("macros", []):
		if m is Dictionary and str(m.get("name", "")).strip_edges().to_lower() == want:
			return str(m.get("text", ""))
	return null


# --- keyword colours -----------------------------------------------------------------------------

func _key_colour(arg: String, _info: Dictionary) -> Variant:
	var a := arg.strip_edges()
	if a == "":
		return {"bbcode": "[/color]"}
	return {"bbcode": "[color=%s]" % a}


static func _hex(c: Variant) -> String:
	if c is Array and c.size() >= 3:
		return "#" + Color8(int(c[0]), int(c[1]), int(c[2])).to_html(false)
	if c is String and str(c) != "":
		return str(c) if str(c).begins_with("#") else "#" + str(c)
	return "#ffe08a"


static func _re_escape(s: String) -> String:
	var out := ""
	for ch in s:
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\"
		out += ch
	return out


## word (lower case) -> colour, from the settings and (optionally) the actors' names.
func keyword_colours() -> Dictionary:
	var out := {}
	if bool(setting("colour_actor_names", false)) and rpg.data != null:
		var hex := _hex(setting("actor_colour", [138, 180, 255, 255]))
		for rec in rpg.data.records("actors"):
			var n := str(rec.get("name", "")).strip_edges()
			if n != "":
				out[n.to_lower()] = hex
		for id in rpg.state.actors:
			var b: Variant = rpg.state.actors[id]
			var n2 := str(b.get("name", "")) if b is Dictionary else (str(b.name) if b is Object and "name" in b else "")
			if n2.strip_edges() != "":
				out[n2.strip_edges().to_lower()] = hex
	for k in setting("keywords", []):
		if k is Dictionary and str(k.get("word", "")).strip_edges() != "":
			out[str(k.word).strip_edges().to_lower()] = _hex(k.get("colour"))
	return out


func _keyword_pass(text: String, _info: Dictionary) -> String:
	var colours := keyword_colours()
	if colours.is_empty():
		return text
	if bool(setting("colour_actor_names", false)):
		# \N[id] and \P[n] become the names here, so they are coloured like typed names.
		var name_re := RegEx.create_from_string("\\\\[NnPp]\\[[^\\]]*\\]")
		var parts := ""
		var at := 0
		for m in name_re.search_all(text):
			parts += text.substr(at, m.get_start() - at) + RPGText.escape(_name_of_code(m.get_string()))
			at = m.get_end()
		text = parts + text.substr(at)
	var key := str(colours)
	if key != _keyword_key:
		var words: Array = colours.keys()
		words.sort_custom(func(a, b): return str(a).length() > str(b).length())
		var alts := PackedStringArray()
		for w in words:
			alts.append(_re_escape(str(w)))
		_keyword_re = RegEx.create_from_string("(?i)(?<![\\w])(" + "|".join(alts) + ")(?![\\w])")
		_keyword_colours = colours
		_keyword_key = key
	# Only plain text is coloured: codes (\X[...]) and tags (<...>) are kept as they are.
	var code_re := RegEx.create_from_string("\\\\[A-Za-z]+(\\[[^\\]]*\\])?|\\\\.|<[^>]*>")
	var out := ""
	var last := 0
	for m in code_re.search_all(text):
		out += _colour_words(text.substr(last, m.get_start() - last))
		out += m.get_string()
		last = m.get_end()
	return out + _colour_words(text.substr(last))


## The name \N[actor] or \P[n] stands for.
func _name_of_code(code: String) -> String:
	var arg := code.substr(3, code.length() - 4)
	if code.substr(1, 1).to_upper() == "N":
		return RPGText._actor_name(rpg, arg)
	var idx := arg.to_int() - 1
	if idx >= 0 and idx < rpg.state.party.size():
		return RPGText._actor_name(rpg, rpg.state.party[idx])
	return ""


func _colour_words(part: String) -> String:
	if part == "" or _keyword_re == null:
		return part
	var out := ""
	var last := 0
	for m in _keyword_re.search_all(part):
		out += part.substr(last, m.get_start() - last)
		var w := m.get_string(1)
		out += "\\KC[%s]%s\\KC[]" % [_keyword_colours.get(w.to_lower(), "#ffe08a"), w]
		last = m.get_end()
	return out + part.substr(last)


# --- message box ---------------------------------------------------------------------------------

## The name box position for the whole game: the setting, unless changed by an event.
func name_box_default() -> String:
	var s := section(SECTION)
	if s.has("name_box"):
		return str(s.name_box)
	return str(setting("name_box", "left"))


func on_message_opened(params: Dictionary) -> void:
	var box: Node = rpg.ui.message_box if rpg.ui != null else null
	if box == null or not ("text_label" in box) or box.text_label == null:
		return
	_ensure_fonts(box.text_label)
	var flags: Dictionary = params.get("flags", {})
	if bool(flags.get("word_wrap", false)):
		box.text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if "name_label" in box and box.name_label != null:
		place_name_box(box, str(flags.get("name_box", name_box_default())))


## Puts the speaker's name at the left, centre or right above the message window, with a small
## window behind it when the setting asks for one.
func place_name_box(box: Node, where: String) -> void:
	var lab: Label = box.name_label
	var panel: Control = box.panel
	var f := lab.get_theme_font("font")
	var fs := lab.get_theme_font_size("font_size")
	var w := f.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else lab.text.length() * 6.0
	var t := float(NAME_BOX_X.get(where, 0.0))
	var x := roundf(8.0 + (panel.size.x - 16.0 - w) * t)
	lab.position.x = x
	var want_window: bool = bool(setting("name_box_window", true)) and lab.visible and lab.text != ""
	if want_window and (_name_panel == null or not is_instance_valid(_name_panel)):
		_name_panel = Panel.new()
		_name_panel.name = "NameBox"
		_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(_name_panel)
		panel.move_child(_name_panel, lab.get_index())
	if _name_panel != null and is_instance_valid(_name_panel):
		_name_panel.visible = want_window
		_name_panel.position = Vector2(x - 5, lab.position.y - 2)
		_name_panel.size = Vector2(w + 10, float(fs) + 6)


## Bold and italic come from the message font (thicker, slanted) unless the theme has them.
static func _ensure_fonts(label: RichTextLabel) -> void:
	if label.has_theme_font_override("bold_font"):
		return
	var base: Font = label.get_theme_font("normal_font")
	if base == null:
		return
	var slant := Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.9
	var ital := FontVariation.new()
	ital.base_font = base
	ital.variation_transform = slant
	var both := FontVariation.new()
	both.base_font = base
	both.variation_embolden = 0.9
	both.variation_transform = slant
	label.add_theme_font_override("bold_font", bold)
	label.add_theme_font_override("italics_font", ital)
	label.add_theme_font_override("bold_italics_font", both)


## Changes word wrap ("on", "off", "default") and the name box ("left", "center", "right",
## "default") for the rest of the game; "keep" leaves one as it is.
func set_style(word_wrap: String, name_box: String) -> void:
	var s := section(SECTION)
	match word_wrap:
		"on": s["word_wrap"] = true
		"off": s["word_wrap"] = false
		"default": s.erase("word_wrap")
	if name_box in ["left", "center", "right"]:
		s["name_box"] = name_box
	elif name_box == "default":
		s.erase("name_box")
