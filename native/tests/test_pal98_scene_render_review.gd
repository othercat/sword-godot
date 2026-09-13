# SPDX-License-Identifier: MIT
extends SceneTree
const Renderer = preload("res://src/native_pal98_scene_render.gd")
const Display = preload("res://src/native_pal98_display_palette.gd")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed := 0
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func zero(n: int) -> PackedByteArray:
	var b = PackedByteArray(); b.resize(n); return b
func is_black(bytes: PackedByteArray) -> bool:
	for at in range(0,bytes.size(),4):
		if bytes[at] != 0 or bytes[at+1] != 0 or bytes[at+2] != 0: return false
	return not bytes.is_empty()
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size()!=2 or FileAccess.file_exists(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error(package.error); quit(2); return
	var renderer = Renderer.new(); renderer.bind(package.pal98_graphics.open_records())
	var state = {"globals":{"loaded_map_id":20,"viewport_x":448,"viewport_y":368,
		"view_offset_x":13,"view_offset_y":9,"previous_viewport_x":0,"previous_viewport_y":0,
		"day_night_word":0,"battle_mode":0}}
	var first = renderer.render(state)
	check(not first.has("error") and not is_black(first.get("rgba",PackedByteArray())), "real resource sample contains visible coloured pixels")
	var globals = first.get("state",{}).get("globals",{})
	check(globals.get("view_offset_x")==0 and globals.get("view_offset_y")==0, "T244 clears view offsets in returned state")
	check(globals.get("previous_viewport_x")==448 and globals.get("previous_viewport_y")==368, "T244 latches viewport origin in returned state")
	check(state.globals.view_offset_x==13, "render candidate does not mutate caller state")
	check(renderer.restore_dialog_background().has("error"), "a map render is not a captured dialogue page")
	var count = renderer.receipts().size()
	var fade = renderer.prepare_clear_cross_fade(state,1,2)
	check(fade.get("completed")==true and fade.receipt.phases==1 and fade.receipt.pixels_per_lane==0x29AC
		and fade.receipt.base_page_sha256 is String and fade.receipt.target_sha256 == fade.receipt.final_sha256,
		"the crossfade preparation renders the target, captures the base page and pins the recovered lane parameters")
	check(fade.receipt.boundary == "per-lane dissolve (adpic) not recovered; presentation pending",
		"the per-lane dissolve stays a named presentation boundary")
	check(renderer.receipts().size()==count+4, "the preparation publishes its two real renders, the page capture and the phase receipt")
	var display = Display.new()
	check(display.answer({"kind":"fade_event_pump"}).has("error"), "unbound event pump refuses instead of draining a private list")
	check(display.answer({"kind":"fade_frame","argument":1}).has("error"), "unbound frame executor refuses instead of incrementing a counter")
	if display.has_method("bind_surface"):
		check(display.bind_surface(renderer), "palette executor binds the indexed pixel surface")
		var installed = display.answer({"kind":"apply_palette","procedure":"intpate","offset":0,"byte_offset":0,"length":768,"bytes":zero(768)})
		check(installed.get("completed")==true and is_black(renderer.current_rgba()), "palette install recolours existing pixels without rerendering")
		var next = renderer.render(state)
		check(not next.has("error") and is_black(next.rgba), "later map render retains the installed palette")
		var before = renderer.current_rgba(); var receipt_count = renderer.receipts().size()
		var bad = state.duplicate(true); bad.globals.loaded_map_id = 32767
		check(renderer.render(bad).has("error") and renderer.current_rgba()==before and renderer.receipts().size()==receipt_count, "failed render preserves live pixels and receipts")
	else:
		check(false,"palette executor has no pixel consumer binding")
	var f=FileAccess.open(args[1],FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed},"  ")+"\n"); f.close()
	quit(1 if failed else 0)
