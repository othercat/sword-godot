# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Provide one Native package path")
		quit(2)
		return
	var package = Package.new()
	if not package.load_package(args[0]):
		push_error(package.error)
		quit(1)
		return
	print(JSON.stringify({"loaded": true, "package_id": package.world.package_id, "content_lock": package.content_lock, "actors": package.world.entities.size(), "party": package.world.active_party.size(), "textures_decoded": package.textures.size(), "project_root": ProjectSettings.globalize_path("res://"), "legacy_data_present": DirAccess.dir_exists_absolute("res://Data") or FileAccess.file_exists("res://objects_dos.bin")}))
	quit(0)
