# SPDX-License-Identifier: MIT
extends RefCounted
const Keys = preload("res://src/native_key_bindings.gd")
const DIRECTIONS = {"up":KEY_UP,"down":KEY_DOWN,"left":KEY_LEFT,"right":KEY_RIGHT}
var held: Dictionary = {}
var movement: Dictionary = {}

func clear() -> void: held.clear(); movement.clear()
func release_movement() -> void: movement.clear()

func handle(app, event: InputEvent) -> void:
	if event is not InputEventKey: return
	var identity: int = Keys.scan(event)
	var action: String = app.key_bindings.action(event)
	if not event.pressed:
		var released: String = movement.get(identity,""); held.erase(identity); movement.erase(identity)
		if DIRECTIONS.has(released) and not movement.values().has(released): app.walk_input.key_event(DIRECTIONS[released],false)
		if not action.is_empty() and not app.session.modal: app.get_viewport().set_input_as_handled()
		return
	# Embedded file/settings/equipment dialogs retain ordinary text and GUI keys.
	if app.session.modal: return
	if action.is_empty():
		if identity == 0x3f: action = "save"
		elif identity == 0x43: action = "load"
		else: return
	app.get_viewport().set_input_as_handled()
	if event.echo or held.has(identity): return
	held[identity] = action
	if not app.session.focused: return
	if action == "none": return
	if action == "cancel": cancel(app); return
	if action == "save": app._save(); return
	if action == "load": app._show_saves(); return
	if action == "confirm":
		var focused = app.get_viewport().gui_get_focus_owner()
		if focused is Button and focused.is_visible_in_tree() and not focused.disabled and focused.get_parent() not in [app.options,app.target_pages,app.dream_hud.commands]:
			if focused is OptionButton: focused.show_popup()
			else: focused.pressed.emit()
			return
	if app.session.paused or app.session.state.is_empty(): return
	if app.battle_view.playing(): app._clear_input(); return
	if DIRECTIONS.has(action):
		if app.session.battle_open() or app.session.dialogue_open: navigate(app,action)
		else: movement[identity] = action; app.walk_input.key_event(DIRECTIONS[action],true)
		return
	if action == "confirm":
		if app.session.battle_open() or app.session.dialogue_open: confirm(app)
		else:
			if app.session.interact(): app.message.text = ""
			elif not app.session.error.is_empty(): app.message.text = app.session.error
		return
	if action == "status": app._show_status(); return
	if not app.session.battle_open():
		if action == "equipment" and not app.equipment_button.disabled and app.equipment_button.visible: app._show_equipment()
		elif action in ["items","skills"]: app.message.text = "当前物品和仙术菜单用于战斗。"
		return
	var battle: Dictionary = app.session.state.extensions[app.Battle.KEY]
	var actor: Dictionary = app.session.entity(battle.party[battle.turn])
	if action in ["previous","next"]:
		var delta: int = -1 if action == "previous" else 1
		if app.skill_menu.mode != "closed": app.skill_menu._page(app,delta)
		elif app.item_menu.mode != "closed": app.item_menu._page(app,delta)
		elif not app.classic_mode or app.classic_attack: app._change_enemy_page(delta)
		return
	if not app.Statuses.blocking(app.session.package,app.session.state,actor.instance_id,"skip_turn").is_empty():
		app.message.text = "当前状态下需要跳过行动。"; return
	match action:
		"skills", "items":
			var skills: bool = action == "skills"
			var ids: Array = app.Session.Progression.skill_ids(app.session.package,actor) if skills else app.session.package.world.get("item_definitions",[])
			if ids.is_empty() or (skills and not app.Statuses.blocking(app.session.package,app.session.state,actor.instance_id,"block_skills").is_empty()):
				app.message.text = "当前没有可用仙术。" if skills else "当前没有物品定义。"; return
			var selected = app.skill_menu if skills else app.item_menu
			var other = app.item_menu if skills else app.skill_menu
			other.mode = "closed"; other.selected_id = ""; other.page = 0
			app.classic_attack = false; app.classic_misc = false
			selected._open(app)
		"guard": app._battle_action("guard","")
		"escape": app._battle_action("escape","")
		"repeat", "auto", "equipment": app.message.text = "当前版本尚未支持" + {"repeat":"重复上次行动","auto":"围攻","equipment":"战斗投掷"}[action] + "。"

func cancel(app) -> void:
	if app.session.paused or app.battle_view.playing(): app._pause()
	elif app.session.battle_open() and app.skill_menu.mode != "closed": app.skill_menu.cancel(app)
	elif app.session.battle_open() and app.item_menu.mode != "closed": app.item_menu.cancel(app)
	elif app.session.battle_open() and app.classic_mode and app.classic_attack: app._classic_select_attack(false)
	elif app.session.battle_open() and app.classic_mode and app.classic_misc: app._classic_select_misc(false)
	else: app._pause()

func controls(app) -> Array:
	var candidates: Array = app._battle_controls() if app.session.battle_open() else app.options.get_children()
	return candidates.filter(func(c): return c is Button and not c.disabled and c.is_visible_in_tree())

func confirm(app) -> void:
	var buttons: Array = controls(app)
	if buttons.is_empty(): return
	var focused = app.get_viewport().gui_get_focus_owner()
	if focused not in buttons: focused = buttons[0]
	# The input is consumed before emitting: one key cannot also activate the
	# next UI generation through Godot's built-in ui_accept release handling.
	focused.grab_focus(); focused.pressed.emit()

func navigate(app, direction: String) -> void:
	var buttons: Array = controls(app)
	if buttons.is_empty(): return
	var focused = app.get_viewport().gui_get_focus_owner()
	if focused not in buttons: buttons[0].grab_focus(); return
	var axis: Vector2 = {"up":Vector2.UP,"down":Vector2.DOWN,"left":Vector2.LEFT,"right":Vector2.RIGHT}[direction]
	var best: Button; var cost: float = INF
	for button in buttons:
		if button == focused: continue
		var offset: Vector2 = button.get_global_rect().get_center()-focused.get_global_rect().get_center()
		var forward: float = offset.dot(axis)
		if forward <= 1: continue
		var candidate_cost: float = forward + absf(offset.cross(axis))*2.0
		if candidate_cost < cost: best = button; cost = candidate_cost
	if best == null:
		var delta: int = -1 if direction in ["up","left"] else 1
		best = buttons[posmod(buttons.find(focused)+delta,buttons.size())]
	best.grab_focus()
