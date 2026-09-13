# SPDX-License-Identifier: MIT
extends SceneTree
## Production nested T212 through the new-game coordinator: a 0x0078 inside a
## running entry starts one nested reload generation whose state, sprite cache
## and map cache are adopted together, and the outer script continues on the
## adopted lease. Each generation owns fresh reload/enter instances, so a
## stale outer receipt is refused and a second nesting level unwinds normally.
## Bounded coordination protects genuinely recursive scripts. The synthetic two-scene source carries the real graphics
## fingerprint; probe initialization and named gaps stay explicit. The
## inherited in-test driver WIP was diagnostic input for this package only.
const Game = preload("res://src/native_pal98_new_game.gd")
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Schema = preload("res://src/native_schema.gd")
const Package = preload("res://src/native_package.gd")

class Clock:
	var frame := 0
	func consume(units: int) -> Dictionary:
		frame += units
		return {"consumed": units, "total": frame}

class Runtime:
	func answer(request: Dictionary) -> Dictionary:
		if request.kind == "fade_event_pump": return {"completed": true, "pumped": request.get("events", [])}
		return {"completed": true}

## Duck-typed package holder: synthetic sources, real graphics records.
class Pack:
	var pal98_sources
	var pal98_graphics

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4; var bytes = _zero(size); bytes.encode_u32(0, size)
	for i in range(chunks.size()): size += chunks[i].size(); bytes.encode_u32((i + 1) * 4, size)
	for chunk in chunks: bytes.append_array(chunk)
	return bytes

## Scene 1 on MAP20 runs program1; scene 2 on MAP12 runs program2. Two event
## records back the scene event ranges; provenance is synthetic but the
## graphics fingerprint is the admitted package's, so the sprite cache admits
## the pairing.
func _source_two(real_fingerprint: String, program1: Array, program2: Array):
	var events: PackedByteArray = _zero(64)
	var scenes: PackedByteArray = _zero(24)
	var enter2: int = 1 + program1.size()
	scenes.encode_u16(0, 20); scenes.encode_u16(2, 1); scenes.encode_u16(6, 0)
	scenes.encode_u16(8, 12); scenes.encode_u16(10, enter2); scenes.encode_u16(14, 1)
	scenes.encode_u16(22, 2)
	var offsets: PackedByteArray = _zero(4)
	var scripts: PackedByteArray = _zero((1 + program1.size() + program2.size()) * 8)
	for i in range(program1.size()):
		for word in range(4):
			scripts.encode_u16((1 + i) * 8 + word * 2, program1[i][word] & 0xFFFF)
	for j in range(program2.size()):
		for word in range(4):
			scripts.encode_u16((1 + program1.size() + j) * 8 + word * 2, program2[j][word] & 0xFFFF)
	var files: Dictionary = {"data": _mkf([_zero(0), _zero(0), _zero(0), _zero(900)]),
		"sss": _mkf([events, scenes, _zero(14), offsets, scripts]),
		"words": _zero(10), "messages": PackedByteArray()}
	var hashes: Dictionary = {}; var entries: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(files[role])
	var identity: String = Sources.fingerprint("gbk", hashes)
	for role in Sources.FILES:
		entries[role] = {"path": "content/pal98-sources/" + identity + "/" + Sources.FILES[role],
			"sha256": hashes[role], "size_bytes": files[role].size()}
	var source = Sources.new()
	if not source.load_source({"schema": Sources.SCHEMA, "kind": "content", "dialect": "pal98-win95",
		"text_encoding": "gbk", "fingerprint": identity, "files": entries,
		"label": "Synthetic nested T212 source", "license": "CC0-1.0", "redistributable": true,
		"provenance": {"status": "synthetic", "source_revision": "sha256:" + real_fingerprint}},
		files, Schema.new()):
		push_error("synthetic source build failed: " + str(source.error)); return null
	return source

