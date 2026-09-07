# SPDX-License-Identifier: MIT
extends RefCounted
## Input sampling policy; no positions, collision, or rendering state live here.
const KEYS = {KEY_UP: "up", KEY_W: "up", KEY_DOWN: "down", KEY_S: "down", KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right"}
const DIRECTIONS = {"up": Vector2i.UP, "down": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT}
var _keys: Dictionary = {}
var _previous: Dictionary = {}

func clear() -> void:
	_keys.clear()
	_previous.clear()

func key_event(code: int, pressed: bool, echo: bool = false) -> void:
	if not KEYS.has(code) or echo: return
	if pressed: _keys[code] = true
	else:
		_keys.erase(code)
		var direction: String = KEYS[code]
		# Preserve a release/repress edge between cadence samples, but a second
		# physical alias does not count as a new logical direction.
		if not _keys.keys().any(func(key): return KEYS[key] == direction): _previous.erase(direction)

func sample(rule: String) -> Vector2i:
	var current: Dictionary = {}
	for code in _keys: current[KEYS[code]] = true
	var selected: String = ""
	if rule == "pal.walk.v1":
		for name in ["right", "left", "down", "up"]:
			if current.has(name) and not _previous.has(name):
				selected = name
				break
		if selected.is_empty() and current.size() == 1: selected = current.keys()[0]
	else:
		for name in ["left", "right", "up", "down"]:
			if current.has(name):
				selected = name
				break
	_previous = current
	return DIRECTIONS.get(selected, Vector2i.ZERO)
