# SPDX-License-Identifier: MIT
extends SceneTree
## Fixed authored content, ordinary commands only: no HP, cursor, variables or
## package mutations. Model routes and injected UI routes are reported separately.
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const App = preload("res://scenes/main.tscn")
const Battle = preload("res://src/native_battle.gd")
const Inventory = preload("res://src/native_inventory.gd")
var checks: Array = []
var routes: Array = []
var saves: Array = []
var failed: int = 0
var output: String
var package_path: String
var s
var store
var app
var route_name: String

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, name: String) -> bool:
	checks.append({"passed": ok, "name": route_name + ": " + name})
	if not ok: failed += 1; push_error(name + (" / " + s.error if s != null else ""))
	return ok
func flag(name: String): return s.state.scopes.run["flag.miaopang.camp." + name]
func nid(name: String) -> String: return "node.miaopang.camp." + name
func sid(name: String) -> String: return "scene.miaopang.camp." + name
func at(name: String) -> bool: return s.current_node().id == nid(name)
func key(code: int, down: bool) -> void:
	var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down; Input.parse_input_event(event)
func press(code: int) -> void:
	key(code, true); await process_frame; key(code, false); await process_frame; await process_frame
func click(text: String) -> bool:
	await process_frame
	for child in app.options.get_children():
		if child is Button and not child.disabled and child.text.begins_with(text):
			child.grab_focus(); await process_frame
			await press(KEY_ENTER)
			return true
	return check(false, "missing enabled UI option " + text)
func presentation() -> void:
	if app == null: return
	# Let real generated animation run. UI-input cases do not call skip(), freeze
	# processing, change HP or bypass the command window.
	var deadline: int = Time.get_ticks_msec() + 15000
	while app.battle_view.playing() and Time.get_ticks_msec() < deadline: await process_frame
	check(not app.battle_view.playing(), "animation completes normally")
func dialogue() -> bool:
	for i in range(30):
		await presentation()
		if not s.dialogue_open or s.current_node().op != "dialogue": return true
		if app == null:
			if not check(s.advance_dialogue(), "dialogue " + s.current_node().id): return false
		else:
			if not await click("继续"): return false
	return check(false, "dialogue chain exceeds expected bound")
func choose(choice: String) -> bool:
	for option in s.current_node().get("options", []):
		if option.id.ends_with("." + choice):
			return await click(option.text) if app != null else check(s.advance_dialogue(option.id), "choice " + choice)
	return check(false, "missing choice " + choice)
func position() -> Vector2i:
	var point: Dictionary = s.entity(s.state.active_party[0]).position
	return Vector2i(point.x, point.y)
func walk(destination: Vector2i) -> bool:
	for step in range(80):
		if position() == destination: return true
		var start: Vector2i = position(); var parents: Dictionary = {start: start}; var queue: Array = [start]; var head: int = 0
		var occupied: Dictionary = {}
		for entity in s.state.entities:
			if entity.scene_id == s.state.cursor.scene_id and entity.instance_id not in s.state.active_party: occupied[Vector2i(entity.position.x, entity.position.y)] = true
		while head < queue.size() and not parents.has(destination):
			var point: Vector2i = queue[head]; head += 1
			for delta in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var target: Vector2i = point + delta
				if target.x < 129 or target.x > 134 or target.y < 68 or target.y > 76 or parents.has(target) or occupied.has(target): continue
				if not s.package.can_stand(s.state.cursor.scene_id, {"x": target.x, "y": target.y}): continue
				parents[target] = point; queue.append(target)
		if not check(parents.has(destination), "walkable route to " + str(destination)): return false
		var next: Vector2i = destination
		while parents[next] != start: next = parents[next]
		var delta: Vector2i = next - start
		if app == null:
			for tick in range(8): s.tick()
			if not check(s.move(delta), "normal move " + str(next)): return false
		else:
			var code: int = KEY_W if delta == Vector2i.UP else KEY_S if delta == Vector2i.DOWN else KEY_A if delta == Vector2i.LEFT else KEY_D
			var focus = root.gui_get_focus_owner()
			if focus != null: focus.release_focus()
			key(code, true); var deadline: int = Time.get_ticks_msec() + 2000
			while position() == start and Time.get_ticks_msec() < deadline: await process_frame
			key(code, false); await process_frame
			if not check(position() == next, "injected movement key " + str(next)): return false
	return check(false, "movement budget exhausted")
