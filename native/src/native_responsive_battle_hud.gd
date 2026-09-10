# SPDX-License-Identifier: MIT
extends Control
const Sampling = preload("res://src/native_sampling.gd")
const DrawLayer = preload("res://src/native_draw_layer.gd")
## Render one supported authored widget template from the displayed actor snapshot.
const Config = preload("res://src/native_battle_hud_config.gd")
const CommandPanel = preload("res://src/native_command_panel.gd")
const Progression = preload("res://src/native_progression.gd")
var commands = Control.new()
var cards: Dictionary = {}
var skin: Dictionary = {}
var active_id: String = ""
var profile: Dictionary = {}
var boxes: Dictionary = {}
var command_profile: Dictionary = {}
var _view
var portrait_layer: Control
var foreground_layer: Control

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	commands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_layer = DrawLayer.new(func(canvas): _paint(canvas, "portrait"))
	foreground_layer = DrawLayer.new(func(canvas): _paint(canvas, "foreground"))
	add_child(portrait_layer); add_child(foreground_layer)
	add_child(commands)

func fit(bounds: Vector2) -> void:
	size = bounds; commands.size = bounds
	if _view != null: bind(_view)
	for button in commands.get_children():
		var key: String = button.get_meta("battle_focus_key","")
		if boxes.get("commands",{}).has(key):
			var rect: Rect2 = boxes.commands[key]
			button.reference_size = rect.size.x; button.custom_minimum_size = rect.size
			button.position = rect.position; button.size = rect.size
			if not command_profile.is_empty(): CommandPanel.apply_button(button,command_profile,_view.session.package)

func bind(view) -> void:
	_view = view; cards.clear()
	var battle: Dictionary = view.display_battle()
	if battle.is_empty(): queue_redraw(); return
	profile = Config.for_encounter(view.session.package.world,battle.encounter_id)
	if profile.is_empty(): queue_redraw(); return
	if size.x <= 0 or size.y <= 0: queue_redraw(); return
	var ids: Array = battle.get("party",[])
	boxes = Config.geometry(profile.layout,size,ids.size(),profile.placement)
	command_profile = CommandPanel.for_encounter(view.session.package.world,battle.encounter_id)
	if not command_profile.is_empty(): boxes.commands = CommandPanel.geometry(command_profile,boxes.content).buttons
	var legacy: int = CanvasItem.TEXTURE_FILTER_NEAREST if profile.style.portrait_filter == "nearest" else CanvasItem.TEXTURE_FILTER_LINEAR
	var content: Dictionary = view.session.package.world
	texture_filter = Sampling.resolve(content, "hud", legacy)
	portrait_layer.texture_filter = Sampling.resolve(content, "portrait", legacy, profile.style.portrait_filter)
	commands.texture_filter = Sampling.resolve(content, "command_ui", legacy)
	active_id = view.presentation.current().get("actor_id","") if view.playing() else (str(ids[battle.turn]) if not ids.is_empty() else "")
	for i in range(ids.size()):
		var id: String = ids[i]
		var actor: Dictionary = view.presentation.actors[id] if view.playing() else view.session.entity(id)
		var definition: Dictionary = view.session.package.index.actor_definitions[actor.definition_id]
		var portrait: Dictionary = Config.portrait(view.session.package.world,actor.definition_id)
		var panel: Rect2 = boxes.cards[i]
		var unit: float = panel.size.y/profile.layout.card_height
		var text_origin_y: float = panel.position.y
		if not profile.placement.is_empty():
			unit = minf(unit,panel.size.x/profile.layout.min_card_width)
			text_origin_y += (panel.size.y-profile.layout.card_height*unit)/2
		var extent: float = minf(profile.style.portrait_size*unit,panel.size.x*.35)
		cards[id] = {"instance_id":id,"hp":actor.hp,"mp":actor.mp,"stats":Progression.stats(view.session.package,actor),
			"name":definition.display_name,"origin":panel.position,"panel_rect":panel,"unit":unit,"text_origin_y":text_origin_y,
			"face_rect":Rect2(panel.position+Vector2(5*unit,(panel.size.y-extent)/2),Vector2.ONE*extent),"portrait_asset":portrait.get("asset_id","")}
	queue_redraw()

func command_rect(symbol: String) -> Rect2:
	return boxes.commands[symbol]

func style_command(button) -> void:
	if not command_profile.is_empty(): CommandPanel.apply_button(button,command_profile,_view.session.package)

func _draw() -> void:
	portrait_layer.queue_redraw(); foreground_layer.queue_redraw()
	_paint(self, "panel")

func _paint(canvas: CanvasItem, part: String) -> void:
	if _view == null or profile.is_empty(): return
	var font: Font = get_theme_font("font")
	var colors: Dictionary = profile.style.colors
	for id in cards:
		var card: Dictionary = cards[id]; var panel: Rect2 = card.panel_rect; var unit: float = card.unit
		if part == "panel":
			var style = StyleBoxFlat.new(); style.bg_color = Color(colors.panel)
			style.border_color = Color(colors.active if id == active_id else colors.border)
			style.set_border_width_all(1); style.set_corner_radius_all(5)
			canvas.draw_style_box(style,panel)
		if part == "portrait" and not card.portrait_asset.is_empty():
			var texture: Texture2D = _view.session.package.textures[card.portrait_asset]
			var face: Rect2 = card.face_rect
			var extent: Vector2 = texture.get_size()*minf(face.size.x/texture.get_width(),face.size.y/texture.get_height())
			canvas.draw_texture_rect(texture,Rect2(face.get_center()-extent/2,extent),false,Color(.45,.45,.45) if card.hp == 0 else Color.WHITE)
		if part != "foreground": continue
		var left: float = card.face_rect.end.x+6*unit
		var width: float = maxf(1,panel.end.x-left-8*unit)
		var font_size: int = maxi(8,roundi(profile.style.font_size*unit))
		canvas.draw_string(font,Vector2(left,card.text_origin_y+(profile.style.font_size+3)*unit),card.name,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,Color(colors.text))
		var row: int = 0
		for entry in [["HP",card.hp,card.stats.max_hp,colors.hp],["MP",card.mp,card.stats.max_mp,colors.mp]]:
			var height: float = (profile.style.font_size-1)*unit
			var bar = Rect2(left,card.text_origin_y+(profile.style.font_size*2+row*(profile.style.font_size+4))*unit,width,height)
			canvas.draw_rect(bar,Color(colors.track))
			var ratio: float = clampf(float(entry[1])/maxf(1,float(entry[2])),0,1)
			canvas.draw_rect(Rect2(bar.position,Vector2(width*ratio,height)),Color(entry[3]))
			var text: String = "%s %d / %d" % [entry[0],entry[1],entry[2]]
			var value_size: int = maxi(7,font_size-2)
			while value_size > 7 and font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,value_size).x > width-4*unit: value_size -= 1
			var at: Vector2 = bar.position+Vector2(3*unit,(profile.style.font_size-3)*unit)
			canvas.draw_string(font,at+Vector2(0,unit),text,HORIZONTAL_ALIGNMENT_LEFT,width-4*unit,value_size,Color(colors.track))
			canvas.draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,width-4*unit,value_size,Color(colors.text))
			row += 1

func clear_commands() -> void:
	for child in commands.get_children(): commands.remove_child(child); child.queue_free()

func clear() -> void:
	clear_commands(); cards.clear(); profile.clear(); boxes.clear(); command_profile = {}; _view = null; active_id = ""; queue_redraw()
