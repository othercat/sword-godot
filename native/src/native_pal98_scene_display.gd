# SPDX-License-Identifier: MIT
extends RefCounted
## Current resources and the installed palette feed a real viewport. Dialogue
## requests remain parked until this owner returns the rendered surface receipt.
const Composition = preload("res://src/native_pal98_scene_composition.gd")
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
var game
var stage: SubViewport
var page_view: TextureRect
var surface
var font
var encoding: String = ""
var error: String = ""
var frame_count: int = 0
var last_receipt: Dictionary = {}
var _binding_generation := 0
var _accepted_generation := -1
var _surface_generation := -1
var _surface_revision := -1
var _surface_palette := PackedByteArray()
var _showing_dialogue := false

func _invalidate() -> void:
	_binding_generation += 1
	last_receipt = {}; frame_count = 0; _accepted_generation = -1
	_surface_generation = -1; _surface_revision = -1; _surface_palette = PackedByteArray()
	_showing_dialogue = false
	if surface != null: surface.invalidate()
	if page_view != null: page_view.texture = null

func bind(owner) -> bool:
	_invalidate(); game = null
	if owner == null or owner.records == null or owner.state.is_empty():
		error = "scene display requires an opened game with a resting state"; return false
	game = owner; error = ""; return true

func bind_display_target(target: SubViewport, page_texture_view: TextureRect = null) -> bool:
	_invalidate(); stage = null; page_view = null
	if target == null or not target.is_inside_tree() or target.size != Vector2i(320,200):
		error = "scene display target must be a real 320x200 viewport in the tree"; return false
	stage = target; page_view = page_texture_view; error = ""; return true

func unbind_display_target() -> void:
	_invalidate()
	stage = null; page_view = null

func bind_dialogue_surface(dialogue_surface, font_owner, text_encoding: String) -> bool:
	_invalidate(); surface = null
	if game == null or dialogue_surface == null or not dialogue_surface.has_method("reset_page") or not dialogue_surface.has_method("apply_request"):
		error = "the dialogue page publisher must be the real dialogue surface"; return false
	if not dialogue_surface.is_inside_tree() or font_owner == null:
		error = "the dialogue surface and font must be ready"; return false
	surface = dialogue_surface; font = font_owner; encoding = text_encoding
	game.require_presented_dialogue()
	error = ""; return true

func active_variant() -> int:
	return 1 if int(game.state.globals.get("day_night_word", 0)) >= 384 else 0

func caller() -> Dictionary:
	var g: Dictionary = game.state.globals
	return {"map_id": g.loaded_map_id, "palette_index": 0,
		"palette_variant": active_variant(), "palette_rgb6": game.executor.installed_rgb6(),
		"map_mode": 0, "clip_bottom": 200,
		"viewport_x": g.viewport_x, "viewport_y": g.viewport_y,
		"member_last": g.member_last, "follower_count": g.follower_count,
		"team_layer": g.party_layer_word, "party_records": game.state.party_records}

func present(publish_receipt: bool = true) -> Dictionary:
	if game == null or game.state.is_empty():
		return {"error": "scene display requires an opened game with a resting state"}
	if stage == null or not stage.is_inside_tree() or stage.size != Vector2i(320,200) or DisplayServer.get_name() == "headless":
		return {"error": "scene presentation requires a live 320x200 rendered target"}
	var composed: Dictionary = Composition.build("render_scene_frame",
		game.records, game.storage, game.state.events, game.cache, caller())
	if composed.has("error"): return composed
	for child in stage.get_children():
		stage.remove_child(child); child.free()
	stage.add_child(composed.value)
	if publish_receipt:
		if page_view != null: page_view.texture = stage.get_texture()
		frame_count += 1; last_receipt = composed; _showing_dialogue = false
		_accepted_generation = game.presentation_generation()
	return composed

