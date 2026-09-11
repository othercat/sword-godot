# SPDX-License-Identifier: MIT
extends RefCounted
## Internal arithmetic for the locked PAL.dll's ordinary RandomControl=0 path.
## Caller must establish policy/context and supply the live seed; no guessed
## startup seed, game-global RNG, poison override or implicit save admission.
const DLL_SHA256 = "3074423f2ea58529fd22b8e72a05ef289adf15a3b796841447e03db3417446ff"
const POLICY = "pal98.fixed-1.6.2.0.controlled-random.v1"
const MASK = 0xffffff

static func _dword(value) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 0xffffffff

static func create(live_seed) -> Dictionary:
	if not _dword(live_seed): return {"error": "An explicit known DWORD live seed is required"}
	return {"policy": POLICY, "live_seed": live_seed, "mirror_seed": null}

static func validate(state: Dictionary) -> String:
	if state.size() != 3 or state.get("policy") != POLICY or not _dword(state.get("live_seed")):
		return "Controlled RNG state shape, policy or live seed is invalid"
	if not state.has("mirror_seed") or (state.mirror_seed != null and not _dword(state.mirror_seed)):
		return "Controlled RNG mirror seed must be Unknown or a DWORD"
	return ""

static func _single(value: float) -> float:
	var bytes = PackedByteArray(); bytes.resize(4); bytes.encode_float(0, value)
	return bytes.decode_float(0)

static func randomize_r8(state: Dictionary, value) -> Dictionary:
	var issue = validate(state)
	if not issue.is_empty(): return {"error": issue}
	if typeof(value) != TYPE_FLOAT or not is_finite(value):
		return {"error": "Explicit Randomize requires a finite R8 value"}
	var bytes = PackedByteArray(); bytes.resize(8); bytes.encode_double(0, value)
	# With the saved ESI on the stack, original [esp+0xC] is the HIGH DWORD
	# of the R8 argument. Preserve both outer bytes of the previous live DWORD.
	var word: int = bytes.decode_u32(4)
	var mixed: int = ((word << 8) ^ (word >> 8)) & 0xffff00
	var next: Dictionary = state.duplicate(true)
	next.live_seed = (state.live_seed & 0xff0000ff) | mixed
	return {"state": next}

static func fresh_startup(hour, minute, second, millisecond) -> Dictionary:
	# Host supplies ONE local-clock sample. This is separate from the logical
	# game clock and only runs on process initialization, not every new game.
	var fields: Array = [hour, minute, second, millisecond]
	var limits: Array = [23, 59, 59, 999]
	for at in range(4):
		if typeof(fields[at]) != TYPE_INT or fields[at] < 0 or fields[at] > limits[at]:
			return {"error": "Startup requires explicit valid local hour/minute/second/millisecond"}
	var timer: float = _single(float((hour * 60 + minute) * 60 + second) + float(millisecond) * 0.001)
	# Fixed VB allocation writes 0x050000 before the observed initializer.
	# PAL constructs VT_R4(Timer), then explicit Randomize converts it to R8.
	var seeded = randomize_r8(create(0x050000), timer)
	return {"state": seeded.state, "timer_single": timer, "seed_before": 0x050000}

static func startup_from_epoch_msec(unix_msec, offset_minutes) -> Dictionary:
	if typeof(unix_msec) != TYPE_INT or typeof(offset_minutes) != TYPE_INT or offset_minutes < -1440 or offset_minutes > 1440:
		return {"error": "Startup clock requires integer epoch milliseconds and explicit UTC offset minutes"}
	# Reduce before adding the offset, so even int64 endpoint inputs cannot
	# overflow. Positive remainder also handles dates before the Unix epoch.
	var local_ms: int = ((unix_msec % 86400000) + offset_minutes * 60000 + 172800000) % 86400000
	var seconds: int = int(local_ms / 1000)
	return fresh_startup(int(seconds / 3600), int(seconds / 60) % 60, seconds % 60, local_ms % 1000)

