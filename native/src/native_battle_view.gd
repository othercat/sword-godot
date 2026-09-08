# SPDX-License-Identifier: MIT
extends Control
## Authored action playback consumes committed results; geometry is explicit fallback.
const Frames = preload("res://src/native_map_animation.gd")
const Presentation = preload("res://src/native_battle_presentation.gd")
signal playback_finished
var presentation = Presentation.new()
var idle_elapsed: float = 0.0
var displayed_frames: Dictionary = {}
var background_asset: String = ""
var background_rect: Rect2
const Battle = preload("res://src/native_battle.gd")
const Statuses = preload("res://src/native_statuses.gd")
const PAGE_SIZE = 8 # Presentation page size, never a battle capacity limit.
var session
var _event_key: String = ""
var _battle_key: String = ""
var enemy_page: int = 0
var _elapsed: float = 1.0
var display_font: Font
var _status_regions: Array = []
func bind(value) -> void:
	session = value
	if not presentation.context.is_empty() and presentation.context != Presentation.state_context(session.state): presentation.clear()
	if not session.battle_open() and not playing(): return
	var battle: Dictionary = display_battle()
	var identity = str(session.state.timeline_epoch) + ":" + battle.execution_id
	if identity != _battle_key:
		_battle_key = identity; enemy_page = 0; idle_elapsed = 0.0
	enemy_page = clampi(enemy_page, 0, page_count() - 1)
	var key = identity + ":" + str(battle.step)
	if key != _event_key:
		_event_key = key; _elapsed = 0.0
	queue_redraw()
func playing() -> bool:
	return presentation.active
func display_battle() -> Dictionary:
	return presentation.battle if playing() else (session.state.extensions.get(Battle.KEY, {}) if session != null else {})
func present_committed(before: Dictionary, result: Dictionary, outcome: String) -> void:
	presentation.begin(session.package, before, result, outcome)
	queue_redraw()
func skip() -> void:
	presentation.clear(); playback_finished.emit(); queue_redraw()
func page_count() -> int:
	var battle: Dictionary = display_battle()
	return ceili(battle.enemies.size() / float(PAGE_SIZE)) if not battle.is_empty() else 1
static func enemy_label(package, enemy: Dictionary, index: int) -> String:
	return "%d · %s" % [index + 1, package.index.actor_definitions[enemy.definition_id].display_name]
func _process(delta: float) -> void:
	if not visible or session == null: return
	var running: bool = not session.paused and not session.modal and session.focused
	if running: _elapsed += delta; idle_elapsed += delta
	if presentation.advance(delta, running): playback_finished.emit()
	queue_redraw()
func _draw() -> void:
	_status_regions.clear()
	if session == null or (not session.battle_open() and not playing()): return
	var battle: Dictionary = display_battle()
	var bounds = Vector2(get_viewport_rect().size)
	if Frames.BATTLE_CAPABILITY in session.package.manifest.required_capabilities:
		_draw_animated(battle, bounds); return
	_draw_background(battle, bounds)
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
					if event.kind in ["attack", "damage", "status_damage"] and event.target == row.instance_id: color = color.lerp(Color.WHITE, 0.5)
					if event.kind in ["heal", "revive", "status_heal"] and event.target == row.instance_id: color = color.lerp(Color("80d8a1"), 0.7)
			draw_rect(Rect2(pos, Vector2(26, maxf(10, gap - 20))), color)
			var width: float = minf(170.0, cell_width - 44)
			draw_rect(Rect2(pos + Vector2(34, 29), Vector2(width, 5)), Color("303942"))
			draw_rect(Rect2(pos + Vector2(34, 29), Vector2(width * row.hp / definition.max_hp, 5)), Color("8fab70"))
			var label: String = enemy_label(session.package, row, start + i) if side == 0 else definition.display_name
			draw_string(display_font, pos + Vector2(34, 16), label, HORIZONTAL_ALIGNMENT_LEFT, width, 16, Color("e5dbc5"))
			draw_string(display_font, pos + Vector2(34, 49), "%d / %d · 真气%d" % [row.hp, definition.max_hp, row.mp], HORIZONTAL_ALIGNMENT_LEFT, width, 14, Color("b2b7b8"))
			var statuses: PackedStringArray = Statuses.describe(session.package, session.state, row.instance_id)
			if not statuses.is_empty():
				draw_string(display_font, pos + Vector2(34, 64), statuses[0] + (" 等%d种" % statuses.size() if statuses.size() > 1 else ""), HORIZONTAL_ALIGNMENT_LEFT, width, 11, Color("dec784"))
				_status_regions.append({"bounds": Rect2(pos, Vector2(cell_width, gap)), "text": definition.display_name + "\n" + "\n".join(statuses)})
			if side == 1 and i == battle.turn: draw_rect(Rect2(pos - Vector2(4, 4), Vector2(34, maxf(18, gap - 12))), Color("ddbd70"), false, 2)

