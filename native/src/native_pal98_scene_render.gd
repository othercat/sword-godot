# SPDX-License-Identifier: MIT
extends RefCounted
## The real scene-background renderer behind the render_current_map_background
## request (original entry 0x0041CB34): the original resets the view offsets,
## latches the render origin to the current viewport, converts the viewport
## pixel to a map cell/half and flattens the map. Native already owns that
## decomposition (draw_plan) and the tile/palette decode, so this module blits
## the same plan into a software 320x200 RGBA frame with a content hash — real
## pixel evidence a headless drive can verify, with a per-render receipt.
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
const Schema = preload("res://src/native_schema.gd")
const WIDTH := 320
const HEIGHT := 200

var error: String = ""
var _records
var _renders: Array = []
var _indices: PackedByteArray = PackedByteArray()
var _coverage: PackedByteArray = PackedByteArray()
var _rgba: PackedByteArray = PackedByteArray()
var _live_palette: PackedByteArray = PackedByteArray()

func _failure(message: String) -> Dictionary:
	error = "pal98-scene-render: " + message
	return {"error": error}

func bind(records) -> bool:
	if records == null:
		error = "pal98-scene-render: addressed graphics reader required"; return false
	_records = records; _renders = []; _indices.clear(); _coverage.clear(); _rgba.clear(); _live_palette.clear()
	_capture_page.clear()
	error = ""; return true

func current_rgba() -> PackedByteArray:
	return _rgba.duplicate()

## Internal rollback of an accepted script invocation. No capture is invented:
## the checkpoint keeps the existing current and captured pages separately.
func checkpoint() -> Dictionary:
	return {"owner": get_instance_id(), "records": _records,
		"indices": _indices.duplicate(), "coverage": _coverage.duplicate(),
		"rgba": _rgba.duplicate(), "palette": _live_palette.duplicate(),
		"capture": _capture_page.duplicate(true), "receipts": _renders.duplicate(true)}

func restore_checkpoint(saved: Dictionary) -> Dictionary:
	if saved.get("owner") != get_instance_id() or saved.get("records") != _records:
		return _failure("render checkpoint belongs to another source or owner")
	for field in ["indices", "coverage", "rgba", "palette"]:
		if not saved.get(field) is PackedByteArray: return _failure("render checkpoint lacks " + field)
	if saved.indices.size() not in [0, WIDTH * HEIGHT] or saved.coverage.size() != saved.indices.size() or saved.rgba.size() != saved.indices.size() * 4:
		return _failure("render checkpoint has invalid page backing")
	if not saved.capture is Dictionary or not saved.receipts is Array:
		return _failure("render checkpoint lacks captured page or receipts")
	if not saved.palette.is_empty() and not Indexed.validate_palette(saved.palette).is_empty():
		return _failure("render checkpoint has invalid palette")
	_indices = saved.indices.duplicate(); _coverage = saved.coverage.duplicate()
	_rgba = saved.rgba.duplicate(); _live_palette = saved.palette.duplicate()
	_capture_page = saved.capture.duplicate(true); _renders = saved.receipts.duplicate(true)
	error = ""
	return {"completed": true}

## Install into the indexed software surface. Existing pixels are recoloured
## immediately and later renders retain this palette. Window upload is a
## separate consumer; this receipt never claims a GPU frame was presented.
func install_palette(rgb6: PackedByteArray) -> Dictionary:
	var issue = Indexed.validate_palette(rgb6)
	if not issue.is_empty(): return _failure(issue)
	var pixels = _rgba
	if not _indices.is_empty():
		var mapped = Indexed.rgba({"width": WIDTH, "height": HEIGHT, "indices": _indices, "coverage": _coverage}, rgb6, false)
		if mapped.has("error"): return _failure(mapped.error)
		pixels = mapped.value
	_live_palette = rgb6.duplicate(); _rgba = pixels.duplicate()
	return {"completed": true, "surface": "indexed_software", "has_frame": not _indices.is_empty(),
		"rgba_sha256": Schema.digest(_rgba) if not _rgba.is_empty() else ""}

func receipts() -> Array:
	return _renders.duplicate(true)

## Blit covered indices in the existing map plan order. Skipped RLE/literal
## 255 pixels preserve the destination; RGB conversion follows composition.
func _blit(frame_buffer: PackedByteArray, image: Dictionary, origin: Vector2i) -> void:
	var width := int(image.width); var height := int(image.height)
	var pixels: PackedByteArray = image.indices
	for row in range(height):
		var y := origin.y + row
		if y < 0 or y >= HEIGHT: continue
		for column in range(width):
			var x := origin.x + column
			if x < 0 or x >= WIDTH: continue
			var at := y * WIDTH + x
			var src := row * width + column
			if image.coverage[src] == 0 or pixels[src] == 255: continue
			frame_buffer[at] = pixels[src]

