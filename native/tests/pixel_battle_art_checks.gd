# SPDX-License-Identifier: MIT
extends RefCounted
## Optional generated-art evidence over the existing five-person story fixture.
## Recipe paths are test input only; runtime never reads this recipe format.
const Battle = preload("res://src/native_battle.gd")
const Classic = preload("res://src/native_classic_battle.gd")

static func exercise(test, app, spec: Dictionary, initial: String) -> Dictionary:
	var s = app.session; var view = app.battle_view; var package = s.package
	var report: Dictionary = {"diagnostic_frames":[],"normal_attacks":[],"bound_frames":0,"visual_acceptance":false}
	var recipes: Dictionary = {}; var unique_recipes: Dictionary = {}
	var unique_pngs: Dictionary = {}; var party: Array = s.state.active_party.duplicate()
	var actual_ids: Array = spec.actors.map(func(entry): return entry.definition_id)
	var expected_ids: Array = ["hero","fist","fist-b","camp-guard","spear"].map(func(id): return "actor.miaopang.camp."+id)
	var party_ids: Array = party.map(func(id): return s.entity(id).definition_id)
	actual_ids.sort(); expected_ids.sort(); party_ids.sort()
	test.check(actual_ids == expected_ids and party_ids == expected_ids,"pixel mode binds the exact five current party definitions")
	if actual_ids != expected_ids or party_ids != expected_ids: return report
	for entry in spec.actors:
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.recipe_path))
		test.check(FileAccess.get_sha256(entry.recipe_path) == entry.recipe_sha256,"runtime pinned art recipe "+entry.definition_id)
		recipes[entry.definition_id] = recipe
		var definition: Dictionary = package.index.actor_definitions[entry.definition_id]
		var sprite: Dictionary = package.index.battle_sprite_sets[definition.battle_sprite_set]
		test.check(sprite.clips.size() == 11 and sprite.missing_action == "error","complete explicit pixel action set "+entry.definition_id)
		for clip in sprite.clips:
			var poses: Array = poses_for(clip.action)
			test.check(clip.facing == "upper_left" and clip.frames.size() == poses.size(),"pixel clip order and facing "+entry.definition_id+" "+clip.action)
			for i in range(poses.size()):
				var expected: Dictionary = recipe.frames.filter(func(f): return f.action_pose == poses[i])[0]
				var frame: Dictionary = clip.frames[i]
				unique_pngs[expected.sha256] = true
				test.check(package.index.assets[frame.asset_id].sha256 == expected.sha256,"pixel PNG bytes "+entry.definition_id+" "+poses[i])
				test.check(frame.width == expected.width and frame.height == expected.height and frame.anchor.x == expected.anchor[0] and frame.anchor.y == expected.anchor[1] and frame.scale_milli == expected.scale_milli and frame.duration_us == expected.duration_us,"pixel geometry and time "+entry.definition_id+" "+poses[i])
				test.check(test.image_hash(package.textures[frame.asset_id].get_image()) == expected.rgba_sha256,"pixel texture alpha and all visible RGB "+entry.definition_id+" "+poses[i])
				report.bound_frames += 1
		unique_recipes[entry.recipe_sha256] = entry.definition_id
	test.check(unique_recipes.size() == 3 and unique_pngs.size() == 48 and report.bound_frames == 80,"three recipes bind forty-eight unique PNGs to eighty actor frames")
	# The 48 pose draws below are diagnostics, not invented skill/sleep events.
	for definition_id in unique_recipes.values():
		var member: String = party.filter(func(id): return s.entity(id).definition_id == definition_id)[0]
		var before: Dictionary = s.state.duplicate(true)
		var definition: Dictionary = package.index.actor_definitions[definition_id]
		var sprite: Dictionary = package.index.battle_sprite_sets[definition.battle_sprite_set]
		for clip in sprite.clips:
			var duration: int = 0
			for frame in clip.frames: duration += int(frame.duration_us)
			view.present_committed(before,before.extensions[Battle.KEY],"")
			view.presentation.phases = [{"actor_id":member,"action":clip.action,"event":{},"event_index":-1,"duration_us":duration}]
			view.presentation.phase_index = 0; view.presentation.active = true
			var elapsed: int = 0
			for frame in clip.frames:
				view.presentation.elapsed_us = elapsed+1; app._refresh(); view.queue_redraw()
				await RenderingServer.frame_post_draw
				var actual: Dictionary = view.displayed_frames[member]
				test.check(actual.asset_id == frame.asset_id and not actual.fallback,"draw exact authored pixel pose "+definition_id+" "+clip.action+" "+str(elapsed))
				var foot: Vector2 = Classic.party_anchor(party.find(member),party.size())
				if clip.action == "attack": foot += Vector2(-18,-8)*sin(PI*(elapsed+1)/duration)
				test.check(actual.anchor.is_equal_approx(view.projection*foot),"pixel foot shares Dream projection "+definition_id+" "+clip.action+" "+str(elapsed))
				var factor: float = float(frame.scale_milli)/1000.0*float(view.classic_layout().sprite_scale_milli)/1000.0
				test.check((actual.rect.size/view.projection.x.x).is_equal_approx(Vector2(frame.width,frame.height)*factor),"authored pixel scale is not overridden "+definition_id+" "+clip.action+" "+str(elapsed))
				var capture: Image = test.root.get_texture().get_image()
				var path: String = test.output.path_join("pixel-pose-%02d.png" % report.diagnostic_frames.size())
				test.check(capture.save_png(path) == OK,"pixel pose screenshot saved "+str(report.diagnostic_frames.size()))
				var visibility: Dictionary = await visible_pixels(test,view,package,frame,actual)
				report.diagnostic_frames.append({"instance_id":member,"action":clip.action,"asset_sha256":package.index.assets[frame.asset_id].sha256,"capture":path,"pixels_sha256":test.image_hash(capture),"visibility":visibility})
				elapsed += int(frame.duration_us)
			view.skip(); await test.settle()
			test.check(s.state == before,"diagnostic pose changes no authoritative state "+definition_id+" "+clip.action)
	# Restore and issue real commands for every roster seat, retaining rules.
	for index in range(party.size()):
		test.check(app.saves.load_into(s,initial),"restore before pixel actor "+str(index)); await test.settle()
		for advance in range(index):
			test.check(s.battle_command("guard"),"normal guard advances to pixel actor "+str(index)); view.skip(); await test.settle()
		var member: String = party[index]
		test.check(s.state.extensions[Battle.KEY].turn == index,"correct authoritative actor turn "+str(index))
		var before_command: Dictionary = s.state.duplicate(true)
		var target_id: String = before_command.extensions[Battle.KEY].enemies[0].instance_id
		await test.click(test.option(app,"攻击",true)); await test.click(test.option(app,"攻击 1"))
		var committed: Dictionary = s.state.duplicate(true); var seen: Array = []; var steps: int = 0
		var committed_battle: Dictionary = committed.extensions[Battle.KEY]
		test.check(committed_battle.step == before_command.extensions[Battle.KEY].step+1 and committed_battle.events.any(func(event): return event.kind == "attack" and event.source == member and event.target == target_id),"one normal attack transaction for the selected member and enemy "+str(index))
		while view.playing() and steps < 400:
			view.queue_redraw(); await RenderingServer.frame_post_draw
			var actual: Dictionary = view.displayed_frames.get(member,{})
			if actual.get("action") == "attack":
				var digest: String = package.index.assets[actual.asset_id].sha256
				if seen.is_empty() or seen[-1] != digest: seen.append(digest)
				if seen.size() == 2 and not FileAccess.file_exists(test.output.path_join("pixel-attack-"+str(index)+".png")):
					test.check(test.root.get_texture().get_image().save_png(test.output.path_join("pixel-attack-"+str(index)+".png")) == OK,"normal attack screenshot saved "+str(index))
			view._process(.03); steps += 1
		var expected: Array = []
		for pose in poses_for("attack"):
			expected.append(recipes[s.entity(member).definition_id].frames.filter(func(f): return f.action_pose == pose)[0].sha256)
		test.check(seen == expected,"normal actor command renders anticipation contact recovery "+str(index))
		test.check(not view.playing() and s.state == committed,"normal pixel action ends without double settlement "+str(index))
		report.normal_attacks.append({"instance_id":member,"target_id":target_id,"frames":seen,"steps":steps,"battle_step":committed_battle.step})
		test.save(app,"pixel-actor-"+str(index))
	test.check(app.saves.load_into(s,initial),"restore after pixel diagnostics and normal commands"); await test.settle()
	view.queue_redraw(); await RenderingServer.frame_post_draw
	test.check(test.root.get_texture().get_image().save_png(test.output.path_join("pixel-party-idle.png")) == OK,"five-person idle screenshot saved")
	test.check(report.bound_frames == 80 and report.diagnostic_frames.size() == 48 and report.normal_attacks.size() == 5,"pixel mode completes all bindings, diagnostic visibility and normal attacks")
	return report

