class_name RPGUI
extends CanvasLayer
## Hosts the default systems: message box, overlay scenes (run_scene, menu, shop, battle, save,
## name input, title, game over), balloons, error toasts and the UI Theme from the window skin.
## Each system is a scene named in project.json "scenes", so a project can replace it.

const DEFAULT_SCENES := {
	"title": "res://addons/rpg/runtime/ui/title_screen.gd",
	"menu": "res://addons/rpg/runtime/ui/main_menu.gd",
	"shop": "res://addons/rpg/runtime/ui/shop_screen.gd",
	"save": "res://addons/rpg/runtime/ui/save_screen.gd",
	"name_input": "res://addons/rpg/runtime/ui/name_input.gd",
	"game_over": "res://addons/rpg/runtime/ui/game_over.gd",
	"options": "res://addons/rpg/runtime/ui/options_screen.gd",
	"debug": "res://addons/rpg/runtime/ui/debug_screen.gd",
	"battle": "res://addons/rpg/runtime/ui/battle/battle_scene.gd",
}
const WINDOWSKIN_SCRIPT := "res://addons/rpg/import/rpg_windowskin.gd"
const CHARSET_SCRIPT := "res://addons/rpg/import/rpg_charset.gd"
const ASSETS_SCRIPT := "res://addons/rpg/core/rpg_assets.gd"

var root: Control
var message_box: Control
var scene_stack: Array[Node] = []
var toast: Label
var ui_theme: Theme
var auto_advance := false:
	set(v):
		auto_advance = v
		if message_box and "auto_advance" in message_box:
			message_box.auto_advance = v
var pending_save_screen := false
## Process frame in which an overlay scene last closed. The key press that closed it is still
## "just pressed" for the rest of that frame, so the player ignores it (see input_settled()).
var scene_closed_frame := -1


## False during a frame in which a menu or message box used up the button press, so the same
## press can't reopen the menu (cancel) or talk to the same event again (ok).
func input_settled() -> bool:
	var f := Engine.get_process_frames()
	if f == scene_closed_frame:
		return false
	if message_box and int(message_box.get("closed_frame")) == f:
		return false
	return true


func _init() -> void:
	name = "UI"
	layer = 20


## The menus, messages and battle are laid out for a 320x240 screen (RPG Maker 2000). On a larger
## game screen (a VX/Ace-style project is 544x416) the whole UI is scaled up to fit and centred.
const BASE_SIZE := Vector2(320, 240)


func fit_to_screen() -> void:
	if root == null or not is_inside_tree():
		return
	var vs := get_viewport().get_visible_rect().size
	if vs.is_equal_approx(BASE_SIZE) or vs.x <= 0 or vs.y <= 0:
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		transform = Transform2D.IDENTITY
		return
	var s := minf(vs.x / BASE_SIZE.x, vs.y / BASE_SIZE.y)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = BASE_SIZE
	transform = Transform2D(0.0, Vector2(s, s), 0.0, ((vs - BASE_SIZE * s) / 2.0).round())


## The whole viewport in UI coordinates. When the game screen's aspect differs from 320x240
## (MV's 816x624 scales by 2.55 to 816x612), this reaches past the 320x240 layout into the
## letterbox bands, so full-screen backgrounds can cover them.
func ui_visible_rect(viewport_size := Vector2.ZERO) -> Rect2:
	var vs := viewport_size
	if vs == Vector2.ZERO:
		vs = get_viewport().get_visible_rect().size if is_inside_tree() else BASE_SIZE
	var s := transform.get_scale().x
	if s <= 0.0 or vs.x <= 0 or vs.y <= 0:
		return Rect2(Vector2.ZERO, BASE_SIZE)
	return Rect2(-transform.origin / s, vs / s)


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	get_viewport().size_changed.connect(fit_to_screen)
	fit_to_screen()
	ui_theme = build_theme()
	root.theme = ui_theme
	_make_message_box()
	toast = Label.new()
	toast.position = Vector2(4, 4)
	toast.size = Vector2(312, 60)
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_font_size_override("font_size", 9)
	toast.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 3)
	toast.visible = false
	root.add_child(toast)


func rpg() -> Node:
	return get_parent()


