# SPDX-License-Identifier: MIT
extends SceneTree
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Game = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
const Facing = preload("res://src/native_pal98_walk_facing.gd")
const Member = preload("res://src/native_pal98_member_sync.gd")
const Frame = preload("res://src/native_pal98_input_frame.gd")
const Probe = preload("res://src/native_pal98_collision_probe.gd")
const Requests = preload("res://src/native_pal98_scene_sprite_requests.gd")
class Recorder:
	var seen: Array = []
	func probe(x: int, y: int) -> Dictionary:
		seen.append([x,y]); return {"accepted": true}
class Gap:
	var seen: Array = []
	func answer(request: Dictionary) -> Dictionary:
		seen.append(request.kind); return {"completed": true}
class ClockDouble:
	func consume(units: int) -> Dictionary: return {"consumed": units}
class RuntimeDouble:
	func answer(request: Dictionary) -> Dictionary:
		if request.kind == "fade_event_pump": return {"completed": true, "pumped": request.events}
		return {"completed": true}
class TerminalEnterDouble:
	var calls := 0
	func start(state: Dictionary, _scene, _entry, _event) -> Dictionary:
		calls += 1
		return {"state":state.duplicate(true),"return_entry":0}
	func cancel() -> void: pass
class TerminalReloadDouble:
	var sprites
	var maps: Dictionary
	func resume(_id: String, response: Dictionary) -> Dictionary:
		return {"state":response.state,"cache":sprites,"map_cache":maps}
	func cancel() -> void: pass
var checks: Array = []
var details: Dictionary = {}
func check(ok: bool, name: String, actual = null) -> void:
	checks.append({"name": name, "passed": ok, "actual": actual.duplicate(true) if actual is Dictionary or actual is Array else actual})
func fixture() -> Dictionary:
	var words: Array=[]; words.resize(450); words.fill(0)
	return {"equipment":{"role_words":words},"globals": {"viewport_x":864,"viewport_y":912,"party_x":160,"party_y":112,
		"world_x":1024,"world_y":1024,"previous_x":1024,"previous_y":1024,"direction_word":0,
		"walk_phase_word":0,"leader_frame_offset_word":0,"party_frame_offset_word":0,"member_last":1,"follower_count":0,"ffxy_max_x":1696,"ffxy_max_y":1840},
		"party_trail":[{"x":1024,"y":1024,"direction_word":0},{"x":1008,"y":1016,"direction_word":0},
		{"x":992,"y":1008,"direction_word":0},{"x":976,"y":1000,"direction_word":0},{"x":960,"y":992,"direction_word":0}],
		"party_records":[{"role_id":0,"x":160,"y":112,"current_frame":0},{"role_id":1,"x":160,"y":112,"current_frame":0}]}
func frame_owner():
	var facing = Facing.new(); var member = Member.new(); var spy = Recorder.new()
	member.bind_probe(spy); facing.bind_member_sync(member)
	var frame = Frame.new(); frame.bind(facing,spy,[0,1,2,3,4,5,6,7,8],0,8)
	return frame
