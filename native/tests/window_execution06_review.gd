# SPDX-License-Identifier: MIT
extends SceneTree
const Game=preload("res://src/native_pal98_new_game.gd")
const Package=preload("res://src/native_package.gd")
const Config=preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Display=preload("res://src/native_pal98_scene_display.gd")
const Host=preload("res://src/native_pal98_scene_window.gd")
class Clock:
 func consume(units:int)->Dictionary:return {"consumed":units}
class Runtime:
 func answer(request:Dictionary)->Dictionary:return {"completed":true,"pumped":request.get("events",[])}
class AsyncDisplay:
 var done=false
 func tick_presented(keys,beat=false)->Dictionary:
  await Engine.get_main_loop().process_frame
  done=true
  return {"completed":true,"input_move":false}
var checks=[]
var args
var returned={}
func check(ok:bool,name:String):checks.append({"passed":ok,"name":name})
func _initialize():
 args=OS.get_cmdline_user_args()
 if args.size()!=2:quit(2);return
 call_deferred("_run")
func _async_bridge(host):returned=await host.tick_frame(PackedInt32Array([0,0,0,0,0,0,0,0,0]),true)
func _run():
 root.size=Vector2i(640,400);root.content_scale_size=Vector2i(640,400)
 var p=Package.new();check(p.load_package(args[0]),"source admitted")
 var game=Game.new();check(game.open(p),"owner assembled")
 Config.bind_gaps(game);game.bind_clock(Clock.new());game.bind_runtime(Runtime.new());game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
 var initialized=game.new_state_from_source(0x12345,"explicit_replay",Config.configuration())
 check(not initialized.has("error"),"explicit probe initialized")
 var run=Config.run(game);check(run.get("completed",false),"source chain rests")
 var host=Host.new();var display=Display.new()
 check(host.bind_host(root,root,game,display),"host binds real render target")
 var target_count=root.get_child_count()
 root.size=Vector2i(960,600)
 for i in range(3):await process_frame
 check(host.fit.get("scale")==3 and host.frame_view.size==Vector2(960,600),"OS resize updates fit without a test-only manual call")
 check(host.window_to_content(Vector2i(90,60)).get("position")==Vector2i(30,20),"coordinate mapping uses current OS size")
 check(root.min_size.x>=320 and root.min_size.y>=200,"host enforces logical minimum instead of allowing clipping")
 check(host.bind_host(root,root,game,display),"same host can rebind")
 for i in range(2):await process_frame
 check(root.get_child_count()==target_count,"rebind replaces owned viewport and view without orphan nodes")
 var stage=host.stage
 check(not host.bind_host(null,root,game,display),"bad rebind is rejected")
 check(not is_instance_valid(stage) or not stage.is_inside_tree() or host.stage==stage,"failed bind does not abandon a live owned viewport")
 var bridge=Host.new();var async_owner=AsyncDisplay.new();bridge._display=async_owner
 call_deferred("_async_bridge",bridge)
 for i in range(5):await process_frame
 check(returned.get("completed",false),"host awaits async display completion and returns its receipt")
 check(async_owner.done,"async display reaches its completion")
 var output={"suite":"window_execution06_independent","checks":checks,"passed":checks.filter(func(x):return x.passed).size(),"failed":checks.filter(func(x):return not x.passed).size(),"scope":"production host OS resize lifecycle and narrow async bridge; source rendering setup is a probe"}
 var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(output,"  "));f.close();game.cancel();quit(1 if output.failed else 0)
