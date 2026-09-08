# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Equipment = preload("res://src/native_equipment.gd")
const Inventory = preload("res://src/native_inventory.gd")
const Growth = preload("res://src/native_progression.gd")
const Battle = preload("res://src/native_battle.gd")
const Statuses = preload("res://src/native_statuses.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	for variant in JSON.parse_string(FileAccess.get_file_as_string(args[0])):
		var app = App.instantiate(); root.add_child(app); await process_frame
		app.saves = Save.new(output.path_join("s"))
		if not app.open_package(variant.path): check(false, "load equipment package: " + app.session.error); _finish(); return
		await process_frame; await process_frame
		var session = app.session; var view = app.battle_view; view.set_process(false)
		var party: Array = session.state.active_party.duplicate(); var hero: String = party[0]; var friend: String = party[1]
		var catalog: Array = session.package.world.item_definitions; var wood: String = catalog[0].id; var heavy: String = catalog[1].id; var charm: String = catalog[2].id
		var originals: Array = session.package.world.actor_definitions.duplicate(true); var total: Dictionary = totals(session)
		check(Equipment.loadout(session.entity(hero))[0].item_id == wood and Inventory.count(session.state, wood) == (9 if variant.kind == "capacity" else 0), "initial weapon debits shared stock " + variant.kind)
		check(session.entity(hero).hp == 120 and Growth.stats(session.package, session.entity(hero)).attack == 32, "initial equipment applied once before starting full HP")
		record(app, variant, "initial"); var initial_save: String = app.saves.last_path
		if variant.kind.begins_with("normal"):
			await click(app.equipment_button); check(app.equipment_menu.visible and session.modal, "equipment window freezes world input")
			var frozen: Dictionary = session.snapshot(); check(not session.change_equipment(hero, "slot.weapon", heavy) and session.state == frozen, "ordinary transaction cannot bypass modal guard")
			var chooser: OptionButton = app.equipment_menu.find_child("EquipmentActor", true, false)
			check(chooser.item_count == session.state.roster.size(), "equipment menu includes active and reserve actors without three-person truncation")
			var names: Dictionary = {}
			for i in range(chooser.item_count): names[chooser.get_item_text(i)] = true
			check(names.size() == chooser.item_count, "same-name companions remain distinguishable by active or reserve position")
			await choose_slot(app, "slot.weapon", heavy)
			check(Inventory.count(session.state, wood) == 1 and Inventory.count(session.state, heavy) == 0, "menu replacement returns old item and takes new item once")
			check(session.entity(hero).hp == 10 and session.entity(hero).mp == 0, "negative equipment clamps current HP and MP")
			await choose_slot(app, "slot.weapon", wood)
			check(session.entity(hero).hp == 10 and session.entity(hero).mp == 0 and totals(session) == total, "reequipping positive stats cannot heal and conserves all possessions")
			await choose_actor(app, friend); await choose_slot(app, "slot.accessory", charm)
			check(Equipment.loadout(session.entity(friend))[0].item_id == charm and Equipment.loadout(session.entity(party[2])).is_empty(), "shared companion definition has independent equipment")
			await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("equipment-" + str(party.size()) + ".png"))
			app.equipment_menu.hide(); record(app, variant, "menu-equipped")
			var equipped: Dictionary = loadouts(session)
			check(app.saves.load_into(session, app.saves.last_path) and loadouts(session) == equipped and totals(session) == total, "loading equipment does not reapply initial inventory deduction")
			for defect in ["missing", "null", "kind", "slot", "item", "duplicate", "eligibility", "hp", "order"]:
				var bad: Dictionary = session.snapshot(); var actor: Dictionary = bad.entities.filter(func(a): return a.instance_id == hero)[0]
				match defect:
					"missing": actor.components.erase(Equipment.KEY)
					"null": actor.components[Equipment.KEY] = null
					"kind": actor.components[Equipment.KEY].kind = "content"
					"slot": actor.components[Equipment.KEY].loadout[0].slot_id = "slot.missing"
					"item": actor.components[Equipment.KEY].loadout[0].item_id = "item.missing"
					"duplicate": actor.components[Equipment.KEY].loadout.append(actor.components[Equipment.KEY].loadout[0].duplicate())
					"eligibility": actor.components[Equipment.KEY].loadout = [{"slot_id":"slot.accessory","item_id":charm}]
					"hp": actor.hp = 1000000
					"order": bad.entities.filter(func(a): return a.instance_id == friend)[0].components[Equipment.KEY].loadout = [{"slot_id":"slot.weapon","item_id":wood},{"slot_id":"slot.accessory","item_id":charm}]
				frozen = session.snapshot(); check(not session.restore(bad) and session.state == frozen, "bad equipment load preserves live state " + defect)
			for request in [[friend,"slot.weapon",heavy], [hero,"slot.head",heavy], [friend,"slot.weapon",wood], ["instance.missing","slot.weapon",wood], [hero,"slot.weapon",wood]]:
				frozen = session.snapshot(); check(not session.change_equipment(request[0],request[1],request[2]) and session.state == frozen, "invalid/no-op/equipped-last-item request is atomic " + str(request))
			check(app.saves.load_into(session, initial_save), "restore actual initial equipment save before combat")
			for gate in ["pause", "focus"]:
				if gate == "pause": session.set_pause(true)
				else: session.set_focus(false)
				frozen = session.snapshot(); check(not session.change_equipment(hero,"slot.weapon",heavy) and session.state == frozen, "equipment obeys " + gate + " gate")
				if gate == "pause": session.set_pause(false)
				else: session.set_focus(true)
		elif variant.kind == "capacity":
			var frozen: Dictionary = session.snapshot(); check(not session.change_equipment(hero,"slot.weapon") and session.state == frozen, "full returned-item stack rejects unequip without deleting gear")
			check(not session.change_equipment(hero,"slot.weapon",heavy) and session.state == frozen, "full old-item stack also rolls back taking the replacement")
			record(app, variant, "capacity-rejected")
		elif variant.kind == "dead":
			# Explicit synthetic precondition, not damage input or a full playthrough.
			session.entity(hero).hp = 0
			check(session.change_equipment(hero,"slot.weapon",heavy) and session.entity(hero).hp == 0, "changing gear on dead actor does not revive")
			record(app, variant, "dead-equipped"); check(app.saves.load_into(session, initial_save), "restore before combat after dead actor check")
		elif variant.kind == "custom-slot":
			check(session.change_equipment(friend,"slot.custom-charm",charm), "custom seventh slot uses stable identity rather than legacy array")
			record(app, variant, "custom-slot")
		await click(option(app, "继续")); check(session.battle_open(), "authored battle starts with equipment " + variant.kind)
		var frozen: Dictionary = session.snapshot(); check(not session.change_equipment(hero,"slot.weapon",heavy) and session.state == frozen and app.equipment_button.disabled, "battle locks equipment changes and preserves event history")
		if variant.kind == "escape":
			await click(option(app,"撤离")); view.skip(); check(not session.battle_open() and totals(session) == total, "escape preserves all equipped and bag items"); record(app,variant,"escaped")
		elif variant.kind == "loss":
			for actor in session.state.entities:
				if actor.instance_id in party: actor.hp = 1
			for i in range(12):
				if not session.battle_open(): break
				check(session.battle_command("guard"),"enemy phase in explicit one-HP defeat case"); view.skip()
			check(not session.battle_open() and party.all(func(id): return session.entity(id).hp == 0) and totals(session) == total,"defeat does not remove equipment or invent inventory");record(app,variant,"defeated")
		else:
			if variant.kind == "status":
				check(session.battle_command("skill",hero,"skill.fixture.equipment-buff"),"actual skill applies equipment-compatible temporary status");view.skip()
				check(Statuses.stat(session.package,session.state,session.entity(hero),"attack") == 64 and Statuses.stat(session.package,session.state,session.entity(hero),"defense") == 16,"temporary percentage consumes equipment-derived stats once")
			else: check(session.battle_command("guard"),"first equipped guard");view.skip()
			for i in range(party.size()-1): check(session.battle_command("guard"),"remaining party guards");view.skip()
			check(session.entity(hero).hp == (120 if variant.kind == "status" else 112),"enemy damage and optional periodic healing respect equipment maxima")
			record(app,variant,"battle-round")
			check(app.saves.load_into(session,app.saves.last_path),"equipment and active combat restore together: "+app.saves.error)
			for i in range(12):
				if not session.battle_open(): break
				var enemy: Dictionary = session.state.extensions[Battle.KEY].enemies.filter(func(e): return e.hp > 0)[0]
				check(session.battle_command("attack",enemy.instance_id),"equipped attack settles through common battle consumer");view.skip()
			check(not session.battle_open() and Equipment.loadout(session.entity(hero))[0].item_id == wood and totals(session) == total,"victory retains equipment and bag while ending temporary battle state")
			if Growth.used(session.package.world): check(Growth.stats(session.package,session.entity(hero)).attack == 36 and Growth.stats(session.package,session.entity(hero)).max_hp == 140,"level-up recomputes growth plus gear without rewriting bases")
			record(app,variant,"victory")
			if variant.kind.begins_with("normal"):
				await click(option(app,"继续"));check(session.battle_open(),"next authored encounter uses learned skills with gear")
				var before_mp: int = session.entity(hero).mp
				check(session.battle_command("skill","",session.package.world.skill_definitions[1].id),"learned full-party healing casts after equipment growth");view.skip()
				check(session.entity(hero).hp == 140 and session.entity(hero).mp == before_mp - 2,"healing and MP debit use equipped grown maximum");record(app,variant,"grown-healing")
		check(session.package.world.actor_definitions == originals,"all paths leave shared base definitions unchanged")
		view.skip(); root.remove_child(app);app.queue_free();await process_frame
	_finish()

