# SPDX-License-Identifier: MIT
extends SceneTree
## Cold start over the real resource-reload chain: the scene record's own MAP
## identity, the real EnterScript chain with the real palette display executor,
## the entry script's own scene travel into MAP12, named missing-resource
## refusals and exit/reopen determinism, all from one admitted package with
## fresh private outputs and no dev caches. The original opening loops between
## runtime scenes 1 and 2 until a real player answers the intro; this suite
## stops that loop by name after the second scene entry instead of waiting.
## Audio stays unowned: the cold start keeps the MIDI bit clear.
const Reload = preload("res://src/native_pal98_resource_reload.gd")
const Enter = preload("res://src/native_pal98_enter_script.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const DialogueHost = preload("res://src/native_pal98_dialogue_host.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
const Inventory = preload("res://src/native_pal98_inventory.gd")
const Palette = preload("res://src/native_pal98_palette.gd")
const Display = preload("res://src/native_pal98_display_palette.gd")
const Package = preload("res://src/native_package.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

## Explicit logical clock for the executor's fade waits.
class ColdClock:
	func consume(units: int) -> Dictionary:
		return {"consumed": units, "total": units}

## Routes the palette family to the real executor and records every other
## display kind as an explicitly named double: the real background/frame
## render owner is a later work package.
class SplitDisplay:
	var palette_executor
	var renderer
	var doubled: Array = []
	func _init(executor, scene_renderer) -> void:
		palette_executor = executor; renderer = scene_renderer
	func answer(request: Dictionary) -> Dictionary:
		if request.kind in ["apply_palette", "fade_wait", "fade_event_pump", "fade_frame"]:
			return palette_executor.answer(request)
		if request.kind == "render_current_map_background" and renderer != null:
			var rendered: Dictionary = renderer.render(request.get("state", {}))
			if rendered.has("error"): return rendered
			var answer: Dictionary = {"completed": true, "render": rendered.receipt}
			if request.get("state") is Dictionary: answer.state = request.state.duplicate(true)
			return answer
		if request.kind == "clear_effective_cross_fade" and renderer != null:
			var prepared: Dictionary = renderer.prepare_clear_cross_fade(
				request.get("state", {}), request.get("first", 0), request.get("second", 0))
			if prepared.has("error"): return prepared
			var answer: Dictionary = {"completed": true, "cross_fade": prepared.receipt}
			if request.get("state") is Dictionary: answer.state = request.state.duplicate(true)
			return answer
		if request.kind == "restore_dialog_background" and renderer != null:
			var restored: Dictionary = renderer.restore_dialog_background()
			if restored.has("error"): return restored
			var answer: Dictionary = {"completed": true, "restore": restored.receipt}
			if request.get("state") is Dictionary: answer.state = request.state.duplicate(true)
			return answer
		doubled.append(request.kind)
		return {"completed": true}

## Movement double implementing the reviewed extf relation (the external extf
## has no body in PAL.EXE): face the delta quadrant, then recompute the world
## position from the viewport plus the party anchor. Other forwarded kinds go
## to the display router with the ByRef state round-trip preserved.
## Binds the real Enter chain with the real palette display executor. The cold
## display palette is installed before any fade runs, with a receipt.
class EnterDriver:
	var enter
	var adapter
	var dialogue_host
	var executor
	var split: SplitDisplay
	var terminals: Array = []
	func _init(package, cold_rgb6: PackedByteArray) -> void:
		enter = Enter.new()
		if not enter.load_source(package.pal98_sources): push_error("enter load failed")
		adapter = EntryHost.new()
		var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
		var kernel = Equipment.new()
		kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
			package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
		var inventory: PackedByteArray = PackedByteArray(); inventory.resize(1536)
		adapter.bind(cache, kernel, inventory, [0, 0, 0, 0, 0, 0])
		adapter.bind_inventory(load("res://src/native_pal98_inventory.gd").new())
		executor = Display.new()
		executor.bind_clock(ColdClock.new())
		var installed: Dictionary = executor.install_cold(cold_rgb6)
		if installed.has("error"): push_error(str(installed.error))
		var renderer = load("res://src/native_pal98_scene_render.gd").new()
		if not renderer.bind(package.pal98_graphics.open_records()): push_error(str(renderer.error))
		split = SplitDisplay.new(executor, renderer)
		adapter.bind_display(split)
		var facing = load("res://src/native_pal98_walk_facing.gd").new()
		facing.bind_fallback(split)
		adapter.bind_movement(facing)
		dialogue_host = DialogueHost.new(); dialogue_host.bind(package.pal98_sources)
	func run(state: Dictionary, scene_id: int, entry: int, event_id: int) -> Dictionary:
		var result: Dictionary = enter.start(state, scene_id, entry, event_id)
		for guard in range(16384):
			if result.has("error"): return result
			if not result.has("request"):
				terminals.append(result)
				return result
			var request: Dictionary = result.request
			if request.kind == "dialogue":
				result = enter.resume(request.id, {"event": dialogue_host.answer(request.effect)})
			elif request.has("original_entry"):
				var answer: Dictionary = adapter.answer(request)
				if answer.has("error"): return {"error": "enter host: " + str(answer.error)}
				result = enter.resume(request.id, answer)
			elif request.kind == "yes_no":
				result = enter.resume(request.id, {"state": request.state, "result": 1})
			elif request.kind == "battle":
				result = enter.resume(request.id, {"state": request.state, "result": 0})
			elif request.has("state"):
				result = enter.resume(request.id, {"state": request.state, "completed": true})
			else:
				result = enter.resume(request.id, {"completed": true})
		return {"error": "enter driver budget exceeded"}

## Answers the reload owner's requests; enter_script goes through the real
## chain. After `max_enters` scene entries the driver stops the original's
## scene loop by name: the opening awaits a real player, not an auto-answer.
class ReloadDriver:
	var reload
	var enter_driver
	var max_enters: int
	var enters_seen: Array = []
	var renderer
	func _init(owner, driver, enters: int, scene_renderer = null) -> void:
		reload = owner; enter_driver = driver; max_enters = enters; renderer = scene_renderer
	func start(state: Dictionary, cache) -> Dictionary:
		var step: Dictionary = reload.start(state, cache)
		for guard in range(32768):
			if step.has("error") or step.get("state") is Dictionary: return step
			if not step.has("request"): return {"error": "reload stopped without a terminal state"}
			var request: Dictionary = step.request
			match request.kind:
				"render_background":
					if renderer != null:
						var rendered: Dictionary = renderer.render(request.state)
						if rendered.has("error"): return {"error": "reload render: " + str(rendered.error)}
					step = reload.resume(request.id, {"completed": true})
				"enter_script":
					enters_seen.append(request.scene_id)
					if enters_seen.size() > max_enters:
						return reload.resume(request.id,
							{"error": "suite chain bound: the opening loop awaits a real player"})
					var run: Dictionary = enter_driver.run(request.state, request.scene_id,
						request.entry, request.event_id)
					if run.has("error"): return {"error": "reload enter: " + str(run.error)}
					step = reload.resume(request.id, {"state": run.state,
						"return_entry": run.return_entry})
				"play_midi":
					step = reload.resume(request.id, {"completed": true})
				"load_save":
					return {"error": "cold start must not request a save load"}
				_:
					return {"error": "reload driver does not own: " + str(request.kind)}
		return {"error": "reload driver budget exceeded"}

func _fixture(package, palette, day: PackedByteArray, night: PackedByteArray) -> Dictionary:
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	var equipment = Equipment.new()
	equipment.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var backing: PackedByteArray = _zero(Palette.BUFFER)
	var loaded: Dictionary = palette.load_day_night(backing, day, night)
	if loaded.has("error"): push_error(str(loaded.error))
	return {"globals": {"current_scene": 0, "requested_scene": 1, "resource_flags": 29,
			"party_x": 160, "party_y": 112, "viewport_x": 864, "viewport_y": 912,
			"world_x": 1024, "world_y": 1024, "previous_x": 1024, "previous_y": 1024,
			"previous_viewport_x": 864, "previous_viewport_y": 912,
			"loaded_map_id": 0, "member_last": 0, "follower_count": 0, "battle_mode": 0,
			"midi_track": 0, "battle_music_track": 0, "day_night_word": 0, "fade_gate_word": 0,
			"direction_word": 0, "party_layer_word": 0, "fbp_mode_word": 0,
			"ffxy_max_x": 1696, "ffxy_max_y": 1840,
			"view_offset_x": 0, "view_offset_y": 0, "transition_cadence": 0, "transition_progress": 0,
			"wave_phase": 0, "wave_amplitude": 0, "trigger_success_word": 0},
		"events": storage.source_state(), "rng": Random.create(0x12345),
		"dialogue": {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44,
			"origin_y": 26, "mode": 1, "line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202,
			"icon": 2, "skip_word": 0, "delay_units": 1, "input_action": 99, "capture_gate": 1,
			"restore_gate": 0, "colours": [79, 45, 26, 141], "timer_counter": 0},
		"equipment": equipment.initial_state([0]), "inventory_bytes": _zero(1536),
		"palette_bytes": backing,
		"party_records": [{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 3}],
		"party_trail": [{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}]}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var records = package.pal98_graphics.open_records()
	var source_records = package.pal98_sources.open_records()
	var palette = Palette.new()
	var day: Dictionary = records.palette(0, 0)
	var night: Dictionary = records.palette(0, 1)
	if day.has("error") or night.has("error"): push_error("PAT admission failed"); quit(2); return

	# Missing-resource diagnostics come before any success path.
	check(records.palette(0, 2).has("error"), "an absent PAT variant is refused by name")
	check(records.decoded_chunk("MAP.MKF", 99999).has("error"), "an absent MAP chunk is refused by name")
	check(source_records.scene_for_runtime_id(99999).has("error"),
		"a scene outside the playable table is refused by name")

	# Cold start: reload scene 1 from the documented original init words, and
	# stop the original's scene loop by name after the scene 2 entry.
	var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
	var reload = Reload.new()
	check(reload.load_source(package.pal98_sources, package.pal98_graphics), "reload binds the admitted sources")
	var scene_renderer = load("res://src/native_pal98_scene_render.gd").new()
	if not scene_renderer.bind(package.pal98_graphics.open_records()):
		push_error(str(scene_renderer.error))
	var driver = ReloadDriver.new(reload, EnterDriver.new(package, day.value), 2, scene_renderer)
	var state: Dictionary = _fixture(package, palette, day.value, night.value)
	var done: Dictionary = driver.start(state, cache)
	check(not done.has("error") and driver.enters_seen == [1, 2],
		"the cold start chains scene 1 into the entry's own scene 2 request and completes: "
			+ str(done.get("error", "")) + str(driver.enters_seen))
	var trace: Array = done.get("trace", [])
	check("load_map_gop:20" in trace and "load_map_gop:12" in trace
		and "enter_script:1" in trace and "enter_script:2" in trace,
		"the chain loads both scenes' own map identities: " + str(trace))
	check(not done.has("error") and done.get("state", {}).get("globals", {}).get("current_scene") == 2
		and done.state.globals.loaded_map_id == 12,
		"the completed chain rests on runtime scene 2 with its map loaded")
	var terminals: Array = driver.enter_driver.terminals
	check(terminals.size() == 2, "both scene entries ran to their terminals: " + str(terminals.size()))
	if terminals.size() != 2: finish(args); return
	var opening: Dictionary = terminals[0]
	check(opening.get("state", {}).get("globals", {}).get("viewport_x") == 864
		and opening.state.globals.viewport_y == 912 and opening.state.globals.world_x == 1024
		and opening.state.globals.world_y == 1024,
		"the real opening entry produced the original viewport and world words")
	var sprite_word: int = 0
	for effect in opening.get("effects", []):
		if effect.get("sprite_word") is int: sprite_word = effect.sprite_word
	check(sprite_word == 193, "the opening entry's own effect carries the 193 map sprite: " + str(sprite_word))
	check(opening.state.globals.day_night_word == 0 and opening.state.globals.fade_gate_word == 0,
		"the opening leaves the day/night words at their documented values")
	var executor = driver.enter_driver.executor
	check(executor.installed_rgb6() == day.value,
		"the cold display palette is byte-identical to the admitted day variant")
	var split: SplitDisplay = driver.enter_driver.split
	var doubled: Array = split.doubled
	check(doubled.has("play_midi") and not doubled.has("restore_dialog_background")
		and not doubled.has("clear_effective_cross_fade"),
		"the dialog restore and cross-fade clear are real; the remaining kinds stay named doubles: "
			+ str(doubled))
	var fades: Array = split.renderer.receipts().filter(func(receipt): return receipt.kind == "clear_effective_cross_fade")
	check(fades.size() >= 1 and fades[0].pixels_per_lane == 0x29AC and fades[0].phases > 0
		and fades[0].post_render.get("frame_sha256") is String,
		"the cross-fade clear prepares two real renders with the recovered lane parameters: "
			+ str(fades.size()))
	var restores: Array = split.renderer.receipts().filter(func(receipt): return receipt.kind == "restore_dialog_background")
	check(not restores.is_empty()
		and restores[0].frame_sha256 == split.renderer.receipts()[0].frame_sha256,
		"the dialog restore re-establishes the rendered background frame: "
			+ str(restores.size()))
	var render_receipts: Array = split.renderer.receipts()
	check(render_receipts.size() >= 2 and render_receipts[0].map_id == 20
		and render_receipts[0].frame_sha256 is String and render_receipts[0].frame_sha256.length() == 64,
		"the background renders are real 320x200 frames with content hashes: "
			+ str(render_receipts.size()))
	var render_maps: Array = render_receipts.map(func(receipt): return receipt.map_id)
	check(20 in render_maps and 12 in render_maps,
		"both scenes' backgrounds rendered through the real pass: " + str(render_maps))

	# Exit and reopen: rebuild every owner from a fresh package load and stop
	# at the same named bound; the chain must repeat itself byte-for-byte.
	var reopened = Package.new()
	if not reopened.load_package(args[0]): push_error("reopen rejected"); quit(2); return
	var reopen_records = reopened.pal98_graphics.open_records()
	var cache2 = Cache.new(); cache2.load_source(reopened.pal98_graphics, reopened.pal98_sources)
	var reload2 = Reload.new()
	check(reload2.load_source(reopened.pal98_sources, reopened.pal98_graphics), "reopen binds fresh owners")
	var reopen_renderer = load("res://src/native_pal98_scene_render.gd").new()
	if not reopen_renderer.bind(reopened.pal98_graphics.open_records()):
		push_error(str(reopen_renderer.error))
	var driver2 = ReloadDriver.new(reload2, EnterDriver.new(reopened,
		reopen_records.palette(0, 0).value), 2, reopen_renderer)
	var state2: Dictionary = _fixture(reopened, Palette.new(),
		reopen_records.palette(0, 0).value, reopen_records.palette(0, 1).value)
	var done2: Dictionary = driver2.start(state2, cache2)
	check(not done2.has("error") and driver2.enters_seen == [1, 2],
		"the reopen repeats the chain to its completion: " + str(done2.get("error", "")) + str(driver2.enters_seen))
	check(done2.get("trace", []) == trace, "the reopen repeats the cold-start trace exactly")
	check(driver2.enter_driver.terminals.size() == 2
		and driver2.enter_driver.terminals[1].get("effects", []) == terminals[1].get("effects", []),
		"the reopen reproduces the scene 2 entry effects byte-for-byte")
	check(driver2.enter_driver.split.renderer.receipts() == split.renderer.receipts(),
		"the reopen reproduces the background renders byte-for-byte")

	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_cold_start", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
