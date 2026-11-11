@tool
extends RPGCommand
## RPG Maker's "Show Animation": plays a Database Animations record (or a built-in effect: hit,
## slash, fire, ice, thunder, heal) on the player, this event or another event. It uses the same
## player as battle animations (RPGBattleEffects), drawn over the map at the character.

const BUILTIN := ["hit", "slash", "fire", "ice", "thunder", "heal"]


static func descriptor() -> Dictionary:
	return {
		"type": "show_animation", "schema_version": 1, "category": "screen", "label": "Show Animation",
		"fields": [
			{"key": "target", "kind": "text", "default": "this", "label": "Character", "help": "player, this, or an event ID"},
			{"key": "animation", "kind": "ref", "ref": "animation", "allow": BUILTIN.duplicate(), "default": "hit", "label": "Animation", "required": true,
				"help": "An Animations record, or a built-in effect: hit, slash, fire, ice, thunder, heal"},
			{"key": "wait", "kind": "bool", "default": false, "label": "Wait for completion"},
		],
	}


func summary(args: Dictionary) -> String:
	return "Show Animation: %s, %s%s" % [args.get("target", "this"), args.get("animation", "?"), " (wait)" if args.get("wait", false) else ""]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var anim := str(args.get("animation", ""))
	if not BUILTIN.has(anim) and not ctx.data.has_record("animations", anim):
		return RPGResult.error("Show Animation: animation '%s' does not exist (use an Animations record or %s)." % [anim, ", ".join(PackedStringArray(BUILTIN))])
	var target := str(args.get("target", "this"))
	var ch: Node = ctx.character(target)
	if ch == null:
		return RPGResult.error("Show Animation: character '%s' not found on this map." % target)
	var host := _host(ctx)
	if host == null:
		return RPGResult.ok()
	var seconds: float = RPGBattleEffects.play(host, _point(ch, host), anim, ctx.rpg)
	if args.get("wait", false) and seconds > 0.0:
		if not await ctx.wait_seconds(seconds):
			return RPGResult.cancelled()
	return RPGResult.ok()


## A full-screen layer under the UI root, behind the message box, for map animations.
static func _host(ctx: RPGContext) -> Control:
	var ui: Node = ctx.ui
	if ui == null or not ("root" in ui) or ui.root == null:
		return null
	var root: Control = ui.root
	var host := root.get_node_or_null("MapAnimations") as Control
	if host == null:
		host = Control.new()
		host.name = "MapAnimations"
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
		root.move_child(host, 0)
	if host.size == Vector2.ZERO:
		host.size = root.size if root.size != Vector2.ZERO else Vector2(320, 240)
	return host


## The character's middle (one tile above its feet) in the host's coordinates.
static func _point(ch: Node, host: Control) -> Vector2:
	if not (ch is Node2D) or not ch.is_inside_tree():
		return host.size / 2.0
	var ts := float(ch.tile_size) if "tile_size" in ch else 16.0
	var screen: Vector2 = (ch as Node2D).get_global_transform_with_canvas() * Vector2(0, -ts * 0.75)
	return host.get_global_transform_with_canvas().affine_inverse() * screen
