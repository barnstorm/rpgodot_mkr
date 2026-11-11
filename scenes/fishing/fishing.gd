extends Control
## Example Run Scene minigame: press OK while the marker is inside the green zone to catch a fish.
## Run Scene contract: start(args, context), then exactly one of finished(result) / cancelled(reason).
## args: {"rounds": 3, "speed": 1.0}. Result: number of fish caught (stored in a variable).

signal finished(result: Variant)
signal cancelled(reason: String)

var rpg: Node
var rounds := 3
var speed := 1.0
var caught := 0
var round_index := 0
var marker := 0.0
var dir := 1.0
var zone_start := 0.4
var zone_size := 0.2
var done := false
var flash := 0.0
var status := ""


func start(args: Dictionary, _context: Variant) -> void:
	rounds = int(args.get("rounds", 3))
	speed = float(args.get("speed", 1.0))
	_new_round()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _new_round() -> void:
	zone_size = randf_range(0.12, 0.22)
	zone_start = randf_range(0.05, 0.95 - zone_size)
	marker = 0.0
	dir = 1.0


func _process(delta: float) -> void:
	if done:
		return
	flash = maxf(0.0, flash - delta)
	marker += dir * delta * 0.9 * speed * (1.0 + round_index * 0.35)
	if marker > 1.0:
		marker = 1.0
		dir = -1.0
	elif marker < 0.0:
		marker = 0.0
		dir = 1.0
	if Input.is_action_just_pressed("rpg_ok"):
		var hit := marker >= zone_start and marker <= zone_start + zone_size
		if hit:
			caught += 1
			status = "Caught one!"
			if rpg:
				rpg.audio.play_role("decision")
		else:
			status = "It got away..."
			if rpg:
				rpg.audio.play_role("buzzer")
		flash = 0.4
		round_index += 1
		if round_index >= rounds:
			done = true
			await get_tree().create_timer(0.8).timeout
			finished.emit(caught)
			return
		_new_round()
	elif Input.is_action_just_pressed("rpg_cancel"):
		done = true
		cancelled.emit("player left the pond")
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 240), Color(0.05, 0.15, 0.3, 0.92))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(20, 40), "Fishing  -  round %d / %d" % [mini(round_index + 1, rounds), rounds], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(font, Vector2(20, 60), "Press OK when the float is in the green zone.", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.9, 1))
	var bar := Rect2(30, 110, 260, 16)
	draw_rect(bar, Color(0.1, 0.1, 0.15))
	draw_rect(Rect2(bar.position.x + bar.size.x * zone_start, bar.position.y, bar.size.x * zone_size, bar.size.y), Color(0.2, 0.8, 0.3))
	draw_rect(bar, Color.WHITE, false, 1)
	var mx := bar.position.x + bar.size.x * marker
	draw_rect(Rect2(mx - 2, bar.position.y - 6, 4, bar.size.y + 12), Color(1, 0.4, 0.2))
	draw_string(font, Vector2(20, 160), "Fish caught: %d" % caught, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if flash > 0.0:
		draw_string(font, Vector2(20, 185), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.6))
	draw_string(font, Vector2(20, 225), "Cancel: leave the pond", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.8))
