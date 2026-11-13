@tool
class_name RPGBattleFacade
extends RefCounted
## The public battle API while a battle runs: `rpg.battle` (null otherwise).
##
## The battle scene creates it when it starts and clears it when the fight ends, so commands
## (battle events, common events called from them) and extensions never have to reach into the
## scene's internals. Documented methods are stable within a minor version; anything prefixed
## `_` may change. Awaitable methods (`reveal`, `message`) return when their effect is done.
##
##   if rpg.battle != null:
##       var slime = rpg.battle.add_enemy("slime", Vector2(120, 150))
##       await rpg.battle.message("%s appears!" % slime.name)


## The battle scene (weakly: the scene owns this facade, and the facade must not keep it alive).
var _scene_ref: WeakRef = null


func _init(p_scene: Node) -> void:
	_scene_ref = weakref(p_scene)


## The battle scene, or null once the battle is gone.
func scene() -> Node:
	var s: Node = _scene_ref.get_ref() if _scene_ref != null else null
	return s if s != null and is_instance_valid(s) else null


## The RPGBattleCore of the running battle, or null.
func core() -> RPGBattleCore:
	var s := scene()
	var c: Variant = s.get("core") if s != null else null
	return c as RPGBattleCore


## The actors fighting now (live array copy).
func party() -> Array:
	var c := core()
	return (c.party as Array).duplicate() if c != null else []


## The enemies of the troop, hidden ones included (live array copy).
func enemies() -> Array:
	var c := core()
	return (c.enemies as Array).duplicate() if c != null else []


## Brings a hidden troop member into the fight (Enemy Appear). Awaits the appear effect.
func reveal(b: RPGBattler) -> void:
	var s := scene()
	var c := core()
	if s == null or c == null or b == null:
		return
	var idx: int = (c.enemies as Array).find(b)
	if idx >= 0:
		await s.enemy_appear(idx)


## Adds a reinforcement: a new enemy built from record `enemy_id` at `position` (pixels on the
## 320x240 battle screen). Returns its battler, or null when the record does not exist.
func add_enemy(enemy_id: String, position := Vector2(160, 120)) -> RPGBattler:
	var s := scene()
	var c := core()
	if s == null or c == null:
		return null
	var b: RPGBattler = c.add_enemy(enemy_id, position)
	if b != null:
		s.refresh_after_event()
	return b


## Timed battles (ATB / CTB): sets a battler's gauge, 0 (empty) to 1 (full).
func set_gauge(b: RPGBattler, value: float) -> void:
	var s := scene()
	var c := core()
	if s == null or c == null:
		return
	c.set_gauge(b, clampf(value, 0.0, 1.0))
	s.refresh_after_event()


## Refreshes the battle after something changed the battlers: runs the change hooks, collapses
## enemies that were defeated and redraws the status display and battler visuals.
func refresh() -> void:
	var s := scene()
	if s != null:
		s.refresh_after_event()


## Shows a line in the battle's message box. Awaits the text.
func message(text: String, seconds := 0.55) -> void:
	var s := scene()
	if s != null:
		await s.say(text, seconds)


## Flashes a battler's graphic.
func flash(b: RPGBattler, col := Color(2.2, 2.2, 2.2)) -> void:
	var s := scene()
	if s != null:
		s.flash(b, col)


## The scene's node for a battler (enemy sprite, side-view actor, status row anchor).
func node_of(b: RPGBattler) -> Node2D:
	var s := scene()
	return s.battler_node(b) if s != null else null


## Ends the battle with `result` ("win", "lose" or "escape"). With `award` false a win gives no
## rewards. The caller's Battle Processing command takes the matching branch.
func end(result: String, award := true) -> void:
	var s := scene()
	if s == null:
		return
	if not award:
		s.skip_rewards = true
	s.core.force_result(result)


## Change Party Member during a battle: puts the field in step with the game state's party
## (added actors get a gauge and act in the normal order; removed actors leave it), re-checks
## victory and defeat, and re-flows both views. `temporary` actors are removed again when the
## battle ends.
func refresh_party(temporary: Array = []) -> void:
	var s := scene()
	if s == null:
		return
	s.refresh_party(temporary)


## True while the battle is running.
func valid() -> bool:
	return scene() != null
