# SPDX-License-Identifier: MIT
extends RefCounted
const KEY = "pal.native.map-ui"
const SCHEMA = "pal.native.map-ui.v1"
const CAPABILITY = "graphics.map-ui.v1"
static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func for_scene(content: Dictionary, scene_id: String) -> Dictionary:
	for row in content.extensions.get(KEY, {}).get("scenes", []):
		if row.scene_id == scene_id: return row
	return {}
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Array = []
	for row in package.world.extensions[KEY].scenes:
		if row.scene_id in seen or not package.world.scenes.any(func(s): return s.id == row.scene_id): return "map UI: duplicate or unknown scene"
		seen.append(row.scene_id)
		var ids: Array = []; var kinds: Array = []
		for element in row.elements:
			if element.id in ids or element.kind in kinds: return "map UI: duplicate element id or kind"
			ids.append(element.id); kinds.append(element.kind)
			var r: Dictionary = element.rect
			if r.x+r.width > 100 or r.y+r.height > 100: return "map UI: element exceeds workspace"
			if element.kind == "dialogue" and not element.visible: return "map UI: dialogue and choices must stay accessible"
		if row.elements[0].kind != "map" or not "party" in kinds or not "dialogue" in kinds: return "map UI: map background and both panels required"
	return ""
