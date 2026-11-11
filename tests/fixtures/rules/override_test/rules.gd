extends RPGRuleSystem
## Test fixture: a project rules.gd that replaces one step (damage) and keeps the rest.


func damage(user: RPGBattler, target: RPGBattler, action: Dictionary, hit_info: Dictionary = {}) -> Dictionary:
	var d := super(user, target, action, hit_info)
	if d.ok and d.type == "damage":
		d.value = 7
	return d
