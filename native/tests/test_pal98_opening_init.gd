# SPDX-License-Identifier: MIT
extends SceneTree
## The source-derived opening initializer: DATA3 base levels, the 70-call
## experience projection, both seed kinds and the named refusals. The chain
## replay still uses explicit probe gaps and nominal timers; this is not
## ordinary new-game acceptance and not physical input.
const ProbeConfig = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const NewGame = preload("res://src/native_pal98_new_game.gd")
const OpeningInit = preload("res://src/native_pal98_opening_init.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
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

## The still-unverified opening words stay explicit; only the probe keys the
## derivation owns are removed.
static func unverified_inputs() -> Dictionary:
	var probe: Dictionary = ProbeConfig.configuration()
	return {"globals": probe.globals, "dialogue": probe.dialogue,
		"party_trail": probe.party_trail, "inventory_bytes": probe.inventory_bytes}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return

	# Named refusals before any success path.
	var refused = NewGame.new()
	check(refused.open(package), "refusal owner binds")
	check(not refused.new_state_from_source(1, "guess", unverified_inputs()).get("completed", false)
		and refused.error.contains("seed kind must be explicit_replay or startup_capture"),
		"an unknown seed kind is refused by name: " + refused.error)
	check(not refused.new_state_from_source(-1, "explicit_replay", unverified_inputs()).get("completed", false)
		and refused.error.contains("DWORD"),
		"an out-of-DWORD replay seed is refused by name: " + refused.error)
	var missing: Dictionary = unverified_inputs(); missing.erase("dialogue")
	check(not refused.new_state_from_source(1, "explicit_replay", missing).get("completed", false)
		and refused.error.contains("unverified opening input requires dialogue"),
		"a missing unverified opening input is refused by name: " + refused.error)
	check(OpeningInit.base_levels([0, 0, 0]).has("error"),
		"a short DATA3 backing is refused by name")
	var fresh_rng: Dictionary = Random.create(7)
	var overflow: Dictionary = Random.new_game_experience(fresh_rng, [40000, 1, 1, 1, 1])
	check(overflow.has("error") and str(overflow.error).contains("signed I2"),
		"an out-of-I2 base level is refused by name with no partial projection: " + str(overflow.get("error", "")))

	# Explicit replay derivation on the admitted package.
	var game = _assembly(package)
	var replay: Dictionary = game.new_state_from_source(0x12345, "explicit_replay", unverified_inputs())
	check(not replay.has("error"), "the replay-derived opening state prepares: " + str(replay.get("error", "")))
	if replay.has("error"): finish(args); return
	check(replay.experience.size() == 5 and replay.experience[0].size() == 8,
		"the experience projection is the 5x8 SubMain shape")
	var receipt: Dictionary = replay.rng_source
	check(receipt.rnd_calls == 70 and receipt.lcg_steps == 140,
		"the projection consumed exactly 70 calls / 140 LCG steps")
	check(receipt.base_levels == [1, 5, 3, 48, 28],
		"roles0..4 base levels read from DATA3 field 6 match the documented disk table: " + str(receipt.base_levels))
	check(receipt.seed.kind == "explicit_replay" and receipt.seed.seed == 0x12345,
		"the replay seed kind and value are recorded in the receipt")
	check(receipt.get("data3_sha256", "").length() == 64,
		"the receipt binds the DATA3 source identity")
	check(replay.rng.mirror_seed != null,
		"both controlled seeds are written after the projection")
	check(replay.experience[0][0].level == 1 and replay.experience[4][0].level == 28,
		"category 0 keeps the DATA3 base level without consuming random values")
	check(replay.rng_source.level_source == "data3_field6_roles0_4",
		"the receipt names the DATA3 field-6 level source")
	var backing_words: Array = replay.equipment.role_words
	check(((backing_words[7 * 6 + 0] + 32768) & 65535) - 32768 == 150
		and ((backing_words[10 * 6 + 0] + 32768) & 65535) - 32768 == 100,
		"role 0's vitals backing stays the same-source DATA3 values")
	check(replay.party_records.size() == 1 and replay.party_records[0].role_id == 0
		and replay.party_records[0].x == 160 and replay.party_records[0].y == 112,
		"the derived opening party is role 0 at the carried party-in-viewport anchor")
	check(not replay.has("roles"), "the probe-only roles key is consumed by the derivation")

	# Determinism: same replay seed reproduces the projection byte-for-byte;
	# a different seed moves the random categories but never category 0.
	var game2 = NewGame.new()
	check(game2.open(package), "second owner binds")
	var replay2: Dictionary = game2.new_state_from_source(0x12345, "explicit_replay", unverified_inputs())
	check(not replay2.has("error") and replay2.experience == replay.experience
		and replay2.rng == replay.rng,
		"the same replay seed reproduces the projection and RNG state exactly")
	var game3 = NewGame.new()
	check(game3.open(package), "third owner binds")
	var other: Dictionary = game3.new_state_from_source(0x54321, "explicit_replay", unverified_inputs())
	var moved := false
	if not other.has("error"):
		for role in range(5):
			for category in range(1, 8):
				if other.experience[role][category].level != replay.experience[role][category].level:
					moved = true
	check(not other.has("error") and moved,
		"a different replay seed moves the random categories")
	check(not other.has("error") and other.experience[0][0].level == 1 and other.experience[4][0].level == 28,
		"category 0 stays the DATA3 base level under any seed")

	# Startup capture: one real host clock sample, recorded with its identity.
	var captured_game = NewGame.new()
	check(captured_game.open(package), "capture owner binds")
	var captured: Dictionary = captured_game.new_state_from_source(0, "startup_capture", unverified_inputs())
	check(not captured.has("error"), "the startup-capture opening state prepares: " + str(captured.get("error", "")))
	var capture_receipt: Dictionary = captured.get("rng_source", {}) if not captured.has("error") else {}
	check(capture_receipt.get("seed", {}).get("kind") == "startup_capture"
		and capture_receipt.seed.get("clock_sample", {}).get("unix_msec") is int
		and capture_receipt.seed.clock_sample.get("offset_minutes") is int,
		"the startup capture records one real host clock sample with its identity")
	var derived_again: Dictionary = OpeningInit.derive(captured.equipment.role_words, captured.rng, capture_receipt.seed)
	var derived_thrice: Dictionary = OpeningInit.derive(captured.equipment.role_words, captured.rng, capture_receipt.seed)
	check(not derived_again.has("error") and derived_again.experience == derived_thrice.experience,
		"deriving from one recorded captured state is reproducible")

	# The full chain through the derived state reaches the same named rest as
	# the probe path, and the probe path is unchanged.
	var game4 = _assembly(package)
	check(not game4.new_state_from_source(0x12345, "explicit_replay", unverified_inputs()).has("error"),
		"the chain owner takes the derived state")
	var chained: Dictionary = ProbeConfig.run(game4)
	check(not chained.has("error") and chained.enters == [1, 2],
		"the derived opening chain completes to the scene 2 rest: " + str(chained.get("error", "")) + str(chained.get("enters", [])))
	if chained.has("error"): finish(args); return
	check("load_map_gop:20" in chained.trace and "load_map_gop:12" in chained.trace,
		"the derived chain loads both scenes' own map identities: " + str(chained.trace))
	check(chained.state.globals.current_scene == 2 and chained.state.globals.loaded_map_id == 12,
		"the derived chain rests on runtime scene 2 with its map loaded")
	var opening_globals: Dictionary = game4.terminals[0].get("state", {}).get("globals", {})
	check(opening_globals.get("viewport_x") == 864 and opening_globals.get("viewport_y") == 912
		and opening_globals.get("world_x") == 1024 and opening_globals.get("world_y") == 1024,
		"the opening entry's own terminal still carries the original world and viewport words")
	check(game4.state.experience == replay.experience,
		"the projection survives the chain unchanged")
	var probe_game = _assembly(package)
	check(not probe_game.new_state(0x12345, ProbeConfig.configuration()).has("error"),
		"the explicit probe path still prepares unchanged")
	var probe_run: Dictionary = ProbeConfig.run(probe_game)
	check(not probe_run.has("error") and probe_run.get("trace", []) == chained.trace,
		"the derived and probe chains leave the same trace: " + str(probe_run.get("error", "")))

	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_opening_init",
		"scope": "source-derived opening initializer; explicit replay and startup-capture seeds; chain replay with explicit probe gaps",
		"checks": checks, "passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
