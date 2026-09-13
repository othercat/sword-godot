# SPDX-License-Identifier: MIT
extends RefCounted
## Source-backed new-game opening derivation. Base levels are read from the
## admitted DATA3 role backing that the equipment kernel already parsed, then
## SubMain's 70-call experience projection runs on the caller's RNG state.
## The still-unverified opening words (globals, dialogue, trail, inventory)
## stay explicit caller inputs elsewhere; nothing here renames a probe value
## as a recovered original initialization.
const Random = preload("res://src/native_pal98_fixed_random.gd")

## T254 evidence: level-up performs a checked +1 on role field 6 before the
## G07BC Level write, so field 6 is the stored base level.
const LEVEL_FIELD := 6
## SubMain's projection iterates roles0..4 only; the sixth disk role is not read.
const EXPERIENCE_ROLES := 5
const ROLE_WORDS := 450

static func _signed_i2(word: int) -> int:
	return ((int(word) + 32768) & 65535) - 32768

## Base levels for roles0..4, read field-major from the kernel's DATA3 words.
## The documented original disk table pins roles0..5 at 1/5/3/48/28/40; a test
## must pin the admitted package against that table. A modified author package
## keeps its own source values instead of the original numbers.
static func base_levels(role_words: Array) -> Dictionary:
	if role_words.size() != ROLE_WORDS:
		return {"error": "opening init requires the full 450-word DATA3 role backing"}
	var levels: Array = []
	for role in range(EXPERIENCE_ROLES):
		var word = role_words[LEVEL_FIELD * 6 + role]
		if typeof(word) != TYPE_INT or word < 0 or word > 65535:
			return {"error": "DATA3 level backing is not a stored WORD", "role": role}
		levels.append(_signed_i2(word))
	return {"levels": levels}

## One derivation receipt: DATA3 base levels plus the 70-call experience
## projection over the caller's controlled RNG state. Failure returns no
## partial projection and no consumed RNG state.
static func derive(role_words: Array, rng_state: Dictionary, seed_receipt: Dictionary) -> Dictionary:
	var levels: Dictionary = base_levels(role_words)
	if levels.has("error"): return levels
	var projection: Dictionary = Random.new_game_experience(rng_state, levels.levels)
	if projection.has("error"): return projection
	return {"experience": projection.experience, "rng": projection.state,
		"receipt": {"rnd_calls": projection.rnd_calls, "lcg_steps": projection.lcg_steps,
			"base_levels": levels.levels, "level_source": "data3_field6_roles0_4",
			"seed": seed_receipt}}
