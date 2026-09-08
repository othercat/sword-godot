# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
const Statuses = preload("res://src/native_statuses.gd")
const Inventory = preload("res://src/native_inventory.gd")
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
	if args.size() != 4: quit(2); return
	output = args[3]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280,800)
	for package_path in args.slice(0,3):
		var app = App.instantiate(); root.add_child(app); await process_frame; app.saves = Save.new(output.path_join("saves"))
		if not app.open_package(package_path): check(false,"status owner package loads: " + app.session.error); _finish(); return
		await process_frame; await process_frame; await click(option(app,"继续"))
		var session = app.session; var party: Array = session.state.active_party.duplicate(); var size: int = party.size()
		var specs: Array = session.package.world.status_definitions; var poison: String = specs[0].id; var regen: String = specs[1].id
		var sleep: String = specs[2].id; var silence: String = specs[3].id; var shield: String = specs[5].id; var persistent: String = specs[6].id
		var enemy_ids: Array = session.state.extensions[Battle.KEY].enemies.map(func(e): return e.instance_id)
		check(session.battle_open() and specs.size() == 8 and session.package.world.skill_definitions.size() == 9, "author-created status scenario enters battle " + str(size))
		var opening: Dictionary = session.state.duplicate(true)
		await skill(app,"侵蚀术"); await skill(app,"侵蚀术"); await item(app,"调息散"); await finish_round(app,1)
		var battle: Dictionary = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 61 and battle.enemies.all(func(e): return e.hp == 170), "round-end stacked damage and healing settle once " + str(size))
		check(enemy_ids.all(func(id): return status(session,id,poison).stacks == 2 and status(session,id,poison).remaining_rounds == 2), "stack refresh and lifetime follow actor IDs")
		check(party.all(func(id): return status(session,id,regen).remaining_rounds == 1), "all-party regeneration includes every configured member")
		var after_tick: String = await save(app,package_path,size,"after-tick")
		var tick_state: Dictionary = session.state.duplicate(true)
		var corrupt: Dictionary = tick_state.duplicate(true); var events: Array = corrupt.extensions[Battle.KEY].events
		for i in range(events.size()):
			if events[i].kind == "status_damage":
				events.insert(i+1,events[i].duplicate(true)); corrupt.extensions[Battle.KEY].enemies[0].hp -= 10; break
		check(not session.validate_saved(corrupt).is_empty(), "duplicate periodic damage plus forged HP is rejected")
		await skill(app,"侵蚀术"); await skill(app,"休眠术",2)
		var before: Dictionary = session.state.duplicate(true)
		check(not session.battle_command("guard") and session.state == before and has_option(app.options,"跳过行动") and not has_option(app.options,"物品"), "restricted actor exposes wait and rejects other commands without spending a turn")
		await click(option(app,"跳过行动")); await finish_round(app,2)
		battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 52 and battle.enemies.all(func(e): return e.hp == 155) and status(session,party[2],sleep).remaining_rounds == 1, "three-stack damage, healing expiry and restricted turn survive round end")
		check(Statuses.rows(session.state,party[0]).is_empty(), "two-round healing expires after its final tick")
		await save(app,package_path,size,"after-control")
		await skill(app,"静心术",1); before = session.state.duplicate(true)
		check(option(app,"技能").disabled and not option(app,"物品").disabled, "silence disables skills while keeping items usable")
		check(not session.battle_command("skill","",session.package.world.skill_definitions[0].id) and session.state == before, "execution rechecks silence without spending MP")
		await item(app,"清心符",1)
		check(status(session,party[1],silence).is_empty() and not option(app,"跳过行动").disabled, "shared item effects clear silence before the next restricted actor")
		await click(option(app,"跳过行动")); await finish_round(app,3)
		battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 37 and battle.enemies.all(func(e): return e.hp == 140) and status(session,party[2],sleep).is_empty(), "control expiry restores later actions without duplicate actor turns")
		await save(app,package_path,size,"after-clear")
		await item(app,"调息散"); await item(app,"护势符"); await finish_round(app,4)
		battle = session.state.extensions[Battle.KEY]
		check(session.entity(party[0]).hp == 40 and battle.enemies.all(func(e): return e.hp == 125), "defense modification precedes three minimum-damage hits and regeneration")
		check(enemy_ids.all(func(id): return status(session,id,poison).is_empty()) and status(session,party[0],shield).remaining_rounds == 2, "poison ticks before expiry while the new defense status persists")
		var expiry_path: String = await save(app,package_path,size,"after-expiry")
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("battle-%d.png" % size))
		check(not app.battle_view._status_regions.is_empty(), "battle HP panels expose status text and hover regions")
		for _turn in range(8):
			if not session.battle_open(): break
			await skill(app,"群攻术")
		check(not session.battle_open() and session.state.committed_effect_ids.size() == 1, "normal skill inputs win and commit the battle once " + str(size))
		var won: String = await save(app,package_path,size,"after-win")
		check(app.saves.load_into(session,won) and not session.state.extensions.has(Battle.KEY), "victory save retains no transient battle statuses")
		check(app.saves.load_into(session,after_tick) and session.state.extensions[Battle.KEY] == tick_state.extensions[Battle.KEY], "load restores exact tick results, status sources and remaining rounds")
		await skill(app,"重燃毒",0); await finish_round(app,2)
		check(session.entity(party[0]).hp == 32 and status(session,party[0],persistent).remaining_rounds == 2, "persistent damage is separate from defense and healing")
		await skill(app,"覆盖术"); await finish_round(app,3)
		check(session.entity(party[0]).hp == 0 and session.state.extensions[Battle.KEY].turn == 1 and status(session,party[0],persistent).remaining_rounds == 1, "natural periodic death keeps the explicitly persistent status and advances to a living actor")
		await save(app,package_path,size,"after-death")
		await skill(app,"复苏术",0)
		check(session.entity(party[0]).hp == 20 and status(session,party[0],persistent).remaining_rounds == 1 and status(session,party[0],regen).remaining_rounds == 2, "revive then heal then status-add preserves the retained poison")
		var revived: String = await save(app,package_path,size,"after-revive")
		var saved_battle: Dictionary = session.state.extensions[Battle.KEY].duplicate(true)
		check(app.saves.load_into(session,revived) and session.state.extensions[Battle.KEY] == saved_battle, "revival load does not tick, heal or consume MP a second time")
		before = session.state.duplicate(true); app.battle_view._process(1.0/60); app.battle_view._process(1.0/100)
		check(session.state == before, "60/100 display updates cannot advance status duration or authority")
		if size != 4:
			check(not app.saves.load_into(session,saves[0].save_path) and session.state == before, "status save from another party/content identity is rejected atomically")
		# The following probes explicitly mutate only synthetic in-memory test candidates.
		probes(app,opening)
		check(app.saves.load_into(session,expiry_path), "normal saved state remains loadable after synthetic probes")
		root.remove_child(app); app.queue_free(); await process_frame
	_finish()

