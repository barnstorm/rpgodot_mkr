@tool
extends Container
## Lays out a Database form like RPG Maker's: the form column is never wider than `max_width`
## (no 1500 px wide text boxes on a big screen), and an optional side panel (a large preview of
## the record's sprite, face or battler) sits right next to it. When the space is narrow the
## form shrinks first; when it is narrower than form + panel, the panel moves under the form.
##
##   var col := preload("res://addons/rpg/editor/database/rpg_form_column.gd").new()
##   col.add_child(form)          # first child: the form
##   col.add_child(preview)       # optional second child: the side panel (may be hidden)

@export var max_width := 720.0
@export var min_form_width := 360.0
@export var gap := 16.0

var _last_side_by_side := true


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _visible_children() -> Array:
	var out := []
	for c in get_children():
		if c is Control and c.visible and not c.is_set_as_top_level():
			out.append(c)
	return out


func _side_by_side(kids: Array) -> bool:
	if kids.size() < 2:
		return true
	return size.x >= min_form_width + gap + kids[1].get_combined_minimum_size().x


func _get_minimum_size() -> Vector2:
	var kids := _visible_children()
	if kids.is_empty():
		return Vector2.ZERO
	var form_min: Vector2 = kids[0].get_combined_minimum_size()
	var w := minf(form_min.x, max_width)
	if kids.size() < 2:
		return Vector2(w, form_min.y)
	var side: Vector2 = kids[1].get_combined_minimum_size()
	if _side_by_side(kids):
		return Vector2(w, maxf(form_min.y, side.y))
	return Vector2(maxf(w, side.x), form_min.y + gap + side.y)


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var kids := _visible_children()
	if kids.is_empty():
		return
	var form: Control = kids[0]
	if kids.size() < 2:
		var fw := minf(size.x, max_width)
		fit_child_in_rect(form, Rect2(0, 0, fw, form.get_combined_minimum_size().y))
		return
	var side: Control = kids[1]
	var side_min := side.get_combined_minimum_size()
	if _side_by_side(kids):
		var fw := clampf(size.x - gap - side_min.x, 0.0, max_width)
		fit_child_in_rect(form, Rect2(0, 0, fw, form.get_combined_minimum_size().y))
		fit_child_in_rect(side, Rect2(fw + gap, 0, side_min.x, side_min.y))
	else:
		var fw := minf(size.x, max_width)
		var fh := form.get_combined_minimum_size().y
		fit_child_in_rect(form, Rect2(0, 0, fw, fh))
		fit_child_in_rect(side, Rect2(0, fh + gap, side_min.x, side_min.y))
	# The side-by-side decision depends on the width: re-measure the height when it flips.
	var sbs := _side_by_side(kids)
	if sbs != _last_side_by_side:
		_last_side_by_side = sbs
		update_minimum_size.call_deferred()
