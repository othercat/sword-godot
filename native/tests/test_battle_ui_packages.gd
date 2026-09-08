# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not spec is Array or spec.size() < 2: quit(2); return
	var checks: Array = []; var failed: int = 0
	for row in spec:
		var package = Package.new(); var accepted: bool = package.load_package(row.path)
		var ok: bool = accepted == row.accepted and (accepted or not package.error.is_empty())
		checks.append({"name":row.name,"passed":ok,"error":package.error})
		if not ok: failed += 1
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"\t"))
	print("UI package checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
