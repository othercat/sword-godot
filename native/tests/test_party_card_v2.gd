# SPDX-License-Identifier: MIT
extends "res://tests/test_status_presentation.gd"
const Card = preload("res://src/native_party_card.gd")
const CardElement = preload("res://src/native_party_card_element.gd")
var command_actor: String = ""
var card_captures: int = 0

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size()!=2: quit(2); return
	output=args[1]; DirAccess.make_dir_recursive_absolute(output); root.size=Vector2i(1280,800)
	var app = App.instantiate(); root.add_child(app); await process_frame
	app.saves=Save.new(output.path_join("saves"))
	if not app.open_package(args[0]): check(false,"v2 owner package loads: "+app.session.error); _finish(); return
	await process_frame; await click(option(app,"继续"))
	var opening: Dictionary = app.session.state.duplicate(true)
	check(app.session.battle_open() and opening.active_party.size()==4 and app._responsive_mode(),"four-person author package enters the real responsive HUD")
	await skill(app,"侵蚀术"); await skill(app,"侵蚀术"); await item(app,"调息散"); await guard_round(app,1)
	await save(app,args[0],4,"v2-after-status-tick")
	await guard_round(app,2)
	check(app.battle_view.display_statuses(opening.active_party[0]).is_empty(),"expired party status disappears after its clear event")
	await save(app,args[0],4,"v2-after-expiry")
	probes(app,opening)
	root.remove_child(app); app.queue_free(); await process_frame; _finish()

func option(app, prefix: String) -> Button:
	if has_option(app.options,prefix): return find_button(app.options,prefix)
	return find_button(app.responsive_hud.commands,prefix)

func use(app, is_item: bool, name: String, target: int) -> void:
	if is_item and app.classic_root: await click(option(app,"其他"))
	await super.use(app,is_item,name,target)

func guard_round(app, expected: int) -> void:
	for _i in range(app.session.state.active_party.size()):
		if app.session.state.extensions[Battle.KEY].round!=expected: return
		if app.classic_root: await click(option(app,"其他"))
		await click(option(app,"防御"))
	check(app.session.state.extensions[Battle.KEY].round!=expected,"real command disc and miscellaneous guard finish round")

func check_card_projection(app, phase: Dictionary, rows: Array) -> void:
	var view = app.battle_view; var hud = app.responsive_hud
	var event: Dictionary = phase.event; var kind: String = event.get("kind","")
	if view.presentation.phase_index==0: command_actor=""
	if phase.has("cover"): command_actor=phase.cover.attacker_id
	elif phase.action=="attack": command_actor=phase.actor_id
	elif kind in ["cast","item_use","guard","escape","status_skip"]: command_actor=event.source
	elif kind in ["status_damage","status_heal"] or (kind=="status_clear" and event.get("reason")=="expired") or phase.has("status_snapshot"): command_actor=""
	check(view.display_action_actor()==command_actor,"action marker remains command source across reaction and clears for round-end settlement")
	hud.bind(view)
	check(Card.schema_id(app.session.package.world)==Card.SCHEMA_V2,"actual loaded card uses v2")
	for id in view.display_battle().party:
		check(hud.cards[id].statuses==rows.filter(func(row):return row.actor_id==id),"card consumes displayed actor statuses, not settled authority")
		check(hud.cards[id].current_action==(id==command_actor),"card marker follows command actor identity")
		var marker = hud.element_nodes[id+"|card.action"]
		check(marker.visible==(id==command_actor),"actual marker node hides during enemy commands and reconciliation")
	if card_captures<2 and kind=="status_add" and event.target in view.display_battle().party:
		await RenderingServer.frame_post_draw
		var node = hud.element_nodes[event.target+"|card.statuses"]
		check(node.rendered_statuses.any(func(row):return row.get("status_id")==event.status_id),"drawn status cell retains the event's stable identity")
		check(node.rendered_statuses.any(func(row):return row.get("status_id")==event.status_id and row.binding.image!=null),"ordinary party regeneration draws its GUI-imported PNG binding")
		check(not node.rendered_text.is_empty(),"actual status label/counter text draws")
		root.get_texture().get_image().save_png(output.path_join("party-card-status-%d.png" % card_captures)); card_captures+=1

func probes(app, opening: Dictionary) -> void:
	super.probes(app,opening)
	var profile: Dictionary = Card.for_encounter(app.session.package.world,opening.extensions[Battle.KEY].encounter_id)
	var element: Dictionary = profile.elements.filter(func(e):return e.kind=="status-list")[0].duplicate(true)
	var definitions: Dictionary = app.session.package.index.status_definitions
	var ids: Array = definitions.keys(); ids.sort()
	var rows: Array = []
	for i in range(ids.size()): rows.append({"status_id":ids[i],"stacks":i%2+1,"remaining_rounds":3})
	element.bindings=[{"status_id":ids[-1],"short_label":"末","image":null,"tint":"#ffffffff"}]
	element.columns=2; element.rows=1; element.unmapped="label"
	var snapshot={"statuses":rows}; var before: Dictionary = snapshot.duplicate(true)
	var cells: Array = Card.status_cells(element,snapshot,definitions)
	check(cells[0].status_id==ids[-1] and cells[0].label=="末" and cells[1].overflow==ids.size()-1,"bound order and overflow include displaced last cell")
	element.columns=1; check(Card.status_cells(element,snapshot,definitions)[0].overflow==ids.size(),"one-cell overflow includes every hidden status")
	element.unmapped="hide"; cells=Card.status_cells(element,snapshot,definitions)
	check(cells.size()==1 and cells[0].status_id==ids[-1],"single binding can be independently placed")
	cells[0].stacks=999; check(snapshot==before,"UI cells cannot mutate display rows")
	check(Card.status_cells(element,{"statuses":[]},definitions).is_empty(),"cleared status list has no cells")
	var bounds=Rect2(7,11,100,30); element.columns=2; element.rows=2
	check(Card.status_cell_rect(element,bounds,2).position.y>Card.status_cell_rect(element,bounds,0).position.y,"grid is row-major within the element")

func _finish() -> void:
	var report={"checks":checks,"failed":failed,"saves":saves,"traces":traces,"signals_seen":signals_seen,"card_captures":card_captures,"event_kinds":event_kinds.keys(),"physical_input":false,"engine_injected_input":true,"synthetic_in_memory_probes":true,"real_assets":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("party card v2 checks=%d traces=%d failed=%d" % [checks.size(),traces.size(),failed]); quit(0 if failed==0 else 1)