func _get_tooltip(at_position: Vector2) -> String:
	for region in _status_regions:
		if region.bounds.has_point(at_position): return region.text
	return ""

static func cover_rect(source: Vector2, bounds: Vector2) -> Rect2:
	var scaled = source * maxf(bounds.x/source.x, bounds.y/source.y)
	return Rect2((bounds-scaled)/2, scaled)

func _draw_background(battle: Dictionary, bounds: Vector2) -> void:
	background_asset = ""; background_rect = Rect2()
	draw_rect(Rect2(Vector2.ZERO, bounds), Color("18232b"))
	var encounter: Dictionary = Battle.encounter(session.package.world, battle.encounter_id)
	if encounter.get("background_asset") == null: return
	background_asset = encounter.background_asset
	var texture: Texture2D = session.package.textures[background_asset]
	background_rect = cover_rect(texture.get_size(), bounds)
	draw_texture_rect(texture, background_rect, false)

static func party_anchor(index: int, count: int, bounds: Vector2) -> Vector2:
	# Independently authored screen layout: every party member faces upper-left.
	# This is presentation order, not a gameplay formation or role-ID limit.
	var layouts = {
		3: [Vector2(.68,.74),Vector2(.80,.57),Vector2(.89,.36)],
		4: [Vector2(.61,.80),Vector2(.72,.71),Vector2(.82,.54),Vector2(.90,.33)],
		5: [Vector2(.59,.84),Vector2(.70,.75),Vector2(.79,.62),Vector2(.87,.48),Vector2(.91,.29)]
	}
	if layouts.has(count): return layouts[count][index] * bounds
	var ranks: int = ceili(count / 2.0)
	return Vector2(.65 + (index % 2) * .16, .28 + (index / 2) * .58 / maxi(1,ranks) + (index % 2)*.1) * bounds

