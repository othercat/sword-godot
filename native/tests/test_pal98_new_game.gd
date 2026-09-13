# SPDX-License-Identifier: MIT
extends SceneTree
## Coordinator replay with explicit probe initialization, nominal timers and
## injected skip/confirm presses; it is not ordinary new-game acceptance.
## Glyph, audio, T121, RGM, event movement and frame helpers remain explicit doubles.
const ProbeConfig = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const NewGame = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")

class ReplayClock:
	var frame := 0
	func consume(units: int) -> Dictionary:
		frame += units
		return {"consumed": units, "total": frame}

class ReplayRuntime:
	var pumps := 0
	func answer(request: Dictionary) -> Dictionary:
		if request.kind == "fade_event_pump": pumps += 1; return {"completed": true, "pumped": request.events}
		return {"completed": true}

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _assembly(package):
	var game = NewGame.new()
	check(game.open(package), "package binds: " + game.error)
	ProbeConfig.bind_gaps(game)
	game.bind_clock(ReplayClock.new())
	game.bind_runtime(ReplayRuntime.new())
	game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	return game

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return

	var game = _assembly(package)
	var begun: Dictionary = {}
	if game.error.is_empty():
		var fresh: Dictionary = game.new_state(0x12345, ProbeConfig.configuration())
		check(not fresh.has("error"), "the explicit probe initial state prepares: " + str(fresh.get("error", "")))
		if fresh.has("error"): finish(args); return
		check(fresh.globals.requested_scene == 1 and fresh.globals.resource_flags == 29,
			"the opening scene and the new-game load mask are explicit probe inputs")
		check(fresh.globals.ffxy_max_x == 1696 and fresh.globals.ffxy_max_y == 1840,
			"the MAP20 viewport limit pair carries the original bounds")
		check(fresh.party_records.size() == 1 and fresh.party_records[0].role_id == 0
			and fresh.party_records[0].x == 160 and fresh.party_records[0].y == 112,
			"the opening party is role 0 at the original party-in-viewport anchor")
		check(fresh.party_trail.size() == 5 and fresh.party_trail[0].x == 0,
			"the walk trail is the named zeroed Native representation")
		check(fresh.inventory_bytes.size() == 1536 and fresh.inventory_bytes[0] == 0,
			"the inventory starts as the empty 1536-byte backing")
		check(fresh.equipment.party_roles == [0],
			"the equipment kernel derives the opening party from the real tables")
		var day: PackedByteArray = package.pal98_graphics.open_records().palette(0, 0).value
		check(game.executor.installed_rgb6() == day,
			"the cold display palette installs byte-identical to the admitted day variant")

		begun = ProbeConfig.run(game)
		check(not begun.has("error") and begun.enters == [1, 2],
			"the intro chains scene 1 into its own scene 2 and rests: "
				+ str(begun.get("error", "")) + str(begun.get("enters", [])))
		if begun.has("error"):
			finish(args); return
		check("load_map_gop:20" in begun.trace and "load_map_gop:12" in begun.trace,
			"the chain loads both scenes' own map identities: " + str(begun.trace))
		var resting: Dictionary = begun.state.globals
		check(resting.current_scene == 2 and resting.loaded_map_id == 12,
			"the new game rests on runtime scene 2 with its map loaded")
		var opening_state: Dictionary = game.terminals[0].get("state", {}).get("globals", {})
		check(opening_state.get("viewport_x") == 864 and opening_state.get("viewport_y") == 912
			and opening_state.get("world_x") == 1024 and opening_state.get("world_y") == 1024,
			"the opening entry's own terminal carries the original world and viewport words")
		var opening: Dictionary = game.terminals[0]
		var sprite_word := 0
		for effect in opening.get("effects", []):
			if effect.get("sprite_word") is int: sprite_word = effect.sprite_word
		check(sprite_word == 193, "the opening entry's own effect carries the 193 map sprite")

		# One real input tick on the resting state: the outcome must agree with
		# the real collision probe, and the draw requests must carry the state.
		var right: PackedInt32Array = PackedInt32Array([0, 0, 0, 2, 0, 0, 0, 0, 0])
		var world_x: int = resting.world_x; var world_y: int = resting.world_y
		var free: Dictionary = game.probe.probe(world_x + 16, world_y + 8)
		check(not free.has("error"), "the candidate probe answers: " + str(free.get("error", "")))
		var ticked: Dictionary = game.tick(right)
		check(not ticked.has("error"), "the input tick completes on the resting state: " + str(ticked.get("error", "")))
		if ticked.has("error"): finish(args); return
		check(ticked.input_move == free.get("accepted", false),
			"the tick's move decision agrees with the real collision probe")
		var party_requests: Array = ticked.requests.filter(func(r): return r.kind == "party")
		check(party_requests.size() == 1 and party_requests[0].get("screen_x") == ticked.state.party_records[0].x,
			"the tick publishes the T209 request from the ticked state")
		var still: Dictionary = game.tick(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
		check(not still.has("error") and still.input_move == false
			and still.state.globals.viewport_x == ticked.state.globals.viewport_x,
			"an empty-input tick stays put and still publishes the frame")
	else:
		finish(args); return

	# Reopen: fresh package load and fresh owners repeat the intro exactly.
	var reopened = Package.new()
	if not reopened.load_package(args[0]): push_error("reopen rejected"); quit(2); return
	var game2 = _assembly(reopened)
	game2.new_state(0x12345, ProbeConfig.configuration())
	var begun2: Dictionary = ProbeConfig.run(game2)
	check(not begun2.has("error") and begun2.enters == [1, 2]
		and begun2.trace == begun.trace,
		"the fresh-owner reopen repeats the intro trace exactly")
	check(game2.terminals.size() == game.terminals.size()
		and game2.terminals[1].get("effects", []) == game.terminals[1].get("effects", []),
		"the reopen reproduces the scene 2 entry effects byte-for-byte")
	check(game2.renderer.receipts() == game.renderer.receipts(),
		"the reopen reproduces the background renders byte-for-byte")

	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_new_game",
		"scope": "internal coordinator; synthetic initializer and nominal clock; glyph/audio/T121/frame policies are doubles",
		"checks": checks, "passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
