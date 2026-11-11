@tool
extends RPGCommand
## RPG Maker's "Change Equipment": puts a weapon or armour in one of the actor's slots (blank
## item = remove). The old item goes back to the inventory; the new one is taken from it when
## the party has one (as in RPG Maker VX, the actor is equipped even when the party has none).
## An item the actor's class can't wear is ignored, as in RPG Maker.


static func descriptor() -> Dictionary:
	return {
		"type": "change_equipment", "schema_version": 1, "category": "rules", "label": "Change Equipment",
		"fields": [
			{"key": "actor", "kind": "ref", "ref": "actor", "label": "Actor", "required": true},
			{"key": "slot", "kind": "text", "default": "weapon", "label": "Slot", "help": "An equipment slot ID from Database > Types (weapon, shield, body, accessory...)"},
			{"key": "kind", "kind": "choice", "options": ["weapon", "armor"], "default": "weapon", "label": "Item kind"},
			{"key": "item", "kind": "ref", "ref": "weapon", "ref_from": "kind", "default": "", "label": "Item (blank = remove)"},
		],
	}


func summary(args: Dictionary) -> String:
	var it := str(args.get("item", "")) if args.get("item") != null else ""
	return "Change Equipment: %s %s = %s" % [args.get("actor", "?"), args.get("slot", "?"), it if it != "" else "(none)"]


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var id := str(args.get("actor", ""))
	if not ctx.data.has_record("actors", id):
		return RPGResult.error("Change Equipment: actor '%s' does not exist." % id)
	var b: Variant = ctx.state.actor(id)
	if b == null:
		return RPGResult.error("Change Equipment: actor '%s' could not be created." % id)
	var slot := str(args.get("slot", ""))
	var slot_kind := _slot_kind(ctx, b, slot)
	var equips: Variant = RPGPartyUtil.get_field(b, "equips", {})
	if not (equips is Dictionary):
		equips = {}
	if slot_kind == "" and not equips.has(slot):
		return RPGResult.error("Change Equipment: there is no equipment slot '%s'." % slot)
	var item := str(args.get("item", "")) if args.get("item") != null else ""
	var kind := "armors" if str(args.get("kind", "weapon")) == "armor" else "weapons"
	if item != "":
		if not ctx.data.has_record(kind, item):
			return RPGResult.error("Change Equipment: %s '%s' does not exist." % [kind.trim_suffix("s"), item])
		if slot_kind != "" and slot_kind + "s" != kind:
			return RPGResult.error("Change Equipment: slot '%s' holds %ss, not %s." % [slot, slot_kind, kind])
		if not _wearable(ctx, b, slot, kind, item):
			return RPGResult.ok()
	var old := str(equips.get(slot, ""))
	if old == item:
		return RPGResult.ok()
	if RPGPartyUtil.rules_has(ctx, "change_equip", 3):
		ctx.rpg.rules.change_equip(b, slot, item)
	else:
		var old_kind := "weapons" if slot_kind == "weapon" else "armors"
		if old != "":
			ctx.state.change_items(old, "increase", 1, old_kind)
		if item != "" and ctx.state.item_count(item, kind) > 0:
			ctx.state.change_items(item, "decrease", 1, kind)
		equips[slot] = item
		RPGPartyUtil.set_field(b, "equips", equips)
		RPGPartyUtil.clamp_after_change(ctx, b)
	ctx.state.notify_actor_changed(id)
	return RPGResult.ok()


## "weapon" / "armor" for a declared slot (dual wield aware with a rule system), "" if unknown.
static func _slot_kind(ctx: RPGContext, b: Variant, slot: String) -> String:
	var declared := ""
	for e in ctx.data.record("types", "equip_slots").get("entries", []):
		if e is Dictionary and str(e.get("id", "")) == slot:
			declared = str(e.get("kind", "armor"))
	if declared == "" and slot != "weapon":
		return ""
	var rules: Variant = ctx.rpg.rules
	if b is RPGBattler and rules != null and rules.has_method("equip_slot_kind"):
		var k := str(rules.equip_slot_kind(b, slot))
		if k != "":
			return k
	return declared if declared != "" else "weapon"


## Class and slot restrictions, the same ones the Equip screen applies.
static func _wearable(ctx: RPGContext, b: Variant, slot: String, kind: String, item: String) -> bool:
	if RPGPartyUtil.rules_has(ctx, "can_equip", 3):
		return bool(ctx.rpg.rules.can_equip(b, slot, item))
	var rec: Dictionary = ctx.data.record(kind, item)
	var cls := str(RPGPartyUtil.get_field(b, "class_id", RPGPartyUtil.get_field(b, "class", "")))
	var allowed: Variant = ctx.data.record("classes", cls).get("equip")
	if kind == "weapons":
		return not (allowed is Dictionary) or (allowed.get("weapon_types", []) as Array).has(str(rec.get("weapon_type", "")))
	var rs := str(rec.get("slot", ""))
	if rs != "" and rs != slot:
		return false
	if rs == "":
		for e in ctx.data.record("types", "equip_slots").get("entries", []):
			if e is Dictionary and str(e.get("id", "")) == slot:
				var types: Array = e.get("armor_types", [])
				if not types.is_empty() and not types.has(str(rec.get("armor_type", ""))):
					return false
	return not (allowed is Dictionary) or (allowed.get("armor_types", []) as Array).has(str(rec.get("armor_type", "")))
