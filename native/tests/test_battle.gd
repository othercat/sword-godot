# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
const Schema = preload("res://src/native_schema.gd")
const NativeJSON = preload("res://src/native_json.gd")
var checks: Array = []
var failed: int = 0
var saves: Array = []
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok:
		failed += 1; push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4:
		quit(2); return
	DirAccess.make_dir_recursive_absolute(args[3]); root.size = Vector2i(1280, 800)
	for package_path in args.slice(0, 3):
		var app = App.instantiate(); root.add_child(app); await process_frame
		app.saves = Save.new(args[3].path_join("saves"))
		check(app.open_package(package_path), "actual author battle package loads")
		if app.session == null:
			_finish(args[3]); return
		await process_frame; await process_frame; await _click(app.options.get_child(0))
		var session = app.session; var size: int = session.state.active_party.size()
		check(session.battle_open() and not session.dialogue_open and app.battle_view.visible and not app.world_view.visible, "battle owns application input and presentation " + str(size))
		if not session.battle_open():
			_finish(args[3]); return
		var before: Dictionary = session.state.duplicate(true)
		check(not session.move(Vector2i.DOWN) and not session.interact() and session.state == before, "map movement and interaction are blocked during commands")
		check(not session.battle_command("attack", "enemy.missing") and session.state == before, "invalid target leaves exact state intact")
		check(not session.battle_command("unknown") and session.state == before, "unknown action leaves exact state intact")
		session.paused = true; check(not session.battle_command("guard") and session.state == before, "pause blocks battle command"); session.paused = false
		await _click(app.options.get_child(1))
		check(session.state.extensions[Battle.KEY].turn == 1 and session.state.extensions[Battle.KEY].guarding == [session.state.active_party[0]], "mouse guard consumes only first actor turn")
		await _click(app.save_button); var save_path: String = app.saves.last_path
		check(not save_path.is_empty(), "battle command save is published")
		if save_path.is_empty():
			print("save failure: " + session.error); _finish(args[3]); return
		var saved_battle: Dictionary = session.state.extensions[Battle.KEY].duplicate(true)
		saves.append({"party": size, "package_path": package_path, "save_path": save_path})
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[3].path_join("battle-" + str(size) + ".png"))
		var hp_before: int = session.state.extensions[Battle.KEY].enemies[0].hp
		await _click(app.options.get_child(0))
		check(session.state.extensions[Battle.KEY].enemies[0].hp == hp_before - 18 and session.state.extensions[Battle.KEY].turn == 2, "mouse attack applies declared damage and advances the next actor")
		before = session.state.duplicate(true)
		var display_before: float = app.battle_view._elapsed
		app.battle_view._process(1.0 / 60); app.battle_view._process(1.0 / 100)
		check(app.battle_view._elapsed > display_before and session.state == before, "60/100 presentation steps never advance authority")
		session.paused = true; display_before = app.battle_view._elapsed; app.battle_view._process(1.0)
		check(app.battle_view._elapsed == display_before, "pause freezes battle presentation"); session.paused = false
		var old_history: String = app.battle_view._event_key
		check(app.saves.load_into(session, save_path) and session.state.extensions[Battle.KEY] == saved_battle and app.battle_view._event_key != old_history, "load restores commands and resets presentation history")
		var node: Dictionary = session.current_node(); var win: String = node.on_win
		# Synthetic callback failure checks the existing all-or-nothing story boundary.
		node.on_win = "node.missing"
		var seen: Array = [session.state.active_party[0]]; var rejected: bool = false
		for _i in range(200):
			var battle: Dictionary = session.state.extensions[Battle.KEY]
			if battle.party[battle.turn] not in seen: seen.append(battle.party[battle.turn])
			var target: String = battle.enemies.filter(func(e): return e.hp > 0)[0].instance_id
			before = session.state.duplicate(true)
			if not session.battle_command("attack", target):
				check(session.state == before, "failed outcome callback rolls back damage and settlement")
				rejected = true; break
		check(rejected and seen.size() == size, "all configured party members reach command turns " + str(size))
		node.on_win = win
		check(session.battle_command("attack", session.state.extensions[Battle.KEY].enemies[0].instance_id) and not session.battle_open() and session.state.cursor.node_id == win, "victory enters exactly the win callback")
		before = session.state.duplicate(true)
		check(not session.battle_command("attack", "enemy.missing") and session.state == before, "finished battle cannot settle twice")
		check(app.saves.load_into(session, save_path) and session.state.extensions[Battle.KEY] == saved_battle, "load resumes exact enemy HP, turn, guard, round and execution identity")
		await _click(app.options.get_child(2))
		check(not session.battle_open() and session.state.cursor.node_id == node.on_escape, "mouse escape selects its own callback")
		check(app.saves.load_into(session, save_path), "saved command restores before loss variant")
		var definition: Dictionary = session.package.index.actor_definitions[session.state.extensions[Battle.KEY].enemies[0].definition_id]
		var original_combat: Dictionary = definition.combat.duplicate(true)
		definition.combat = {"attack": 1000000, "defense": 1000000}
		for _i in range(200):
			if not session.battle_open(): break
			check(session.battle_command("guard"), "synthetic enemy death/retarget round progresses")
		check(not session.battle_open() and session.state.cursor.node_id == node.on_loss and session.state.active_party.all(func(id): return session.entity(id).hp == 0), "defeat excludes dead turns and takes loss callback")
		definition.combat = original_combat
		check(app.saves.load_into(session, save_path), "restore command after loss variant")
		var encounter: Dictionary = Battle.encounter(session.package.world, node.encounter_id)
		encounter.allow_escape = false; before = session.state.duplicate(true)
		check(not session.battle_command("escape") and session.state == before, "forbidden escape is inert")
		encounter.allow_escape = true
		var invalid: Dictionary = session.state.duplicate(true); invalid.extensions[Battle.KEY].turn = size
		check(not session.restore(invalid) and session.state == before, "out-of-range saved turn is rejected before restore")
		invalid = session.state.duplicate(true); invalid.extensions[Battle.KEY].party.reverse()
		check(not session.restore(invalid) and session.state == before, "reordered saved battle party is rejected")
		for forged in ["effect." + "a".repeat(64), "effect." + Schema.digest(JSON.stringify([session.state.run_id, session.state.extensions["pal.native.executor"].activation, session.state.extensions["pal.native.executor"].step, node.on_win]).to_utf8_buffer())]:
			invalid = session.state.duplicate(true); invalid.extensions[Battle.KEY].execution_id = forged
			check(not session.restore(invalid) and session.state == before, "forged or next-callback battle execution ID is rejected")
		for token in ["1.0", "1e0"]:
			var raw: String = JSON.stringify(session.state).replace('"turn":1', '"turn":' + token)
			var normalized = NativeJSON.new().decode(raw.to_utf8_buffer())
			check(session.validate_saved(normalized).is_empty(), "integral JSON turn notation remains loadable " + token)
		root.remove_child(app); app.queue_free(); await process_frame
	_finish(args[3])
func _finish(output: String) -> void:
	var report = {"checks": checks, "failed": failed, "saves": saves, "physical_input": false, "engine_injected_input": true, "synthetic_callback_and_loss_variants": true, "full_playthrough": false}
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t")); print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
func _click(control: Control) -> void:
	var p = control.get_global_rect().get_center()
	for down in [true, false]:
		var e = InputEventMouseButton.new(); e.position = p; e.global_position = p; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; root.push_input(e, true)
	await process_frame; await process_frame
