# SPDX-License-Identifier: MIT
extends Control
## Authored action playback consumes committed results; geometry is explicit fallback.
const Frames = preload("res://src/native_map_animation.gd")
const Presentation = preload("res://src/native_battle_presentation.gd")
const Layout = preload("res://src/native_battle_layout.gd")
const Classic = preload("res://src/native_classic_battle.gd")
const Hud = preload("res://src/native_battle_hud_config.gd")
const Progression = preload("res://src/native_progression.gd")
signal playback_finished
signal display_changed
var presentation = Presentation.new()
var idle_elapsed: float = 0.0
var displayed_frames: Dictionary = {}
var displayed_bodies: Dictionary = {}
var displayed_markers: Dictionary = {}
var target_ids: Array = []
var projection: Transform2D = Transform2D.IDENTITY
var layout_spacing: float = 1.0
var _frame_extents: Dictionary = {}
var _extent_package
var background_asset: String = ""
var background_rect: Rect2
var classic_stage: Rect2
const Battle = preload("res://src/native_battle.gd")
const Statuses = preload("res://src/native_statuses.gd")
const PAGE_SIZE = 8 # Presentation page size, never a battle capacity limit.
var session
var _event_key: String = ""
var _elapsed: float = 1.0
var _battle_key: String = ""
var enemy_page: int = 0
var display_font: Font
var _status_regions: Array = []
func bind(value) -> void:
	session = value
	if _extent_package != session.package:
		_extent_package = session.package; _frame_extents.clear()
	if not presentation.context.is_empty() and presentation.context != Presentation.state_context(session.state): presentation.clear()
	if not session.battle_open() and not playing(): target_ids.clear(); queue_redraw(); return
	var battle: Dictionary = display_battle()
	var identity = str(session.state.timeline_epoch) + ":" + battle.execution_id
	if identity != _battle_key:
		_battle_key = identity; enemy_page = 0; idle_elapsed = 0.0; target_ids.clear()
		_event_key = identity + ":" + str(battle.step); _elapsed = 1.0
	enemy_page = clampi(enemy_page, 0, page_count() - 1)
	var key = identity + ":" + str(battle.step)
	if key != _event_key:
		_event_key = key; _elapsed = 0.0
	queue_redraw()
func playing() -> bool:
	return presentation.active

func action_caption() -> String:
	if not playing(): return ""
	var phase: Dictionary = presentation.current()
	if phase.get("reaction") in ["block","cover"]:
		var defender: Dictionary = presentation.actors[phase.defender_id]
		return session.package.index.actor_definitions[defender.definition_id].display_name + (" · 援护" if phase.reaction == "cover" else " · 格挡")
	var event: Dictionary = phase.event
	if event.get("kind") != "cast": return ""
	var actor: Dictionary = presentation.actors[event.source]
	var skills: Array = session.package.world.get("skill_definitions", []).filter(func(s): return s.id == event.skill_id)
	if skills.is_empty(): return ""
	return (session.package.index.actor_definitions[actor.definition_id].display_name + " · " + skills[0].display_name).replace("\n", " ").replace("\r", " ")
func display_battle() -> Dictionary:
	return presentation.battle if playing() else (session.state.extensions.get(Battle.KEY, {}) if session != null else {})
func classic_layout() -> Dictionary:
	var battle: Dictionary = display_battle()
	return {} if battle.is_empty() else Classic.for_encounter(session.package.world,battle.encounter_id)
func present_committed(before: Dictionary, result: Dictionary, outcome: String) -> void:
	target_ids.clear()
	presentation.begin(session.package, before, result, outcome)
	display_changed.emit()
	queue_redraw()
func skip() -> void:
	target_ids.clear(); presentation.clear(); playback_finished.emit(); queue_redraw()
func preview_targets(ids: Array) -> void:
	target_ids = ids.duplicate() if session != null and session.battle_open() and not playing() else []
	queue_redraw()
func invalidate_layout() -> void:
	_frame_extents.clear(); queue_redraw()
func page_count() -> int:
	var battle: Dictionary = display_battle()
	return ceili(battle.enemies.size() / float(PAGE_SIZE)) if not battle.is_empty() else 1
static func enemy_label(package, enemy: Dictionary, index: int) -> String:
	return "%d · %s" % [index + 1, package.index.actor_definitions[enemy.definition_id].display_name]
func _process(delta: float) -> void:
	if not visible or session == null: return
	var running: bool = not session.paused and not session.modal and session.focused
	if running: idle_elapsed += delta; _elapsed += delta
	var previous_phase: int = presentation.phase_index
	if presentation.advance(delta, running): playback_finished.emit()
	if previous_phase != presentation.phase_index: display_changed.emit()
	queue_redraw()
