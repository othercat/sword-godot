# SPDX-License-Identifier: MIT
extends RefCounted
## Shared map/battle frame selection; presentation only, never dispatches game effects.
const CAPABILITY = "graphics.map-animation.v1"
const BATTLE_CAPABILITY = "graphics.battle-animation.v1"
const BATTLE_ACTIONS = ["idle", "attack", "cast", "item", "defend", "hit", "dying", "dead", "sleep", "escape", "victory"]
const FACINGS = ["up", "down", "left", "right"]

static func validate(sprites: Dictionary, assets: Dictionary) -> String:
	for id in sprites:
		var sprite: Dictionary = sprites[id]
		var clips: Dictionary = {}
		for clip in sprite.clips:
			var key: String = clip.action + "/" + clip.facing
			if clips.has(key): return "duplicate action/facing clip: " + id
			clips[key] = clip
			var frames: Dictionary = {}
			var duration: int = 0
			for frame in clip.frames:
				if frames.has(frame.frame_id): return "duplicate frame identity: " + id
				frames[frame.frame_id] = true
				if not assets.has(frame.asset_id) or assets[frame.asset_id].kind != "texture": return "invalid animation texture: " + id
				if frame.anchor.x > frame.width or frame.anchor.y > frame.height: return "anchor outside declared image: " + id
				duration += int(frame.duration_us)
			if duration > 60000000: return "animation clip exceeds 60 seconds: " + id
		var battle: bool = sprite.kind == "battle"
		var facings: Array = [] if battle else FACINGS.duplicate()
		if battle:
			for clip in sprite.clips:
				if clip.facing not in facings: facings.append(clip.facing)
		for facing in facings:
			if not clips.has("idle/" + facing): return "missing directional idle: " + id
			for action in (BATTLE_ACTIONS if battle else ["walk"]):
				if sprite.missing_action == "error" and not clips.has(action + "/" + facing): return "missing action without fallback: " + id
	return ""

static func clip_for(sprite: Dictionary, action: String, facing: String) -> Dictionary:
	for clip in sprite.clips:
		if clip.action == action and clip.facing == facing: return clip
	if sprite.missing_action == "idle" and action != "idle": return clip_for(sprite, "idle", facing)
	return {} # Explicit static fallback; validation prevents missing required clips.

static func frame_at(clip: Dictionary, elapsed_us: int) -> Dictionary:
	if clip.is_empty(): return {}
	var total: int = 0
	for frame in clip.frames: total += int(frame.duration_us)
	var time_us: int = maxi(0, elapsed_us)
	if clip.loop: time_us %= total
	else: time_us = mini(time_us, total - 1)
	for frame in clip.frames:
		if time_us < int(frame.duration_us): return frame
		time_us -= int(frame.duration_us)
	return {}
