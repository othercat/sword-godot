# SPDX-License-Identifier: MIT
extends RefCounted
const EnemyPhysical = preload("res://src/native_enemy_physical.gd")
const Zip = preload("res://src/native_zip.gd")
const Directory = preload("res://src/native_directory.gd")
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
const EnemyActions = preload("res://src/native_enemy_actions.gd")
const Equipment = preload("res://src/native_equipment.gd")
const InitialVitals = preload("res://src/native_initial_vitals.gd")
const Classic = preload("res://src/native_classic_battle.gd")
const BattleUi = preload("res://src/native_battle_ui.gd")
const BattleHud = preload("res://src/native_battle_hud_config.gd")
const PartyCard = preload("res://src/native_party_card.gd")
const HudPlacement = preload("res://src/native_hud_placement.gd")
const Sampling = preload("res://src/native_sampling.gd")
const MapPerformance = preload("res://src/native_performance.gd")
const CommandPanel = preload("res://src/native_command_panel.gd")
const MapUi = preload("res://src/native_map_ui.gd")
const StoryNotice = preload("res://src/native_story_notice.gd")
const BattleCanvas = preload("res://src/native_battle_canvas.gd")
const EnemyOverlay = preload("res://src/native_enemy_overlay.gd")
const BattleFormation = preload("res://src/native_battle_formation.gd")
const AttackFormula = preload("res://src/native_attack_formula.gd")
const AttackRandom = preload("res://src/native_attack_random.gd")
const PlayerPhysical = preload("res://src/native_player_physical.gd")
const Training = preload("res://src/native_training.gd")
const Progression = preload("res://src/native_progression.gd")
const Regions = preload("res://src/native_regions.gd")
const PartyTrail = preload("res://src/native_party_trail.gd")
const BATTLE_SCENE_CAPABILITY = "graphics.battle-scene.v1"
const CAPABILITIES = [BATTLE_SCENE_CAPABILITY, Statuses.CAPABILITY, Inventory.CAPABILITY, Skills.CAPABILITY, Battle.CAPABILITY, SceneTravel.GATE_CAPABILITY, Regions.CAPABILITY, Condition.CAPABILITY, PartyTrail.CAPABILITY, SceneTravel.CAPABILITY, "package.local-preview.v1", "world.tile-layers.v1", "world.isometric.v1", "movement.pal-walk.v1", "world.orthogonal.v1", "party.roster.v1", "story.dialogue.v1", "story.choice.v1", "story.variables.v1", MapAnimation.CAPABILITY, MapAnimation.BATTLE_CAPABILITY]
const RULES = {"schema": "pal.native.ruleset.v1", "id": "pal.native.story-core.v1", "version": "0.1.0", "operations": ["dialogue", "choice", "set", "branch", "party", "end"], "variable_assignment": "declared_type_and_scope", "save_phase": "before_node"}
var error: String = ""
var manifest: Dictionary = {}
var world: Dictionary = {}
var content_lock: String = ""
var index: Dictionary = {}
var textures: Dictionary = {}
var schema = Schema.new()
var _source
var map_cells: Dictionary = {}
var map_blocked: Dictionary = {}