func _draw() -> void:
	_status_regions.clear(); displayed_frames.clear(); displayed_bodies.clear(); displayed_markers.clear()
	if session == null or (not session.battle_open() and not playing()): return
	_draw_battle(display_battle(), Vector2(get_viewport_rect().size))

func _get_tooltip(at_position: Vector2) -> String:
	for region in _status_regions:
		if region.bounds.has_point(at_position): return region.text
	return ""

static func cover_rect(source: Vector2, bounds: Vector2) -> Rect2:
	var scaled = source * maxf(bounds.x/source.x, bounds.y/source.y)
	return Rect2((bounds-scaled)/2, scaled)

func presentation_rect(bounds: Vector2) -> Rect2:
	var battle: Dictionary = display_battle()
	var profile: Dictionary = Hud.for_encounter(session.package.world,battle.encounter_id) if not battle.is_empty() else {}
	return Rect2(Vector2.ZERO,bounds) if profile.is_empty() else Hud.geometry(profile.layout,bounds,battle.party.size()).content

func _classic_stage(bounds: Vector2) -> Rect2:
	var region: Rect2 = presentation_rect(bounds)
	var result: Rect2 = Classic.stage_rect(region.size)
	result.position += region.position
	return result

func _draw_background(battle: Dictionary, bounds: Vector2) -> void:
	background_asset = ""; background_rect = Rect2()
	draw_rect(Rect2(Vector2.ZERO, bounds), Color("18232b"))
	var encounter: Dictionary = Battle.encounter(session.package.world, battle.encounter_id)
	if encounter.get("background_asset") == null: return
	background_asset = encounter.background_asset
	var texture: Texture2D = session.package.textures[background_asset]
	background_rect = cover_rect(texture.get_size(), bounds)
	if not classic_layout().is_empty():
		var stage: Rect2 = _classic_stage(bounds)
		var rendered: Vector2 = texture.get_size() * minf(stage.size.x/texture.get_width(),stage.size.y/texture.get_height())
		background_rect = Rect2(stage.get_center()-rendered/2.0,rendered)
	draw_texture_rect(texture, background_rect, false)

static func party_anchor(index: int, count: int, bounds: Vector2) -> Vector2:
	return Layout.party_anchor(index, count, bounds)

func _extent(definition: Dictionary, side: int) -> Rect2:
	var set_id = definition.get("battle_sprite_set")
	var key: String = str(set_id) + ":" + str(side)
	if not _frame_extents.has(key):
		var extent = Rect2(-28,-68,56,92)
		if set_id != null:
			for clip in session.package.index.battle_sprite_sets[set_id].clips:
				if clip.facing != ("upper_left" if side == 1 else "lower_right"): continue
				for frame in clip.frames: extent = extent.merge(Layout.frame_rect(frame))
		# Include every action plus motion and readable overlay margins, so
		# changing frame/action/page never pumps the camera zoom.
		_frame_extents[key] = extent.grow_individual(20,32,20,12)
	return _frame_extents[key]

func _sprite_extent(definition: Dictionary, side: int) -> Rect2:
	var set_id = definition.get("battle_sprite_set")
	var key: String = str(set_id)+":"+str(side)+":sprite"
	if not _frame_extents.has(key):
		var extent = Rect2(); var found: bool = false
		if set_id != null:
			for clip in session.package.index.battle_sprite_sets[set_id].clips:
				if clip.facing != ("upper_left" if side == 1 else "lower_right"): continue
				for frame in clip.frames:
					var rect: Rect2 = Layout.frame_rect(frame)
					extent = extent.merge(rect) if found else rect; found = true
		_frame_extents[key] = extent if found else Rect2(-12,-40,24,40)
	return _frame_extents[key]

