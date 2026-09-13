# SPDX-License-Identifier: MIT
extends SceneTree
## The formal app's load-failure page: a corrupt package shows the actual
## error with reselect/dismiss and never touches the live session; a good
## package opens the formal session; a later failure cannot clobber it.
## Windowed because the app builds its real UI in _ready.
const App = preload("res://src/native_app.gd")

var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray

func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)

func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 3 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("_run")

func _run() -> void:
	get_root().title = "PAL Wanxiang | load failure page probe"
	get_root().size = Vector2i(1280, 720)
	var app = App.new()
	get_root().add_child(app)
	await process_frame

	# A corrupt package: real error page, session untouched.
	var file = FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string("this is not a content package"); file.close()
	var first: bool = app.open_package(args[0])
	check(not first, "the corrupt package refuses")
	check(app.session.state.is_empty(),
		"the failed candidate does not touch the live session")
	check(app.load_error_picker != null and app.load_error_picker.visible,
		"the load failure page is presented")
	check(app.load_error_text.text.contains(args[0]) and app.load_error_text.text.contains("实际错误："),
		"the failure page carries the path and the actual error")

	# Dismiss (cancel) without reselecting: still nothing running.
	app.load_error_picker.hide()
	check(not app.load_error_picker.visible and app.session.state.is_empty(),
		"dismissing the page keeps the session untouched")

	# A good author package opens the formal session.
	var second: bool = app.open_package(args[1])
	check(second and not app.session.state.is_empty(),
		"the author package opens the formal session after the failure")
	var live_id: String = app.session.state.session_id
	details.live_session = live_id

	# A later failure cannot clobber the live session.
	var third: bool = app.open_package(args[0])
	check(not third and not app.session.state.is_empty()
		and app.session.state.session_id == live_id,
		"a later failure cannot clobber the live session")
	check(app.load_error_picker.visible, "the failure page presents again on the later failure")
	details.message = app.message.text
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed,
		"failed": failed, "success": failed == 0, "details": details,
		"scope": "real app instance; corrupt package, dismiss, author package, isolation"} , "  "))
	file.close(); quit(1 if failed else 0)
