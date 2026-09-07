# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> bool:
	checks.append({"name": label, "passed": ok})
	if not ok:
		failed += 1; push_error(label)
	return ok
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 5:
		quit(2); return
	output = args[4]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	for package_path in args.slice(0, 3):
		var app = App.instantiate(); root.add_child(app); await process_frame
		app.saves = Save.new(output.path_join("saves"))
		if not check(app.open_package(package_path), "owner-built composed battle package loads"):
			_finish(); return
		await process_frame; await process_frame; await _click(app.options.get_child(0))
		var session = app.session; var size: int = session.state.active_party.size()
		if not check(session.battle_open(), "composed encounter starts " + str(size)):
			_finish(); return
		var battle: Dictionary = session.state.extensions[Battle.KEY]
		var ids: Array = battle.enemies.map(func(e): return e.instance_id)
		var win: String = session.current_node().on_win
		check(battle.enemies.size() == 3 and battle.enemies.map(func(e): return e.hp) == [36, 65, 36] and battle.enemies.map(func(e): return e.mp) == [5, 13, 5], "authored enemy HP and MP initialize independent instances")
		check(battle.enemies[0].definition_id == battle.enemies[2].definition_id and battle.enemies[0].definition_id != battle.enemies[1].definition_id, "authored shared definition and leader clone reach runtime")
		check(session.entity(session.state.active_party[0]).hp == 117 and session.entity(session.state.active_party[0]).mp == 23, "authored ally upper bounds reach new game state")
		check(app.options.get_child(0).text == "攻击 1 · 练习苗兵" and app.options.get_child(2).text == "攻击 3 · 练习苗兵", "duplicate names have distinct stable visible target ordinals")
		check(app.options.get_child(2).tooltip_text.contains("真气 5 / 5"), "target tooltip exposes authored MP and HP")
		await _click(app.options.get_child(2)); battle = session.state.extensions[Battle.KEY]
		check(battle.enemies.map(func(e): return e.hp) == [36, 65, 18] and battle.events[0].target == ids[2], "mouse target three damages only its independent instance")
		await _click(app.options.get_child(2)); battle = session.state.extensions[Battle.KEY]
		check(battle.enemies.map(func(e): return e.hp) == [36, 65, 0] and app.options.get_child(2).disabled, "dead target stays identified and is disabled")
		var before: Dictionary = session.state.duplicate(true)
		check(not session.battle_command("attack", ids[2]) and session.state == before, "dead target command is rejected atomically")
		await _click(app.save_button); var save_path: String = app.saves.last_path
		if not check(not save_path.is_empty(), "multi-enemy command save is written"):
			_finish(); return
		var saved_battle: Dictionary = session.state.extensions[Battle.KEY].duplicate(true)
		saves.append({"party": size, "enemy_count": 3, "package_path": package_path, "save_path": save_path})
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("battle-" + str(size) + ".png"))
		for _i in range(size):
			if session.state.extensions[Battle.KEY].round > 1: break
			await _click(app.options.get_child(3))
		battle = session.state.extensions[Battle.KEY]
		var hits: Array = battle.events.filter(func(e): return e.kind == "attack")
		check(battle.round == 2 and hits.map(func(e): return e.source) == ids.slice(0, 2) and hits.map(func(e): return e.amount) == [4, 8], "living enemies retaliate in authored order and dead enemy is skipped")
		check(session.entity(session.state.active_party[0]).hp == 105, "two distinct enemy hits settle once")
		for _i in range(80):
			if not session.battle_open(): break
			battle = session.state.extensions[Battle.KEY]
			var target: int = 0
			while battle.enemies[target].hp == 0: target += 1
			await _click(app.options.get_child(target))
		check(not session.battle_open() and session.state.cursor.node_id == win, "all enemies must be defeated before authored win callback " + str(size))
		check(app.saves.load_into(session, save_path) and session.state.extensions[Battle.KEY] == saved_battle, "load restores all enemy identities, order, HP, MP and dead target")
		if saves.size() > 1:
			before = session.state.duplicate(true)
			check(not app.saves.load_into(session, saves[0].save_path) and session.state == before, "different content lock cannot replace current battle state")
		root.remove_child(app); app.queue_free(); await process_frame
	# This package is a declared synthetic 32-enemy capacity expansion, not a balanced encounter.
	var app = App.instantiate(); root.add_child(app); await process_frame
	app.saves = Save.new(output.path_join("capacity-saves"))
	if not check(app.open_package(args[3]), "synthetic 32-enemy package loads"):
		_finish(); return
	await process_frame; await process_frame; await _click(app.options.get_child(0))
	var session = app.session; var battle: Dictionary = session.state.extensions[Battle.KEY]
	check(battle.enemies.size() == 32 and app.battle_view.page_count() == 4 and app.target_pages.visible, "all 32 enemies retained behind four presentation pages")
	for page in range(1, 4):
		var before: Dictionary = session.state.duplicate(true)
		await _click(app.target_pages.get_child(2))
		# The window continues ticking while mouse input crosses frames. A tick
		# increments the revision once; pagination must add no other mutation.
		before.state_revision += session.state.clock.logic_tick - before.clock.logic_tick
		before.clock = session.state.clock.duplicate(true)
		check(app.battle_view.enemy_page == page and session.state == before, "enemy page changes only elapsed clock ticks " + str(page + 1))
	check(app.options.get_child(7).text == "攻击 32 · 练习苗兵" and app.target_pages.get_child(2).disabled, "final authored target remains reachable and numbered")
	for control in app.options.get_children():
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(control.get_global_rect()), "capacity command remains inside actual application window")
	await _click(app.options.get_child(7)); battle = session.state.extensions[Battle.KEY]
	check(battle.enemies[31].hp == 18 and battle.enemies.slice(0, 31).all(func(e): return e.hp == 36), "page-four input damages only enemy instance 32")
	await _click(app.save_button); var save_path: String = app.saves.last_path
	if not check(not save_path.is_empty(), "32-enemy command state is saved"):
		_finish(); return
	saves.append({"party": 4, "enemy_count": 32, "package_path": args[3], "save_path": save_path, "synthetic_capacity": true})
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("capacity-32.png"))
	check(app.saves.load_into(session, save_path) and app.battle_view.enemy_page == 0 and session.state.extensions[Battle.KEY].enemies[31].hp == 18, "load resets display page while preserving remote target state")
	root.remove_child(app); app.queue_free(); await process_frame; _finish()
func _finish() -> void:
	var report = {"checks": checks, "failed": failed, "saves": saves, "physical_input": false, "engine_injected_input": true, "synthetic_capacity": true, "full_playthrough": false}
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t")); print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
func _click(control: Control) -> void:
	var point = control.get_global_rect().get_center()
	for down in [true, false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event, true)
	await process_frame; await process_frame
