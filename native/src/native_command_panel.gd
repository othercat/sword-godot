# SPDX-License-Identifier: MIT
extends RefCounted
## Presentation-only rectangles/images; the existing Button owns input and rules.
const KEY = "pal.native.command-panel"
const SCHEMA = KEY + ".v1"
const CAPABILITY = "graphics.command-panel.v1"
static func used(world: Dictionary) -> bool: return world.get("extensions",{}).has(KEY)
static func definition(world: Dictionary) -> Dictionary: return world.get("extensions",{}).get(KEY,{})
static func for_encounter(world: Dictionary, encounter: String) -> Dictionary:
	for row in definition(world).get("encounters",[]):
		if row.encounter_id == encounter: return row
	return {}
static func sprites(world: Dictionary) -> Array:
	var result: Array = []
	for row in definition(world).get("encounters",[]):
		for button in row.buttons: result.append_array(button.sprites)
	return result
static func validate_content(package) -> String:
	if not used(package.world): return ""
	# Validate the raw value before asking a typed accessor to return it.
	var issue: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Array = []
	var hud: Array = package.world.extensions.get("pal.native.battle-hud",{}).get("encounters",[])
	for row in definition(package.world).encounters:
		if row.encounter_id in seen or not package.world.encounters.any(func(e):return e.id == row.encounter_id): return "command panel: duplicate or unknown encounter"
		seen.append(row.encounter_id)
		if not hud.any(func(e):return e.encounter_id == row.encounter_id): return "command panel requires responsive battle HUD"
		var commands: Array = []
		for button in row.buttons:
			if button.command in commands: return "command panel: duplicate command"
			commands.append(button.command)
			var r: Dictionary = button.rect
			if r.x+r.width > row.size.width or r.y+r.height > row.size.height: return "command button exceeds panel"
			var states: Array = []
			for sprite in button.sprites:
				if sprite.state in states: return "command panel: duplicate image state"
				states.append(sprite.state)
				if package.index.assets.get(sprite.asset_id,{}).get("kind") != "texture": return "command panel image must reference texture"
			if button.appearance == "image" and "normal" not in states: return "command panel image requires normal state"
	return ""
static func geometry(profile: Dictionary, bounds: Rect2) -> Dictionary:
	var authored = Vector2(profile.size.width,profile.size.height)
	var factor: float = profile.scale_milli/1000.0
	if profile.clamp_to_canvas: factor = minf(factor,minf(maxf(0,bounds.size.x)/authored.x,maxf(0,bounds.size.y)/authored.y))
	var extent = authored*factor
	var right: bool = profile.anchor.ends_with("right")
	var bottom: bool = profile.anchor.begins_with("bottom")
	var position = Vector2(bounds.end.x-extent.x-profile.offset.x if right else bounds.position.x+profile.offset.x,bounds.end.y-extent.y-profile.offset.y if bottom else bounds.position.y+profile.offset.y)
	if profile.clamp_to_canvas:
		position.x = clampf(position.x,bounds.position.x,maxf(bounds.position.x,bounds.end.x-extent.x))
		position.y = clampf(position.y,bounds.position.y,maxf(bounds.position.y,bounds.end.y-extent.y))
	var buttons: Dictionary = {}
	for b in profile.buttons:
		buttons[b.command] = Rect2(position+Vector2(b.rect.x,b.rect.y)*factor,Vector2(b.rect.width,b.rect.height)*factor)
	return {"panel":Rect2(position,extent),"buttons":buttons,"factor":factor}
static func apply_button(button, profile: Dictionary, package) -> void:
	button.authored_layout = true
	if not button.text.is_empty(): button.set_meta("command_label",button.text)
	button.accessibility_name = str(button.get_meta("command_label",""))
	if button.tooltip_text.is_empty(): button.tooltip_text = button.accessibility_name
	# Native Button text has a font-height floor even when painted transparent.
	# The authored renderer paints the label; accessible text and input identity remain.
	button.text = ""
	for entry in profile.buttons:
		if entry.command != button.symbol: continue
		button.skin = {}
		if entry.appearance == "image":
			for sprite in entry.sprites: button.skin["command."+entry.command+"."+sprite.state] = package.textures[sprite.asset_id]
		button.image_fit = profile.fit
		button.state_tints = profile.tints
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if profile.filter == "nearest" else CanvasItem.TEXTURE_FILTER_LINEAR
		button.queue_redraw()
