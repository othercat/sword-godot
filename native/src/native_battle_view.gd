# SPDX-License-Identifier: MIT
extends Control
## Geometric preview actors until authored battle action sets are available.
const Battle = preload("res://src/native_battle.gd")
const PAGE_SIZE = 8 # Presentation page size, never a battle capacity limit.
var session
var _event_key: String = ""
var _battle_key: String = ""
var enemy_page: int = 0
var _elapsed: float = 1.0
var display_font: Font
func bind(value) -> void:
	session = value
	if not session.battle_open(): return
	var battle: Dictionary = session.state.extensions[Battle.KEY]
	var identity = str(session.state.timeline_epoch) + ":" + battle.execution_id
	if identity != _battle_key:
		_battle_key = identity; enemy_page = 0
	enemy_page = clampi(enemy_page, 0, page_count() - 1)
	var key = identity + ":" + str(battle.step)
	if key != _event_key:
		_event_key = key; _elapsed = 0.0
	queue_redraw()
func page_count() -> int:
	return ceili(session.state.extensions[Battle.KEY].enemies.size() / float(PAGE_SIZE)) if session != null and session.battle_open() else 1
static func enemy_label(package, enemy: Dictionary, index: int) -> String:
	return "%d · %s" % [index + 1, package.index.actor_definitions[enemy.definition_id].display_name]
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
		var start: int = enemy_page * PAGE_SIZE if side == 0 else 0
		var rows: Array = battle.enemies.slice(start, start + PAGE_SIZE) if side == 0 else battle.party.map(func(id): return Battle.actor(session.state, id))
		var columns: int = 2 if side == 0 and rows.size() > 4 else 1
		var per_column: int = ceili(rows.size() / float(columns))
		var gap: float = minf(72.0, (bounds.y - 40.0) / per_column)
		var cell_width: float = bounds.x * (0.51 / columns if side == 0 else 0.36)
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var definition: Dictionary = session.package.index.actor_definitions[row.definition_id]
			var pos = Vector2(bounds.x * (0.04 if side == 0 else 0.62) + floori(i / float(per_column)) * cell_width, 24 + (i % per_column) * gap)
			var color = Color("855759") if side == 0 else Color("587d95")
			if row.hp == 0: color = color.darkened(0.6)
			if _elapsed < 0.35:
				for event in battle.events:
					if event.kind in ["attack", "cast", "item_use"] and event.source == row.instance_id: pos.x += (1 if side == 0 else -1) * sin(_elapsed / 0.35 * PI) * 18
					if event.kind in ["attack", "damage"] and event.target == row.instance_id: color = color.lerp(Color.WHITE, 0.5)
					if event.kind in ["heal", "revive"] and event.target == row.instance_id: color = color.lerp(Color("80d8a1"), 0.7)
			draw_rect(Rect2(pos, Vector2(26, maxf(10, gap - 20))), color)
			var width: float = minf(170.0, cell_width - 44)
			draw_rect(Rect2(pos + Vector2(34, 29), Vector2(width, 5)), Color("303942"))
			draw_rect(Rect2(pos + Vector2(34, 29), Vector2(width * row.hp / definition.max_hp, 5)), Color("8fab70"))
			var label: String = enemy_label(session.package, row, start + i) if side == 0 else definition.display_name
			draw_string(display_font, pos + Vector2(34, 16), label, HORIZONTAL_ALIGNMENT_LEFT, width, 16, Color("e5dbc5"))
			draw_string(display_font, pos + Vector2(34, 49), "%d / %d · 真气%d" % [row.hp, definition.max_hp, row.mp], HORIZONTAL_ALIGNMENT_LEFT, width, 14, Color("b2b7b8"))
			if side == 1 and i == battle.turn: draw_rect(Rect2(pos - Vector2(4, 4), Vector2(34, maxf(18, gap - 12))), Color("ddbd70"), false, 2)
