# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
const Actions = preload("res://src/native_enemy_actions.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	var variants: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for variant in variants:
		var app = App.instantiate(); root.add_child(app); await process_frame
		app.saves = Save.new(output.path_join("s"))
		if not app.open_package(variant.path): check(false, "authored package loads: " + app.session.error); _finish(); return
		await process_frame; await process_frame; await click(option(app, "继续"))
		var session = app.session; var view = app.battle_view; view.set_process(false)
		check(session.battle_open(), "actual authored battle opens " + variant.kind)
		if not session.battle_open(): _finish(); return
		var party: Array = session.state.active_party.duplicate(); var n: int = party.size()
		var battle: Dictionary = session.state.extensions[Battle.KEY]
		var enemies: Array = battle.enemies.map(func(e): return e.instance_id)
		var baseline: Dictionary = session.state.duplicate(true)
		if variant.kind == "budget":
			for i in range(n - 1): check(session.battle_command("guard"), "budget prefix command"); view.skip()
			var before: Dictionary = session.state.duplicate(true)
			check(not session.battle_command("guard") and session.state == before and "8192" in session.error, "8225 events reject complete player and enemy candidate without MP/HP/round publication")
			check(not view.playing(), "budget failure emits no committed presentation")
		elif variant.kind == "status":
			for i in range(n): check(session.battle_command("guard"), "status round command " + str(i)); view.skip()
			battle = session.state.extensions[Battle.KEY]
			check(battle.statuses.size() == 2 and battle.statuses.all(func(s): return s.remaining_rounds == 2 and s.source_id == enemies[1]), "all enemies cast with no periodic effects: last source and decremented duration survive")
			check(session.validate_saved(session.state).is_empty(), "multi-cast status state validates: " + session.validate_saved(session.state))
			record(app, variant, "status-round")
		elif variant.kind == "fault":
			for i in range(n - 1): check(session.battle_command("guard"), "apply failure prefix"); view.skip()
			battle = session.state.extensions[Battle.KEY]; battle.enemies[1].hp = 70
			for i in range(16): battle.statuses.append({"actor_id":enemies[1],"source_id":enemies[1],"status_id":"status.enemy.%02d" % i,"stacks":1,"remaining_rounds":3})
			check(session.validate_saved(session.state).is_empty(), "sixteen-status synthetic starting point remains admissible")
			var before: Dictionary = session.state.duplicate(true)
			check(not session.battle_command("guard") and session.state == before and not session.error.is_empty(), "second enemy heal then seventeenth status failure rolls back first enemy damage, all MP and player command")
			check(not view.playing(), "apply failure emits no committed animation")
			record(app, variant, "apply-failure-retained-state")
		elif variant.kind == "silence-item":
			battle.statuses.append({"actor_id":enemies[0],"source_id":enemies[0],"status_id":"status.enemy.resolve","stacks":1,"remaining_rounds":3})
			for i in range(n - 1): check(session.battle_command("guard"), "item prefix"); view.skip()
			check(session.battle_command("item", "", "", "item.enemy.tonic"), "actual player item followed by enemy command blocks"); view.skip()
			battle = session.state.extensions[Battle.KEY]
			check(battle.events[0].kind == "item_use" and battle.events.filter(func(e): return e.kind == "attack").size() == 1 and battle.events.filter(func(e): return e.kind == "cast").size() == 1, "silenced first enemy attacks, second enemy casts after player item")
			check(battle.enemies[0].mp == 30 and battle.enemies[1].mp == 26, "silence fallback does not spend first enemy MP")
			record(app, variant, "item-then-silence-fallback-and-cast")
		elif variant.kind == "retarget":
			session.entity(party[0]).hp = 1
			for i in range(n): check(session.battle_command("guard"), "retarget prefix"); view.skip()
			battle = session.state.extensions[Battle.KEY]
			var effects: Array = battle.events.filter(func(e): return e.kind == "damage")
			check(effects.size() == n * 2 - 1 and effects.filter(func(e): return e.source == enemies[1]).all(func(e): return e.target != party[0]) and battle.turn == 1, "second caster recomputes all living targets after first caster kills leader")
			check(session.validate_saved(session.state).is_empty(), "retarget save preserves action-time target sets")
			var bad: Dictionary = session.state.duplicate(true); bad.extensions[Battle.KEY].guarding = [party[0]]
			check(not session.validate_saved(bad).is_empty(), "dead earlier seat cannot retain forged guard into next round")
			record(app, variant, "retarget-after-kill")
		elif variant.kind == "selection":
			battle.enemies[0].hp = 50; session.entity(party[1]).hp = 30
			for i in range(n): check(session.battle_command("guard"), "selection prefix"); view.skip()
			battle = session.state.extensions[Battle.KEY]
			check(battle.enemies[0].hp == 68 and session.entity(party[1]).hp == 27, "self HP threshold heals self; enemy chooses lowest HP ratio rather than first party seat")
			record(app, variant, "self-and-lowest-hp")
			for i in range(n): check(session.battle_command("guard"), "selection next round"); view.skip()
			battle = session.state.extensions[Battle.KEY]
			check(battle.enemies[0].mp == 26 and battle.events.any(func(e): return e.source == enemies[0] and e.kind == "attack"), "self healed above threshold now uses physical fallback")
			record(app, variant, "above-threshold-fallback")
		elif variant.kind == "revival":
			# Controlled starting HP is synthetic; commands and subsequent saves use the actual package.
			battle.enemies[0].hp = 1
			check(session.battle_command("attack", enemies[0]), "party kills earlier enemy before its seat"); view.skip()
			for i in range(n - 1): check(session.battle_command("guard"), "revival round remainder"); view.skip()
			battle = session.state.extensions[Battle.KEY]
			check(battle.enemies[0].hp == 12 and battle.events.filter(func(e): return e.kind == "cast").size() == 1 and battle.events.filter(func(e): return e.kind == "cast")[0].source == enemies[1], "later healer revives passed enemy seat without granting another action")
			check(session.validate_saved(session.state).is_empty(), "saved revival validates from action-time HP rather than final living roster")
			record(app, variant, "revived-earlier-seat")
			# Swap policy roles in the separately compiled next-seat variant below.
		elif variant.kind == "revival-next":
			battle.enemies[1].hp = 0
			for i in range(n): check(session.battle_command("guard"), "next-seat revival command"); view.skip()
			battle = session.state.extensions[Battle.KEY]
			check(battle.enemies[1].hp == 12 and battle.events.filter(func(e): return e.kind == "cast").size() == 2, "revived upcoming seat acts once in declared order")
			check(session.validate_saved(session.state).is_empty(), "upcoming revival save validates complete phase")
			record(app, variant, "revived-upcoming-seat")
		else:
			for i in range(n):
				if view.playing(): view.skip()
				await click(option(app, "防御"))
			battle = session.state.extensions[Battle.KEY]
			check(battle.round == 2 and battle.turn == 0 and battle.events.filter(func(e): return e.kind == "cast").map(func(e): return e.source) == enemies, "normal UI guards lead to two ordered enemy casts " + str(n))
			check(party.all(func(id): return session.entity(id).hp == 117) and battle.enemies[0].mp == 27 and battle.enemies[1].mp == 26, "guard rounds odd damage upward and debits each same-definition instance independently")
			check(session.validate_saved(session.state).is_empty(), "normal multi-cast result is saveable: " + session.validate_saved(session.state))
			var committed: Dictionary = battle.duplicate(true)
			var seen: Array = []
			while view.playing():
				await RenderingServer.frame_post_draw
				var phase: Dictionary = view.presentation.current()
				if phase.event.get("kind") == "cast":
					seen.append(phase.actor_id)
					check(view.displayed_frames[phase.actor_id].resolved_action == "cast" and not view.displayed_frames[phase.actor_id].fallback, "enemy uses authored cast clip " + phase.actor_id)
					check("敌·" in view.action_caption(), "visible caption resolves authored enemy skill name")
					if phase.actor_id == enemies[1]:
						var elapsed: float = view.presentation.elapsed_us; session.set_pause(true); view._process(2.0)
						check(view.presentation.elapsed_us == elapsed, "pause freezes second enemy cast"); session.set_pause(false)
						record(app, variant, "during-second-cast")
						root.get_texture().get_image().save_png(output.path_join("enemy-cast-" + str(n) + ".png"))
				view._process((phase.duration_us - view.presentation.elapsed_us + 1) / 1000000.0)
			check(seen == enemies and session.state.extensions[Battle.KEY] == committed, "each enemy phase plays once without changing authority")
			var saved_path: String = app.saves.last_path
			check(app.saves.load_into(session, saved_path) and not view.playing() and session.state.extensions[Battle.KEY] == committed, "loading during-cast save restores committed result without replay")
			var bad: Dictionary = session.state.duplicate(true); bad.extensions[Battle.KEY].events.remove_at(bad.extensions[Battle.KEY].events.size() - 1)
			check(not session.validate_saved(bad).is_empty(), "missing final enemy effect rejected")
			bad = session.state.duplicate(true); bad.extensions[Battle.KEY].events.append(bad.extensions[Battle.KEY].events.filter(func(e): return e.kind == "cast")[1].duplicate(true))
			check(not session.validate_saved(bad).is_empty(), "duplicate enemy cast rejected")
			bad = session.state.duplicate(true); bad.extensions[Battle.KEY].events = []
			check(not session.validate_saved(bad).is_empty(), "completed command cannot erase all result evidence")
			bad = session.state.duplicate(true); bad.extensions[Battle.KEY].turn = 1
			check(not session.validate_saved(bad).is_empty(), "completed enemy round cannot skip first living party seat")
			for i in range(n): check(session.battle_command("guard"), "second round " + str(i)); view.skip()
			battle = session.state.extensions[Battle.KEY]
			check(battle.round == 3 and battle.events.filter(func(e): return e.kind == "attack").size() == 1 and battle.enemies[0].mp == 27 and battle.enemies[1].mp == 22, "even-round policy uses physical fallback without spending first enemy MP")
			record(app, variant, "interval-fallback")
			# Bounded synthetic state mutation: dry enemy MP, then real shared execution.
			battle.enemies[0].mp = 0; battle.enemies[1].mp = 0
			for i in range(n): check(session.battle_command("guard"), "no MP round " + str(i)); view.skip()
			check(session.state.extensions[Battle.KEY].events.filter(func(e): return e.kind == "attack").size() == 2, "unaffordable enemy skills fall back to two ordinary attacks")
			record(app, variant, "unaffordable-fallback")
			check(app.saves.load_into(session, saved_path), "restore actual saved cast before transaction fault")
			check(baseline.content_lock == session.state.content_lock, "same exact authored package identity retained")
		view.skip(); root.remove_child(app); app.queue_free(); await process_frame
	_finish()
func record(app, variant: Dictionary, stage: String) -> void:
	check(app.saves.save(app.session), "write immutable save " + stage + ": " + app.saves.error)
	if not app.saves.last_path.is_empty(): saves.append({"package_path": variant.path, "save_path": app.saves.last_path, "stage": stage, "kind": variant.kind})
func option(app, prefix: String) -> Button:
	for child in app.options.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false, "missing command " + prefix); return null
func click(control: Control) -> void:
	if control == null: return
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var point: Vector2 = control.get_global_rect().get_center()
	for down in [true, false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event, true)
	await process_frame; await process_frame
func _finish() -> void:
	var report: Dictionary = {"checks": checks, "failed": failed, "saves": saves, "engine_injected_input": true, "synthetic_frames": true, "synthetic_state_cases": true, "physical_input": false, "full_playthrough": false}
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t")); print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
