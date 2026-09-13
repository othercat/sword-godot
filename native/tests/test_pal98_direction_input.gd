# SPDX-License-Identifier: MIT
extends SceneTree
## The recovered PollAndResolveDirection: held keys weigh 1, new presses weigh
## 2 and override in the right > left > down > up order, an axis resolves
## alone only while the other axis is idle, and the result carries at most one
## nonzero axis component.
const DirectionInput = preload("res://src/native_pal98_direction_input.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

## Slot order 0..7: up, down, left, right, and the four alias slots 4..7.
class AcceptProbe:
	func probe(_x: int, _y: int) -> Dictionary:
		return {"accepted": true}

class RejectProbe:
	func probe(_x: int, _y: int) -> Dictionary:
		return {"accepted": false}

func resolve(levels: Array) -> Dictionary:
	var input = DirectionInput.new()
	return input.resolve(levels, [0, 1, 2, 3, 4, 5, 6, 7])

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1: quit(2); return
	var output: Dictionary = {"suite": "test_pal98_direction_input", "checks": checks, "failed": 0}

	check(resolve([0, 0, 0, 0, 0, 0, 0, 0]).get("direction_x") == 0
		and resolve([0, 0, 0, 0, 0, 0, 0, 0]).get("direction_y") == 0,
		"no keys resolve to a zero direction")

	# Held-only movement: weight 1 per axis side.
	check(resolve([3, 0, 0, 0, 0, 0, 0, 0]).get("direction_y") == -1,
		"a held up key resolves negative Y")
	check(resolve([0, 3, 0, 0, 0, 0, 0, 0]).get("direction_y") == 1,
		"a held down key resolves positive Y")
	check(resolve([0, 0, 3, 0, 0, 0, 0, 0]).get("direction_x") == -1,
		"a held left key resolves negative X")
	check(resolve([0, 0, 0, 3, 0, 0, 0, 0]).get("direction_x") == 1,
		"a held right key resolves positive X")

	# A new press (level 2) overrides a held opposite key.
	var pressed: Dictionary = resolve([0, 3, 0, 2, 0, 0, 0, 0])
	check(pressed.get("direction_x") == 1 and pressed.get("direction_y") == 0,
		"a newly pressed right beats a held down")
	var pressed_up: Dictionary = resolve([2, 0, 0, 3, 0, 0, 0, 0])
	check(pressed_up.get("direction_y") == -1 and pressed_up.get("direction_x") == 0,
		"a newly pressed up beats a held right")

	# Same-frame new presses resolve right > left > down > up.
	check(resolve([0, 0, 0, 2, 0, 0, 2, 0]).get("direction_x") == 1,
		"same-frame right beats left")
	check(resolve([0, 0, 2, 2, 0, 0, 0, 0]).get("direction_x") == 1,
		"same-frame left and right resolve to right (the last override wins)")
	check(resolve([0, 2, 0, 2, 0, 0, 0, 0]).get("direction_x") == 1,
		"same-frame right beats down")
	check(resolve([2, 0, 0, 2, 0, 0, 0, 0]).get("direction_x") == 1,
		"same-frame right beats up")
	check(resolve([0, 2, 2, 0, 0, 0, 0, 0]).get("direction_x") == -1,
		"same-frame left beats down")
	check(resolve([2, 2, 0, 0, 0, 0, 0, 0]).get("direction_y") == 1,
		"same-frame down beats up")

	# Opposing held keys cancel through the neutral-axis path.
	var cancel: Dictionary = resolve([0, 3, 0, 3, 0, 0, 0, 0])
	check(cancel.get("direction_x") == 0 and cancel.get("direction_y") == 0,
		"opposing held keys cancel")

	# Alias slots feed the same logical directions.
	check(resolve([0, 0, 0, 0, 2, 0, 0, 0]).get("direction_y") == -1,
		"the alias up slot resolves like the primary")
	check(resolve([0, 0, 0, 0, 0, 0, 0, 3]).get("direction_x") == 1,
		"the alias right slot resolves like the primary")

	# The isometric conversion: cartesian screen directions become the tile
	# diagonals the input walk moves along.
	var converter = DirectionInput.new()
	var iso = converter.convert_to_isometric(0, -1)
	check(iso.get("direction_x") == 1 and iso.get("direction_y") == -1,
		"cartesian up converts to the up-right isometric diagonal")
	var iso_right = converter.convert_to_isometric(1, 0)
	check(iso_right.get("direction_x") == 1 and iso_right.get("direction_y") == 1,
		"cartesian right converts to the down-right isometric diagonal")
	var iso_zero = converter.convert_to_isometric(0, 0)
	check(iso_zero.get("direction_x") == 0 and iso_zero.get("direction_y") == 0,
		"a zero direction converts to zero")

	# The movement intent: a 16/8 step candidate through an injected probe.
	var mover = DirectionInput.new()
	var accepting = AcceptProbe.new()
	var rejecting = RejectProbe.new()
	check(mover.probe_and_prepare({}, {}, 1, 0, null).has("error"),
		"a move intent without positions is refused by name")
	check(mover.probe_and_prepare({"x": 160, "y": 112}, {"x": 864, "y": 912}, 0, 0, null).get("pending_steps") == 0,
		"a zero direction prepares no movement")
	var right_iso: Dictionary = converter.convert_to_isometric(1, 0)
	var prepared: Dictionary = mover.probe_and_prepare(
		{"x": 160, "y": 112}, {"x": 864, "y": 912},
		right_iso.get("direction_x"), right_iso.get("direction_y"), accepting)
	check(prepared.get("pending_steps") == 1 and prepared.get("delta_x") == 16
		and prepared.get("delta_y") == 8,
		"an accepted probe prepares the 16/8 isometric step: "
			+ str(prepared.get("delta_x")) + "," + str(prepared.get("delta_y")))
	var blocked: Dictionary = mover.probe_and_prepare(
		{"x": 160, "y": 112}, {"x": 864, "y": 912},
		right_iso.get("direction_x"), right_iso.get("direction_y"), rejecting)
	check(blocked.get("pending_steps") == 0,
		"a rejected probe prepares no movement")
	var up_iso: Dictionary = converter.convert_to_isometric(0, -1)
	var blocked_up: Dictionary = mover.probe_and_prepare(
		{"x": 160, "y": 112}, {"x": 864, "y": 912},
		up_iso.get("direction_x"), up_iso.get("direction_y"), rejecting)
	check(blocked_up.get("pending_steps") == 0,
		"a rejected probe with a converted diagonal prepares no movement")

	# Malformed tables are refused by name.
	var input = DirectionInput.new()
	check(input.resolve([0, 0, 0], [0, 1, 2, 3, 4, 5, 6, 7]).has("error"),
		"a short key-state table is refused by name")
	check(input.resolve([0, 0, 0, 0, 0, 0, 0, 0], [0, 1, 2, 3]).has("error"),
		"a short logical map is refused by name")

	output = {"suite": "test_pal98_direction_input", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
