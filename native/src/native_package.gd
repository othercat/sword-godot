# SPDX-License-Identifier: MIT
extends RefCounted
const Zip = preload("res://src/native_zip.gd")
const Reader = preload("res://src/native_json.gd")
const Schema = preload("res://src/native_schema.gd")
const MapAnimation = preload("res://src/native_map_animation.gd")
const Terrain = preload("res://src/native_terrain.gd")
const TexturePolicy = preload("res://src/native_texture.gd")
const SceneTravel = preload("res://src/native_scene_travel.gd")
const Condition = preload("res://src/native_condition.gd")
const Skills = preload("res://src/native_skills.gd")
const Inventory = preload("res://src/native_inventory.gd")
const Statuses = preload("res://src/native_statuses.gd")
const Battle = preload("res://src/native_battle.gd")
const Regions = preload("res://src/native_regions.gd")
const PartyTrail = preload("res://src/native_party_trail.gd")
const CAPABILITIES = [Statuses.CAPABILITY, Inventory.CAPABILITY, Skills.CAPABILITY, Battle.CAPABILITY, SceneTravel.GATE_CAPABILITY, Regions.CAPABILITY, Condition.CAPABILITY, PartyTrail.CAPABILITY, SceneTravel.CAPABILITY, "package.local-preview.v1", "world.tile-layers.v1", "world.isometric.v1", "movement.pal-walk.v1", "world.orthogonal.v1", "party.roster.v1", "story.dialogue.v1", "story.choice.v1", "story.variables.v1", MapAnimation.CAPABILITY]
const RULES = {"schema": "pal.native.ruleset.v1", "id": "pal.native.story-core.v1", "version": "0.1.0", "operations": ["dialogue", "choice", "set", "branch", "party", "end"], "variable_assignment": "declared_type_and_scope", "save_phase": "before_node"}
var error: String = ""
var manifest: Dictionary = {}
var world: Dictionary = {}
var content_lock: String = ""
var index: Dictionary = {}
var textures: Dictionary = {}
var schema = Schema.new()
var _zip = Zip.new()
var map_cells: Dictionary = {}
var map_blocked: Dictionary = {}

