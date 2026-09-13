# SPDX-License-Identifier: MIT
extends RefCounted
## Internal new-game coordinator. Initializer and device presentation remain
## explicit dependencies; a probe configuration does not open ordinary Session.
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
const OpeningInit = preload("res://src/native_pal98_opening_init.gd")

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
var map_cache: Dictionary = {}
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
var _pending_dialogue: Dictionary = {}
var _active_enter_request: Dictionary = {}
var _palette = Palette.new()
var _doubles: Dictionary = {}
var _initial_cache
var _start_state: Dictionary = {}
var _start_cache
var _start_map: Dictionary = {}
var _initialized := false
var _running := false

class DisplayRouter:
	var game
	func _init(owner) -> void: game = weakref(owner)
	func answer(request: Dictionary) -> Dictionary:
		var owner = game.get_ref()
		return owner._route_display(request) if owner != null else {"error": "new-game host released"}

## Cancellation invalidates both continuation generations and captured pages.
## It does not manufacture a terminal result or erase the caller's diagnostic.
func cancel() -> void:
	if reload != null: reload.cancel()
	if enter != null: enter.cancel()
	_pending_dialogue = {}; _active_enter_request = {}
	awaiting_confirm = false; awaiting_player = false; _running = false
	terminals = []; enters_seen = []
	if renderer != null and records != null: renderer.bind(records)

func _failure(message: String) -> Dictionary:
	var diagnostic := {"enters": enters_seen.duplicate(), "pending": _pending_dialogue.duplicate(true)}
	cancel()
	if not _start_state.is_empty():
		state = _start_state.duplicate(true); cache = _start_cache; map_cache = _start_map.duplicate(true)
	error = "pal98-new-game: " + message
	return {"error": error, "diagnostic": diagnostic}

func bind_named_double(kind: String, owner) -> bool:
	if kind.is_empty() or kind == "*" or owner == null or not owner.has_method("answer"):
		error = "pal98-new-game: an explicit named owner is required (no wildcard)"; return false
	_doubles[kind] = owner; error = ""; return true

func bind_clock(clock) -> bool: return executor.bind_clock(clock)
func bind_runtime(runtime) -> bool: return executor.bind_runtime(runtime)

func bind_key_map(logical_map: Array, layer_base: int, confirm_slot: int = -1) -> bool:
	if input == null:
		error = "pal98-new-game: input owner not assembled"; return false
	var bound: bool = input.bind(facing, probe, logical_map, layer_base, confirm_slot)
	if not bound: error = input.error
	return bound

func open(package) -> bool:
	cancel(); state = {}; map_cache = {}; _start_state = {}; _initialized = false
	if package == null or package.pal98_sources == null or package.pal98_graphics == null:
		return _open_fail("admitted package sources and graphics required")
	records = package.pal98_graphics.open_records()
	if records == null: return _open_fail("graphics records unavailable")
	storage = Events.new()
	if not storage.load_source(package.pal98_sources): return _open_fail(storage.error)
	cache = Cache.new()
	if not cache.load_source(package.pal98_graphics, package.pal98_sources): return _open_fail(cache.error)
	_initial_cache = cache
	kernel = Equipment.new()
	if not kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
			package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4)):
		return _open_fail(kernel.error)
	renderer = SceneRender.new()
	if not renderer.bind(records): return _open_fail(renderer.error)
	executor = Display.new()
	if not executor.bind_surface(renderer): return _open_fail(executor.error)
	adapter = EntryHost.new()
	adapter.bind_inventory(Inventory.new())
	adapter.bind_display(DisplayRouter.new(self))
	reload = Reload.new()
	if not reload.load_source(package.pal98_sources, package.pal98_graphics): return _open_fail(reload.error)
	enter = Enter.new()
	if not enter.load_source(package.pal98_sources): return _open_fail(enter.error)
	dialogue_host = DialogueHost.new()
	if not dialogue_host.bind(package.pal98_sources): return _open_fail(dialogue_host.error)
	if not dialogue_host.bind_page_owner(renderer): return _open_fail(dialogue_host.error)
	facing = Facing.new(); member = MemberSync.new(); probe = CollisionProbe.new()
	if not member.bind_probe(probe): return _open_fail(member.error)
	facing.bind_member_sync(member); facing.bind_fallback(DisplayRouter.new(self))
	adapter.bind_movement(facing)
	input = InputFrame.new()
	if not input.bind_events(storage): return _open_fail(input.error)
	error = ""; return true

func _open_fail(message: String) -> bool:
	_failure(message); _initialized = false; return false

