extends RefCounted
## Builds an isolated runtime (service + game root) on a fixture project for integration tests.

const SERVICE := "res://addons/rpg/runtime/rpg_service.gd"

var rpg: Node
var game: RPGGame
var tree: SceneTree


static func create(p_tree: SceneTree, root := "res://tests/fixtures/door_project") -> RefCounted:
	var env = load("res://tests/rpg_test_env.gd").new()
	env.tree = p_tree
	env.rpg = load(SERVICE).new()
	env.rpg.name = "RPGTest"
	env.rpg.playtest = true
	env.rpg.auto_boot = false
	p_tree.root.add_child(env.rpg)
	env.rpg.boot(root)
	env.rpg.ui.auto_advance = true
	env.game = RPGGame.new()
	env.game.rpg = env.rpg
	env.game.auto_start = false
	p_tree.root.add_child(env.game)
	return env


func start_on(map_id: String, cell: Vector2i, facing := "down") -> RPGResult:
	game._make_player()
	return await game.transfer(map_id, cell, facing, "none")


## Waits until the main interpreter is idle (or `max_frames` pass). Returns true if idle.
func settle(max_frames := 600) -> bool:
	for i in max_frames:
		await tree.process_frame
		if not rpg.scheduler.is_main_busy() and not game.transferring and not rpg._refresh_pending:
			return true
	return false


## Waits until a character has finished its current step.
func walk_done(ch: Node, max_frames := 300) -> void:
	for i in max_frames:
		if not ch.moving:
			return
		await tree.process_frame


func destroy() -> void:
	await rpg.scheduler.cancel_all("test teardown")
	game.queue_free()
	rpg.queue_free()
	await tree.process_frame