func load_package(path: String) -> bool:
	error = ""
	if not _zip.open(path): return _fail(_zip.error)
	var bytes = _zip.read("manifest.json")
	manifest = _json(bytes)
	if not error.is_empty(): return _fail(error)
	var issue: String = schema.validate("pal.native.package.v1", manifest)
	if not issue.is_empty(): return _fail(issue)
	content_lock = Schema.digest(bytes)
	if not manifest.dependencies.is_empty(): return _fail("package dependencies not implemented")
	for capability in manifest.required_capabilities:
		if capability not in CAPABILITIES: return _fail("unsupported capability: " + capability)
	for key in ["pal.native.package.v1", "pal.native.content.v1"]:
		if manifest.contract_hashes.get(key) != schema.hashes.get(key): return _fail("contract hash mismatch: " + key)
	if manifest.contract_hashes.size() != 2: return _fail("unknown contract hash")
	var files: Dictionary = {}
	var folded: Dictionary = {"manifest.json": true}
	for file in manifest.files:
		if not Zip.portable(file.path) or folded.has(file.path.to_lower()): return _fail("duplicate/nonportable manifest path")
		folded[file.path.to_lower()] = true
		files[file.path] = file
	if files.size() + 1 != _zip.entries.size(): return _fail("undeclared or missing ZIP files")
	var payloads: Dictionary = {}
	for name in files:
		if not _zip.entries.has(name) or _zip.entries[name].size != files[name].size_bytes: return _fail("missing file or length mismatch: " + name)
		var data = _zip.read(name)
		if not _zip.error.is_empty() or Schema.digest(data) != files[name].sha256: return _fail("payload hash mismatch: " + name)
		payloads[name] = data
	if not payloads.has("content/world.json") or not payloads.has("content/rules.json"): return _fail("missing Native world/rules")
	if manifest.ruleset_id != RULES.id or Schema.digest(payloads["content/rules.json"]) != manifest.ruleset_hash: return _fail("rules identity mismatch")
	world = _json(payloads["content/world.json"])
	if not error.is_empty(): return _fail(error)
	issue = schema.validate("pal.native.content.v1", world)
	if not issue.is_empty(): return _fail(issue)
	for key in ["package_id", "entry_scene", "entry_node"]:
		if manifest[key] != world[key]: return _fail("manifest/world mismatch: " + key)
	if not _references(): return _fail(error)
	if _json(payloads["content/rules.json"]) != expected_rules(world): return _fail("unsupported rules definition")
	if Condition.used(world) and Condition.CAPABILITY not in manifest.required_capabilities: return _fail("missing condition capability")
	if not index.sprite_sets.is_empty() and MapAnimation.CAPABILITY not in manifest.required_capabilities: return _fail("missing map animation capability")
	var declared: Dictionary = {"content/world.json": "content", "content/rules.json": "content"}
	var distribution = manifest.extensions.get("pal.native.distribution")
	var local_preview: bool = manifest.extensions.has("pal.native.distribution")
	if local_preview and distribution != {"scope": "local-preview"}: return _fail("invalid local-preview distribution metadata")
	if local_preview != ("package.local-preview.v1" in manifest.required_capabilities): return _fail("local-preview capability/metadata mismatch")
	textures = {}
	var pixels: int = 0
	for asset in world.assets:
		if declared.has(asset.path) or not files.has(asset.path): return _fail("duplicate/missing asset path")
		declared[asset.path] = asset.kind
		if files[asset.path].sha256 != asset.sha256 or files[asset.path].size_bytes != asset.size_bytes: return _fail("asset identity mismatch")
		if not asset.redistributable and not local_preview: return _fail("asset has no distribution approval")
		# Current runtime supports PNG textures. Audio/font contracts are reserved,
		# and rejected explicitly until their bounded media paths are implemented.
		if asset.kind != "texture": return _fail("asset type not implemented: " + asset.kind)
		var png: PackedByteArray = payloads[asset.path]
		if png.size() < 33 or png.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or png.slice(12, 16).get_string_from_ascii() != "IHDR": return _fail("PNG header missing")
		var width: int = _big32(png, 16)
		var height: int = _big32(png, 20)
		pixels += width * height
		if width < 1 or height < 1 or width > 8192 or height > 8192 or pixels > 33554432: return _fail("decoded texture budget exceeded")
		var decoded = Image.new()
		if decoded.load_png_from_buffer(png) != OK or decoded.get_width() != width or decoded.get_height() != height: return _fail("PNG decode failed")
		# Preserve packaged bytes/hash and all visible RGBA; sanitize only the
		# invisible RGB used by texture filtering, never quantize to a palette.
		TexturePolicy.fix_transparent_edges(decoded)
		textures[asset.id] = ImageTexture.create_from_image(decoded)
	for sprite in index.sprite_sets.values():
		for clip in sprite.clips:
			for frame in clip.frames:
				var texture: Texture2D = textures[frame.asset_id]
				if texture.get_width() != frame.width or texture.get_height() != frame.height: return _fail("animation PNG dimensions mismatch")
	if declared.size() != files.size(): return _fail("unsupported extra payload")
	for map_data in world.maps:
		for tile in map_data.get("terrain", {}).get("tiles", []):
			var texture: Texture2D = textures[tile.asset_id]
			if texture.get_width() != tile.width or texture.get_height() != tile.height: return _fail("tile PNG dimensions mismatch")
	for path_name in files:
		if declared.get(path_name) != files[path_name].kind: return _fail("file kind mismatch")
	_zip.close()
	return true

static func _big32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]

func _json(bytes: PackedByteArray) -> Dictionary:
	var reader = Reader.new()
	var value = reader.decode(bytes)
	if not reader.error.is_empty() or not value is Dictionary:
		error = "invalid JSON object: " + reader.error
		return {}
	return value

func _fail(message: String) -> bool:
	error = message
	_zip.close()
	return false