## Renders the loaded map at the state's current viewport the way the original
## background pass does: convert the viewport pixel to a map cell/half, flatten
## the map with the installed palette (source selection before first install),
## and clip to the 320x200 drawing window.
func render(state: Dictionary, palette_index: int = 0, palette_variant: int = 0) -> Dictionary:
	if _records == null: return _failure("graphics reader not bound")
	if not state.get("globals") is Dictionary: return _failure("render requires the pending state")
	var globals: Dictionary = state.globals
	var map_id = globals.get("loaded_map_id")
	var viewport_x = globals.get("viewport_x"); var viewport_y = globals.get("viewport_y")
	if not map_id is int or not viewport_x is int or not viewport_y is int:
		return _failure("render requires the explicit loaded map id and viewport words")
	var cell: Dictionary = Occlusion.world_to_cell(viewport_x, viewport_y)
	if cell.has("error"): return _failure(str(cell.error))
	var background = Background.new()
	if not background.load_source(_records, map_id, palette_index, palette_variant):
		return _failure(str(background.error))
	var plan: Dictionary = background.draw_plan(cell.value.x, cell.value.y, cell.value.half)
	if plan.has("error"): return _failure(str(plan.error))
	var group: Dictionary = _records.group("GOP.MKF", map_id)
	if group.has("error"): return _failure(str(group.error))
	var palette: Dictionary = _records.palette(palette_index, palette_variant)
	if palette.has("error"): return _failure(str(palette.error))
	var frame_buffer := PackedByteArray(); frame_buffer.resize(WIDTH * HEIGHT)
	var images: Dictionary = {}
	var rendered_cells: int = 0
	for cell_plan in plan.value:
		for piece in ["lower", "upper"]:
			var descriptor: Dictionary = cell_plan[piece]
			if piece == "upper" and not descriptor.present: continue
			var frame_index: int = descriptor.frame
			if frame_index < 0: continue
			if not images.has(frame_index):
				var decoded: Dictionary = Indexed.frame(group.value, frame_index)
				if decoded.has("error"): return _failure(str(decoded.error))
				images[frame_index] = decoded.value
			var origin: Vector2i = Vector2i(cell_plan.top_left.x, cell_plan.top_left.y)
			_blit(frame_buffer, images[frame_index], origin)
		rendered_cells += 1
	var coverage = PackedByteArray(); coverage.resize(WIDTH * HEIGHT); coverage.fill(1)
	var rgb6: PackedByteArray = _live_palette if not _live_palette.is_empty() else palette.value
	var mapped = Indexed.rgba({"width": WIDTH, "height": HEIGHT, "indices": frame_buffer, "coverage": coverage}, rgb6, false)
	if mapped.has("error"): return _failure(mapped.error)
	var pixels: PackedByteArray = mapped.value
	var candidate = state.duplicate(true)
	candidate.globals.view_offset_x = 0; candidate.globals.view_offset_y = 0
	candidate.globals.previous_viewport_x = viewport_x; candidate.globals.previous_viewport_y = viewport_y
	var identity: Dictionary = background.source()
	var receipt: Dictionary = {"kind": "render_current_map_background", "map_id": map_id,
		"map_cell": [cell.value.x, cell.value.y, cell.value.half],
		"cells": rendered_cells, "tiles": images.size(),
		"frame_sha256": Schema.digest(pixels), "palette_sha256": Schema.digest(rgb6), "identity": identity,
		"surface": "indexed_software"}
	_indices = frame_buffer; _coverage = coverage; _rgba = pixels; _live_palette = rgb6.duplicate()
	_renders.append(receipt)
	return {"completed": true, "state": candidate, "rgba": pixels.duplicate(), "width": WIDTH, "height": HEIGHT,
		"receipt": receipt}

