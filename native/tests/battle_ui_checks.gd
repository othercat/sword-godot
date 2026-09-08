# SPDX-License-Identifier: MIT
extends RefCounted
const Ui = preload("res://src/native_battle_ui.gd")
const Classic = preload("res://src/native_classic_battle.gd")
const Command = preload("res://src/native_classic_command_button.gd")

static func close_color(a: Color, b: Color) -> bool:
	return absf(a.r-b.r)<.015 and absf(a.g-b.g)<.015 and absf(a.b-b.b)<.015

static func exercise(host, app) -> void:
	var session = app.session; var hud = app.dream_hud
	var state: Dictionary = session.state.duplicate(true)
	var geometry: Dictionary = app.battle_view.displayed_frames.duplicate(true)
	host.check(hud.skin.size() == 26,"26 authored UI textures bound in real HUD")
	var slots: Array = ["panel","slash"]
	for channel in ["hp","mp"]:
		for i in range(10): slots.append("digit."+channel+"."+str(i))
	for symbol in ["attack","skills","cooperative","misc"]: slots.append("command."+symbol+".normal")
	for slot in slots: host.check(hud.skin.has(slot),"declared UI slot reaches HUD: "+slot)
	await RenderingServer.frame_post_draw
	var image: Image = host.root.get_texture().get_image()
	for i in range(state.active_party.size()):
		var id: String = state.active_party[i]; var card: Dictionary = hud.cards[id]
		host.check(card.origin == Classic.dream_status_origin(i,5),"source HUD origin retained "+str(i))
		var offset = Vector2(40,1)
		var point: Vector2 = hud.get_global_transform_with_canvas() * (card.origin+offset+Vector2(.5,.5))
		var expected: Color = hud.skin.panel.get_image().get_pixelv(Vector2i(offset))
		host.check(close_color(image.get_pixelv(Vector2i(point)),expected),"panel PNG visible in composed viewport "+str(i))
	for button in hud.commands.get_children():
		host.check(button.get_rect() == Classic.dream_command_rect(button.symbol,5),"unchanged command hitbox "+button.symbol)
		host.check(button.skin.size() == 26,"command uses selected encounter skin "+button.symbol)
		host.check(button.disabled == (button.symbol == "cooperative"),"retained command availability "+button.symbol)
	image.save_png(host.output.path_join("source-ui-battle.png"))
	# Rendering checks use an isolated real Button to exercise all authored states.
	var button = Command.new(); button.symbol = "attack"; button.reference_size = 30
	button.position = Vector2(8,8); button.size = Vector2(30,30); button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colors = {"normal":Color("e34741"),"focus":Color("45ba62"),"disabled":Color("4476d8")}
	for key in colors:
		var source = Image.create(4,4,false,Image.FORMAT_RGBA8); source.fill(colors[key])
		button.skin["command.attack."+key] = ImageTexture.create_from_image(source)
	host.root.add_child(button)
	for key in ["normal","focus","disabled"]:
		button.disabled = key == "disabled"
		if key == "focus": button.grab_focus()
		else: button.release_focus()
		button.queue_redraw(); await host.settle(); await RenderingServer.frame_post_draw
		host.check(button.skin_state() == key,"actual Button selects "+key)
		host.check(close_color(host.root.get_texture().get_image().get_pixel(20,20),colors[key]),"authored state PNG drawn without tint "+key)
	button.skin.erase("command.attack.disabled"); button.queue_redraw(); await host.settle(); await RenderingServer.frame_post_draw
	host.check(close_color(host.root.get_texture().get_image().get_pixel(20,20),colors.normal*Color(.45,.45,.45)),"missing disabled state uses documented dim fallback")
	button.queue_free(); await host.settle()
	# Restore normal controls after the independent focus probe.
	app._refresh(); await host.settle()
	host.check(session.state == state,"skin focus and rendering never advance authority")
	host.check(app.battle_view.displayed_frames == geometry,"skin leaves actor projection unchanged")
