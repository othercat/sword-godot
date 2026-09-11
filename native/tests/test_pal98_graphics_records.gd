# SPDX-License-Identifier: MIT
extends SceneTree
const Yj2 = preload("res://src/native_pal98_yj2.gd")
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const Package = preload("res://src/native_package.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var failed: int = 0
var packed: Array = []
var output: String
var totals: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3: quit(2); return
	output = args[2]
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): quit(2); return
	var reference = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not reference is Dictionary or not reference.get("packed") is Array: quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(180).timeout.connect(func(): check(false, "graphics records test watchdog expired"); finish())
	_vectors(); _images()
	var package = Package.new()
	check(package.load_package(args[0]), "ordinary author graphics package loads: " + package.error)
	if package.pal98_graphics == null: finish(); return
	var records = package.pal98_graphics.open_records()
	check(records != null, "admitted graphics opens addressed reader")
	if records == null: finish(); return
	check(records.metadata().fingerprint == reference.graphics_source.fingerprint, "independent source reference identifies same effective graphics")
	for role in reference.graphics_source.files:
		check(records.metadata().files[role].sha256 == reference.graphics_source.files[role].sha256, "reference source hash: " + role)
	var original: Dictionary = {}
	for role in ["MAP.MKF", "GOP.MKF", "MGO.MKF", "PAT.MKF"]: original[role] = Schema.digest(package.pal98_graphics.copy_bytes(role))
	var start: int = Time.get_ticks_msec()
	for row in reference.packed:
		var raw: Dictionary = records.raw_chunk(row.family, row.index)
		var result: Dictionary = records.decoded_chunk(row.family, row.index)
		var ok: bool = not result.has("error") and not raw.has("error")
		if ok: ok = Schema.digest(raw.value) == row.encoded_sha256 and result.value.size() == row.size_bytes and Schema.digest(result.value) == row.decoded_sha256
		check(ok, "original/managed/Native YJ2: %s:%d" % [row.family, row.index])
		packed.append({"family": row.family, "index": row.index, "passed": ok, "error": result.get("error", ""),
			"decoded_sha256": Schema.digest(result.value) if not result.has("error") else ""})
		if packed.size() % 50 == 0: print("YJ2 source blocks: ", packed.size(), "/", reference.packed.size()); await process_frame
	totals.yj2_milliseconds = Time.get_ticks_msec() - start
	check(packed.size() == 859, "complete locked MAP/MGO reference corpus")
	var copied: Dictionary = records.decoded_chunk("MAP.MKF", 20); var digest: String = Schema.digest(copied.value)
	copied.value[0] ^= 255; copied.source.file_sha256 = "changed"
	var reread: Dictionary = records.decoded_chunk("MAP.MKF", 20)
	check(Schema.digest(reread.value) == digest and reread.source.file_sha256 == original["MAP.MKF"], "decoded cache returns detached bytes and provenance")
	check(not records.load_source(null) and records.metadata().fingerprint == reference.graphics_source.fingerprint, "failed reader replacement keeps original snapshot")
	check(records.raw_chunk("PAT.MKF", -1).has("error") and records.raw_chunk("PAT.MKF", 4096).has("error") and records.raw_chunk("other", 0).has("error"), "addressed chunk bounds")
	check(records.decoded_chunk("GOP.MKF", 20).has("error") and records.group("MAP.MKF", 20).has("error"), "explicit codec and resource family")
	check(records.decoded_chunk("MAP.MKF", 0).has("error"), "empty MAP is preserved but not decoded as a map")
	check(records.palette(0, -1).has("error") and records.palette(0, 2).has("error"), "no inferred palette variant")
	var day: Dictionary = records.palette(0, 0); var night: Dictionary = records.palette(0, 1)
	check(not day.has("error") and not night.has("error") and day.value != night.value, "explicit day and night source variants")
	check(reference.palette_variant == "explicit-day-chunk0", "independent PNG oracle explicitly selects day variant")
	for row in reference.details:
		var rgba: Dictionary = records.rgba_frame("GOP.MKF", row.group, row.frame, 0, 0, false)
		check(not rgba.has("error") and rgba.width == row.Width and rgba.height == row.Height and Schema.digest(rgba.value) == row.rgba_sha256, "independent map20 PNG comparison: %d" % row.frame)
	var bad: Dictionary = records.frame("MGO.MKF", 571, 1)
	check(bad.has("error") and bad.byte_offset == 99396 and bad.group_size == 59516 and bad.source.file_sha256 == original["MGO.MKF"], "known source MGO571 frame1 retains addressed failure")
	var good: Dictionary = records.frame("MGO.MKF", 571, 0)
	check(not good.has("error") and good.value.width == 320 and good.value.height == 200, "bad unselected pointer leaves MGO571 frame0 readable")
	await _scan_images(records, reference)
	check(totals.has("mgo_frames"), "complete image scan reached its final boundary")
	for role in original: check(Schema.digest(package.pal98_graphics.copy_bytes(role)) == original[role], "source bytes unchanged after decode: " + role)
	finish()