func _draw_battle(battle: Dictionary, bounds: Vector2) -> void:
	_draw_background(battle, bounds)
	var classic: Dictionary = classic_layout()
	var dream: bool = Classic.is_dream(classic)
	var reference_bounds: Vector2 = Classic.SIZE if not classic.is_empty() else bounds
	var phase: Dictionary = presentation.current()
	var static_feedback: bool = Frames.BATTLE_CAPABILITY not in session.package.manifest.required_capabilities and _elapsed < .35
	if not phase.is_empty():
		for i in range(battle.enemies.size()):
			if battle.enemies[i].instance_id == phase.actor_id: enemy_page = i / PAGE_SIZE
	var bodies: Array = []
	for side in range(2):
		var rows: Array = battle.enemies if side == 0 else battle.party.map(func(id): return presentation.actors[id] if playing() else Battle.actor(session.state,id))
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var definition: Dictionary = session.package.index.actor_definitions[row.definition_id]
			var count: int = mini(PAGE_SIZE, rows.size() - (i / PAGE_SIZE) * PAGE_SIZE)
			var pos: Vector2 = Layout.enemy_anchor(i % PAGE_SIZE,count,reference_bounds) if side == 0 else (Classic.party_anchor(i,rows.size()) if not classic.is_empty() else Layout.party_anchor(i,rows.size(),bounds))
			if dream and side == 0: pos = Classic.dream_enemy_anchor(session.package.world,battle.encounter_id,row.instance_id,i,rows.size())
			var sprite_scale: float = float(classic.get("sprite_scale_milli",1000))/1000.0
			if definition.get("battle_sprite_set") == null: sprite_scale = 1.0
			var fit: float = 1.0 if classic.is_empty() or dream else Classic.sprite_fit(_sprite_extent(definition,side),pos,sprite_scale,side)
			bodies.append({"row":row,"position":pos,"side":side,"index":i,"page":i/PAGE_SIZE if side == 0 else -1,"extent":_extent(definition,side),"sprite_fit":fit})
	classic_stage = Rect2()
	if classic.is_empty():
		layout_spacing = Layout.spacing(bodies)
		for body in bodies: body.position *= layout_spacing
		projection = Layout.fit(bodies,bounds)
	else:
		layout_spacing = 1.0; classic_stage = _classic_stage(bounds)
		var zoom: float = classic_stage.size.x / Classic.SIZE.x
		projection = Transform2D(Vector2(zoom,0),Vector2(0,zoom),classic_stage.position)
	var scale_value: float = projection.x.x * (float(classic.sprite_scale_milli)/1000.0 if not classic.is_empty() else 1.0)
	var anchors: Dictionary = {}
	for body in bodies: anchors[body.row.instance_id] = body.position
	for body in bodies: body.position = presentation.position_for(body.row.instance_id,anchors)
	bodies.sort_custom(func(a,b): return a.position.y < b.position.y)
	for body in bodies:
		if body.side == 0 and body.index / PAGE_SIZE != enemy_page: continue
		var row: Dictionary = body.row
		var definition: Dictionary = session.package.index.actor_definitions[row.definition_id]
		var pos: Vector2 = body.position
		var feedback_color = Color("855759") if body.side == 0 else Color("587d95")
		if dream and body.side == 0 and row.instance_id in target_ids: feedback_color = feedback_color.lightened(.4)
		if row.hp == 0: feedback_color = feedback_color.darkened(.6)
		if static_feedback:
			for event in battle.events:
				if event.kind in ["attack","cast","item_use"] and event.source == row.instance_id: pos.x += (1 if body.side == 0 else -1) * sin(_elapsed / .35 * PI) * 18
				if event.kind in ["attack","damage","status_damage"] and event.target == row.instance_id: feedback_color = feedback_color.lerp(Color.WHITE,.5)
				if event.kind in ["heal","revive","status_heal"] and event.target == row.instance_id: feedback_color = feedback_color.lerp(Color("80d8a1"),.7)
		var action: String = "idle"
		if row.hp == 0: action = "dead"
		elif not playing() and session.battle_open() and not Statuses.blocking(session.package,session.state,row.instance_id,"skip_turn").is_empty(): action = "sleep"
		elif row.instance_id in battle.guarding: action = "defend"
		elif row.hp * 5 <= Progression.stats(session.package, row).max_hp: action = "dying"
		var elapsed: int = roundi(idle_elapsed * 1000000.0)
		var override: String = presentation.pose_for(row.instance_id)
		if not override.is_empty():
			action = override; elapsed = roundi(presentation.elapsed_us)
			if action == "attack": pos += Vector2(-18,-8) * (1 if body.side == 1 else -1) * sin(PI * elapsed / phase.duration_us)
		pos = projection * pos
		var set_id = definition.get("battle_sprite_set")
		var clip: Dictionary = {} if set_id == null else Frames.clip_for(session.package.index.battle_sprite_sets[set_id],action,"upper_left" if body.side == 1 else "lower_right")
		var frame: Dictionary = Frames.frame_at(clip,elapsed)
		var local_rect: Rect2 = Rect2(-12,-40,24,40) if frame.is_empty() else Layout.frame_rect(frame)
		var body_scale: float = projection.x.x if frame.is_empty() and not classic.is_empty() else scale_value
		body_scale *= body.sprite_fit
		var rect = Rect2(pos + local_rect.position * body_scale,local_rect.size * body_scale)
		draw_circle(pos,maxf(6,15*scale_value),Color(0.05,0.07,0.08,0.55))
		if not frame.is_empty():
			var tint: Color = Color(1.35,1.35,1.35) if dream and body.side == 0 and row.instance_id in target_ids and int(idle_elapsed*5)%2 == 0 else Color.WHITE
			var texture: Texture2D = session.package.textures[frame.asset_id]
			if dream:
				var clipped: Rect2 = rect.intersection(classic_stage)
				if clipped.has_area(): draw_texture_rect_region(texture,clipped,Rect2((clipped.position-rect.position)/rect.size*texture.get_size(),clipped.size/rect.size*texture.get_size()),tint)
			else: draw_texture_rect(texture,rect,false,tint)
			displayed_frames[row.instance_id] = {"action":action,"resolved_action":clip.action,"fallback":clip.action != action,"frame_id":frame.frame_id,"asset_id":frame.asset_id,"anchor":pos,"rect":rect}
		else:
			draw_rect(rect.intersection(classic_stage) if dream else rect,feedback_color)
		displayed_bodies[row.instance_id] = {"anchor":pos,"rect":rect,"effect_origin":Layout.effect_origin(rect,bounds),"side":body.side,"index":body.index,"hp":row.hp,"sprite_fit":body.sprite_fit}
		if body.side == 1 and body.index == battle.turn and not playing() and not dream: draw_arc(pos,18,0,TAU,32,Color("ddbd70"),2)
		var label: String = enemy_label(session.package,row,body.index) if body.side == 0 else definition.display_name
		var statuses: PackedStringArray = Statuses.describe(session.package,session.state,row.instance_id) if session.battle_open() and not playing() else PackedStringArray()
		var resolved: String = str(clip.get("action","static"))
		var action_label: String = action if resolved == action else action + " (回退为 " + resolved + ")"
		_status_regions.append({"bounds":rect,"text":label+" · "+action_label+"\n"+"\n".join(statuses)})
	# Overlay after all bodies: stable ordinals cannot be painted over by a
	# nearer sprite. Full names, resources and status detail belong to controls.
	for id in displayed_bodies:
		var body: Dictionary = displayed_bodies[id]
		if body.side == 0 and not dream:
			var badge: Vector2 = (body.anchor + Vector2(20,0)).clamp(Vector2(15,15),bounds-Vector2(15,15))
			draw_circle(badge,13,Color("0b1219"))
			draw_arc(badge,13,0,TAU,24,Color("718392"),1)
			var number: String = str(body.index+1)
			draw_string(display_font,badge+Vector2(-display_font.get_string_size(number,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x/2,5),number,HORIZONTAL_ALIGNMENT_LEFT,28,14,Color("e5dbc5"))
		if dream and body.side == 1 and not playing() and (id in target_ids or body.index == battle.turn):
			var offset: Vector2 = Vector2(-8,-67 if id in target_ids else -74)
			var at: Vector2 = projection * (Classic.party_anchor(body.index,battle.party.size())+offset)
			var marker_size: Vector2 = Vector2(9,6)*projection.x.x
			displayed_markers[id] = Rect2(at,marker_size)
			draw_colored_polygon(PackedVector2Array([at,at+Vector2(marker_size.x,0),at+Vector2(marker_size.x/2,marker_size.y)]),Color("82d5e7") if id in target_ids else Color("ddbd70"))
		if id in target_ids and not dream:
			var top: Vector2 = Vector2(body.rect.get_center().x,maxf(12,body.rect.position.y-12))
			draw_colored_polygon(PackedVector2Array([top+Vector2(-7,-7),top+Vector2(7,-7),top+Vector2(0,4)]),Color("82d5e7"))
			draw_arc(body.anchor,22,0,TAU,32,Color("82d5e7"),2)
		if phase.get("actor_id") == id and not phase.event.is_empty():
			var event: Dictionary = phase.event
			if event.kind in ["attack","damage","status_damage","heal","revive","status_heal"]:
				var healing: bool = event.kind in ["heal","revive","status_heal"]
				var result_text: String = ("援护" if phase.reaction == "cover" else "格挡") if phase.get("reaction") in ["block","cover"] else ("+" if healing else "-")+str(event.amount)
				draw_string(display_font,body.effect_origin,result_text,HORIZONTAL_ALIGNMENT_LEFT,90,22,Color("80d8a1") if healing else Color("ffc7a0"))
	var caption: String = action_caption()
	if not caption.is_empty():
		var width: float = maxf(24, bounds.x - 40)
		var text: String = caption
		while text.length() > 1 and display_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > width:
			text = text.left(text.length() - 2) + "…"
		draw_rect(Rect2(12, 8, minf(width + 16, display_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 16), 30), Color("101820"))
		draw_string(display_font, Vector2(20, 29), text, HORIZONTAL_ALIGNMENT_LEFT, width, 18, Color("f1dda7"))
