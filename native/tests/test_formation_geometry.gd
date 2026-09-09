# SPDX-License-Identifier: MIT
extends SceneTree
const Formation = preload("res://src/native_battle_formation.gd")
const Overlay = preload("res://src/native_enemy_overlay.gd")
var checks: int = 0
var errors: Array = []
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:errors.append(label)
func _initialize() -> void:
	var group: Dictionary = {"region":{"x":0,"y":0,"width":100,"height":100},"offset":{"x":0,"y":0},"scale_milli":1000,"gap":5,"separate_overlaps":true,"fit":"contain","pattern":"diagonal.v1"}
	for side in range(2):
		for count in [1,2,3,4,5,16]:
			var entries: Array = []
			for i in range(count):entries.append({"id":"instance."+str(i),"extent":Rect2(-12-i*5,-25-i*9,24+i*10,27+i*9)})
			var result: Dictionary = Formation.arrange(group,entries,Vector2(320,200),side)
			check(result.anchors.size()==count,"each instance has one anchor")
			check(result.fit>0 and result.fit<=1,"one positive shared fit")
			for i in range(count):
				var id: String = entries[i].id
				check(result.region.grow(.01).encloses(result.occupied[id]),"whole visible range inside group region")
				check(result.occupied[id].size.is_equal_approx(entries[i].extent.size*result.fit),"relative sizes preserved")
	group.fit="none";group.separate_overlaps=false;group.offset={"x":12,"y":7}
	group.positions=[{"instance_id":"a","x":20,"y":70},{"instance_id":"b","x":60,"y":30}]
	var entries: Array = [{"id":"a","extent":Rect2(-10,-30,20,30)},{"id":"b","extent":Rect2(-20,-40,40,40)}]
	var first: Dictionary = Formation.arrange(group,entries,Vector2(320,200),0)
	entries.reverse();var reordered: Dictionary = Formation.arrange(group,entries,Vector2(320,200),0)
	check(first.anchors==reordered.anchors,"enemy reordering preserves authored instance anchors")
	check(first.anchors.a.is_equal_approx(Vector2(76,147)),"whole-group offset uses reference units")
	check(first.fit==1,"explicit no-fit keeps chosen scale")
	group.slots_by_count=[{"count":2,"slots":[{"x":20,"y":70},{"x":60,"y":30}]}]
	var party: Dictionary = Formation.arrange(group,entries,Vector2(320,200),1)
	check(party.anchors.b==first.anchors.a,"party points follow current party slots, not definition IDs")
	var profile: Dictionary = {"bar_width":28,"bar_height":2,"font_size":7,"show_name":false,"value_format":"current","placement":"above-body","offset":{"x":0,"y":-3},"visibility":"always"}
	var rect: Rect2 = Overlay.measure(profile,Rect2(-10,-30,20,30))
	check(rect.end.y==-33 and rect.size.x==28,"HP bar reserves space above full visible range")
	profile.visibility="hidden";check(Overlay.measure(profile,Rect2(-10,-30,20,30))==rect,"visibility does not change reserved space")
	profile.placement="below-body";check(Overlay.measure(profile,Rect2(-10,-30,20,30)).position.y==-3,"below-body placement is explicit")
	profile.overrides=[{"instance_id":"b","offset":{"x":-8,"y":-3},"bar_width":32}]
	check(Overlay.for_actor(profile,"a").bar_width==28 and Overlay.for_actor(profile,"b").bar_width==32,"per-instance width follows ID")
	var canvas=Rect2(0,0,320,200)
	for requested in [Rect2(10,-30,28,13),Rect2(300,198,32,13),Rect2(-1,-1,640,400)]:
		var placed: Dictionary = Overlay.place(requested,canvas,true)
		check(canvas.encloses(placed.rect),"blood bar including text stays in canvas")
		check(Overlay.place(requested,canvas,false).rect==requested,"author can explicitly allow off-canvas overlays")
	for region in [canvas,Rect2(0,0,32,20)]:
		var extent=Rect2(-60,-80,120,80)
		var fit: float = minf(1,minf(region.size.x/extent.size.x,region.size.y/extent.size.y))
		extent=Rect2(extent.position*fit,extent.size*fit)
		for target in [Vector2(-18,-8),Vector2(5,20),Vector2(500,400)]:
			var at: Vector2 = Formation.motion_anchor(target,extent,region)
			check(region.grow(.01).encloses(Rect2(at+extent.position,extent.size)),"large coverer and attack movement use their own full fitted extent")
	var view=load("res://src/native_battle_view.gd").new()
	var raster=Image.create(8,8,false,Image.FORMAT_RGBA8);raster.fill(Color.WHITE)
	var clip: Dictionary = {"action":"idle","facing":"lower_right","frames":[{"asset_id":"tiny","anchor":{"x":4,"y":8},"scale_milli":1000}]}
	view.session={"state":{"extensions":{"pal.native.battle":{"encounter_id":"test"}}},"package":{"world":{"extensions":{"pal.native.battle-layout":{"encounters":[{"encounter_id":"test","layout_id":"layout.test"}],"layouts":[{"id":"layout.test","sprite_scale_milli":500}]}}},"index":{"battle_sprite_sets":{"tiny":{"clips":[clip],"missing_action":"static"}}},"textures":{"tiny":ImageTexture.create_from_image(raster)}}}
	var visible: Rect2 = view._visible_extent({"battle_sprite_set":"tiny"},0)
	check(visible.encloses(Rect2(-24,-80,48,80)),"all-action alpha union includes actual static fallback divided by classic scale")
	check(view._frame_contact(clip.frames[0])==Vector2.ZERO,"opaque sprite contact follows bottom-row pixels and anchor")
	profile.show_name=true;var font: Font = ThemeDB.fallback_font
	var size: Vector2 = Overlay.measure(profile,Rect2(-1,-10,2,10),font).size*.5
	var placed: Dictionary = Overlay.place(Rect2(Vector2(300,199),size),canvas,true)
	var measured: Dictionary = Overlay.metrics(profile,font)
	check(is_equal_approx(measured.height*.5,placed.rect.size.y) and placed.rect.end.y<=canvas.end.y,"two text lines at half scale paint the same bottom edge used by clamping")
	var shadow: Dictionary = Formation.shadow_for(group,"a",0,2,0)
	check(shadow.enabled and shadow.height<shadow.width,"new formation defaults to translucent flat shadows")
	group.positions[0].shadow=shadow.duplicate(true);group.positions[0].shadow.enabled=false
	check(not Formation.shadow_for(group,"a",1,2,0).enabled and Formation.shadow_for(group,"b",0,2,0).enabled,"shadow overrides stay on enemy ID after reorder")
	view.free()
	print(JSON.stringify({"success":errors.is_empty(),"checks":checks,"errors":errors,"evidence":"synthetic rectangles and identity mapping only"}))
	quit(0 if errors.is_empty() else 1)
