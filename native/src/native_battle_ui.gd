# SPDX-License-Identifier: MIT
extends RefCounted
## Content-only true-color skin. Geometry and battle decisions stay elsewhere.
const Classic = preload("res://src/native_classic_battle.gd")
const KEY = "pal.native.battle-ui"
const SCHEMA = "pal.native.battle-ui.v1"
const CAPABILITY = "graphics.battle-ui.v1"

static func used(world: Dictionary) -> bool: return world.get("extensions",{}).has(KEY)
static func definition(world: Dictionary) -> Dictionary: return world.get("extensions",{}).get(KEY,{})
static func sprites(world: Dictionary) -> Array:
	var result: Array = []
	for entry in definition(world).get("encounters",[]): result.append_array(entry.sprites)
	return result
static func for_encounter(package, encounter_id: String) -> Dictionary:
	var result: Dictionary = {}
	for entry in definition(package.world).get("encounters",[]):
		if entry.encounter_id == encounter_id:
			for sprite in entry.sprites: result[sprite.slot] = package.textures[sprite.asset_id]
	return result
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Dictionary = {}
	for entry in definition(package.world).encounters:
		if seen.has(entry.encounter_id) or not package.world.get("encounters",[]).any(func(e): return e.id == entry.encounter_id): return "battle UI: duplicate or unknown encounter"
		seen[entry.encounter_id] = true
		if Classic.for_encounter(package.world,entry.encounter_id).get("preset") != "pal.dream-oblique.v1": return "battle UI requires Dream presentation"
		var slots: Dictionary = {}
		for sprite in entry.sprites:
			if slots.has(sprite.slot): return "battle UI: duplicate sprite slot"
			slots[sprite.slot] = true
			if package.index.assets.get(sprite.asset_id,{}).get("kind") != "texture": return "battle UI must reference a texture"
	return ""
