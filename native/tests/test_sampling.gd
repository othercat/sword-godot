# SPDX-License-Identifier: MIT
extends SceneTree
## Windowed presentation checks over immutable author packages; no physical input claim.
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
var checks: Array = []
var windows: Array = []
var failed: int = 0
var output: String

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)
func settle() -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
func effective(item: CanvasItem) -> int:
	if item.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE: return item.texture_filter
	var parent = item.get_parent()
	return effective(parent) if parent is CanvasItem else CanvasItem.TEXTURE_FILTER_LINEAR

func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() not in [2, 3]: quit(2); return
	var baseline: bool = args.size() == 3 and args[2] == "--baseline"
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	root.size = Vector2i(1280, 800)
	var app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
	var geometry: Dictionary = {}
	for fixture in fixtures.valid:
		if baseline and fixture.profile != "legacy": continue
		var label: String = fixture.label
		check(app.open_package(fixture.path), label + " admission")
		if app.session.state.is_empty(): finish(); return
		app.world_view.set_process(false)
		app.saves = Save.new(output.path_join(label + "-saves"))
		app.session.focused = true
		await settle()
		var world = app.world_view; var expected: Dictionary = fixture.expected
		check(world.tiles is TileMapLayer and not world.terrain_layers.is_empty(), label + " formal terrain")
		if not baseline:
			check(effective(app.render_surface) == int(expected.surface), label + " surface filter")
			check(world.terrain_layers.all(func(layer): return effective(layer) == int(expected.map_terrain)), label + " all flat terrain")
			check(not world.depth_tiles.is_empty() and world.depth_tiles.all(func(layer): return effective(layer) == int(expected.map_terrain)), label + " all depth terrain")
			if world.backdrop != null: check(effective(world.backdrop) == int(expected.map_background), label + " map background")
			for visual in world.visuals.values():
				check(effective(visual.sprite) == int(expected.map_animation), label + " map animation")
				if visual.fallback is Sprite2D: check(effective(visual.fallback) == int(expected.map_static), label + " map static")
		var map_image = output.path_join(label + "-map.png")
		check(root.get_texture().get_image().save_png(map_image) == OK, label + " map capture")
		for i in range(30):
			if app.session.battle_open(): break
			var node: Dictionary = app.session.current_node()
			if node.op == "dialogue": check(app.session.advance_dialogue(), label + " dialogue")
			elif node.op == "choice":
				var choice: String = ""
				for row in node.options:
					if row.id.ends_with(".train"): choice = row.id
				check(not choice.is_empty() and app.session.advance_dialogue(choice), label + " training choice")
			else: check(false, label + " unexpected story node"); finish(); return
		app._refresh(); await settle()
		check(app.session.battle_open(), label + " battle entry")
		if not app.session.battle_open(): finish(); return
		var view = app.battle_view
		if not baseline:
			check(effective(view) == int(expected.battle_actor), label + " battle actors")
			check(effective(view.background_layer) == int(expected.battle_background), label + " battle background")
			if fixture.hud == "simple":
				for card in app.classic_hud.cards.values(): check(effective(card.face) == int(expected.portrait), label + " simple portrait")
			else:
				var hud = app.dream_hud
				check(effective(hud) == int(expected.hud), label + " HUD panel")
				check(effective(hud.portrait_layer) == int(expected.portrait), label + " portrait layer")
				check(effective(hud.foreground_layer) == int(expected.hud), label + " HUD digits")
				for button in hud.commands.get_children(): check(effective(button) == int(expected.command_ui), label + " command " + button.symbol)
		var state: Dictionary = app.session.snapshot()
		var shape = {"bodies":view.displayed_bodies.duplicate(true), "background":view.background_rect, "source":view.background_source}
		if geometry.has(fixture.hud): check(shape == geometry[fixture.hud], label + " unchanged geometry")
		else: geometry[fixture.hud] = shape
		for hz in [30, 60, 100, 144]:
			app.session.paused = true; view._process(1.0/hz)
		app.session.paused = false; await settle()
		check(app.session.snapshot() == state, label + " render rates preserve authority")
		check(app.saves.save(app.session), label + " save generation")
		check(app.saves.load_into(app.session, app.saves.last_path, 0), label + " same package save restore")
		app._refresh(); await settle()
		var path = output.path_join(label + "-battle.png")
		check(root.get_texture().get_image().save_png(path) == OK, label + " battle capture")
		windows.append({"label":label,"map":map_image,"battle":path})
	if not baseline:
		for fixture in fixtures.invalid:
			var state: Dictionary = app.session.snapshot()
			check(not app.open_package(fixture.path), fixture.label + " rejected")
			check(app.session.snapshot() == state, fixture.label + " preserves session")
	finish()

func finish() -> void:
	var file = FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failed == 0,"checks":checks,"windows":windows}, "\t")); file.close()
	quit(0 if failed == 0 else 1)