func _make_message_box() -> void:
	var path: String = DEFAULT_SCENES.get("message_box", "")
	var r := rpg()
	if r and r.data:
		path = r.data.scene_setting("message_box", "")
	if path != "" and ResourceLoader.exists(path):
		var res: Resource = load(path)
		message_box = res.instantiate() if res is PackedScene else res.new()
	else:
		message_box = RPGMessageBox.new()
	if "rpg" in message_box:
		message_box.rpg = r
	root.add_child(message_box)


## Builds the UI Theme from the System graphic (window skin) when one exists. `skin` overrides
## the System record's window_skin ("Change Window Skin" keeps its choice in the game state).
func build_theme(skin := "") -> Theme:
	var r := rpg()
	var skin_name := "system"
	if r and r.data:
		skin_name = str(r.data.system.get("window_skin", "system"))
	if skin == "" and r and "state" in r and r.state != null and "windowskin" in r.state:
		skin = str(r.state.windowskin)
	if skin != "":
		skin_name = skin
	if ResourceLoader.exists(WINDOWSKIN_SCRIPT) and ResourceLoader.exists(ASSETS_SCRIPT):
		var assets: Script = load(ASSETS_SCRIPT)
		var ws: Script = load(WINDOWSKIN_SCRIPT)
		var tex: Texture2D = null
		if assets.has_method("load_texture"):
			tex = assets.load_texture("system", skin_name)
		if tex != null and ws.has_method("make_theme"):
			var t: Theme = ws.make_theme(tex)
			if t != null:
				_apply_font_defaults(t)
				return t
		if ws.has_method("fallback_theme"):
			var ft: Theme = ws.fallback_theme()
			if ft != null:
				_apply_font_defaults(ft)
				return ft
	return fallback_theme()


## Rebuilds the UI Theme (after "Change Window Skin" or a load). Every window under `root`
## picks it up; open screens that read colours re-read them when redrawn.
func apply_windowskin(skin := "") -> void:
	ui_theme = build_theme(skin)
	set_meta("rpg_skin", skin)
	if root != null:
		root.theme = ui_theme


func _apply_font_defaults(t: Theme) -> void:
	t.default_font_size = 11


static func fallback_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 11
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.35, 0.92)
	sb.border_color = Color(0.85, 0.88, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	t.set_stylebox("panel", "Panel", sb)
	t.set_stylebox("panel", "PanelContainer", sb)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(1, 1, 1, 0.18)
	focus.border_color = Color(1, 1, 1, 0.7)
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(2)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "pressed", "disabled"]:
		t.set_stylebox(st, "Button", empty)
	t.set_stylebox("hover", "Button", focus)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color(1, 1, 0.7))
	t.set_color("font_focus_color", "Button", Color(1, 1, 0.7))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.6))
	t.set_color("font_color", "Label", Color.WHITE)
	return t


# --- assets helpers --------------------------------------------------------------------------

func load_texture(kind: String, name_: String) -> Texture2D:
	if name_ == "":
		return null
	if name_.begins_with("res://"):
		return load(name_) if ResourceLoader.exists(name_) else null
	if ResourceLoader.exists(ASSETS_SCRIPT):
		var assets: Script = load(ASSETS_SCRIPT)
		if assets.has_method("load_texture"):
			return assets.load_texture(kind, name_)
	return null


func face_texture(sheet: String, index: int) -> Texture2D:
	var tex := load_texture("faceset", sheet)
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	# Face size comes from the project's profile (48 rm2k, 96 VX, 144 MV).
	var r := rpg()
	var prof := "rm2k"
	if r != null and "data" in r and r.data != null:
		prof = str(r.data.profile.get("profile", "rm2k"))
	prof = RPGAssets.sheet_profile("faceset", sheet, prof)
	at.region = Rect2(RPGCharset.face_rect(prof, Vector2i(tex.get_width(), tex.get_height()), index))
	return at


# --- overlay scenes ---------------------------------------------------------------------------

func scene_path(key: String) -> String:
	var r := rpg()
	var fallback: String = DEFAULT_SCENES.get(key, "")
	if r and r.data:
		return r.data.scene_setting(key, fallback)
	return fallback


