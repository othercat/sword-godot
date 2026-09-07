# SPDX-License-Identifier: MIT
extends RefCounted
## Shared map/actor/background/camera geometry, independent of movement policy.
static func project(point: Vector2, coordinates: Dictionary) -> Vector2:
	if coordinates.kind == "isometric":
		return Vector2((point.x - point.y) * coordinates.tile_width / 2.0, (point.x + point.y) * coordinates.tile_height / 2.0)
	return point * Vector2(coordinates.tile_width, coordinates.tile_height)

static func bounds(map_data: Dictionary) -> Rect2:
	var c: Dictionary = map_data.coordinates
	var origin = Vector2(c.origin.x, c.origin.y)
	if map_data.has("terrain"):
		var extent = Rect2(project(Vector2(map_data.terrain.cells[0].x, map_data.terrain.cells[0].y), c), Vector2.ZERO)
		for point in map_data.terrain.cells: extent = extent.expand(project(Vector2(point.x, point.y), c))
		return Rect2(extent.position - Vector2(c.tile_width, c.tile_height) / 2.0, extent.size + Vector2(c.tile_width, c.tile_height))
	var result = Rect2(project(origin, c), Vector2.ZERO)
	for offset in [Vector2(map_data.width - 1, 0), Vector2(0, map_data.height - 1), Vector2(map_data.width - 1, map_data.height - 1)]:
		result = result.expand(project(origin + offset, c))
	return Rect2(result.position - Vector2(c.tile_width, c.tile_height) / 2.0, result.size + Vector2(c.tile_width, c.tile_height))
