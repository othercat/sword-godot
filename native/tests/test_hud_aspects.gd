# SPDX-License-Identifier: MIT
extends SceneTree
const Hud = preload("res://src/native_battle_hud_config.gd")
const Placement = preload("res://src/native_hud_placement.gd")
var errors: Array = []
var checks: int = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: errors.append(label)
func _initialize() -> void:
	var style: Dictionary = {"dock":"bottom","max_columns":5,"card_width":240,"min_card_width":170,"card_height":64,"margin":12,"gap":8,"command_size":40,"reserve_space":true}
	var fallback: Dictionary = {"cards_region":{"x":0,"y":70,"width":100,"height":30},"content_region":{"x":0,"y":0,"width":100,"height":70},"max_columns":3,"slots_by_count":[]}
	var bottom: Dictionary = {"cards_region":{"x":0,"y":80,"width":100,"height":20},"content_region":{"x":0,"y":0,"width":100,"height":80},"max_columns":5,"slots_by_count":[]}
	var right: Dictionary = {"cards_region":{"x":80,"y":0,"width":20,"height":100},"content_region":{"x":0,"y":0,"width":80,"height":100},"max_columns":1,"slots_by_count":[]}
	var profile: Dictionary = fallback.duplicate(true)
	profile.variants = [{"id":"layout.standard","display_name":"Standard","min_aspect":{"width":6,"height":5},"layout":bottom},{"id":"layout.ultrawide","display_name":"Ultrawide","min_aspect":{"width":2,"height":1},"layout":right}]
	var before: Dictionary = profile.duplicate(true)
	for sample in [[1000,1000,"default"],[1200,900,"layout.standard"],[1280,800,"layout.standard"],[1280,720,"layout.standard"],[1680,720,"layout.ultrawide"],[119999,100000,"default"],[6,5,"layout.standard"],[120001,100000,"layout.standard"],[199999,100000,"layout.standard"],[2,1,"layout.ultrawide"],[200001,100000,"layout.ultrawide"]]:
		var bounds = Vector2(sample[0],sample[1])
		for count in [1,3,4,5,16]:
			var result: Dictionary = Hud.geometry(style,bounds,count,profile)
			check(result.variant_id == sample[2],"inclusive stage threshold " + str(sample))
			check(result.cards.size() == count,"complete card count")
			for card in result.cards:
				check(result.region.grow(.001).encloses(card),"selected region contains cards")
				check(not result.content.intersects(card),"selected actor canvas avoids cards")
			for command in result.commands.values(): check(result.content.grow(.001).encloses(command),"commands share selected actor canvas")
		check(profile==before,"selection and geometry do not mutate content")
	check(Placement.selected_variant(profile,Vector2(2100,900)).id=="layout.ultrawide","no feedback selection from chosen content width")
	check(Hud.geometry(style,Vector2(1680,720),5,fallback).variant_id=="default","v1 fallback unchanged")
	profile.variants=[]
	check(Hud.geometry(style,Vector2(1680,720),5,profile)==Hud.geometry(style,Vector2(1680,720),5,fallback),"empty variants preserve fallback geometry")
	print(JSON.stringify({"success":errors.is_empty(),"checks":checks,"errors":errors,"evidence":"synthetic aspect geometry, not physical windows or art"}))
	quit(0 if errors.is_empty() else 1)
