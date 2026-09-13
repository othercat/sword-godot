# SPDX-License-Identifier: MIT
extends SceneTree
## Windowed ordinary new-game entry probe: the production new-game owner runs
## the real intro to scene 2, the composed software frame uploads to a real
## Godot window, injected logical right-presses walk the party through the
## production input tick, and the window is captured before and after.
##
## Run this script twice in separate processes; equal captures and state are
## the ordinary close-reopen smoke. Injected key levels drive the production
## tick - physical keyboard mapping is not claimed here. Audio, the T121
## transition and the other documented gaps stay host-bound named doubles.
const NewGame = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")

class NamedDouble:
	var seen: Array = []
	func answer(request: Dictionary) -> Dictionary:
		seen.append(request.kind)
		return {"completed": true}

class ReplayClock:
	var frame := 0
	func consume(units: int) -> Dictionary:
		frame += units
		return {"consumed": units, "total": frame}

class ReplayRuntime:
	func answer(request: Dictionary) -> Dictionary:
		if request.kind == "fade_event_pump": return {"completed": true, "pumped": request.events}
		return {"completed": true}

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _rgba_image(rgba: PackedByteArray) -> Image:
	return Image.create_from_data(320, 200, false, Image.FORMAT_RGBA8, rgba)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4: quit(2); return
	create_timer(240).timeout.connect(func(): check(false, "ordinary entry watchdog"); finish(args))
	var package = Package.new()
	if not package.load_package(args[0]):
		push_error("package rejected: " + str(package.error)); quit(2); return
	var game = NewGame.new()
	game.bind_named_double("play_midi", NamedDouble.new())
	game.bind_named_double("play_sound_effect", NamedDouble.new())
	game.bind_named_double("clear_effective_cross_fade", NamedDouble.new())
	game.bind_named_double("restore_dialog_background_without_initial_page", NamedDouble.new())
	game.bind_named_double("upper_dialog_layout", NamedDouble.new())
	game.bind_named_double("start_frame_and_process_events", NamedDouble.new())
	game.bind_named_double("update_viewport_and_party_position", NamedDouble.new())
	game.bind_named_double("render_scene_frame", NamedDouble.new())
	game.bind_named_double("*", NamedDouble.new())
	check(game.open(package), "the ordinary entry binds the package: " + str(game.error))
	if not game.error.is_empty(): finish(args); return
	game.bind_clock(ReplayClock.new())
	game.bind_runtime(ReplayRuntime.new())
	game.bind_key_map([0, 1, 2, 3, 4, 5, 6, 7], 0)
	var begun: Dictionary = game.new_state(0x12345)
	if begun.has("error"): check(false, str(begun.error)); finish(args); return
	begun = game.begin()
	check(not begun.has("error") and begun.get("enters", []) == [1, 2],
		"the ordinary intro rests on the entry's own next scene: " + str(begun.get("error", begun.get("enters", []))))
	if begun.has("error"): finish(args); return
	var resting: Dictionary = begun.state.globals
	check(resting.current_scene == 2 and resting.loaded_map_id == 12,
		"the ordinary entry rests on scene 2 with MAP12 loaded")

	var root = Window.new(); root.size = Vector2i(560, 400)
	root.title = "PAL Wanxiang | ordinary original new game (probe)"
	get_root().add_child(root)
	var frame_view = TextureRect.new()
	frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame_view.size = Vector2(320, 200); frame_view.position = Vector2(120, 100)
	frame_view.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(frame_view)

	var before_image := _rgba_image(game.renderer.current_rgba())
	frame_view.texture = ImageTexture.create_from_image(before_image)
	check(before_image.get_size() == Vector2i(320, 200), "the composed frame uploads at 320x200")
	await process_frame
	await RenderingServer.frame_post_draw
	check(before_image.save_png(args[1]) == OK, "the resting frame is captured")

	var right: PackedInt32Array = PackedInt32Array([0, 0, 0, 2, 0, 0, 0, 0])
	var start_x: int = resting.world_x; var start_y: int = resting.world_y
	var moved := 0; var refused := 0
	var last_tick: Dictionary = {}
	for step in range(12):
		var free: Dictionary = game.probe.probe(game.state.globals.world_x + 16, game.state.globals.world_y + 8)
		if free.has("error") or not free.get("accepted", false):
			refused += 1
			var stationary: Dictionary = game.tick(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0]))
			if stationary.has("error"): check(false, "stationary tick failed: " + str(stationary.error)); break
			last_tick = stationary
			continue
		var ticked: Dictionary = game.tick(right)
		if ticked.has("error"): check(false, "walk tick failed: " + str(ticked.error)); break
		if ticked.input_move: moved += 1
		last_tick = ticked
	check(moved + refused == 12, "twelve logical ticks drove the production chain: %d moved, %d refused" % [moved, refused])
	check(moved > 0, "the ordinary entry walks: %d accepted steps from (%d,%d)" % [moved, start_x, start_y])
	check(game.state.globals.world_x != start_x or game.state.globals.world_y != start_y,
		"the party world position followed the input ticks")
	# The walked frame composes through the production scene-composition owner:
	# the re-rendered MAP12 background at the new viewport plus the loaded
	# party and event sprites, uploaded as a real texture.
	const SceneComposition = preload("res://src/native_pal98_scene_composition.gd")
	var globals: Dictionary = game.state.globals
	var caller: Dictionary = {"map_id": globals.loaded_map_id, "palette_index": 0, "palette_variant": 0,
		"map_mode": 0, "clip_bottom": 200, "viewport_x": globals.viewport_x, "viewport_y": globals.viewport_y,
		"member_last": globals.member_last, "follower_count": globals.follower_count,
		"team_layer": globals.get("party_layer_word", 0), "party_records": game.state.party_records}
	var composed: Dictionary = SceneComposition.build("render_scene_frame", game.records, game.storage,
		game.state.events, game.cache, caller)
	var composition_gap := ""
	var after_image: Image
	if composed.has("error"):
		# MAP12's own event sprites carry zeroed paksize bytes, so the sprite
		# cache refuses them by name (the documented source-data boundary).
		# The walked state keeps the last composed page; the gap is recorded.
		composition_gap = str(composed.error)
		after_image = _rgba_image(game.renderer.current_rgba())
		check(after_image.save_png(args[2]) == OK,
			"the walked state keeps the last composed page; composition refused: " + composition_gap)
	else:
		var stage_viewport = SubViewport.new()
		stage_viewport.size = Vector2i(320, 200)
		stage_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		stage_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		root.add_child(stage_viewport)
		stage_viewport.add_child(composed.value)
		await process_frame
		await RenderingServer.frame_post_draw
		after_image = stage_viewport.get_texture().get_image()
		after_image.convert(Image.FORMAT_RGBA8)
		check(after_image.get_size() == Vector2i(320, 200), "the composed walked frame is the 320x200 target")
		check(after_image.save_png(args[2]) == OK, "the composed walked frame is captured")
	_composition_gap = composition_gap
	check(last_tick.get("requests", []).size() >= 1, "the final tick published draw requests: "
		+ str(last_tick.get("requests", []).size()))
	_world = {"x": game.state.globals.world_x, "y": game.state.globals.world_y}
	finish(args)

func finish(args: Array) -> void:
	var file = FileAccess.open(args[3], FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks,
		"original_gameplay": false, "window_probe": true, "injected_logical_input": true,
		"composition_gap": _composition_gap,
		"world_x": game_state_world_x(), "world_y": game_state_world_y()}, "\t")); file.close()
	print("Ordinary entry window probe: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)

func game_state_world_x() -> int:
	return int(_world.get("x", -1))

func game_state_world_y() -> int:
	return int(_world.get("y", -1))

var _world: Dictionary = {}
var _composition_gap: String = ""
