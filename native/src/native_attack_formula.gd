# SPDX-License-Identifier: MIT
extends RefCounted
## Deterministic base-curve adaptation, not complete PAL98 ordinary combat.
const KEY = "pal.native.attack-formula"
const SCHEMA = "pal.native.attack-formula.v1"
const CAPABILITY = "battle.attack-formula.v1"
const PROFILE = "pal98.base-physical.v1"

static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	if package.world.get("encounters", []).is_empty() or not package.world.nodes.any(func(n): return n.op == "battle"):
		return "attack formula requires an authored battle"
	return ""

static func base_damage(attack: int, defense: int) -> int:
	# For nonnegative integer D, 3D/5 has no half-integer ties. Keep the
	# arithmetic wide and exact; legacy I2 overflow is deliberately not emulated.
	var threshold: int = (3 * defense + 2) / 5
	if attack <= threshold: return 0
	return (attack - threshold + maxi(0, attack - defense)) / 2

static func ordinary(content: Dictionary, attack: int, defense: int, party_source: bool, guarded: bool) -> int:
	if not used(content):
		var old: int = maxi(1, attack - defense)
		return (old + 1) >> 1 if guarded else old
	var effective_defense: int = defense * 2 if guarded and not party_source else defense
	var base: int = base_damage(attack, effective_defense)
	return base * 2 if party_source else base
