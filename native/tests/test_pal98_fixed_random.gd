# SPDX-License-Identifier: MIT
extends SceneTree
const Random = preload("res://src/native_pal98_fixed_random.gd")
var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func bits(value: float) -> int:
	var bytes = PackedByteArray(); bytes.resize(4); bytes.encode_float(0, value)
	return bytes.decode_u32(0)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var oracle = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not oracle is Dictionary or not oracle.has("vectors") or not oracle.has("sequences"): quit(2); return
	check(oracle.authority["PAL.dll"] == Random.DLL_SHA256, "numeric oracle binds the observed fixed DLL")
	var equal: bool = true
	for vector in oracle.vectors:
		var state = Random.create(int(vector.seed)); var before = state.duplicate(true)
		var actual = Random.ordinary_next(state, "ordinary")
		if actual.has("error") or actual.state.live_seed != int(vector.next) or actual.state.mirror_seed != int(vector.next) or actual.intermediate_seed != int(vector.intermediate) or bits(actual.value) != int(vector.value_bits) or state != before: equal = false; break
	check(equal and oracle.vectors.size() > 1000, "exact Single bits, both LCG steps and input preservation across rational boundary/spread vectors")
	for sequence in oracle.sequences:
		var state = Random.create(int(sequence.initial)); var sequence_equal: bool = true
		for call in sequence.calls:
			var actual = Random.ordinary_next(state, "ordinary"); state = actual.state
			if state.live_seed != int(call.next) or bits(actual.value) != int(call.value_bits): sequence_equal = false
		check(sequence_equal and state.live_seed == int(sequence.final), "complete70-call sequence from explicit seed " + str(int(sequence.initial)))
		var levels: Array = []
		for level in sequence.base_levels: levels.append(int(level))
		var experience = Random.new_game_experience(Random.create(int(sequence.initial)), levels)
		var match_rows: bool = not experience.has("error")
		if match_rows:
			for role in range(5):
				for category in range(8):
					var actual = experience.experience[role][category]; var expected = sequence.experience[role][category]
					if actual.level != int(expected.level) or actual.count != int(expected.count): match_rows = false
		check(match_rows and experience.state == state and experience.rnd_calls == 70 and experience.lcg_steps == 140, "five-by-eight experience and exact next RNG state from seed " + str(int(sequence.initial)))
	for invalid in [null, -1, 0x100000000, 0.0, "0", true]:
		check(Random.create(invalid).has("error"), "reject Unknown/non-DWORD seed " + str(invalid))
	var state = Random.create(123); var next = Random.ordinary_next(state, "ordinary").state
	var altered = next.duplicate(true); altered.live_seed = 0xffffffff
	check(Random.ordinary_next(altered, "ordinary") == Random.ordinary_next(next, "ordinary"), "later live VB seed changes do not reinitialize the DLL static mirror")
	check(Random.ordinary_next(next.duplicate(true), "ordinary") == Random.ordinary_next(next, "ordinary"), "detached internal checkpoint preserves both seed identities")
	for context in ["", "poison", "mode1", "forced"]:
		check(Random.ordinary_next(state, context).has("error"), "unimplemented RNG context diagnoses: " + context)
	var invalid_state = state.duplicate(true); invalid_state.erase("mirror_seed")
	check(Random.ordinary_next(invalid_state, "ordinary").has("error"), "missing mirror does not masquerade as initial Unknown")
	invalid_state = state.duplicate(true); invalid_state.mirror_seed = 1.0
	check(Random.ordinary_next(invalid_state, "ordinary").has("error"), "mirror seed does not accept implicit float conversion")
	invalid_state = state.duplicate(true); invalid_state.policy = "another"
	check(Random.new_game_experience(invalid_state, [1, 1, 1, 1, 1]).has("error"), "new-game state retains policy binding")
	var before = state.duplicate(true)
	check(Random.new_game_experience(state, [32767, 1, 1, 1, 1]).has("error") and state == before, "checked experience I2 overflow publishes no partial rows or RNG consumption")
	check(Random.new_game_experience(state, [1, 1, 1, 1]).has("error") and Random.new_game_experience(state, [1, 1, 1, 1, null]).has("error") and Random.new_game_experience(state, [1, 1, 1, 1, 1.0]).has("error"), "explicit five signed role levels required")
	check(Random._nearest_even(2.5) == 2 and Random._nearest_even(3.5) == 4 and Random._nearest_even(0.5) == 0 and Random._nearest_even(19.5) == 20, "VB CInt ties round to even, independently of roundf")
	var out = FileAccess.open(args[1], FileAccess.WRITE)
	out.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "vectors": oracle.vectors.size(), "original_gameplay": false, "native_save_acceptance": false}, "\t")); out.close()
	print("Fixed original RNG: ", checks.size(), " checks, ", failed, " failed"); quit(0 if failed == 0 else 1)
