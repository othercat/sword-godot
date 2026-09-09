# SPDX-License-Identifier: MIT
extends RefCounted
## Named map presentation only. The session owns time and continuation transactions.
const KEY = "pal.native.performance"
const SCHEMA = KEY + ".v1"
const CAPABILITY = "story.performance.v1"

static func used(world: Dictionary) -> bool: return world.get("extensions", {}).has(KEY)
static func definition(world: Dictionary) -> Dictionary: return world.get("extensions", {}).get(KEY, {})
static func active(state: Dictionary) -> bool: return state.get("extensions", {}).get(KEY, {}).get("active") != null
static func for_node(world: Dictionary, node_id: String) -> Dictionary:
	for row in definition(world).get("performances", []):
		if row.node_id == node_id: return row
	return {}
static func clip_for(world: Dictionary, clip_id: String) -> Dictionary:
	for clip in definition(world).get("clips", []):
		if clip.id == clip_id: return clip
	return {}
static func frames(world: Dictionary) -> Array:
	var result: Array = []
	for clip in definition(world).get("clips", []): result.append_array(clip.frames)
	return result
static func ticks(row: Dictionary) -> int:
	return ceili(float(row.duration_us) * 60.0 / 1000000.0)
static func initialize(world: Dictionary, state: Dictionary) -> void:
	if used(world): state.extensions[KEY] = {"schema": SCHEMA, "kind": "state", "active": null}

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var value: Dictionary = definition(package.world)
	if value.kind != "content": return "performance: wrong component kind"
	var clips: Dictionary = {}
	for clip in value.clips:
		if clips.has(clip.id): return "performance: duplicate clip"
		clips[clip.id] = clip
		var seen: Array = []
		var duration: int = 0
		for frame in clip.frames:
			if frame.frame_id in seen: return "performance: duplicate frame identity"
			seen.append(frame.frame_id); duration += int(frame.duration_us)
			if package.index.assets.get(frame.asset_id, {}).get("kind") != "texture": return "performance: frame requires texture"
			if frame.anchor.x > frame.width or frame.anchor.y > frame.height: return "performance: anchor outside image"
		if duration > 60000000: return "performance: clip exceeds 60 seconds"
	var nodes: Array = []
	for row in value.performances:
		if row.node_id in nodes or package.index.nodes.get(row.node_id, {}).get("op") != "end": return "performance: requires unique explicit end-node boundary"
		nodes.append(row.node_id)
		if not package.index.nodes.has(row.next_node_id) or row.next_node_id == row.node_id: return "performance: unresolved or self-referential continuation"
		var participants: Array = []
		for track in row.tracks:
			if not clips.has(track.clip_id): return "performance: unknown track clip"
			if not track.hide_actor_ids.is_empty() and clips[track.clip_id].composition != "baked-composite": return "performance: only baked composite may replace other visuals"
			for actor in [track.actor_id] + track.hide_actor_ids:
				if not package.index.entities.has(actor) or actor in participants: return "performance: unknown or multiply presented participant"
				participants.append(actor)
	return ""

static func validate_state(package, state: Dictionary) -> String:
	if not used(package.world): return "performance: state without content capability" if state.extensions.has(KEY) else ""
	var value = state.extensions.get(KEY)
	var issue: String = package.schema.validate(SCHEMA, value)
	if not issue.is_empty(): return issue
	if value.kind != "state": return "performance: wrong component kind"
	var row: Dictionary = for_node(package.world, state.cursor.node_id)
	if (value.active != null) != (not row.is_empty()): return "performance: active state and waiting cursor disagree"
	if value.active == null: return ""
	if state.cursor.phase != "before_node" or state.extensions.has("pal.native.battle"): return "performance: map performance cannot overlap battle or another cursor phase"
	if value.active.node_id != row.node_id or value.active.elapsed_ticks >= ticks(row): return "performance: invalid active node or elapsed time"
	var entities: Dictionary = {}
	for actor in state.entities: entities[actor.instance_id] = actor
	for track in row.tracks:
		for actor in [track.actor_id] + track.hide_actor_ids:
			if entities.get(actor, {}).get("scene_id") != state.cursor.scene_id: return "performance: participant outside active scene"
	return ""

static func begin(package, state: Dictionary, row: Dictionary) -> String:
	if state.cursor.safe_point_id == null: return "performance: authored scene/node requires a save boundary"
	state.extensions[KEY].active = {"node_id": row.node_id, "elapsed_ticks": 0}
	return validate_state(package, state)
