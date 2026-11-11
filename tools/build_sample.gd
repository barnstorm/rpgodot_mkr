extends SceneTree
## Builds the sample game "Sample Quest" from code: three painted maps (town, house, field), their
## events, common events and the start position. Everything it writes is an ordinary project file
## that the editor can open and change.
##   godot --headless --path . --script res://tools/build_sample.gd

const ROOT := "res://rpg"

var data: RPGProjectData


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	data = RPGProjectData.open(ROOT)
	for id in ["town", "house_inside", "field"]:
		if data.maps.has(id):
			RPGMapFiles.delete_map(data, id)
	RPGMap.clear_tileset_cache()
	_town()
	_house()
	_field()
	_common_events()
	_system_start()
	print("Sample project built: ", data.maps.keys())
	quit(0)


# --- painting helpers ---------------------------------------------------------------------------

func _new_map(id: String, name: String, display: String, w: int, h: int, parent := "") -> RPGMap:
	var err := RPGMapFiles.create_map(data, id, name, "town", w, h, parent)
	assert(err == OK, "create_map %s failed: %d" % [id, err])
	var node := RPGMapFiles.load_map(data, id)
	get_root().add_child(node)
	for c in node.get_children():
		if c is TileMapLayer:
			c.set_meta(RPGAutotile.MAP_SIZE_META, Vector2i(w, h))
	var props: Dictionary = data.map_props(id).duplicate(true)
	props["display_name"] = display
	RPGMapFiles.save_props(data, id, props)
	return node


func _layer(node: RPGMap, key: String) -> TileMapLayer:
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key(key)
	return node.tile_layers[RPGTilesetBuilder.default_layer_for(a.source) - 1]


func put(node: RPGMap, c: Vector2i, key: String) -> void:
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key(key)
	assert(not a.is_empty(), "unknown tile key " + key)
	RPGAutotile.paint(_layer(node, key), c, a.source, a.coords, true)


func rect(node: RPGMap, r: Rect2i, key: String) -> void:
	var a: Dictionary = RPGTilesetBuilder.atlas_for_key(key)
	var cells := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			cells.append(Vector2i(x, y))
	var layer := _layer(node, key)
	if a.source == RPGTilesetBuilder.SOURCE_AUTOTILE:
		RPGAutotile.paint_cells(layer, cells, a.source, a.coords)
	else:
		for c in cells:
			layer.set_cell(c, a.source, a.coords)


func tree(node: RPGMap, c: Vector2i, pine := false) -> void:
	put(node, c, "upper_2" if pine else "upper_1")
	put(node, c + Vector2i.DOWN, "upper_8" if pine else "upper_7")


## A 5-wide house: two roof rows and a wall row. walls: 5 upper tile indices.
func house(node: RPGMap, at: Vector2i, walls: Array) -> void:
	var roof_top := [3, 4, 4, 4, 5]
	var roof_bottom := [9, 10, 10, 10, 11]
	for i in 5:
		put(node, at + Vector2i(i, 0), "upper_%d" % roof_top[i])
		put(node, at + Vector2i(i, 1), "upper_%d" % roof_bottom[i])
		put(node, at + Vector2i(i, 2), "upper_%d" % walls[i])


