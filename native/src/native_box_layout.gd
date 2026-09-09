# SPDX-License-Identifier: MIT
extends RefCounted
## Pure rectangle layout. No textures, actors, HP, orientation or state consumers.

static func flow(count: int, region: Rect2, preferred: Vector2, minimum_width: float, gap: float, max_columns: int) -> Array:
	var result: Array = []
	if count <= 0 or region.size.x <= 0 or region.size.y <= 0: return result
	var columns: int = clampi(floori((region.size.x+gap)/(minimum_width+gap)),1,mini(count,max_columns))
	var rows: int = ceili(float(count)/columns)
	var width: float = minf(preferred.x,maxf(1.0,(region.size.x-gap*(columns-1))/columns))
	var group_size = Vector2(width*columns+gap*(columns-1),preferred.y*rows+gap*(rows-1))
	var scale_value: float = minf(1.0,minf(region.size.x/group_size.x,region.size.y/group_size.y))
	var origin: Vector2 = region.position+(region.size-group_size*scale_value)/2.0
	for i in range(count):
		var row: int = i/columns
		var row_count: int = mini(columns,count-row*columns)
		var offset = Vector2((columns-row_count)*(width+gap)/2.0+(i%columns)*(width+gap),row*(preferred.y+gap))
		result.append(Rect2(origin+offset*scale_value,Vector2(width,preferred.y)*scale_value))
	return result

static func contain(extent: Rect2, region: Rect2, allow_upscale: bool = false) -> Transform2D:
	if extent.size.x <= 0 or extent.size.y <= 0 or region.size.x <= 0 or region.size.y <= 0: return Transform2D.IDENTITY
	var scale_value: float = minf(region.size.x/extent.size.x,region.size.y/extent.size.y)
	if not allow_upscale: scale_value = minf(1.0,scale_value)
	return Transform2D(Vector2(scale_value,0),Vector2(0,scale_value),region.get_center()-extent.get_center()*scale_value)

static func contain_group(extents: Array, region: Rect2, allow_upscale: bool = false) -> Transform2D:
	if extents.is_empty(): return Transform2D.IDENTITY
	var combined: Rect2 = extents[0]
	for extent in extents.slice(1): combined = combined.merge(extent)
	return contain(combined,region,allow_upscale)