func _draw_animated(battle: Dictionary, bounds: Vector2) -> void:
	displayed_frames.clear()
	_draw_background(battle, bounds)
	var phase: Dictionary = presentation.current()
	if not phase.is_empty():
		for i in range(battle.enemies.size()):
			if battle.enemies[i].instance_id == phase.actor_id: enemy_page = i / PAGE_SIZE
	var bodies: Array = []
	for side in range(2):
		var start: int = enemy_page * PAGE_SIZE if side == 0 else 0
		var rows: Array = battle.enemies.slice(start, start + PAGE_SIZE) if side == 0 else battle.party.map(func(id): return presentation.actors[id] if playing() else Battle.actor(session.state, id))
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var column: int = i % 2
			var ranks: int = ceili(rows.size() / 2.0)
			var pos = Vector2(bounds.x * ((0.19 if side == 0 else 0.65) + column * 0.16), bounds.y * (0.28 + (i / 2) * 0.58 / maxi(1, ranks) + column * 0.1))
			if side == 1: pos = party_anchor(i, rows.size(), bounds)
			bodies.append({"row":row,"position":pos,"side":side,"index":start+i})
	bodies.sort_custom(func(a,b): return a.position.y < b.position.y)
	for body in bodies:
		var row: Dictionary = body.row
		var definition: Dictionary = session.package.index.actor_definitions[row.definition_id]
		var pos: Vector2 = body.position
		var action: String = "idle"
		if row.hp == 0: action = "dead"
		elif not playing() and session.battle_open() and not Statuses.blocking(session.package, session.state, row.instance_id, "skip_turn").is_empty(): action = "sleep"
		elif row.instance_id in battle.guarding: action = "defend"
		elif row.hp < 100 and row.hp * 5 <= definition.max_hp: action = "dying"
		var elapsed: int = roundi(idle_elapsed * 1000000.0)
		if phase.get("actor_id") == row.instance_id and not phase.action.is_empty():
			action = phase.action; elapsed = roundi(presentation.elapsed_us)
			if action == "attack": pos += Vector2(-18, -8) * (1 if body.side == 1 else -1) * sin(PI * elapsed / phase.duration_us)
		var set_id = definition.get("battle_sprite_set")
		var clip: Dictionary = {} if set_id == null else Frames.clip_for(session.package.index.battle_sprite_sets[set_id], action, "upper_left" if body.side == 1 else "lower_right")
		var frame: Dictionary = Frames.frame_at(clip, elapsed)
		draw_circle(pos, 15, Color(0.05,0.07,0.08,0.55))
		if not frame.is_empty():
			var scale_value: float = float(frame.scale_milli) / 1000.0
			var rect = Rect2(pos - Vector2(frame.anchor.x, frame.anchor.y) * scale_value, Vector2(frame.width, frame.height) * scale_value)
			draw_texture_rect(session.package.textures[frame.asset_id], rect, false)
			displayed_frames[row.instance_id] = {"action":action,"resolved_action":clip.action,"fallback":clip.action != action,"frame_id":frame.frame_id,"asset_id":frame.asset_id,"anchor":pos,"rect":rect}
		else:
			var color = Color("855759") if body.side == 0 else Color("587d95")
			if row.hp == 0: color = color.darkened(0.6)
			draw_rect(Rect2(pos-Vector2(12,40),Vector2(24,40)), color)
		if body.side == 1 and body.index == battle.turn and not playing(): draw_arc(pos, 18, 0, TAU, 32, Color("ddbd70"), 2)
		var label: String = enemy_label(session.package, row, body.index) if body.side == 0 else definition.display_name
		# Party names/HP/MP already have an ordered sidebar. Repeating labels
		# between diagonally arranged bodies makes one member obscure another.
		if body.side == 0:
			draw_string(display_font, pos+Vector2(-46,19), label, HORIZONTAL_ALIGNMENT_LEFT, 135, 13, Color("e5dbc5"))
			draw_rect(Rect2(pos+Vector2(-36,23),Vector2(72,4)), Color("303942"))
			draw_rect(Rect2(pos+Vector2(-36,23),Vector2(72.0*row.hp/definition.max_hp,4)), Color("8fab70"))
			draw_string(display_font, pos+Vector2(-36,43), "%d / %d" % [row.hp,definition.max_hp], HORIZONTAL_ALIGNMENT_LEFT, 100, 11, Color("b2b7b8"))
		if phase.get("actor_id") == row.instance_id and not phase.event.is_empty():
			var event: Dictionary = phase.event
			if event.kind in ["attack","damage","status_damage","heal","revive","status_heal"]:
				var healing: bool = event.kind in ["heal","revive","status_heal"]
				draw_string(display_font,pos+Vector2(-12,-62), ("+" if healing else "-")+str(event.amount), HORIZONTAL_ALIGNMENT_LEFT,100,22,Color("80d8a1") if healing else Color("ffc7a0"))
		var statuses: PackedStringArray = Statuses.describe(session.package, session.state, row.instance_id) if session.battle_open() and not playing() else PackedStringArray()
		var resolved: String = str(clip.get("action", "static"))
		var action_label: String = action if resolved == action else action + " (回退为 " + resolved + ")"
		_status_regions.append({"bounds":Rect2(pos-Vector2(48,75),Vector2(115,120)),"text":label+" · "+action_label+"\n"+"\n".join(statuses)})
