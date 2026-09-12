# SPDX-License-Identifier: MIT
extends SceneTree
## The real palette display executor: the G0150 endpoints cold load from the
## admitted PAT day/night pair, and the 0x0080/0x008C fades run with those real
## palette bytes through the real executor, so every receipt is an install that
## actually happened. Covers per-round byte identity, pixel evidence, host
## writeback, clock/queue/frame helpers and the Enter-level cancellation guard.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Palette = preload("res://src/native_pal98_palette.gd")
const Display = preload("res://src/native_pal98_display_palette.gd")
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const Package = preload("res://src/native_package.gd")
const Enter = preload("res://src/native_pal98_enter_script.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Schema = preload("res://src/native_schema.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

## Explicit logical clock: fade delays are consumed from here, never from time.
class CountingClock:
	var total: int = 0
	var refuse: bool = false
	func consume(units: int) -> Dictionary:
		if refuse: return {"error": "clock refused the wait"}
		total += units
		return {"consumed": units, "total": total}

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

## Mean channel value on the 0..255 display scale for an RGB6 palette.
func _avg(rgb6: PackedByteArray) -> float:
	var total: int = 0
	for index in range(0, rgb6.size(), 3):
		total += int(rgb6[index]) + int(rgb6[index + 1]) + int(rgb6[index + 2])
	return float(total) * 4.0 / float(rgb6.size() / 3)

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4; var bytes = _zero(size); bytes.encode_u32(0, size)
	for i in range(chunks.size()): size += chunks[i].size(); bytes.encode_u32((i + 1) * 4, size)
	for chunk in chunks: bytes.append_array(chunk)
	return bytes

## Synthetic admitted source whose scene 1 entry script is the given program.
func _source(program: Array):
	var events: PackedByteArray = _zero(32)
	var scenes: PackedByteArray = _zero(16)
	scenes.encode_u16(0, 20); scenes.encode_u16(2, 1); scenes.encode_u16(6, 0)
	var offsets: PackedByteArray = _zero(4)
	var scripts: PackedByteArray = _zero((program.size() + 1) * 8)
	for i in range(program.size()):
		for word in range(4): scripts.encode_u16((i + 1) * 8 + word * 2, program[i][word] & 0xffff)
	var files: Dictionary = {"data": _mkf([_zero(0), _zero(0), _zero(0), _zero(900)]),
		"sss": _mkf([events, scenes, _zero(14), offsets, scripts]), "words": _zero(10), "messages": PackedByteArray()}
	var hashes: Dictionary = {}; var entries: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(files[role])
	var identity: String = Sources.fingerprint("gbk", hashes)
	for role in Sources.FILES: entries[role] = {"path": "content/pal98-sources/" + identity + "/" + Sources.FILES[role],
		"sha256": hashes[role], "size_bytes": files[role].size()}
	var source = Sources.new()
	if not source.load_source({"schema": Sources.SCHEMA, "kind": "content", "dialect": "pal98-win95",
		"text_encoding": "gbk", "fingerprint": identity, "files": entries,
		"label": "Synthetic display palette source", "license": "CC0-1.0", "redistributable": true,
		"provenance": {"status": "synthetic"}}, files, Schema.new()): return null
	return source

func _cold_backing(palette, day: PackedByteArray, night: PackedByteArray) -> PackedByteArray:
	var backing: PackedByteArray = _zero(Palette.BUFFER)
	var loaded: Dictionary = palette.load_day_night(backing, day, night)
	if loaded.has("error"): push_error(str(loaded.error))
	return backing

func _command_state(palette, day: PackedByteArray, night: PackedByteArray) -> Dictionary:
	return {"globals": {"current_scene": 1, "battle_mode": 0, "day_night_word": 0,
		"fade_gate_word": 1, "member_last": 0, "follower_count": 0, "trigger_success_word": 0},
		"palette_bytes": _cold_backing(palette, day, night)}

func _fixture(source, palette, day: PackedByteArray, night: PackedByteArray) -> Dictionary:
	var storage = Events.new(); storage.load_source(source)
	var equipment = Equipment.new()
	equipment.read_tables(source.copy_chunk("data", 3), source.copy_chunk("sss", 2), source.copy_chunk("sss", 4))
	return {"globals": {"current_scene": 1, "requested_scene": 1, "party_x": 160, "party_y": 112,
			"viewport_x": 864, "viewport_y": 912, "resource_flags": 0, "direction_word": 0, "loaded_map_id": 0,
			"member_last": 0, "follower_count": 0, "battle_mode": 0, "midi_track": 0, "battle_music_track": 0,
			"day_night_word": 0, "fade_gate_word": 1, "trigger_success_word": 0},
		"events": storage.source_state(), "rng": Random.create(0x12345),
		"dialogue": {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44, "origin_y": 26,
			"mode": 1, "line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202, "icon": 2, "skip_word": 0,
			"delay_units": 1, "input_action": 99, "capture_gate": 1, "restore_gate": 0,
			"colours": [79, 45, 26, 141], "timer_counter": 0},
		"equipment": equipment.initial_state([0]), "inventory_bytes": _zero(1536),
		"palette_bytes": _cold_backing(palette, day, night),
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
	var day: Dictionary = records.palette(0, 0)
	var night: Dictionary = records.palette(0, 1)
	if day.has("error") or night.has("error"):
		push_error("PAT admission failed: " + str(day.get("error", "")) + str(night.get("error", ""))); quit(2); return
	var day_bytes: PackedByteArray = day.value
	var night_bytes: PackedByteArray = night.value
	check(_avg(night_bytes) < _avg(day_bytes),
		"the admitted night variant is the dark pair: %.1f < %.1f" % [_avg(night_bytes), _avg(day_bytes)])

	# Cold load: the admitted pair fills the fade endpoints, scratch starts zero.
	var palette = Palette.new()
	var backing: PackedByteArray = _zero(Palette.BUFFER)
	var loaded: Dictionary = palette.load_day_night(backing, day_bytes, night_bytes)
	check(not loaded.has("error"), "the admitted PAT pair cold loads: " + str(loaded.get("error", "")))
	check(backing.slice(0, 0x300) == day_bytes and backing.slice(0x300, 0x600) == night_bytes,
		"the day and night blocks are byte-identical to the admitted variants")
	check(backing.slice(0x600, 0xC00) == _zero(0x600), "the work and target blocks start zeroed")
	var short_backing: PackedByteArray = _zero(0x600)
	check(palette.load_day_night(short_backing, day_bytes, night_bytes).has("error")
		and short_backing == _zero(0x600), "a short backing is refused untouched")
	var hot_day: PackedByteArray = day_bytes.duplicate(); hot_day[5] = 64
	var untouched: PackedByteArray = _zero(Palette.BUFFER)
	check(palette.load_day_night(untouched, hot_day, night_bytes).has("error")
		and untouched == _zero(Palette.BUFFER), "an RGB6 overflow day palette is refused untouched")
	var short_night: PackedByteArray = night_bytes.slice(0, 0x2FF)
	check(palette.load_day_night(untouched, day_bytes, short_night).has("error"),
		"a short night palette is refused")

	# Executor refusals: nothing is installed unless the request is complete.
	var executor = Display.new()
	check(executor.installed_rgb6().is_empty() and executor.install_generation() == 0,
		"nothing is installed before the first apply")
	check(executor.answer({"kind": "palette_swap"}).has("error")
		and "not a display palette request" in executor.error, "foreign requests are refused by name")
	var good: Dictionary = {"kind": "apply_palette", "procedure": "intpate", "offset": 0x300,
		"byte_offset": 0x600, "length": 0x300, "bytes": night_bytes}
	var short_install: Dictionary = good.duplicate(); short_install.bytes = night_bytes.slice(0, 0x2FF)
	check(executor.answer(short_install).has("error") and executor.installed_rgb6().is_empty(),
		"a short install block is refused and nothing is installed")
	var odd: Dictionary = good.duplicate(); odd.byte_offset = 0x601
	check(executor.answer(odd).has("error"), "an odd byte offset is refused")
	var mismatch: Dictionary = good.duplicate(); mismatch.offset = 0x180
	check(executor.answer(mismatch).has("error"), "a WORD/byte offset disagreement is refused")
	var beyond: Dictionary = good.duplicate(); beyond.byte_offset = 0x902; beyond.offset = 0x481
	check(executor.answer(beyond).has("error"), "an install outside the G0150 backing is refused")
	var hot: Dictionary = good.duplicate(); hot.bytes = night_bytes.duplicate(); hot.bytes[10] = 64
	check(executor.answer(hot).has("error") and executor.installed_rgb6().is_empty(),
		"an RGB6 overflow install is refused and nothing is installed")
	var wrong_procedure: Dictionary = good.duplicate(); wrong_procedure.procedure = "blit"
	check(executor.answer(wrong_procedure).has("error"), "a foreign procedure name is refused")

	# A valid install really installs, and its receipt carries the generation.
	var first_install: Dictionary = executor.answer(good)
	check(not first_install.has("error") and first_install.get("completed") == true
		and first_install.install.byte_offset == 0x600 and first_install.install.generation == 1,
		"the first valid install completes with receipt generation 1")
	check(executor.installed_rgb6() == night_bytes, "the installed palette is byte-identical to the block")
	var again: Dictionary = executor.answer(good)
	check(again.install.generation == 2 and executor.receipts().size() == 2,
		"every install bumps the generation and appends a receipt")

	# The wait consumes from the bound logical clock only.
	var clock = CountingClock.new()
	var wait_executor = Display.new()
	check(wait_executor.answer({"kind": "fade_wait", "delay": 5}).has("error")
		and "no logical clock" in wait_executor.error, "fade_wait without a clock is refused by name")
	check(wait_executor.bind_clock(clock) and not wait_executor.answer({"kind": "fade_wait", "delay": 5}).has("error")
		and clock.total == 5, "fade_wait consumes exactly the delay units")
	check(wait_executor.answer({"kind": "fade_wait", "delay": 0}).has("error"),
		"a nonpositive delay is refused")
	clock.refuse = true
	check(wait_executor.answer({"kind": "fade_wait", "delay": 2}).has("error") and clock.total == 5,
		"a clock refusal propagates and consumes nothing")
	clock.refuse = false

	# The pump drains the offered queue; the frame counter advances by argument.
	wait_executor.offer_input({"action": 7}); wait_executor.offer_input({"action": 9})
	var pumped: Dictionary = wait_executor.answer({"kind": "fade_event_pump"})
	check(pumped.get("pumped", []).size() == 2 and pumped.pumped[0].action == 7
		and wait_executor.answer({"kind": "fade_event_pump"}).get("pumped", []).is_empty(),
		"the pump drains exactly the offered events")
	check(wait_executor.answer({"kind": "fade_frame", "argument": 1}).frame == 1,
		"the frame helper advances the frame counter")

	# Real 0x0080 with the real palette bytes through the real executor.
	var commands = Commands.new()
	if not commands.load_source(package.pal98_sources): push_error("commands load failed"); quit(2); return
	var fade_executor = Display.new()
	var fade_clock = CountingClock.new()
	fade_executor.bind_clock(fade_clock)
	var state: Dictionary = _command_state(palette, day_bytes, night_bytes)
	var run: Dictionary = commands.consume(state, {"words": [0x0080, 5, 0, 0], "entry": 1, "event_id": 0})
	check(not run.has("error"), "the real day palette starts the 0x0080 fade: " + str(run.get("error", "")))
	var installs: int = 0; var waits: int = 0; var broken: int = 0
	var samples: Array = []; var rewrite_at: int = -1; var settled_kept: bool = true
	while run.has("pending") or not run.get("requests", []).is_empty():
		for request in run.get("requests", []):
			var answer: Dictionary = fade_executor.answer(request)
			if answer.has("error"):
				broken += 1; push_error(str(answer.error)); continue
			if request.kind == "apply_palette":
				installs += 1
				var installed: PackedByteArray = fade_executor.installed_rgb6()
				if installed != state.palette_bytes.slice(request.byte_offset, request.byte_offset + 0x300):
					broken += 1
				if installs == 2:
					# Host writeback: settle one work byte at its target between
					# rounds; the later installs must carry the settled byte.
					state.palette_bytes[0x600 + 5] = night_bytes[5]
					rewrite_at = installs
				if rewrite_at >= 0 and installs > rewrite_at and installed[5] != night_bytes[5]:
					settled_kept = false
				if installs in [1, 9, 17, 25, 33]: samples.append(installed.duplicate())
			elif request.kind == "fade_wait": waits += 1
		if not run.has("pending"): break
		run = commands.continue_command(run.pending, state)
	check(broken == 0, "every answered install is byte-identical to the command block: %d broken" % broken)
	check(installs == 33 and waits == 32 and fade_clock.total == 160,
		"the real fade publishes 32 round installs plus the terminal install: %d/%d" % [installs, waits])
	check(state.globals.day_night_word == 0x180 and state.globals.fade_gate_word == 0,
		"the terminal adopts the night offset and clears the gate")
	check(fade_executor.installed_rgb6() == night_bytes,
		"the terminal install leaves the admitted night palette on the display")
	check(rewrite_at == 2 and settled_kept, "the host-settled byte survives every later install")
	if samples.size() == 5:
		var dropping: bool = true
		for index in range(1, samples.size()):
			if _avg(samples[index]) > _avg(samples[index - 1]): dropping = false
		check(dropping and _avg(samples[4]) < _avg(samples[0]),
			"the installed palette darkens monotonically from day toward night")
	else:
		check(false, "sampling missed fade installs: %d" % samples.size())

	# Pixel evidence: a real decoded plane through the installed palettes.
	var plane: Dictionary = {"error": "sprite group not scanned"}
	for candidate in range(40):
		plane = records.frame("GOP.MKF", candidate, 0)
		if not plane.has("error"): break
	check(not plane.has("error"), "a real GOP plane decodes for the pixel evidence: " + str(plane.get("error", "")))
	if not plane.has("error"):
		var first: Dictionary = Indexed.rgba(plane.value, samples[0], true)
		var last: Dictionary = Indexed.rgba(plane.value, samples[4], true)
		if first.has("error") or last.has("error"):
			check(false, "pixel conversion failed: " + str(first.get("error", "")) + str(last.get("error", "")))
		else:
			var first_sum: int = 0; var last_sum: int = 0
			for at in range(0, first.value.size(), 4): first_sum += int(first.value[at])
			for at in range(0, last.value.size(), 4): last_sum += int(last.value[at])
			check(last_sum < first_sum,
				"the same plane renders darker under the final palette: %d -> %d" % [first_sum, last_sum])

	# Real 0x008C: the fill color converges the writable block in 63 rounds.
	var color_clock = CountingClock.new()
	var color_executor = Display.new()
	color_executor.bind_clock(color_clock)
	var color_state: Dictionary = _command_state(palette, day_bytes, night_bytes)
	var color_run: Dictionary = commands.consume(color_state, {"words": [0x008C, 0, 3, 0], "entry": 1, "event_id": 0})
	check(not color_run.has("error"), "the real color fade starts from the admitted pair: " + str(color_run.get("error", "")))
	var color_installs: int = 0; var color_broken: int = 0
	var final_color: PackedByteArray = PackedByteArray()
	while color_run.has("pending") or not color_run.get("requests", []).is_empty():
		for request in color_run.get("requests", []):
			var answer: Dictionary = color_executor.answer(request)
			if answer.has("error"):
				color_broken += 1; push_error(str(answer.error)); continue
			if request.kind == "apply_palette":
				color_installs += 1
				if color_executor.installed_rgb6() != color_state.palette_bytes.slice(request.byte_offset, request.byte_offset + 0x300):
					color_broken += 1
				final_color = color_executor.installed_rgb6()
		if not color_run.has("pending"): break
		color_run = commands.continue_command(color_run.pending, color_state)
	check(color_broken == 0, "every color fade install is byte-identical to the writable block")
	check(color_installs == 63 and color_clock.total == 189,
		"the color fade publishes exactly 63 installs and waits: %d" % color_installs)
	check(final_color == _zero(0x300), "63 signed rounds land the display palette exactly on black")
	check(color_state.palette_bytes.slice(0x900, 0xC00) == _zero(0x300),
		"the untouched target block stays zeroed")

	# The A2 swap fades the work block back toward the saved day copy.
	var swap_clock = CountingClock.new()
	var swap_executor = Display.new()
	swap_executor.bind_clock(swap_clock)
	var swap_state: Dictionary = _command_state(palette, day_bytes, night_bytes)
	var swap_run: Dictionary = commands.consume(swap_state, {"words": [0x008C, 0, 3, 1], "entry": 1, "event_id": 0})
	var swap_installs: int = 0; var swap_final: PackedByteArray = PackedByteArray()
	while swap_run.has("pending") or not swap_run.get("requests", []).is_empty():
		for request in swap_run.get("requests", []):
			var answer: Dictionary = swap_executor.answer(request)
			if not answer.has("error") and request.kind == "apply_palette":
				swap_installs += 1
				swap_final = swap_executor.installed_rgb6()
		if not swap_run.has("pending"): break
		swap_run = commands.continue_command(swap_run.pending, swap_state)
	check(swap_installs == 63, "the swapped fade also runs 63 installs: %d" % swap_installs)
	check(swap_final == day_bytes, "the swapped writable block converges exactly onto the admitted day palette")

	# Enter-level cancellation: the abandoned fade stops answering, a restart
	# on the same owner completes through the same executor.
	var source = _source([[0x0080, 5, 0, 0], [0x0001, 0, 0, 0]])
	if source == null:
		check(false, "synthetic display source builds")
	else:
		var owner = Enter.new()
		check(owner.load_source(source), "the enter owner binds the synthetic display source")
		var adapter = EntryHost.new()
		var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
		adapter.bind(cache, Equipment.new(), _zero(1536), [0, 0, 0, 0, 0, 0])
		var cancel_executor = Display.new()
		var cancel_clock = CountingClock.new()
		cancel_executor.bind_clock(cancel_clock)
		adapter.bind_display(cancel_executor)
		var start_state: Dictionary = _fixture(source, palette, day_bytes, night_bytes)
		var result: Dictionary = owner.start(start_state, 1, 1)
		if result.has("error"): print("START ERR: %s" % str(result.error))
		var seen_installs: int = 0; var cancelled: bool = false; var stale_refused: bool = false
		for guard in range(4096):
			if not result.has("request"): break
			var request: Dictionary = result.request
			if not request.has("original_entry"):
				result = owner.resume(request.id, {"completed": true}); continue
			if seen_installs == 1:
				owner.cancel()
				cancelled = true
				stale_refused = owner.resume(request.id, {"completed": true}).has("error")
				break
			var answer: Dictionary = adapter.answer(request)
			if answer.has("error"): check(false, "executor answer failed: " + str(answer.error)); break
			if request.kind == "apply_palette": seen_installs += 1
			result = owner.resume(request.id, answer)
		check(cancelled and stale_refused, "a resume after cancel is refused as stale")
		check(seen_installs == 1, "the cancelled fade stopped after its first install")
		var restart_state: Dictionary = _fixture(source, palette, day_bytes, night_bytes)
		var restart: Dictionary = owner.start(restart_state, 1, 1)
		if restart.has("error"): print("RESTART ERR: %s" % str(restart.error))
		var restart_installs: int = 0; var restart_broken: int = 0; var restart_done: bool = false
		for guard in range(4096):
			if not restart.has("request"): restart_done = true; break
			var request: Dictionary = restart.request
			if not request.has("original_entry"):
				restart = owner.resume(request.id, {"completed": true}); continue
			var answer: Dictionary = adapter.answer(request)
			if answer.has("error"): restart_broken += 1; break
			if request.kind == "apply_palette":
				restart_installs += 1
				# The enter owner runs on its own state copy, so the honest
				# invariant is against the bytes the command published.
				if cancel_executor.installed_rgb6() != request.bytes:
					restart_broken += 1
			restart = owner.resume(request.id, answer)
		check(restart_done and restart_broken == 0 and restart_installs == 33,
			"the restarted fade completes through the same executor: %d installs, %d broken" % [restart_installs, restart_broken])
		var final_effects: Array = restart.get("effects", [])
		check(not final_effects.is_empty() and final_effects[final_effects.size() - 1].get("kind", "") == "day_night_fade_done"
			and cancel_executor.installed_rgb6() == night_bytes,
			"the restarted fade lands the admitted night palette on the display")

	var output: Dictionary = {"suite": "test_pal98_display_palette", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
