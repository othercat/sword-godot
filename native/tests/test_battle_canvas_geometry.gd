# SPDX-License-Identifier: MIT
extends SceneTree
const Canvas = preload("res://src/native_battle_canvas.gd")
var checks: int = 0
var errors: Array = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: errors.append(label)
func _initialize() -> void:
	for bounds in [Vector2(1440,960),Vector2(980,720),Vector2(1680,720)]:
		for source in [Vector2(320,200),Vector2(600,900)]:
			var profile: Dictionary = Canvas.default_profile()
			var full: Dictionary = Canvas.placement(profile,bounds,source)
			check(full.destination == Rect2(Vector2.ZERO,bounds),"default covers whole canvas")
			for fit in ["cover","contain","stretch"]:
				profile.fit = fit; profile.region = {"x":10,"y":15,"width":70,"height":60}
				for alignment in [Vector2.ZERO,Vector2(50,50),Vector2(100,100)]:
					profile.alignment = {"x":alignment.x,"y":alignment.y}
					var result: Dictionary = Canvas.placement(profile,bounds,source)
					var dest: Rect2 = result.destination; var src: Rect2 = result.source
					check(result.canvas.grow(.01).encloses(dest),"paint stays inside authored region")
					check(Rect2(Vector2.ZERO,source).grow(.01).encloses(src),"sampling stays inside source")
					if fit != "contain": check(dest.is_equal_approx(result.canvas),"fill modes cover region")
					if fit != "stretch": check(is_equal_approx(dest.size.x/src.size.x,dest.size.y/src.size.y),"aspect preserved")
	var profile: Dictionary = Canvas.default_profile(); profile.alignment.x=0
	var left: Dictionary = Canvas.placement(profile,Vector2(200,200),Vector2(400,200))
	profile.alignment.x=100
	var right: Dictionary = Canvas.placement(profile,Vector2(200,200),Vector2(400,200))
	check(left.source.position.x==0 and right.source.position.x==200,"alignment chooses crop edge")
	check(Canvas.placement(profile,Vector2.ZERO,Vector2(320,200)).destination.size==Vector2.ZERO,"empty viewport is safe")
	print(JSON.stringify({"success":errors.is_empty(),"checks":checks,"errors":errors,"evidence":"synthetic background rectangles only"}))
	quit(0 if errors.is_empty() else 1)
