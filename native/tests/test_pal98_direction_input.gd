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
