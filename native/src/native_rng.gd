# SPDX-License-Identifier: MIT
extends RefCounted
## Versioned gameplay stream. Never called by presentation or wall-clock code.
const ALGORITHM = "pal.native.lcg24.v1"
const MAX_DRAWS = 4294967292
const MASK = 0xffffff
const DENOMINATOR = 16777216

static func initial(seed: int) -> Dictionary:
	return {"algorithm": ALGORITHM, "state": "%06x:0" % seed}

static func advance(seed: int, count: int) -> int:
	var multiplier: int = 0xfd43fd
	var increment: int = 0xc39ec3
	while count > 0:
		if count & 1: seed = (seed * multiplier + increment) & MASK
		increment = (increment * (multiplier + 1)) & MASK
		multiplier = (multiplier * multiplier) & MASK
		count >>= 1
	return seed

static func validate(value: Variant, initial_seed: int) -> String:
	if not value is Dictionary or value.size() != 2 or value.get("algorithm") != ALGORITHM or not value.get("state") is String:
		return "unsupported gameplay random algorithm"
	var pattern = RegEx.new(); pattern.compile("^[0-9a-f]{6}:(0|[1-9][0-9]{0,9})$")
	var cursor: String = value.state
	if pattern.search(cursor) == null or cursor.ends_with("\n"): return "noncanonical random cursor"
	var parts: PackedStringArray = cursor.split(":")
	var count: int = parts[1].to_int()
	if count > MAX_DRAWS or count % 4 != 0: return "random draw count outside profile boundary"
	if parts[0].hex_to_int() != advance(initial_seed, count): return "random seed does not match authored seed and cursor"
	return ""

static func draw_four(value: Dictionary) -> Dictionary:
	# Caller has validated the stream and owns a transactional state candidate.
	var parts: PackedStringArray = value.state.split(":")
	var seed: int = parts[0].hex_to_int()
	var count: int = parts[1].to_int()
	if count > MAX_DRAWS - 4: return {"error": "随机序列已达到当前规则上限；本次行动保留原状态。"}
	var rolls: Array = []
	for i in range(4):
		seed = (seed * 0xfd43fd + 0xc39ec3) & MASK
		rolls.append(seed)
	value.state = "%06x:%d" % [seed, count + 4]
	return {"rolls": rolls}
