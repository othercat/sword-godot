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
var _pending_transition: Dictionary = {}
var _active_enter_request: Dictionary = {}
var _page_requests: Array = []
var _sources
var _graphics
var _frames: Array = []
var _coordination_steps: int = 0
var _generation: int = 0
var page_revision: int = 0
var _captured_page_requests: Array = []
var _presentation_required := true
var nested_traces: Array = []

const MAX_COORDINATION_DEPTH := 64
const MAX_COORDINATION_STEPS := 65536
const PRESENTATION_KINDS := ["draw_string", "draw_glyph", "capture_background",
	"restore_background", "draw_dialogue_icon", "draw_dialogue_box"]
var _palette = Palette.new()
var _doubles: Dictionary = {}
var _initial_cache
var _start_state: Dictionary = {}
var _start_cache
var _start_map: Dictionary = {}
var _start_resting := false
var _start_render: Dictionary = {}
var _start_palette := PackedByteArray()
var _start_pages: Array = []
var _start_captured: Array = []
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
	for frame in _frames:
		if frame.reload != reload: frame.reload.cancel()
		if frame.enter != enter: frame.enter.cancel()
	if reload != null: reload.cancel()
	if enter != null: enter.cancel()
	_frames = []; _coordination_steps = 0; _generation += 1; page_revision += 1
	_pending_dialogue = {}; _active_enter_request = {}; _page_requests = []; _captured_page_requests = []
	if not _pending_transition.is_empty() and _pending_transition.get("owner") != null:
		_pending_transition.owner.cancel()
	_pending_transition = {}
	nested_traces = []
	awaiting_confirm = false; awaiting_player = false; _running = false
	terminals = []; enters_seen = []
	if renderer != null and records != null: renderer.bind(records)

## The parked page's raw draw requests, recorded exactly as the dialogue host
## answered them. They exist so the display adapter can publish the same page
## the chain produced; they are not a glyph policy.
func pending_page_requests() -> Array:
	return _page_requests.duplicate(true)

func is_dialogue_parked() -> bool:
	return not _pending_dialogue.is_empty()

func pending_kind() -> String:
	if _pending_dialogue.is_empty(): return ""
	return String(_pending_dialogue.get("effect", {}).get("kind", ""))

func pending_model() -> String:
	if _pending_dialogue.is_empty(): return ""
	return String(_pending_dialogue.get("effect", {}).get("model", ""))

func _checkpoint(resting: bool) -> void:
	_start_state = state.duplicate(true); _start_cache = cache; _start_map = map_cache.duplicate(true)
	_start_resting = resting; _start_render = renderer.checkpoint()
	_start_palette = executor.installed_rgb6()
	_start_pages = _page_requests.duplicate(true); _start_captured = _captured_page_requests.duplicate(true)

func _failure(message: String) -> Dictionary:
	var diagnostic := {"enters": enters_seen.duplicate(), "pending": _pending_dialogue.duplicate(true)}
	cancel()
	if not _start_state.is_empty():
		state = _start_state.duplicate(true); cache = _start_cache; map_cache = _start_map.duplicate(true)
		if _start_resting:
			var rebound := _bind_lease(state, cache, map_cache)
			var page: Dictionary = renderer.restore_checkpoint(_start_render)
			var installed: Dictionary = executor.install_cold(_start_palette)
			if rebound.is_empty() and not page.has("error") and not installed.has("error"):
				awaiting_player = true
				_page_requests = _start_pages.duplicate(true); _captured_page_requests = _start_captured.duplicate(true)
			else:
				diagnostic.rollback = {"lease": rebound, "page": page.get("error"), "palette": installed.get("error")}
	error = "pal98-new-game: " + message
	return {"error": error, "diagnostic": diagnostic}

func bind_named_double(kind: String, owner) -> bool:
	if kind.is_empty() or kind == "*" or owner == null or not owner.has_method("answer"):
		error = "pal98-new-game: an explicit named owner is required (no wildcard)"; return false
	_doubles[kind] = owner; error = ""; return true

