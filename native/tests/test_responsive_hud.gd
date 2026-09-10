# SPDX-License-Identifier: MIT
extends "res://tests/test_legacy_battle_import.gd"
const Placement = preload("res://src/native_hud_placement.gd")
const PartyCard = preload("res://src/native_party_card.gd")
const CardElement = preload("res://src/native_party_card_element.gd")
## Authored variants and real routed GUI input. No legacy parity or art verdict.
var windows: Array = []
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0])).fixtures
	for fixture in fixtures:
		package_path = fixture.package_path; root.size = Vector2i(1280,800)
		var app = App.instantiate(); root.add_child(app); await settle(); root.grab_focus(); await settle()
		app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
		app.saves = Save.new(output.path_join("saves-"+fixture.label))
		check(app.open_package(package_path),"open "+fixture.label)
		if app.session.package == null: finish(); return
		root.grab_focus(); await settle()
		for i in range(30):
			if app.session.battle_open(): break
			var node: Dictionary = app.session.current_node()
			if node.op == "dialogue": check(app.session.advance_dialogue(),"advance authored dialogue")
			elif node.op == "choice":
				var selected: String = ""
				for row in node.options:
					if row.id.ends_with(".train"): selected = row.id
				check(not selected.is_empty() and app.session.advance_dialogue(selected),"select authored training branch")
			else: check(false,"unexpected story entry"); finish(); return
		app._refresh(); await settle()
		var s = app.session; var view = app.battle_view
		if not s.battle_open(): check(false,"battle entry"); finish(); return
		check(app._responsive_mode() and app.dream_hud == app.responsive_hud,"authored HUD selected")
		var authority: Dictionary = s.state.duplicate(true)
		if fixture.label=="card-custom": await card_stress(app)
		var battle: Dictionary = s.state.extensions[Battle.KEY]
		var authored_placement: Dictionary = Placement.for_encounter(s.package.world,battle.encounter_id)
		check(battle.party.size() == int(fixture.count),"authored party count")
		for size in [Vector2i(720,720),Vector2i(960,720),Vector2i(1120,700),Vector2i(1120,630),Vector2i(1120,480)]:
			root.size = size; await settle(); root.grab_focus(); await settle(); await RenderingServer.frame_post_draw
			check(s.state == authority,"resize keeps authority")
			var hud = app.dream_hud
			var placement: Dictionary = Placement.select_layout(authored_placement,hud.size)
			check(root.size==size,"actual content window matches requested aspect")
			if not placement.is_empty():
				check(hud.boxes.variant_id==Placement.selected_variant(authored_placement,hud.size).get("id","default"),"all render consumers select from the unreserved logical stage")
			if fixture.label=="aspect-defaults":
				var expected_variant: String = {720:"default",960:"layout.standard",700:"layout.wide",630:"layout.wide",480:"layout.ultrawide"}[size.x if size.x<1120 else size.y]
				check(hud.boxes.variant_id==expected_variant,"default actual windows keep square stacked, 4:3 and 16:9 bottom, 21:9 right")
			check(view.presentation_rect(view.size).is_equal_approx(hud.boxes.content),"actors and HUD use the same content rectangle including origin")
			if not placement.is_empty():
				var expected = Rect2(hud.size*Vector2(placement.content_region.x,placement.content_region.y)/100,hud.size*Vector2(placement.content_region.width,placement.content_region.height)/100)
				check(hud.boxes.content.is_equal_approx(expected),"authored content region follows viewport percentage")
				check(expected.grow(.01).encloses(view.classic_stage),"actor stage follows reserved region origin")
			for button in app.dream_hud.commands.get_children():
				check(button.get_rect().is_equal_approx(app.dream_hud.boxes.commands[button.symbol]),"resized root command "+button.symbol)
			for id in battle.party:
				var card: Dictionary = app.dream_hud.cards[id]
				check(card.instance_id == id and card.hp == s.entity(id).hp and card.mp == s.entity(id).mp,"HUD reads stable instance")
				if placement.is_empty(): check(not hud.boxes.content.intersects(card.panel_rect),"HUD reserved space")
				else:
					var region = Rect2(hud.size*Vector2(placement.cards_region.x,placement.cards_region.y)/100,hud.size*Vector2(placement.cards_region.width,placement.cards_region.height)/100)
					check(region.grow(.01).encloses(card.panel_rect),"card stays within freely placed group")
					check(card.panel_rect.grow(.01).encloses(card.face_rect),"portrait fits resized card")
					for table in placement.slots_by_count:
						if table.count == battle.party.size():
							var authored: Dictionary = table.slots[battle.party.find(id)]
							var exact = Rect2(region.position+region.size*Vector2(authored.x,authored.y)/100,region.size*Vector2(authored.width,authored.height)/100)
							check(card.panel_rect.is_equal_approx(exact),"manual card follows current seat rectangle")
			var conflicts: Array = []
			verify_card_elements(app)
			if fixture.get("aspect_defaults",false):
				for side in ["enemy","party"]:
					conflicts.append_array(view.formation_diagnostics[side].conflicts)
					check(view.formation_diagnostics[side].conflicts.is_empty(),"automatic "+side+" group keeps all-action occupied bounds within its region")
				for enemy in view.formation_diagnostics.enemy.occupied.values():
					for party in view.formation_diagnostics.party.occupied.values(): check(not enemy.intersects(party),"five-boss defaults leave the opposing side separate")
			# Exercise the root command and target/cancel mapping at each actual size.
			await click(option(app,"攻击",true)); check(not app.classic_root,"resized attack command opens targets")
			await key(KEY_ESCAPE); check(app.classic_root and s.state==authority,"resized target cancel preserves authority")
			var path = output.path_join(fixture.label+"-%dx%d.png" % [size.x,size.y])
			root.get_texture().get_image().save_png(path)
			windows.append({"path":path,"package_path":package_path,"requested_window":[size.x,size.y],"actual_window":[root.size.x,root.size.y],"logical_root":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"logical_stage":[hud.size.x,hud.size.y],"render_pixels":[app.viewport.size.x,app.viewport.size.y],"variant_id":hud.boxes.get("variant_id","old-hud"),"group_conflicts":conflicts})
		root.size = Vector2i(1280,800); await settle(); root.grab_focus(); await settle()
		var initial: String = save(app,"initial-"+fixture.label)
		check(not s.state.extensions.has(Placement.KEY),"placement does not become saved authority")
		check(not s.state.extensions.has(PartyCard.KEY),"card elements do not become saved authority")
		var actor: Dictionary = s.entity(battle.party[battle.turn])
		var all_targets: bool = Battle.PlayerPhysical.all_targets(s.package.world,actor.definition_id)
		var target_label: String = "攻击全体" if all_targets else "攻击 2"
		var expected_ids: Array = Battle.PlayerPhysical.order(s.package.world,battle.encounter_id) if all_targets else [battle.enemies[1].instance_id]
		await click(option(app,"攻击",true)); var target = option(app,target_label)
		if target == null: finish(); return
		target.grab_focus(); await settle(); check(view.target_ids == expected_ids,"target focus uses authored enemy identities")
		await key(KEY_ESCAPE); check(app.classic_root and s.state == authority,"cancel leaves state unchanged")
		await click(option(app,"攻击",true)); target = option(app,target_label)
		s.set_pause(true,s._last_usec); await settle()
		var paused_state: Dictionary = s.state.duplicate(true)
		await click(option(app,target_label)); check(s.state == paused_state,"paused routed click cannot commit")
		s.set_pause(false,s._last_usec); await settle(); await click(option(app,target_label))
		check(view.playing(),"routed target starts playback")
		var committed: Dictionary = s.state.duplicate(true)
		check(app.dream_hud.visible and not app.dream_hud.commands.visible,"status overlay stays visible while commands hide")
		for delta in [1.0/60,1.0/144]: view._process(delta)
		await settle(); check(s.state == committed,"display clocks do not recommit")
		verify_card_elements(app)
		for id in view.presentation.actors:
			if app.dream_hud.cards.has(id): check(app.dream_hud.cards[id].hp == view.presentation.actors[id].hp,"HUD follows playback snapshot")
		view.skip(); await settle(); save(app,"after-action-"+fixture.label)
		check(app.saves.load_into(s,initial),"save restores initial command phase"); await settle()
		check(app.classic_root and app.dream_hud.cards.size() == int(fixture.count),"restore rebuilds HUD and root commands")
		await click(option(app,"其他",true)); await click(option(app,"防御",true)); view.skip(); await settle()
		check(s.entity(s.state.extensions[Battle.KEY].party[s.state.extensions[Battle.KEY].turn]).instance_id != actor.instance_id,"normal guard advances to next member")
		await click(option(app,"攻击",true)); target = option(app,"攻击 2")
		if target == null: finish(); return
		target.grab_focus(); await settle(); check(view.target_ids == [s.state.extensions[Battle.KEY].enemies[1].instance_id],"second member single target identity")
		await key(KEY_ESCAPE)
		root.remove_child(app); app.queue_free(); await process_frame
	finish()