## Instantiates a scene (PackedScene path or script path) and adds it over the map.
func open_scene(path: String) -> Node:
	if path == "" or not ResourceLoader.exists(path):
		push_error("RPG: scene '%s' not found." % path)
		return null
	var res: Resource = load(path)
	var node: Node = null
	if res is PackedScene:
		node = res.instantiate()
	elif res is Script:
		node = res.new()
	if node == null:
		return null
	if "rpg" in node:
		node.rpg = rpg()
	root.add_child(node)
	root.move_child(toast, -1)
	scene_stack.append(node)
	return node


## Untyped on purpose: a screen may ask for its own close deferred after its host has already
## closed (freed) it, and a typed Node argument would fail to convert the freed object.
func close_scene(node) -> void:
	scene_closed_frame = Engine.get_process_frames()
	if not is_instance_valid(node):
		var alive: Array[Node] = []
		for n in scene_stack:
			if is_instance_valid(n):
				alive.append(n)
		scene_stack = alive
		return
	scene_stack.erase(node)
	node.queue_free()


func scene_open() -> bool:
	var alive: Array[Node] = []
	for n in scene_stack:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			alive.append(n)
	scene_stack = alive
	return not scene_stack.is_empty()


func close_all() -> void:
	for n in scene_stack:
		if is_instance_valid(n):
			n.queue_free()
	scene_stack.clear()
	if message_box and message_box.has_method("force_close"):
		message_box.force_close()


## Runs a scene that follows the Run Scene contract: start(args, context), then exactly one of
## finished(result) / cancelled(reason). Returns {status: "finished"|"cancelled"|"timeout"|"error", value}.
func run_contract_scene(path: String, args: Dictionary, context: Variant, token: RPGCancelToken, timeout := 0.0) -> Dictionary:
	var node := open_scene(path)
	if node == null:
		return {"status": "error", "value": "Scene '%s' could not be opened." % path}
	if not node.has_signal("finished") or not node.has_signal("cancelled"):
		close_scene(node)
		return {"status": "error", "value": "Scene '%s' must declare signals finished(result) and cancelled(reason)." % path}
	var r := rpg()
	r.scheduler.lock_input("scene")
	var sigs: Array = [node.finished, node.cancelled, token.cancelled]
	var timer: SceneTreeTimer = null
	if timeout > 0.0:
		timer = get_tree().create_timer(timeout, false)
		sigs.append(timer.timeout)
	var w := RPGWaiter.any(sigs)
	if node.has_method("start"):
		node.start(args, context)
	var res: Array = await w.done
	r.scheduler.unlock_input("scene")
	close_scene(node)
	match res[0]:
		0: return {"status": "finished", "value": res[1]}
		1: return {"status": "cancelled", "value": res[1]}
		2: return {"status": "cancelled", "value": "event cancelled"}
		3: return {"status": "timeout", "value": "Scene '%s' did not finish within %s s." % [path, timeout]}
	return {"status": "error", "value": null}


# --- balloons, errors ----------------------------------------------------------------------------

const BALLOONS := {"exclamation": "!", "question": "?", "music": "♪", "heart": "♥", "anger": "💢", "sweat": "💧", "frustration": "~", "silence": "…", "light_bulb": "💡", "zzz": "Zz"}


## Shows a balloon icon over a character for about a second. Returns a Signal for waiting.
func balloon(character: Node2D, kind: String) -> Signal:
	var lab := Label.new()
	lab.text = BALLOONS.get(kind, "!")
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color.BLACK)
	var bg := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	bg.add_theme_stylebox_override("panel", sb)
	bg.add_child(lab)
	bg.z_index = 50
	bg.position = Vector2(-8, -40)
	character.add_child(bg)
	var t := character.create_tween()
	bg.scale = Vector2(0.2, 0.2)
	t.tween_property(bg, "scale", Vector2.ONE, 0.12)
	t.tween_interval(0.9)
	t.tween_callback(bg.queue_free)
	return t.finished


func show_error(text: String) -> void:
	if toast == null:
		return
	toast.text = "Event error: " + text
	toast.visible = true
	var t := create_tween()
	t.tween_interval(6.0)
	t.tween_callback(func(): toast.visible = false)
