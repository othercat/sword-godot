# SPDX-License-Identifier: MIT
extends SceneTree
## N02 diagnostic: with the capability report dismissed, is the hosted scene
## frame actually visible on the formal app window, and where did the window
## host place it? Not a package smoke; scope evidence only.
const App = preload("res://src/native_app.gd")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("_run", args[0], args[1])

func _run(package_path: String, png_path: String) -> void:
	get_root().size = Vector2i(960, 640)
	var app = App.new()
	get_root().add_child(app)
	await process_frame
	app.session.set_focus(true)
	app.open_package(package_path)
	app.start_original_experiment()
	await process_frame
	# Dismiss the capability report so the hosted scene is unobstructed.
	app.admission_picker.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var out := {"message": app.message.text, "active": app.pal98 != null and app.pal98.active()}
	if app.pal98 != null and app.pal98.active():
		var host = app.pal98.host
		var view = host.frame_view
		out.pending_kind = app.pal98.pending_kind()
		out.window_size = [get_root().size.x, get_root().size.y]
		out.stage_global = [app.stage.global_position.x, app.stage.global_position.y]
		out.stage_size = [app.stage.size.x, app.stage.size.y]
		out.view_global_rect = [view.global_position.x, view.global_position.y, view.size.x, view.size.y]
		out.view_in_stage = [view.position.x, view.position.y]
		out.host_fit = host.fit
		var image: Image = host.window.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		out.save_ok = image.save_png(png_path) == OK
		# Sample the visible scene region for non-uniform content.
		var colours := {}
		for sample_x in range(280, 940, 20):
			for sample_y in range(120, 460, 20):
				var c := image.get_pixel(sample_x, sample_y)
				var key := str(int(c.r8)) + "," + str(int(c.g8)) + "," + str(int(c.b8))
				colours[key] = colours.get(key, 0) + 1
		out.distinct_colours = colours.size()
		var file = FileAccess.open(png_path + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "  ") + "\n"); file.close()
		print(JSON.stringify(out))
	quit(0)
