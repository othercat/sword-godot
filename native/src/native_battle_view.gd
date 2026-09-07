# SPDX-License-Identifier: MIT
extends Control
## Geometric preview actors until authored battle action sets are available.
const Battle = preload("res://src/native_battle.gd")
var session
var _event_key: String = ""
var _elapsed: float = 1.0
var display_font: Font
func bind(value) -> void:
	session = value
	if not session.battle_open(): return
	var battle: Dictionary = session.state.extensions[Battle.KEY]
	var key = str(session.state.timeline_epoch) + ":" + battle.execution_id + ":" + str(battle.step)
	if key != _event_key:
		_event_key = key; _elapsed = 0.0
	queue_redraw()
func _process(delta: float) -> void:
	if not visible or session == null: return
	if not session.paused and not session.modal and session.focused: _elapsed += delta
	queue_redraw()
func _draw() -> void:
	if session == null or not session.battle_open(): return
	var battle: Dictionary = session.state.extensions[Battle.KEY]
	var bounds = Vector2(get_viewport_rect().size)
	draw_rect(Rect2(Vector2.ZERO, bounds), Color("151b24"))
	for side in range(2):
		var rows: Array = battle.enemies if side == 0 else battle.party.map(func(id): return Battle.actor(session.state, id))
		var gap: float = minf(72.0, (bounds.y - 40.0) / rows.size())
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var definition: Dictionary = session.package.index.actor_definitions[row.definition_id]
			var pos = Vector2(bounds.x * (0.14 if side == 0 else 0.62), 24 + i * gap)
			var color = Color("855759") if side == 0 else Color("587d95")
			if row.hp == 0: color = color.darkened(0.6)
			if _elapsed < 0.35:
				for event in battle.events:
					if event.kind == "attack" and event.source == row.instance_id: pos.x += (1 if side == 0 else -1) * sin(_elapsed / 0.35 * PI) * 18
					if event.kind == "attack" and event.target == row.instance_id: color = color.lerp(Color.WHITE, 0.5)
			draw_rect(Rect2(pos, Vector2(26, maxf(10, gap - 20))), color)
			var width: float = minf(170.0, bounds.x * 0.25)
			draw_rect(Rect2(pos + Vector2(34, 29), Vector2(width, 5)), Color("303942"))
			draw_rect(Rect2(pos + Vector2(34, 29), Vector2(width * row.hp / definition.max_hp, 5)), Color("8fab70"))
			draw_string(display_font, pos + Vector2(34, 16), definition.display_name, HORIZONTAL_ALIGNMENT_LEFT, width, 16, Color("e5dbc5"))
			draw_string(display_font, pos + Vector2(34, 49), str(row.hp) + " / " + str(definition.max_hp), HORIZONTAL_ALIGNMENT_LEFT, width, 14, Color("b2b7b8"))
			if side == 1 and i == battle.turn: draw_rect(Rect2(pos - Vector2(4, 4), Vector2(34, maxf(18, gap - 12))), Color("ddbd70"), false, 2)
