extends "res://tests/rpg_test_case.gd"
## Save format and persistence: atomic slots, safe points, validation before touching live state,
## migrations, extension sections.

const Env := preload("res://tests/rpg_test_env.gd")
const SLOT := 16

var env


func before_each() -> void:
	env = Env.create(tree)
	var r: RPGResult = await env.start_on("town", Vector2i(4, 4), "left")
	assert_true(r.is_ok(), str(r))


func after_each() -> void:
	if FileAccess.file_exists(env.rpg.saves.slot_path(SLOT)):
		DirAccess.remove_absolute(env.rpg.saves.slot_path(SLOT))
	await env.destroy()


func test_save_and_load_round_trip() -> void:
	var st: RPGGameState = env.rpg.state
	st.set_switch("door_unlocked", true)
	st.set_variable("counter", 42)
	st.set_variable("hero_name", "Zed")
	st.set_self_switch("town", "chest", "A", true)
	st.change_gold("set", 777)
	var r: RPGResult = env.rpg.saves.save(SLOT)
	assert_true(r.is_ok(), str(r))
	var text := FileAccess.get_file_as_string(env.rpg.saves.slot_path(SLOT))
	assert_false(text.contains("pages"), "saves never copy event pages")
	# Change everything, then load.
	st.set_switch("door_unlocked", false)
	st.set_variable("counter", 1)
	st.change_gold("set", 0)
	await env.game.transfer("house_inside", Vector2i(1, 1), "down", "none")
	var lr: RPGResult = await env.rpg.saves.load_slot(SLOT)
	assert_true(lr.is_ok(), str(lr))
	assert_true(st.get_switch("door_unlocked"))
	assert_eq(st.get_variable("counter"), 42)
	assert_eq(typeof(st.get_variable("counter")), TYPE_INT, "typed after load")
	assert_eq(st.get_variable("hero_name"), "Zed")
	assert_true(st.get_self_switch("town", "chest", "A"))
	assert_eq(st.gold, 777)
	assert_eq(env.game.map.map_id, "town")
	assert_eq(env.game.player.cell, Vector2i(4, 4))
	assert_eq(env.game.player.facing, "left")
	await frames(2)
	assert_eq(env.game.map.get_event("chest").page_index, 1, "pages rebuilt from project data + saved self switch")


func test_saving_refused_during_main_event() -> void:
	var t: RPGScheduler.Ticket = env.rpg.scheduler.request_main("long", [{"type": "wait", "seconds": 30}], {"kind": "test"}, null)
	await frames(2)
	var r: RPGResult = env.rpg.saves.save(SLOT)
	assert_true(r.is_error(), "no saving while an event runs")
	assert_true(r.message.contains("event"), r.message)
	assert_false(FileAccess.file_exists(env.rpg.saves.slot_path(SLOT)))
	await env.rpg.scheduler.cancel_all("test")
	await t.wait()
	assert_true(env.rpg.saves.save(SLOT).is_ok(), "allowed again at a safe point")


func test_load_rejects_foreign_project_without_touching_state() -> void:
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	var raw: Dictionary = RPGJson.parse_file(env.rpg.saves.slot_path(SLOT)).data
	raw["project_id"] = "someone_else"
	raw["state"]["gold"] = 123456
	env.rpg.state.change_gold("set", 5)
	var r: RPGResult = await env.rpg.saves.load_data(raw)
	assert_true(r.is_error())
	assert_eq(env.rpg.state.gold, 5, "current game continues unchanged")
	raw["project_id"] = "fixture_door"
	raw["map"]["id"] = "deleted_map"
	var r2: RPGResult = await env.rpg.saves.load_data(raw)
	assert_true(r2.is_error())
	assert_true(r2.message.contains("deleted_map"))
	assert_eq(env.rpg.state.gold, 5)


func test_migration_from_version_zero() -> void:
	var old := {"project_id": "fixture_door", "map": {"id": "town", "position": [2, 2], "facing": "up"}, "switches": {"door_unlocked": true}, "variables": {"counter": 9}, "gold": 50, "party": []}
	var m: Dictionary = env.rpg.saves.migrate(old)
	assert_true(m.ok)
	assert_eq(m.data.schema_version, RPGSaveService.SCHEMA_VERSION)
	assert_false(m.changes.is_empty(), "reports what changed")
	assert_false(old.has("state"), "migration runs on a copy")
	var r: RPGResult = await env.rpg.saves.load_data(old)
	assert_true(r.is_ok(), str(r))
	assert_eq(env.rpg.state.get_variable("counter"), 9)
	assert_true(env.rpg.state.get_switch("door_unlocked"))


func test_unknown_extension_sections_are_kept() -> void:
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	var raw: Dictionary = RPGJson.parse_file(env.rpg.saves.slot_path(SLOT)).data
	raw["extensions"] = {"fishing": {"version": 1, "data": {"best_catch": "carp"}}}
	var r: RPGResult = await env.rpg.saves.load_data(raw)
	assert_true(r.is_ok())
	var again: Dictionary = env.rpg.saves.build_save()
	assert_eq(again.extensions.get("fishing", {}).get("data", {}).get("best_catch", ""), "carp", "kept for when the extension returns")


func test_atomic_write_leaves_no_temp_files() -> void:
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	assert_true(env.rpg.saves.save(SLOT).is_ok())
	assert_false(FileAccess.file_exists(env.rpg.saves.slot_path(SLOT) + ".tmp"))
	assert_false(FileAccess.file_exists(env.rpg.saves.slot_path(SLOT) + ".bak"))
	var d: Dictionary = env.rpg.saves.describe(SLOT)
	assert_true(d.exists)
