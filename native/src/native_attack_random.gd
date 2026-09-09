# SPDX-License-Identifier: MIT
extends RefCounted
## Explicit partial player-hit profile. Existing formulas remain immutable.
const KEY = "pal.native.attack-random"
const SCHEMA = "pal.native.attack-random.v1"
const CAPABILITY = "battle.attack-random.v1"
const PROFILE = "pal98.player-hit.v1"
const Rng = preload("res://src/native_rng.gd")
const Formula = preload("res://src/native_attack_formula.gd")
const Statuses = preload("res://src/native_statuses.gd")

static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)

static func rule(content: Dictionary) -> Variant:
	if not used(content): return null
	var value: Dictionary = content.extensions[KEY]
	return {"profile":value.profile, "seed":value.seed, "critical_status_id":value.critical_status_id, "bonus_actor_definitions":value.bonus_actor_definitions}

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var value = package.world.extensions[KEY]
	var issue: String = package.schema.validate(SCHEMA, value)
	if not issue.is_empty(): return issue
	if not Formula.used(package.world): return "attack random requires the base physical formula"
	for id in value.bonus_actor_definitions:
		if not package.index.actor_definitions.has(id): return "attack random: unknown bonus actor definition"
	if value.critical_status_id != null and not package.index.status_definitions.has(value.critical_status_id): return "attack random: unknown critical status"
	return ""

static func initial(content: Dictionary) -> Dictionary:
	return Rng.initial(int(content.extensions[KEY].seed)) if used(content) else {"algorithm":"pal.native.unused.v1", "state":"unused"}

static func validate_state(content: Dictionary, state: Dictionary) -> String:
	if not used(content): return "" if state.rng == initial(content) else "unsupported unused random state"
	return Rng.validate(state.rng, int(content.extensions[KEY].seed), 1 if content.extensions.has("pal.native.player-physical") else 4)

static func nearest_even(numerator: int, denominator: int) -> int:
	var whole: int = numerator / denominator
	var remainder: int = numerator % denominator
	return whole + (1 if remainder * 2 > denominator or (remainder * 2 == denominator and whole % 2 != 0) else 0)

static func vary(base: int, rolls: Array, force_critical: bool, bonus: bool) -> int:
	var den: int = Rng.DENOMINATOR
	var damage: int = base + nearest_even(den + int(rolls[0]), den)
	if int(rolls[1]) * 6 / den == 3 or force_critical: damage *= 3
	# Quotient/remainder decomposition keeps multiplication below 2^51 even
	# for large Native stats; rounding applies to the entire resulting damage.
	var scale: int = den * 8
	var product: int = (damage % scale) * int(rolls[2])
	var whole: int = damage + (damage / scale) * int(rolls[2]) + product / scale
	var remainder: int = product % scale
	damage = whole + (1 if remainder * 2 > scale or (remainder * 2 == scale and whole % 2 != 0) else 0)
	if int(rolls[3]) * 12 / den == 3 and bonus: damage *= 2
	return damage

static func apply(package, state: Dictionary, source: Dictionary, damage: int) -> Dictionary:
	if not used(package.world): return {"damage":damage}
	var issue: String = validate_state(package.world, state)
	if not issue.is_empty(): return {"error":issue}
	var drawn: Dictionary = Rng.draw_four(state.rng)
	if drawn.has("error"): return drawn
	var value: Dictionary = package.world.extensions[KEY]
	var forced: bool = value.critical_status_id != null and not Statuses.find(state,source.instance_id,value.critical_status_id).is_empty()
	return {"damage":vary(damage,drawn.rolls,forced,source.definition_id in value.bonus_actor_definitions)}
