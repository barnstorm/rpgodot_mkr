extends "res://tests/rpg_test_case.gd"
## Movement speeds 1-6 follow the project's RPG Maker (issue #161): each speed is twice the one
## before, at the pace of the profile's engine, so a cutscene timed with speed 3 takes as long
## as it does there. The editors show RPG Maker's names for the speeds.

const Env := preload("res://tests/rpg_test_env.gd")
const FRAME := 1.0 / 60.0

var env


func after_each() -> void:
	RPGProfile.clear_cache()
	if env != null:
		await env.destroy()
		env = null


func _start() -> void:
	env = Env.create(tree, "res://rpg")
	env.rpg.state.new_game()
	var r: RPGResult = await env.start_on("town", Vector2i(14, 12))
	assert_true(r.is_ok(), str(r))
	assert_true(await env.settle())


## Starts a one-tile step in the first open direction and returns how many 1/60 s frames it
## takes (the frames are fed by hand, so the count does not depend on the machine).
func _frames_for_a_step(ch: RPGCharacter) -> int:
	var started := false
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		if ch.step(d):
			started = true
			break
	assert_true(started, "there is room to step")
	if not started:
		return -1
	var n := 0
	while ch.moving and n < 1000:
		ch._process(FRAME)
		n += 1
	return n


func test_each_profile_has_its_rpg_makers_scale() -> void:
	# VX, VX Ace and MV: 2^speed / 256 of a tile per frame at 60 fps.
	var vx := RPGProfile.load_profile("vx")
	assert_eq(vx.move_speeds, [0.46875, 0.9375, 1.875, 3.75, 7.5, 15.0])
	assert_eq(RPGProfile.load_profile("mv").move_speeds, vx.move_speeds, "MV moves as VX does")
	# 2000 / 2003: 2^(speed+1) / 256 per frame, twice VX's pace in tiles (EasyRPG Player's
	# Game_Character::Update: amount = 1 << (1 + move_speed), 256 to the tile).
	assert_eq(RPGProfile.load_profile("rm2k").move_speeds, [0.9375, 1.875, 3.75, 7.5, 15.0, 30.0])
	# XP: 2^speed / 128 per frame at 40 fps.
	assert_eq(RPGProfile.load_profile("xp").move_speeds, [0.625, 1.25, 2.5, 5.0, 10.0, 20.0])
	for id in RPGProfile.available():
		var t: Array = RPGProfile.load_profile(id).move_speeds
		assert_true(RPGProfile.valid_move_speeds(t), "%s has six speeds" % id)
		for i in range(1, t.size()):
			assert_eq(float(t[i]), float(t[i - 1]) * 2.0, "%s: speed %d is twice speed %d" % [id, i + 1, i])
	assert_eq(RPGProfile.DEFAULT_MOVE_SPEEDS, vx.move_speeds, "a profile that does not say moves as VX")
	assert_eq(RPGCharacter.SPEEDS.slice(1), RPGProfile.DEFAULT_MOVE_SPEEDS, "and so does a character with no project")
	assert_false(RPGProfile.valid_move_speeds([1, 2, 3]))
	assert_false(RPGProfile.valid_move_speeds([1, 2, 3, 4, 5, 0]))
	assert_false(RPGProfile.valid_move_speeds("fast"))


func test_the_project_uses_its_profiles_scale_or_its_own() -> void:
	env = Env.create(tree, "res://rpg")
	var data: RPGProjectData = env.rpg.data
	assert_eq(str(data.profile.get("profile", "")), "rm2k", "the sample project is in the 2000/2003 style")
	assert_eq(data.move_speeds(), [0.9375, 1.875, 3.75, 7.5, 15.0, 30.0])
	assert_eq(data.move_speed(4), 7.5)
	assert_eq(data.move_speed(0), 0.9375, "clamped to 1")
	assert_eq(data.move_speed(9), 30.0, "clamped to 6")
	# The project's own table (profile.json "move_speeds") wins: here the kit's older scale.
	var kept: Dictionary = data.profile.duplicate(true)
	data.profile["move_speeds"] = [1.0, 2.0, 3.0, 4.2, 6.0, 9.0]
	assert_eq(data.move_speed(4), 4.2)
	data.profile["move_speeds"] = [1.0, 2.0, 3.0]
	assert_eq(data.move_speed(4), 7.5, "a table that is not six speeds is ignored")
	data.profile.erase("move_speeds")
	data.profile["profile"] = "vx"
	assert_eq(data.move_speed(4), 3.75, "another profile, another scale")
	data.profile = kept
	assert_eq(data.move_speed(4), 7.5)


