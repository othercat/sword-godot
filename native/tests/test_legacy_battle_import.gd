# SPDX-License-Identifier: MIT
extends SceneTree
## Actual legacy records, explicit Native combat adaptation, existing practice story/art.
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
const PixelArtChecks = preload("res://tests/pixel_battle_art_checks.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
var package_path: String
var art_spec: Dictionary = {}
var art_frames_seen: Array = []
var pixel_spec: Dictionary = {}
var pixel_report: Dictionary = {}
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() not in [2,3,4]: quit(2); return
	if args.size() >= 3: art_spec = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	package_path = args[0]; output = args[1]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280,800)
	if args.size() == 4:
		var parsed_pixel: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[3]))
		var valid_pixel: bool = parsed_pixel is Dictionary and parsed_pixel.get("actors") is Array and parsed_pixel.actors.size() == 5
		check(valid_pixel,"explicit pixel mode requires five actor recipes")
		if not valid_pixel: finish(); return
		pixel_spec = parsed_pixel
	var app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
	app.saves = Save.new(output.path_join("saves"))
	check(app.open_package(package_path),"real author import package loads")
	if app.session.package == null: finish(); return
	app.session.set_focus(true,app.session._last_usec); await settle()
	await click(option(app,"继续")); await click(option(app,"五人")); await click(option(app,"继续"))
	var s = app.session; var view = app.battle_view
	check(s.battle_open() and s.state.active_party.size() == 5,"existing five-person story enters imported Native draft")
	if not s.battle_open(): finish(); return
	var battle: Dictionary = s.state.extensions[Battle.KEY]
	var execution_id: String = battle.execution_id
	var receipt: Dictionary = s.package.world.extensions["pal.studio.legacy_battle_imports"][battle.encounter_id]
	check(receipt.mode == "native-adaptation-draft" and not receipt.runtime_observed,"package retains explicit legacy evidence boundary")
	check(battle.enemies.size() == 2 and battle.enemies[0].instance_id != battle.enemies[1].instance_id,"source repeated object has two independent battle identities")
	var ids: Array = battle.enemies.map(func(e): return e.instance_id)
	check(battle.enemies.all(func(e): return e.hp == 28 and e.mp == 0),"authored initial HP and MP loaded")
	check(battle.enemies.all(func(e): return s.package.index.actor_definitions[e.definition_id].combat == {"attack":60,"defense":0}),"explicit Native attributes used instead of unsigned legacy values")
	if art_spec.is_empty():
		check(battle.enemies.all(func(e): return not s.package.index.actor_definitions[e.definition_id].has("battle_sprite_set")),"unimported ABC art remains unassigned")
	else:
		await check_art(app,battle)
	check(receipt.members[0].attack_signed_view == -1 and receipt.members[0].enemy_words[21] == 65535,"raw source words preserved separately from gameplay")
	var initial: String = save(app,"initial")
	if not pixel_spec.is_empty(): pixel_report = await PixelArtChecks.exercise(self,app,pixel_spec,initial)
	if not art_spec.is_empty():
		for i in range(5):
			check(s.battle_command("guard"),"source-art normal defense "+str(i)); await drain_art(app,ids)
		check(art_frames_seen.has(art_spec.enemy.frames[2].sha256) and art_frames_seen.has(art_spec.enemy.frames[3].sha256),"both real attack frames rendered during normal enemy commands")
		check(app.saves.load_into(s,initial),"restore after source-art playback observation")
		await settle()
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("imported-draft.png"))
	await click(option(app,"攻击",true)); await click(option(app,"攻击 2"))
	battle = s.state.extensions[Battle.KEY]
	check(battle.enemies[0].hp == 28 and battle.enemies[1].hp < 28,"real mouse command targets only the selected imported instance")
	var committed: Dictionary = s.state.duplicate(true); view._process(1.0/60); view._process(1.0/100)
	check(s.state == committed,"display frame steps never reapply imported combat results")
	view.skip(); await settle(); save(app,"after-target-command")
	check(app.saves.load_into(s,initial) and s.state.extensions[Battle.KEY].enemies.all(func(e): return e.hp == 28),"load restores both independent original HP values")
	var commands: int = 0
	while s.battle_open() and commands < 100:
		var target: String = s.state.extensions[Battle.KEY].enemies.filter(func(e): return e.hp > 0)[0].instance_id
		check(s.battle_command("attack",target),"normal Native attack "+str(commands)); view.skip(); commands += 1
	check_outcome(s,"win","won-text","camp",3,execution_id)
	var win: String = save(app,"win"); var state: Dictionary = s.state.duplicate(true)
	check(app.saves.load_into(s,win) and s.state.cursor == state.cursor and s.state.entities == state.entities and s.state.scopes == state.scopes and s.state.active_party == state.active_party and s.state.committed_effect_ids == state.committed_effect_ids and s.state.extensions == state.extensions,"victory save preserves effects, rewards and party without repeating the callback")
	check(app.saves.load_into(s,initial),"restore initial state before escape")
	await settle(); await click(option(app,"其他",true)); await click(option(app,"撤离"))
	view.skip(); await settle(); check_outcome(s,"escape","escape-text","camp",3,execution_id); save(app,"escape")
	check(app.saves.load_into(s,initial),"restore initial state before ordinary defensive loss")
	commands = 0
	while s.battle_open() and commands < 1000:
		check(s.battle_command("guard"),"normal Native defense "+str(commands)); view.skip(); commands += 1
	check_outcome(s,"loss","loss-text","loss",5,execution_id)
	save(app,"loss"); check(app.saves.load_into(s,initial),"loss does not overwrite prior save generation")
	check(s.state.extensions[Battle.KEY].enemies.map(func(e): return e.instance_id) == ids,"all reloads retain imported instance identities")
	root.remove_child(app); app.queue_free(); await process_frame; finish()
