# SPDX-License-Identifier: MIT
extends RefCounted
## Disposable selection state. Choosing/canceling does not mutate the session.
const Skills = preload("res://src/native_skills.gd")
const Inventory = preload("res://src/native_inventory.gd")
const Effects = preload("res://src/native_battle_effects.gd")
const Statuses = preload("res://src/native_statuses.gd")
const PAGE_SIZE = 8
var mode: String = "closed"
var selected_id: String = ""
var context: String = ""
var page: int = 0
var page_count: int = 1
var item_mode: bool = false

func _init(for_items: bool = false) -> void:
	item_mode = for_items

func cancel(app) -> void:
	mode = "closed"; selected_id = ""; page = 0; app._refresh()

func sync_context(app, battle: Dictionary, actor: Dictionary) -> void:
	var key: String = str(app.session.state.timeline_epoch) + ":" + battle.execution_id + ":" + str(battle.step) + ":" + actor.instance_id
	if key != context:
		context = key; mode = "closed"; selected_id = ""; page = 0

func render(app, battle: Dictionary, actor: Dictionary) -> void:
	sync_context(app, battle, actor)
	var ids: Array = app.session.package.world.get("item_definitions", []).map(func(i): return i.id) if item_mode else app.session.package.index.actor_definitions[actor.definition_id].get("skill_ids", [])
	if mode == "closed":
		if not ids.is_empty():
			var button = app._button(app.options, "物品" if item_mode else "技能", _open.bind(app))
			button.disabled = not item_mode and not Statuses.blocking(app.session.package, app.session.state, actor.instance_id, "block_skills").is_empty()
			if button.disabled: button.tooltip_text = "当前状态下不能施放技能。"
		return
	_clear(app.options); _clear(app.target_pages); app.target_pages.visible = false
	app.options.columns = 2
	if mode in ["skills", "items"]:
		app.dialogue_text.text = "选择物品 · 数量在确认后扣除" if item_mode else "选择技能 · 真气 %d" % actor.mp
		_pages(app, ids.size())
		for i in range(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, ids.size())):
			var skill: Dictionary = _definition(app, ids[i]); var use = _use(skill)
			var label: String = "%s · 数量%d" % [skill.display_name, Inventory.count(app.session.state, skill.id)] if item_mode else "%s · 真气%d" % [skill.display_name, skill.mp_cost]
			var button = app._button(app.options, label, _select.bind(app, ids[i]))
			button.tooltip_text = description(skill)
			button.disabled = use == null or (Inventory.count(app.session.state, skill.id) < 1 if item_mode else actor.mp < skill.mp_cost or not Statuses.blocking(app.session.package, app.session.state, actor.instance_id, "block_skills").is_empty()) or (use != null and Effects.eligible(app.session.state, use).is_empty())
	else:
		var skill: Dictionary = _definition(app, selected_id); var use: Dictionary = _use(skill)
		var eligible: Array = Effects.eligible(app.session.state, use)
		app.dialogue_text.text = skill.display_name + " · " + description(skill)
		if use.target_mode == "all":
			var button = app._button(app.options, ("用于全部符合条件的目标（%d）" if item_mode else "施放于全部符合条件的目标（%d）") % eligible.size(), commit.bind(app, selected_id, "", context))
			button.disabled = eligible.is_empty()
			app._bind_battle_target(button,eligible.map(func(row): return row.instance_id),("item:" if item_mode else "skill:")+selected_id)
		else:
			var rows: Array = battle.enemies if use.target_side == "enemy" else battle.party.map(func(id): return app.session.entity(id))
			_pages(app, rows.size())
			if use.target_side == "enemy": app.battle_view.enemy_page = page; app.battle_view.queue_redraw()
			for i in range(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, rows.size())):
				var target: Dictionary = rows[i]; var definition: Dictionary = app.session.package.index.actor_definitions[target.definition_id]
				var button = app._button(app.options, "%d · %s · 气血%d" % [i + 1, definition.display_name, target.hp], commit.bind(app, selected_id, target.instance_id, context))
				button.disabled = not eligible.any(func(a): return a.instance_id == target.instance_id)
				button.tooltip_text = app._battle_target_detail(target)
				app._bind_battle_target(button,[target.instance_id],("item:" if item_mode else "skill:")+selected_id)
	app._button(app.options, "取消", cancel.bind(app))

func _open(app) -> void:
	mode = "items" if item_mode else "skills"; page = 0; app._refresh()

func _select(app, id: String) -> void:
	mode = "targets"; selected_id = id; page = 0; app._refresh()

func commit(app, id: String, target: String, expected_context: String) -> void:
	if app.battle_view.playing(): return
	if not app.session.battle_open(): return
	var battle: Dictionary = app.session.state.extensions[Effects.KEY]
	sync_context(app, battle, app.session.entity(battle.party[battle.turn]))
	if mode != "targets" or expected_context != context or id != selected_id: return
	var ok: bool = app.session.battle_command("item", target, "", id) if item_mode else app.session.battle_command("skill", target, id)
	if ok: app.message.text = ""
	else: app.message.text = app.session.error

func _pages(app, count: int) -> void:
	page_count = maxi(1, ceili(count / float(PAGE_SIZE))); page = clampi(page, 0, page_count - 1)
	if page_count <= 1: return
	app.target_pages.visible = true
	app._button(app.target_pages, "上一组", _page.bind(app, -1)).disabled = page == 0
	var label = Label.new(); label.text = "%d / %d" % [page + 1, page_count]; app.target_pages.add_child(label)
	app._button(app.target_pages, "下一组", _page.bind(app, 1)).disabled = page == page_count - 1

func _page(app, delta: int) -> void:
	page = clampi(page + delta, 0, page_count - 1); app._refresh()

func _definition(app, id: String) -> Dictionary:
	return Inventory.definition(app.session.package, id) if item_mode else Skills.definition(app.session.package, id)

func _use(definition: Dictionary) -> Variant:
	return definition.battle_use if item_mode else definition

func description(definition: Dictionary) -> String:
	var use = _use(definition)
	if use == null: return "不能在战斗中使用"
	var side: String = "敌方" if use.target_side == "enemy" else "我方"
	var scope: String = "单体" if use.target_mode == "single" else "全体"
	var life: String = "存活" if use.target_life == "living" else "死亡"
	var cost: String = ("消耗一件" if definition.consumable else "使用后保留") if item_mode else "消耗真气%d" % definition.mp_cost
	return "%s%s%s目标 · %s" % [side, life, scope, cost]

static func _clear(control) -> void:
	for child in control.get_children(): control.remove_child(child); child.queue_free()