func test_a_step_takes_as_long_as_in_rpg_maker() -> void:
	await _start()
	var player: RPGCharacter = env.game.player
	player.dashing = false
	# 2000 / 2003: Normal (4) crosses a tile in 8 frames, x2 Slower (3) in 16, x8 Slower in 64.
	player.speed = 4
	assert_eq(player.move_speed(), 7.5)
	assert_eq(_frames_for_a_step(player), 8, "speed 4")
	player.speed = 3
	assert_eq(_frames_for_a_step(player), 16, "speed 3")
	player.speed = 1
	assert_eq(_frames_for_a_step(player), 64, "speed 1")
	player.speed = 6
	assert_eq(_frames_for_a_step(player), 2, "speed 6")
	# Dashing doubles it, as RPG Maker's dash is one speed up.
	player.speed = 3
	player.dashing = true
	assert_eq(player.move_speed(), 7.5)
	assert_eq(_frames_for_a_step(player), 8, "speed 3, dashing")
	player.dashing = false
	# With VX's scale the same speeds take twice as many frames.
	env.rpg.data.profile["move_speeds"] = RPGProfile.load_profile("vx").move_speeds
	player.speed = 4
	assert_eq(_frames_for_a_step(player), 16, "VX speed 4")
	player.speed = 3
	assert_eq(_frames_for_a_step(player), 32, "VX speed 3")
	env.rpg.data.profile.erase("move_speeds")
	# An event moves on the same table.
	var sign: RPGEvent = env.game.map.get_event("village_sign")
	sign.speed = 3
	assert_eq(sign.move_speed(), 3.75)
	sign.speed = 9
	assert_eq(sign.move_speed(), 30.0, "an out-of-range speed is clamped")


func test_a_character_without_a_project_uses_vx_speeds() -> void:
	var ch := RPGCharacter.new()
	ch.speed = 4
	assert_eq(ch.move_speed(), 3.75)
	ch.dashing = true
	assert_eq(ch.move_speed(), 7.5)
	ch.free()


func test_the_editors_name_the_speeds() -> void:
	assert_eq(RPGCharacter.SPEED_LABELS, ["1: x8 Slower", "2: x4 Slower", "3: x2 Slower", "4: Normal", "5: x2 Faster", "6: x4 Faster"])
	# The event page's Movement > Speed.
	var page_fields: Array = load("res://addons/rpg/editor/event_editor/rpg_event_editor.gd").PAGE_FIELDS
	var movement: Dictionary = page_fields.filter(func(f): return f.key == "movement")[0]
	var speed: Dictionary = (movement.fields as Array).filter(func(f): return f.key == "speed")[0]
	assert_eq(str(speed.kind), "choice")
	assert_eq(speed.options, [1, 2, 3, 4, 5, 6], "the stored value is still the number")
	assert_eq(speed.option_labels, RPGCharacter.SPEED_LABELS)
	assert_eq(int(speed.default), 3)
	# The move route's Speed step.
	var route = load("res://addons/rpg/editor/forms/rpg_route_editor.gd")
	var step: Dictionary = route.STEP_FIELDS["speed"][0]
	assert_eq(str(step.kind), "choice")
	assert_eq(step.option_labels, RPGCharacter.SPEED_LABELS)
	assert_eq(route.describe({"speed": 3}), "Speed 3: x2 Slower")
	assert_eq(route.describe({"speed": 6}), "Speed 6: x4 Faster")
	assert_eq(route.describe({"speed": 12}), "Speed 12", "a value outside 1-6 is shown as it is")
	# Scroll Map pans on the same scale.
	var scroll: Dictionary = load("res://addons/rpg/runtime/commands/scroll_map.gd").descriptor()
	var pan_speed: Dictionary = (scroll.fields as Array).filter(func(f): return f.key == "speed")[0]
	assert_eq(pan_speed.option_labels, RPGCharacter.SPEED_LABELS)
	assert_eq(pan_speed.options, [1, 2, 3, 4, 5, 6])
