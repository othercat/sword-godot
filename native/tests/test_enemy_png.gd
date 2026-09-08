# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Battle = preload("res://src/native_battle.gd")
const Save = preload("res://src/native_save.gd")
var checks: Array = []
var failed: int = 0
var output: String
var seen: Dictionary = {}
var saves: Array = []
var death_art_fallback_verified: bool = false
func check(ok: bool, message: String) -> void:
	checks.append({"name": message, "passed": ok})
	if not ok: failed += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280, 800)
	var app = App.instantiate(); root.add_child(app); await process_frame
	app.saves = Save.new(output.path_join("saves"))
	if not app.open_package(args[0]): check(false, app.session.error); _finish(); return
	app.set_physics_process(false); app.battle_view.set_process(false)
	await process_frame; await click(option(app, "继续"))
	var session = app.session; var view = app.battle_view
	var battle: Dictionary = session.state.extensions[Battle.KEY]
	var ids: Array = battle.enemies.map(func(e): return e.instance_id)
	check(ids.size() == 9 and view.page_count() == 2, "nine authored enemy instances span two pages")
	var definition: Dictionary = session.package.index.actor_definitions[battle.enemies[0].definition_id]
	var sprite: Dictionary = session.package.index.battle_sprite_sets[definition.battle_sprite_set]
	check(sprite.clips.size() == 2 and sprite.clips[0].frames.size() == 2 and sprite.clips[1].frames.size() == 1, "actual imported group retains idle and attack without fabricated dead frames")
	await RenderingServer.frame_post_draw
	var first: Dictionary = view.displayed_frames[ids[0]]
	check(first.action == "idle" and first.resolved_action == "idle" and not first.fallback, "real enemy idle is resolved explicitly")
	check(session.package.textures[first.asset_id].get_image().detect_alpha() != Image.ALPHA_NONE, "original enemy PNG transparency reaches GPU texture")
	view._process(.2); await RenderingServer.frame_post_draw
	check(view.displayed_frames[ids[0]].frame_id != first.frame_id, "second original idle frame follows authored duration")
	root.get_texture().get_image().save_png(output.path_join("enemy-page-one.png"))
	await click(app.target_pages.get_child(2)); await RenderingServer.frame_post_draw
	check(view.enemy_page == 1 and view.displayed_frames.has(ids[8]), "page two renders the ninth real enemy")
	await click(option(app, "攻击 9")); await drain(app)
	check(battle.enemies[8].hp == 36, "retained before-command snapshot is not mutated")
	battle = session.state.extensions[Battle.KEY]
	check(battle.enemies[8].hp == 18 and battle.enemies.slice(0, 8).all(func(e): return e.hp == 36), "page-two input damages only instance nine")
	await click(app.target_pages.get_child(0));
	await click(option(app, "攻击 8")); await drain(app)
	await click(option(app, "攻击 8")); await drain(app)
	battle = session.state.extensions[Battle.KEY]
	check(battle.enemies[7].hp == 0 and option(app, "攻击 8").disabled, "dead instance eight keeps its ordinal and is disabled for attacks")
	var before: Dictionary = session.state.duplicate(true)
	check(not session.battle_command("attack", ids[7]) and session.state == before, "dead target command is rejected without changing state")
	await RenderingServer.frame_post_draw
	var dead: Dictionary = view.displayed_frames[ids[7]]
	death_art_fallback_verified = dead.action == "dead" and dead.resolved_action == "idle" and dead.fallback
	check(death_art_fallback_verified, "missing death art is reported as explicit idle fallback, not a played dead clip")
	root.get_texture().get_image().save_png(output.path_join("enemy-dead-fallback.png"))
	await click(option(app, "防御")); await drain(app)
	battle = session.state.extensions[Battle.KEY]
	check(battle.round == 2 and seen.has(ids[8] + "/attack") and not seen.has(ids[7] + "/attack"), "counterattacks cross to page two and skip the dead enemy")
	check(view.enemy_page == 1 and not option(app, "攻击 9").disabled, "command page follows completed ninth-enemy playback")
	await click(app.save_button)
	check(not app.saves.last_path.is_empty(), "real battle state with imported enemy art saves")
	if not app.saves.last_path.is_empty():
		saves.append({"package_path": args[0], "save_path": app.saves.last_path, "party": 4})
		var saved: Dictionary = battle.duplicate(true)
		check(app.saves.load_into(session, app.saves.last_path), "saved encounter loads through actual save adapter")
		check(view.enemy_page == 0 and session.state.extensions[Battle.KEY] == saved, "load clears display page while preserving all nine identities, death and target-nine HP")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("enemy-restored.png"))
	root.remove_child(app); app.queue_free(); await process_frame; _finish()
func drain(app) -> void:
	var view = app.battle_view; var count: int = 0
	while view.playing() and count < 100:
		var phase: Dictionary = view.presentation.current()
		view.queue_redraw(); await RenderingServer.frame_post_draw
		if phase.actor_id.begins_with("enemy.") and not phase.action.is_empty():
			var frame: Dictionary = view.displayed_frames[phase.actor_id]
			seen[phase.actor_id + "/" + phase.action] = frame
			var row: Dictionary = view.presentation.actors[phase.actor_id]
			var definition: Dictionary = app.session.package.index.actor_definitions[row.definition_id]
			var sprite: Dictionary = app.session.package.index.battle_sprite_sets[definition.battle_sprite_set]
			var expected: Dictionary = sprite.clips[1] if phase.action == "attack" else sprite.clips[0]
			check(frame.resolved_action == expected.action and frame.asset_id == expected.frames[0].asset_id, "actual image binding for enemy " + phase.action)
			if phase.action == "attack": root.get_texture().get_image().save_png(output.path_join("enemy-counterattack.png"))
		view._process((float(phase.duration_us) - view.presentation.elapsed_us) / 1000000.0 + .0001)
		await process_frame; count += 1
	check(not view.playing(), "committed presentation finishes within its declared phases")
func option(app, prefix: String) -> Button:
	for child in app.options.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false, "missing button " + prefix); return null
func click(control: Control) -> void:
	if control == null: return
	await process_frame
	var point = control.get_global_rect().get_center()
	for down in [true, false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event, true)
	await process_frame; await process_frame
func _finish() -> void:
	var report = {"checks": checks, "failed": failed, "saves": saves, "real_source_png": true, "synthetic_encounter": true,
		"death_art_fallback_verified": death_art_fallback_verified, "formal_death_art": false, "physical_input": false, "full_playthrough": false}
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t")); print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