func probes(app, opening: Dictionary) -> void:
	var session = app.session; var package = session.package; var party: Array = opening.active_party
	var definitions: Array = package.world.status_definitions; var skills: Array = package.world.skill_definitions
	var marker: String = definitions[7].id; var source: String = party[0]
	session.state = opening.duplicate(true)
	check(session.battle_command("skill","",skills[6].id) and session.battle_command("skill","",skills[7].id), "synthetic command probe: replace lowers two stacks to one")
	var before: Dictionary = session.state.duplicate(true); var bad: Dictionary = before.duplicate(true)
	for row in bad.extensions[Battle.KEY].statuses: row.stacks = 3
	for event in bad.extensions[Battle.KEY].events:
		if event.kind == "status_add": event.amount = 3
	check(not session.validate_saved(bad).is_empty(), "forged replace amount and matching current stacks are rejected together")
	check(before.extensions[Battle.KEY].statuses.all(func(r): return r.status_id == marker and r.stacks == 1), "replace result records every enemy instance")
	session.state = opening.duplicate(true)
	check(session.battle_command("skill",party[1],skills[1].id), "synthetic command probe: apply attack modifier")
	var enemy: String = session.state.extensions[Battle.KEY].enemies[0].instance_id
	check(session.battle_command("attack",enemy) and session.state.extensions[Battle.KEY].enemies[0].hp == 142, "ordinary attack uses the modified stat before defense")
	session.state = opening.duplicate(true)
	check(session.battle_command("item","","",package.world.item_definitions[3].id), "synthetic command probe: enemies receive sleep")
	for _i in range(party.size()-1): check(session.battle_command("guard"), "synthetic guarded party action")
	var battle: Dictionary = session.state.extensions[Battle.KEY]
	check(session.entity(source).hp == 70 and battle.events.filter(func(e): return e.kind == "status_skip").size() == 3, "all three sleeping enemies skip without attacking")
	session.state = opening.duplicate(true); battle = session.state.extensions[Battle.KEY]
	var target: Dictionary = battle.enemies[0]
	Statuses.add(package,session.state,session.entity(source),target,{"status_id":definitions[2].id,"stacks":1})
	Statuses.add(package,session.state,session.entity(source),target,{"status_id":definitions[5].id,"stacks":1})
	check(session.battle_command("skill","",skills[4].id) and session.state.extensions[Battle.KEY].enemies[0].hp == 152, "skill damage uses modified defense but not ordinary attack bonus")
	check(status(session,enemy,definitions[2].id).is_empty() and not status(session,enemy,definitions[5].id).is_empty(), "positive damage wakes sleep and preserves the independent shield")
	session.state = opening.duplicate(true)
	check(session.battle_command("skill",source,skills[2].id) and session.validate_saved(session.state).is_empty(), "self-applied silence remains a legal post-cast save")
	session.state = opening.duplicate(true); session.entity(source).hp = 60
	var tick_spec: Dictionary = package.index.status_definitions[marker]
	var old_ticks: Array = tick_spec.round_end_effects.duplicate(true)
	tick_spec.remove_on_damage = true; tick_spec.round_end_effects = [{"op":"damage","power":2},{"op":"heal","power":3}]
	Statuses.add(package,session.state,session.entity(source),session.entity(source),{"status_id":marker,"stacks":1})
	for row in session.state.extensions[Battle.KEY].enemies:
		Statuses.add(package,session.state,session.entity(source),row,{"status_id":definitions[2].id,"stacks":1})
	for _i in range(party.size()): check(session.battle_command("guard"), "synthetic periodic self-clear round")
	check(session.entity(source).hp == 58 and status(session,source,marker).is_empty(), "periodic damage clears its own status before the later healing component")
	bad = session.state.duplicate(true); bad.entities[0].hp += 3
	bad.extensions[Battle.KEY].events.append({"kind":"status_heal","source":source,"target":source,"amount":3,"status_id":marker,"tick_index":1})
	check(not session.validate_saved(bad).is_empty(), "forged later tick after self-clear is rejected with otherwise bounded HP")
	tick_spec.remove_on_damage = false; tick_spec.round_end_effects = old_ticks
	# Capacity failure happens after MP/item debit and an earlier healing effect on the private candidate.
	session.state = opening.duplicate(true); session.entity(source).hp = 69
	var original_defs: Array = definitions.duplicate(true); var original_index: Dictionary = package.index.status_definitions.duplicate(true)
	for i in range(16):
		var spec: Dictionary = definitions[7].duplicate(true); spec.id = "status.capacity.%02d" % i
		definitions.append(spec); package.index.status_definitions[spec.id] = spec
		Statuses.add(package,session.state,session.entity(source),session.entity(source),{"status_id":spec.id,"stacks":1})
	var original_effects: Array = skills[1].effects.duplicate(true)
	skills[1].effects = [{"op":"heal","power":1},{"op":"status_add","status_id":original_defs[4].id,"stacks":1}]
	before = session.state.duplicate(true)
	check(not session.battle_command("skill",source,skills[1].id) and session.state == before, "17th status rolls back preceding heal, MP debit, results and turn")
	var use: Dictionary = package.world.item_definitions[5].battle_use; var item_effects: Array = use.effects.duplicate(true)
	use.effects = skills[1].effects.duplicate(true)
	check(not session.battle_command("item",source,"",package.world.item_definitions[5].id) and session.state == before, "17th item-applied status rolls back healing and inventory debit together")
	use.effects = item_effects; skills[1].effects = original_effects
	package.world.status_definitions = original_defs; package.index.status_definitions = original_index
	# Failure in the authored victory callback must also discard death-triggered status removals.
	session.state = opening.duplicate(true); battle = session.state.extensions[Battle.KEY]
	for row in battle.enemies:
		row.hp = 1; Statuses.add(package,session.state,session.entity(source),row,{"status_id":original_defs[0].id,"stacks":1})
	var node: Dictionary = package.index.nodes[battle.node_id]; var win: String = node.on_win; node.on_win = "node.missing"
	before = session.state.duplicate(true)
	check(not session.battle_command("skill","",skills[4].id) and session.state == before, "failed victory callback restores status rows, enemy HP, MP and the whole battle candidate")
	node.on_win = win

