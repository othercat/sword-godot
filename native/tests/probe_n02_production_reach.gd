# SPDX-License-Identifier: MIT
extends SceneTree
## N02 scoping probe: what the formal app's production path can reach with no
## named doubles bound. Diagnostic scope; not Session acceptance.
const ProbeConfig = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const NewGame = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")

class Clock:
	func consume(units: int) -> Dictionary: return {"consumed": units}
class Runtime:
	func answer(request: Dictionary) -> Dictionary: return {"completed": true}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var out = {}
	if args.size() != 2:
		out = {"error": "need package and output args"}
	else:
		var package = Package.new()
		if not package.load_package(args[0]):
			out = {"error": "package rejected: " + str(package.error)}
		else:
			var game = NewGame.new()
			if not game.open(package):
				out = {"error": "open: " + str(game.error)}
			else:
				game.bind_clock(Clock.new()); game.bind_runtime(Runtime.new())
				game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
				var probe: Dictionary = ProbeConfig.configuration()
				var inputs := {"globals": probe.globals, "dialogue": probe.dialogue,
					"party_trail": probe.party_trail, "inventory_bytes": probe.inventory_bytes}
				var state: Dictionary = game.new_state_from_source(0x12345, "explicit_replay", inputs)
				if state.has("error"):
					out = {"error": "initial state: " + str(state.error)}
				else:
					out = {"initial_state": true, "awaiting_player": game.awaiting_player,
						"loaded_map_id": game.state.globals.get("loaded_map_id"),
						"current_scene": game.state.globals.get("current_scene")}
					# Production: no named doubles at all. Begin and record the
					# exact first stop.
					var begun: Dictionary = game.begin()
					out.begin = {"error": str(begun.error) if begun.has("error") else "",
						"completed": begun.get("completed", false),
						"enters": begun.get("enters", [])}
					out.state_after_begin = {"empty": game.state.is_empty(),
						"loaded_map_id": null if game.state.is_empty() else game.state.globals.get("loaded_map_id"),
						"current_scene": null if game.state.is_empty() else game.state.globals.get("current_scene")}
					# If the chain rests, sample one production display tick.
					if not begun.has("error") and begun.get("completed"):
						var ticked: Dictionary = game.tick(PackedInt32Array([0,0,0,0,0,0,0,0,0]), false)
						out.first_tick = {"error": str(ticked.error) if ticked.has("error") else "",
							"input_move": ticked.get("input_move"),
							"world": null if game.state.is_empty() else [game.state.globals.world_x, game.state.globals.world_y]}
					out.pending_after_begin = {"kind": game.pending_kind(), "model": game.pending_model(),
						"dialogue_parked": game.is_dialogue_parked(),
						"has_presentation": game.has_pending_presentation()}
					# Drive the loop as the formal app would: real timer ticks and
					# confirm presses at poll requests. No dialogue surface bound.
					var stops: Array = []
					var confirm_reaches := 0
					for step in range(4000):
						if game.state.is_empty(): break
						var waiting: bool = game.is_dialogue_parked() and not game.has_pending_presentation()
						var levels := PackedInt32Array([0,0,0,0,0,0,0,0,0])
						if waiting and game.pending_model() == "poll_input":
							levels[8] = 2; confirm_reaches += 1
						var ticked: Dictionary = game.tick(levels, true)
						if ticked.has("error"):
							stops.append({"error": str(ticked.error)}); break
						if not game.is_dialogue_parked() and not game.has_pending_presentation():
							stops.append({"resting": true, "step": step}); break
						var kind: String = game.pending_kind()
						if stops.is_empty() or stops.back().get("kind") != kind:
							stops.append({"kind": kind, "model": game.pending_model(), "step": step,
								"presentation": game.has_pending_presentation()})
						if kind == "" and stops.size() > 40: break
					out.loop = {"stops": stops, "confirm_reaches": confirm_reaches,
						"final_awaiting_player": game.awaiting_player,
						"final_scene": null if game.state.is_empty() else game.state.globals.get("current_scene")}
					game.cancel()
	var file = FileAccess.open(args[1] if args.size() > 1 else "user://n02-scope.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "  ") + "\n"); file.close()
	print(JSON.stringify(out))
	quit(0)
