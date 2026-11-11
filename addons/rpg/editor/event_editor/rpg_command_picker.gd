@tool
class_name RPGCommandPicker
extends ConfirmationDialog
## Command picker: one tab per category plus a search box. Commands from extensions appear in
## their own "★" categories next to the built-in ones.

signal picked(type: String)

const CATEGORY_ORDER := ["message", "flow", "state", "party", "rules", "movement", "screen", "pictures", "audio", "scenes", "godot"]

var registry: RPGCommandRegistry
var _search: LineEdit
var _tabs: TabContainer
var _results: ItemList
var _lists: Array = []   # [{list: ItemList, types: Array}]


func _init(p_registry: RPGCommandRegistry = null) -> void:
	registry = p_registry
	title = "Insert command"
	ok_button_text = "Insert"
	min_size = Vector2i(560, 420)
	var vb := VBoxContainer.new()
	add_child(vb)
	_search = LineEdit.new()
	_search.placeholder_text = "Search commands…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search)
	_search.text_submitted.connect(func(_t): _accept_current())
	vb.add_child(_search)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_tabs)
	_results = ItemList.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.visible = false
	_results.item_activated.connect(func(_i): _accept_current())
	vb.add_child(_results)
	confirmed.connect(_accept_current)
	_build()


func _build() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	_lists.clear()
	if registry == null:
		return
	var by_cat := {}
	for d in registry.all_descriptors():
		var cmd: RPGCommand = registry.get_command(d.type)
		var cat := str(d.get("category", "other"))
		if cmd != null and cmd.extension_id != "builtin":
			cat = "★ " + cat
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(d)
	var cats: Array = by_cat.keys()
	cats.sort_custom(func(a, b):
		var ia := CATEGORY_ORDER.find(a)
		var ib := CATEGORY_ORDER.find(b)
		ia = 100 if ia == -1 else ia
		ib = 100 if ib == -1 else ib
		return [ia, a] < [ib, b])
	for cat in cats:
		var list := ItemList.new()
		list.name = str(cat).capitalize() if not str(cat).begins_with("★") else str(cat)
		list.item_activated.connect(func(_i): _accept_current())
		var types := []
		for d in by_cat[cat]:
			list.add_item(str(d.get("label", d.type)))
			list.set_item_tooltip(list.item_count - 1, str(d.type))
			types.append(d.type)
		_tabs.add_child(list)
		_lists.append({"list": list, "types": types})


func open() -> void:
	_search.text = ""
	_on_search("")
	popup_centered()
	_search.grab_focus()


func _on_search(t: String) -> void:
	var q := t.strip_edges().to_lower()
	_results.visible = q != ""
	_tabs.visible = q == ""
	_results.clear()
	if q == "" or registry == null:
		return
	for d in registry.all_descriptors():
		var label := str(d.get("label", d.type))
		if label.to_lower().find(q) != -1 or str(d.type).find(q) != -1 or str(d.get("category", "")).find(q) != -1:
			_results.add_item("%s  (%s)" % [label, d.get("category", "")])
			_results.set_item_metadata(_results.item_count - 1, d.type)
	if _results.item_count > 0:
		_results.select(0)


func _accept_current() -> void:
	var type := ""
	if _results.visible:
		var sel := _results.get_selected_items()
		if not sel.is_empty():
			type = str(_results.get_item_metadata(sel[0]))
	else:
		var tab := _tabs.current_tab
		if tab >= 0 and tab < _lists.size():
			var sel2: PackedInt32Array = _lists[tab].list.get_selected_items()
			if not sel2.is_empty():
				type = _lists[tab].types[sel2[0]]
	if type == "":
		return
	hide()
	picked.emit(type)
