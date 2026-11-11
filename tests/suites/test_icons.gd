extends "res://tests/rpg_test_case.gd"
## Icons: the generated starter sheets (both sizes) and icons.json, RPGIcons atlas regions and
## record lookups, the Database icon picker, icons in the menus and shop, the \I[n] message code,
## System "show_icons", and old data (an icon sheet's name in "icon") still loading.

const Env := preload("res://tests/rpg_test_env.gd")
const INDEX := "res://assets/starter/icons.json"
## Names other work relies on (README, starter database, editors).
const REQUIRED := [
	"sword", "broadsword", "dagger", "axe", "spear", "bow", "crossbow", "staff", "wand", "mace", "whip", "claw", "gun", "katana",
	"shield_round", "shield_heater", "helmet", "hat_wizard", "armor_plate", "robe", "gloves", "boots",
	"ring_ruby", "amulet_red", "potion_red", "potion_blue", "potion_green", "ether", "elixir", "herb", "bread",
	"scroll", "book_brown", "key_gold", "ruby", "sapphire", "coin_gold", "bag", "letter", "map", "crystal_blue", "feather",
	"fire", "ice", "thunder", "water", "earth", "wind", "light", "dark",
	"heal", "revive", "attack_up", "attack_down", "defense_up", "defense_down", "speed_up", "magic", "steal", "guard", "escape",
	"poison", "sleep", "silence", "confusion", "blind", "paralysis", "stun", "knockout", "regen", "berserk", "charm", "petrify",
]

var env
var _keep: Array = []


func after_each() -> void:
	if env != null:
		await env.destroy()
		env = null
	RPGIcons.use_project(null)
	RPGIcons.clear_cache()
	_keep.clear()


## A project with the sample data but another profile / System settings (kept alive for the test).
func _project(profile := "rm2k", system := {}) -> RPGProjectData:
	var p := RPGProjectData.open("res://rpg")
	p.profile["profile"] = profile
	for k in system:
		p.system[k] = system[k]
	_keep.append(p)
	RPGIcons.use_project(p)
	return p


func _index() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(INDEX))


func test_sheets_exist_in_both_sizes() -> void:
	var a := RPGAssets.load_texture("system", "starter/IconSet24")
	var b := RPGAssets.load_texture("system", "starter/IconSet32")
	assert_true(a != null and b != null, "both starter sheets load")
	assert_eq(a.get_width(), 16 * 24)
	assert_eq(b.get_width(), 16 * 32)
	assert_eq(RPGIcons.count(a), RPGIcons.count(b), "same icons in both sizes")
	assert_true(RPGIcons.count(a) >= 160, "at least 160 icons: %d" % RPGIcons.count(a))
	assert_true(ResourceLoader.exists("res://assets/starter/System/IconSet24.png"), "imported (\\I[n] uses the resource)")


func test_index_matches_sheet() -> void:
	var doc := _index()
	assert_eq(str(doc.license), "CC0-1.0")
	assert_eq(int(doc.columns), 16)
	var list: Array = doc.icons
	for size in [24, 32]:
		var tex := RPGAssets.load_texture("system", "starter/IconSet%d" % size)
		assert_eq(list.size(), RPGIcons.count(tex), "icons.json lists every icon of the %d px sheet" % size)
		var img := RPGAssets.texture_image(tex)
		for e in list:
			var i := int(e.index)
			var cell := img.get_region(Rect2i((i % 16) * size, (i / 16) * size, size, size))
			var drawn := not cell.is_invisible()
			var blank := i == 0 or str(e.name).begins_with("blank")
			assert_eq(drawn, not blank, "%d px icon %d (%s) is %s" % [size, i, e.name, "blank" if blank else "drawn"])
	var names := {}
	for i in list.size():
		assert_eq(int(list[i].index), i, "indices in order")
		assert_false(names.has(list[i].name), "unique name %s" % list[i].name)
		names[list[i].name] = true
		assert_true(str(list[i].category) != "", "category of %s" % list[i].name)
	for n in REQUIRED:
		assert_true(names.has(n), "icon %s exists" % n)
	assert_eq(RPGIcons.find("potion_red"), RPGIcons.entries().filter(func(e): return e.name == "potion_red")[0].index)
	assert_eq(RPGIcons.name_of(RPGIcons.find("sword")), "sword")
	assert_eq(RPGIcons.find("no_such_icon"), -1)


