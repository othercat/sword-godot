# SPDX-License-Identifier: MIT
extends RefCounted
## One disposable projection for bodies, target marks and committed-effect text.
## Authored scale ratios survive camera fitting; no gameplay formation is implied.
static func party_anchor(index: int, count: int, bounds: Vector2) -> Vector2:
	var layouts = {
		3: [Vector2(.68,.74),Vector2(.80,.57),Vector2(.89,.36)],
		4: [Vector2(.61,.80),Vector2(.72,.71),Vector2(.82,.54),Vector2(.90,.33)],
		5: [Vector2(.59,.84),Vector2(.70,.75),Vector2(.79,.62),Vector2(.87,.48),Vector2(.91,.29)]
	}
	if layouts.has(count): return layouts[count][index] * bounds
	var ranks: int = ceili(count / 2.0)
	return Vector2(.65 + (index % 2) * .16, .28 + (index / 2) * .58 / maxi(1,ranks) + (index % 2)*.1) * bounds

static func enemy_anchor(index: int, count: int, bounds: Vector2) -> Vector2:
	var column: int = index % 2
	return Vector2(.19 + column * .16, .28 + (index / 2) * .58 / maxi(1,ceili(count / 2.0)) + column * .1) * bounds

static func frame_rect(frame: Dictionary) -> Rect2:
	var scale_value: float = float(frame.scale_milli) / 1000.0
	return Rect2(-Vector2(frame.anchor.x, frame.anchor.y) * scale_value, Vector2(frame.width, frame.height) * scale_value)

static func fit(bodies: Array, bounds: Vector2) -> Transform2D:
	var total = Rect2()
	for body in bodies:
		var rect: Rect2 = body.extent
		rect.position += body.position
		total = rect if total == Rect2() else total.merge(rect)
	if total == Rect2(): return Transform2D.IDENTITY
	var safe = Rect2(Vector2(20,36), (bounds - Vector2(40,56)).max(Vector2.ONE))
	var scale_value: float = minf(1.0, minf(safe.size.x / total.size.x, safe.size.y / total.size.y))
	var offset = Vector2.ZERO
	for axis in range(2):
		offset[axis] = clampf(0.0, safe.position[axis] - total.position[axis] * scale_value, safe.end[axis] - total.end[axis] * scale_value)
	return Transform2D(Vector2(scale_value,0), Vector2(0,scale_value), offset)

static func spacing(bodies: Array) -> float:
	var factor: float = 1.0
	for i in range(bodies.size()):
		for j in range(i+1,bodies.size()):
			var a: Dictionary = bodies[i]; var b: Dictionary = bodies[j]
			if a.side == 0 and b.side == 0 and a.page != b.page: continue
			var delta: Vector2 = b.position - a.position
			var required: float = INF
			for axis in range(2):
				if is_zero_approx(delta[axis]): continue
				var gap: float = a.extent.end[axis] - b.extent.position[axis] if delta[axis] > 0 else b.extent.end[axis] - a.extent.position[axis]
				required = minf(required,(gap+8.0)/absf(delta[axis]))
			if is_finite(required): factor = maxf(factor,required)
	return factor

static func effect_origin(rect: Rect2, bounds: Vector2) -> Vector2:
	return Vector2(clampf(rect.get_center().x - 28, 4, maxf(4,bounds.x - 90)), clampf(rect.position.y - 12, 26, maxf(26,bounds.y - 8)))