## Non-battle T121 preparation only: G01B0 is the new target while pushscr
## captures the OLD displayed page into G00C0. Build an isolated candidate;
## neither the current page nor the dialogue capture changes here. T121's
## lane execution, timing and final presentation are still unbound, so this
## preparation must never acknowledge the full host command as completed.
func prepare_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	if _records == null or _indices.is_empty(): return _failure("cross-fade requires a bound current indexed page")
	if not state.get("globals") is Dictionary or typeof(state.globals.get("battle_mode")) != TYPE_INT:
		return _failure("cross-fade requires explicit battle mode")
	if state.globals.battle_mode != 0: return _failure("T121 battle target preparation owner not bound")
	if first < -32768 or first > 32767 or second < -32768 or second > 32767:
		return _failure("T121 arguments outside I2")
	var target = get_script().new()
	target.bind(_records)
	if not _live_palette.is_empty():
		var installed: Dictionary = target.install_palette(_live_palette)
		if installed.has("error"): return installed
	var rendered: Dictionary = target.render(state)
	if rendered.has("error"): return rendered
	var receipt: Dictionary = {"kind": "clear_effective_cross_fade",
		"first": first, "second": second, "pixels_per_lane": 0x29AC,
		"base_page_sha256": Schema.digest(_indices),
		"base_rgba_sha256": Schema.digest(_rgba),
		"target_sha256": rendered.receipt.frame_sha256,
		"boundary": "T121 lane execution (adpic), timing and final presentation not implemented"}
	return {"completed": false, "prepared": true, "receipt": receipt,
		"candidate_state": rendered.state, "target_rgba": rendered.rgba,
		"base_page": {"indices": _indices.duplicate(), "coverage": _coverage.duplicate()},
		"target_page": {"indices": target._indices.duplicate(), "coverage": target._coverage.duplicate()}}

var _transition_clock

func bind_transition_clock(clock) -> bool:
	if not clock is Object or not clock.has_method("consume"):
		error = "the transition clock must consume logical units"; return false
	_transition_clock = clock; error = ""; return true

## Recovered map transition structure (PAL98_CLEAR_EFFECTIVE_CROSS_FADE_STAGE_
## OPINION.md): G01B0 holds two pages, the fresh target render lands in the
## second page and copymen publishes it into the first; CrossFadePreparedScene
## pushscr's the live screen into G00C0, then For phase = 0 To lastPhase
## (inclusive) runs lane = phase % 6 with the only adpic0 gate below phase 6,
## presents and waits wtime(delay) every phase, and popscr's the exact target
## page after the loop. pixelsPerLane is 0x29AC on the map path. The PAL.dll
## adpic/adpic0 per-pixel blend and the six G050C lane values stay unrecovered;
## the stride/nibble steps below cross-reference the palxex fade.cpp
## reconstruction and are recorded as a named approximation in every receipt.
const DEFAULT_PHASES := 88
const MAP_PIXELS_PER_LANE := 0x29AC
const LANE_GAPS := [0, 3, 1, 5, 2, 4]

