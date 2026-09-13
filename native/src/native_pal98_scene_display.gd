# SPDX-License-Identifier: MIT
extends RefCounted
## Production scene presentation. Every player tick's resulting state reaches
## the actually displayed frame: the caller is derived from the game's live
## state (viewport, party, layers, day/night word), the frame is composed from
## the same sprite cache the chain adopted, and the GPU view is published to
## the bound display target. No fixed palette index, no reuse of an old frame
## as success, and no initialization or input authority here.
const Composition = preload("res://src/native_pal98_scene_composition.gd")

var game
var stage: SubViewport
var error: String = ""
var frame_count: int = 0
var last_receipt: Dictionary = {}

func bind(owner) -> bool:
	if owner == null or owner.records == null or owner.state.is_empty():
		error = "scene display requires an opened game with a resting state"; return false
	game = owner; error = ""; return true

func bind_display_target(target: SubViewport) -> bool:
	if target == null: error = "scene display target must be a real viewport"; return false
	stage = target; error = ""; return true

## The active palette view follows the day/night word (G026C word indexing:
## day 0, night 384), never a fixed palette number.
func active_variant() -> int:
	return 1 if int(game.state.globals.get("day_night_word", 0)) >= 384 else 0

func caller() -> Dictionary:
	var g: Dictionary = game.state.globals
	return {"map_id": g.loaded_map_id, "palette_index": 0,
		"palette_variant": active_variant(), "map_mode": 0, "clip_bottom": 200,
		"viewport_x": g.viewport_x, "viewport_y": g.viewport_y,
		"member_last": g.member_last, "follower_count": g.follower_count,
		"team_layer": g.party_layer_word, "party_records": game.state.party_records}

## Compose the current state and publish it to the display target. A
## composition failure is returned by name; the previously published frame is
## left untouched and is never reported as this frame's success.
func present() -> Dictionary:
	if game == null or game.state.is_empty():
		return {"error": "scene display requires an opened game with a resting state"}
	var composed: Dictionary = Composition.build("render_scene_frame",
		game.records, game.storage, game.state.events, game.cache, caller())
	if composed.has("error"): return composed
	if stage != null:
		for child in stage.get_children():
			stage.remove_child(child); child.free()
		stage.add_child(composed.value)
	frame_count += 1
	last_receipt = composed
	return composed

## Republish the authoritative page without any logic tick: the last accepted
## receipt is re-presented exactly as it was accepted (minimize/restore and
## refocus paths). A stored page is never resurrected into a newer state.
func republish() -> Dictionary:
	if last_receipt.is_empty():
		return {"error": "nothing accepted to republish yet"}
	return {"completed": true, "frame_count": frame_count,
		"receipt": last_receipt}

## One production iteration: the game's tick (movement, requests) followed by
## presentation of the resulting state. The tick's draw requests and the
## published frame are returned together so the caller can check that the
## requests reached the displayed frame.
func tick_presented(key_levels) -> Dictionary:
	if game == null: return {"error": "scene display is not bound"}
	var ticked: Dictionary = game.tick(key_levels)
	if ticked.has("error"): return ticked
	var presented: Dictionary = present()
	if presented.has("error"): return presented
	return {"completed": true, "tick": ticked, "composition": presented,
		"requests": presented.requests, "sprite_rows": presented.sprite_rows,
		"input_move": ticked.get("input_move", false)}
