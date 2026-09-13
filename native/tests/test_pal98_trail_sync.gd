# SPDX-License-Identifier: MIT
extends SceneTree
## The real trail rotation and member sync: the five-entry trail shifts with
## the newest entry carrying the direction plus the pre-move world position,
## the leader and followers adopt their trail positions relative to the
## viewport, and members use the original's probe-rejected fallback while the
## formation-offset candidate stays unrecovered (named in the receipt).
const Facing = preload("res://src/native_pal98_walk_facing.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _state() -> Dictionary:
	return {"globals": {"viewport_x": 864, "viewport_y": 912, "party_x": 160, "party_y": 112,
			"world_x": 1040, "world_y": 1032, "previous_x": 1024, "previous_y": 1024,
			"direction_word": 3, "member_last": 1, "follower_count": 1},
		"party_trail": [
			{"x": 1024, "y": 1024, "direction_word": 3},
			{"x": 1008, "y": 1016, "direction_word": 3},
			{"x": 992, "y": 1008, "direction_word": 3},
			{"x": 976, "y": 1000, "direction_word": 3},
			{"x": 960, "y": 992, "direction_word": 3}],
		"party_records": [
			{"role_id": 0, "screen_x": 160, "screen_y": 112},
			{"role_id": 1, "screen_x": 172, "screen_y": 98},
			{"role_id": 3, "screen_x": 188, "screen_y": 84}]}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]) or DirAccess.dir_exists_absolute(args[0]): quit(2); return
	var facing = Facing.new()

	# rotate_party_trail: the five entries shift back, trail[0] takes the
	# pre-move world and the team direction.
	var state: Dictionary = _state()
	var rotated: Dictionary = facing.answer({"kind": "rotate_party_trail", "state": state})
	check(not rotated.has("error"), "rotate completes: " + str(rotated.get("error", "")))
	var trail: Array = rotated.state.party_trail
	check(trail[0].x == 1024 and trail[0].y == 1024 and trail[0].direction_word == 3,
		"the newest trail entry carries the pre-move world and direction")
	check(trail[1].x == 1024 and trail[2].x == 1008 and trail[3].x == 992 and trail[4].x == 976,
		"the older entries shifted back by one")

	# rotate refuses a wrong-shaped trail.
	var bad = Facing.new()
	var bad_state: Dictionary = _state()
	bad_state.party_trail = [{"x": 0, "y": 0, "direction_word": 0}]
	check(bad.answer({"kind": "rotate_party_trail", "state": bad_state}).has("error"),
		"a wrong-shaped trail is refused by name")

	# sync_members_from_trail: leader, member fallback and follower positions.
	var synced: Dictionary = facing.answer({"kind": "sync_members_from_trail", "state": rotated.state})
	check(not synced.has("error"), "sync completes: " + str(synced.get("error", "")))
	var records: Array = synced.state.party_records
	check(records[0].screen_x == 160 and records[0].screen_y == 112,
		"the leader adopts the party-in-viewport position")
	check(records[1].screen_x == 160 and records[1].screen_y == 112,
		"the member falls back to the raw trail-relative position: %d,%d" % [records[1].screen_x, records[1].screen_y])
	check(records[2].screen_x == 128 and records[2].screen_y == 96,
		"the follower adopts trail[3] relative to the viewport: %d,%d" % [records[2].screen_x, records[2].screen_y])

	# Missing counters are refused by name.
	var no_counters: Dictionary = _state()
	no_counters.globals.erase("member_last")
	var refused: Dictionary = facing.answer({"kind": "sync_members_from_trail", "state": no_counters})
	check(refused.has("error"), "missing member counters are refused by name")

	var output: Dictionary = {"suite": "test_pal98_trail_sync", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