## One bound transition: advances one phase per call so the production host can
## present every phase before the endpoint acknowledges the command. The
## renderer's displayed page stays untouched until finish(); a clock failure or
## cancel() publishes nothing and leaves the renderer reusable.
class ClearCrossFade:
	var host: RefCounted
	var clock: Object
	var last_phase: int = 0
	var delay: int = 0
	var phase: int = -1
	var failed: bool = false
	var finished: bool = false
	var cancelled: bool = false
	var work: PackedByteArray
	var coverage: PackedByteArray
	var target_indices: PackedByteArray
	var target_coverage: PackedByteArray
	var target_rgba: PackedByteArray
	var candidate_state: Dictionary
	var prepared: Dictionary
	var previous_capture: Dictionary
	var phase_receipts: Array = []

	func total_phases() -> int:
		return last_phase + 1

	func complete() -> bool:
		return phase >= last_phase

	## One recovered loop round: the lane's stride pixels step toward the
	## target page (assimilate below phase 6, one-index steps after), then the
	## bound clock consumes wtime(delay). Nothing here can complete the host
	## command; presentation stays the display owner's act.
	func advance() -> Dictionary:
		if cancelled: return {"error": "the transition owner was cancelled"}
		if failed: return {"error": "the transition owner already failed"}
		if finished: return {"error": "the transition already reached its endpoint"}
		if complete(): return {"error": "the transition phases are exhausted"}
		phase += 1
		var lane: int = phase % 6
		var gap: int = host.LANE_GAPS[lane]
		var target: PackedByteArray = target_indices
		var changed: int = 0
		var touched: int = 0
		var at: int = gap
		while at < host.WIDTH * host.HEIGHT and touched < host.MAP_PIXELS_PER_LANE:
			var before: int = work[at]
			var goal: int = target[at]
			var after: int = before
			if phase < 6:
				after = (before & 0x0F) | (goal & 0xF0)
			else:
				after = before + 1 if goal > before else (before - 1 if goal < before else before)
			if after != before: work[at] = after; changed += 1
			touched += 1; at += 6
		var consumed: Dictionary = clock.consume(delay)
		if consumed.has("error"):
			failed = true
			return {"error": "T121 wtime: " + str(consumed.error)}
		var receipt: Dictionary = {"phase": phase, "lane": lane, "lane_gap": gap,
			"step": "adpic0" if phase < 6 else "adpic", "wtime": delay,
			"changed_pixels": changed, "page_sha256": host.Schema.digest(work)}
		phase_receipts.append(receipt)
		return {"completed": false, "receipt": receipt}

	## The composed indexed page as RGBA through the live palette, for the
	## display owner's per-phase window upload.
	func frame_rgba() -> Dictionary:
		if failed or cancelled: return {"error": "the transition owner is not presentable"}
		var mapped: Dictionary = host.Indexed.rgba({"width": host.WIDTH, "height": host.HEIGHT,
			"indices": work, "coverage": coverage}, host._live_palette, false)
		if mapped.has("error"): return mapped
		return {"completed": true, "rgba": mapped.value, "width": host.WIDTH,
			"height": host.HEIGHT, "sha256": Schema.digest(work)}

	## popscr(G01B0): publish the exact target page and hand back the T244
	## candidate state. The endpoint digest must equal the prepared target.
	func finish() -> Dictionary:
		if cancelled: return {"error": "the transition owner was cancelled"}
		if failed: return {"error": "the transition owner already failed"}
		if finished: return {"error": "the transition already reached its endpoint"}
		if not complete(): return {"error": "the transition phases are not exhausted"}
		host._indices = target_indices.duplicate()
		host._coverage = target_coverage.duplicate()
		host._rgba = target_rgba.duplicate()
		finished = true
		var receipt: Dictionary = {"kind": "clear_effective_cross_fade", "completed": true,
			"phases": total_phases(), "pixels_per_lane": host.MAP_PIXELS_PER_LANE,
			"delay": delay, "lane_rotation": "phase % 6", "lane_gaps": host.LANE_GAPS.duplicate(),
			"base_page_sha256": prepared.receipt.base_page_sha256,
			"base_rgba_sha256": prepared.receipt.base_rgba_sha256,
			"target_sha256": prepared.receipt.target_sha256,
			"endpoint_sha256": host.Schema.digest(host._rgba),
			"g00c0": {"captured_sha256": host.Schema.digest(previous_capture.get("indices", PackedByteArray())),
				"restored_on_cancel": true},
			"phase_receipts": phase_receipts.duplicate(true),
			"named_gaps": ["per-phase adpic/adpic0 pixel blend stays an unrecovered PAL.dll helper; the stride-6 nibble and one-index steps cross-reference the palxex fade.cpp reconstruction",
				"the six G050C lane init values are unrecovered; lane gaps 0,3,1,5,2,4 are the palxex reconstruction",
				"per-phase window upload is the production display owner's act, not the renderer's"],
			"approximation": "mid-phase presented pixels converge lane by lane instead of the unrecovered exact blend; the endpoint page is exact"}
		host._renders.append(receipt)
		return {"completed": true, "state": candidate_state.duplicate(true), "receipt": receipt}

	## Cancel publishes nothing and restores the pre-transition G00C0.
	func cancel() -> void:
		if finished or cancelled: return
		cancelled = true
		host._capture_page = previous_capture.duplicate(true)

## Binds the clock, prepares the two-page target and captures the live page
## into G00C0 (pushscr) exactly once per transition. Completion still requires
## the production presentation owner; the renderer-scoped shortcut stays
## refused in execute_clear_cross_fade.
func begin_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	if _transition_clock == null: return _failure("T121 execution requires a bound logical clock")
	if _records == null or _indices.is_empty(): return _failure("cross-fade requires a bound current indexed page")
	if not state.get("globals") is Dictionary or typeof(state.globals.get("battle_mode")) != TYPE_INT:
		return _failure("cross-fade requires explicit battle mode")
	if state.globals.battle_mode != 0: return _failure("T121 battle target preparation owner not bound")
	if first < -32768 or first > 32767 or second < -32768 or second > 32767:
		return _failure("T121 arguments outside I2")
	var effective: int = DEFAULT_PHASES if first == 0 else first
	if effective < 0 or second < 0: return _failure("T121 phases or delay outside the original range")
	var prepared: Dictionary = prepare_clear_cross_fade(state, first, second)
	if prepared.has("error"): return prepared
	var owner := ClearCrossFade.new()
	owner.host = self
	owner.clock = _transition_clock
	owner.last_phase = effective
	owner.delay = second
	owner.work = _indices.duplicate()
	owner.coverage = PackedByteArray(); owner.coverage.resize(WIDTH * HEIGHT); owner.coverage.fill(1)
	owner.target_indices = prepared.target_page.indices
	owner.target_coverage = prepared.target_page.coverage
	owner.target_rgba = prepared.target_rgba
	owner.candidate_state = prepared.candidate_state
	owner.prepared = prepared
	owner.previous_capture = _capture_page.duplicate(true)
	# pushscr(G00C0): the fade shares the dialog capture arena in the original;
	# a cancel restores exactly what was here before.
	_capture_page = {"indices": _indices.duplicate(), "coverage": _coverage.duplicate(),
		"sha256": Schema.digest(_indices)}
	return {"completed": false, "owner": owner, "phases": owner.total_phases(),
		"receipt": prepared.receipt}