func test_atlas_regions() -> void:
	_project("rm2k")
	assert_eq(RPGIcons.sheet_name(), "starter/IconSet24", "2000/2003 projects use the 24 px set")
	var t := RPGIcons.texture(17) as AtlasTexture
	assert_eq(t.region, Rect2(24, 24, 24, 24))
	assert_eq(t.get_width(), 24)
	assert_eq((RPGIcons.texture(35) as AtlasTexture).region, Rect2(3 * 24, 2 * 24, 24, 24))
	assert_eq(RPGIcons.texture(0), null, "0 is no icon")
	assert_eq(RPGIcons.texture(-3), null)
	assert_eq(RPGIcons.texture(100000), null, "past the sheet")
	# A size other than the sheet's: the starter set drawn at that size, else a scaled copy.
	var big := RPGIcons.texture(17, 32) as AtlasTexture
	assert_eq(big.region, Rect2(32, 32, 32, 32))
	assert_eq(big.atlas.get_width(), 512, "the 32 px starter sheet, not a scaled one")
	var huge := RPGIcons.texture(17, 48) as AtlasTexture
	assert_eq(huge.region, Rect2(48, 48, 48, 48))
	assert_eq(huge.get_width(), 48)
	assert_true(RPGIcons.texture(17) == RPGIcons.texture(17), "cached")
	_project("vx")
	assert_eq(RPGIcons.sheet_name(), "starter/IconSet24", "VX / VX Ace: 24 px")
	_project("mv")
	assert_eq(RPGIcons.sheet_name(), "starter/IconSet32", "MV / MZ: 32 px")
	assert_eq((RPGIcons.texture(17) as AtlasTexture).region, Rect2(32, 32, 32, 32))


func test_icon_sheet_setting() -> void:
	_project("rm2k", {"icon_sheet": "IconSet32"})
	assert_eq(RPGIcons.sheet_name(), "IconSet32", "System icon_sheet wins over the profile")
	assert_eq(RPGIcons.texture(1).get_width(), 32)
	_project("rm2k", {"icon_sheet": "NoSuchSheet"})
	assert_eq(RPGIcons.sheet_name(), "starter/IconSet24", "a missing sheet falls back to the starter set")
	assert_true(RPGIcons.enabled())
	_project("rm2k", {"show_icons": false})
	assert_false(RPGIcons.enabled())


func test_for_record_and_old_data() -> void:
	_project("rm2k")
	var t := RPGIcons.for_record({"icon": 64}) as AtlasTexture
	assert_eq(t.region, Rect2(0, 4 * 24, 24, 24))
	assert_eq(RPGIcons.icon_index({"icon": 64.0}), 64, "JSON numbers are floats")
	assert_eq(RPGIcons.icon_index({"icon": "12"}), 12)
	# Old data: the field held the icon sheet's name (or ""): no icon, no error.
	assert_eq(RPGIcons.icon_index({"icon": "IconSet"}), 0)
	assert_eq(RPGIcons.icon_index({"icon": ""}), 0)
	assert_eq(RPGIcons.icon_index({}), 0)
	assert_eq(RPGIcons.icon_index({"icon": "IconSet", "icon_index": 5}), 5)
	assert_eq(RPGIcons.for_record({"icon": "IconSet"}), null)
	assert_eq(RPGIcons.for_record({}), null)


func test_sample_and_template_records_have_icons() -> void:
	for root in ["res://rpg/database", "res://addons/rpg/templates/new_project/database"]:
		for type in ["items", "weapons", "armors", "skills", "states"]:
			var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(type + ".json")))
			for rec in doc.records:
				assert_true(RPGIcons.icon_index(rec) > 0, "%s %s/%s has an icon" % [root, type, rec.id])
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://rpg/database/items.json"))
	assert_eq(int(items.records[0].icon), RPGIcons.find("potion_red"))


