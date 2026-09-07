# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Travel = preload("res://src/native_scene_travel.gd")
var checks: Array = []
var failed: int = 0
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok:
		failed += 1
		push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[1]); root.size = Vector2i(1280, 800)
	var app = App.instantiate(); root.add_child(app); await process_frame
	app.saves = Save.new(args[1].path_join("saves"))
	check(app.open_package(args[0]), "production GUI-authored gated package loads")
	await process_frame; await process_frame
	await _click(app.options.get_child(0)); await _click(app.options.get_child(1))
	_key(KEY_S, true)
	for i in range(2): await physics_frame
	_key(KEY_S, false)
	# Let the entire existing follower trail settle before comparing window frames.
	for i in range(64): await physics_frame
	var session = app.session
	var scene: String = session.state.cursor.scene_id
	var portal: Dictionary = session.package.index.scenes[scene].portals[0]
	check(session.entity(session.state.active_party[0]).position == portal.position, "keyboard reaches the gated portal cell")
	check(not session.portal_status(portal).allowed and app.dialogue_text.text.contains(portal.gate.blocked_text), "player HUD shows authored reason without condition variable identifiers")
	var before: Dictionary = session.state.duplicate(true)
	_key(KEY_SPACE, true); _key(KEY_SPACE, false); await process_frame; await process_frame
	var after: Dictionary = session.state.duplicate(true)
	check(after.state_revision - before.state_revision == after.clock.logic_tick - before.clock.logic_tick, "window revision changes only by the regular logic ticks")
	after.erase("clock"); before.erase("clock")
	after.erase("state_revision"); before.erase("state_revision")
	check(after == before and not session.dialogue_open, "blocked key interaction changes no gameplay state while sampling clock continues")
	check(app.message.text == portal.gate.blocked_text and not app.message.text.contains(portal.gate.condition.variable), "blocked interaction displays only player text")
	before = session.state.duplicate(true)
	for i in range(3): check(not session.interact() and session.state == before, "repeated blocked interaction is inert " + str(i))
	await _click(app.save_button); var saved: String = app.saves.last_path
	check(not saved.is_empty(), "blocked portal position saves through game window")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1].path_join("portal-gate-player.png"))
	# Re-enter the existing sample conversation, then choose its real set effect.
	check(session._interact_node(session.package.world.entry_node), "existing conversation reopens for unlock effect")
	await process_frame; await _click(app.options.get_child(0)); await _click(app.options.get_child(0))
	check(session.portal_status(portal).allowed, "actual story set effect unlocks gate without cached truth")
	_key(KEY_SPACE, true); _key(KEY_SPACE, false); await process_frame; await process_frame
	check(session.state.cursor.scene_id != scene and session.state.entities.filter(func(e): return e.instance_id in session.state.active_party).all(func(e): return e.scene_id == session.state.cursor.scene_id), "unlocked keyboard entry transfers the entire party")
	check(app.message.text.is_empty(), "successful entry clears the earlier blocked message")
	await _click(app.options.get_child(0))
	check(session.interact() and session.state.cursor.scene_id == scene, "reverse portal remains independently open")
	check(app.saves.load_into(session, saved) and not session.portal_status(portal).allowed, "loading earlier saved scopes relocks the gate")
	before = session.state.duplicate(true)
	var original: Dictionary = portal.gate.condition.duplicate(true)
	portal.gate.condition.variable = "variable.missing"
	check(session.portal_status(portal).has("error") and not session.interact() and session.state == before, "synthetic invalid gate is distinct from false and fails before mutation")
	portal.gate.condition = original
	# Gate applies to the portal, not all story transfers using the same node.
	check(session._interact_node(portal.transfer_node) and session.state.cursor.scene_id != scene, "explicit story transfer remains independent of portal condition")
	var report = {"checks": checks, "failed": failed, "save_path": saved, "engine_injected_input": true, "synthetic_invalid_variant": true, "physical_human_input": false, "full_playthrough": false}
	FileAccess.open(args[1].path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
func _click(control: Control) -> void:
	var p = control.get_global_rect().get_center()
	for down in [true, false]:
		var e = InputEventMouseButton.new(); e.position = p; e.global_position = p; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down
		root.push_input(e, true)
	await process_frame; await process_frame
func _key(code: Key, down: bool) -> void:
	var e = InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down; Input.parse_input_event(e)
