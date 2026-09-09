# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const E = preload("res://src/native_enemy_physical.gd")
var checks: Array = []
var failed: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	var package = Package.new(); check(package.load_package(args[0]),"package admission: "+package.error)
	if not package.error.is_empty(): quit(1); return
	var session = Session.new(); check(session.activate(package),"new session: "+session.error)
	var budget: int = 0
	while not session.battle_open() and budget < 30:
		var node: Dictionary = session.current_node(); var chosen: String = ""
		if node.op == "choice":
			var choices: Array = node.options.filter(func(o): return str(o.text).contains("五人"))
			chosen = (choices[0] if not choices.is_empty() else node.options[0]).id
		if node.op not in ["dialogue","choice"]: break
		check(session.advance_dialogue(chosen),"enter route "+str(budget)+": "+session.error); budget += 1
	check(session.battle_open(),"authored route enters battle")
	if not session.battle_open(): quit(1); return
	var party: Array = session.state.active_party.duplicate()
	for _i in range(party.size()):
		check(session.battle_command("guard"),"guard command: "+session.error)
		if not session.battle_open(): break
	check(session.battle_open(),"party survives first enemy phase")
	if session.battle_open():
		var value: Dictionary = session.state.extensions[E.KEY].pending
		check(value.commands[-1].enemy_actions.size() > 0 and E.cursor(session.state) > 0,"enemy phase owns logical draws")
		check(session.validate_saved(session.state).is_empty(),"complete enemy phase admits as saved state: "+session.validate_saved(session.state))
		var before: Dictionary = session.state.duplicate(true)
		for defect in ["missing","defense","rng","source","guard","event"]:
			var bad: Dictionary = before.duplicate(true); var command: Dictionary = bad.extensions[E.KEY].pending.commands[-1]
			var action: Dictionary = command.enemy_actions[0]
			match defect:
				"missing": command.enemy_actions.clear()
				"defense": action.party[0].defense += 1
				"rng": action.rng_before += 1
				"source": action.source = "enemy.missing"
				"guard": action.party[0].guarding = not action.party[0].guarding
				"event": command.events[0].amount = 1
			check(not session.restore(bad) and session.state == before,"tamper rollback "+defect)
		var output: String = args[1]; DirAccess.make_dir_recursive_absolute(output)
		var saves = Save.new(output.path_join("saves")); check(saves.save(session),"production save: "+saves.error)
		var fresh = Session.new(); check(fresh.activate(package) and saves.load_into(fresh,saves.last_path),"fresh load reproduces merged history")
		check(fresh.state.entities == session.state.entities and fresh.state.rng == session.state.rng,"restored authority equals continuous state")
		FileAccess.open(output.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(session.state))
		FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"package":args[0],"save":saves.last_path,"synthetic_package":true,"physical_input":false,"full_playthrough":false},"\t"))
	print("enemy physical checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
