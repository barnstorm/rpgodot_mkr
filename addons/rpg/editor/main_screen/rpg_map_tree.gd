@tool
class_name RPGMapTree
extends Tree
## Every map as a tree (maps nest under parent maps), with a Favourites list on top.
## Drag to reorder or re-parent. Right-click: New, Properties, Copy, Paste, Delete, Load sample map,
## Add to / remove from favourites.

signal map_selected(map_id: String)
signal map_action(action: String, map_id: String)
signal reorder_requested(index: Dictionary)

const PopupPlace := preload("res://addons/rpg/editor/rpg_popup_place.gd")

var data: RPGProjectData
var _items: Dictionary = {}


func _init() -> void:
	hide_root = true
	allow_rmb_select = true
	select_mode = Tree.SELECT_ROW
	custom_minimum_size = Vector2(200, 160)
	item_selected.connect(_on_selected)


func rebuild(p_data: RPGProjectData, selected := "") -> void:
	data = p_data
	clear()
	_items.clear()
	var root := create_item()
	var favs: Array = data.map_index.get("favourites", [])
	if not favs.is_empty():
		var fav_root := create_item(root)
		fav_root.set_text(0, "★ Favourites")
		fav_root.set_selectable(0, false)
		fav_root.set_custom_color(0, Color(1, 0.85, 0.4))
		for id in favs:
			if data.maps.has(id):
				var it := create_item(fav_root)
				it.set_text(0, _label(id))
				it.set_metadata(0, id)
	var maps: Array = data.map_index.get("maps", []).duplicate()
	maps.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	var project_item := create_item(root)
	project_item.set_text(0, str(data.project.get("name", "Project")))
	project_item.set_selectable(0, false)
	project_item.set_metadata(0, "")
	_add_children(project_item, "", maps)
	if selected != "" and _items.has(selected):
		_items[selected].select(0)
		scroll_to_item(_items[selected])


func _label(id: String) -> String:
	var e: Dictionary = data.map_entry(id)
	return "%s  (%s)" % [e.get("name", id), id] if str(e.get("name", id)) != id else id


func _add_children(parent_item: TreeItem, parent_id: String, maps: Array) -> void:
	for m in maps:
		if str(m.get("parent", "")) != parent_id:
			continue
		var it := create_item(parent_item)
		it.set_text(0, _label(m.id))
		it.set_tooltip_text(0, _label(m.id))
		it.set_metadata(0, m.id)
		_items[m.id] = it
		_add_children(it, m.id, maps)


## Highlights a map's row without emitting map_selected (the map is already open).
func select_map(id: String) -> void:
	if not _items.has(id):
		return
	set_block_signals(true)
	_items[id].select(0)
	set_block_signals(false)
	scroll_to_item(_items[id])


func selected_map() -> String:
	var it := get_selected()
	return str(it.get_metadata(0)) if it != null and it.get_metadata(0) != null else ""


func _on_selected() -> void:
	var id := selected_map()
	if id != "":
		map_selected.emit(id)


## Right-click anywhere in the tree: on a map, that map's menu; on the project row or empty space,
## the menu for new top-level maps (so a project with no maps can still get one).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var it := get_item_at_position(event.position)
		var id := ""
		if it != null and it.get_metadata(0) != null:
			id = str(it.get_metadata(0))
		if id != "":
			it.select(0)
		else:
			deselect_all()
		open_menu(id, event.global_position)
		accept_event()


## The map tree's context menu for `id` ("" = the project row / empty space).
func open_menu(id: String, at := Vector2(-1, -1)) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.add_item("New map...", 0)
	if id != "":
		menu.add_item("Properties...", 1)
		menu.add_separator()
		menu.add_item("Copy", 2)
		menu.add_item("Paste", 3)
		menu.add_item("Delete", 4)
		menu.add_separator()
		var favs: Array = data.map_index.get("favourites", [])
		menu.add_item("Remove from favourites" if favs.has(id) else "Add to favourites", 5)
		menu.add_item("Set as starting map (top-left free cell)", 6)
		menu.add_separator()
		menu.add_item("Shift contents...", 7)
		menu.add_item("Generate dungeon...", 9)
	else:
		menu.add_item("Paste", 3)
	menu.add_item("Load sample map...", 8)
	menu.id_pressed.connect(func(action_id: int):
		var names := {0: "new", 1: "properties", 2: "copy", 3: "paste", 4: "delete", 5: "favourite", 6: "start_here", 7: "shift", 8: "sample", 9: "dungeon"}
		map_action.emit(names.get(action_id, ""), id)
		menu.queue_free())
	menu.close_requested.connect(menu.queue_free)
	menu.popup_hide.connect(menu.queue_free)
	if at.x >= 0:
		PopupPlace.at_point(self, menu, at)
	else:
		PopupPlace.at_mouse(self, menu)
	return menu


# --- drag and drop: reorder or re-parent maps (IDs never change) ----------------------------------

func _get_drag_data(at_position: Vector2) -> Variant:
	var it := get_item_at_position(at_position)
	if it == null or it.get_metadata(0) == null or str(it.get_metadata(0)) == "":
		return null
	var lab := Label.new()
	lab.text = it.get_text(0)
	set_drag_preview(lab)
	drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	return {"rpg_map": str(it.get_metadata(0))}


func _can_drop_data(at_position: Vector2, d: Variant) -> bool:
	return d is Dictionary and d.has("rpg_map") and get_item_at_position(at_position) != null


func _drop_data(at_position: Vector2, d: Variant) -> void:
	drop_mode_flags = Tree.DROP_MODE_DISABLED
	var target := get_item_at_position(at_position)
	var section := get_drop_section_at_position(at_position)
	if target == null:
		return
	var moving: String = d.rpg_map
	var target_id := str(target.get_metadata(0)) if target.get_metadata(0) != null else ""
	if target_id == moving or _is_descendant(target_id, moving):
		return
	var index: Dictionary = data.map_index.duplicate(true)
	var entries: Array = index.get("maps", [])
	var mv: Dictionary = {}
	for m in entries:
		if m.id == moving:
			mv = m
	if mv.is_empty():
		return
	var new_parent := ""
	var insert_after := ""
	var insert_before := ""
	if section == 0 or target_id == "":
		new_parent = target_id
	else:
		var tgt: Dictionary = data.map_entry(target_id)
		new_parent = str(tgt.get("parent", ""))
		if section > 0:
			insert_after = target_id
		else:
			insert_before = target_id
	mv["parent"] = new_parent
	var siblings := entries.filter(func(m): return str(m.get("parent", "")) == new_parent and m.id != moving)
	siblings.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	var ordered := []
	for s in siblings:
		if s.id == insert_before:
			ordered.append(mv)
		ordered.append(s)
		if s.id == insert_after:
			ordered.append(mv)
	if not ordered.has(mv):
		ordered.append(mv)
	for i in ordered.size():
		ordered[i]["order"] = i
	reorder_requested.emit(index)


func _is_descendant(id: String, ancestor: String) -> bool:
	var cur := id
	var guard := 0
	while cur != "" and guard < 100:
		if cur == ancestor:
			return true
		cur = str(data.map_entry(cur).get("parent", ""))
		guard += 1
	return false
