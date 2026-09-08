# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
const Skills = preload("res://src/native_skills.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4: quit(2); return
	output = args[3]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	for package_path in args.slice(0, 3):
		var app = App.instantiate(); root.add_child(app); await process_frame; app.saves = Save.new(output.path_join("saves"))
		if not app.open_package(package_path): check(false, "owner skill package loads"); _finish(); return
		await process_frame; await process_frame; await click(option(app, "继续"))
		var session = app.session; var size: int = session.state.active_party.size(); var party: Array = session.state.active_party.duplicate()
		check(session.battle_open(), "skills enter actual battle " + str(size))
		var catalog: Array = session.package.world.skill_definitions; var single: String = catalog[0].id; var all_skill: String = catalog[1].id; var revival: String = catalog[3].id
		var battle: Dictionary = session.state.extensions[Battle.KEY]; var enemies: Array = battle.enemies.map(func(e): return e.instance_id)
		check(catalog.size() == 5 and party.all(func(id): return session.package.index.actor_definitions[session.entity(id).definition_id].skill_ids.size() == 5), "author catalog and shared role loadouts reach every party member")
		var before: Dictionary = session.state.duplicate(true)
		check(not session.battle_command("skill", enemies[0], "skill.missing") and session.state == before, "unknown or unowned skill leaves exact state")
		check(not session.battle_command("skill", enemies[0], catalog[4].id) and session.state == before, "unaffordable skill never debits MP")
		check(not session.battle_command("skill", party[0], single) and session.state == before, "wrong-side target cannot consume a turn")
		check(not session.battle_command("skill", enemies[0], all_skill) and session.state == before, "all-target skill refuses a forged single target")
		await click(option(app, "技能"))
		check(option(app, "回魂术 ·").disabled and option(app, "真气不足样例 ·").disabled, "menu disables missing dead targets and insufficient MP")
		await click(option(app, "回风诀 ·")); await click(option(app, "取消"))
		check(clock_only(before, session.state) and app.skill_menu.mode == "closed", "choosing and cancelling only advances normal clock ticks")
		await click(option(app, "技能")); await click(option(app, "回风诀 ·")); var old_context: String = app.skill_menu.context
		await click(option(app, "施放于全部")); battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).mp == 45 and battle.enemies.map(func(e): return e.hp) == [85, 85, 85], "all-target effects apply to each enemy but debit MP once")
		check(battle.events.map(func(e): return e.kind) == ["cast", "damage", "damage", "damage"] and battle.events[0].amount == 5, "result list records one debit and each ordered target")
		before = session.state.duplicate(true); app.skill_menu.commit(app, all_skill, "", old_context)
		check(session.state == before, "stale selection cannot cast on the next actor turn")
		await click(option(app, "技能")); await click(option(app, "破风斩 ·")); await click(option(app, "3 ·")); battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[1]).mp == 37 and battle.enemies.map(func(e): return e.hp) == [85, 85, 55], "single target damages only the selected enemy instance")
		for _guard in range(size):
			if session.state.extensions[Battle.KEY].round != 1: break
			await click(option(app, "防御"))
		battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 0 and battle.turn == 1, "normal enemy retaliation kills the hero and skips the dead turn")
		before = session.state.duplicate(true)
		check(not session.battle_command("skill", party[1], revival) and session.state == before, "revival refuses a living ally without cost")
		await click(option(app, "技能")); await click(option(app, "回魂术 ·"))
		check(not option(app, "1 ·").disabled and option(app, "2 ·").disabled, "revival target menu selects dead allies only")
		await click(app.save_button); var selection_save: String = app.saves.last_path
		if selection_save.is_empty(): check(false, "selection save written"); _finish(); return
		saves.append({"party": size, "stage": "before-revive", "package_path": package_path, "save_path": selection_save})
		check(app.saves.load_into(session, selection_save) and app.skill_menu.mode == "closed" and session.entity(party[1]).mp == 37, "load clears pending UI choice without charging it")
		await click(option(app, "技能")); await click(option(app, "回魂术 ·")); await click(option(app, "1 ·")); battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 20 and session.entity(party[0]).mp == 45 and session.entity(party[1]).mp == 31, "revive then heal settles in order and preserves revived actor MP")
		check(battle.events.map(func(e): return e.kind) == ["cast", "revive", "heal"] and battle.events.map(func(e): return e.amount) == [6, 12, 8] and battle.turn == 2, "revived earlier actor gets no duplicate turn")
		await click(app.save_button); var saved: String = app.saves.last_path
		if saved.is_empty(): check(false, "revived command save written"); _finish(); return
		saves.append({"party": size, "stage": "after-revive", "package_path": package_path, "save_path": saved})
		var saved_battle: Dictionary = session.state.extensions[Battle.KEY].duplicate(true)
		before = session.state.duplicate(true)
		var incomplete: Dictionary = before.duplicate(true); incomplete.extensions[Battle.KEY].events.remove_at(1)
		check(not session.validate_saved(incomplete).is_empty() and session.state == before, "save rejects missing declared revival effect without changing live state")
		incomplete = before.duplicate(true)
		incomplete.extensions[Battle.KEY].events.insert(2, {"kind": "attack", "source": enemies[0], "target": party[0], "amount": 1})
		check(not session.validate_saved(incomplete).is_empty() and session.state == before, "save rejects retaliation interrupting ordered skill effects")
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("battle-" + str(size) + ".png"))
		await click(option(app, "技能")); await click(option(app, "回春术 ·")); await click(option(app, "施放于全部")); battle = session.state.extensions[Battle.KEY]
		var heals: Array = battle.events.filter(func(e): return e.kind == "heal")
		check(heals.size() == size * 2 and heals[0].amount == 10 and heals[size].amount == 0 and session.entity(party[2]).mp == 36, "all-ally healing clamps to maxima and follows both effect components")
		before = session.state.duplicate(true); incomplete = before.duplicate(true); incomplete.extensions[Battle.KEY].events.remove_at(1)
		check(not session.validate_saved(incomplete).is_empty() and session.state == before, "save rejects a missing target in an all-target effect block")
		# Explicit synthetic callback failure; restore the actual package definitions afterwards.
		var node: Dictionary = session.current_node(); var win: String = node.on_win; var power: int = catalog[1].effects[0].power
		catalog[1].effects[0].power = 1000000; node.on_win = "node.missing"; before = session.state.duplicate(true)
		check(not session.battle_command("skill", "", all_skill) and session.state == before, "failed win callback rolls back skill MP, targets, events and turn together")
		catalog[1].effects[0].power = power; node.on_win = win
		for _i in range(80):
			if not session.battle_open(): break
			battle = session.state.extensions[Battle.KEY]; var index: int = 0
			while battle.enemies[index].hp == 0: index += 1
			await click(option(app, "技能")); await click(option(app, "破风斩 ·")); await click(option(app, str(index + 1) + " ·"))
		check(not session.battle_open() and session.state.cursor.node_id == win, "skill victory enters authored callback " + str(size))
		check(app.saves.load_into(session, saved) and session.state.extensions[Battle.KEY] == saved_battle and session.entity(party[0]).hp == 20 and session.entity(party[1]).mp == 31, "revived save restores exact results without replaying skill cost")
		before = session.state.duplicate(true); app.battle_view._process(1.0 / 60); app.battle_view._process(1.0 / 100)
		check(session.state == before, "60/100 display updates never resolve skill effects")
		if saves.size() > 2:
			before = session.state.duplicate(true)
			check(not app.saves.load_into(session, saves[0].save_path) and session.state == before, "cross-content skill save is rejected atomically")
		root.remove_child(app); app.queue_free(); await process_frame
	_finish()
func clock_only(before: Dictionary, after: Dictionary) -> bool:
	var expected = before.duplicate(true); expected.state_revision += after.clock.logic_tick - before.clock.logic_tick; expected.clock = after.clock.duplicate(true); return expected == after
func option(app, prefix: String) -> Button:
	for child in app.options.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false, "missing option " + prefix); return null
func click(control: Control) -> void:
	if control == null: return
	var point = control.get_global_rect().get_center()
	for down in [true, false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event, true)
	await process_frame; await process_frame
func _finish() -> void:
	var report = {"checks": checks, "failed": failed, "saves": saves, "physical_input": false, "engine_injected_input": true, "synthetic_callback_failure": true, "full_playthrough": false}
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t")); print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