func interact() -> bool:
	if app == null: return check(s.interact(), "normal interaction")
	var cursor: String = s.state.cursor.node_id
	await press(KEY_SPACE)
	return check(cursor != s.state.cursor.node_id, "injected interaction reaches authored node")
func door(point: Vector2i, scene: String) -> bool:
	if not await walk(point) or not await interact(): return false
	if not check(s.state.cursor.scene_id == sid(scene), "arrived " + scene): return false
	return await dialogue()
func checkpoint(label: String) -> bool:
	var before: Dictionary = s.snapshot()
	if app == null:
		if not check(store.save(s), "save " + label + " " + store.error): return false
	else:
		await press(KEY_F5)
		if not check(not store.last_path.is_empty(), "F5 save " + label): return false
	saves.append({"package_path": package_path, "save_path": store.last_path, "route": route_name, "checkpoint": label})
	if not check(store.load_into(s, store.last_path), "resume " + label + " " + store.error): return false
	return check(s.state.entities == before.entities and s.state.scopes == before.scopes and s.state.committed_effect_ids == before.committed_effect_ids and s.state.extensions.get(Inventory.KEY) == before.extensions.get(Inventory.KEY), "resume preserves actors, inventory and story effects " + label)
func shot(name: String) -> void:
	if app == null: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func fight(outcome: String) -> bool:
	if not check(s.battle_open() and s.state.active_party.size() == 5, "five actual participants enter encounter"): return false
	if not await checkpoint("battle-entry"): return false
	await shot("five-person-battle")
	for turn in range(400):
		await presentation()
		if not s.battle_open():
			if not check(flag("practice") == outcome, "normal battle outcome " + outcome): return false
			return await dialogue()
		var battle: Dictionary = s.state.extensions[Battle.KEY]
		var target: String = ""
		for enemy in battle.enemies:
			if enemy.hp > 0: target = enemy.instance_id; break
		if app != null:
			if not await click("攻击 " if outcome == "win" else "防御" if outcome == "loss" else "撤离"): return false
		elif turn == 0 and outcome == "win":
			if not check(s.battle_command("skill", target, "skill.miaopang.camp.heavy"), "authored skill command"): return false
		elif turn == 5 and outcome == "win":
			if not check(s.battle_command("item", "instance.miaopang.camp.hero", "", "item.miaopang.camp.medicine"), "authored medicine command"): return false
		else:
			if not check(s.battle_command("attack" if outcome == "win" else "guard" if outcome == "loss" else "escape", target if outcome == "win" else ""), "battle command " + str(turn)): return false
		if turn == 2 and s.battle_open():
			await presentation()
			if not await checkpoint("battle-middle"): return false
	return check(false, "battle turn budget exceeded")
