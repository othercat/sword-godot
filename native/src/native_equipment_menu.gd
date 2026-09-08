# SPDX-License-Identifier: MIT
extends AcceptDialog
const Equipment = preload("res://src/native_equipment.gd")
const Inventory = preload("res://src/native_inventory.gd")
const Growth = preload("res://src/native_progression.gd")
var host
var body: VBoxContainer
var scroll: ScrollContainer
var actor_id: String = ""
var notice: String = ""

func setup(app) -> void:
	host = app; title = "伙伴装备"; min_size = Vector2i(720, 450)
	scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(680, 360); add_child(scroll)
	body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 12); scroll.add_child(body)
	get_ok_button().text = "返回游戏"

func open() -> void:
	if host.session.state.is_empty() or host.session.battle_open() or host.battle_view.playing() or host.session.paused: return
	if not Equipment.used(host.session.package.world): return
	rebuild(); popup_centered(Vector2i(800, 610))

func _label(text: String) -> Label:
	var label = Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func rebuild() -> void:
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	scroll.set_deferred("scroll_vertical", 0)
	var session = host.session; var package = session.package
	var actors: Array = session.state.entities.filter(func(a): return a.instance_id in session.state.roster and a.components.has(Equipment.KEY))
	if actors.is_empty(): body.add_child(_label("队伍与候补中尚无可装备的伙伴。")); return
	if not actors.any(func(a): return a.instance_id == actor_id): actor_id = actors[0].instance_id
	var chooser = OptionButton.new(); chooser.name = "EquipmentActor"; body.add_child(chooser)
	for actor in actors:
		var active_index: int = session.state.active_party.find(actor.instance_id)
		var position: String = "同行 %d" % (active_index + 1) if active_index >= 0 else "候补 %d" % (session.state.roster.find(actor.instance_id) + 1)
		chooser.add_item(package.index.actor_definitions[actor.definition_id].display_name + " · " + position)
		chooser.set_item_metadata(chooser.item_count - 1, actor.instance_id)
		if actor.instance_id == actor_id: chooser.select(chooser.item_count - 1)
	chooser.item_selected.connect(func(i): actor_id = chooser.get_item_metadata(i); notice = ""; rebuild())
	var actor: Dictionary = session.entity(actor_id); var before: Dictionary = Growth.stats(package, actor)
	body.add_child(_label("气血 %d/%d · 真气 %d/%d · 攻击 %d · 防御 %d" % [actor.hp, before.max_hp, actor.mp, before.max_mp, before.attack, before.defense]))
	body.add_child(_label("装备从背包取出，卸下后退回背包。更换不会补满气血或真气。"))
	if not notice.is_empty():
		var result = _label(notice); result.name = "EquipmentNotice"; body.add_child(result)
	var gear: Dictionary = Equipment.items(package.world); var catalog: Dictionary = Inventory.definitions(package.world)
	for slot in Equipment.definition(package.world).slots:
		var current: String = ""
		for row in Equipment.loadout(actor):
			if row.slot_id == slot.id: current = row.item_id
		var line = HBoxContainer.new(); body.add_child(line)
		var name_label = _label(slot.display_name); name_label.custom_minimum_size.x = 80; line.add_child(name_label)
		var choices = OptionButton.new(); choices.name = "EquipmentSlot" + str(body.get_child_count()); choices.set_meta("slot_id", slot.id)
		choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL; choices.add_item("无装备"); choices.set_item_metadata(0, ""); line.add_child(choices)
		for item in gear.values():
			if item.slot_id != slot.id or not Equipment.eligible(item, actor.definition_id): continue
			var count: int = Inventory.count(session.state, item.item_id)
			if count == 0 and item.item_id != current: continue
			choices.add_item("%s · 背包 %d%s" % [catalog[item.item_id].display_name, count, " · 已装备" if current == item.item_id else ""])
			choices.set_item_metadata(choices.item_count - 1, item.item_id)
			if current == item.item_id: choices.select(choices.item_count - 1)
		var apply = Button.new(); apply.text = "更换"; apply.set_meta("slot_id", slot.id); line.add_child(apply)
		var preview = _label(""); body.add_child(preview)
		var update = func(_i = 0):
			var selected: String = choices.get_item_metadata(choices.selected)
			apply.disabled = selected == current
			var candidate: Dictionary = actor.duplicate(true); var plan: Dictionary = Equipment.plan(package, candidate, slot.id, selected)
			preview.visible = not plan.has("error")
			if plan.has("error"): preview.text = ""; return
			candidate.components[Equipment.KEY].loadout = plan.loadout
			var after: Dictionary = Growth.stats(package, candidate)
			preview.text = "上限 气血 %d→%d · 真气 %d→%d · 攻击 %d→%d · 防御 %d→%d" % [before.max_hp, after.max_hp, before.max_mp, after.max_mp, before.attack, after.attack, before.defense, after.defense]
		choices.item_selected.connect(update); update.call()
		apply.pressed.connect(func():
			var selected: String = choices.get_item_metadata(choices.selected)
			# Close synchronously so the session's ordinary modal guard still applies.
			hide()
			notice = "装备已更新。" if session.change_equipment(actor_id, slot.id, selected) else session.error
			open())