func region(node: RPGMap, r: Rect2i, n: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			node.regions.set_cell(Vector2i(x, y), 0, Vector2i(n % 16, n / 16))


func finish(node: RPGMap, events: Array, props_patch: Dictionary = {}) -> void:
	var w: int = node.tile_layers[0].get_meta(RPGAutotile.MAP_SIZE_META).x
	var h: int = node.tile_layers[0].get_meta(RPGAutotile.MAP_SIZE_META).y
	RPGAutotile.apply_auto_shadows(node.tile_layers, node.shadows, Rect2i(0, 0, w, h))
	var err := RPGMapFiles.save_scene(node, data.map_scene_path(node.map_id))
	assert(err == OK)
	RPGMapFiles.save_events_file(data, node.map_id, {"schema_version": 1, "map": node.map_id, "events": events})
	if not props_patch.is_empty():
		var props: Dictionary = data.map_props(node.map_id).duplicate(true)
		for k in props_patch:
			props[k] = props_patch[k]
		RPGMapFiles.save_props(data, node.map_id, props)
	node.queue_free()


# --- event helpers (same command sequences as the quick event templates) -----------------------------

static func page(graphic: Variant, trigger: String, commands: Array, extra: Dictionary = {}) -> Dictionary:
	var p := {
		"conditions": [],
		"graphic": graphic,
		"movement": {"type": "fixed", "speed": 3, "frequency": 3},
		"options": {"walk_anim": true, "step_anim": false, "direction_fix": false, "through": false},
		"priority": "same",
		"trigger": trigger,
		"commands": commands,
	}
	for k in extra:
		p[k] = extra[k]
	return p


static func ev(id: String, name: String, pos: Vector2i, pages: Array) -> Dictionary:
	return {"id": id, "name": name, "position": [pos.x, pos.y], "notes": "", "pages": pages}


static func npc(sheet_index: int, facing := "down") -> Dictionary:
	return {"sheet": "hero", "index": sheet_index, "facing": facing}


static func say(text: String, face := -1, speaker := "") -> Dictionary:
	var c := {"type": "show_text", "text": text, "face": null}
	if face >= 0:
		c["face"] = {"sheet": "hero_face", "index": face}
	if speaker != "":
		c["name"] = speaker
	return c


static func transfer_event(id: String, pos: Vector2i, to_map: String, to: Vector2i, facing: String) -> Dictionary:
	return ev(id, "Transfer", pos, [page(null, "player_touch", [
		{"type": "play_sound", "sound": {"role": "step"}},
		{"type": "transfer_player", "to": {"map": to_map, "position": [to.x, to.y]}, "facing": facing, "fade": "black"},
	], {"priority": "below"})])


static func door_event(id: String, pos: Vector2i, to_map: String, to: Vector2i, locked_pages: Array = []) -> Dictionary:
	var open_cmds := [
		{"type": "play_sound", "sound": {"role": "door_open"}},
		{"type": "move_route", "target": "this", "wait": true, "steps": [
			{"turn": "left"}, {"wait": 0.05}, {"turn": "right"}, {"wait": 0.05}, {"turn": "up"}, {"through": true},
		]},
		{"type": "move_route", "target": "player", "wait": true, "skip_if_blocked": true, "steps": [{"step": "forward"}]},
		{"type": "transfer_player", "to": {"map": to_map, "position": [to.x, to.y]}, "facing": "keep", "fade": "black"},
	]
	var pages := locked_pages.duplicate()
	var open_page := page({"sheet": "objects", "index": 0, "facing": "down"}, "action_button", open_cmds, {"options": {"walk_anim": false, "step_anim": false, "direction_fix": false, "through": false}})
	if not locked_pages.is_empty():
		open_page["conditions"] = [{"kind": "item", "id": "house_key"}]
	pages.append(open_page)
	return ev(id, "Door", pos, pages)


static func treasure_event(id: String, pos: Vector2i, give: Dictionary, label: String) -> Dictionary:
	var closed := page({"sheet": "objects", "index": 1, "facing": "down"}, "action_button", [
		{"type": "play_sound", "sound": {"role": "chest_open"}},
		{"type": "move_route", "target": "this", "wait": true, "steps": [{"turn": "left"}, {"wait": 0.05}, {"turn": "right"}, {"wait": 0.05}, {"turn": "up"}]},
		give,
		{"type": "show_text", "text": "Found %s!" % label},
		{"type": "set_self_switch", "switch": "A", "value": true},
	], {"options": {"walk_anim": false, "step_anim": false, "direction_fix": false, "through": false}})
	var opened := page({"sheet": "objects", "index": 1, "facing": "up"}, "action_button", [], {
		"conditions": [{"kind": "self_switch", "id": "A"}],
		"options": {"walk_anim": false, "step_anim": false, "direction_fix": true, "through": false},
	})
	return ev(id, "Treasure", pos, [closed, opened])


static func sign_event(id: String, pos: Vector2i, text: String) -> Dictionary:
	return ev(id, "Sign", pos, [page({"sheet": "objects", "index": 2, "facing": "down"}, "action_button", [{"type": "show_text", "text": text}], {"options": {"walk_anim": false, "step_anim": false, "direction_fix": true, "through": false}})])


static func inn_event(id: String, pos: Vector2i, price: int) -> Dictionary:
	return ev(id, "Inn", pos, [page(npc(4), "action_button", [
		{"type": "show_text", "gold_window": true, "name": "Innkeeper", "face": {"sheet": "hero_face", "index": 4}, "text": "Welcome! A night's stay is %d gold. Would you like to rest?" % price},
		{"type": "show_choices", "choices": [
			{"label": "Yes", "then": [
				{"type": "if", "condition": {"kind": "gold", "op": ">=", "value": price}, "then": [
					{"type": "change_gold", "operation": "decrease", "amount": price},
					{"type": "fade_out"},
					{"type": "play_jingle", "sound": {"role": "inn_rest"}},
					{"type": "wait", "seconds": 3},
					{"type": "recover_all", "target": "party"},
					{"type": "fade_in"},
					{"type": "show_text", "text": "Good morning! Safe travels."},
				], "else": [{"type": "show_text", "text": "Sorry, you don't have enough gold."}]},
			]},
			{"label": "No", "then": [{"type": "show_text", "text": "Please come again."}]},
		]},
	])])


static func shop_event(id: String, pos: Vector2i, goods: Array) -> Dictionary:
	return ev(id, "Shop", pos, [page(npc(3), "action_button", [
		{"type": "show_text", "name": "Shopkeeper", "face": {"sheet": "hero_face", "index": 3}, "text": "Welcome! Take a look."},
		{"type": "shop", "goods": goods, "buy_only": false},
	])])


# --- maps -----------------------------------------------------------------------------------------------------

func _town() -> void:
	var m := _new_map("town", "Town", "Riverside Village", 30, 22)
	rect(m, Rect2i(0, 0, 30, 22), "terrain_0")
	rect(m, Rect2i(2, 10, 28, 2), "terrain_1")
	rect(m, Rect2i(14, 3, 2, 17), "terrain_1")
	rect(m, Rect2i(5, 6, 1, 4), "terrain_1")
	rect(m, Rect2i(21, 6, 1, 4), "terrain_1")
	rect(m, Rect2i(16, 15, 9, 1), "terrain_1")
	rect(m, Rect2i(3, 14, 6, 5), "water_a")
	rect(m, Rect2i(10, 14, 3, 4), "terrain_6")
	for c in [Vector2i(9, 13), Vector2i(10, 18), Vector2i(2, 13), Vector2i(12, 13)]:
		put(m, c, "lower_3")
	for c in [Vector2i(8, 4), Vector2i(9, 5), Vector2i(17, 7), Vector2i(26, 8), Vector2i(11, 7), Vector2i(19, 18), Vector2i(26, 18)]:
		put(m, c, "lower_1")
	for c in [Vector2i(10, 4), Vector2i(18, 6), Vector2i(25, 9), Vector2i(12, 19), Vector2i(17, 19)]:
		put(m, c, "lower_2")
	# Border of trees, with a gap on the east side for the road to the field.
	for x in range(0, 30, 2):
		tree(m, Vector2i(x, 0), x % 4 == 0)
		tree(m, Vector2i(x, 20), x % 4 == 2)
	for y in range(2, 20, 2):
		tree(m, Vector2i(0, y), y % 4 == 0)
		if y != 10:
			tree(m, Vector2i(29, y), y % 4 == 2)
	put(m, Vector2i(29, 12), "upper_6")
	house(m, Vector2i(3, 3), [15, 21, 22, 21, 17])
	house(m, Vector2i(19, 3), [15, 23, 22, 21, 17])
	house(m, Vector2i(22, 12), [15, 35, 22, 21, 17])
	for x in range(8, 12):
		put(m, Vector2i(x, 8), "upper_12")
	put(m, Vector2i(25, 5), "upper_18")
	put(m, Vector2i(26, 5), "upper_19")
	put(m, Vector2i(17, 4), "upper_32")
	put(m, Vector2i(17, 5), "upper_38")
	put(m, Vector2i(12, 4), "upper_20")
	put(m, Vector2i(27, 15), "upper_36")
	put(m, Vector2i(20, 16), "upper_37")
	var events := [
		ev("elder", "Elder", Vector2i(7, 9), [
			page(npc(6), "autorun", [
				say("Ah, you're finally awake! Welcome to Riverside, \\N[hero].", 6, "Elder"),
				say("A goblin has been seen on the road east of the village.\\.\\. Would you look into it?", 6, "Elder"),
				say("Here, take the key to my house. Rest there whenever you need.", 6, "Elder"),
				{"type": "play_sound", "sound": {"role": "decision"}},
				{"type": "change_items", "item_kind": "items", "item": "house_key", "operation": "increase", "amount": 1},
				say("\\C[4]Received the House Key!\\C[0]"),
				{"type": "set_self_switch", "switch": "A", "value": true},
			]),
			page(npc(6), "action_button", [
				{"type": "if", "condition": {"kind": "switch", "id": "goblin_defeated"}, "then": [
					say("You drove off the goblin! The whole village thanks you, \\N[hero].", 6, "Elder"),
				], "else": [
					say("The goblin is somewhere on the eastern road. Buy potions at the shop first!", 6, "Elder"),
				]},
			], {"conditions": [{"kind": "self_switch", "id": "A"}]}),
		]),
		door_event("elder_door", Vector2i(5, 5), "house_inside", Vector2i(5, 8), [
			page({"sheet": "objects", "index": 0, "facing": "down"}, "action_button", [say("It's locked.")], {"options": {"walk_anim": false, "step_anim": false, "direction_fix": false, "through": false}}),
		]),
		treasure_event("garden_chest", Vector2i(7, 6), {"type": "change_items", "item_kind": "items", "item": "potion", "operation": "increase", "amount": 1}, "a Potion"),
		sign_event("village_sign", Vector2i(13, 9), "Riverside Village\nEast: the Green Field road.\nWest: the elder's house."),
		shop_event("shopkeeper", Vector2i(20, 6), [
			{"kind": "items", "id": "potion", "price": null},
			{"kind": "items", "id": "hi_potion", "price": null},
			{"kind": "items", "id": "antidote", "price": null},
			{"kind": "weapons", "id": "iron_sword", "price": null},
			{"kind": "armors", "id": "wooden_shield", "price": null},
		]),
		inn_event("innkeeper", Vector2i(23, 15), 20),
		ev("villager", "Villager", Vector2i(10, 12), [page(npc(2), "action_button", [
			say("Lovely weather today, isn't it?", 2, "Villager"),
			say("They say the old pond is full of fish. Talk to the fisherman!", 2, "Villager"),
		], {"movement": {"type": "random", "speed": 2, "frequency": 2}})]),
		ev("child", "Child", Vector2i(18, 14), [page(npc(7), "action_button", [
			{"type": "set_variable", "id": "talks", "operation": "add", "value": 1},
			{"type": "if", "condition": {"kind": "variable", "id": "talks", "op": ">=", "value": 3}, "then": [
				say("You've talked to me \\V[talks] times! Are you bored?", 7, "Child"),
				{"type": "show_balloon", "target": "this", "balloon": "music"},
			], "else": [
				say("Hi! I'm practising my sword moves!", 7, "Child"),
			]},
		], {"movement": {"type": "random", "speed": 3, "frequency": 3}})]),
		ev("fisherman", "Fisherman", Vector2i(9, 16), [page(npc(5, "left"), "action_button", [
			say("Want to try fishing? Press OK when the float is in the green zone.", 5, "Fisherman"),
			{"type": "show_choices", "choices": [
				{"label": "Let's fish!", "then": [
					{"type": "run_scene", "scene": "res://scenes/fishing/fishing.tscn", "args": {"rounds": 3, "speed": 1.0}, "result": "fish_caught", "on_cancel": [say("Come back any time.", 5, "Fisherman")]},
					{"type": "if", "condition": {"kind": "variable", "id": "fish_caught", "op": ">=", "value": 2}, "then": [
						say("\\V[fish_caught] fish! Here, take this for your trouble.", 5, "Fisherman"),
						{"type": "change_items", "item_kind": "items", "item": "hi_potion", "operation": "increase", "amount": 1},
					], "else": [
						say("Only \\V[fish_caught]. Keep practising!", 5, "Fisherman"),
					]},
				]},
				{"label": "Not now", "then": []},
			]},
		], {"options": {"walk_anim": true, "step_anim": false, "direction_fix": false, "through": false}})]),
		transfer_event("to_field_a", Vector2i(29, 10), "field", Vector2i(1, 10), "right"),
		transfer_event("to_field_b", Vector2i(29, 11), "field", Vector2i(1, 11), "right"),
	]
	finish(m, events, {"music": {"file": "town", "volume": 80, "pitch": 100, "pan": 0}})


func _house() -> void:
	var m := _new_map("house_inside", "Elder's house", "Elder's House", 12, 10, "town")
	rect(m, Rect2i(1, 2, 10, 7), "terrain_5")
	rect(m, Rect2i(0, 0, 12, 1), "lower_12")
	rect(m, Rect2i(0, 1, 12, 1), "lower_13")
	put(m, Vector2i(3, 1), "lower_14")
	put(m, Vector2i(8, 1), "lower_14")
	put(m, Vector2i(6, 1), "lower_15")
	for y in range(1, 10):
		put(m, Vector2i(0, y), "lower_12")
		put(m, Vector2i(11, y), "lower_12")
	for x in range(0, 12):
		if x != 5:
			put(m, Vector2i(x, 9), "lower_12")
	put(m, Vector2i(5, 9), "lower_10")
	put(m, Vector2i(9, 2), "upper_27")
	put(m, Vector2i(9, 3), "upper_33")
	put(m, Vector2i(5, 4), "upper_28")
	put(m, Vector2i(4, 4), "upper_29")
	put(m, Vector2i(6, 4), "upper_29")
	put(m, Vector2i(2, 2), "upper_34")
	put(m, Vector2i(10, 7), "upper_31")
	put(m, Vector2i(1, 7), "upper_30")
	var events := [
		transfer_event("exit", Vector2i(5, 9), "town", Vector2i(5, 6), "down"),
		treasure_event("house_chest", Vector2i(2, 7), {"type": "change_gold", "operation": "increase", "amount": 100}, "100 gold"),
		ev("bed", "Bed", Vector2i(9, 3), [page(null, "action_button", [
			say("A soft bed. Rest a while?"),
			{"type": "show_choices", "choices": [
				{"label": "Sleep", "then": [
					{"type": "fade_out", "seconds": 1.0},
					{"type": "play_jingle", "sound": {"role": "inn_rest"}, "wait": false},
					{"type": "wait", "seconds": 1.5},
					{"type": "recover_all", "target": "party"},
					{"type": "fade_in", "seconds": 1.0},
					say("You feel refreshed."),
				]},
				{"label": "Not now", "then": []},
			]},
		], {"priority": "below"})]),
		ev("mira", "Mira", Vector2i(3, 5), [
			page(npc(1), "action_button", [
				say("I'm Mira, the elder's apprentice. You're going after the goblin? Then I'm coming too!", 1, "Mira"),
				{"type": "change_party", "actor": "mira", "operation": "add"},
				{"type": "play_jingle", "sound": {"role": "level_up"}},
				say("\\C[3]Mira joined the party!\\C[0]"),
				{"type": "erase_event"},
			], {"movement": {"type": "random", "speed": 2, "frequency": 2}}),
			page(null, "action_button", [], {"conditions": [{"kind": "actor", "id": "mira"}], "priority": "below"}),
		]),
	]
	finish(m, events, {"music": {"file": "inn", "volume": 70, "pitch": 100, "pan": 0}})


func _field() -> void:
	var m := _new_map("field", "Green Field", "Green Field", 32, 20)
	rect(m, Rect2i(0, 0, 32, 20), "terrain_0")
	rect(m, Rect2i(2, 2, 12, 6), "terrain_6")
	rect(m, Rect2i(0, 10, 26, 2), "terrain_1")
	rect(m, Rect2i(18, 14, 6, 4), "water_a")
	rect(m, Rect2i(4, 14, 5, 3), "terrain_10")
	for x in range(0, 32, 2):
		tree(m, Vector2i(x, 0), x % 4 == 0)
		tree(m, Vector2i(x, 18), x % 4 == 2)
	for y in range(2, 18, 2):
		if y != 10:
			tree(m, Vector2i(0, y), true)
		tree(m, Vector2i(31, y), false)
	for c in [Vector2i(8, 6), Vector2i(12, 3), Vector2i(20, 4), Vector2i(24, 6), Vector2i(27, 13), Vector2i(14, 14)]:
		tree(m, c, c.x % 2 == 0)
	for c in [Vector2i(6, 12), Vector2i(7, 13), Vector2i(16, 8), Vector2i(17, 9), Vector2i(22, 8)]:
		put(m, c, "lower_3")
	put(m, Vector2i(10, 15), "upper_20")
	region(m, Rect2i(2, 2, 12, 6), 1)
	var events := [
		transfer_event("to_town_a", Vector2i(0, 10), "town", Vector2i(28, 10), "left"),
		transfer_event("to_town_b", Vector2i(0, 11), "town", Vector2i(28, 11), "left"),
		sign_event("field_sign", Vector2i(3, 9), "Green Field\nBats nest in the dark grass to the north."),
		ev("goblin", "Goblin", Vector2i(26, 10), [
			page(npc(5, "left"), "event_touch", [
				{"type": "shake_camera", "strength": 3.0, "seconds": 0.4, "wait": true},
				say("Hah! Nobody passes the Goblin of the Green Field!", -1, "Goblin"),
				{"type": "battle", "troop": "goblin_boss", "can_escape": false, "can_lose": false, "result": "battle_outcome", "on_win": [
					{"type": "set_switch", "id": "goblin_defeated", "value": "on"},
					say("The goblin drops its stolen armour and runs away!"),
				]},
			], {"movement": {"type": "approach", "speed": 2, "frequency": 2}}),
			page(null, "action_button", [], {"conditions": [{"kind": "switch", "id": "goblin_defeated"}], "priority": "below"}),
		]),
		ev("boulder", "Heavy pot", Vector2i(14, 11), [
			page({"sheet": "objects", "index": 3, "facing": "down"}, "action_button", [
				say("A huge pot blocks part of the road. Push it?"),
				{"type": "roll_check", "actor": "leader", "stat": "str", "dc": 12, "result": "door_check"},
				{"type": "if", "condition": {"kind": "variable", "id": "door_check", "op": "==", "value": true}, "then": [
					{"type": "move_route", "target": "this", "wait": true, "skip_if_blocked": true, "steps": [{"step": "up"}]},
					say("With a mighty shove, the pot slides aside!"),
					{"type": "set_self_switch", "switch": "A", "value": true},
				], "else": [
					say("It won't budge. (A strength check: try again!)"),
				]},
			], {"options": {"walk_anim": false, "step_anim": false, "direction_fix": true, "through": false}}),
			page({"sheet": "objects", "index": 3, "facing": "down"}, "action_button", [say("The pot is out of the way.")], {
				"conditions": [{"kind": "self_switch", "id": "A"}],
				"options": {"walk_anim": false, "step_anim": false, "direction_fix": true, "through": false},
			}),
		]),
	]
	finish(m, events, {
		"music": {"file": "field", "volume": 80, "pitch": 100, "pan": 0},
		"battle_background": "grass",
		"encounters": {"steps": 28, "groups": [
			{"troop": "slimes", "weight": 10, "regions": []},
			{"troop": "bats", "weight": 8, "regions": [1]},
		]},
	})


func _common_events() -> void:
	RPGJson.save_file(ROOT.path_join("common_events.json"), {
		"schema_version": 1,
		"common_events": [
			{"id": "rain", "name": "Rain", "trigger": "parallel", "switch": "rain", "commands": [
				{"type": "set_weather", "weather": "rain", "power": 6},
				{"type": "tint_screen", "red": 80, "green": 85, "blue": 100, "seconds": 1.0, "wait": true},
				{"type": "wait", "seconds": 5},
			]},
			{"id": "full_heal", "name": "Full heal", "trigger": "none", "switch": "", "commands": [
				{"type": "play_sound", "sound": {"role": "heal"}},
				{"type": "recover_all", "target": "party"},
			]},
		],
	})


func _system_start() -> void:
	var path := ROOT.path_join("database/system.json")
	var file: Dictionary = RPGJson.load_or(path, {"schema_version": 1, "system": {}})
	file.system["start"] = {"map": "town", "position": [14, 12], "facing": "up"}
	file.system["title_image"] = "title"
	RPGJson.save_file(path, file)