static func visible_pixels(test, view, package, frame: Dictionary, actual: Dictionary) -> Dictionary:
	# Diagnostic A/B of the actual battle SubViewport, with clock/state held.
	# Only the already-loaded texture is masked; source bytes and game state stay intact.
	var texture: Texture2D = package.textures[frame.asset_id]
	var source: Image = texture.get_image()
	var used: Rect2i = source.get_used_rect()
	test.check(used.has_area(),"pixel pose contains nontransparent pixels "+frame.frame_id)
	var scale: Vector2 = actual.rect.size/Vector2(source.get_size())
	var glyph: Rect2 = Rect2(actual.rect.position+Vector2(used.position)*scale,Vector2(used.size)*scale)
	var viewport = view.get_viewport()
	var before: Image = viewport.get_texture().get_image()
	var visible: Rect2 = glyph.intersection(view.classic_stage).intersection(Rect2(Vector2.ZERO,Vector2(before.get_size())))
	test.check(visible.has_area(),"pixel pose silhouette intersects the visible battle stage "+frame.frame_id)
	if not visible.has_area(): return {"changed_pixels":0}
	var area: Rect2i = Rect2i(Vector2i(visible.position.floor()),Vector2i(visible.end.ceil()-visible.position.floor()))
	area = area.intersection(Rect2i(Vector2i.ZERO,before.get_size()))
	var blank: Image = Image.create(source.get_width(),source.get_height(),false,Image.FORMAT_RGBA8)
	blank.fill(Color.TRANSPARENT)
	package.textures[frame.asset_id] = ImageTexture.create_from_image(blank)
	view.queue_redraw(); await RenderingServer.frame_post_draw
	var masked: Image = viewport.get_texture().get_image()
	package.textures[frame.asset_id] = texture
	view.queue_redraw(); await RenderingServer.frame_post_draw
	var restored: Image = viewport.get_texture().get_image()
	var a: Image = before.get_region(area); a.convert(Image.FORMAT_RGBA8)
	var b: Image = masked.get_region(area); b.convert(Image.FORMAT_RGBA8)
	var c: Image = restored.get_region(area); c.convert(Image.FORMAT_RGBA8)
	var a_bytes: PackedByteArray = a.get_data(); var b_bytes: PackedByteArray = b.get_data()
	var changed: int = 0
	for i in range(0,a_bytes.size(),4):
		if a_bytes[i] != b_bytes[i] or a_bytes[i+1] != b_bytes[i+1] or a_bytes[i+2] != b_bytes[i+2] or a_bytes[i+3] != b_bytes[i+3]: changed += 1
	test.check(changed > 0,"pixel pose actually affects the rendered actor region "+frame.frame_id)
	test.check(a_bytes == c.get_data(),"restoring the texture restores exact visible pixels "+frame.frame_id)
	return {"changed_pixels":changed,"region":[area.position.x,area.position.y,area.size.x,area.size.y],"before_sha256":test.image_hash(a),"masked_sha256":test.image_hash(b),"restored_sha256":test.image_hash(c)}

static func poses_for(action: String) -> Array:
	match action:
		"idle": return ["idle-a","idle-b"]
		"attack": return ["attack-anticipation","attack-contact","attack-recovery"]
		"cast": return ["cast-gather","cast-release"]
		"escape": return ["escape-a","escape-b"]
	return [action]
