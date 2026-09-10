# SPDX-License-Identifier: MIT
extends RefCounted
## Explicit subset of the pinned MIT contracts; not a general schema engine.
const Reader = preload("res://src/native_json.gd")
const KEYWORDS = ["$schema", "$id", "$ref", "x-status", "title", "description", "definitions", "type", "required", "properties", "additionalProperties", "items", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength", "pattern", "minimum", "maximum", "const", "enum", "oneOf", "anyOf"]
var schemas: Dictionary = {}
var hashes: Dictionary = {}
var error: String = ""

func _init() -> void:
	for kind in ["content.v1", "package.v1", "state.v1", "save.v1", "enemy-actions.v1", "progression.v1", "equipment.v1", "battle-layout.v1", "battle-layout.v2", "battle-ui.v1", "battle-hud.v1", "hud-placement.v1", "hud-placement.v2", "party-card.v1", "party-card.v2", "battle-canvas.v1", "command-panel.v1", "enemy-overlay.v1", "battle-formation.v1", "attack-formula.v1", "attack-random.v1", "player-physical.v1", "training.v1", "enemy-physical.v1", "performance.v1", "sampling.v1"]:
		var identity = "pal.native.%s" % kind
		var bytes = FileAccess.get_file_as_bytes("res://contracts/%s.schema.json" % identity)
		var reader = Reader.new()
		var value = reader.decode(bytes)
		if value is Dictionary and reader.error.is_empty():
			schemas[identity] = value
			hashes[identity] = digest(bytes)

static func digest(bytes: PackedByteArray) -> String:
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func is_type(value: Variant, kind: String) -> bool:
	match kind:
		"object": return value is Dictionary
		"array": return value is Array
		"string": return value is String
		"boolean": return value is bool
		"null": return value == null
		"integer": return value is int or (value is float and is_finite(value) and floor(value) == value)
		"number": return value is int or (value is float and is_finite(value))
	return false

static func equal(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool: return a is bool and b is bool and a == b
	if typeof(a) != typeof(b) and not ((a is int or a is float) and (b is int or b is float)): return false
	return a == b

func validate(identity: String, value: Variant) -> String:
	error = ""
	if not schemas.has(identity):
		error = "missing pinned schema " + identity
		return error
	_check(schemas[identity], value, schemas[identity], "$", 0)
	return error

func _fail(path: String, message: String) -> void:
	if error.is_empty(): error = path + ": " + message

func _check(rule: Dictionary, value: Variant, root: Dictionary, path: String, depth: int) -> void:
	if not error.is_empty(): return
	if depth > 64:
		_fail(path, "schema depth limit")
		return
	for key in rule:
		if key not in KEYWORDS:
			_fail(path, "unsupported schema assertion " + key)
			return
	if rule.has("$ref"):
		var ref: String = rule["$ref"]
		if not ref.begins_with("#/definitions/") or not root.get("definitions", {}).has(ref.trim_prefix("#/definitions/")):
			_fail(path, "invalid local schema reference")
			return
		_check(root.definitions[ref.trim_prefix("#/definitions/")], value, root, path, depth + 1)
		return
	for branch in ["oneOf", "anyOf"]:
		if rule.has(branch):
			var matches: int = 0
			for child in rule[branch]:
				error = ""
				_check(child, value, root, path, depth + 1)
				if error.is_empty(): matches += 1
			error = ""
			if matches == 0 or (branch == "oneOf" and matches != 1):
				_fail(path, branch + " mismatch")
				return
	if rule.has("type"):
		var kinds = rule.type if rule.type is Array else [rule.type]
		var valid: bool = false
		for kind in kinds: valid = valid or is_type(value, kind)
		if not valid:
			_fail(path, "type mismatch")
			return
	if rule.has("const") and not equal(value, rule.const): _fail(path, "const mismatch")
	if rule.has("enum"):
		var valid: bool = false
		for candidate in rule.enum: valid = valid or equal(value, candidate)
		if not valid: _fail(path, "enum mismatch")
	if value is Dictionary:
		for key in rule.get("required", []):
			if not value.has(key): _fail(path, "missing " + key)
		for key in value:
			var properties: Dictionary = rule.get("properties", {})
			if properties.has(key):
				_check(properties[key], value[key], root, path + "." + key, depth + 1)
			else:
				var additional = rule.get("additionalProperties", true)
				if additional is Dictionary: _check(additional, value[key], root, path + "." + key, depth + 1)
				elif additional == false: _fail(path, "unknown field " + key)
	elif value is Array:
		if value.size() < rule.get("minItems", 0) or value.size() > rule.get("maxItems", 1000000): _fail(path, "array bounds")
		var seen: Dictionary = {}
		for i in value.size():
			if rule.get("uniqueItems", false):
				var identity = JSON.stringify(value[i], "", true)
				if seen.has(identity): _fail(path, "duplicate item")
				seen[identity] = true
			if rule.has("items"): _check(rule.items, value[i], root, path + "[%d]" % i, depth + 1)
	elif value is String:
		if value.length() < rule.get("minLength", 0) or value.length() > rule.get("maxLength", 16777216): _fail(path, "string bounds")
		if rule.has("pattern") and RegEx.create_from_string(rule.pattern).search(value) == null: _fail(path, "pattern mismatch")
	elif value is int or value is float:
		if value < rule.get("minimum", -INF) or value > rule.get("maximum", INF): _fail(path, "number bounds")
