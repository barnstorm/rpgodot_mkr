@tool
extends RefCounted
## Places hand-made popups (context menus, pickers) where the maker is looking. A popup's position
## is in screen pixels when it is a real OS window, but relative to the editor window when Godot
## embeds subwindows (single-window mode, or the editor setting), so screen maths put menus
## hundreds of pixels away there. Use these instead of setting `position` by hand.


## Pops `m` up at the mouse. `owner` adds it to the tree first if it has no parent.
static func at_mouse(owner: Node, m: Window) -> void:
	if m.get_parent() == null:
		owner.add_child(m)
	_popup(m, mouse_position(m))


## Pops `m` up at `global_pos`, a point in `owner`'s canvas (an input event's global_position):
## exact even when the OS cursor and the event disagree (touch, pen, scripted input).
static func at_point(owner: Control, m: Window, global_pos: Vector2) -> void:
	if m.get_parent() == null:
		owner.add_child(m)
	var pos: Vector2
	if _embedded(m):
		pos = _to_embedder(owner, global_pos, _embedder(m))
	else:
		# Viewport pixels -> the control's local space -> the screen.
		pos = owner.get_screen_transform() * (owner.get_global_transform_with_canvas().affine_inverse() * global_pos)
	_popup(m, pos)


## Pops `w` up just below `anchor` (a field or button), left-aligned with it, kept on screen.
static func below(anchor: Control, w: Window, min_size := Vector2i.ZERO) -> void:
	if w.get_parent() == null:
		anchor.add_child(w)
	var r := anchor.get_global_rect()
	var pos := r.position + Vector2(0, r.size.y)
	if not _embedded(w):
		pos = Vector2(anchor.get_screen_position()) + Vector2(0, r.size.y * anchor.get_global_transform_with_canvas().get_scale().y)
	else:
		pos = _to_embedder(anchor, pos, _embedder(w))
	_popup(w, pos, min_size)


## The mouse position in the coordinates `w`'s position uses.
static func mouse_position(w: Window) -> Vector2:
	if _embedded(w):
		var embedder := _embedder(w)
		return embedder.get_mouse_position() if embedder != null else Vector2.ZERO
	return Vector2(DisplayServer.mouse_get_position())


static func _embedded(w: Window) -> bool:
	return _embedder(w) != null


## The viewport that draws `w` inside itself, or null when `w` is its own OS window.
static func _embedder(w: Window) -> Viewport:
	var p := w.get_parent()
	if p == null:
		return null
	var vp := p.get_viewport()
	while vp != null:
		if vp.is_embedding_subwindows():
			return vp
		if vp is Window and vp.get_parent() != null:
			vp = vp.get_parent().get_viewport()
		else:
			return null
	return null


## A point in `c`'s canvas, moved into the coordinates of `target` (the viewport that will embed
## the popup). An embedded window's position is relative to the viewport that embeds it, which
## is not its parent window unless that one embeds subwindows: so the walk goes from embedder to
## embedder (a dialog inside the event editor is embedded by the editor, like the event editor
## itself, and only its own position counts).
static func _to_embedder(c: Node, pos: Vector2, target: Viewport = null) -> Vector2:
	var vp := c.get_viewport()
	while vp != null and vp != target and vp is Window:
		var host := _embedder(vp as Window)
		if host == null:
			break   # its own OS window
		pos += Vector2((vp as Window).position)
		vp = host
	return pos


static func _popup(w: Window, pos: Vector2, min_size := Vector2i.ZERO) -> void:
	var sz := Vector2i(maxi(min_size.x, w.size.x), maxi(min_size.y, w.size.y))
	var area := Rect2(Vector2.ZERO, Vector2(DisplayServer.screen_get_size()))
	var embedder := _embedder(w)
	if embedder != null:
		area = embedder.get_visible_rect()
	elif w.get_parent() != null:
		area = Rect2(DisplayServer.screen_get_usable_rect(w.get_parent().get_window().current_screen))
	var p := Vector2i(pos)
	if w is PopupMenu:
		w.reset_size()
		sz = Vector2i(maxi(sz.x, w.get_contents_minimum_size().x), maxi(sz.y, w.get_contents_minimum_size().y))
	# Keep it inside the visible area.
	p.x = clampi(p.x, int(area.position.x), maxi(int(area.position.x), int(area.end.x) - sz.x))
	p.y = clampi(p.y, int(area.position.y), maxi(int(area.position.y), int(area.end.y) - sz.y))
	w.position = p
	if min_size != Vector2i.ZERO:
		w.size = sz
	w.popup()