func loadouts(session) -> Dictionary:
	var result: Dictionary = {}
	for actor in session.state.entities: result[actor.instance_id] = Equipment.loadout(actor).duplicate(true)
	return result
func totals(session) -> Dictionary:
	var result: Dictionary = {}
	for item in session.package.world.item_definitions: result[item.id] = Inventory.count(session.state,item.id)
	for actor in session.state.entities:
		for row in Equipment.loadout(actor): result[row.item_id] += 1
	return result
func record(app, variant: Dictionary, stage: String) -> void:
	check(app.saves.save(app.session),"save "+stage+": "+app.saves.error)
	if not app.saves.last_path.is_empty():saves.append({"package_path":variant.path,"save_path":app.saves.last_path,"stage":stage,"kind":variant.kind})
func option(app, text: String) -> Button:
	for child in app.options.get_children():
		if child is Button and text in child.text:return child
	check(false,"missing option "+text);return null
func choose_actor(app, id: String) -> void:
	var box: OptionButton = app.equipment_menu.find_child("EquipmentActor",true,false)
	for i in range(box.item_count):
		if box.get_item_metadata(i) == id: box.select(i);box.item_selected.emit(i);await process_frame;return
	check(false,"missing equipment actor "+id)
func choose_slot(app, slot_id: String, item_id: String) -> void:
	for line in app.equipment_menu.body.get_children():
		if not line is HBoxContainer:continue
		for child in line.get_children():
			if child is OptionButton and child.get_meta("slot_id","") == slot_id:
				for i in range(child.item_count):
					if child.get_item_metadata(i) == item_id:
						child.select(i);child.item_selected.emit(i)
						var button: Button = line.get_children().filter(func(c):return c is Button and not c is OptionButton)[0]
						check(not button.disabled,"equipment choice enables apply "+item_id);await click(button);return
	check(false,"missing available equipment "+item_id)
func click(control: Control) -> void:
	if control == null:return
	var parent = control.get_parent()
	while parent != null and not parent is ScrollContainer:parent=parent.get_parent()
	if parent is ScrollContainer:parent.ensure_control_visible(control)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var point: Vector2 = control.get_global_rect().get_center()
	var target: Viewport = control.get_viewport()
	if target is Window and target != root and target.is_embedded():
		point += Vector2(target.position); target = root
	var motion = InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; target.push_input(motion, true)
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;target.push_input(event,true)
	await process_frame;await process_frame
func _finish() -> void:
	var report={"checks":checks,"failed":failed,"saves":saves,"engine_injected_input":true,"synthetic_state_cases":true,"physical_input":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if failed==0 else 1)
