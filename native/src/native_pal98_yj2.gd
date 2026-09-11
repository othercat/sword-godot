# SPDX-License-Identifier: MIT
extends RefCounted
## Portable bounded decoder from the documented YJ2 byte-stream grammar.
## No original binary, DLL, parent-project codec or .NET dependency.
const MAX_INPUT = 16777216
const MAX_OUTPUT = 33554432
const ROOT = 640
const PREFIXES = [0x07, 0x0d, 0x0b, 0x03, 0x1e, 0x19, 0x15, 0x11, 0x0e, 0x09, 0x05, 0x01,
	0x3a, 0x36, 0x32, 0x2a, 0x26, 0x22, 0x1a, 0x16, 0x12, 0x0a, 0x06, 0x02,
	0x7c, 0x78, 0x74, 0x6c, 0x68, 0x64, 0x5c, 0x58, 0x54, 0x4c, 0x48, 0x44,
	0x3c, 0x38, 0x34, 0x2c, 0x28, 0x24, 0x1c, 0x18, 0x14, 0x0c, 0x08, 0x04,
	0xf0, 0xe0, 0xd0, 0xc0, 0xb0, 0xa0, 0x90, 0x80, 0x70, 0x60, 0x50, 0x40, 0x30, 0x20, 0x10, 0x00]

static func decode(bytes: PackedByteArray, maximum: int = 8388608) -> Dictionary:
	if maximum < 0 or maximum > MAX_OUTPUT: return {"error": "YJ2 output budget outside 0..32 MiB"}
	if bytes.size() < 4 or bytes.size() > MAX_INPUT: return {"error": "YJ2 encoded length outside 4 bytes..16 MiB"}
	var length: int = bytes.decode_u32(0)
	if length > maximum: return {"error": "YJ2 declared output exceeds budget"}
	var decoder = Stream.new()
	return decoder.run(bytes, length)

class Stream extends RefCounted:
	var input: PackedByteArray
	var cursor: int = 32
	var weights = PackedInt32Array()
	var symbols = PackedInt32Array()
	var parents = PackedInt32Array()
	var left = PackedInt32Array()
	var right = PackedInt32Array()
	var positions = PackedInt32Array()
	var distances: Dictionary = {}

	func _init() -> void:
		weights.resize(641); symbols.resize(641); symbols.fill(-1)
		parents.resize(641); left.resize(641); right.resize(641); positions.resize(321)
		for index in range(321):
			weights[index] = 1; symbols[index] = index; positions[index] = index
		for index in range(321, 641):
			var child: int = (index - 321) * 2
			left[index] = child; right[index] = child + 1
			parents[child] = index; parents[child + 1] = index
			weights[index] = weights[child] + weights[child + 1]
		for high in range(64):
			var length: int = 3 if high == 0 else (4 if high < 4 else (5 if high < 12 else (6 if high < 24 else (7 if high < 48 else 8))))
			distances[(length << 8) | PREFIXES[high]] = high

	func bit() -> int:
		if cursor >= input.size() * 8: return -1
		var result: int = (input[cursor >> 3] >> (cursor & 7)) & 1
		cursor += 1; return result

	func rebind(index: int) -> void:
		if symbols[index] >= 0: positions[symbols[index]] = index
		else: parents[left[index]] = index; parents[right[index]] = index

	func increment(symbol: int) -> void:
		var index: int = positions[symbol]
		while true:
			weights[index] += 1
			if index == ROOT: return
			var last: int = index
			while last < ROOT and weights[last + 1] < weights[index]: last += 1
			if last != index:
				var old_weight: int = weights[index]; weights[index] = weights[last]; weights[last] = old_weight
				var old_symbol: int = symbols[index]; symbols[index] = symbols[last]; symbols[last] = old_symbol
				var old_left: int = left[index]; left[index] = left[last]; left[last] = old_left
				var old_right: int = right[index]; right[index] = right[last]; right[last] = old_right
				rebind(index); rebind(last); index = last
			index = parents[index]

	func run(bytes: PackedByteArray, length: int) -> Dictionary:
		input = bytes
		var output = PackedByteArray(); output.resize(length)
		var written: int = 0
		while true:
			var index: int = ROOT
			while symbols[index] < 0:
				var value: int = bit()
				if value < 0: return {"error": "YJ2 bitstream truncated in symbol", "bit_offset": cursor}
				index = left[index] if value == 0 else right[index]
			var symbol: int = symbols[index]
			if weights[ROOT] == 32768:
				for leaf in range(321):
					if weights[positions[leaf]] & 1: increment(leaf)
				for node in range(641): weights[node] >>= 1
			increment(symbol)
			if symbol < 256:
				if written == length: return {"error": "YJ2 literal exceeds declared output"}
				output[written] = symbol; written += 1; continue
			var prefix: int = 0; var high: int = -1
			for count in range(1, 9):
				var value: int = bit()
				if value < 0: return {"error": "YJ2 bitstream truncated in distance", "bit_offset": cursor}
				prefix |= value << (count - 1); high = distances.get((count << 8) | prefix, -1)
				if high >= 0: break
			if high < 0: return {"error": "YJ2 invalid distance prefix"}
			var distance: int = high * 64
			for count in range(6):
				var value: int = bit()
				if value < 0: return {"error": "YJ2 bitstream truncated in distance", "bit_offset": cursor}
				distance |= value << count
			if distance == 4095:
				if written != length: return {"error": "YJ2 terminator disagrees with declared output"}
				return {"value": output, "consumed_bits": cursor}
			var origin: int = written - distance - 1; var count: int = symbol - 253
			if origin < 0: return {"error": "YJ2 reference precedes decoded output"}
			if count > length - written: return {"error": "YJ2 match exceeds declared output"}
			for offset in range(count): output[written] = output[origin + offset]; written += 1
		return {"error": "YJ2 missing terminator"}
