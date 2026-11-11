@tool
class_name RPGRandom
extends RefCounted
## Seeded random number generator with savable state.
##
## Every random draw the game makes for rules (hit rolls, damage variance, dice, enemy AI,
## drops) goes through one RPGRandom so a battle can be replayed from a saved state.
## get_state() returns strings because the 64-bit generator state does not survive a JSON
## round trip as a number (JSON numbers are doubles).

var _rng := RandomNumberGenerator.new()

## The seed this generator was created with (or last reseeded with).
var seed: int:
	get:
		return _rng.seed
	set(value):
		_rng.seed = value


## `p_seed` < 0 picks a random seed.
func _init(p_seed: int = -1) -> void:
	if p_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = p_seed


## Inclusive integer range. Swaps the bounds if they are reversed.
func randi_range(lo: int, hi: int) -> int:
	if hi < lo:
		var t := lo
		lo = hi
		hi = t
	return _rng.randi_range(lo, hi)


## Float in [0, 1].
func randf() -> float:
	return _rng.randf()


func randf_range(lo: float, hi: float) -> float:
	return _rng.randf_range(lo, hi)


## True with probability p (0..1). p <= 0 is never, p >= 1 is always (no draw is wasted).
func chance(p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return _rng.randf() < p


## True with probability percent/100 (0..100), drawing an integer 0..99.
func chance_percent(percent: float) -> bool:
	if percent <= 0.0:
		return false
	if percent >= 100.0:
		return true
	return float(_rng.randi_range(0, 99)) < percent


## Rolls `count` dice of `sides` sides and returns the sum.
func roll_dice(count: int, sides: int) -> int:
	var total := 0
	for i in maxi(count, 0):
		total += _rng.randi_range(1, maxi(sides, 1))
	return total


## Index of a weighted pick from an array of Dictionaries with a "weight" key
## (missing weight = 1, weights <= 0 are never picked). Returns -1 if nothing can be picked.
func pick_weighted_index(items: Array) -> int:
	var total := 0.0
	for it in items:
		total += _weight_of(it)
	if total <= 0.0:
		return -1
	var r := _rng.randf() * total
	var last_ok := -1
	for i in items.size():
		var w := _weight_of(items[i])
		if w <= 0.0:
			continue
		last_ok = i
		if r < w:
			return i
		r -= w
	return last_ok


## The picked element itself, or null when nothing can be picked.
func pick_weighted(items: Array) -> Variant:
	var i := pick_weighted_index(items)
	return items[i] if i >= 0 else null


## Uniform pick from an array, or null when empty.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


## Savable state. Values are strings so they survive JSON exactly.
func get_state() -> Dictionary:
	return {"seed": str(_rng.seed), "state": str(_rng.state)}


func set_state(d: Dictionary) -> void:
	if d.has("seed"):
		_rng.seed = _to_int(d.seed)
	if d.has("state"):
		_rng.state = _to_int(d.state)


static func _to_int(v: Variant) -> int:
	if v is String:
		return (v as String).to_int()
	return int(v)


static func _weight_of(it: Variant) -> float:
	if it is Dictionary:
		return float(it.get("weight", 1))
	return 1.0
