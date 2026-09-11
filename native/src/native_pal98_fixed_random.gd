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
