# SPDX-License-Identifier: MIT
extends SceneTree
## Original G0150 uses WORD indices; PALOLD helpers consume byte lengths.
## Hard-coded byte sentinels here are independent of the implementation's
## layout constants. Host receipts are synthetic and do not prove display.
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _state(night: bool) -> Dictionary:
	var bytes: PackedByteArray = PackedByteArray(); bytes.resize(3072)
	for index in range(768):
		bytes[index] = index % 64
		bytes[768 + index] = 63 - index % 64
		bytes[1536 + index] = 99
		bytes[2304 + index] = 111
	return {"globals": {"day_night_word": 384 if night else 0, "fade_gate_word": 7},
		"palette_bytes": bytes}

func _one_step(from_byte: int, to_byte: int) -> int:
	return from_byte + (1 if from_byte < to_byte else -1 if from_byte > to_byte else 0)

func _request(opcode: int, a0: int, a1: int, a2: int) -> Dictionary:
	return {"words": [opcode, a0, a1, a2], "entry": 1, "event_id": 0}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): quit(2); return
	var commands = Commands.new(); commands.load_source(package.pal98_sources)
	for night in [false, true]:
		var state: Dictionary = _state(night)
		var original: PackedByteArray = state.palette_bytes.duplicate()
		var result: Dictionary = commands.consume(state, _request(0x0080, 5, 0, 0))
		check(not result.has("error"), "0080 accepts separate full 256-color day/night windows: night=" + str(night))
		if result.has("error"): continue
		check(state.palette_bytes.slice(0, 1536) == original.slice(0, 1536),
			"0080 preserves every day/night source byte: night=" + str(night))
		var expected: PackedByteArray = PackedByteArray()
		for index in range(768):
			expected.append(_one_step(original[(768 if night else 0) + index], original[(0 if night else 768) + index]))
		check(result.requests[0].get("byte_offset") == 1536 and result.requests[0].offset == 768
			and result.requests[0].bytes == expected,
			"0080 work install scales WORD index 768 to byte 1536 and advances all RGB bytes: night=" + str(night))
		check(state.palette_bytes.slice(2304, 3072) == original.slice(2304, 3072),
			"0080 does not touch the separate color target: night=" + str(night))
	for swapped in [0, 1]:
		var state: Dictionary = _state(true)
		var original: PackedByteArray = state.palette_bytes.duplicate()
		var result: Dictionary = commands.consume(state, _request(0x008C, 255, 3, swapped))
		check(not result.has("error"), "008C admits WORD-indexed night source and color255: swapped=" + str(swapped))
		if result.has("error"): continue
		var expected: PackedByteArray = PackedByteArray()
		for index in range(768):
			var source: int = original[768 + index]
			var color: int = original[768 + 765 + index % 3]
			expected.append(_one_step(source, color) if swapped == 0 else _one_step(color, source))
		check(result.requests[0].bytes == expected and result.requests[0].get("byte_offset") == (2304 if swapped == 0 else 1536)
			and result.requests[0].offset == (1152 if swapped == 0 else 768),
			"008C samples the last complete RGB triple and installs the correct full block: swapped=" + str(swapped))
		check(state.palette_bytes.slice(0, 1536) == original.slice(0, 1536),
			"008C preserves all 1536 source bytes: swapped=" + str(swapped))
		var reference: PackedByteArray = PackedByteArray()
		for index in range(768): reference.append(original[768 + 765 + index % 3] if swapped == 0 else original[768 + index])
		check(state.palette_bytes.slice(1536 if swapped == 0 else 2304, 2304 if swapped == 0 else 3072) == reference,
			"008C leaves the complete reference block unchanged: swapped=" + str(swapped))
	for opcode in [0x0080, 0x008C]:
		var state: Dictionary = _state(false); state.palette_bytes.resize(1920)
		var before: Dictionary = state.duplicate(true)
		var result: Dictionary = commands.consume(state, _request(opcode, 0, 0, 0))
		check(result.get("diagnostic", {}).get("code") == "palette_backing" and state == before,
			"old byte-indexed 1920-byte backing is refused without candidate writes: " + str(opcode))
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"suite": "test_pal98_palette_layout", "checks": checks,
		"passed": checks.size() - failed, "failed": failed}, "  ") + "\n"); file.close()
	print("Palette layout: %d/%d" % [checks.size() - failed, checks.size()]); quit(1 if failed else 0)
