# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
const Inventory = preload("res://src/native_inventory.gd")
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
		if not app.open_package(package_path): check(false, "owner item package loads: " + app.session.error); _finish(); return
		await process_frame; await process_frame; await click(option(app, "继续"))
		var session = app.session; var size: int = session.state.active_party.size(); var party: Array = session.state.active_party.duplicate()
		check(session.battle_open(), "grant enters actual battle " + str(size))
		var catalog: Array = session.package.world.item_definitions
		var single: String = catalog[0].id; var all_item: String = catalog[1].id; var healing: String = catalog[2].id; var revival: String = catalog[3].id; var reusable: String = catalog[4].id
		var battle: Dictionary = session.state.extensions[Battle.KEY]; var enemies: Array = battle.enemies.map(func(e): return e.instance_id)
		check(catalog.size() == 9 and Inventory.count(session.state, single) == 3 and Inventory.count(session.state, catalog[6].id) == 500 and session.state.committed_effect_ids.size() == 1, "initial inventory and opening grant preserve counts above 99 and commit once")
		var before: Dictionary = session.state.duplicate(true)
		check(not session.battle_command("item", enemies[0], "", "item.missing") and session.state == before, "unknown item leaves exact state")
		check(not session.battle_command("item", party[0], "", single) and session.state == before, "wrong-side item target never spends a turn or inventory")
		check(not session.battle_command("item", enemies[0], "", all_item) and session.state == before, "all-target item rejects forged single target")
		check(not session.battle_command("item", party[0], "", catalog[5].id) and session.state == before, "empty stack cannot be used")
		check(not session.battle_command("item", party[0], "", catalog[6].id) and session.state == before, "quest item cannot be used in battle")
		check(not session.battle_command("guard", "", "", single) and session.state == before, "item identity cannot leak into another action")
		var candidate: Dictionary = before.duplicate(true)
		check(not Inventory.change(session.package, candidate, [{"item_id": single, "delta": -1}, {"item_id": healing, "delta": -1000000}]).is_empty() and candidate == before, "multi-item underflow keeps the complete candidate inventory")
		check(not Inventory.change(session.package, candidate, [{"item_id": single, "delta": -1}, {"item_id": healing, "delta": 1000000}]).is_empty() and candidate == before, "multi-item overflow never clamps or partially applies")
		check(has_option(app.options, "技能") and has_option(app.options, "物品"), "skill and item commands coexist")
		await click(option(app, "物品"))
		check(not has_option(app.options, "技能") and option(app, "返魂香 ·").disabled and option(app, "空药瓶 ·").disabled and option(app, "行路札记 ·").disabled, "item menu excludes the skill menu and disables illegal uses")
		await click(find_button(app.target_pages, "下一组")); check(option(app, "路引 ·").disabled, "item catalog paging reaches the ninth definition without changing inventory")
		await click(find_button(app.target_pages, "上一组")); await click(option(app, "霹雳弹 ·")); await click(option(app, "取消"))
		check(clock_only(before, session.state) and app.item_menu.mode == "closed", "selection and cancel only advance normal clock ticks")
		await click(option(app, "物品")); await click(option(app, "霹雳弹 ·"))
		var opening: String = await save(app, package_path, size, "before-use")
		check(app.saves.load_into(session, opening) and app.item_menu.mode == "closed" and app.skill_menu.mode == "closed" and Inventory.count(session.state, all_item) == 2, "load clears both menus and does not replay grant or charge pending selection")
		await click(option(app, "物品")); await click(option(app, "霹雳弹 ·")); var old_context: String = app.item_menu.context
		await click(option(app, "用于全部")); battle = session.state.extensions[Battle.KEY]
		check(Inventory.count(session.state, all_item) == 1 and session.entity(party[0]).mp == 50 and battle.enemies.map(func(e): return e.hp) == [85,85,85], "all enemies receive effects but only one unit and zero MP are spent")
		check(battle.events.map(func(e): return e.kind) == ["item_use","damage","damage","damage"] and battle.events[0].amount == 1, "item result block records one consumption followed by ordered targets")
		before = session.state.duplicate(true); app.item_menu.commit(app, all_item, "", old_context)
		check(session.state == before, "stale item callback cannot consume the next actor inventory")
		await save(app, package_path, size, "after-use")
		var malformed: Dictionary = before.duplicate(true)
		for stack in malformed.extensions[Inventory.KEY].stacks:
			if stack.item_id == all_item: stack.count = catalog[1].max_stack
		check(not session.validate_saved(malformed).is_empty(), "saved post-use maximum rejects impossible pre-use overflow")
		malformed = before.duplicate(true); malformed.extensions[Battle.KEY].events.remove_at(1)
		# For all-target damage a dead target may be absent; a whole missing effect is never legal.
		malformed.extensions[Battle.KEY].events = malformed.extensions[Battle.KEY].events.slice(0,1)
		check(not session.validate_saved(malformed).is_empty(), "saved item requires its complete declared effect block")
		await click(option(app, "物品")); await click(option(app, "爆竹 ·")); await click(option(app, "3 ·")); battle = session.state.extensions[Battle.KEY]
		check(Inventory.count(session.state, single) == 2 and battle.enemies.map(func(e): return e.hp) == [85,85,55] and session.entity(party[1]).mp == 40, "single item affects only the chosen instance and does not spend MP")
		for _guard in range(size):
			if session.state.extensions[Battle.KEY].round != 1: break
			await click(option(app, "防御"))
		battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 0 and battle.turn == 1, "enemy retaliation naturally kills the hero before item revival")
		before = session.state.duplicate(true)
		check(not session.battle_command("item", party[1], "", revival) and session.state == before, "revival on a living target is rejected without consumption")
		await click(option(app, "物品")); await click(option(app, "返魂香 ·"))
		check(not option(app, "1 ·").disabled and option(app, "2 ·").disabled, "revival item offers only dead targets")
		await click(option(app, "1 ·")); battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 20 and session.entity(party[0]).mp == 50 and session.entity(party[1]).mp == 40 and Inventory.count(session.state, revival) == 0, "last revival unit settles revive then heal and preserves all MP")
		check(battle.events.map(func(e): return e.kind) == ["item_use","revive","heal"] and battle.events.map(func(e): return e.amount) == [1,12,8] and battle.turn == 2, "revived earlier actor gets no duplicate turn")
		var revived: String = await save(app, package_path, size, "after-revive"); var saved_battle: Dictionary = session.state.extensions[Battle.KEY].duplicate(true)
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("battle-" + str(size) + ".png"))
		before = session.state.duplicate(true)
		check(not session.battle_command("item", party[0], "", revival) and session.state == before, "used last unit cannot be consumed again")
		await click(option(app, "物品")); check(option(app, "返魂香 ·").disabled, "depleted item remains visible and disabled")
		await click(option(app, "回春散 ·")); await click(option(app, "用于全部")); battle = session.state.extensions[Battle.KEY]
		var heals: Array = battle.events.filter(func(e): return e.kind == "heal")
		check(heals.size() == size*2 and heals[0].amount == 10 and heals[size].amount == 0 and Inventory.count(session.state, healing) == 1, "all-ally healing shares ordered clamped effects and consumes once")
		await click(option(app, "物品")); await click(option(app, "护身符 ·")); await click(option(app, "1 ·")); battle = session.state.extensions[Battle.KEY]
		check(Inventory.count(session.state, reusable) == 1 and battle.events[0].kind == "item_use" and battle.events[0].amount == 0, "reusable item requires ownership and spends no stack unit")
		malformed = session.state.duplicate(true); malformed.extensions[Inventory.KEY].stacks = malformed.extensions[Inventory.KEY].stacks.filter(func(s): return s.item_id != reusable)
		check(not session.validate_saved(malformed).is_empty(), "saved reusable-item command cannot lose its owned unit")
		# Explicit synthetic fault injection into a loaded definition; always restore it.
		var node: Dictionary = session.current_node(); var reward_id: String = node.on_win; var reward: Dictionary = session.package.index.nodes[reward_id]
		var win: String = reward.next; var power: int = catalog[1].battle_use.effects[0].power; var delta: int = reward.changes[0].delta
		catalog[1].battle_use.effects[0].power = 1000000; node.on_win = "node.missing"; before = session.state.duplicate(true)
		check(not session.battle_command("item", "", "", all_item) and session.state == before, "missing victory callback rolls back item, HP, results and battle turn")
		node.on_win = reward_id; reward.changes[0].delta = 1000000
		check(not session.battle_command("item", "", "", all_item) and session.state == before, "overflowing reward rolls back the whole victory transaction")
		reward.changes[0].delta = delta; catalog[1].battle_use.effects[0].power = power
		for _i in range(100):
			if not session.battle_open(): break
			battle = session.state.extensions[Battle.KEY]; var index: int = 0
			while battle.enemies[index].hp == 0: index += 1
			if Inventory.count(session.state, single) > 0:
				await click(option(app, "物品")); await click(option(app, "爆竹 ·")); await click(option(app, str(index+1) + " ·"))
			else: await click(option(app, "攻击 " + str(index+1) + " ·"))
		check(not session.battle_open() and session.state.cursor.node_id == win and Inventory.count(session.state, healing) == 4 and session.state.committed_effect_ids.size() == 3, "victory commits battle and one authored reward " + str(size))
		var reward_save: String = await save(app, package_path, size, "after-reward")
		check(app.saves.load_into(session, reward_save) and Inventory.count(session.state, healing) == 4 and session.state.committed_effect_ids.size() == 3, "reward save resumes without regranting")
		check(app.saves.load_into(session, revived) and session.state.extensions[Battle.KEY] == saved_battle and Inventory.count(session.state, revival) == 0 and Inventory.count(session.state, healing) == 2, "revival save restores exact inventory/results without replaying use or later reward")
		before = session.state.duplicate(true); app.battle_view._process(1.0/60); app.battle_view._process(1.0/100)
		check(session.state == before, "60/100 display updates never consume items")
		if saves.size() > 4:
			before = session.state.duplicate(true)
			check(not app.saves.load_into(session, saves[0].save_path) and session.state == before, "cross-content item save is rejected atomically")
		root.remove_child(app); app.queue_free(); await process_frame
	_finish()
func save(app, package_path: String, size: int, stage: String) -> String:
	await click(app.save_button); var path: String = app.saves.last_path
	check(not path.is_empty() and app.session.validate_saved(app.session.state).is_empty(), "actual item save written: " + stage)
	saves.append({"party":size,"stage":stage,"package_path":package_path,"save_path":path}); return path
func clock_only(before: Dictionary, after: Dictionary) -> bool:
	var expected = before.duplicate(true); expected.state_revision += after.clock.logic_tick-before.clock.logic_tick; expected.clock = after.clock.duplicate(true); return expected == after
func has_option(parent, prefix: String) -> bool:
	return parent.get_children().any(func(c): return c is Button and c.text.begins_with(prefix))
func find_button(parent, prefix: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false, "missing option " + prefix); return null
func option(app, prefix: String) -> Button: return find_button(app.options, prefix)
func click(control: Control) -> void:
	if control == null: return
	var point = control.get_global_rect().get_center()
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event,true)
	await process_frame; await process_frame
func _finish() -> void:
	var report = {"checks":checks,"failed":failed,"saves":saves,"physical_input":false,"engine_injected_input":true,"synthetic_callback_failure":true,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")); print(JSON.stringify(report)); quit(0 if failed==0 else 1)