func verify_card_elements(app) -> void:
	var hud = app.dream_hud; var view = app.battle_view
	var profile: Dictionary = PartyCard.for_encounter(app.session.package.world,view.display_battle().encounter_id)
	var expected_count: int = 0
	for id in hud.cards:
		var snapshot: Dictionary = hud.cards[id]
		var actor: Dictionary = view.presentation.actors[id] if view.playing() else app.session.entity(id)
		var expected: Array = PartyCard.elements(profile,actor.definition_id)
		check(snapshot.elements==expected,"card element selection is character-bound")
		for element in expected:
			var node = hud.element_nodes[id+"|"+element.id]
			check(node.get_index()==expected_count,"card draw order follows the authored list")
			expected_count+=1
			check(node.mouse_filter==Control.MOUSE_FILTER_IGNORE,"decorative card element never intercepts commands")
			check(node.get_rect().is_equal_approx(PartyCard.rectangle(element,snapshot.panel_rect)),"individual rectangle follows actual card parent")
			check(node.visible==element.visible and snapshot.panel_rect.grow(.01).encloses(node.get_rect()),"element visibility and bounds")
			check(node.snapshot.hp==actor.hp and node.snapshot.mp==actor.mp,"element consumes the same displayed actor snapshot")
			if not node.visible: continue
			if element.kind=="text" and node.rendered_font_size>0:
				var font: Font = node.get_theme_font("font")
				check(font.get_string_size(node.rendered_text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.rendered_font_size).x<=node.size.x*node.TEXT_RESOLUTION+.01,"rendered text stays within element width")
				check(font.get_height(node.rendered_font_size)<=node.size.y*node.TEXT_RESOLUTION+.01 or node.rendered_font_size==1,"text height is bounded or minimally clipped")
			if element.kind=="bar": check(node.rendered_fill.is_equal_approx(PartyCard.fill_rect(Rect2(Vector2.ZERO,node.size),PartyCard.fraction(element,snapshot),element.direction)),"bar fill uses displayed values and authored direction")
	check(hud.element_nodes.size()==expected_count and hud.element_layer.get_child_count()==expected_count,"no leaked or stale card nodes")
	var nodes: Dictionary = {}
	for key in hud.element_nodes: nodes[key]=hud.element_nodes[key].get_instance_id()
	for i in range(3): hud.bind(view)
	for key in nodes: check(hud.element_nodes[key].get_instance_id()==nodes[key],"unchanged cards reuse existing draw nodes")
