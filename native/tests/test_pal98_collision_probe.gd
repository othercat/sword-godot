# SPDX-License-Identifier: MIT
extends SceneTree
## The two-level collision probe over real MAP20 data: the party's own start
## position accepts, the blocked tile pair refuses, and the event proximity
## scan refuses within abs(dx) + 2*abs(dy) < 16 of an active event.
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
const CollisionProbe = preload("res://src/native_pal98_collision_probe.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Package = preload("res://src/native_package.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error("package rejected: " + str(package.error)); quit(2); return
	var records = package.pal98_graphics.open_records()

	# Real MAP20 blocked-tile scan: find one blocked cell and one free cell.
	var background = preload("res://src/native_pal98_map_background.gd").new()
	check(background.load_source(records, 20, 0, 0), "MAP20 loads with the day palette")
	var plan: Dictionary = background.draw_plan(27, 57, 0)
	check(not plan.has("error"), "the opening viewport's map plan builds: " + str(plan.get("error", "")))
	var map_bytes: PackedByteArray = records.decoded_chunk("MAP.MKF", 20).value
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	var events_state: Dictionary = storage.source_state()
	events_state = storage.load_scene_events(events_state, 1).state
	var probe = CollisionProbe.new()
	check(probe.bind(map_bytes, events_state), "the probe binds the real map and event state")

	# The party's own opening position must be free ground.
	var start: Dictionary = probe.probe(1024, 1024)
	check(start.get("accepted") == true,
		"the opening position probes as free ground: " + str(start))
	if not start.get("accepted", false): finish(args); return

	# Inspect only the selected lower descriptors across all 16384 half-cells.
	# No blocking data in this map is an observation, not a collision assertion.
	var blocked_cell := "none in MAP20"
	for cell in range(16384):
		if (map_bytes.decode_u16(cell * 4) & 0x2000) == 0: continue
		var half := cell & 1; var cell_x := (cell >> 1) & 63; var cell_y := cell >> 7
		blocked_cell = "%d,%d,%d" % [cell_x, cell_y, half]
		var refused = probe.probe(cell_x * 32 + half * 16, cell_y * 16 + half * 8)
		check(refused.get("accepted") == false, "the actual selected blocked half-cell refuses")
		break

	# The event proximity scan: an active event within the threshold refuses.
	var events_state2: Dictionary = storage.source_state()
	var with_events: int = -1
	for scene in range(2, 60):
		var loaded: Dictionary = storage.load_scene_events(events_state2, scene)
		if loaded.has("error"): continue
		events_state2 = loaded.state
		if events_state2.active_slots[0] is PackedByteArray:
			with_events = scene
			break
	check(with_events > 0, "a scene with an active first event record loads: " + str(with_events))
	if with_events < 0: finish(args); return
	var row: PackedByteArray = events_state2.active_slots[0]
	row.encode_s16(12, 2)
	row.encode_s16(2, 1024 + 4)
	row.encode_s16(4, 1024 + 2)
	events_state2.active_slots[0] = row
	var probe2 = CollisionProbe.new()
	probe2.bind(map_bytes, events_state2)
	var near: Dictionary = probe2.probe(1024, 1024)
	check(near.get("accepted") == false and near.get("reason") == "event_proximity",
		"an active event within abs(dx)+2*abs(dy)<16 refuses the probe: " + str(near))
	check(probe2.probe(1024, 1024, 1).get("accepted") == true, "the excluded runtime event id does not collide with itself")
	var far_row: PackedByteArray = row.duplicate()
	far_row.encode_s16(2, 1024 + 40)
	far_row.encode_s16(4, 1024 + 40)
	events_state2.active_slots[0] = far_row
	var probe3 = CollisionProbe.new()
	probe3.bind(map_bytes, events_state2)
	var far: Dictionary = probe3.probe(1024, 1024)
	check(far.get("accepted") == true, "an event beyond the threshold stops blocking")

	var output: Dictionary = {"suite": "test_pal98_collision_probe", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_collision_probe", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
