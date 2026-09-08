# SPDX-License-Identifier: MIT
extends RefCounted
const TexturePolicy = preload("res://src/native_texture.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
## Native data/rendering policy. No legacy codec or legacy occlusion executor.

static func validate(map_data: Dictionary, assets: Dictionary) -> String:
	var terrain: Dictionary = map_data.terrain
	var cells: Dictionary = {}
	var origin: Dictionary = map_data.coordinates.origin
	for point in terrain.cells:
		var cell = Vector2i(point.x, point.y)
		if cells.has(cell) or point.x < origin.x or point.y < origin.y or point.x >= origin.x + map_data.width or point.y >= origin.y + map_data.height: return "duplicate or out-of-bounds available cell"
		cells[cell] = true
	var tiles: Dictionary = {}
	for tile in terrain.tiles:
		if tiles.has(tile.id) or not assets.has(tile.asset_id) or assets[tile.asset_id].kind != "texture": return "duplicate tile or invalid tile texture"
		if tile.anchor.x > tile.width or tile.anchor.y > tile.height: return "tile anchor outside image"
		tiles[tile.id] = tile
	var layers: Dictionary = {}
	var count: int = 0
	for layer in terrain.layers:
		if layers.has(layer.id) or (layer.depth_sort != (layer.draw_order == 0)): return "duplicate layer or invalid depth draw order"
		layers[layer.id] = true
		var used: Dictionary = {}
		count += layer.placements.size()
		if count > 131072: return "terrain placement budget exceeded"
		for placement in layer.placements:
			var cell = Vector2i(placement.position.x, placement.position.y)
			if not cells.has(cell) or used.has(cell): return "unavailable or duplicate tile placement"
			used[cell] = true
			if not tiles.has(placement.tile_id) or (not layer.depth_sort and placement.sort_offset_y != 0): return "invalid tile reference or flat depth offset"
	return ""

# Arbitrary HD scales use CanvasItem drawing without reducing source resolution.
class FlatLayer extends Node2D:
	var items: Array = []
	func _draw() -> void:
		for item in items: draw_texture_rect(item.texture, item.rect, false)

static func make_flat(map_data: Dictionary, layer: Dictionary, textures: Dictionary, atlas_cache: Dictionary) -> Node2D:
	var definitions: Dictionary = {}
	for tile in map_data.terrain.tiles: definitions[tile.id] = tile
	var factor: float = float(map_data.terrain.tiles[0].scale_milli) / 1000.0
	var basis = Vector2(map_data.coordinates.tile_width, map_data.coordinates.tile_height) / factor
	var atlas_compatible: bool = basis.x == floorf(basis.x) and basis.y == floorf(basis.y) and basis.x <= 8192 and basis.y <= 8192
	var padded_pixels: int = 0
	for tile in definitions.values():
		var padded = Vector2i(2 * maxi(tile.anchor.x, tile.width - tile.anchor.x), 2 * maxi(tile.anchor.y, tile.height - tile.anchor.y))
		padded_pixels += padded.x * padded.y
		atlas_compatible = atlas_compatible and is_equal_approx(float(tile.scale_milli) / 1000.0, factor) and padded.x <= 8192 and padded.y <= 8192
	atlas_compatible = atlas_compatible and padded_pixels <= 33554432
	if not atlas_compatible:
		var canvas = FlatLayer.new()
		for placement in layer.placements:
			var tile: Dictionary = definitions[placement.tile_id]
			var scale_value: float = float(tile.scale_milli) / 1000.0
			var point = MapProjection.project(Vector2(placement.position.x, placement.position.y), map_data.coordinates)
			canvas.items.append({"texture": textures[tile.asset_id], "rect": Rect2(point - Vector2(tile.anchor.x, tile.anchor.y) * scale_value, Vector2(tile.width, tile.height) * scale_value)})
		canvas.z_index = layer.draw_order
		return canvas
	# One map's flat layers share an atlas. Otherwise an allowed multi-layer map
	# would multiply padded GPU textures beyond the per-map pixel budget.
	if atlas_cache.is_empty(): atlas_cache.merge(_make_atlas(map_data, definitions, textures, basis))
	var result = TileMapLayer.new()
	result.tile_set = atlas_cache.tile_set
	result.z_index = layer.draw_order
	result.scale = Vector2.ONE * factor
	var origin = Vector2i(map_data.coordinates.origin.x, map_data.coordinates.origin.y)
	result.position = MapProjection.project(Vector2(origin), map_data.coordinates) - Vector2(map_data.coordinates.tile_width, map_data.coordinates.tile_height) / 2.0
	for placement in layer.placements:
		# TileMap serialization's 16-bit coordinates never receive global origins.
		result.set_cell(Vector2i(placement.position.x, placement.position.y) - origin, atlas_cache.source_ids[placement.tile_id], atlas_cache.coordinates[placement.tile_id])
	return result

static func _atlas_grid(cell_size: Vector2i, count: int) -> Vector2i:
	# Include Godot's one-pixel padding in the limits. Very uneven HD tiles keep
	# the existing per-tile path rather than allocate an unbounded common cell.
	var padded: Vector2i = cell_size + Vector2i(2, 2)
	if count < 1 or padded.x > 8192 or padded.y > 8192: return Vector2i.ZERO
	var columns: int = clampi(ceili(sqrt(float(count) * padded.y / padded.x)), 1, 8192 / padded.x)
	var rows: int = ceili(float(count) / columns)
	if rows * padded.y > 8192 or columns * padded.x * rows * padded.y > 33554432: return Vector2i.ZERO
	return Vector2i(columns, rows)

static func _make_atlas(map_data: Dictionary, definitions: Dictionary, textures: Dictionary, basis: Vector2) -> Dictionary:
	var tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(basis)
	if map_data.coordinates.kind == "isometric":
		tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
		tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	var source_ids: Dictionary = {}
	var coordinates: Dictionary = {}
	var common_size: Vector2i = Vector2i.ZERO
	for tile in definitions.values():
		common_size = common_size.max(Vector2i(2 * maxi(tile.anchor.x, tile.width - tile.anchor.x), 2 * maxi(tile.anchor.y, tile.height - tile.anchor.y)))
	var grid: Vector2i = _atlas_grid(common_size, definitions.size())
	var packed: Image
	var packed_source: TileSetAtlasSource
	if grid != Vector2i.ZERO:
		packed = Image.create(common_size.x * grid.x, common_size.y * grid.y, false, Image.FORMAT_RGBA8)
		packed.fill(Color.TRANSPARENT)
		packed_source = TileSetAtlasSource.new()
		packed_source.texture_region_size = common_size
	var index: int = 0
	for tile in definitions.values():
		# Symmetric padding puts the explicit anchor at the atlas cell center,
		# including odd source heights. No resampling or hidden color adjustment.
		var size = common_size if packed != null else Vector2i(2 * maxi(tile.anchor.x, tile.width - tile.anchor.x), 2 * maxi(tile.anchor.y, tile.height - tile.anchor.y))
		var padded = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		padded.fill(Color.TRANSPARENT)
		var texture: Texture2D = textures[tile.asset_id]
		var original = texture.get_image()
		original.convert(Image.FORMAT_RGBA8)
		padded.blit_rect(original, Rect2i(0, 0, tile.width, tile.height), size / 2 - Vector2i(tile.anchor.x, tile.anchor.y))
		TexturePolicy.fix_transparent_edges(padded)
		if packed != null:
			var cell = Vector2i(index % grid.x, index / grid.x)
			packed.blit_rect(padded, Rect2i(Vector2i.ZERO, size), cell * size)
			source_ids[tile.id] = 0
			coordinates[tile.id] = cell
			index += 1
			continue
		var source = TileSetAtlasSource.new()
		source.texture = ImageTexture.create_from_image(padded)
		source.texture_region_size = size
		source.create_tile(Vector2i.ZERO)
		source_ids[tile.id] = tile_set.add_source(source)
		coordinates[tile.id] = Vector2i.ZERO
	if packed != null:
		packed_source.texture = ImageTexture.create_from_image(packed)
		for cell in coordinates.values(): packed_source.create_tile(cell)
		tile_set.add_source(packed_source, 0)
	return {"tile_set": tile_set, "source_ids": source_ids, "coordinates": coordinates}

static func add_depth(map_data: Dictionary, layer: Dictionary, textures: Dictionary, parent: Node2D) -> Array:
	var tiles: Dictionary = {}
	for tile in map_data.terrain.tiles: tiles[tile.id] = tile
	var result: Array = []
	for placement in layer.placements:
		var tile: Dictionary = tiles[placement.tile_id]
		var body = Node2D.new()
		body.position = MapProjection.project(Vector2(placement.position.x, placement.position.y), map_data.coordinates) + Vector2(0, placement.sort_offset_y)
		var sprite = Sprite2D.new()
		sprite.texture = textures[tile.asset_id]
		sprite.centered = false
		sprite.scale = Vector2.ONE * float(tile.scale_milli) / 1000.0
		sprite.position = -Vector2(tile.anchor.x, tile.anchor.y) * sprite.scale - Vector2(0, placement.sort_offset_y)
		body.add_child(sprite)
		parent.add_child(body)
		result.append(body)
	return result