func test_picker_grid_and_search() -> void:
	var p := RPGIconPicker.new(_project("rm2k"))
	tree.root.add_child(p)
	var got := []
	p.value_changed.connect(func(v): got.append(v))
	p.set_value("IconSet")
	assert_eq(p.get_value(), 0, "old data (a sheet name) reads as no icon")
	p.set_value(64)
	assert_eq(p._button.text, "#64 potion red")
	assert_true(p._thumb.texture != null)
	p.open_popup()
	assert_eq(p.cell_rect(17), Rect2(48, 48, 48, 48), "24 px icons shown at 2x")
	assert_eq(p.index_at(Vector2(48 + 10, 48 + 10)), 17)
	p.search("red potion")
	assert_true(p.matches().has(64), "words in any order: %s" % str(p.matches()))
	assert_false(p.matches().has(65))
	p.search("state")
	assert_true(p.matches().has(RPGIcons.find("poison")), "categories match")
	p.search("128")
	assert_eq(p.matches(), [128])
	p._search.text_submitted.emit("128")
	assert_eq(got, [128], "Enter takes the first match")
	assert_eq(p.get_value(), 128)
	# A click on the grid chooses that icon.
	p.open_popup()
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p.cell_rect(16).get_center()
	p._grid_input(ev)
	assert_eq(p.get_value(), 16)
	p.pick(0)
	assert_eq(p._button.text, "(none)")
	p.queue_free()
	await frames(1)


func test_form_icon_field() -> void:
	var fields: Array = RPGRecordSchemas.fields_for("items")
	var form := RPGFormBuilder.new()
	tree.root.add_child(form)
	form.setup(fields, RPGProjectData.open("res://rpg"))
	form.set_value({"id": "old", "name": "Old", "icon": "IconSet"})
	assert_true(form.editor_for("icon") is RPGIconPicker)
	assert_eq(form.get_value().icon, "IconSet", "old data is left alone until the icon is changed")
	(form.editor_for("icon") as RPGIconPicker).pick(66)
	assert_eq(form.get_value().icon, 66)
	var sys: Array = RPGRecordSchemas.fields_for("system")
	assert_true(sys.any(func(f): return f.key == "icon_sheet" and f.res == "iconset"))
	assert_true(sys.any(func(f): return f.key == "show_icons" and f.default == true))
	form.queue_free()
	await frames(1)


func _open(key: String) -> Node:
	var node: Node = env.rpg.ui.open_scene(env.rpg.ui.scene_path(key))
	await frames(2)
	return node


func test_menu_lists_show_icons() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	var menu: Node = await _open("menu")
	menu.choose("item")
	var it: Dictionary = menu.list.items[0]
	assert_eq(it.data, "potion")
	assert_true(it.icon is AtlasTexture, "the item list shows the potion's icon")
	assert_eq((it.icon as AtlasTexture).region, (RPGIcons.texture(RPGIcons.find("potion_red")) as AtlasTexture).region)
	menu.handle_action("cancel")
	# Skills
	menu.open_skills(rpg.state.actor("hero"))
	for e in menu.list.items:
		assert_true(e.icon is Texture2D, "skill %s has an icon" % e.data)
	menu.handle_action("cancel")
	# Equipment: slots show the equipped item's icon, candidates their own.
	rpg.state.change_items("iron_sword", "increase", 1, "weapons")
	menu.open_equip(rpg.state.actor("hero"))
	var slot_icons: Array = menu.slot_list.items.filter(func(e): return e.get("right_icon") is Texture2D)
	assert_true(not slot_icons.is_empty(), "an equipped item's icon is shown")
	menu.slot_list.select(menu.slot_ids.find("weapon"))
	menu._refresh_candidates(false)
	assert_true(menu.cand_list.items[0].icon is Texture2D, "candidate icon")
	assert_eq(menu.cand_list.items.back().get("icon"), null, "(Remove) has none")
	# show_icons off: the old look.
	rpg.data.system["show_icons"] = false
	menu._refresh_candidates(false)
	assert_eq(menu.cand_list.items[0].get("icon"), null)
	menu.close()
	await frames(1)


