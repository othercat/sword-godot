# SPDX-License-Identifier: MIT
extends SceneTree
const Edges = preload("res://src/native_pal98_key_edges.gd")
var failed := 0
var count := 0
func check(value: bool, label: String) -> void:
	count += 1
	if not value: failed += 1; push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var keys = Edges.new()
	keys.accept(1,"confirm",true,false,1)
	check(keys.level("confirm") == 2,"press")
	check(keys.level("confirm") == 3,"hold")
	keys.accept(1,"confirm",true,true,2)
	keys.accept(1,"confirm",true,false,3)
	check(keys.level("confirm") == 3,"echo and duplicate")
	keys.accept(2,"confirm",true,false,4)
	keys.accept(1,"confirm",false,false,5)
	check(keys.level("confirm") == 3,"second key holds action")
	keys.accept(2,"confirm",false,false,6)
	check(keys.level("confirm") == 1,"last release")
	check(keys.level("confirm") == 0,"idle")
	keys.accept(1,"confirm",true,false,7)
	keys.accept(1,"confirm",false,false,8)
	check(keys.level("confirm") == 2,"short tap press survives")
	check(keys.level("confirm") == 1,"short tap release survives")
	keys.accept(1,"confirm",true,false,9)
	keys.clear()
	check(keys.level("confirm") == 0,"focus loss drops pending")
	keys.accept(1,"confirm",true,false,10)
	check(keys.level("confirm") == 0,"held key cannot revive")
	keys.accept(1,"confirm",false,false,11)
	keys.accept(1,"confirm",true,false,12)
	check(keys.level("confirm") == 2,"fresh press after release")
	var app = preload("res://src/native_app.gd").new()
	root.add_child(app)
	app._experimental_window = Window.new()
	app.session.set_focus(true)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE; event.pressed = true
	app._pal98_window_input(event,app._experimental_generation-1)
	check(app._pal98_levels()[8] == 0,"old window generation rejected")
	app._pal98_window_input(event,app._experimental_generation)
	check(app._pal98_levels()[8] == 2,"space maps through production handler")
	event.pressed = false
	app._pal98_window_input(event,app._experimental_generation)
	check(app._pal98_levels()[8] == 1,"production release")
	event.physical_keycode = KEY_ENTER; event.pressed = true
	app._pal98_window_input(event,app._experimental_generation)
	check(app._pal98_levels()[8] == 2,"enter maps through production handler")
	app.session.set_focus(false)
	check(app._pal98_levels()[8] == 0,"unfocused production tick clears")
	app._experimental_window.free(); app._experimental_window = null
	app.queue_free()
	await process_frame
	await process_frame
	print("key_edges ",count-failed,"/",count)
	quit(1 if failed else 0)
