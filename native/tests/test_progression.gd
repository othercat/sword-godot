# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
const Growth = preload("res://src/native_progression.gd")
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
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	for variant in JSON.parse_string(FileAccess.get_file_as_string(args[0])):
		var app = App.instantiate(); root.add_child(app); await process_frame
		app.saves = Save.new(output.path_join("s"))
		if not app.open_package(variant.path): check(false, "package loads: " + app.session.error); _finish(); return
		await process_frame; await process_frame
		var session = app.session; var view = app.battle_view; view.set_process(false)
		var party: Array = session.state.active_party.duplicate(); var n: int = party.size(); var hero = session.entity(party[0])
		var definition: Dictionary = session.package.index.actor_definitions[hero.definition_id]
		if variant.kind == "initial":
			check(hero.components[Growth.KEY].level == 3 and hero.hp == Growth.stats(session.package, hero).max_hp, "initial XP starts at derived level with full effective HP")
		check(party.all(func(id): return session.entity(id).components.has(Growth.KEY)), "all actual world instances have separate growth " + variant.kind)
		await click(option(app, "继续")); check(session.battle_open(), "authored battle opens " + variant.kind)
		hero = session.entity(party[0]) # Commands publish a new candidate, never retain an old actor reference.
		var b: Dictionary = session.state.extensions[Battle.KEY]; var enemy_ids: Array = b.enemies.map(func(e): return e.instance_id)
		var skills: Array = session.package.world.skill_definitions.map(func(s): return s.id)
		check(Growth.validate_state(session.package, session.state).is_empty(), "initial pending matches battle executor")
		if variant.kind.begins_with("normal"):
			var original_component = session.package.world.extensions[Growth.KEY]
			for malformed in [null, [], "invalid"]:
				session.package.world.extensions[Growth.KEY] = malformed
				check(not Growth.validate_content(session.package).is_empty(), "nonobject growth returns diagnostic without type fault")
			session.package.world.extensions[Growth.KEY] = original_component
			check(Growth.skill_ids(session.package, hero).is_empty(), "level-one actor has not learned authored skills")
			await click(option(app, "防御")); view.skip()
			var bad: Dictionary = session.state.duplicate(true)
			bad.extensions[Growth.KEY].pending.defeats.append({"enemy_id": enemy_ids[0], "source_id": party[0], "living": [], "step": 1})
			check(not session.validate_saved(bad).is_empty(), "guard with full-health enemy cannot forge current-step defeat")
			# The next actual player seat attacks, then its successor ends the encounter.
			await click(option(app, "攻击")); view.skip()
			check(session.state.extensions[Growth.KEY].pending.defeats.size() == 1 and session.state.extensions[Growth.KEY].credits.is_empty(), "first death records eligibility without awarding early")
			record(app, variant, "first-defeat")
			var first_save: String = app.saves.last_path
			check(app.saves.load_into(session, first_save), "load pending first defeat: " + app.saves.error)
			check(session.state.extensions[Growth.KEY].credits.is_empty(), "loading pending defeat does not award XP")
		elif variant.kind.begins_with("party-"):
			hero.hp = 50; hero.mp = 3; session.entity(party[1]).hp = 0
		elif variant.kind == "loss":
			for id in party: session.entity(id).hp = 0
			hero.hp = 1
			check(session.battle_command("guard"), "real enemy phase defeats sole living actor"); view.skip()
		elif variant.kind == "escape":
			await click(option(app, "撤离")); view.skip()
		elif variant.kind == "revival":
			check(session.battle_command("attack", enemy_ids[0]), "first actual enemy defeat before revival"); view.skip()
			for i in range(n - 1): check(session.battle_command("guard"), "enemy healer round"); view.skip()
			check(session.state.extensions[Battle.KEY].enemies[0].hp > 0, "later enemy skill revives earlier defeated instance")
			record(app, variant, "revived-enemy")
			check(session.battle_command("attack", enemy_ids[0]), "same enemy defeated second time"); view.skip()
			check(session.state.extensions[Growth.KEY].pending.defeats.size() == 1, "revival cannot farm a second reward")
		elif variant.kind == "periodic":
			var poison: String = session.package.world.status_definitions[0].id
			b.statuses.append({"actor_id": enemy_ids[0], "source_id": party[0], "status_id": poison, "stacks": 1, "remaining_rounds": 1})
			for i in range(n): check(session.battle_command("guard"), "periodic round"); view.skip()
			check(session.state.extensions[Growth.KEY].pending.defeats.size() == 1 and session.state.extensions[Growth.KEY].pending.defeats[0].source_id == party[0], "periodic damage credits original status source")
			record(app, variant, "periodic-defeat")
		elif variant.kind == "same-definition":
			check(b.enemies[0].hp == definition.max_hp and hero.hp > definition.max_hp, "same-definition transient enemy keeps base stats while world actor grows")
		if variant.kind == "fault":
			check(session.battle_command("attack", enemy_ids[0]), "failure prefix kill"); view.skip()
			var before: Dictionary = session.state.duplicate(true)
			var callback: String = session.current_node().on_win; var original = session.package.index.nodes[callback]
			session.package.index.nodes.erase(callback)
			check(not session.battle_command("attack", enemy_ids[1]) and session.state == before, "missing victory callback rolls back HP MP XP learned credit pending and execution")
			check(not view.playing(), "rejected reward transaction emits no presentation")
			session.package.index.nodes[callback] = original
		if variant.kind not in ["loss", "escape"]:
			var attempts: int = 0
			while session.battle_open() and attempts < 100:
				var living: Array = session.state.extensions[Battle.KEY].enemies.filter(func(e): return e.hp > 0)
				check(session.battle_command("attack", living[0].instance_id), "battle command reaches victory " + variant.kind)
				view.skip(); attempts += 1
			check(not session.battle_open(), "battle victory callback completes " + variant.kind)
		var ledger: Dictionary = session.state.extensions[Growth.KEY]
		if ledger.credits.size() != 1: check(false, "one reward execution " + variant.kind); _finish(); return
		var credit: Dictionary = ledger.credits[0]; hero = session.entity(party[0])
		check(ledger.pending == null and session.validate_saved(session.state).is_empty(), "settled ledger validates " + variant.kind + ": " + session.validate_saved(session.state))
		if variant.kind in ["loss", "escape"]:
			check(credit.outcome == variant.kind and credit.awards.all(func(a): return a.amount == 0), "nonwin records zero awards " + variant.kind)
		elif variant.kind == "cap": check(hero.components[Growth.KEY].experience == Growth.MAX_EXPERIENCE and credit.awards[0].amount == 1, "experience saturation preserves exact actual award")
		elif variant.kind == "initial" or variant.kind == "same-definition": check(hero.components[Growth.KEY].experience == 160, "initial experience plus actual rewards")
		else:
			check(hero.components[Growth.KEY].experience == 80 and hero.components[Growth.KEY].level == 3, "two cumulative thresholds crossed in one settlement " + variant.kind)
			check(hero.components[Growth.KEY].learned_skills == skills.slice(0, 2), "all crossed-level skills learned once in declared order")
			check(credit.defeats.size() == 2 and credit.awards[0].amount == 80, "exact two enemy rewards, no duplicates")
		if variant.kind.begins_with("party-"):
			var dead = session.entity(party[1]); var policy: String = variant.kind.trim_prefix("party-")
			check(dead.hp == 0 and dead.components[Growth.KEY].experience == 8 and dead.components[Growth.KEY].level == 3, "dead-at-defeat earns floor10percent with party eligibility and never revives")
			check(hero.hp == (70 if policy == "keep_deficit" else (120 if policy == "full_living" else 50)), "selected level-up HP policy " + policy)
			check(hero.mp == (18 if policy == "keep_deficit" else (35 if policy == "full_living" else 3)), "selected level-up MP policy " + policy)
		record(app, variant, "settled")
		var saved: String = app.saves.last_path; var frozen = ledger.duplicate(true)
		check(app.saves.load_into(session, saved) and session.state.extensions[Growth.KEY] == frozen, "loading settlement cannot repeat or erase awards")
		for defect in ["xp", "credit", "node", "activation", "learned", "ledger"]:
			var bad: Dictionary = session.state.duplicate(true)
			match defect:
				"xp": bad.entities[0].components[Growth.KEY].experience -= 1 if bad.entities[0].components[Growth.KEY].experience > 0 else -1
				"credit": bad.extensions[Growth.KEY].credits.append(credit.duplicate(true))
				"node": bad.extensions[Growth.KEY].credits[0].node_id = session.package.world.entry_node
				"activation": bad.extensions[Growth.KEY].credits[0].activation = "activation.other"
				"learned": bad.entities[0].components[Growth.KEY].learned_skills.append("skill.missing")
				"ledger": bad.extensions.erase(Growth.KEY)
			check(not session.validate_saved(bad).is_empty(), "forged saved growth rejected " + defect)
		if variant.kind.begins_with("normal"):
			check(app.find_child("GrowthRewardSummary", true, false) != null, "player sees last reward summary")
			await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("growth-" + str(n) + ".png"))
			await click(option(app, "继续")); check(session.battle_open(), "authored continue enters next battle execution")
			check(session.state.extensions[Growth.KEY].pending.execution_id != credit.execution_id, "repeat encounter uses a fresh execution identity")
			await click(option(app, "技能"))
			check(app.options.get_children().any(func(c): return c is Button and "穿林击" in c.text), "learned skill appears in actual command menu")
			# Select learned skill in UI; all-enemy cast needs no target cursor.
			await click(option(app, "新学·穿林击")); await click(option(app, "施放于全部")); view.skip()
			check(session.state.extensions[Battle.KEY].events[0].kind == "cast" and session.entity(party[0]).mp == 33, "newly learned skill casts next battle and spends current MP")
			record(app, variant, "learned-skill-next-battle")
			check(session.state.extensions[Growth.KEY].credits.size() == 1, "next incomplete battle cannot replay prior rewards")
			session.entity(party[0]).hp -= 1
			await click(option(app, "技能")); await click(option(app, "新学·回春")); await click(option(app, "施放于全部")); view.skip()
			check(session.entity(party[0]).hp == 120 and session.entity(party[1]).hp == 140, "learned healing restores effective maxima beyond original definition")
			record(app, variant, "healed-at-grown-maxima")
		view.skip(); root.remove_child(app); app.queue_free(); await process_frame
	_finish()
func record(app, variant: Dictionary, stage: String) -> void:
	check(app.saves.save(app.session), "save " + stage + ": " + app.saves.error)
	if not app.saves.last_path.is_empty(): saves.append({"package_path":variant.path,"save_path":app.saves.last_path,"stage":stage,"kind":variant.kind})
func option(app, text: String) -> Button:
	for child in app.options.get_children():
		if child is Button and text in child.text: return child
	check(false, "missing UI option " + text); return null
func click(control: Control) -> void:
	if control == null: return
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var point: Vector2 = control.get_global_rect().get_center()
	for down in [true, false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event, true)
	await process_frame; await process_frame
func _finish() -> void:
	var report = {"checks":checks,"failed":failed,"saves":saves,"engine_injected_input":true,"synthetic_state_cases":true,"physical_input":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if failed == 0 else 1)
