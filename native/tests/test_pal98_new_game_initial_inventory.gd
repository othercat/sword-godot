# SPDX-License-Identifier: MIT
extends SceneTree
## The new-game initial inventory is source-derived from the recovered T156
## clearing instead of an unverified caller input; an explicit inventory is
## accepted only when it is already T156-consistent. The chain replay still
## uses explicit probe gaps and nominal timers; this is not ordinary
## new-game acceptance and not physical input.
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

static func unverified_inputs(with_inventory: bool) -> Dictionary:
	var probe: Dictionary = ProbeConfig.configuration()
	var inputs: Dictionary = {"globals": probe.globals, "dialogue": probe.dialogue,
		"party_trail": probe.party_trail}
	if with_inventory: inputs.inventory_bytes = probe.inventory_bytes
	return inputs

static func fully_zero(bytes: PackedByteArray) -> bool:
	for byte in bytes:
		if byte != 0: return false
	return true

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return

	# The derivation: no caller inventory at all.
	var game = _assembly(package)
	var derived: Dictionary = game.new_state_from_source(0x12345, "explicit_replay", unverified_inputs(false))
	check(not derived.has("error"), "the opening state prepares without any caller inventory: " + str(derived.get("error", "")))
	if derived.has("error"): finish(args); return
	check(derived.inventory_bytes.size() == 1536 and fully_zero(derived.inventory_bytes),
		"the derived opening inventory is the fully cleared 256-slot backing")

	# Illegal values are refused by name before any state is published.
	var malformed = NewGame.new()
	check(malformed.open(package), "refusal owner binds")
	var short_input: Dictionary = unverified_inputs(false)
	short_input.inventory_bytes = PackedByteArray()
	check(not malformed.new_state_from_source(1, "explicit_replay", short_input).get("completed", false)
		and malformed.error.contains("requires 1536 six-byte records"),
		"a wrong-shape explicit inventory is refused by name: " + malformed.error)
	var carrying: Dictionary = unverified_inputs(false)
	var bag := PackedByteArray(); bag.resize(1536); bag.encode_u16(3 * 6 + 4, 1)
	carrying.inventory_bytes = bag
	var refusing = NewGame.new()
	check(refusing.open(package), "second refusal owner binds")
	check(not refusing.new_state_from_source(1, "explicit_replay", carrying).get("completed", false)
		and refusing.error.contains("T156-cleared initial state"),
		"an in-use slot is refused as contradicting the T156-cleared initial state: " + refusing.error)

	# T156 clears only the in-use word: dead record bytes stay caller-known
	# input and are accepted, never renamed as derived facts.
	var consistent: Dictionary = unverified_inputs(false)
	var stale := PackedByteArray(); stale.resize(1536)
	stale.encode_u16(2 * 6, 31); stale.encode_u16(2 * 6 + 2, 1)
	consistent.inventory_bytes = stale
	var keeper = NewGame.new()
	check(keeper.open(package), "third owner binds")
	var adopted: Dictionary = keeper.new_state_from_source(1, "explicit_replay", consistent)
	check(not adopted.has("error") and adopted.inventory_bytes.decode_u16(2 * 6) == 31
		and adopted.inventory_bytes.decode_u16(2 * 6 + 4) == 0,
		"a T156-consistent explicit inventory is adopted with its dead record intact: " + str(adopted.get("error", "")))

	# The derived state runs the real opening chain to the named scene-2 rest.
	var chained_game = _assembly(package)
	check(not chained_game.new_state_from_source(0x12345, "explicit_replay", unverified_inputs(false)).has("error"),
		"the chain owner takes the inventory-free derivation")
	var chained: Dictionary = ProbeConfig.run(chained_game)
	check(not chained.has("error") and chained.enters == [1, 2],
		"the derived opening chain rests at scene 2: " + str(chained.get("error", "")) + str(chained.get("enters", [])))
	if chained.has("error"): finish(args); return
	check(fully_zero(chained.state.inventory_bytes),
		"the post-chain inventory stays fully cleared")
	check(chained.state.equipment.party_roles == [0],
		"the equipment phase rebuilt the opening party over the derived bag")

	# The explicit probe path is unchanged: it still demands its inventory.
	var probe_game = _assembly(package)
	var probe_missing: Dictionary = ProbeConfig.configuration()
	probe_missing.erase("inventory_bytes")
	var refused_probe: Dictionary = probe_game.new_state(1, probe_missing)
	check(refused_probe.has("error") and refused_probe.error.contains("explicit probe inventory required"),
		"the probe path still requires its explicit inventory: " + str(refused_probe.get("error", "")))

	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_new_game_initial_inventory",
		"scope": "T156-derived new-game initial inventory; named refusals for inconsistent explicit bags; chain replay with explicit probe gaps",
		"checks": checks, "passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
