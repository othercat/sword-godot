# SPDX-License-Identifier: MIT
extends RefCounted
const Schema = preload("res://src/native_schema.gd")
const CAPABILITY = "story.conditions.v1"
const RULE = "native.conditions.v1"
const LIMIT = 9007199254740991

static func used(content: Dictionary) -> bool:
	return content.nodes.any(func(node): return node.has("condition")) or content.scenes.any(func(scene): return scene.get("triggers", []).any(func(trigger): return trigger.condition != null))

static func matches(value: Variant, kind: String, literal: bool = true) -> bool:
	if not Schema.is_type(value, kind): return false
	if kind == "integer": return value >= -LIMIT and value <= LIMIT
	if kind == "string": return not literal or value.length() <= 4096
	return true

static func validate(expression: Dictionary, variables: Dictionary) -> String:
	var pending: Array = [[expression, 1]]
	var count: int = 0
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		count += 1
		if count > 128 or entry[1] > 8: return "condition exceeds 128 nodes or depth 8"
		var node: Dictionary = entry[0]
		var op: String = node.op
		if op in ["and", "or"]:
			for child in node.args: pending.append([child, entry[1] + 1])
		elif op == "not": pending.append([node.arg, entry[1] + 1])
		else:
			if not variables.has(node.variable): return "condition unresolved variable: " + node.variable
			var kind: String = variables[node.variable].type
			if op in ["var_lt", "var_le", "var_gt", "var_ge"] and kind != "integer": return "ordered condition requires integer"
			var values: Array = node.values if op == "var_in" else [node.value]
			var seen: Array = []
			for value in values:
				if not matches(value, kind): return "condition literal type/range differs from declaration"
				if seen.any(func(prior): return Schema.equal(prior, value)): return "duplicate condition set member"
				seen.append(value)
	return ""

static func evaluate(expression: Dictionary, variables: Dictionary, scopes: Dictionary) -> Dictionary:
	var issue: String = validate(expression, variables)
	if not issue.is_empty(): return {"error": issue}
	return _visit(expression, variables, scopes)

static func _visit(node: Dictionary, variables: Dictionary, scopes: Dictionary) -> Dictionary:
	var op: String = node.op
	if op in ["and", "or"]:
		var truth: bool = op == "and"
		for child in node.args:
			var result: Dictionary = _visit(child, variables, scopes)
			if result.has("error"): return result
			truth = (truth and result.value) if op == "and" else (truth or result.value)
		return {"value": truth}
	if op == "not":
		var result: Dictionary = _visit(node.arg, variables, scopes)
		return result if result.has("error") else {"value": not result.value}
	var variable: Dictionary = variables[node.variable]
	var actual: Variant = scopes.get(variable.scope, {}).get(node.variable)
	if not matches(actual, variable.type, false): return {"error": "condition missing or invalid scoped state: " + node.variable}
	match op:
		"var_eq": return {"value": Schema.equal(actual, node.value)}
		"var_ne": return {"value": not Schema.equal(actual, node.value)}
		"var_lt": return {"value": actual < node.value}
		"var_le": return {"value": actual <= node.value}
		"var_gt": return {"value": actual > node.value}
		"var_ge": return {"value": actual >= node.value}
		"var_in": return {"value": node.values.any(func(value): return Schema.equal(actual, value))}
	return {"error": "unknown condition operator"}
