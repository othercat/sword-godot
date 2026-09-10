# SPDX-License-Identifier: MIT
extends "res://tests/test_miaopang_practice.gd"
## Reuse ordinary input helpers, selecting only notice-related routes. No state
## or content injection; the two packages were authored in the production form.
const Notice = preload("res://src/native_story_notice.gd")
var camp_save: String = ""
var loss_save: String = ""
var final_package: String

func key(code: int, down: bool) -> void:
	# The reused historical route helper uses WASD. Exercise today's default
	# traditional arrow keys, with an isolated absent preferences path.
	var actual: int = {KEY_W:KEY_UP, KEY_S:KEY_DOWN, KEY_A:KEY_LEFT, KEY_D:KEY_RIGHT}.get(code, code)
	super.key(actual, down)

func settle() -> void:
	for i in range(8): await process_frame

func notice_check(label: String) -> void:
	await settle()
	var row: Dictionary = Notice.for_node(s.package.world, s.current_node().id)
	var shown: bool = not row.is_empty() and not s.dialogue_open and not s.battle_open()
	check(app.story_notice.scroll.visible == shown, "notice visibility " + label)
	check(app.story_notice.text.text == (row.title + "\n" + row.text if shown else ""), "exact authored plain text or cleared " + label)
	check(not s.state.extensions.has(Notice.KEY), "notice never enters state " + label)
	if not shown: return
	check(app.map_ui.active, "bound end uses authored map UI " + label)
	check(app.story_notice.scroll.size.y <= 130.0 and app.stage.size.y > 200.0, "notice remains bounded without shrinking map " + label)
	check(app.dialogue_text.visible and not app.dialogue_text.text.is_empty(), "ordinary interaction hint retained " + label)
	check(app.story_notice.text.get_theme_font_size("font_size") == app.dialogue_text.get_theme_font_size("font_size"), "notice inherits map typography " + label)
	check(not app.save_button.disabled and not s.dialogue_open, "notice is not a modal or save gate " + label)
	await shot(route_name + "-" + label)
	if row.text.length() == 2000:
		var bar: VScrollBar = app.story_notice.scroll.get_v_scroll_bar()
		check(bar.max_value > bar.page, "long notice has real scroll range")
		app.story_notice.scroll.scroll_vertical = int(bar.max_value); await settle()
		check(app.story_notice.scroll.scroll_vertical > 0 and app.story_notice.text.text.ends_with("末行可见"), "long notice reaches final line without markup interpretation")
		await shot(route_name + "-" + label + "-scrolled")

func checkpoint(label: String) -> bool:
	await notice_check("before-" + label)
	var previous_path: String = store.last_path
	var ok: bool = await super.checkpoint(label)
	if not ok: return false
	if not check(store.last_path != previous_path, "F5 creates a new save " + label): return false
	root.grab_focus(); s.set_focus(true)
	await notice_check("loaded-" + label)
	if package_path == final_package and at("camp-end"): camp_save = store.last_path
	if at("loss-end"): loss_save = store.last_path
	return true

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 4: quit(2); return
	final_package = args[0]; output = args[3]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800); app = App.instantiate()
	app.input_profile_path = output.path_join("isolated-input.json")
	root.add_child(app); await process_frame
	check(app.key_bindings.profile.preset == "classic", "isolated default arrow-key profile")
	for entry in [[args[1], "long-skip", "skip", "medicine"], [args[0], "final-skip", "skip", "medicine"], [args[0], "final-loss", "loss", "none"]]:
		package_path = entry[0]; route_name = entry[1]
		store = Save.new(output.path_join(route_name)); app.saves = store
		if not check(app.open_package(package_path), "production window opens authored package"): finish(); return
		s = app.session; root.grab_focus(); s.set_focus(true); await settle()
		await notice_check("new-package")
		var ok: bool = await route(entry[2], entry[3])
		routes.append({"name":route_name, "success":ok, "input_kind":"Godot Input.parse_input_event; save restore uses validated loader"})
		if not ok or failed > 0: finish(); return
		await notice_check("route-end")
		if entry[2] == "skip" and not await checkpoint("back-to-camp"): finish(); return
	check(not camp_save.is_empty() and not loss_save.is_empty(), "both exact save paths retained")
	check(store.load_into(s, camp_save), "load earlier camp checkpoint after defeat"); await notice_check("loss-to-camp")
	check(store.load_into(s, loss_save), "restore independent defeat checkpoint"); await notice_check("defeat-restored")
	package_path = args[2]
	check(app.open_package(package_path), "switch to unchanged package without notice component")
	s = app.session; await notice_check("legacy-package-switch")
	check(not app.map_ui.active and not app.story_notice.scroll.visible and app.story_notice.text.text.is_empty(), "legacy parent and hidden empty notice restored")
	finish()