## Preparation is useful, but the renderer alone still cannot present the
## phases; the full command completes only through the production host's
## presentation owner (scene display + window), never through this shortcut.
func execute_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	if _transition_clock == null: return _failure("T121 execution requires a bound logical clock")
	var prepared: Dictionary = prepare_clear_cross_fade(state, first, second)
	if prepared.has("error"): return prepared
	var refused: Dictionary = _failure("T121 full-scene target, adpic lane, presentation and shake execution owners are not implemented")
	refused.prepared = true; refused.completed = false
	refused.receipt = prepared.receipt
	return refused

## Production host adapter: preparation alone never releases a script waiter.
func answer(request: Dictionary) -> Dictionary:
	var result: Dictionary
	match request.get("kind"):
		"render_current_map_background":
			if not request.get("state") is Dictionary: return _failure("render host requires pending state")
			return render(request.state)
		"capture_dialog_background": result = capture_page()
		"restore_dialog_background": result = restore_dialog_background()
		"clear_effective_cross_fade":
			if not request.get("state") is Dictionary: return _failure("cross-fade host requires pending state")
			for key in ["first", "second"]:
				if typeof(request.get(key)) != TYPE_INT: return _failure("cross-fade requires explicit " + key)
			var executed = execute_clear_cross_fade(request.state, request.first, request.second)
			if executed.has("error"): return executed
			return executed
		_: return _failure("unhandled scene-page request " + str(request.get("kind")))
	if not result.has("error") and request.get("state") is Dictionary:
		result.state = request.state.duplicate(true)
	return result

## DialogueCaller uses these names, not the display family's command names.
func answer_dialogue(request: Dictionary) -> Dictionary:
	var result: Dictionary
	var event: String
	match request.get("kind"):
		"capture_background": result = capture_page(); event = "captured"
		"restore_background": result = restore_dialog_background(); event = "restored"
		_: return _failure("unhandled dialogue-page request " + str(request.get("kind")))
	if result.has("error"): return result
	# DialogueCaller validates the event's exact shape. Pixel evidence remains
	# in receipts(), not in extra event fields that invalidate the signal.
	return {"kind": event}

var _capture_page: Dictionary = {}

## G00C0: capture the composed indexed page (indices + coverage) at dialog
## open. Later renders overwrite the screen, never the page; only a new
## capture replaces it. Refuses while the surface is empty.
func capture_page() -> Dictionary:
	if _indices.is_empty():
		return _failure("capture_page requires a rendered indexed surface")
	_capture_page = {"indices": _indices.duplicate(), "coverage": _coverage.duplicate(),
		"sha256": Schema.digest(_indices)}
	var receipt: Dictionary = {"kind": "capture_dialog_background",
		"page_sha256": _capture_page.sha256}
	_renders.append(receipt)
	return {"completed": true, "receipt": receipt}

## G00C0 restore: copy the captured page back into the surface and recompose
## the RGBA through the live palette. Without a captured page the refusal
## stands: a map render receipt is not G00C0.
func restore_dialog_background() -> Dictionary:
	if _capture_page.is_empty():
		return _failure("restore_dialog_background requires the captured-page owner; a map receipt is not G00C0")
	var indices: PackedByteArray = _capture_page.indices.duplicate()
	var coverage: PackedByteArray = _capture_page.coverage.duplicate()
	var palette: PackedByteArray = _live_palette
	var mapped = Indexed.rgba({"width": WIDTH, "height": HEIGHT, "indices": indices, "coverage": coverage}, palette, false)
	if mapped.has("error"): return _failure(mapped.error)
	_indices = indices; _coverage = coverage; _rgba = mapped.value
	var receipt: Dictionary = {"kind": "restore_dialog_background",
		"page_sha256": _capture_page.sha256,
		"frame_sha256": Schema.digest(_rgba), "from_page": true}
	_renders.append(receipt)
	return {"completed": true, "receipt": receipt}
