# SPDX-License-Identifier: MIT
extends RefCounted
## The ordinary new-game owner: derives the opening state from the same
## admitted package sources and drives the real resource/enter chain until the
## original's scene loop rests awaiting a real player. Nothing here copies a
## test fixture; every state field comes from one of these provenance groups:
##
## - Source-derived: the opening runtime scene 1 with entry word 4, both
##   scenes' map words, the day/night palettes, the event storage, the
##   equipment kernel tables and the sprite cache all come from the package
##   reads below.
## - Original pinned facts: the party-in-viewport anchor (160,112), the
##   MAP20 viewport limit pair 1696/1840 from the original 0x41B120..0x41B14A
##   bounds, and the new-game load mask 29 (events + party sprites + entry
##   script + midi request bits) that the reload state machine consumes.
## - Named Native representations: the zeroed five-entry walk trail and the
##   explicit RNG seed argument stand for the original's uninitialized trail
##   and its unobserved new-game seed; the seed is required, never defaulted.
##   The dialog window words are the admitted context the verified chain
##   already consumes; their original initializer is not decoded.
##
## Display routing is real (palette family through the display executor,
## capture/restore/render through the shared page owner). Effects this
## project has not built — audio, the unfinished T121 transition, the replay
## clock — stay named: they execute only through `bind_named_double`, and an
## unbound kind refuses by name instead of acknowledging.
const Reload = preload("res://src/native_pal98_resource_reload.gd")
const Enter = preload("res://src/native_pal98_enter_script.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const DialogueHost = preload("res://src/native_pal98_dialogue_host.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Inventory = preload("res://src/native_pal98_inventory.gd")
const Palette = preload("res://src/native_pal98_palette.gd")
const Display = preload("res://src/native_pal98_display_palette.gd")
const SceneRender = preload("res://src/native_pal98_scene_render.gd")
const Facing = preload("res://src/native_pal98_walk_facing.gd")
const MemberSync = preload("res://src/native_pal98_member_sync.gd")
const CollisionProbe = preload("res://src/native_pal98_collision_probe.gd")
const InputFrame = preload("res://src/native_pal98_input_frame.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")

var error: String = ""
var state: Dictionary = {}
var records
var reload
var enter
var adapter
var dialogue_host
var executor
var renderer
var cache
var kernel
var storage
var facing
var member
var probe
var input
var enters_seen: Array = []
var terminals: Array = []
var awaiting_player := false
var awaiting_confirm := false
var _confirm_gated := false
var _pending_dialogue: Dictionary = {}
var _active_enter_request: Dictionary = {}
var _palette: Palette
var _doubles: Dictionary = {}
var _roles_snapshot: Array = []

class DisplayRouter:
	var game
	func _init(owner) -> void: game = owner
	func answer(request: Dictionary) -> Dictionary:
		return game._route_display(request)

func _failure(message: String) -> Dictionary:
	error = "pal98-new-game: " + message
	return {"error": error}

## A host-bound explicit double for one named product gap (audio, the
## unfinished transition, the replay clock). Never a silent default: the kind
## stays refused when nothing is bound.
func bind_named_double(kind: String, owner) -> bool:
	if kind.is_empty() or owner == null:
		error = "pal98-new-game: a named double requires a kind and an owner"; return false
	_doubles[kind] = owner; error = ""; return true

## The replay clock and runtime event pump are host responsibilities on a real
## frame loop; the suite binds counting doubles under their own names.
func bind_clock(clock) -> bool:
	return executor.bind_clock(clock)

func bind_runtime(runtime) -> bool:
	return executor.bind_runtime(runtime)

## The eight-slot G0854-style logical key map and the T209 layer base word
## come from the host input configuration; the original default map is not
## decoded yet, so the host must pass one explicitly. confirm_slot: the
## optional logical slot whose new press confirms a parked dialogue page.
func bind_key_map(logical_map: Array, layer_base: int, confirm_slot: int = -1) -> bool:
	if input == null:
		error = "pal98-new-game: the input frame is not assembled"; return false
	return input.bind(facing, probe, logical_map, layer_base, confirm_slot)

func open(package) -> bool:
	if package == null or package.pal98_sources == null or package.pal98_graphics == null:
		return _open_fail("the admitted package with sources and graphics is required")
	records = package.pal98_graphics.open_records()
	storage = Events.new()
	if not storage.load_source(package.pal98_sources): return _open_fail(str(storage.error))
	cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
	kernel = Equipment.new()
	kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var inventory: PackedByteArray = PackedByteArray(); inventory.resize(1536)
	adapter = EntryHost.new()
	if not adapter.bind(cache, kernel, inventory, [0, 0, 0, 0, 0, 0]): return _open_fail(str(adapter.error))
	adapter.bind_inventory(Inventory.new())
	renderer = SceneRender.new()
	if not renderer.bind(records): return _open_fail(str(renderer.error))
	executor = Display.new()
	executor.bind_surface(renderer)
	var router := DisplayRouter.new(self)
	adapter.bind_display(router)
	reload = Reload.new()
	if not reload.load_source(package.pal98_sources, package.pal98_graphics): return _open_fail(str(reload.error))
	enter = Enter.new()
	if not enter.load_source(package.pal98_sources): return _open_fail(str(enter.error))
	dialogue_host = DialogueHost.new()
	dialogue_host.bind(package.pal98_sources)
	dialogue_host.bind_page_owner(renderer)
	facing = Facing.new()
	member = MemberSync.new()
	probe = CollisionProbe.new()
	if not member.bind_probe(probe): return _open_fail(str(member.error))
	var role_source: Dictionary = kernel.initial_state([0])
	var roles := self
	member.bind_frame_counts(func(slot: int) -> int:
		var role: int = roles._roles_snapshot[slot] if slot < roles._roles_snapshot.size() else -1
		if role < 0 or role >= 6: return 0
		var field64: int = ((int(role_source.role_words[64 * 6 + role]) + 32768) & 65535) - 32768
		return 4 if field64 == 4 else 3)
	facing.bind_member_sync(member)
	facing.bind_fallback(router)
	adapter.bind_movement(facing)
	input = InputFrame.new()
	_palette = Palette.new()
	error = ""; return true

func _open_fail(message: String) -> bool:
	_failure(message); return false

## The source-derived new-game state. `seed` is required: the original
## new-game RNG seed is unobserved, so the host must pass one explicitly.
func new_state(seed: int) -> Dictionary:
	error = ""
	var day: Dictionary = records.palette(0, 0)
	var night: Dictionary = records.palette(0, 1)
	if day.has("error"): return _failure("day palette: " + str(day.error))
	if night.has("error"): return _failure("night palette: " + str(night.error))
	var backing: PackedByteArray = PackedByteArray(); backing.resize(Palette.BUFFER)
	var loaded: Dictionary = _palette.load_day_night(backing, day.value, night.value)
	if loaded.has("error"): return _failure(str(loaded.error))
	var cold: Dictionary = executor.install_cold(day.value)
	if cold.has("error"): return _failure(str(cold.error))
	var inventory: PackedByteArray = PackedByteArray(); inventory.resize(1536)
	var opening := {"current_scene": 0, "requested_scene": 1, "resource_flags": 29,
		"party_x": 160, "party_y": 112, "viewport_x": 0, "viewport_y": 0,
		"world_x": 0, "world_y": 0, "previous_x": 0, "previous_y": 0,
		"previous_viewport_x": 0, "previous_viewport_y": 0,
		"loaded_map_id": 0, "member_last": 0, "follower_count": 0, "battle_mode": 0,
		"midi_track": 0, "battle_music_track": 0, "day_night_word": 0, "fade_gate_word": 0,
		"direction_word": 0, "party_layer_word": 0, "fbp_mode_word": 0,
		"ffxy_max_x": 1696, "ffxy_max_y": 1840,
		"view_offset_x": 0, "view_offset_y": 0, "transition_cadence": 0, "transition_progress": 0,
		"wave_phase": 0, "wave_amplitude": 0, "trigger_success_word": 0}
	state = {"globals": opening,
		"events": storage.source_state(), "rng": Random.create(seed),
		"dialogue": {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44,
			"origin_y": 26, "mode": 1, "line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202,
			"icon": 2, "skip_word": 0, "delay_units": 1, "input_action": 99, "capture_gate": 1,
			"restore_gate": 0, "colours": [79, 45, 26, 141], "timer_counter": 0},
		"equipment": kernel.initial_state([0]),
		"inventory_bytes": inventory,
		"palette_bytes": backing,
		"party_records": [{"role_id": 0, "x": 160, "y": 112, "current_frame": 0}],
		"party_trail": [{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}]}
	_roles_snapshot = [0]
	return state.duplicate(true)

## Runs the real reload/enter chain until it rests on the entry's own next
## scene; a further scene entry stops the intro as awaiting_player instead of
## inventing player input. With `confirm_gated` the intro's dialogue requests
## park instead of auto-advancing: each player confirm (a new press on the
## bound confirm slot, delivered through `tick`) advances one real dialogue
## through the dialogue host and the chain continues to the next page.
func begin(confirm_gated := false) -> Dictionary:
	error = ""; awaiting_player = false; awaiting_confirm = false
	_confirm_gated = confirm_gated
	_pending_dialogue = {}; _active_enter_request = {}
	enters_seen = []
	var step: Dictionary = reload.start(state, cache)
	return _drive_reload(step)

func _drive_reload(step: Dictionary) -> Dictionary:
	for guard in range(32768):
		if step.has("error"): return _failure(str(step.error))
		if step.get("state") is Dictionary:
			state = step.state
			_refresh_roles(); _rebind_probe()
			return {"completed": true, "state": state.duplicate(true), "trace": step.get("trace", []),
				"enters": enters_seen.duplicate(), "awaiting_player": awaiting_player,
				"awaiting_confirm": false}
		if not step.has("request"): return _failure("reload stopped without a terminal state")
		var request: Dictionary = step.request
		match request.kind:
			"render_background":
				var rendered: Dictionary = renderer.render(request.state)
				if rendered.has("error"): return _failure("reload render: " + str(rendered.error))
				step = reload.resume(request.id, {"completed": true, "state": rendered.state})
			"enter_script":
				enters_seen.append(request.scene_id)
				if enters_seen.size() > 2:
					awaiting_player = true
					return _await_player(step, request)
				_active_enter_request = request
				var run: Dictionary = _drive_entry(enter.start(request.state, request.scene_id,
					request.entry, request.event_id))
				if run.has("error"): return _failure("reload enter: " + str(run.error))
				if run.get("parked"):
					return {"completed": false, "awaiting_confirm": true, "advanced": false,
						"state": state.duplicate(true), "enters": enters_seen.duplicate(),
						"pending_effect": str(_pending_dialogue.get("effect", {}).get("kind", ""))}
				step = reload.resume(request.id, {"state": run.state,
					"return_entry": run.get("return_entry", 0)})
			"play_midi":
				var answered: Dictionary = _named(request.kind, request)
				if answered.has("error"): return _failure(str(answered.error))
				step = reload.resume(request.id, {"completed": true})
			"load_save":
				return _failure("a new game must not request a save load")
			_:
				return _failure("the new-game chain does not own: " + str(request.kind))
	return _failure("new-game chain budget exceeded")

func _await_player(step: Dictionary, request: Dictionary) -> Dictionary:
	# The intro has finished; the original now waits for a real player. Answer
	# the pending enter request with the named stop and rest on the last state.
	var rested: Dictionary = reload.resume(request.id,
		{"error": "the intro completes here; further scene entries belong to the player"})
	state = step.request.state if step.request.get("state") is Dictionary else state
	_refresh_roles(); _rebind_probe()
	return {"completed": true, "state": state.duplicate(true), "awaiting_player": true,
		"enters": enters_seen.duplicate(), "stopped_request": request.kind}

## One player input tick on the resting state through the production input
## frame; the collision probe rebinds to the current map and events first. A
## confirm press on the bound slot advances a parked intro dialogue through
## the real dialogue host — the production input tick is the only path.
func tick(key_levels) -> Dictionary:
	_rebind_probe()
	var ticked: Dictionary = input.tick(state, key_levels)
	if ticked.has("error"): return _failure(str(ticked.error))
	state = ticked.state
	var out: Dictionary = ticked
	if ticked.get("confirm", false) and awaiting_confirm:
		var advanced: Dictionary = _confirm_advance()
		if advanced.has("error"): return _failure(str(advanced.error))
		out["confirm_advanced"] = true
		out["state"] = state
	out["awaiting_confirm"] = awaiting_confirm
	return out

func _confirm_advance() -> Dictionary:
	var pending: Dictionary = _pending_dialogue
	_pending_dialogue = {}; awaiting_confirm = false
	var event: Dictionary = dialogue_host.answer(pending.effect)
	if event.has("error"): return _failure("dialogue host: " + str(event.error))
	var result: Dictionary = enter.resume(pending.id, {"event": event})
	var run: Dictionary = _drive_entry(result)
	if run.has("error"): return _failure(str(run.error))
	if run.get("parked"):
		return {"completed": true, "awaiting_confirm": true}
	var step: Dictionary = reload.resume(_active_enter_request.id,
		{"state": run.state, "return_entry": run.get("return_entry", 0)})
	var done: Dictionary = _drive_reload(step)
	return done

func _drive_entry(result: Dictionary) -> Dictionary:
	for guard in range(16384):
		if result.has("error"): return {"error": str(result.error)}
		if not result.has("request"):
			terminals.append(result)
			return {"state": result.state, "return_entry": result.get("return_entry", 0)}
		var pending: Dictionary = result.request
		if pending.kind == "dialogue":
			if _confirm_gated and pending.get("effect", {}).get("kind") == "draw_string":
				# Park: the page advances only on a player confirm through tick.
				# The gate sits on the page-text draw; the capture/restore/box/
				# glyph sub-effects and the waits are not player pages. Gating
				# the page on its text draw is a named Native reading — the
				# original confirm gate point is not decoded.
				_pending_dialogue = pending
				awaiting_confirm = true
				return {"parked": true}
			var event: Dictionary = dialogue_host.answer(pending.effect)
			if event.has("error"): return {"error": "dialogue host: " + str(event.error)}
			result = enter.resume(pending.id, {"event": event})
		elif pending.has("original_entry"):
			var answer: Dictionary = adapter.answer(pending)
			if answer.has("error"): return {"error": "enter host: " + str(answer.error)}
			result = enter.resume(pending.id, answer)
		elif pending.kind == "yes_no" or pending.kind == "battle":
			var decided: Dictionary = _named(pending.kind, pending)
			if decided.has("error"): return {"error": str(decided.error)}
			result = enter.resume(pending.id, decided)
		elif pending.has("state"):
			result = enter.resume(pending.id, {"state": pending.state, "completed": true})
		else:
			var other: Dictionary = _named(pending.kind, pending)
			if other.has("error"): return {"error": str(other.error)}
			result = enter.resume(pending.id, other)
	return {"error": "entry driver budget exceeded"}

func _named(kind: String, request: Dictionary) -> Dictionary:
	if _doubles.has(kind): return _doubles[kind].answer(request)
	if _doubles.has("*"): return _doubles["*"].answer(request)
	return {"error": "no execution owner bound for " + kind}

func _route_display(request: Dictionary) -> Dictionary:
	var kind: String = request.kind
	if kind in ["apply_palette", "fade_wait", "fade_event_pump", "fade_frame"]:
		return executor.answer(request)
	match kind:
		"capture_dialog_background":
			var captured: Dictionary = renderer.capture_page()
			if captured.has("error"): return captured
			var cap: Dictionary = {"completed": true, "capture": captured.receipt}
			if request.get("state") is Dictionary: cap.state = request.state.duplicate(true)
			return cap
		"restore_dialog_background":
			var restored: Dictionary = renderer.restore_dialog_background()
			if restored.has("error"):
				# The initial G00C0 page is not proved yet; the host may isolate
				# exactly that named refusal. Everything else propagates.
				if str(restored.error).contains("requires the captured-page owner") and _doubles.has("restore_dialog_background_without_initial_page"):
					return _doubles["restore_dialog_background_without_initial_page"].answer(request)
				return restored
			var res: Dictionary = {"completed": true, "restore": restored.receipt}
			if request.get("state") is Dictionary: res.state = request.state.duplicate(true)
			return res
		"render_current_map_background":
			var rendered: Dictionary = renderer.render(request.get("state", {}))
			if rendered.has("error"): return rendered
			var answer: Dictionary = {"completed": true, "render": rendered.receipt}
			if request.get("state") is Dictionary: answer.state = rendered.state
			return answer
	if _doubles.has(kind):
		return _doubles[kind].answer(request)
	if _doubles.has("*"):
		return _doubles["*"].answer(request)
	return {"error": "no execution owner bound for " + kind}

func _refresh_roles() -> void:
	_roles_snapshot = []
	for row in state.get("party_records", []):
		_roles_snapshot.append(int(row.role_id) if row.get("role_id") is int else -1)

func _rebind_probe() -> void:
	var map_id = state.get("globals", {}).get("loaded_map_id")
	if not map_id is int or map_id <= 0: return
	var map: Dictionary = records.decoded_chunk("MAP.MKF", map_id)
	if map.has("error"): return
	probe.bind(map.value, state.get("events", {}))