func test_states_show_icons() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	var hero: RPGBattler = rpg.state.actor("hero")
	rpg.rules.add_state(hero, "poison")
	var menu: Node = await _open("menu")
	var poison_icon := RPGIcons.for_record(rpg.data.record("states", "poison"))
	var found: Array = menu.party_rows.find_children("*", "TextureRect", true, false).filter(func(t): return t.texture == poison_icon)
	assert_eq(found.size(), 1, "the party window shows the poison icon")
	var names: Array = menu.party_rows.find_children("*", "Label", true, false).filter(func(l): return l.text == "Poison")
	assert_eq(names.size(), 1, "and its name when there is room")
	menu.open_status(0)
	await frames(1)
	found = menu.view.find_children("*", "TextureRect", true, false).filter(func(t): return t.texture == poison_icon)
	assert_eq(found.size(), 1, "the status screen shows the poison icon")
	# A narrow column: a single state's name alone, never cut ("Knocked out" stays readable).
	var box := Control.new()
	menu.add_child(box)
	var c: Control = menu.make_states(box, Vector2.ZERO, hero, 30, 9)
	assert_true(c is Label and c.text == "Poison", "too narrow for icon and name: the name")
	rpg.rules.add_state(hero, "sleep")
	c = menu.make_states(box, Vector2.ZERO, hero, 40, 9)
	assert_eq(c.find_children("*", "TextureRect", true, false).size(), 2, "several states: icons")
	rpg.data.system["show_icons"] = false
	c = menu.make_states(box, Vector2.ZERO, hero, 200, 9)
	assert_true(c is Label and c.text == "Poison, Sleep", "show_icons off: names, as before")
	menu.close()
	await frames(1)


func test_shop_shows_icons() -> void:
	env = Env.create(tree, "res://rpg")
	var shop: Node = await _open("shop")
	shop.start({"goods": [{"kind": "items", "id": "potion"}, {"kind": "weapons", "id": "iron_sword"}], "buy_only": false}, {"rpg": env.rpg})
	await frames(1)
	shop.handle_action("ok")
	assert_eq(shop.mode, "buy")
	for e in shop.list.items:
		assert_true(e.icon is Texture2D, "buy list icon for %s" % e.data.id)
	shop.handle_action("cancel")
	shop.handle_action("down")
	shop.handle_action("ok")
	assert_eq(shop.mode, "sell")
	assert_true(shop.list.items[0].icon is Texture2D, "sell list icon")


func test_message_icon_code() -> void:
	env = Env.create(tree, "res://rpg")
	var rpg: Node = env.rpg
	var r := RPGText.expand("Got \\I[64] Potion!\\.", rpg)
	assert_eq(r.icons, [64])
	assert_true(str(r.bbcode).contains("[img width=12 height=12 region=0,96,24,24]res://assets/starter/System/IconSet24.png[/img]"), r.bbcode)
	assert_eq(r.plain_length, "Got ".length() + 1 + " Potion!".length(), "the icon counts as one character")
	assert_eq(r.waits[0].at, r.plain_length, "waits after an icon stay in place")
	assert_eq(RPGText.expand("\\I[0]\\I[99999]x", rpg).bbcode, "x", "no such icon: dropped")
	assert_eq(RPGText.strip_codes("a\\I[3]b"), "ab")
	assert_eq(RPGText.expand_plain("a\\I[3]b", rpg), "ab")
	assert_eq(RPGFormBuilder.preview_text("a\\I[64]b", null), "a«icon potion red»b", "the editor's message preview names it")
	# The message box shows it inline.
	var box: Node = rpg.ui.message_box
	box.auto_advance = false
	box.open_text({"text": "\\I[64] Potion"})
	assert_true(box.text_label.text.contains("[img"))
	assert_eq(box.text_label.get_total_character_count(), 1 + " Potion".length())
	box.force_close()
	# show_icons off: the code is dropped.
	rpg.data.system["show_icons"] = false
	assert_eq(RPGText.expand("\\I[64]x", rpg).bbcode, "x")


func test_release_caches_clears_icons() -> void:
	env = Env.create(tree, "res://rpg")
	assert_true(RPGIcons.texture(5) != null)
	assert_false(RPGIcons._icons.is_empty())
	env.rpg.release_caches()
	assert_true(RPGIcons._icons.is_empty(), "release_caches drops the icon textures")
	assert_true(RPGIcons.texture(5) != null, "and they load again on demand")
