# SPDX-License-Identifier: MIT
extends RefCounted
## Presentation-only policy. An absent component preserves the consumer's old filter.
const KEY = "pal.native.sampling"
const SCHEMA = KEY + ".v1"
const CAPABILITY = "graphics.sampling.v1"
const SCOPES = ["map_actor", "map_terrain", "map_background", "battle_actor", "battle_background", "portrait", "hud", "command_ui", "surface"]

static func used(content: Dictionary) -> bool:
	return content.get("extensions", {}).has(KEY)

static func validate_content(package) -> String:
	return package.schema.validate(SCHEMA, package.world.extensions[KEY]) if used(package.world) else ""

static func resolve(content: Dictionary, scope: String, legacy: int = CanvasItem.TEXTURE_FILTER_PARENT_NODE, widget_filter: String = "") -> int:
	assert(scope in SCOPES, "Unknown sampling scope")
	if not used(content): return legacy
	var component: Dictionary = content.extensions[KEY]
	var fallback: String = widget_filter if not widget_filter.is_empty() else ("linear" if component.profile == "IllustratedHD" else "nearest")
	return CanvasItem.TEXTURE_FILTER_NEAREST if component.get("overrides", {}).get(scope, fallback) == "nearest" else CanvasItem.TEXTURE_FILTER_LINEAR