func assemble(package, all_gaps: bool = true):
	var game = Game.new()
	if not game.open(package): return game
	game.bind_clock(ClockDouble.new()); game.bind_runtime(RuntimeDouble.new())
	game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	Config.bind_gaps(game, all_gaps)
	return game
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var right = PackedInt32Array([0,0,0,2,0,0,0,0,0])
	var idle = PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var frame = frame_owner()
	var moved: Dictionary = frame.tick(fixture(),right)
	check(not moved.has("error"),"control: movement tick completes")
	var stopped: Dictionary = frame.tick(moved.state,idle)
	check(not stopped.has("error") and stopped.state.party_trail == moved.state.party_trail,
		"idle after movement must not rotate stale previous-world trail",stopped.get("state",{}).get("party_trail",[]))
	check(not stopped.has("error") and stopped.state.party_records[0].current_frame == stopped.state.globals.direction_word * 3,
		"idle after movement must select the standing frame",stopped.get("state",{}).get("party_records",[])[0].current_frame)
	var idle_again: Dictionary = frame.tick(stopped.state,idle)
	check(not idle_again.has("error") and idle_again.state.party_records[0].current_frame==idle_again.state.globals.direction_word*3,
		"second idle must not animate from stale previous world",idle_again.get("state",{}).get("party_records",[])[0].current_frame)
	for axis in ["x","y"]:
		var edge: Dictionary = fixture()
		edge.globals.ffxy_max_x=1696; edge.globals.ffxy_max_y=1840
		if axis=="x": edge.globals.viewport_x=1696
		else: edge.globals.viewport_y=1840
		edge.globals.world_x=edge.globals.viewport_x+edge.globals.party_x
		edge.globals.world_y=edge.globals.viewport_y+edge.globals.party_y
		edge.globals.previous_x=edge.globals.world_x; edge.globals.previous_y=edge.globals.world_y
		var edge_tick: Dictionary = frame.tick(edge,right)
		check(not edge_tick.has("error") and edge_tick.state.globals.viewport_x==edge.globals.viewport_x
			and edge_tick.state.globals.viewport_y==edge.globals.viewport_y,
			"input ffxy clamp plus one-axis rollback at max "+axis,
			[edge_tick.get("state",{}).get("globals",{}).get("viewport_x"),edge_tick.get("state",{}).get("globals",{}).get("viewport_y")])
	var spy = Recorder.new(); var member = Member.new()
	member.bind_probe(spy)
	var s: Dictionary = fixture()
	member.answer({"kind":"sync_party_formation_and_frames","state":s})
	check(spy.seen.size() == 1 and spy.seen[0][0] > 800 and spy.seen[0][1] > 900,
		"member collision candidates must use world coordinates, not screen coordinates",spy.seen)
	s.equipment.role_words[64*6]=4
	s.globals.member_last=0; s.globals.direction_word=1; s.globals.walk_phase_word=3
	s.globals.leader_frame_offset_word=2; s.globals.party_frame_offset_word=1
	var four: Dictionary = member.answer({"kind":"sync_party_formation_and_frames","state":s})
	check(not four.has("error") and four.party_records[0].current_frame == 7,
		"four-frame leader uses direction*4+walk_phase",four.get("party_records",[]))
	var held = PackedInt32Array([0,0,0,0,0,0,0,0,3])
	var held_result: Dictionary = frame.tick(fixture(),held)
	check(not held_result.has("error") and held_result.confirm == false,
		"held level 3 is not a newly pressed confirm",held_result.get("confirm"))
	var illegal = PackedInt32Array([0,0,0,0,0,0,0,0,7])
	check(frame.tick(fixture(),illegal).has("error"),"confirm level outside 0..3 must refuse")
	var invalid_map = Frame.new()
	var bound: bool = invalid_map.bind(frame._facing,spy,[0,1,2,3,4,5,6,7,-1],0,8)
	var map_result: Dictionary = invalid_map.tick(fixture(),idle) if bound else {"error":"bind refused"}
	check(not bound or map_result.has("error"),"negative confirm mapping must refuse")
	var package = Package.new()
	check(package.load_package(args[0]), "real package admits")
	if not package.error.is_empty(): finish(args); return
	var game = assemble(package)
	check(game.new_state(0x12345).has("error"), "unknown initializer is not silently source-derived")
	var fresh: Dictionary = game.new_state(0x12345, Config.configuration())
	check(not fresh.has("error"), "explicit probe initializer accepted")
	var parked: Dictionary = game.begin()
	check(not parked.has("error") and parked.get("awaiting_effect") and not parked.get("completed"), "begin parks a real effect")
	if parked.has("error") or not parked.get("awaiting_effect"): finish(args); return
	check(parked.state.globals.current_scene == 1 and parked.state.globals.world_x == 1024, "parked state is current scene/coordinates")
	check(parked.pending_effect.kind in ["wait","poll_input"], "draw_string is never a confirm gate")
	check(game.begin().has("error"), "active begin refuses without replacing continuation")
	var pending_id: String = parked.pending_id
	var pending_state: Dictionary = game.state.duplicate(true)
	var wait_tested := false; var held_tested := false; var timer_tested := false
	var kinds: Dictionary = {}; var titles_before_confirm := false
	var terminal: Dictionary = parked
	for ordinal in range(8192):
		if terminal.has("error") or terminal.get("completed"): break
		var effect: Dictionary = terminal.pending_effect
		kinds[effect.kind + ":" + str(effect.get("model",""))] = true
		if effect.kind == "wait" and not wait_tested:
			var before: Dictionary = game.state.duplicate(true)
			var no_clock: Dictionary = game.tick(right, false)
			check(no_clock.get("pending_id") == terminal.pending_id and game.state == before, "wait without timer does not advance or move")
			var held_wait: Dictionary = game.tick(held, false)
			check(held_wait.get("pending_id") == terminal.pending_id, "held confirm cannot bypass timer")
			var clocked: Dictionary = game.tick(idle, true)
			check(not clocked.has("error") and clocked.get("pending_id") != terminal.pending_id, "one supplied timer event advances one continuation")
			terminal = clocked; wait_tested = true; timer_tested = true
			continue
		if effect.kind == "poll_input" and effect.get("model") == "until_nonzero" and not held_tested:
			var before: Dictionary = game.state.duplicate(true)
			var held_reply: Dictionary = game.tick(held)
			check(held_reply.get("awaiting_confirm") and game.state.globals == before.globals, "held level does not release confirmation or move")
			terminal = held_reply; held_tested = true
		for title in game.dialogue_host.texts():
			if title == "李逍遥:": titles_before_confirm = true
		# Explicit character-skip input keeps this integration replay bounded.
		var key: int = 2 if terminal.pending_effect.kind == "poll_input" else 0
		terminal = game.tick(PackedInt32Array([0,0,0,0,0,0,0,0,key]), true)
	check(not terminal.has("error") and terminal.get("completed"), "explicit nominal replay reaches actual reload terminal", terminal.get("error"))
	if terminal.has("error") or not terminal.get("completed"): finish(args); return
	check(wait_tested and timer_tested and held_tested, "real timer and confirmation paths exercised", kinds)
	check(titles_before_confirm, "title was drawn normally through text host")
	check(game.enters_seen == [1,2] and game.terminals.size() == 2, "source entry order retained")
	var g: Dictionary = game.state.globals
	var ev: Dictionary = Requests.event_requests(game.storage,game.state.events,g.viewport_x,g.viewport_y)
	check(not ev.has("error") and ev.value.size() == 2, "MAP12 has two visible event requests")
	var resolved_cache: Dictionary = game.cache.resolve_requests(game.storage,game.state.events,game.state.party_records,ev.value)
	check(not resolved_cache.has("error"), "current adopted cache decodes real MAP12 events", resolved_cache.get("error"))
	check(game.map_cache.get("map_id") == 12 and game.cache.snapshot("event").cache.used_words == 23555, "map and sprite cache adopted together")
	var tk: Dictionary = game.tick(idle)
	check(not tk.has("error") and tk.requests.filter(func(row): return row.kind=="event").size() == 2, "normal tick emits T213 from state.events")
	if tk.has("error"): finish(args); return
	game.state.equipment.role_words[64*6]=4
	game.state.globals.direction_word=1
	var dynamic: Dictionary = game.tick(right)
	check(not dynamic.has("error") and dynamic.state.party_records[0].current_frame == dynamic.state.globals.direction_word*4+dynamic.state.globals.walk_phase_word,
		"frame count reads current role table")
	var preserved: Dictionary = game.state.duplicate(true)
	game.state.globals.loaded_map_id=32767
	check(game.tick(right).has("error"), "unavailable current map cannot retain old probe")
	game.state=preserved.duplicate(true); game.awaiting_player=true
	game.state.events.event_count=161
	check(game.tick(right).has("error"), "invalid current events cannot retain old probe")
	# Restart the SAME owner after a host failure.
	var recovering = assemble(package, false)
	recovering.new_state(0x12345,Config.configuration())
	var failed_run: Dictionary = Config.run(recovering)
	check(failed_run.has("error"), "unowned audio is an actual failure", failed_run.get("error"))
	Config.bind_gaps(recovering)
	var retried: Dictionary = Config.run(recovering)
	check(not retried.has("error") and retried.get("completed"), "same-owner failure cleanup permits restart", retried.get("error"))
	if not retried.has("error") and retried.get("completed"):
		var third = TerminalEnterDouble.new(); var resource = TerminalReloadDouble.new()
		resource.sprites = recovering.cache; resource.maps = recovering.map_cache.duplicate(true)
		recovering.enter = third; recovering.reload = resource
		var third_result: Dictionary = recovering._drive_reload({"request":{"id":"third-request","kind":"enter_script",
			"scene_id":2,"entry":0,"event_id":0,"state":recovering.state,"cache":resource.sprites,"map_cache":resource.maps}})
		check(third.calls == 1 and third_result.get("completed") and third_result.enters.size() == 3,
			"third entry is executed, never treated as automatic intro completion")
	# Fresh initialization/cancel must clear prior terminals and captures.
	game.new_state(0x12345,Config.configuration())
	var restarted: Dictionary = game.begin()
	check(game.terminals.is_empty() and restarted.get("awaiting_effect"), "new attempt clears terminal records")
	var current_id: String = restarted.get("pending_id","")
	var current_state: Dictionary = game.state.duplicate(true)
	check(game.resume_dialogue(pending_id,{"kind":"tick"}).has("error") and game.state == current_state and game._pending_dialogue.id == current_id, "old receipt cannot write or cancel new generation")
	var old_enter: String = current_id
	var old_reload: String = game._active_enter_request.id
	game.cancel()
	check(game.enter.resume(old_enter,{"event":{"kind":"tick"}}).has("error") and game.reload.resume(old_reload,{"completed":true}).has("error"), "cancel releases both continuation owners")
	check(game.renderer.restore_dialog_background().has("error"), "cancel removes captured page")
	game.new_state(0x12345,Config.configuration())
	check(not game.begin().has("error"), "cancel then same owner can begin again")
	game.cancel()
	finish(args)
func finish(args) -> void:
	var failed: int=checks.filter(func(row):return not row.passed).size()
	var file=FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"details":details,"passed":checks.size()-failed,"failed":failed},"  "))
	file.close(); print("INDEPENDENT ",checks.size()-failed,"/",checks.size());quit(1 if failed else 0)