func _vectors() -> void:
	for pair in [["000000007E003F", ""], ["01000000FDFC007E", "00"], ["01000000FBFD007E", "41"], ["01000000BE7E003F", "FF"], ["04000000FBFD0EEC07F801", "41414141"]]:
		var input: PackedByteArray = pair[0].hex_decode(); var before: PackedByteArray = input.duplicate()
		var result: Dictionary = Yj2.decode(input)
		check(not result.has("error") and result.value == pair[1].hex_decode() and input == before, "independent YJ2 vector " + pair[0])
	for hex in ["", "000000", "00000000", "000000007E00", "FFFFFFFF7E003F", "02000000FBFD007E", "00000000FBFD007E", "030000007E0000", "03000000FBFD0EEC07F801"]:
		check(Yj2.decode(hex.hex_decode()).has("error"), "reject malformed YJ2 " + hex)
	var padded: PackedByteArray = "04000000FBFD0EEC07F801A55A".hex_decode()
	check(Yj2.decode(padded, 3).has("error") and Yj2.decode(padded, -1).has("error") and Yj2.decode(padded, 33554433).has("error"), "YJ2 declared and caller budgets")
	check(Yj2.decode(padded, 4).value == "41414141".hex_decode() and padded.hex_encode().ends_with("a55a"), "YJ2 trailing bytes preserved")
	var input: PackedByteArray = "00000100fbfb7abdaeebbad65a6badb5aaaaaaaaaaaaaaaa244992244992244992244912555555555555555555555555555555d5ffffffffffffffffffffffffffffff7f00000000000000000000000000000080".hex_decode()
	var fill = PackedByteArray(); fill.resize(8151); fill.fill(255); input.append_array(fill); input.append_array("7F07007E".hex_decode())
	check(input.size() == 8239 and Schema.digest(input) == "ba82a89a59524522890b6aeedcb6e48cf92c4eaae46ba6605732a21251c0e2ed", "rescale vector encoded identity")
	var result: Dictionary = Yj2.decode(input, 65536)
	check(not result.has("error") and Schema.digest(result.value) == "156c38442089c1323d3e3ba549a6ac24341c47e8b6367bec4740c9b8c865826e", "three adaptive tree rescale boundaries")

