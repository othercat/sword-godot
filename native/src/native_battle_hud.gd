# SPDX-License-Identifier: MIT
extends HBoxContainer
## Bottom party cards use the same disposable snapshot as the battle sprites.
const Classic = preload("res://src/native_classic_battle.gd")
const Progression = preload("res://src/native_progression.gd")
var cards: Dictionary = {}
var _identity: Array = []
var _package

func bind(view) -> void:
	var battle: Dictionary = view.display_battle()
	var ids: Array = battle.get("party",[])
	if _identity != ids or _package != view.session.package:
		for child in get_children(): remove_child(child); child.queue_free()
		cards.clear(); _identity = ids.duplicate(); _package = view.session.package
		for id in ids:
			var panel = PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var row = HBoxContainer.new(); panel.add_child(row); row.add_theme_constant_override("separation",6)
			var face = TextureRect.new(); face.custom_minimum_size = Vector2(52,64)
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(face)
			var text = Label.new(); text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.clip_text = true; text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			text.add_theme_font_size_override("font_size",15); row.add_child(text)
			add_child(panel); cards[id] = {"panel":panel,"face":face,"text":text}
	var active: String = view.presentation.current().get("actor_id","") if view.playing() else (str(ids[battle.turn]) if not ids.is_empty() else "")
	for id in ids:
		var actor: Dictionary = view.presentation.actors[id] if view.playing() else view.session.entity(id)
		var definition: Dictionary = _package.index.actor_definitions[actor.definition_id]
		var stats: Dictionary = Progression.stats(_package,actor)
		var portrait: Dictionary = Classic.portrait(_package.world,actor.definition_id)
		var card: Dictionary = cards[id]
		card.face.texture = null if portrait.is_empty() else _package.textures[portrait.asset_id]
		card.face.visible = not portrait.is_empty()
		card.face.modulate = Color(.4,.4,.4,1) if actor.hp == 0 else Color.WHITE
		card.text.text = "%s\n气血 %d/%d\n真气 %d/%d" % [definition.display_name,actor.hp,stats.max_hp,actor.mp,stats.max_mp]
		card.panel.tooltip_text = card.text.text
		var style = StyleBoxFlat.new(); style.bg_color = Color("132a2b")
		style.border_color = Color("ead296") if id == active else Color("467775")
		style.set_border_width_all(2); style.set_content_margin_all(7)
		card.panel.add_theme_stylebox_override("panel",style)
		card["instance_id"] = id; card["hp"] = actor.hp; card["mp"] = actor.mp
		card["portrait_asset"] = portrait.get("asset_id","")

func clear() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	cards.clear(); _identity.clear(); _package = null
