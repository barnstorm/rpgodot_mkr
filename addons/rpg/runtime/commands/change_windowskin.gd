@tool
extends RPGCommand
## RPG Maker's "Change Window Skin" (VX Ace: the Windowskin in "Change Window Color"/System): the
## System graphic used for windows and text colours. Blank = the System record's. Saved.


static func descriptor() -> Dictionary:
	return {
		"type": "change_windowskin", "schema_version": 1, "category": "screen", "label": "Change Window Skin",
		"fields": [{"key": "skin", "kind": "resource", "res": "system", "default": "", "label": "Window skin (blank = default)"}],
	}


func summary(args: Dictionary) -> String:
	var s := str(args.get("skin", "")) if args.get("skin") != null else ""
	return "Change Window Skin: %s" % (s if s != "" else "(default)")


func run(ctx: RPGContext, args: Dictionary) -> RPGResult:
	var skin := str(args.get("skin", "")) if args.get("skin") != null else ""
	if skin != "" and RPGAssets.find("system", skin) == "":
		return RPGResult.error("Change Window Skin: system graphic '%s' not found." % skin)
	ctx.state.windowskin = skin
	if ctx.ui != null and ctx.ui.has_method("apply_windowskin"):
		ctx.ui.apply_windowskin(skin)
	return RPGResult.ok()