func load_package(path: String) -> bool:
	error = ""
	# Reject network share/URL spellings before any directory existence query.
	var local_path = path.replace("\\", "/")
	if local_path.begins_with("//") or (local_path.contains("://") and not local_path.begins_with("res://") and not local_path.begins_with("user://")):
		return _fail("Native package must be a local file or directory")
	_source = Directory.new() if DirAccess.dir_exists_absolute(path) or path.get_file() == "manifest.json" else Zip.new()
	if not _source.open(path): return _fail(_source.error)
	var bytes: PackedByteArray = _source.read("manifest.json")
	if not _source.error.is_empty(): return _fail(_source.error)
	manifest = _json(bytes)
	if not error.is_empty(): return _fail(error)
	var issue: String = schema.validate("pal.native.package.v1", manifest)
	if not issue.is_empty(): return _fail(issue)
	content_lock = Schema.digest(bytes)
	if not manifest.dependencies.is_empty(): return _fail("package dependencies not implemented")
	for capability in manifest.required_capabilities:
		if capability not in CAPABILITIES and capability not in [InitialVitals.CAPABILITY, StoryNotice.CAPABILITY, MapUi.CAPABILITY, PartyCard.CAPABILITY, PartyCard.CAPABILITY_V2, HudPlacement.CAPABILITY, HudPlacement.CAPABILITY_V2, EnemyActions.CAPABILITY, Progression.CAPABILITY, Equipment.CAPABILITY, Classic.CAPABILITY, Classic.CAPABILITY_V2, BattleUi.CAPABILITY, BattleHud.CAPABILITY, BattleCanvas.CAPABILITY, CommandPanel.CAPABILITY, EnemyOverlay.CAPABILITY, BattleFormation.CAPABILITY, AttackFormula.CAPABILITY, AttackRandom.CAPABILITY, PlayerPhysical.CAPABILITY, Training.CAPABILITY, Training.ESCAPE_CAPABILITY, EnemyPhysical.CAPABILITY, MapPerformance.CAPABILITY, Sampling.CAPABILITY]: return _fail("unsupported capability: " + capability)
	for key in ["pal.native.package.v1", "pal.native.content.v1"]:
		if manifest.contract_hashes.get(key) != schema.hashes.get(key): return _fail("contract hash mismatch: " + key)
	if manifest.contract_hashes.size() != 2: return _fail("unknown contract hash")
	var files: Dictionary = {}
	var folded: Dictionary = {"manifest.json": true}
	for file in manifest.files:
		if not Zip.portable(file.path) or folded.has(file.path.to_lower()): return _fail("duplicate/nonportable manifest path")
		folded[file.path.to_lower()] = true
		files[file.path] = file
	if files.size() + 1 != _source.entries.size(): return _fail("undeclared or missing package files")
	var payloads: Dictionary = {}
	for name in files:
		if not _source.entries.has(name) or _source.entries[name].size != files[name].size_bytes: return _fail("missing file or length mismatch: " + name)
		var data: PackedByteArray = _source.read(name)
		if not _source.error.is_empty() or Schema.digest(data) != files[name].sha256: return _fail("payload hash mismatch: " + name)
		payloads[name] = data
	if not payloads.has("content/world.json") or not payloads.has("content/rules.json"): return _fail("missing Native world/rules")
	if manifest.ruleset_id != RULES.id or Schema.digest(payloads["content/rules.json"]) != manifest.ruleset_hash: return _fail("rules identity mismatch")
	world = _json(payloads["content/world.json"])
	if not error.is_empty(): return _fail(error)
	issue = schema.validate("pal.native.content.v1", world)
	if not issue.is_empty(): return _fail(issue)
	var enemy_used: bool = EnemyActions.used(world)
	if enemy_used != (EnemyActions.CAPABILITY in manifest.required_capabilities): return _fail("enemy action capability/component mismatch")
	var growth_used: bool = Progression.used(world)
	if growth_used != (Progression.CAPABILITY in manifest.required_capabilities): return _fail("progression capability/component mismatch")
	var equipment_used: bool = Equipment.used(world)
	if equipment_used != (Equipment.CAPABILITY in manifest.required_capabilities): return _fail("equipment capability/component mismatch")
	var component_hashes: Dictionary = {}
	if InitialVitals.used(world) != (InitialVitals.CAPABILITY in manifest.required_capabilities): return _fail("initial-vitals capability/component mismatch")
	if InitialVitals.used(world): component_hashes[InitialVitals.SCHEMA] = schema.hashes.get(InitialVitals.SCHEMA)
	if Sampling.used(world) != (Sampling.CAPABILITY in manifest.required_capabilities): return _fail("sampling capability/component mismatch")
	if Sampling.used(world): component_hashes[Sampling.SCHEMA] = schema.hashes.get(Sampling.SCHEMA)
	if MapPerformance.used(world) != (MapPerformance.CAPABILITY in manifest.required_capabilities): return _fail("performance capability/component mismatch")
	if MapPerformance.used(world): component_hashes[MapPerformance.SCHEMA] = schema.hashes.get(MapPerformance.SCHEMA)
	var formula_used: bool = AttackFormula.used(world)
	if formula_used != (AttackFormula.CAPABILITY in manifest.required_capabilities): return _fail("attack formula capability/component mismatch")
	if formula_used: component_hashes[AttackFormula.SCHEMA] = schema.hashes.get(AttackFormula.SCHEMA)
	var random_used: bool = AttackRandom.used(world)
	if random_used != (AttackRandom.CAPABILITY in manifest.required_capabilities): return _fail("attack random capability/component mismatch")
	if random_used: component_hashes[AttackRandom.SCHEMA] = schema.hashes.get(AttackRandom.SCHEMA)
	var physical_used: bool = PlayerPhysical.used(world)
	if physical_used != (PlayerPhysical.CAPABILITY in manifest.required_capabilities): return _fail("player physical capability/component mismatch")
	if physical_used: component_hashes[PlayerPhysical.SCHEMA] = schema.hashes.get(PlayerPhysical.SCHEMA)
	for capability in [Training.CAPABILITY,Training.ESCAPE_CAPABILITY]:
		if Training.used(world) != (capability in manifest.required_capabilities): return _fail("training capability/component mismatch")
	if Training.used(world): component_hashes[Training.SCHEMA] = schema.hashes.get(Training.SCHEMA)
	if EnemyPhysical.used(world) != (EnemyPhysical.CAPABILITY in manifest.required_capabilities): return _fail("enemy physical capability/component mismatch")
	if EnemyPhysical.used(world): component_hashes[EnemyPhysical.SCHEMA] = schema.hashes.get(EnemyPhysical.SCHEMA)
	var ui_used: bool = BattleUi.used(world)
	if ui_used != (BattleUi.CAPABILITY in manifest.required_capabilities): return _fail("battle UI capability/component mismatch")
	if ui_used: component_hashes[BattleUi.SCHEMA] = schema.hashes.get(BattleUi.SCHEMA)
	if BattleHud.used(world) != (BattleHud.CAPABILITY in manifest.required_capabilities): return _fail("battle HUD capability/component mismatch")
	if BattleHud.used(world): component_hashes[BattleHud.SCHEMA] = schema.hashes.get(BattleHud.SCHEMA)
	for capability in [PartyCard.CAPABILITY,PartyCard.CAPABILITY_V2]:
		if (PartyCard.used(world) and PartyCard.capability(world)==capability) != (capability in manifest.required_capabilities): return _fail("party-card capability/component mismatch")
	if PartyCard.used(world): component_hashes[PartyCard.schema_id(world)] = schema.hashes.get(PartyCard.schema_id(world))
	for capability in [HudPlacement.CAPABILITY,HudPlacement.CAPABILITY_V2]:
		if (HudPlacement.used(world) and HudPlacement.capability(world)==capability) != (capability in manifest.required_capabilities): return _fail("HUD placement capability/component mismatch")
	if HudPlacement.used(world): component_hashes[HudPlacement.schema_id(world)] = schema.hashes.get(HudPlacement.schema_id(world))
	if CommandPanel.used(world) != (CommandPanel.CAPABILITY in manifest.required_capabilities): return _fail("command panel capability/component mismatch")
	if CommandPanel.used(world): component_hashes[CommandPanel.SCHEMA] = schema.hashes.get(CommandPanel.SCHEMA)
	if BattleCanvas.used(world) != (BattleCanvas.CAPABILITY in manifest.required_capabilities): return _fail("battle canvas capability/component mismatch")
	if BattleCanvas.used(world): component_hashes[BattleCanvas.SCHEMA] = schema.hashes.get(BattleCanvas.SCHEMA)
	if MapUi.used(world) != (MapUi.CAPABILITY in manifest.required_capabilities): return _fail("map UI capability/component mismatch")
	if MapUi.used(world): component_hashes[MapUi.SCHEMA] = schema.hashes.get(MapUi.SCHEMA)
	if StoryNotice.used(world) != (StoryNotice.CAPABILITY in manifest.required_capabilities): return _fail("story notice capability/component mismatch")
	if StoryNotice.used(world): component_hashes[StoryNotice.SCHEMA] = schema.hashes.get(StoryNotice.SCHEMA)
	if EnemyOverlay.used(world) != (EnemyOverlay.CAPABILITY in manifest.required_capabilities): return _fail("enemy-overlay capability/component mismatch")
	if EnemyOverlay.used(world): component_hashes[EnemyOverlay.SCHEMA] = schema.hashes.get(EnemyOverlay.SCHEMA)
	if BattleFormation.used(world) != (BattleFormation.CAPABILITY in manifest.required_capabilities): return _fail("battle-formation capability/component mismatch")
	if BattleFormation.used(world): component_hashes[BattleFormation.SCHEMA] = schema.hashes.get(BattleFormation.SCHEMA)
	var layout_used: bool = Classic.used(world)
	for capability in [Classic.CAPABILITY,Classic.CAPABILITY_V2]:
		if (layout_used and Classic.capability(world) == capability) != (capability in manifest.required_capabilities): return _fail("battle layout capability/component mismatch")
	if layout_used: component_hashes[Classic.schema_id(world)] = schema.hashes.get(Classic.schema_id(world))
	if enemy_used: component_hashes[EnemyActions.SCHEMA] = schema.hashes.get(EnemyActions.SCHEMA)
	if growth_used: component_hashes[Progression.SCHEMA] = schema.hashes.get(Progression.SCHEMA)
	if equipment_used: component_hashes[Equipment.SCHEMA] = schema.hashes.get(Equipment.SCHEMA)
	if manifest.extensions.has(EnemyActions.HASH_KEY) != (not component_hashes.is_empty()): return _fail("component hash declaration mismatch")
	if manifest.extensions.get(EnemyActions.HASH_KEY) != (null if component_hashes.is_empty() else component_hashes): return _fail("component contract hash mismatch")
	for key in ["package_id", "entry_scene", "entry_node"]:
		if manifest[key] != world[key]: return _fail("manifest/world mismatch: " + key)
	if not _references(): return _fail(error)
	if _json(payloads["content/rules.json"]) != expected_rules(world): return _fail("unsupported rules definition")
	if Condition.used(world) and Condition.CAPABILITY not in manifest.required_capabilities: return _fail("missing condition capability")
	if not index.battle_sprite_sets.is_empty() and MapAnimation.BATTLE_CAPABILITY not in manifest.required_capabilities: return _fail("missing battle animation capability")
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
	for portrait in Classic.definition(world).get("portraits",[]) + BattleUi.sprites(world) + BattleHud.portraits(world) + PartyCard.sprites(world) + CommandPanel.sprites(world) + MapPerformance.frames(world):
		var texture: Texture2D = textures[portrait.asset_id]
		if texture.get_width() != portrait.width or texture.get_height() != portrait.height: return _fail("portrait PNG dimensions mismatch")
	for sprite in index.sprite_sets.values() + index.battle_sprite_sets.values():
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
	_source.close()
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
	if _source != null: _source.close()
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
	index.battle_sprite_sets = {}
	for row in world.get("battle_sprite_sets", []):
		if index.battle_sprite_sets.has(row.id): return _fail("duplicate battle sprite set ID")
		index.battle_sprite_sets[row.id] = row
	var battle_animation_issue: String = MapAnimation.validate(index.battle_sprite_sets, index.assets)
	if not battle_animation_issue.is_empty(): return _fail(battle_animation_issue)
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
		if actor.get("battle_sprite_set") != null and not index.battle_sprite_sets.has(actor.battle_sprite_set): return _fail("unresolved battle sprite set")
	var battle_uses: Array = world.roster.map(func(id): return [index.entities[id].definition_id, "upper_left"])
	for encounter in world.get("encounters", []):
		if not _texture_ref(encounter.get("background_asset")): return _fail("invalid battle background texture")
		if encounter.get("background_asset") != null and BATTLE_SCENE_CAPABILITY not in manifest.required_capabilities: return _fail("missing battle scene capability")
		for enemy in encounter.enemies: battle_uses.append([enemy.definition_id, "lower_right"])
	for use in battle_uses:
		var set_id = index.actor_definitions.get(use[0], {}).get("battle_sprite_set")
		if set_id != null and not index.battle_sprite_sets[set_id].clips.any(func(c): return c.action == "idle" and c.facing == use[1]): return _fail("battle actor lacks authored side-facing idle")
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
	var formula_issue: String = AttackFormula.validate_content(self)
	if not formula_issue.is_empty(): return _fail(formula_issue)
	var random_issue: String = AttackRandom.validate_content(self)
	if not random_issue.is_empty(): return _fail(random_issue)
	var physical_issue: String = PlayerPhysical.validate_content(self)
	if not physical_issue.is_empty(): return _fail(physical_issue)
	var enemy_issue: String = EnemyActions.validate_content(self)
	if not enemy_issue.is_empty(): return _fail(enemy_issue)
	var equipment_issue: String = Equipment.validate_content(self)
	if not equipment_issue.is_empty(): return _fail(equipment_issue)
	var layout_issue: String = Classic.validate_content(self)
	if not layout_issue.is_empty(): return _fail(layout_issue)
	var ui_issue: String = BattleUi.validate_content(self)
	if not ui_issue.is_empty(): return _fail(ui_issue)
	var battle_formation_issue: String = BattleFormation.validate_content(self)
	if not battle_formation_issue.is_empty(): return _fail(battle_formation_issue)
	var enemy_overlay_issue: String = EnemyOverlay.validate_content(self)
	if not enemy_overlay_issue.is_empty(): return _fail(enemy_overlay_issue)
	var map_ui_issue: String = MapUi.validate_content(self)
	if not map_ui_issue.is_empty(): return _fail(map_ui_issue)
	var notice_issue: String = StoryNotice.validate_content(self)
	if not notice_issue.is_empty(): return _fail(notice_issue)
	var canvas_issue: String = BattleCanvas.validate_content(self)
	if not canvas_issue.is_empty(): return _fail(canvas_issue)
	var hud_issue: String = BattleHud.validate_content(self)
	if not hud_issue.is_empty(): return _fail(hud_issue)
	var card_issue: String = PartyCard.validate_content(self)
	if not card_issue.is_empty(): return _fail(card_issue)
	var placement_issue: String = HudPlacement.validate_content(self)
	if not placement_issue.is_empty(): return _fail(placement_issue)
	var sampling_issue: String = Sampling.validate_content(self)
	if not sampling_issue.is_empty(): return _fail(sampling_issue)
	var performance_issue: String = MapPerformance.validate_content(self)
	if not performance_issue.is_empty(): return _fail(performance_issue)
	var command_issue: String = CommandPanel.validate_content(self)
	if not command_issue.is_empty(): return _fail(command_issue)
	var growth_issue: String = Progression.validate_content(self)
	if not growth_issue.is_empty(): return _fail(growth_issue)
	var training_issue: String = Training.validate_content(self)
	if not training_issue.is_empty(): return _fail(training_issue)
	var enemy_physical_issue: String = EnemyPhysical.validate_content(self)
	if not enemy_physical_issue.is_empty(): return _fail(enemy_physical_issue)
	var vitals_issue: String = InitialVitals.validate_content(self)
	if not vitals_issue.is_empty(): return _fail(vitals_issue)
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
	if EnemyActions.used(content):
		result.version = "0.12.0"; result.enemy_actions = EnemyActions.RULE
	if Progression.used(content):
		result.version = "0.13.0"; result.progression = "native.progression.v1"
	if Equipment.used(content):
		result.version = "0.14.0"; result.equipment = "native.equipment.v1"
	if AttackFormula.used(content):
		result.version = "0.15.0"; result.normal_attack = AttackFormula.PROFILE
	if AttackRandom.used(content):
		result.version = "0.16.0"; result.attack_random = AttackRandom.rule(content)
	if PlayerPhysical.used(content):
		result.version = "0.17.0"; result.player_physical = PlayerPhysical.rule(content)
	if Training.used(content):
		result.version = "0.18.0"; result.training = Training.rule(content)
	if EnemyPhysical.used(content):
		result.version = "0.19.0"; result.enemy_physical = EnemyPhysical.rule(content)
	return result
