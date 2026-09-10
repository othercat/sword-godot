# SPDX-License-Identifier: MIT
extends RefCounted
const KEY = "pal.native.story-notice"
const SCHEMA = "pal.native.story-notice.v1"
const CAPABILITY = "graphics.story-notice.v1"
static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func for_node(content: Dictionary, node_id: String) -> Dictionary:
	for row in content.extensions.get(KEY, {}).get("notices", []):
		if row.node_id == node_id: return row
	return {}
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Array = []
	var performance: Variant = package.world.extensions.get("pal.native.performance", {})
	var reserved: Variant = performance.get("performances", []) if performance is Dictionary else []
	for row in package.world.extensions[KEY].notices:
		if row.node_id in seen or not package.world.nodes.any(func(n): return n.id == row.node_id and n.op == "end"): return "story notice: duplicate or unresolved end node"
		seen.append(row.node_id)
		if reserved is Array:
			for binding in reserved:
				if binding is Dictionary and binding.get("node_id") == row.node_id: return "story notice: node already continues through a map performance"
	return ""