func _assembly(holder: Pack):
	var game = Game.new()
	check(game.open(holder), "the coordinator binds synthetic sources with real graphics: " + game.error)
	Config.bind_gaps(game)
	game.bind_clock(Clock.new())
	game.bind_runtime(Runtime.new())
	game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	return game

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var fingerprint: String = package.pal98_graphics.metadata().source_fingerprint

	# Scenario A: the scene 1 entry runs 0x0078; the nested generation travels
	# to scene 2 (MAP12) and the outer script completes on the adopted lease.
	var source = _source_two(fingerprint,
		[[0x0059, 2, 0, 0], [0x0078, 0, 0, 0], [0x0001, 0, 0, 0]], [[0x0001, 0, 0, 0]])
	if source == null: check(false, "the two-scene synthetic source builds"); finish(args); return
	var holder = Pack.new(); holder.pal98_sources = source; holder.pal98_graphics = package.pal98_graphics
	var game = _assembly(holder)
	if game.error.is_empty():
		# The synthetic source's zeroed records cannot back real sprite cache
		# loads, so the chain runs on the load mask the diagnostic WIP pinned
		# (12) instead of the probe's full 29.
		var probe_input: Dictionary = Config.configuration()
		probe_input.globals.resource_flags = 12
		var fresh: Dictionary = game.new_state(0x12345, probe_input)
		check(not fresh.has("error"), "the probe initial state prepares: " + str(fresh.get("error", "")))
		if not fresh.has("error"):
			var done: Dictionary = game.begin()
			check(not done.has("error"), "the nested T212 reload completes: " + str(done.get("error", "")))
			if done.has("error"): finish(args); return
			check(game.enters_seen == [1, 2],
				"the outer chain entered scene 1 and the nested generation scene 2: " + str(game.enters_seen))
			check(done.state.globals.current_scene == 2 and done.state.globals.loaded_map_id == 12,
				"the adopted state rests on runtime scene 2 with MAP12 loaded")
			check(game.map_cache.get("map_id") == 12
				and game.map_cache.get("graphics_fingerprint") == game.cache.source().get("graphics_fingerprint"),
				"the nested map cache is adopted together with the returned scene state")
			check(game.nested_traces.size() == 1
				and "load_map_gop:12" in str(game.nested_traces[0])
				and "enter_script:2" in str(game.nested_traces[0]),
				"the nested generation keeps its own scene identity trace: " + str(game.nested_traces))
			check("load_map_gop:20" in str(done.get("trace", [])) and "enter_script:1" in str(done.get("trace", [])),
				"the outer generation keeps its own scene identity trace")
			var map12_receipts: Array = game.renderer.receipts().filter(func(r):
				return r.kind == "render_current_map_background" and r.map_id == 12)
			check(not map12_receipts.is_empty() and map12_receipts[0].frame_sha256 is String
				and map12_receipts[0].frame_sha256.length() == 64,
				"scene 2's background rendered through the nested chain's real pass")
			var stale: Dictionary = game.reload.resume("stale-generation-receipt", {"completed": true})
			check(stale.has("error"),
				"a stale receipt on the outer generation is refused by name: " + str(stale.get("error", "")))
	# Scenario B: a second nested call without an entry flag returns normally.
	var source_b = _source_two(fingerprint,
		[[0x0059, 2, 0, 0], [0x0078, 0, 0, 0], [0x0001, 0, 0, 0]],
		[[0x0078, 0, 0, 0], [0x0001, 0, 0, 0]])
	if source_b == null:
		check(false, "scenario B source builds"); finish(args); return
	var holder_b = Pack.new(); holder_b.pal98_sources = source_b; holder_b.pal98_graphics = package.pal98_graphics
	var game_b = _assembly(holder_b)
	if game_b.error.is_empty():
		var probe_b: Dictionary = Config.configuration()
		probe_b.globals.resource_flags = 12
		check(not game_b.new_state(0x12345, probe_b).has("error"), "scenario B state prepares")
		var done_b: Dictionary = game_b.begin()
		check(not done_b.has("error") and done_b.get("completed", false) and game_b.nested_traces.size() == 2,
			"a second nested T212 uses current caches and unwinds both call frames: " + str(done_b.get("error", "")))
	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_nested_t212_production",
		"scope": "production nested T212 generations through the new-game coordinator; synthetic two-scene sources with real graphics; probe initialization and named gaps",
		"checks": checks, "passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