func status(session, actor_id: String, id: String) -> Dictionary: return Statuses.find(session.state,actor_id,id)
func finish_round(app, expected: int) -> void:
	for _i in range(app.session.state.active_party.size()):
		if not app.session.battle_open() or app.session.state.extensions[Battle.KEY].round != expected: return
		await click(option(app,"跳过行动" if has_option(app.options,"跳过行动") else "防御"))
	check(app.session.state.extensions[Battle.KEY].round != expected,"UI finishes expected round")
func skill(app, name: String, target: int = -1) -> void: await use(app,false,name,target)
func item(app, name: String, target: int = -1) -> void: await use(app,true,name,target)
func use(app, is_item: bool, name: String, target: int) -> void:
	var before: int = app.session.state.extensions[Battle.KEY].step
	await click(option(app,"物品" if is_item else "技能"))
	for _page in range(4):
		if has_option(app.options,name + " ·"): break
		await click(find_button(app.target_pages,"下一组"))
	await click(option(app,name + " ·"))
	await click(option(app,str(target+1) + " ·" if target >= 0 else ("用于全部" if is_item else "施放于全部")))
	check(not app.session.battle_open() or app.session.state.extensions[Battle.KEY].step == before+1,"UI commits one action: " + name + " / " + app.session.error)
func save(app, package_path: String, size: int, stage: String) -> String:
	await click(app.save_button); var path: String = app.saves.last_path
	check(not path.is_empty() and app.session.validate_saved(app.session.state).is_empty(),"actual status save written: " + stage)
	saves.append({"party":size,"stage":stage,"package_path":package_path,"save_path":path}); return path
func has_option(parent, prefix: String) -> bool:
	return parent.get_children().any(func(c): return c is Button and c.text.begins_with(prefix))
func find_button(parent, prefix: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false,"missing option " + prefix); return null
func option(app, prefix: String) -> Button: return find_button(app.options,prefix)
func click(control: Control) -> void:
	if control == null: return
	await process_frame # A direct load rebuilds containers before their next layout frame.
	check(not control.disabled,"UI option enabled: " + control.text)
	var point = control.get_global_rect().get_center()
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event,true)
	await process_frame; await process_frame
func _finish() -> void:
	var report = {"checks":checks,"failed":failed,"saves":saves,"physical_input":false,"engine_injected_input":true,"synthetic_in_memory_probes":true,"real_assets":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")); print(JSON.stringify(report)); quit(0 if failed==0 else 1)
