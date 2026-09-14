# SPDX-License-Identifier: MIT
extends RefCounted
## Opt-in experimental original preview, separate from ordinary admission.
## OpeningInputs are provisional probe inputs, not recovered original defaults.
## Unowned requests remain named failures/parks, never completion receipts.
const Game = preload("res://src/native_pal98_new_game.gd")
const Display = preload("res://src/native_pal98_scene_display.gd")
const Host = preload("res://src/native_pal98_scene_window.gd")
const OpeningInputs = preload("res://src/native_pal98_opening_inputs.gd")
const Schema = preload("res://src/native_schema.gd")

## Minimal production logic clock: consumed timer units counted separately
## from display frames. The full recovered cadence stays a named dependency.
class LogicClock:
	var units := 0
	func consume(count: int) -> Dictionary:
		units += count
		return {"consumed": count, "total": units}

## The display executor's fade/event pump completion; the fade state
## machines themselves stay real in the executor.
class EventPump:
	func answer(request: Dictionary) -> Dictionary:
		return {"error": "experimental preview has no event executor for " + str(request.get("kind", "unknown"))}

var error := ""
var game
var display
var host
var clock := LogicClock.new()
var _runtime := EventPump.new()
var _timer_accumulator := 0.0
var _timer_interval := 1.0 / 60.0
var _present_generation := -1
var _generation := 0
var _ticking := false

func active() -> bool:
	return game != null and not game.state.is_empty()

func pending_kind() -> String:
	return "" if game == null else game.pending_kind()

func describe() -> Dictionary:
	if not active(): return {"active": false}
	var globals: Dictionary = game.state.globals
	return {"active": true, "pending_kind": game.pending_kind(),
		"has_pending_presentation": game.has_pending_presentation(),
		"loaded_map_id": globals.get("loaded_map_id"),
		"current_scene": globals.get("current_scene"),
		"palette_variant": display.active_variant(),
		"palette_rgb6_sha": Schema.digest(game.executor.installed_rgb6()),
		"frame_count": display.frame_count,
		"seed_kind": game.state.get("rng_source", {}).get("seed", {}).get("kind"),
		"seed": game.state.get("rng_source", {}).get("seed", {}).get("seed"),
		"inputs": OpeningInputs.provenance()}

func start(package, host_window: Window, content_parent: Node, experimental_inputs: bool = false) -> bool:
	stop(); error = ""
	if not experimental_inputs:
		error = "provisional opening inputs require explicit experimental preview opt-in"; return false
	if package == null or host_window == null or content_parent == null \
			or not host_window.is_inside_tree() or not content_parent.is_inside_tree():
		error = "pal98 scene session requires an in-tree window and content parent"; return false
	if DisplayServer.get_name() == "headless":
		error = "pal98 scene session requires a non-headless display server"; return false
	game = Game.new()
	if not game.open(package):
		error = game.error; stop(); return false
	game.bind_clock(clock); game.bind_runtime(_runtime)
	game.bind_key_map([0, 1, 2, 3, 4, 5, 6, 7, 8], 0, 8)
	var opening: Dictionary = game.new_state_from_source(0, "startup_capture", OpeningInputs.inputs())
	if opening.has("error"):
		error = "opening state: " + str(opening.error); stop(); return false
	display = Display.new()
	host = Host.new()
	if not host.bind_host(host_window, content_parent, game, display):
		error = host.error; stop(); return false
	var begun: Dictionary = game.begin()
	if begun.has("error"):
		error = "opening chain: " + str(begun.error); stop(); return false
	var presented: Dictionary = display.present()
	if presented.has("error"):
		error = str(presented.error); stop(); return false
	_present_generation = game.presentation_generation()
	return true

func stop() -> void:
	_generation += 1; _ticking = false; clock = LogicClock.new()
	if host != null: host.unbind()
	if game != null: game.cancel()
	game = null; display = null; host = null
	_present_generation = -1; _timer_accumulator = 0.0

## One production frame. A parked opening keeps the adopted state visible and
## is reported by name: the dialogue-page owner (capture order, surface and
## typed presentation) is a separate capability, and movement waits behind
## the parked opening. Nothing here fakes a completed chain.
func tick(delta: float, key_levels: PackedInt32Array) -> Dictionary:
	if not active(): return {"error": "the pal98 scene session is not active"}
	if _ticking: return {"pending": true, "completed": false, "owner": "experimental_frame"}
	if not is_finite(delta) or delta < 0: return {"error": "experimental frame delta must be finite and nonnegative"}
	_timer_accumulator += delta
	var timer_due := false
	while _timer_accumulator >= _timer_interval:
		_timer_accumulator -= _timer_interval; timer_due = true
	if (game.has_pending_presentation() or game.is_dialogue_parked()) and display.surface == null:
		var shown: Dictionary = _repaint()
		if shown.has("error"): return {"error": str(shown.error)}
		return {"parked": game.pending_kind(), "owner": "dialogue_page",
			"completed": false, "timer_due": timer_due,
			"current_scene": game.state.globals.get("current_scene")}
	var generation := _generation
	_ticking = true
	var ticked: Dictionary = await host.tick_frame(key_levels, timer_due)
	if generation != _generation: return {"error": "stale experimental frame completion"}
	_ticking = false
	if ticked.has("error"): return {"error": str(ticked.error)}
	return {"completed": ticked.get("completed", false),
		"input_move": ticked.get("input_move", false),
		"pending_kind": game.pending_kind(),
		"world": [game.state.globals.world_x, game.state.globals.world_y]}

func _repaint() -> Dictionary:
	if game.presentation_generation() == _present_generation:
		var again: Dictionary = display.republish()
		if not again.has("error"): return again
	var presented: Dictionary = display.present()
	if presented.has("error"): return presented
	_present_generation = game.presentation_generation()
	return presented
