# SPDX-License-Identifier: MIT
extends SceneTree
const Game=preload("res://src/native_pal98_new_game.gd")
const Config=preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Package=preload("res://src/native_package.gd")
class Clock:
 func consume(units:int)->Dictionary:return {"consumed":units}
class Runtime:
 func answer(r:Dictionary)->Dictionary:return {"completed":true,"pumped":r.get("events",[])}
var checks=[]
func check(ok:bool,name:String):checks.append({"name":name,"passed":ok})
func setup(p):
 var g=Game.new();g.open(p);Config.bind_gaps(g);g.bind_clock(Clock.new());g.bind_runtime(Runtime.new());g.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
 g.new_state_from_source(7,"explicit_replay",Config.configuration());return g
func _initialize():
 var args=OS.get_cmdline_user_args();var p=Package.new();check(p.load_package(args[0]),"source admitted")
 var g=setup(p);var done=Config.run(g);check(done.get("completed",false),"owner rests on actual MAP12")
 var before=g.state.duplicate(true);var old_cache=g.cache;var old_map=g.map_cache.duplicate(true)
 var refused=g.begin_event_trigger(0)
 check(refused.has("error"),"invalid trigger refused")
 check(g.state==before,"invalid event id preserves current gameplay state")
 check(g.cache==old_cache and g.map_cache==old_map,"invalid event id preserves current map/sprite lease")
 check(g.awaiting_player,"invalid event id preserves resting state for retry")
 g.cancel()
 var waiting=setup(p);waiting.begin();var pending=waiting._pending_dialogue.duplicate(true);var wait_state=waiting.state.duplicate(true);var count=waiting._frames.size()
 check(waiting.is_dialogue_parked(),"source dialogue parked")
 var busy=waiting.begin_event_trigger(1)
 check(busy.has("error"),"concurrent trigger refused")
 check(waiting.is_dialogue_parked() and waiting._pending_dialogue==pending,"busy refusal retains actual pending request")
 check(waiting.state==wait_state and waiting._frames.size()==count,"busy refusal retains suspended call frames and state")
 waiting.cancel()
 # A real event reaches an unbound audio request after its accepted start.
 # Rollback restores the current resting lease/page, not the opening snapshot.
 var failed_call=Game.new();check(failed_call.open(p),"rollback owner binds source")
 Config.bind_gaps(failed_call);failed_call.bind_clock(Clock.new());failed_call.bind_runtime(Runtime.new());failed_call.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
 var cfg=Config.configuration();cfg.globals.requested_scene=146
 failed_call.new_state_from_source(7,"explicit_replay",cfg)
 var rest=Config.run(failed_call);check(rest.get("completed",false),"real MAP74 resting baseline")
 var rest_state=failed_call.state.duplicate(true);var rest_cache=failed_call.cache;var rest_map=failed_call.map_cache.duplicate(true)
 var page=failed_call.renderer.checkpoint();var palette=failed_call.executor.installed_rgb6()
 var rejected_type=failed_call.begin_event_trigger(true)
 check(rejected_type.has("error") and failed_call.state==rest_state,"boolean selector rejected without state changes")
 var failure=failed_call.begin_event_trigger(3)
 check(failure.get("error","").contains("query_cd_track_playing"),"accepted call preserves named unbound audio failure")
 check(failed_call.state==rest_state and failed_call.cache==rest_cache and failed_call.map_cache==rest_map,"accepted failure restores current state and both caches")
 check(failed_call.renderer.checkpoint()==page and failed_call.executor.installed_rgb6()==palette,"accepted failure restores current and captured renderer pages plus palette")
 check(failed_call.awaiting_player and failed_call._frames.is_empty() and not failed_call.is_dialogue_parked(),"accepted failure releases call frames and restores resting retry")
 var retried=failed_call.begin_event_trigger(3)
 check(retried.get("error","").contains("query_cd_track_playing") and failed_call.awaiting_player,"same owner can retry without already-active leak")
 failed_call.cancel()
 var out={"suite":"test_execution06_trigger_refusal","checks":checks,"passed":checks.filter(func(x):return x.passed).size(),"failed":checks.filter(func(x):return not x.passed).size()}
 var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(out,"  "));f.close();quit(1 if out.failed else 0)