## The probe path: globals/dialogue/trail/inventory are REQUIRED explicit
## probe inputs. Source tables, palette and seed arithmetic are real. The
## source-derived path is new_state_from_source.
func new_state(seed: int, probe_configuration: Dictionary = {}) -> Dictionary:
	if records == null or _initial_cache == null: return _failure("open the package first")
	for key in ["globals", "dialogue"]:
		if not probe_configuration.get(key) is Dictionary: return _failure("explicit probe configuration requires " + key)
	for key in ["roles", "party_records", "party_trail"]:
		if not probe_configuration.get(key) is Array: return _failure("explicit probe configuration requires " + key)
	if not probe_configuration.get("inventory_bytes") is PackedByteArray:
		return _failure("explicit probe inventory required")
	var candidate: Dictionary = probe_configuration.duplicate(true)
	candidate.equipment = kernel.initial_state(candidate.roles)
	candidate.erase("roles")
	if candidate.equipment.has("error"): return _failure(str(candidate.equipment.error))
	candidate.events = storage.source_state(); candidate.rng = Random.create(seed)
	if candidate.rng.has("error"): return _failure(str(candidate.rng.error))
	return _publish(candidate)

## The source-derived opening. Base levels come from the admitted DATA3
## backing and SubMain's 70-call experience projection runs on the seed.
## Seed kinds: "explicit_replay" takes a known DWORD; "startup_capture"
## samples the host wall clock once, exactly as the fixed VB startup does.
## The still-unverified opening words (globals, dialogue, trail, inventory)
## remain REQUIRED explicit inputs and are never renamed as recovered values.
func new_state_from_source(seed, seed_kind: String, unverified: Dictionary) -> Dictionary:
	if records == null or _initial_cache == null: return _failure("open the package first")
	if seed_kind != "explicit_replay" and seed_kind != "startup_capture":
		return _failure("seed kind must be explicit_replay or startup_capture")
	for key in ["globals", "dialogue"]:
		if not unverified.get(key) is Dictionary: return _failure("unverified opening input requires " + key)
	for key in ["party_trail"]:
		if not unverified.get(key) is Array: return _failure("unverified opening input requires " + key)
	if not unverified.get("inventory_bytes") is PackedByteArray:
		return _failure("unverified opening inventory required")
	var roles: Array = [0]
	var equipment: Dictionary = kernel.initial_state(roles)
	if equipment.is_empty() or not (equipment.get("role_words") is Array):
		return _failure("source role backing unavailable for the opening party")
	var candidate: Dictionary = {
		"globals": unverified.globals.duplicate(true),
		"dialogue": unverified.dialogue.duplicate(true),
		"party_trail": unverified.party_trail.duplicate(true),
		"inventory_bytes": unverified.inventory_bytes.duplicate(),
		"party_records": [], "events": storage.source_state(),
		"equipment": equipment}
	var rng: Dictionary; var receipt_seed: Dictionary
	if seed_kind == "explicit_replay":
		rng = Random.create(seed)
		if rng.has("error"): return _failure(str(rng.error))
		receipt_seed = {"kind": "explicit_replay", "seed": seed}
	else:
		var captured: Dictionary = Random.capture_startup()
		if captured.has("error"): return _failure("startup seed capture: " + str(captured.error))
		rng = captured.state
		receipt_seed = {"kind": "startup_capture", "clock_sample": captured.clock_sample,
			"timer_single": captured.timer_single, "seed": captured.state.live_seed}
	var opening: Dictionary = OpeningInit.derive(candidate.equipment.role_words, rng, receipt_seed)
	if opening.has("error"): return _failure("opening init: " + str(opening.error))
	candidate.experience = opening.experience
	candidate.rng = opening.rng
	candidate.rng_source = opening.receipt
	candidate.rng_source.data3_sha256 = kernel.source_receipt().get("data3_sha256")
	# The opening party is role 0 at the original party-in-viewport anchor;
	# the same carried opening-chain facts the probe configuration pinned.
	candidate.party_records = [{"role_id": 0,
		"x": int(candidate.globals.get("party_x", 160)),
		"y": int(candidate.globals.get("party_y", 112)), "current_frame": 0}]
	return _publish(candidate)

