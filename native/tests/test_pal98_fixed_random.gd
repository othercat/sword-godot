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
	var timers_equal: bool = true
	for vector in oracle.timer_vectors:
		var f = vector.fields
		var actual = Random.fresh_startup(int(f[0]), int(f[1]), int(f[2]), int(f[3]))
		if actual.has("error") or actual.state.live_seed != int(vector.seed) or actual.state.mirror_seed != null or bits(actual.timer_single) != int(vector.timer_bits): timers_equal = false; break
	check(timers_equal and oracle.timer_vectors.size() == 14000, "14000 local Timer samples match exact Single rounding and high-DWORD startup mixing")
	var mix_equal: bool = true
	for vector in oracle.randomize_r8_vectors:
		var input = Random.create(int(vector.seed)); input.mirror_seed = 456
		var actual = Random.randomize_r8(input, float(vector.value))
		if actual.state.live_seed != int(vector.next) or actual.state.mirror_seed != 456 or input.live_seed != int(vector.seed): mix_equal = false
	check(mix_equal, "explicit R8 mixing preserves outer bytes, static mirror and input across signed and large values")
	var observed = Random.randomize_r8(Random.create(0x050000), 20117.587890625)
	check(observed.state.live_seed == 0xe5b600, "actual fixed-package Randomize sample: 050000 to E5B600 from VT_R4 bits469D2B2D")
	var end_day = Random.fresh_startup(23, 59, 59, 999)
	check(end_day.timer_single == 86400.0 and Random.fresh_startup(0, 0, 0, 0).state.live_seed == 0, "Single can round the final millisecond to86400 and midnight mixes zero")
	for f in [[-1, 0, 0, 0], [24, 0, 0, 0], [1, 60, 0, 0], [1, 0, 60, 0], [1, 0, 0, 1000], [1.0, 0, 0, 0], [1, 0, 0, null]]:
		check(Random.fresh_startup(f[0], f[1], f[2], f[3]).has("error"), "invalid or Unknown local clock fields diagnose: " + str(f))
	check(Random.randomize_r8(state, INF).has("error") and Random.randomize_r8(state, NAN).has("error") and Random.randomize_r8(state, 1).has("error"), "R8 rejects nonfinite or implicit numeric conversion")
	var clock_vectors: Array = [[0, 0, [0,0,0,0]], [-1, 0, [23,59,59,999]],
		[0,345,[5,45,0,0]], [0,-210,[20,30,0,0]], [86399999,480,[7,59,59,999]],
		[28800125,-480,[0,0,0,125]], [9223372036854775807,0,[7,12,55,807]],
		[-9223372036854775807-1,0,[16,47,4,192]]]
	var clocks_equal: bool = true
	for vector in clock_vectors:
		var f = vector[2]
		if Random.startup_from_epoch_msec(vector[0], vector[1]) != Random.fresh_startup(f[0],f[1],f[2],f[3]): clocks_equal = false
	check(clocks_equal, "epoch conversion handles offsets, midnight, pre-epoch and int64 endpoints without overflow")
	check(Random.startup_from_epoch_msec(0.0,0).has("error") and Random.startup_from_epoch_msec(0,null).has("error") and Random.startup_from_epoch_msec(0,1441).has("error"), "epoch and timezone require explicit valid integers")
	var clock_before: int = int(floor(Time.get_unix_time_from_system() * 1000.0))
	var captured = Random.capture_startup()
	var clock_after: int = int(floor(Time.get_unix_time_from_system() * 1000.0))
	check(not captured.has("error") and captured.clock_sample.unix_msec >= clock_before and captured.clock_sample.unix_msec <= clock_after, "actual host captures one bounded startup wall-clock sample")
	if not captured.has("error"):
		check(captured.state == Random.startup_from_epoch_msec(captured.clock_sample.unix_msec,captured.clock_sample.offset_minutes).state, "recorded host clock deterministically reproduces its initial RNG state")
	var out = FileAccess.open(args[1], FileAccess.WRITE)
	out.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "vectors": oracle.vectors.size(), "host_clock": captured, "original_gameplay": false, "native_save_acceptance": false}, "\t")); out.close()
	print("Fixed original RNG: ", checks.size(), " checks, ", failed, " failed"); quit(0 if failed == 0 else 1)
