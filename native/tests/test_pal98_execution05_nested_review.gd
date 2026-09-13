# SPDX-License-Identifier: MIT
extends "res://tests/test_pal98_nested_t212_production.gd"

func _with_message(source):
	var files: Dictionary = {}
	for role in Sources.FILES: files[role] = source.copy_bytes(role)
	var chunks: Array = []
	for i in range(5): chunks.append(source.copy_chunk("sss",i))
	chunks[3] = PackedByteArray([0,0,0,0,2,0,0,0])
	files.sss = _mkf(chunks); files.messages = PackedByteArray([65,0])
	var hashes: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(files[role])
	var identity = Sources.fingerprint("gbk",hashes)
	var meta = source.metadata();meta.fingerprint = identity
	for role in Sources.FILES:
		meta.files[role] = {"path":"content/pal98-sources/"+identity+"/"+Sources.FILES[role],"sha256":hashes[role],"size_bytes":files[role].size()}
	var candidate = Sources.new()
	if not candidate.load_source(meta,files,Schema.new()): push_error(candidate.error); return null
	return candidate

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var package = Package.new()
	if not package.load_package(args[0]): quit(2); return
	var game = Game.new(); game.open(package); Config.bind_gaps(game)
	game.bind_clock(Clock.new()); game.bind_runtime(Runtime.new()); game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	game.new_state_from_source(0x12345,"explicit_replay",Config.configuration())
	var begun = game.begin()
	check(not begun.has("error"),"original opening reaches its first real wait")
	var empty = PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var before: Array = []
	var counter := 0
	while game.is_dialogue_parked() and counter < 4096:
		before = game.pending_page_requests()
		if not before.is_empty(): break
		var advanced = game.tick(empty,true)
		if advanced.has("error"): check(false,"unexpected source drive failure: "+str(advanced.error));finish(args);return
		counter += 1
	check(not before.is_empty(),"original opening emitted a title or body draw, steps="+str(counter))
	if not before.is_empty():
		var carried: Array = before.duplicate(true)
		var next = game.tick(empty,true)
		check(not next.has("error"),"one timer/input event resumes source flow")
		var after: Array = game.pending_page_requests()
		check(not after.is_empty() and after.has(carried[0]),"same-page text survives a timing/input park; before="+str(carried)+" after="+str(after))
	game.cancel()
	# Full nested T212 is evidenced. Starting it with an empty cache while the
	# current map is already loaded must not invent a map/cache mismatch.
	var fingerprint: String = package.pal98_graphics.metadata().source_fingerprint
	var source = _source_two(fingerprint,[[0x0078,0,0,0],[0x0001,0,0,0]],[[0x0001,0,0,0]])
	var holder = Pack.new();holder.pal98_sources = source;holder.pal98_graphics = package.pal98_graphics
	var same = _assembly(holder);var initial = Config.configuration();initial.globals.resource_flags=12
	same.new_state(1,initial)
	var same_result = same.begin()
	check(not same_result.has("error"),"nested T212 on the current map reuses the live cache: "+str(same_result.get("error","")))
	# A scene switch inside the child legitimately enters the destination.
	# A dialogue wait there suspends the stack; it is not an unsupported user
	# decision and must not be rejected merely because the call is nested.
	var child_wait = _with_message(_source_two(fingerprint,[[0x0059,2,0,0],[0x0078,0,0,0],[0x0001,0,0,0]],[[0xFFFF,0,0,0],[0x0001,0,0,0]]))
	var h = Pack.new();h.pal98_sources=child_wait;h.pal98_graphics=package.pal98_graphics
	var waiting = _assembly(h);waiting.new_state(1,initial)
	var waited = waiting.begin()
	check(not waited.has("error") and waited.get("awaiting_effect",false),"nested entry may park on its real timer wait: "+str(waited.get("error","")))
	if not waited.has("error"):
		var old_id: String = waited.get("pending_id", "")
		check(waiting._frames.size() == 2, "both parent and child continuations survive the dialogue wait")
		for ordinal in range(2048):
			if waited.has("error") or waited.get("completed", false): break
			var levels = PackedInt32Array([0,0,0,0,0,0,0,0,2 if waiting.pending_kind()=="poll_input" else 0])
			waited = waiting.tick(levels, true)
		check(not waited.has("error") and waited.get("completed", false), "child dialogue resumes and returns through the parent")
		if waited.get("completed", false):
			check(waiting.terminals.size() == 2 and waiting.terminals[0].scene == 2 and waiting.terminals[1].scene == 1,
				"inner and outer EnterScript retain their own scene identity")
			check(waiting.state.events.scene_records.decode_u16(2) == waiting.terminals[1].return_entry
				and waiting.state.events.scene_records.decode_u16(10) == waiting.terminals[0].return_entry,
				"each ByRef result writes exactly its own scene entry")
			check(waiting.map_cache.map_id == waiting.state.globals.loaded_map_id and waiting.map_cache.map_id == 12,
				"parent terminal retains child's latest MAP lease")
		var current: Dictionary = waiting.state.duplicate(true)
		check(waiting.resume_dialogue(old_id, {"kind":"tick"}).has("error") and waiting.state == current,
			"completed child receipt cannot overwrite the final parent state")
		waiting.new_state(1,initial)
		var again: Dictionary = waiting.begin()
		check(not again.has("error") and waiting._frames.size() == 2, "same coordinator can recreate both frames")
		var stale_child: String = again.get("pending_id", "")
		waiting.cancel()
		check(waiting._frames.is_empty() and waiting.resume_dialogue(stale_child,{"kind":"tick"}).has("error"),
			"cancel releases every nested frame and refuses its pending receipt")
		waiting.new_state(1,initial)
		check(not waiting.begin().has("error"), "nested cancellation permits a fresh start")
	waiting.cancel(); same.cancel()
	finish(args)
