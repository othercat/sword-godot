# SPDX-License-Identifier: MIT
extends Control
const Sampling = preload("res://src/native_sampling.gd")
const DrawLayer = preload("res://src/native_draw_layer.gd")
## One reference canvas for status panels and command controls. Read-only view.
const Classic = preload("res://src/native_classic_battle.gd")
const Progression = preload("res://src/native_progression.gd")
const BattleUi = preload("res://src/native_battle_ui.gd")
var skin: Dictionary = {}
var commands = Control.new()
var cards: Dictionary = {}
var active_id: String = ""
var _view
var portrait_layer: Control
var foreground_layer: Control

func _init() -> void:
	# This reference layout uses pixel-art panels and glyphs. Linear sampling
	# changes their indexed source colors and blends transparent icon edges.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Classic.SIZE; clip_contents = true; mouse_filter = Control.MOUSE_FILTER_IGNORE
	commands.size = Classic.SIZE; commands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_layer = DrawLayer.new(func(canvas): _paint(canvas, "portrait"))
	foreground_layer = DrawLayer.new(func(canvas): _paint(canvas, "foreground"))
	add_child(portrait_layer); add_child(foreground_layer)
	add_child(commands)

func bind(view) -> void:
	_view = view; cards.clear()
	var content: Dictionary = view.session.package.world
	texture_filter = Sampling.resolve(content, "hud", CanvasItem.TEXTURE_FILTER_NEAREST)
	portrait_layer.texture_filter = Sampling.resolve(content, "portrait", CanvasItem.TEXTURE_FILTER_NEAREST)
	commands.texture_filter = Sampling.resolve(content, "command_ui", CanvasItem.TEXTURE_FILTER_NEAREST)
	var battle: Dictionary = view.display_battle()
	skin = BattleUi.for_encounter(view.session.package,battle.encounter_id)
	var ids: Array = battle.get("party",[])
	active_id = str(ids[battle.turn]) if not ids.is_empty() else ""
	for i in range(ids.size()):
		var id: String = ids[i]
		var actor: Dictionary = view.presentation.actors[id] if view.playing() else view.session.entity(id)
		var definition: Dictionary = view.session.package.index.actor_definitions[actor.definition_id]
		var portrait: Dictionary = Classic.portrait(view.session.package.world,actor.definition_id)
		var origin: Vector2 = Classic.dream_status_origin(i,ids.size())
		cards[id] = {"instance_id":id,"hp":actor.hp,"mp":actor.mp,"stats":Progression.stats(view.session.package,actor),
			"name":definition.display_name,"origin":origin,"panel_rect":Rect2(origin,Vector2(75,35)),
			"face_rect":Rect2(origin+Vector2(-2,-4),Vector2(36,35)),"portrait_asset":portrait.get("asset_id","")}
	queue_redraw()

func _number(canvas: CanvasItem, value: int, at: Vector2, right: bool, tint: Color, channel: String) -> void:
	var text: String = str(value)
	if right: at.x += 30-text.length()*6
	var font: Font = get_theme_font("font")
	for digit in text:
		var texture: Texture2D = skin.get("digit."+channel+"."+digit)
		if texture != null: canvas.draw_texture_rect(texture,Rect2(at,Vector2(6,8)),false)
		else: canvas.draw_string(font,at+Vector2(0,7),digit,HORIZONTAL_ALIGNMENT_LEFT,6,8,tint)
		at.x += 6

func _draw() -> void:
	portrait_layer.queue_redraw(); foreground_layer.queue_redraw()
	_paint(self, "panel")

func _paint(canvas: CanvasItem, part: String) -> void:
	if _view == null: return
	var font: Font = get_theme_font("font")
	for id in cards:
		var card: Dictionary = cards[id]; var p: Vector2 = card.origin
		if part == "panel":
			if skin.has("panel"): canvas.draw_texture_rect(skin.panel,card.panel_rect,false)
			else: canvas.draw_style_box(_panel(id == active_id),card.panel_rect)
		if part == "portrait" and not card.portrait_asset.is_empty():
			var texture: Texture2D = _view.session.package.textures[card.portrait_asset]
			var extent: Vector2 = texture.get_size()*minf(36.0/texture.get_width(),35.0/texture.get_height())
			canvas.draw_texture_rect(texture,Rect2(card.face_rect.position,extent),false,Color(.4,.4,.4) if card.hp == 0 else Color.WHITE)
		elif part == "portrait":
			canvas.draw_string(font,p+Vector2(0,14),card.name.left(2),HORIZONTAL_ALIGNMENT_LEFT,32,10,Color("9dbbb3"))
		if part != "foreground": continue
		_number(canvas, card.hp,p+Vector2(19,5),true,Color("ead28e"),"hp"); _number(canvas, card.stats.max_hp,p+Vector2(49,10),false,Color("ead28e"),"hp")
		_number(canvas, card.mp,p+Vector2(19,21),true,Color("7dd3d2"),"mp"); _number(canvas, card.stats.max_mp,p+Vector2(49,26),false,Color("7dd3d2"),"mp")
		for at in [Vector2(47,6),Vector2(47,22)]:
			if skin.has("slash"): canvas.draw_texture_rect(skin.slash,Rect2(p+at,Vector2(5,8)),false)
			else: canvas.draw_line(p+at+Vector2(4,0),p+at+Vector2(0,7),Color("8cb8b0"),1)

static func _panel(active: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new(); style.bg_color = Color("092827")
	style.border_color = Color("ead296") if active else Color("447c73")
	style.set_border_width_all(1); style.set_corner_radius_all(2)
	return style

func clear_commands() -> void:
	for child in commands.get_children(): commands.remove_child(child); child.queue_free()

func clear() -> void:
	clear_commands(); cards.clear(); skin.clear(); _view = null; active_id = ""; queue_redraw()