func route(outcome: String, pack: String) -> bool:
	if not await checkpoint("opening"): return false
	if not await dialogue() or not await choose("skip" if outcome == "skip" else "train") or not await dialogue(): return false
	if outcome != "skip" and not await fight(outcome): return false
	if not await checkpoint("after-practice"): return false
	if outcome == "loss":
		return check(at("loss-end") and s.state.cursor.scene_id == sid("loss") and not flag("mission") and s.state.entities.filter(func(x): return x.instance_id in s.state.active_party).all(func(x): return x.hp == 0), "defeat ends independently without forged healing or mission progress")
	if not check(s.state.active_party.size() == 3, "two temporary camp soldiers leave active party"): return false
	var experience_before: Dictionary = {}
	for actor in s.state.entities:
		if actor.components.has(Session.Progression.KEY): experience_before[actor.instance_id] = actor.components[Session.Progression.KEY].duplicate(true)
	if not await walk(Vector2i(130, 73)) or not await interact() or not await dialogue(): return false
	if not check(s.state.active_party == ["instance.miaopang.camp.hero"] and flag("summoned"), "canonical solo audience starts after token verification"): return false
	if not await door(Vector2i(130, 76), "path") or not await door(Vector2i(134, 74), "stone"): return false
	if not check(not s.portal_status(s.package.index.scenes[sid("stone")].portals[1]).allowed, "supply door initially locked"): return false
	if not await walk(Vector2i(132, 73)) or not await interact() or not await dialogue(): return false
	if not check(flag("mission"), "Stone Elder mission recorded"): return false
	if not await door(Vector2i(134, 74), "supply"): return false
	if not await walk(Vector2i(132, 73)) or not await interact() or not await choose(pack) or not await dialogue(): return false
	if not check(flag("pack") == pack and flag("supplied"), "selected supply branch " + pack): return false
	if not await checkpoint("supply"): return false
	var inventory: Dictionary = s.state.extensions[Inventory.KEY].duplicate(true)
	if not await interact() or not await dialogue(): return false
	if not check(inventory == s.state.extensions[Inventory.KEY], "repeat NPC interaction cannot duplicate supplies"): return false
	if not await door(Vector2i(130, 74), "stone") or not await door(Vector2i(130, 74), "path") or not await door(Vector2i(130, 74), "camp"): return false
	if not check(s.state.active_party.size() == 3, "original three reunite after return"): return false
	if not await checkpoint("return-camp"): return false
	if not await walk(Vector2i(130, 73)) or not await interact() or not await dialogue() or not await choose("leave") or not await dialogue(): return false
	if not await door(Vector2i(132, 76), "departure"): return false
	if not check(flag("complete") and s.state.active_party.size() == 3, "complete authored opening with canonical three"): return false
	await shot("departure-complete")
	if not await checkpoint("complete"): return false
	if not await door(Vector2i(130, 74), "camp"): return false
	if not check(inventory == s.state.extensions[Inventory.KEY], "scene return and save resume preserve supplies"): return false
	for actor in s.state.entities:
		if experience_before.has(actor.instance_id) and not check(actor.components[Session.Progression.KEY] == experience_before[actor.instance_id], "travel does not replay XP " + actor.instance_id): return false
	return true
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3: quit(2); return
	package_path = args[0]; output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var package = Package.new()
	if not check(package.load_package(package_path), "load authored package " + package.error): finish(); return
	for entry in [["win", "medicine"], ["win", "money"], ["win", "arms"], ["escape", "medicine"], ["skip", "medicine"], ["loss", "none"]]:
		route_name = "model-" + entry[0] + "-" + entry[1]; s = Session.new(); store = Save.new(output.path_join(route_name)); app = null
		if not check(s.activate(package, 0), "activate"): break
		var ok: bool = await route(entry[0], entry[1]); routes.append({"name": route_name, "success": ok, "input_kind": "production-session-commands"})
		if not ok: break
	if failed == 0 and args[2] == "ui":
		route_name = "ui-win-medicine"; root.size = Vector2i(1280, 800); app = App.instantiate(); root.add_child(app); await process_frame
		store = Save.new(output.path_join(route_name)); app.saves = store
		if check(app.open_package(package_path), "production window loads named package"):
			s = app.session; root.grab_focus(); await process_frame
			var ok: bool = await route("win", "medicine")
			routes.append({"name": route_name, "success": ok, "input_kind": "Godot Input.parse_input_event; save restore uses validated loader"})
	finish()
func finish() -> void:
	var report = {"passed": checks.size() - failed, "failed": failed, "checks": checks, "routes": routes, "saves": saves, "physical_input": false, "full_work_playthrough": false, "package_path": package_path, "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name()}
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ", true))
	print("Miaopang routes: ", routes.size(), "; checks: ", checks.size(), "; failed: ", failed)
	quit(0 if failed == 0 else 1)
