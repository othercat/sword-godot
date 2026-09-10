# SPDX-License-Identifier: MIT
extends SceneTree
const Card = preload("res://src/native_party_card.gd")
const Element = preload("res://src/native_party_card_element.gd")
const Hud = preload("res://src/native_responsive_battle_hud.gd")
var checks: int = 0
var errors: Array = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: errors.append(label)
func _initialize() -> void:
	var bounds=Rect2(100,40,80,20)
	for row in [["left-to-right",Rect2(100,40,20,20)],["right-to-left",Rect2(160,40,20,20)],["top-to-bottom",Rect2(100,40,80,5)],["bottom-to-top",Rect2(100,55,80,5)]]:
		check(Card.fill_rect(bounds,.25,row[0])==row[1],"fill crops in authored direction "+row[0])
		check(Card.fill_rect(bounds,2,row[0])==bounds,"overflow clamps to full")
		check(not Card.fill_rect(bounds,-1,row[0]).has_area(),"negative fill clamps empty")
	var snapshot={"name":"甲\n乙","hp":75,"mp":0,"stats":{"max_hp":100,"max_mp":0}}
	var before: Dictionary = snapshot.duplicate(true)
	var element={"source":"hp","format":"current-max","label":"气血","text":"原样\n文字"}
	check(Card.text(element,snapshot)=="75 / 100","current-max displayed values")
	element.format="labeled"; check(Card.text(element,snapshot)=="气血 75 / 100","author label")
	element.format="percent"; check(Card.text(element,snapshot)=="75%","integer percent")
	element.source="mp"; check(Card.text(element,snapshot)=="0%" and Card.fraction(element,snapshot)==0,"zero maximum is empty")
	element.source="name"; check(Card.text(element,snapshot)=="甲 乙","single-line actor name")
	element.source="literal"; check(Card.text(element,snapshot)=="原样 文字","single-line literal")
	check(snapshot==before,"element presentation does not mutate snapshot")
	element.rect={"x":10,"y":20,"width":30,"height":40}
	check(Card.rectangle(element,Rect2(40,50,200,100))==Rect2(60,70,60,40),"geometry is local to the actual parent origin")
	var profile={"elements":[{"id":"common"}],"overrides":[{"definition_id":"actor.one","elements":[{"id":"custom"}]}]}
	check(Card.elements(profile,"actor.one")[0].id=="custom","definition override independent of seat")
	check(Card.elements(profile,"actor.two")[0].id=="common","other characters inherit common elements")
	print(JSON.stringify({"success":errors.is_empty(),"checks":checks,"errors":errors,"evidence":"headless card geometry and displayed-value checks, not artwork"}))
	quit(0 if errors.is_empty() else 1)