## Shared publication tail: source palettes, cold display install, sprite
## fork and the initialized hand-off state.
func _publish(candidate: Dictionary) -> Dictionary:
	var day: Dictionary = records.palette(0, 0); var night: Dictionary = records.palette(0, 1)
	if day.has("error") or night.has("error"): return _failure("source day/night palette unavailable")
	var backing := PackedByteArray(); backing.resize(Palette.BUFFER)
	var loaded: Dictionary = _palette.load_day_night(backing, day.value, night.value)
	if loaded.has("error"): return _failure(str(loaded.error))
	candidate.palette_bytes = backing
	cancel(); _start_state = {}
	var installed: Dictionary = executor.install_cold(day.value)
	if installed.has("error"): return _failure(str(installed.error))
	cache = _initial_cache.fork_for_reload(); map_cache = {}
	if cache == null: return _failure("initial sprite fork unavailable")
	state = candidate; _initialized = true; error = ""
	return state.duplicate(true)

func begin() -> Dictionary:
	if not _initialized: return _failure("explicit initial state required")
	if _running: return {"error": "pal98-new-game: owner already active"}
	cancel()
	var installed: Dictionary = executor.install_cold(executor.installed_rgb6())
	if installed.has("error"): return _failure(str(installed.error))
	_start_state = state.duplicate(true); _start_cache = cache; _start_map = map_cache.duplicate(true)
	error = ""; _running = true
	return _drive_reload(reload.start(state, cache, map_cache))

## Adopt a state/cache/map lease as one binding. Validation precedes publication.
func _adopt(candidate: Dictionary, sprites, maps: Dictionary) -> Dictionary:
	if sprites == null or sprites.source() != _initial_cache.source(): return _failure("cache source identity mismatch")
	var issue: String = storage.validate_state(candidate.get("events", {}))
	if not issue.is_empty(): return _failure(issue)
	issue = kernel.validate_state(candidate.get("equipment", {}))
	if not issue.is_empty(): return _failure(issue)
	var map_id = candidate.get("globals", {}).get("loaded_map_id")
	if typeof(map_id) != TYPE_INT or map_id < 0 or maps.get("map_id") != map_id:
		return _failure("state and MAP cache identity mismatch")
	if maps.get("graphics_fingerprint") != sprites.source().get("graphics_fingerprint"):
		return _failure("MAP cache graphics identity mismatch")
	if not maps.get("map_bytes") is PackedByteArray or not maps.get("gop_bytes") is PackedByteArray or maps.gop_bytes.size() < 2:
		return _failure("MAP/GOP cache backing missing")
	var check_probe = CollisionProbe.new()
	if not check_probe.bind(maps.map_bytes, candidate.events): return _failure(check_probe.error)
	var ids: Array = []
	for role in range(6): ids.append(candidate.equipment.role_words[2 * 6 + role])
	if not candidate.get("inventory_bytes") is PackedByteArray: return _failure("inventory backing unavailable")
	if not adapter.bind(sprites, kernel, candidate.inventory_bytes, ids): return _failure(adapter.error)
	# Same stable probe instance is bound by both the input and member owners.
	if not probe.bind(maps.map_bytes, candidate.events): return _failure(probe.error)
	state = candidate.duplicate(true); cache = sprites; map_cache = maps.duplicate(true)
	return {"completed": true}

func _drive_reload(step: Dictionary) -> Dictionary:
	for guard in range(32768):
		if step.has("error"): return _failure(str(step.error))
		if step.get("state") is Dictionary:
			var adopted: Dictionary = _adopt(step.state, step.get("cache"), step.get("map_cache", {}))
			if adopted.has("error"): return adopted
			awaiting_player = true; _running = false
			return {"completed": true, "state": state.duplicate(true), "trace": step.get("trace", []),
				"enters": enters_seen.duplicate(), "awaiting_player": true, "awaiting_confirm": false}
		if not step.has("request"): return _failure("reload stopped without terminal state")
		var request: Dictionary = step.request
		match request.kind:
			"render_background":
				var rendered: Dictionary = renderer.render(request.state)
				if rendered.has("error"): return _failure("reload render: " + str(rendered.error))
				step = reload.resume(request.id, {"completed": true, "state": rendered.state})
			"enter_script":
				var adopted: Dictionary = _adopt(request.state, request.get("cache"), request.get("map_cache", {}))
				if adopted.has("error"): return adopted
				enters_seen.append(request.scene_id); _active_enter_request = request
				var run: Dictionary = _drive_entry(enter.start(request.state, request.scene_id, request.entry, request.event_id))
				if run.has("error"): return _failure(str(run.error))
				if run.get("parked"): return _parked()
				step = reload.resume(request.id, {"state": run.state, "return_entry": run.get("return_entry", 0)})
			"play_midi":
				var answer: Dictionary = _named(request.kind, request)
				if answer.has("error"): return _failure(str(answer.error))
				step = reload.resume(request.id, answer)
			_:
				return _failure("unowned reload request: " + str(request.kind))
	return _failure("reload coordination budget exceeded")

