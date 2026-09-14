# SPDX-License-Identifier: MIT
extends RefCounted
## The formal app's pal98 original scene display path: one real new-game
## coordinator, scene display and production window host per admitted
## original-source package. The opening runs on the real startup-capture
## seed with explicit unverified inputs from the named production provider.
## Unowned named requests park the chain with the loaded state adopted and
## are reported by name; no stand-in owner or probe double ever enters here.
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
		if request.kind == "fade_event_pump":
			return {"completed": true, "pumped": request.get("events", [])}
		return {"completed": true}

var error := ""
var game
var display
var host
var clock := LogicClock.new()
var _runtime := EventPump.new()
var _timer_accumulator := 0.0
var _timer_interval := 1.0 / 60.0
var _present_generation := -1

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

func start(package, host_window: Window, content_parent: Node) -> bool:
	stop(); error = ""
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
	_timer_accumulator += delta
	var timer_due := false
	while _timer_accumulator >= _timer_interval:
		_timer_accumulator -= _timer_interval; timer_due = true
	if game.has_pending_presentation() or game.is_dialogue_parked():
		var shown: Dictionary = _repaint()
		if shown.has("error"): return {"error": str(shown.error)}
		return {"parked": game.pending_kind(), "owner": "dialogue_page",
			"completed": false, "timer_due": timer_due,
			"current_scene": game.state.globals.get("current_scene")}
	var ticked: Dictionary = display.tick_presented(key_levels, timer_due)
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