func check_outcome(session, outcome: String, node: String, scene: String, party_size: int, execution_id: String) -> void:
	# This existing story drains set/party/transfer nodes before waiting at dialogue.
	check(not session.battle_open() and session.state.cursor.node_id == "node.miaopang.camp."+node and session.state.cursor.scene_id == "scene.miaopang.camp."+scene,outcome+" reaches the authored dialogue and scene")
	check(session.state.scopes.run["flag.miaopang.camp.practice"] == outcome and session.state.active_party.size() == party_size,outcome+" applies the retained story flag and party change")
	check(session.state.committed_effect_ids.count(execution_id) == 1,outcome+" commits the battle exactly once")
func save(app, label: String) -> String:
	check(app.saves.save(app.session),label+" save publishes"); var path: String = app.saves.last_path
	saves.append({"label":label,"package_path":package_path,"save_path":path}); return path
func finish() -> void:
	var report = {"checks":checks,"failed":failed,"saves":saves,"engine_injected_input":true,"physical_input":false,
		"normal_rule_commands_for_outcomes":true,"legacy_rule_parity":false,"full_playthrough":false,"legacy_art_imported":not art_spec.is_empty(),"source_art_frames_seen":art_frames_seen}
	report["pixel_art"] = pixel_report
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("legacy import checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
func option(app, prefix: String, exact: bool = false) -> Button:
	for control in app._battle_controls():
		if control is Button and (control.text == prefix if exact else control.text.begins_with(prefix)): return control
	check(false,"missing command "+prefix); return null
func click(control: Control) -> void:
	if control == null: return
	var p = control.get_global_rect().get_center()
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = p; event.global_position = p; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event,true)
	await settle()
func settle() -> void:
	await process_frame; await process_frame; await process_frame