func card_stress(app) -> void:
	# Synthetic display values only, on a separate GPU surface. Never feed them to gameplay.
	var authority: Dictionary = app.session.state.duplicate(true)
	var profile: Dictionary = PartyCard.for_encounter(app.session.package.world,app.battle_view.display_battle().encounter_id)
	var viewport=SubViewport.new(); viewport.size=Vector2i(640,300); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var background=ColorRect.new(); background.color=Color("161b16"); background.size=viewport.size; viewport.add_child(background)
	var nodes: Array = []
	var areas=[Rect2(12,30,292,75),Rect2(324,30,300,75),Rect2(12,150,100,100),Rect2(132,150,492,100)]
	for i in range(4):
		var snapshot: Dictionary = app.dream_hud.cards.values()[0].duplicate(true)
		snapshot.panel_rect=areas[i]; snapshot.name="很长的人物名称与组合文字 é 中文 Long Name".repeat(4)
		snapshot.hp=[999999999,0,100,75][i]; snapshot.mp=[0,0,100,0][i]
		snapshot.stats={"max_hp":[3999999996,0,100,100][i],"max_mp":[0,0,100,0][i]}
		for original in profile.elements:
			var element: Dictionary = original.duplicate(true)
			if element.kind=="bar": element.direction=["left-to-right","right-to-left","top-to-bottom","bottom-to-top"][i]
			var node=CardElement.new(); background.add_child(node); node.add_theme_font_override("font",app.battle_view.display_font)
			node.bind(app.session.package,element,snapshot,i==0,CanvasItem.TEXTURE_FILTER_NEAREST); nodes.append(node)
	await settle(); await RenderingServer.frame_post_draw
	for node in nodes:
		var element: Dictionary = node.element
		check(node.clip_contents and node.mouse_filter==Control.MOUSE_FILTER_IGNORE,"stress elements remain clipped and non-interactive")
		if element.kind=="text":
			var font: Font=node.get_theme_font("font")
			check(font.get_string_size(node.rendered_text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.rendered_font_size).x<=node.size.x*node.TEXT_RESOLUTION+.01,"long names and large values remain within their own text rectangle")
			check(not "\n" in node.rendered_text,"stress text is single line")
		if element.kind=="bar":
			check(node.rendered_fill.is_equal_approx(PartyCard.fill_rect(Rect2(Vector2.ZERO,node.size),PartyCard.fraction(element,node.snapshot),element.direction)),"stress zero maxima and four fill directions match the displayed snapshot")
	viewport.get_texture().get_image().save_png(output.path_join("party-card-stress.png"))
	check(app.session.state==authority,"synthetic rendering stress cannot alter authority")
	root.remove_child(viewport); viewport.queue_free(); await process_frame
func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down; root.push_input(event,true)
	await settle()
func finish() -> void:
	var report = {"success":failed==0,"checks":checks,"failed":failed,"saves":saves,"windows":windows,"engine_injected_input":true,"physical_input":false,"full_playthrough":false,"art_acceptance":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("responsive HUD checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