func _parked() -> Dictionary:
	return {"completed": false, "awaiting_confirm": awaiting_confirm, "awaiting_effect": true,
		"state": state.duplicate(true), "enters": enters_seen.duplicate(), "input_move": false,
		"pending_effect": _pending_dialogue.get("effect", {}).duplicate(true),
		"pending_id": _pending_dialogue.get("id", "")}

## timer_tick is one explicit nominal timer event from the caller. A function
## call is not elapsed time. Each invocation consumes at most ONE input or
## timer event, so one press cannot release several subsequent waits.
func tick(key_levels, timer_tick: bool = false) -> Dictionary:
	var polled: Dictionary = input.poll(key_levels)
	if polled.has("error"): return _failure(str(polled.error))
	if not _pending_dialogue.is_empty():
		var effect: Dictionary = _pending_dialogue.effect
		if effect.kind == "wait" and not timer_tick: return _parked()
		var event: Dictionary = {"kind": "tick"} if effect.kind == "wait" else {"kind": "input", "action": 2 if polled.confirm else 0}
		return resume_dialogue(_pending_dialogue.id, event)
	if not awaiting_player: return _failure("no resting map or dialogue request")
	var rebound: Dictionary = _adopt(state, cache, map_cache)
	if rebound.has("error"): return rebound
	var ticked: Dictionary = input.tick(state, key_levels)
	if ticked.has("error"): return _failure(str(ticked.error))
	state = ticked.state
	return ticked

## Internal explicit-host continuation. Stale receipts cannot cancel or write
## a newer pending generation. Non-dialogue commands never receive generic ACKs.
func resume_dialogue(request_id: String, event: Dictionary) -> Dictionary:
	if _pending_dialogue.is_empty() or request_id != _pending_dialogue.id:
		return {"error": "pal98-new-game: stale dialogue completion"}
	var pending: Dictionary = _pending_dialogue
	_pending_dialogue = {}; awaiting_confirm = false
	var run: Dictionary = _drive_entry(enter.resume(pending.id, {"event": event}))
	if run.has("error"): return _failure(str(run.error))
	if run.get("parked"): return _parked()
	return _drive_reload(reload.resume(_active_enter_request.id,
		{"state": run.state, "return_entry": run.get("return_entry", 0)}))

func _drive_entry(result: Dictionary) -> Dictionary:
	for guard in range(16384):
		if result.has("error"): return result
		if not result.has("request"):
			if not result.get("state") is Dictionary: return {"error": "entry terminal lacks state"}
			terminals.append(result.duplicate(true))
			return {"state": result.state, "return_entry": result.get("return_entry", 0)}
		var pending: Dictionary = result.request
		if pending.kind == "dialogue":
			if pending.get("effect", {}).get("kind") in ["poll_input", "wait"]:
				var adopted: Dictionary = _adopt(pending.state, cache, map_cache)
				if adopted.has("error"): return adopted
				_pending_dialogue = pending.duplicate(true)
				awaiting_confirm = pending.effect.kind == "poll_input" and pending.effect.get("model") == "until_nonzero"
				return {"parked": true}
			var event: Dictionary = dialogue_host.answer(pending.effect)
			if event.has("error"): return {"error": "dialogue host: " + str(event.error)}
			result = enter.resume(pending.id, {"event": event})
		elif pending.has("original_entry"):
			# Scene/event state may have changed since the last wait.
			var rebound: Dictionary = _adopt(pending.state, cache, map_cache)
			if rebound.has("error"): return rebound
			var answer: Dictionary = adapter.answer(pending)
			if answer.has("error"): return {"error": "enter host: " + str(answer.error)}
			result = enter.resume(pending.id, answer)
		elif pending.kind == "restore_background":
			var page_request: Dictionary = pending.duplicate(true); page_request.kind = "restore_dialog_background"
			var answer: Dictionary = _route_display(page_request)
			if answer.has("error"): return answer
			result = enter.resume(pending.id, answer)
		else:
			var answer: Dictionary = _named(pending.kind, pending)
			if answer.has("error"): return answer
			result = enter.resume(pending.id, answer)
	return {"error": "entry coordination budget exceeded"}

func _named(kind: String, request: Dictionary) -> Dictionary:
	if _doubles.has(kind): return _doubles[kind].answer(request)
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
	return {"error": "no execution owner bound for " + kind}