func _images() -> void:
	var decoded: Dictionary = Indexed.rle("0400010001008201ffA55A".hex_decode())
	check(not decoded.has("error") and decoded.value.indices == PackedByteArray([0, 0, 0, 255]) and decoded.value.coverage == PackedByteArray([1, 0, 0, 1]) and decoded.value.tail == "A55A".hex_decode(), "RLE retains zero/255 literals, skips and opaque tail")
	var palette = PackedByteArray(); palette.resize(768); palette[0] = 63; palette[767] = 63
	var opaque: Dictionary = Indexed.rgba(decoded.value, palette, false); var transparent: Dictionary = Indexed.rgba(decoded.value, palette, true)
	check(opaque.value == "fc0000ff00000000000000000000fcff".hex_decode() and transparent.value == "fc0000ff000000000000000000000000".hex_decode(), "explicit literal255 coverage versus original putp transparency")
	for hex in ["", "0100", "00000100", "01000000", "01200100", "01000100", "0100010002ff", "020001000201"]:
		check(Indexed.rle(hex.hex_decode()).has("error"), "bounded RLE rejects " + hex)
	check(not Indexed.rle("0100010000000107".hex_decode()).has("error"), "zero-run commands still consume bounded input")
	check(Indexed.validate_palette(palette.slice(0, 767)) != "", "palette requires exactly768 bytes")
	palette[0] = 64; check(Indexed.rgba(decoded.value, palette, true).has("error"), "RGB6 channel bounds")
	var group: PackedByteArray = "030003000000010001000109".hex_decode()
	check(Indexed.frame(group, 0).value == Indexed.frame(group, 1).value, "equal frame pointers alias")
	group.encode_u16(2, 65535)
	check(not Indexed.frame(group, 0).has("error") and Indexed.frame(group, 1).has("error"), "bad unselected frame pointer is retained")
	check(Indexed.frame(group, -1).has("error") and Indexed.frame(group, 2).has("error"), "selected frame index bounds")
	check(Indexed.frame_count("01000000".hex_decode()).has("error") and Indexed.frame_count("03100000".hex_decode()).has("error"), "word directory bounds")
	var reordered: PackedByteArray = "04000a0007000000010001000107010001000108010001000109".hex_decode()
	check(Indexed.frame(reordered, 1).value.indices == PackedByteArray([9]) and Indexed.frame(reordered, 2).value.indices == PackedByteArray([8]), "reordered valid frame pointers preserve requested identity")

func _scan_images(records, reference: Dictionary) -> void:
	var images: int = 0; var pixels: int = 0; var tail: int = 0; var failures: Array = []
	var count: int = records.chunk_count("GOP.MKF").value
	for index in range(count):
		var raw: Dictionary = records.raw_chunk("GOP.MKF", index)
		if raw.value.is_empty(): continue
		var shape: Dictionary = Indexed.frame_count(raw.value)
		if shape.has("error"): failures.append({"group": index, "error": shape.error}); continue
		for frame in range(shape.value):
			var result: Dictionary = Indexed.frame(raw.value, frame)
			if result.has("error"): failures.append({"group": index, "frame": frame, "error": result.error}); continue
			images += 1; pixels += result.value.width * result.value.height; tail += result.value.tail.size()
		if index % 25 == 0: await process_frame
	check(failures.is_empty() and images == reference.images and pixels == reference.pixels and tail == reference.preserved_tail_bytes, "all GOP images match managed counts and preserved tails")
	totals.merge({"gop_images": images, "gop_pixels": pixels, "gop_tail_bytes": tail, "gop_failures": failures})
	var frames: int = 0; failures = []
	for row in reference.packed:
		if row.family != "MGO.MKF": continue
		var group: Dictionary = records.group(row.family, row.index)
		if group.has("error"): failures.append({"group": row.index, "error": group.error}); continue
		for frame in range(group.frame_count):
			var result: Dictionary = Indexed.frame(group.value, frame)
			if result.has("error"): failures.append({"group": row.index, "frame": frame, "error": result.error}); continue
			frames += 1
		if int(row.index) % 25 == 0: await process_frame
	check(frames == reference.sprite_frames and failures.size() == 1 and failures[0].group == 571 and failures[0].frame == 1, "MGO corpus matches with one retained invalid source frame")
	totals.merge({"mgo_frames": frames, "mgo_failures": failures})

func finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "packed": packed, "totals": totals,
		"original_gameplay": false, "all_source_frames_valid": false}, "\t")); file.close()
	print("PAL98 graphics records: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