## One logical clock drives both the palette fade waits and the T121 phase
## waits; the transition refuses to run without it.
func bind_clock(clock) -> bool:
	var fade: bool = executor.bind_clock(clock)
	var transition: bool = renderer.bind_transition_clock(clock)
	if not fade or not transition:
		error = "clock binding failed: fade=%s transition=%s" % [str(fade), str(transition)]
		return false
	return true
func bind_runtime(runtime) -> bool: return executor.bind_runtime(runtime)

func bind_key_map(logical_map: Array, layer_base: int, confirm_slot: int = -1) -> bool:
	if input == null:
		error = "pal98-new-game: input owner not assembled"; return false
	var bound: bool = input.bind(facing, probe, logical_map, layer_base, confirm_slot)
	if not bound: error = input.error
	return bound

func open(package) -> bool:
	cancel(); state = {}; map_cache = {}; _start_state = {}; _start_resting = false; _initialized = false
	if package == null or package.pal98_sources == null or package.pal98_graphics == null:
		return _open_fail("admitted package sources and graphics required")
	_sources = package.pal98_sources; _graphics = package.pal98_graphics
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
## T156 proves clearing InUse at the reload tail, not zero ItemId/Amount
## at cold start. Inventory, globals, dialogue and trail therefore remain
## explicit unverified inputs; only DATA3/experience/seed facts are derived.
func new_state_from_source(seed, seed_kind: String, unverified: Dictionary) -> Dictionary:
	if records == null or _initial_cache == null: return _failure("open the package first")
	if seed_kind != "explicit_replay" and seed_kind != "startup_capture":
		return _failure("seed kind must be explicit_replay or startup_capture")
	for key in ["globals", "dialogue"]:
		if not unverified.get(key) is Dictionary: return _failure("unverified opening input requires " + key)
	for key in ["party_trail"]:
		if not unverified.get(key) is Array: return _failure("unverified opening input requires " + key)
	var explicit_inventory = unverified.get("inventory_bytes")
	if not explicit_inventory is PackedByteArray or explicit_inventory.size() != Inventory.SLOTS * Inventory.RECORD_BYTES:
		return _failure("unverified opening inventory requires 1536 bytes (256 six-byte records)")
	var inventory: PackedByteArray = explicit_inventory.duplicate()
	var roles: Array = [0]
	var equipment: Dictionary = kernel.initial_state(roles)
	if equipment.is_empty() or not (equipment.get("role_words") is Array):
		return _failure("source role backing unavailable for the opening party")
	var candidate: Dictionary = {
		"globals": unverified.globals.duplicate(true),
		"dialogue": unverified.dialogue.duplicate(true),
		"party_trail": unverified.party_trail.duplicate(true),
		"inventory_bytes": inventory,
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
	cancel(); _start_state = {}; _start_resting = false
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
	_checkpoint(false)
	error = ""; _running = true
	return _drive_reload(reload.start(state, cache, map_cache))

## RunTriggerScript's production call shape: run one loaded event's trigger
## script (its +8 WORD entry) with the event slot as context, on the current
## resource lease. Nested T212 requests from the script reuse the same frame
## machinery as the entry chain. The T218 contact gate that fires this call
## in the original frame loop is a separate named gap, not part of this call.
func begin_event_trigger(event_id) -> Dictionary:
	# A refused invocation has not acquired the owner. Preserve its live frame.
	if not _initialized: return {"error": "pal98-new-game: explicit initial state required"}
	if _running or not awaiting_player or not _pending_dialogue.is_empty():
		return {"error": "pal98-new-game: event trigger requires the resting map"}
	if typeof(event_id) != TYPE_INT or event_id < 1 or event_id > Events.CAPACITY:
		return {"error": "pal98-new-game: trigger event requires a WORD in the owned 1..160 slots"}
	var record: Dictionary = storage.event_record(state.events, event_id)
	if record.has("error"): return {"error": "pal98-new-game: " + str(record.error)}
	var entry: int = record.value.decode_u16(8)
	if entry == 0: return {"error": "pal98-new-game: event %d carries no trigger script entry" % event_id}
	if state.events.loaded_scene_id != state.globals.get("current_scene"):
		return {"error": "pal98-new-game: trigger requires the current loaded event backing"}
	_checkpoint(true)
	var rebound: Dictionary = _adopt(state, cache, map_cache)
	if rebound.has("error"): return rebound
	_generation += 1; _coordination_steps = 0
	enters_seen = []; terminals = []; nested_traces = []
	_running = true; awaiting_player = false; error = ""
	var request: Dictionary = {"kind": "event_trigger", "state": state.duplicate(true),
		"cache": cache, "map_cache": map_cache.duplicate(true),
		"scene_id": state.globals.current_scene, "entry": entry, "event_id": event_id}
	_active_enter_request = request
	_frames = [{"reload": reload, "enter": enter, "phase": "enter",
		"step": enter.start_event(state, request.scene_id, entry, event_id),
		"active_enter": request, "child_request": {}, "trigger_only": true}]
	return _drive()

## Adopt a state/cache/map lease as one binding. Validation precedes publication.
func _adopt(candidate: Dictionary, sprites, maps: Dictionary) -> Dictionary:
	var issue := _bind_lease(candidate, sprites, maps)
	return _failure(issue) if not issue.is_empty() else {"completed": true}

## Also used for rollback; never recursively enters the failure path.
func _bind_lease(candidate: Dictionary, sprites, maps: Dictionary) -> String:
	if sprites == null or sprites.source() != _initial_cache.source(): return ("cache source identity mismatch")
	var issue: String = storage.validate_state(candidate.get("events", {}))
	if not issue.is_empty(): return (issue)
	issue = kernel.validate_state(candidate.get("equipment", {}))
	if not issue.is_empty(): return (issue)
	var map_id = candidate.get("globals", {}).get("loaded_map_id")
	if typeof(map_id) != TYPE_INT or map_id < 0 or maps.get("map_id") != map_id:
		return ("state and MAP cache identity mismatch")
	if maps.get("graphics_fingerprint") != sprites.source().get("graphics_fingerprint"):
		return ("MAP cache graphics identity mismatch")
	if not maps.get("map_bytes") is PackedByteArray or not maps.get("gop_bytes") is PackedByteArray or maps.gop_bytes.size() < 2:
		return ("MAP/GOP cache backing missing")
	var check_probe = CollisionProbe.new()
	if not check_probe.bind(maps.map_bytes, candidate.events): return (check_probe.error)
	var ids: Array = []
	for role in range(6): ids.append(candidate.equipment.role_words[2 * 6 + role])
	if not candidate.get("inventory_bytes") is PackedByteArray: return ("inventory backing unavailable")
	if not adapter.bind(sprites, kernel, candidate.inventory_bytes, ids): return (adapter.error)
	# Same stable probe instance is bound by both the input and member owners.
	if not probe.bind(maps.map_bytes, candidate.events): return (probe.error)
	state = candidate.duplicate(true); cache = sprites; map_cache = maps.duplicate(true)
	return ""

## Each suspended T212 owns its reload, EnterScript and continuation. A child
## returns the current resource lease together, before its parent resumes.
func _drive_reload(step: Dictionary) -> Dictionary:
	_frames = [{"reload": reload, "enter": enter, "phase": "reload", "step": step,
		"active_enter": {}, "child_request": {}}]
	return _drive()

func _push_nested(request: Dictionary) -> Dictionary:
	if _frames.size() >= MAX_COORDINATION_DEPTH:
		return _failure("nested T212 coordination depth budget exceeded")
	var child_reload = Reload.new(); var child_enter = Enter.new()
	if not child_reload.load_source(_sources, _graphics): return _failure(child_reload.error)
	if not child_enter.load_source(_sources): return _failure(child_enter.error)
	var parent: Dictionary = _frames.back()
	parent.child_request = request.duplicate(true)
	var started: Dictionary = child_reload.start(request.state, cache, map_cache)
	_frames.append({"reload": child_reload, "enter": child_enter, "phase": "reload",
		"step": started, "active_enter": {}, "child_request": {}})
	return {}

func _drive() -> Dictionary:
	while not _frames.is_empty():
		_coordination_steps += 1
		if _coordination_steps > MAX_COORDINATION_STEPS:
			return _failure("T212 coordination step budget exceeded")
		var frame: Dictionary = _frames.back()
		var step: Dictionary = frame.step
		if step.has("error"): return _failure(str(step.error))
		if not step.has("request"):
			if not step.get("state") is Dictionary: return _failure("coordinator terminal lacks state")
			if frame.phase == "enter":
				terminals.append(step.duplicate(true))
				if frame.get("trigger_only", false):
					var trigger_adopt: Dictionary = _adopt(step.state, step.get("cache", cache), step.get("map_cache", map_cache))
					if trigger_adopt.has("error"): return trigger_adopt
					var returned = step.get("return_entry", 0)
					if returned is bool or not returned is int or returned < 0 or returned > 65535:
						return _failure("trigger script must return its ByRef entry WORD")
					var slot: int = frame.active_enter.event_id
					var record: Dictionary = storage.event_record(state.events, slot)
					if record.has("error"): return _failure(str(record.error))
					var updated: PackedByteArray = record.value.duplicate()
					updated.encode_u16(8, returned)
					var written: Dictionary = storage.write_event_record(state.events, slot, updated)
					if written.has("error"): return _failure(str(written.error))
					state.events = written.state
					_frames.pop_back()
					if not _frames.is_empty():
						return _failure("trigger frame lost its root position")
					awaiting_player = true; _running = false
					return {"completed": true, "state": state.duplicate(true),
						"trace": step.get("trace", []), "enters": enters_seen.duplicate(),
						"nested": nested_traces.duplicate(), "awaiting_player": true,
						"awaiting_confirm": false, "trigger_event": slot}
				frame.phase = "reload"
				frame.step = frame.reload.resume(frame.active_enter.id,
					{"state": step.state, "return_entry": step.get("return_entry", 0),
					"cache": cache, "map_cache": map_cache.duplicate(true)})
				continue
			var adopted: Dictionary = _adopt(step.state, step.get("cache"), step.get("map_cache", {}))
			if adopted.has("error"): return adopted
			_frames.pop_back()
			if _frames.is_empty():
				awaiting_player = true; _running = false
				return {"completed": true, "state": state.duplicate(true),
					"trace": step.get("trace", []), "enters": enters_seen.duplicate(),
					"awaiting_player": true, "awaiting_confirm": false}
			nested_traces.append(step.get("trace", []).duplicate())
			var parent: Dictionary = _frames.back()
			_active_enter_request = parent.active_enter
			parent.step = parent.enter.resume(parent.child_request.id,
				{"completed": true, "state": state.duplicate(true)})
			parent.child_request = {}
			continue
		var request: Dictionary = step.request
		if frame.phase == "reload":
			match request.kind:
				"render_background":
					var rendered: Dictionary = renderer.render(request.state)
					if rendered.has("error"): return _failure("reload render: " + str(rendered.error))
					_new_scene_page()
					frame.step = frame.reload.resume(request.id, {"completed": true, "state": rendered.state})
				"enter_script":
					var adopted: Dictionary = _adopt(request.state, request.get("cache"), request.get("map_cache", {}))
					if adopted.has("error"): return adopted
					enters_seen.append(request.scene_id)
					frame.active_enter = request; _active_enter_request = request
					frame.phase = "enter"
					frame.step = frame.enter.start(request.state, request.scene_id, request.entry, request.event_id)
				"play_midi":
					var answer: Dictionary = _named(request.kind, request)
					if answer.has("error"): return _failure(str(answer.error))
					frame.step = frame.reload.resume(request.id, answer)
				_:
					return _failure("unowned reload request: " + str(request.kind))
			continue
		# All script host state comes from the request, never an opening snapshot.
		if request.kind == "load_resources_if_needed":
			var pushed: Dictionary = _push_nested(request)
			if pushed.has("error"): return pushed
			continue
		if request.kind == "dialogue":
			var effect: Dictionary = request.get("effect", {})
			if effect.get("kind") in ["poll_input", "wait"]:
				return _park_request(request, effect, "event")
			if _presentation_required and effect.get("kind") in PRESENTATION_KINDS:
				return _park_request(request, effect, "presentation_event")
			var event: Dictionary = dialogue_host.answer(effect)
			if event.has("error"): return _failure("dialogue host: " + str(event.error))
			_record_page(effect)
			frame.step = frame.enter.resume(request.id, {"event": event})
			continue
		if _presentation_required and request.kind in ["capture_dialog_background", "restore_dialog_background", "restore_background"]:
			var effect := {"kind": "capture_background" if request.kind == "capture_dialog_background" else "restore_background"}
			return _park_request(request, effect, "presentation_owner")
		if request.has("original_entry"):
			var adopted: Dictionary = _adopt(request.state, cache, map_cache)
			if adopted.has("error"): return adopted
			var answer: Dictionary = adapter.answer(request)
			if answer.has("error"): return _failure("enter host: " + str(answer.error))
			if answer.get("parked_transition", false):
				# T121 parks here: the display owner presents every phase
				# before finish_transition releases this waiter.
				return {"awaiting_transition": true, "id": request.id,
					"pending_kind": "clear_effective_cross_fade"}
			frame.step = frame.enter.resume(request.id, answer)
		elif request.kind == "restore_background":
			var page_request: Dictionary = request.duplicate(true)
			page_request.kind = "restore_dialog_background"
			var answer: Dictionary = _route_display(page_request)
			if answer.has("error"): return _failure(str(answer.error))
			_record_page({"kind": "restore_background"})
			frame.step = frame.enter.resume(request.id, answer)
		elif request.kind == "render_scene":
			var scene_answer: Dictionary = _route_display(request)
			if scene_answer.has("error"): return _failure(str(scene_answer.error))
			frame.step = frame.enter.resume(request.id, scene_answer)
		else:
			var answer: Dictionary = _named(request.kind, request)
			if answer.has("error"): return _failure(str(answer.error))
			frame.step = frame.enter.resume(request.id, answer)
	return _failure("coordinator has no active frame")

func _new_scene_page() -> void:
	page_revision += 1
	_page_requests = []

func _record_page(effect: Dictionary) -> void:
	match effect.get("kind"):
		"draw_string", "draw_glyph":
			_page_requests.append(effect.duplicate(true))
		"capture_background":
			_captured_page_requests = _page_requests.duplicate(true)
		"restore_background":
			_page_requests = _captured_page_requests.duplicate(true)

func _park_request(request: Dictionary, effect: Dictionary, transport: String) -> Dictionary:
	var adopted: Dictionary = _adopt(request.state, cache, map_cache)
	if adopted.has("error"): return adopted
	_pending_dialogue = request.duplicate(true)
	_pending_dialogue.inner_id = request.id
	_pending_dialogue.id = str(_generation) + ":" + request.id
	_pending_dialogue.effect = effect.duplicate(true)
	_pending_dialogue.transport = transport
	awaiting_confirm = effect.get("kind") == "poll_input" and effect.get("model") == "until_nonzero"
	return _parked()

func _parked() -> Dictionary:
	return {"completed": false, "awaiting_confirm": awaiting_confirm, "awaiting_effect": true,
		"awaiting_presentation": has_pending_presentation(), "state": state.duplicate(true),
		"enters": enters_seen.duplicate(), "input_move": false,
		"pending_effect": _pending_dialogue.get("effect", {}).duplicate(true),
		"pending_id": _pending_dialogue.get("id", "")}

func has_pending_presentation() -> bool:
	return String(_pending_dialogue.get("transport", "")).begins_with("presentation_")

func pending_presentation() -> Dictionary:
	if not has_pending_presentation(): return {}
	return {"id": _pending_dialogue.id, "effect": _pending_dialogue.effect.duplicate(true),
		"generation": _generation, "page_revision": page_revision}

func presentation_generation() -> int: return _generation

## T121 production owner: the renderer's bounded transition parks here and the
## display owner presents every phase. Advancement and completion both verify
## the caller's transition id, so a stale driver can never finish a newer
## transition or resurrect an old one.
func has_pending_transition() -> bool:
	return not _pending_transition.is_empty()

func pending_transition_id() -> String:
	return String(_pending_transition.get("id", ""))

func advance_transition(expected_id: String) -> Dictionary:
	if _pending_transition.is_empty(): return {"error": "no pending cross-fade transition"}
	if expected_id != String(_pending_transition.get("id", "")):
		return {"error": "stale cross-fade phase request"}
	var advanced: Dictionary = _pending_transition.owner.advance()
	if advanced.has("error"): return advanced
	if _pending_transition.owner.complete():
		return {"phase": advanced.receipt, "exhausted": true}
	return {"phase": advanced.receipt, "exhausted": false}

func transition_phase_frame(expected_id: String) -> Dictionary:
	if _pending_transition.is_empty(): return {"error": "no pending cross-fade transition"}
	if expected_id != String(_pending_transition.get("id", "")):
		return {"error": "stale cross-fade frame request"}
	return _pending_transition.owner.frame_rgba()

## The endpoint: publish the exact target page, adopt the T244 candidate state
## and release the parked script waiter. Everything runs only after the display
## owner has presented the phases it promised to.
func finish_transition(expected_id: String) -> Dictionary:
	if _pending_transition.is_empty(): return {"error": "no pending cross-fade transition"}
	if expected_id != String(_pending_transition.get("id", "")):
		return {"error": "stale cross-fade completion"}
	var finished: Dictionary = _pending_transition.owner.finish()
	if finished.has("error"): return finished
	var pending: Dictionary = _pending_transition
	_pending_transition = {}
	var candidate: Dictionary = finished.state
	var adopted: Dictionary = _adopt(candidate, cache, map_cache)
	if adopted.has("error"): return adopted
	var frame: Dictionary = _frames.back()
	frame.step = frame.enter.resume(pending.inner_id,
		{"completed": true, "state": state.duplicate(true)})
	return _drive()

## Explicit test-only choice. Production defaults to awaiting real presentation.
func bind_recording_dialogue_for_probe() -> bool:
	if _running: return false
	_presentation_required = false
	return true

func require_presented_dialogue() -> void:
	_presentation_required = true

func tick(key_levels, timer_tick: bool = false) -> Dictionary:
	if has_pending_transition():
		# The parked cross-fade advances through its named owner only.
		return {"completed": false, "awaiting_transition": true,
			"id": pending_transition_id(), "pending_kind": "clear_effective_cross_fade",
			"input_move": false}
	var polled: Dictionary = input.poll(key_levels)
	if polled.has("error"): return _failure(str(polled.error))
	if not _pending_dialogue.is_empty():
		if has_pending_presentation(): return _parked()
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

func resume_dialogue(request_id: String, event: Dictionary) -> Dictionary:
	if _pending_dialogue.is_empty() or request_id != _pending_dialogue.id or has_pending_presentation():
		return {"error": "pal98-new-game: stale or non-input dialogue completion"}
	var pending: Dictionary = _pending_dialogue
	_pending_dialogue = {}; awaiting_confirm = false
	var frame: Dictionary = _frames.back()
	frame.step = frame.enter.resume(pending.inner_id, {"event": event})
	return _drive()

## Match the exact parked generation and rendered receipt before releasing it.
func resume_presentation(request_id: String, response: Dictionary) -> Dictionary:
	if not has_pending_presentation() or request_id != _pending_dialogue.id:
		return {"error": "pal98-new-game: stale presentation completion"}
	if response.has("error"): return _failure("presentation: " + str(response.error))
	if not response.get("receipt") is Dictionary:
		return {"error": "pal98-new-game: matching rendered receipt required"}
	var receipt: Dictionary = response.receipt
	if not receipt.get("source") is Dictionary:
		return {"error": "pal98-new-game: matching rendered receipt source required"}
	if receipt.source.get("request_id") != request_id or typeof(receipt.get("rendered_process_frame")) != TYPE_INT:
		return {"error": "pal98-new-game: matching rendered receipt required"}
	var pending: Dictionary = _pending_dialogue
	var kind: String = pending.effect.kind
	var expected: String = "captured" if kind == "capture_background" else ("restored" if kind == "restore_background" else ("box_drawn" if kind == "draw_dialogue_box" else "drawn"))
	if response.get("event") != {"kind": expected}:
		return {"error": "pal98-new-game: presentation event does not match request"}
	_record_page(pending.effect)
	_pending_dialogue = {}; awaiting_confirm = false
	var answer: Dictionary = {"event": response.event} if pending.transport == "presentation_event" else {"completed": true, "state": pending.state}
	var frame: Dictionary = _frames.back()
	frame.step = frame.enter.resume(pending.inner_id, answer)
	return _drive()

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
			_record_page({"kind": "capture_background"})
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
			_record_page({"kind": "restore_background"})
			var res: Dictionary = {"completed": true, "restore": restored.receipt}
			if request.get("state") is Dictionary: res.state = request.state.duplicate(true)
			return res
		"render_current_map_background":
			var rendered: Dictionary = renderer.render(request.get("state", {}))
			if rendered.has("error"): return rendered
			_new_scene_page()
			var answer: Dictionary = {"completed": true, "render": rendered.receipt}
			if request.get("state") is Dictionary: answer.state = rendered.state
			return answer
		"play_midi", "stop_midi", "play_sound_effect", "stop_sound":
			# The preview plays no audio. A named skip receipt keeps the
			# chain honest (no track is claimed to have played) while the
			# opening script continues past its BGM cues.
			return {"completed": true, "named_unsupported": "preview audio", "kind": kind}
		"render_scene":
			# The trigger redraw phase re-renders the resting scene from the
			# live coordinator state; the mode word stays trigger-owned.
			var redrawn: Dictionary = renderer.render(state)
			if redrawn.has("error"): return redrawn
			_new_scene_page()
			var redraw_answer: Dictionary = {"completed": true, "render": redrawn.receipt}
			redraw_answer.state = redrawn.state if redrawn.get("state") is Dictionary else state.duplicate(true)
			return redraw_answer
		"clear_effective_cross_fade":
			# T121: an explicitly bound double keeps its probe scope; the
			# production owner otherwise parks the script waiter and the
			# scene display presents every phase through finish_transition.
			if _doubles.has("clear_effective_cross_fade"):
				return _doubles["clear_effective_cross_fade"].answer(request)
			if has_pending_transition():
				return _failure("a cross-fade transition is already pending")
			if typeof(request.get("first")) != TYPE_INT or typeof(request.get("second")) != TYPE_INT:
				return _failure("cross-fade requires explicit first and second words")
			var begun: Dictionary = renderer.begin_clear_cross_fade(state, request.first, request.second)
			if begun.has("error"): return begun
			_pending_transition = {"id": String(request.id), "inner_id": request.id,
				"owner": begun.owner}
			return {"parked_transition": true, "id": request.id, "receipt": begun.receipt}
	if _doubles.has(kind):
		return _doubles[kind].answer(request)
	return {"error": "no execution owner bound for " + kind}