func image_hash(image: Image) -> String:
	image.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = image.get_data()
	# Native's established edge repair changes only invisible RGB. Normalize
	# alpha-zero RGB, while checking every alpha and every visible RGB byte.
	for i in range(0,bytes.size(),4):
		if bytes[i+3] == 0: bytes[i] = 0; bytes[i+1] = 0; bytes[i+2] = 0
	var context = HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

func check_art(app, battle: Dictionary) -> void:
	var package = app.session.package; var view = app.battle_view
	var definition: Dictionary = package.index.actor_definitions[battle.enemies[0].definition_id]
	check(definition.has("battle_sprite_set"),"source enemy has an imported action set")
	if not definition.has("battle_sprite_set"): return
	var sprite: Dictionary = package.index.battle_sprite_sets[definition.battle_sprite_set]
	check(sprite.clips.size() == 2 and sprite.missing_action == "idle","only supplied idle/attack clips with explicit missing-action fallback")
	var frames: Array = []
	for action in ["idle","attack"]:
		var clip: Dictionary = sprite.clips.filter(func(c): return c.action == action and c.facing == "lower_right")[0]
		check(clip.frames.size() == 2,"two source frames bound to "+action)
		frames.append_array(clip.frames)
	for i in range(4):
		var expected: Dictionary = art_spec.enemy.frames[i]; var frame: Dictionary = frames[i]
		check(frame.width == expected.width and frame.height == expected.height,"original dimensions retained for source frame "+str(i))
		check(package.index.assets[frame.asset_id].sha256 == expected.sha256,"exact exported PNG bound for source frame "+str(i))
		check(image_hash(package.textures[frame.asset_id].get_image()) == expected.rgba_sha256,"GPU texture retains every alpha and visible RGB byte for source frame "+str(i))
		check(not package.index.assets[frame.asset_id].redistributable,"source frame remains local-use-only "+str(i))
	var encounter: Dictionary = Battle.encounter(package.world,battle.encounter_id)
	var background: Dictionary = art_spec.background.frames[0]
	check(package.index.assets[encounter.background_asset].sha256 == background.sha256,"exact FBP export bound to the encounter")
	check(image_hash(package.textures[encounter.background_asset].get_image()) == background.rgba_sha256,"background palette bytes reach the GPU texture")
	var state: Dictionary = app.session.state.duplicate(true)
	for elapsed in [0.0,0.201]:
		view.idle_elapsed = elapsed; view.queue_redraw(); await RenderingServer.frame_post_draw
		var frame: Dictionary = view.displayed_frames[battle.enemies[0].instance_id]
		var expected: Dictionary = art_spec.enemy.frames[0 if elapsed == 0 else 1]
		check(package.index.assets[frame.asset_id].sha256 == expected.sha256,"actual source idle frame at "+str(elapsed))
		var size: Vector2 = frame.rect.size / view.projection.x.x
		check(size.is_equal_approx(Vector2(expected.width,expected.height)),"source enemy renders at original reference size")
	check(app.session.state == state,"inspecting original art leaves authoritative state unchanged")
	check(view.background_rect == view.classic_stage,"320x200 source background fills the retained reference stage without cropping")
	root.get_texture().get_image().save_png(output.path_join("source-art-idle.png"))

func drain_art(app, ids: Array) -> void:
	var view = app.battle_view; var steps: int = 0
	var committed: Dictionary = app.session.state.duplicate(true)
	while view.playing() and steps < 1000:
		view.queue_redraw(); await RenderingServer.frame_post_draw
		for id in ids:
			if not view.displayed_frames.has(id): continue
			var frame: Dictionary = view.displayed_frames[id]
			var hash_value: String = app.session.package.index.assets[frame.asset_id].sha256
			if hash_value not in art_frames_seen:
				art_frames_seen.append(hash_value)
				root.get_texture().get_image().save_png(output.path_join("source-art-frame-"+str(art_frames_seen.size())+".png"))
		view._process(.05); steps += 1
	check(not view.playing(),"source-art action finishes within its declared duration")
	check(app.session.state == committed,"source-art playback does not settle damage twice")
