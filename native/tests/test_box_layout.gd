# SPDX-License-Identifier: MIT
extends SceneTree
const Box = preload("res://src/native_box_layout.gd")
const Hud = preload("res://src/native_battle_hud_config.gd")
var checks: int = 0
var errors: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: errors.append(label)
func _initialize() -> void:
	var layout: Dictionary = {"dock":"bottom","max_columns":5,"card_width":240,"min_card_width":170,"card_height":64,"margin":12,"gap":8,"command_size":40,"reserve_space":true}
	for bounds in [Vector2(1280,720),Vector2(960,540),Vector2(640,360),Vector2(1920,1080)]:
		for count in [1,2,3,4,5,8,16]:
			for dock in ["bottom","right"]:
				layout.dock = dock
				var saved: Dictionary = layout.duplicate(true)
				var geometry: Dictionary = Hud.geometry(layout,bounds,count)
				check(layout == saved,"layout remains data")
				check(geometry.cards.size() == count,"one rectangle per identity")
				for i in range(count):
					var rect: Rect2 = geometry.cards[i]
					check(Rect2(Vector2.ZERO,bounds).grow(.01).encloses(rect),"card inside viewport")
					check(not geometry.content.intersects(rect),"reserved content does not cover HUD")
					for j in range(i): check(not rect.intersects(geometry.cards[j]),"cards do not overlap")
				for command in geometry.commands.values():
					check(Rect2(Vector2.ZERO,bounds).grow(.01).encloses(command),"command inside viewport")
					for card in geometry.cards: check(not command.intersects(card),"commands do not cover cards")
				layout.reserve_space = false
				check(Hud.geometry(layout,bounds,count).content == Rect2(Vector2.ZERO,bounds),"overlay keeps content bounds")
				layout.reserve_space = true
	var extents: Array = [Rect2(-40,-100,80,100),Rect2(130,-180,211,139),Rect2(70,10,64,83)]
	for bounds in [Vector2(640,360),Vector2(1280,720),Vector2(800,1200)]:
		for region_data in [{"x":0,"y":0,"width":25,"height":100},{"x":0,"y":0,"width":100,"height":20},{"x":50,"y":50,"width":.01,"height":.01}]:
			var placement: Dictionary = {"cards_region":region_data,"content_region":{"x":25,"y":10,"width":70,"height":85},"max_columns":1,"slots_by_count":[]}
			for count in [1,3,4,5,16]:
				var before: Dictionary = placement.duplicate(true)
				var placed: Dictionary = Hud.geometry(layout,bounds,count,placement)
				check(placement==before,"authored geometry remains data")
				check(placed.cards.size()==count,"complete authored flow seats")
				for card in placed.cards:
					check(card.size.x>0 and card.size.y>0 and placed.region.grow(.001).encloses(card),"positive bounded cards even in tiny region")
				for command in placed.commands.values(): check(placed.content.grow(.001).encloses(command),"default commands respect shifted content origin")
	var region = Rect2(20,30,240,180)
	var transform: Transform2D = Box.contain_group(extents,region)
	check(is_equal_approx(transform.x.length(),transform.y.length()),"group scaling is uniform")
	for extent in extents: check(region.grow(.01).encloses(transform*extent),"whole group fits")
	check(Box.flow(0,region,Vector2(100,50),80,8,3).is_empty(),"empty group has no phantom box")
	print(JSON.stringify({"success":errors.is_empty(),"checks":checks,"errors":errors,"evidence":"synthetic geometry; not actor or input acceptance"}))
	quit(0 if errors.is_empty() else 1)
