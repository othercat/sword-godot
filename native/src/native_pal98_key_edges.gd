# SPDX-License-Identifier: MIT
extends RefCounted
## Window-local input, sampled by the logical tick rather than global Input.
var held: Dictionary = {}
var suppressed: Dictionary = {}
var pending: Dictionary = {}
var sampled: Dictionary = {}
var generation := 0

func clear() -> void:
	for identity in held: suppressed[identity] = true
	held.clear(); pending.clear(); sampled.clear(); generation += 1

func accept(identity: int, action: String, pressed: bool, echo: bool, stamp: int) -> void:
	if identity < 0 or action.is_empty() or echo: return
	if suppressed.has(identity):
		if not pressed: suppressed.erase(identity)
		return
	if pressed == held.has(identity): return
	var before := held.values().has(action)
	if pressed: held[identity] = action
	else: held.erase(identity)
	var after := held.values().has(action)
	if before == after: return
	if not pending.has(action): pending[action] = []
	pending[action].append({"down":after,"stamp":stamp,"generation":generation})

func level(action: String) -> int:
	if pending.has(action) and not pending[action].is_empty():
		var edge: Dictionary = pending[action].pop_front()
		sampled[action] = edge.down
		return 2 if edge.down else 1
	return 3 if sampled.get(action,false) else 0
