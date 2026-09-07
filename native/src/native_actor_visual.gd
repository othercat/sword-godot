# SPDX-License-Identifier: MIT
extends Node2D
const MapAnimation = preload("res://src/native_map_animation.gd")
var sprite: Sprite2D
var fallback: Node2D
var definition: Dictionary
var sprite_set: Dictionary = {}
var textures: Dictionary
var elapsed_us: float = 0.0
var selection: String = ""
var displayed_frame: Dictionary = {}

func bind(actor: Dictionary, package, tile_height: int, color: Color) -> void:
	definition = actor
	textures = package.textures
	if actor.get("map_sprite_set") != null: sprite_set = package.index.sprite_sets[actor.map_sprite_set]
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	if actor.sprite_asset != null:
		var image = Sprite2D.new()
		image.texture = textures[actor.sprite_asset]
		image.scale = Vector2.ONE * (tile_height * 1.3 / image.texture.get_height())
		image.position.y = -tile_height * 0.65
		fallback = image
	else:
		var shape = Polygon2D.new()
		shape.polygon = PackedVector2Array([Vector2(-14, 0), Vector2(-18, -27), Vector2(-10, -38), Vector2(10, -38), Vector2(18, -27), Vector2(14, 0)])
		shape.color = color
		fallback = shape
	add_child(fallback)

func present(item: Dictionary, logic_tick: int, delta: float, running: bool, leader: bool = true) -> void:
	var pose: Dictionary = item.components["pal.native.pose"]
	var action: String = "walk" if int(pose.get("moving_until_tick", 0)) > logic_tick else "idle"
	var key: String = action + "/" + pose.facing
	if key != selection:
		selection = key
		elapsed_us = 0.0
	elif running:
		elapsed_us += maxf(0.0, delta) * 1000000.0
	var clip: Dictionary = {} if sprite_set.is_empty() else MapAnimation.clip_for(sprite_set, action, pose.facing)
	displayed_frame = MapAnimation.frame_at(clip, roundi(elapsed_us))
	if action == "walk" and sprite_set.get("playback", "time") == "pal.walk-phase.v1" and not clip.is_empty():
		var phase: int = int(pose.get("step_phase", 0))
		var order: Array = [0, 1, 0, 2] if leader else [0, 2, 0, 1]
		displayed_frame = clip.frames[order[phase]]
	sprite.visible = not displayed_frame.is_empty()
	fallback.visible = not sprite.visible
	if not sprite.visible: return
	sprite.texture = textures[displayed_frame.asset_id]
	sprite.scale = Vector2.ONE * (float(displayed_frame.scale_milli) / 1000.0)
	# Pixel-edge anchor is measured from the PNG top-left; every frame's foot
	# lands at this node's origin regardless of image size or transparent padding.
	sprite.position = -Vector2(displayed_frame.anchor.x, displayed_frame.anchor.y) * sprite.scale
