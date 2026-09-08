# SPDX-License-Identifier: MIT
extends RefCounted
## Disposable selection state. Choosing/canceling does not mutate the session.
const Skills = preload("res://src/native_skills.gd")
const PAGE_SIZE = 8
var mode: String = "closed"
var selected_id: String = ""
var context: String = ""
var page: int = 0
var page_count: int = 1

func cancel(app) -> void:
	mode = "closed"; selected_id = ""; page = 0; app._refresh()

func render(app, battle: Dictionary, actor: Dictionary) -> void:
	var key: String = str(app.session.state.timeline_epoch) + ":" + battle.execution_id + ":" + str(battle.step) + ":" + actor.instance_id
	if key != context:
		context = key; mode = "closed"; selected_id = ""; page = 0
	var ids: Array = app.session.package.index.actor_definitions[actor.definition_id].get("skill_ids", [])
	if mode == "closed":
		if not ids.is_empty(): app._button(app.options, "技能", _open.bind(app))
		return
	_clear(app.options); _clear(app.target_pages); app.target_pages.visible = false
	app.options.columns = 2
	if mode == "skills":
		app.dialogue_text.text = "选择技能 · 真气 %d" % actor.mp
		_pages(app, ids.size())
		for i in range(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, ids.size())):
			var skill: Dictionary = Skills.definition(app.session.package, ids[i])
			var button = app._button(app.options, "%s · 真气%d" % [skill.display_name, skill.mp_cost], _select.bind(app, ids[i]))
			button.tooltip_text = description(skill)
			button.disabled = actor.mp < skill.mp_cost or Skills.eligible(app.session.state, skill).is_empty()
	else:
		var skill: Dictionary = Skills.definition(app.session.package, selected_id)
		var eligible: Array = Skills.eligible(app.session.state, skill)
		app.dialogue_text.text = skill.display_name + " · " + description(skill)
		if skill.target_mode == "all":
			app._button(app.options, "施放于全部符合条件的目标（%d）" % eligible.size(), commit.bind(app, selected_id, "", context)).disabled = eligible.is_empty()
		else:
			var rows: Array = battle.enemies if skill.target_side == "enemy" else battle.party.map(func(id): return app.session.entity(id))
			_pages(app, rows.size())
			if skill.target_side == "enemy": app.battle_view.enemy_page = page; app.battle_view.queue_redraw()
			for i in range(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, rows.size())):
				var target: Dictionary = rows[i]; var definition: Dictionary = app.session.package.index.actor_definitions[target.definition_id]
				var button = app._button(app.options, "%d · %s · 气血%d" % [i + 1, definition.display_name, target.hp], commit.bind(app, selected_id, target.instance_id, context))
				button.disabled = not eligible.any(func(a): return a.instance_id == target.instance_id)
	app._button(app.options, "取消", cancel.bind(app))

func _open(app) -> void:
	mode = "skills"; page = 0; app._refresh()

func _select(app, id: String) -> void:
	mode = "targets"; selected_id = id; page = 0; app._refresh()

func commit(app, id: String, target: String, expected_context: String) -> void:
	if mode != "targets" or expected_context != context or id != selected_id: return
	if app.session.battle_command("skill", target, id): app.message.text = ""
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

static func description(skill: Dictionary) -> String:
	var side: String = "敌方" if skill.target_side == "enemy" else "我方"
	var scope: String = "单体" if skill.target_mode == "single" else "全体"
	var life: String = "存活" if skill.target_life == "living" else "死亡"
	return "%s%s%s目标 · 消耗真气%d" % [side, life, scope, skill.mp_cost]

static func _clear(control) -> void:
	for child in control.get_children(): control.remove_child(child); child.queue_free()