func _references() -> bool:
	index = {}
	map_cells = {}
	map_blocked = {}
	for table in ["actor_definitions", "entities", "maps", "scenes", "nodes", "variables", "assets", "safe_points"]:
		index[table] = {}
		var key: String = "instance_id" if table == "entities" else "id"
		for row in world[table]:
			if index[table].has(row[key]): return _fail("duplicate " + table + " ID")
			index[table][row[key]] = row
	index.sprite_sets = {}
	for row in world.get("sprite_sets", []):
		if index.sprite_sets.has(row.id): return _fail("duplicate sprite set ID")
		index.sprite_sets[row.id] = row
	var animation_issue: String = MapAnimation.validate(index.sprite_sets, index.assets)
	if not animation_issue.is_empty(): return _fail(animation_issue)
	for key in ["roster", "active_party", "narrative_cast"]:
		for id in world[key]:
			if not index.entities.has(id): return _fail("unresolved " + key)
	for id in world.active_party:
		if id not in world.roster: return _fail("active member outside roster")
		if index.entities[id].scene_id != world.entry_scene: return _fail("active members must share the entry scene")
	if not index.scenes.has(world.entry_scene) or not index.nodes.has(world.entry_node): return _fail("unresolved entry")
	for scene in world.scenes:
		if not index.maps.has(scene.map_id): return _fail("unresolved scene map")
	for map_data in world.maps:
		if map_data.has("terrain"):
			if "world.tile-layers.v1" not in manifest.required_capabilities: return _fail("missing tile layer capability")
			var issue: String = Terrain.validate(map_data, index.assets)
			if not issue.is_empty(): return _fail(issue)
			map_cells[map_data.id] = {}
			for point in map_data.terrain.cells: map_cells[map_data.id][Vector2i(point.x, point.y)] = true
		if "world." + map_data.coordinates.kind + ".v1" not in manifest.required_capabilities: return _fail("missing world projection capability")
		if map_data.coordinates.kind == "isometric" and (map_data.coordinates.tile_width < 2 or map_data.coordinates.tile_height < 2): return _fail("isometric tile edge budget")
		if map_data.get("movement_rule") == "pal.walk.v1":
			if map_data.coordinates.kind != "isometric" or "movement.pal-walk.v1" not in manifest.required_capabilities: return _fail("PAL walking requires isometric capability")
		if map_data.width * map_data.height > 65536: return _fail("map cell budget exceeded")
		if not _texture_ref(map_data.background_asset): return _fail("invalid map texture")
		var blocked: Dictionary = {}
		for point in map_data.blocked:
			var cell = Vector2i(point.x, point.y)
			if not within(point, map_data) or blocked.has(cell) or (map_cells.has(map_data.id) and not map_cells[map_data.id].has(cell)): return _fail("invalid blocked cell")
			blocked[cell] = true
		map_blocked[map_data.id] = blocked
	for actor in world.actor_definitions:
		if not _texture_ref(actor.sprite_asset): return _fail("invalid actor texture")
		if actor.get("map_sprite_set") != null and not index.sprite_sets.has(actor.map_sprite_set): return _fail("unresolved map sprite set")
	for sprite in index.sprite_sets.values():
		if sprite.get("playback", "time") == "pal.walk-phase.v1":
			if "movement.pal-walk.v1" not in manifest.required_capabilities or sprite.missing_action != "error": return _fail("PAL phase capability/directions missing")
			for clip in sprite.clips:
				if clip.action == "walk" and (clip.frames.size() != 3 or not clip.loop): return _fail("PAL phase walk needs three looping frames")
	for entity in world.entities:
		if not index.actor_definitions.has(entity.definition_id) or not index.scenes.has(entity.scene_id): return _fail("unresolved entity reference")
		if entity.interaction_node != null and not index.nodes.has(entity.interaction_node): return _fail("unresolved interaction")
		if not can_stand(entity.scene_id, entity.position): return _fail("invalid entity spawn")
		var sprite_id = index.actor_definitions[entity.definition_id].get("map_sprite_set")
		if sprite_id != null and index.sprite_sets[sprite_id].get("playback") == "pal.walk-phase.v1" and movement_rule(entity.scene_id) != "pal.walk.v1": return _fail("PAL phase entity requires PAL walking map")
	var entry_safe: bool = false
	for point in world.safe_points:
		if not index.scenes.has(point.scene_id) or not index.nodes.has(point.node_id): return _fail("invalid safe point")
		entry_safe = entry_safe or (point.scene_id == world.entry_scene and point.node_id == world.entry_node)
	if not entry_safe: return _fail("entry has no safe point")
	for variable in world.variables:
		if not Schema.is_type(variable.initial, variable.type): return _fail("initial variable type mismatch")
	for node in world.nodes:
		for key in ["next", "then", "else"]:
			if node.has(key) and not index.nodes.has(node[key]): return _fail("unresolved node target")
		match node.op:
			"set", "branch":
				if node.has("condition"):
					var issue: String = Condition.validate(node.condition, index.variables)
					if not issue.is_empty(): return _fail(issue)
					continue
				if not index.variables.has(node.variable): return _fail("unresolved variable")
				if not Schema.is_type(node.get("value", node.get("equals")), index.variables[node.variable].type): return _fail("variable assignment/comparison type")
			"dialogue":
				if node.speaker != null and not index.entities.has(node.speaker): return _fail("unresolved speaker")
			"choice":
				var choices: Dictionary = {}
				for choice in node.options:
					if choices.has(choice.id) or not index.nodes.has(choice.next): return _fail("invalid choice")
					choices[choice.id] = true
			"party":
				for member in node.members:
					if member not in world.roster: return _fail("party node member outside roster")
	if Statuses.used(world) and Statuses.CAPABILITY not in manifest.required_capabilities: return _fail("missing status capability")
	var status_issue: String = Statuses.validate_content(self)
	if not status_issue.is_empty(): return _fail(status_issue)
	if Inventory.used(world) and Inventory.CAPABILITY not in manifest.required_capabilities: return _fail("missing inventory capability")
	var inventory_issue: String = Inventory.validate_content(self)
	if not inventory_issue.is_empty(): return _fail(inventory_issue)
	if Skills.used(world) and Skills.CAPABILITY not in manifest.required_capabilities: return _fail("missing skill capability")
	var skill_issue: String = Skills.validate_content(self)
	if not skill_issue.is_empty(): return _fail(skill_issue)
	if Battle.used(world) and Battle.CAPABILITY not in manifest.required_capabilities: return _fail("missing battle capability")
	var battle_issue: String = Battle.validate_content(self)
	if not battle_issue.is_empty(): return _fail(battle_issue)
	if SceneTravel.used(world) and SceneTravel.CAPABILITY not in manifest.required_capabilities: return _fail("missing scene travel capability")
	if PartyTrail.used(world):
		if PartyTrail.CAPABILITY not in manifest.required_capabilities: return _fail("missing party trail capability")
		for id in world.active_party:
			if index.entities[id].scene_id != world.entry_scene: return _fail("initial trail party must share entry scene")
			for other in world.entities:
				if other.instance_id not in world.active_party and other.scene_id == world.entry_scene and other.position == index.entities[id].position: return _fail("initial trail party overlaps inactive actor")
	var region_issue: String = Regions.validate(self)
	if not region_issue.is_empty(): return _fail(region_issue)
	if SceneTravel.gates_used(world) and SceneTravel.GATE_CAPABILITY not in manifest.required_capabilities: return _fail("missing portal gate capability")
	if Regions.used(world) and Regions.CAPABILITY not in manifest.required_capabilities: return _fail("missing region capability")
	var travel_issue: String = SceneTravel.validate(self)
	if not travel_issue.is_empty(): return _fail(travel_issue)
	return true