func _ensure_page() -> Dictionary:
	var generation: int = game.presentation_generation()
	var palette: PackedByteArray = game.executor.installed_rgb6()
	var issue: String = Indexed.validate_palette(palette)
	if not issue.is_empty(): return {"error": issue}
	if _surface_generation == generation and _surface_revision == game.page_revision and _surface_palette == palette:
		return {}
	var binding: int = _binding_generation
	# Preparing a background must not replace the accepted dialogue receipt.
	var base: Dictionary = present(false)
	if base.has("error"): return base
	await stage.get_tree().process_frame
	await RenderingServer.frame_post_draw
	if binding != _binding_generation or game.presentation_generation() != generation:
		return {"error": "scene display binding changed during page preparation"}
	var frame: Image = stage.get_texture().get_image(); frame.convert(Image.FORMAT_RGBA8)
	var colours := PackedColorArray()
	for index in range(256):
		colours.append(Color8(palette[index*3]*4,palette[index*3+1]*4,palette[index*3+2]*4))
	if _surface_generation != generation: surface.invalidate()
	var reset: Dictionary = await surface.reset_page(font, colours, frame)
	if reset.has("error"): return reset
	if binding != _binding_generation or game.presentation_generation() != generation:
		return {"error": "scene display binding changed during page reset"}
	# Repaint only accepted same-page text when the base/palette is refreshed.
	# This replay never releases a script request or consumes input/timer events.
	for request in game.pending_page_requests():
		var replayed: Dictionary = await surface.apply_request(request, encoding)
		if replayed.has("error"): return replayed
		if binding != _binding_generation or game.presentation_generation() != generation:
			return {"error": "scene display binding changed during text repaint"}
	_surface_generation = generation; _surface_revision = game.page_revision
	_surface_palette = palette.duplicate()
	return {}

func present_dialogue_page() -> Dictionary:
	if game == null or not game.is_dialogue_parked(): return {"error": "no parked dialogue page to publish"}
	if surface == null: return {"error": "a dialogue page requires a bound dialogue surface"}
	var binding: int = _binding_generation
	var generation: int = game.presentation_generation()
	var drawn := 0
	for guard in range(4096):
		var ready: Dictionary = await _ensure_page()
		if ready.has("error"): return ready
		if not game.has_pending_presentation(): break
		var pending: Dictionary = game.pending_presentation()
		var applied: Dictionary = await surface.apply_request(pending.effect, encoding,
			{"request_id": pending.id, "generation": pending.generation})
		if binding != _binding_generation or game.presentation_generation() != generation:
			return {"error": "stale scene display completion"}
		var resumed: Dictionary = game.resume_presentation(pending.id, applied)
		if resumed.has("error"): return resumed
		if pending.effect.kind in ["draw_glyph","draw_string"]: drawn += 1
		if not game.has_pending_presentation(): break
	if game.has_pending_presentation(): return {"error": "dialogue presentation request budget exceeded"}
	if binding != _binding_generation or game.presentation_generation() != generation:
		return {"error": "stale dialogue page publication"}
	if page_view != null: page_view.texture = surface.get_texture()
	_showing_dialogue = true; _accepted_generation = generation
	last_receipt = {"kind": "dialogue_page", "snapshot": surface.text_snapshot(), "generation": generation}
	return {"completed": true, "drawn": drawn, "snapshot": surface.text_snapshot()}

func republish() -> Dictionary:
	if game == null or last_receipt.is_empty() or _accepted_generation != game.presentation_generation():
		return {"error": "nothing accepted in the current generation to republish"}
	var target = surface if _showing_dialogue else stage
	if target == null or not target.is_inside_tree(): return {"error": "accepted display target is unavailable"}
	if page_view != null: page_view.texture = target.get_texture()
	return {"completed": true, "frame_count": frame_count, "receipt": last_receipt}

func tick_presented(key_levels, timer_tick: bool = false) -> Dictionary:
	if game == null: return {"error": "scene display is not bound"}
	var ticked: Dictionary = game.tick(key_levels, timer_tick)
	if ticked.has("error"): return ticked
	if ticked.get("awaiting_effect", false):
		var page: Dictionary = await present_dialogue_page()
		if page.has("error"): return page
		return {"completed": game.awaiting_player, "awaiting_effect": game.is_dialogue_parked(),
			"pending_kind": game.pending_kind(), "pending_model": game.pending_model(),
			"tick": ticked, "page": page, "input_move": false,
			"world": [game.state.globals.world_x, game.state.globals.world_y]}
	var presented: Dictionary = present()
	if presented.has("error"): return presented
	return {"completed": true, "tick": ticked, "composition": presented,
		"requests": presented.requests, "sprite_rows": presented.sprite_rows,
		"input_move": ticked.get("input_move", false)}