static func capture_startup() -> Dictionary:
	# Portable host adapter, called once by the future original process owner.
	# UTC wall time supplies fractions; timezone bias supplies local time.
	# This wall clock must never become the game's authoritative logic clock.
	for attempt in range(3):
		var before: Dictionary = Time.get_time_zone_from_system()
		var unix_seconds: float = Time.get_unix_time_from_system()
		var after: Dictionary = Time.get_time_zone_from_system()
		if before.get("bias") != after.get("bias"): continue
		if not is_finite(unix_seconds) or absf(unix_seconds) > 4503599627370.0:
			return {"error": "System clock outside precise epoch-millisecond acquisition range"}
		var unix_msec: int = int(floor(unix_seconds * 1000.0))
		var result = startup_from_epoch_msec(unix_msec, after.get("bias"))
		if result.has("error"): return result
		result.clock_sample = {"unix_msec": unix_msec, "offset_minutes": after.bias}
		return result
	return {"error": "System timezone changed during startup clock acquisition"}

static func ordinary_next(state: Dictionary, context: String) -> Dictionary:
	var issue = validate(state)
	if not issue.is_empty(): return {"error": issue}
	if context != "ordinary": return {"error": "Only the explicitly ordinary controlled RNG context is implemented"}
	# The DLL initializes its local static from live VB state once. Later writes
	# to the live seed (for example Randomize) do not reset this mirror.
	var seed: int = state.live_seed if state.mirror_seed == null else state.mirror_seed
	var first: int = (seed * 0xfd43fd + 0xc39ec3) & MASK
	var second: int = (first * 0xfd43fd + 0xc39ec3) & MASK
	# The fixed instructions store Single after each SSE operation. roundf's
	# halfway rule differs from VB CInt. All values here are finite/nonnegative.
	var scaled: float = _single(float(second) / 16777216.0)
	scaled = _single(scaled * 10000000.0)
	var value: float = _single(floor(scaled + 0.5) / 10000000.0)
	value = clampf(value, 0.0, _single(0.9999999))
	var next: Dictionary = state.duplicate(true)
	next.live_seed = second; next.mirror_seed = second
	return {"state": next, "value": value, "intermediate_seed": first, "steps": 2}

static func _nearest_even(value: float) -> int:
	var lower: int = int(floor(value)); var fraction: float = value - float(lower)
	return lower + 1 if fraction > 0.5 or (fraction == 0.5 and (lower & 1) != 0) else lower

static func new_game_experience(state: Dictionary, base_levels: Array) -> Dictionary:
	var issue = validate(state)
	if not issue.is_empty(): return {"error": issue}
	if base_levels.size() != 5: return {"error": "Original startup requires five explicitly read role levels"}
	for level in base_levels:
		if typeof(level) != TYPE_INT or level < -32768 or level > 32767:
			return {"error": "Original role level must be a known signed I2"}
	var candidate: Dictionary = state.duplicate(true); var rows: Array = []
	for role in range(5):
		var categories: Array = []
		for category in range(8):
			var delta: int = 0; var count: int = 0
			if category != 0:
				var first = ordinary_next(candidate, "ordinary"); candidate = first.state
				# Single output is extended by x87: these short multiply/add
				# expressions are exact in double. Do not narrow them to Single.
				delta = _nearest_even(first.value * 2.0 + 2.0)
				var second = ordinary_next(candidate, "ordinary"); candidate = second.state
				count = _nearest_even(second.value * 20.0)
			var level: int = base_levels[role] + delta
			if level < -32768 or level > 32767:
				return {"error": "Original startup experience level AddI2 overflow", "role": role, "category": category}
			categories.append({"level": level, "count": count})
		rows.append(categories)
	# Logical projection, not the VB array descriptor, complete EXP record,
	# original save layout or a claim that unknown neighboring fields are zero.
	return {"state": candidate, "experience": rows, "rnd_calls": 70, "lcg_steps": 140}