func _texture_ref(id: Variant) -> bool:
	return id == null or (index.assets.has(id) and index.assets[id].kind == "texture")

static func within(point: Dictionary, map_data: Dictionary) -> bool:
	var origin: Dictionary = map_data.coordinates.origin
	return point.x >= origin.x and point.y >= origin.y and point.x < origin.x + map_data.width and point.y < origin.y + map_data.height

func can_stand(scene_id: String, point: Dictionary) -> bool:
	if not index.scenes.has(scene_id): return false
	var map_data: Dictionary = index.maps[index.scenes[scene_id].map_id]
	var cell = Vector2i(point.x, point.y)
	return within(point, map_data) and not map_blocked[map_data.id].has(cell) and (not map_cells.has(map_data.id) or map_cells[map_data.id].has(cell))

func movement_rule(scene_id: String) -> String:
	return index.maps[index.scenes[scene_id].map_id].get("movement_rule", "native.grid.v1")

static func expected_rules(content: Dictionary) -> Dictionary:
	var result: Dictionary = RULES.duplicate(true)
	var explicit: bool = false
	var profiles: Array = []
	for map_data in content.maps:
		explicit = explicit or map_data.has("movement_rule") or map_data.coordinates.kind == "isometric"
		var id: String = map_data.get("movement_rule", "native.grid.v1")
		if id not in profiles: profiles.append(id)
	if explicit:
		profiles.sort()
		result.version = "0.2.0"
		result.movement_profiles = profiles
	if SceneTravel.used(content):
		result.version = "0.3.0"
		result.operations.append("scene_transfer")
		result.scene_travel = "explicit-party-slots-interact-portal.v1"
	if PartyTrail.used(content):
		result.version = "0.4.0"
		result.party_movement = PartyTrail.RULE
	if Condition.used(content):
		result.version = "0.5.0"
		result.conditions = Condition.RULE
	if Regions.used(content):
		result.version = "0.6.0"
		result.regions = "native.regions.v1"
	if SceneTravel.gates_used(content):
		result.version = "0.7.0"
		result.portal_gates = "native.portal-gates.v1"
	if Battle.used(content):
		result.version = "0.8.0"
		result.operations.append("battle")
		result.battle = Battle.RULE
		result.save_phase = "before_node_or_battle_command"
	if Skills.used(content):
		result.version = "0.9.0"; result.skills = Skills.RULE
	if Inventory.used(content):
		result.version = "0.10.0"; result.inventory = Inventory.RULE; result.operations.append("inventory")
	if Statuses.used(content):
		result.version = "0.11.0"; result.statuses = Statuses.RULE
	return result
