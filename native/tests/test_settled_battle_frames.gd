# SPDX-License-Identifier: MIT
extends SceneTree
const View = preload("res://src/native_battle_view.gd")
var failed: int = 0
var checks: int = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1; push_error(label)
func _initialize() -> void:
	var dead: Dictionary={"action":"dead","loop":false,"frames":[{"frame_id":"fall-start","duration_us":125000},{"frame_id":"grounded","duration_us":375000}]}
	for clock in [0,50000,125000,499999,500000,1000000]:
		check(View.frame_for_pose(dead,clock,true).frame_id=="grounded","settled death independent of idle clock "+str(clock))
		check(View.frame_for_pose(dead,clock,false).frame_id==("fall-start" if clock<125000 else "grounded"),"explicit death phase retains authored timing "+str(clock))
	var looping: Dictionary=dead.duplicate(true); looping.loop=true
	for clock in [0,124999,125000,499999,500000,624999,625000]:
		check(View.frame_for_pose(looping,clock,true).frame_id==("fall-start" if clock%500000<125000 else "grounded"),"looping death retains animation "+str(clock))
	var idle: Dictionary=dead.duplicate(true); idle.action="idle"
	check(View.frame_for_pose(idle,0,true).frame_id=="fall-start","missing death idle fallback is not frozen")
	check(View.frame_for_pose({},0,true).is_empty(),"static fallback remains empty")
	check(dead.frames[0].duration_us==125000 and dead.frames.size()==2,"authored clip unchanged")
	print("Settled battle frames checks=",checks," failed=",failed)
	quit(0 if failed==0 else 1)
