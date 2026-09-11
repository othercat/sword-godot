# SPDX-License-Identifier: MIT
extends RefCounted
## Authored new-game HP/MP; saved entity values stay authoritative after creation.
const KEY = "pal.native.initial-vitals"
const SCHEMA = "pal.native.initial-vitals.v1"
const CAPABILITY = "actors.initial-vitals.v1"
const Progression = preload("res://src/native_progression.gd")
const Training = preload("res://src/native_training.gd")
const Equipment = preload("res://src/native_equipment.gd")

static func used(content: Dictionary) -> bool:
	return content.extensions.has(KEY)

static func initial_stats(package, entity: Dictionary) -> Dictionary:
	var components: Dictionary = {}
	var growth: Dictionary = Progression.profile(package, entity.definition_id)
	if not growth.is_empty(): components[Progression.KEY] = {"experience": growth.initial_experience}
	var secondary: Dictionary = Training.profile(package.world, entity.definition_id)
	if not secondary.is_empty(): components[Training.KEY] = Training.initial(secondary)
	var loadout: Array = []
	for row in Equipment.definition(package.world).get("initial_loadouts", []):
		if row.instance_id == entity.instance_id: loadout = row.loadout
	components[Equipment.KEY] = {"loadout": loadout}
	return Progression.stats(package, {"definition_id": entity.definition_id, "components": components})

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Dictionary = {}
	for row in package.world.extensions[KEY].actors:
		if seen.has(row.instance_id) or not package.index.entities.has(row.instance_id): return "initial-vitals: duplicate or unresolved instance"
		seen[row.instance_id] = true
		var limits: Dictionary = initial_stats(package, package.index.entities[row.instance_id])
		if row.hp > limits.max_hp or row.mp > limits.max_mp: return "initial-vitals: HP/MP exceeds effective new-game maximum"
	return ""

static func initialize(package, state: Dictionary) -> String:
	if not used(package.world): return ""
	# Recheck the actual initialized state before applying anything. The session
	# owns rollback if a candidate has changed since package admission.
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var actors: Dictionary = {}; var seen: Dictionary = {}
	for actor in state.entities: actors[actor.instance_id] = actor
	for row in package.world.extensions[KEY].actors:
		if seen.has(row.instance_id) or not actors.has(row.instance_id): return "initial-vitals: duplicate or unresolved instance"
		seen[row.instance_id] = true
		var limits: Dictionary = Progression.stats(package, actors[row.instance_id])
		if row.hp > limits.max_hp or row.mp > limits.max_mp: return "initial-vitals: HP/MP exceeds initialized maximum"
	for row in package.world.extensions[KEY].actors:
		actors[row.instance_id].hp = int(row.hp); actors[row.instance_id].mp = int(row.mp)
	return ""
