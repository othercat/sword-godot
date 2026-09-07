# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Condition = preload("res://src/native_condition.gd")
const Save = preload("res://src/native_save.gd")
const Reader = preload("res://src/native_json.gd")
var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok:
		failed += 1
		push_error(label)

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	var package = Package.new()
	check(package.load_package(args[0]), "load actual author condition package: " + package.error)
	if not package.error.is_empty():
		quit(1)
		return
	var node: Dictionary = package.world.nodes.filter(func(n): return n.has("condition"))[0]
	var session = Session.new()
	check(session.activate(package, 0), "activate actual condition package")
	var choice: Dictionary = package.world.nodes[1]
	check(session.advance_dialogue(), "advance to actual choice")
	check(session.advance_dialogue(choice.options[1].id) and session.current_node().op == "end", "false condition follows else")
	check(session.state.committed_effect_ids.is_empty(), "pure false condition has no effects")
	check(session.activate(package, 0) and session.advance_dialogue(), "restart same package")
	check(session.advance_dialogue(choice.options[0].id), "actual set establishes run flag")
	check(session._interact_node(package.world.entry_node) and session.advance_dialogue(), "reenter actual interaction story")
	check(session.advance_dialogue(choice.options[1].id) and session.current_node().id == node.then, "true composite condition follows then")
	check(session.state.committed_effect_ids.size() == 1, "condition never duplicates set effect")
	var accept: Dictionary = package.index.nodes[choice.options[0].next]
	var original_next: String = accept.next
	accept.next = node.id
	check(session.activate(package, 0) and session.advance_dialogue() and session.advance_dialogue(choice.options[0].id), "set then condition completes in one activation")
	check(session.current_node().id == node.then, "condition reads candidate effects, not stale committed state")
	check(session.activate(package, 0) and session.advance_dialogue(), "prepare failed transaction")
	var before: Dictionary = session.snapshot()
	var original: Dictionary = node.condition.duplicate(true)
	node.condition.args[1].arg.variable = "variable.missing"
	check(not session.advance_dialogue(choice.options[0].id) and session.state == before, "invalid condition rolls back preceding set and cursor")
	node.condition = original
	accept.next = original_next
	check(session.advance_dialogue(choice.options[0].id), "retry valid actual choice")
	for scope in ["profile", "run", "chapter"]:
		var id: String = "var.condition." + scope
		var result: Dictionary = Condition.evaluate({"op": "var_ge", "variable": id, "value": 9007199254740991}, package.index.variables, session.state.scopes)
		check(result.get("value", false), "exact maximum from declared " + scope + " scope")
	var vars: Dictionary = {"n": {"type": "integer", "scope": "run"}, "b": {"type": "boolean", "scope": "chapter"}, "s": {"type": "string", "scope": "profile"}}
	var scopes: Dictionary = {"run": {"n": 1}, "chapter": {"b": true}, "profile": {"s": "中文"}}
	for op in ["var_eq", "var_ne", "var_lt", "var_le", "var_gt", "var_ge"]:
		check(Condition.evaluate({"op": op, "variable": "n", "value": 1}, vars, scopes).get("value") == (op in ["var_eq", "var_le", "var_ge"]), "integer operator " + op)
	check(Condition.evaluate({"op": "var_in", "variable": "s", "values": ["中文", "ABC"]}, vars, scopes).get("value", false), "typed set membership")
	check(Condition.evaluate({"op": "var_ne", "variable": "s", "value": "中文 "}, vars, scopes).get("value", false), "string equality preserves whitespace")
	scopes.profile.s = "a".repeat(4097)
	check(Condition.evaluate({"op": "var_ne", "variable": "s", "value": "x"}, vars, scopes).get("value", false), "long declared string state remains comparable")
	check(Condition.evaluate({"op": "var_eq", "variable": "s", "value": scopes.profile.s}, vars, scopes).has("error"), "literal still obeys independent length budget")
	check(Condition.evaluate({"op": "var_eq", "variable": "n", "value": true}, vars, scopes).has("error"), "boolean is not integer")
	check(Condition.evaluate({"op": "var_lt", "variable": "s", "value": "x"}, vars, scopes).has("error"), "string ordering rejected")
	check(Condition.evaluate({"op": "var_in", "variable": "n", "values": [1, 1.0]}, vars, scopes).has("error"), "numeric duplicate set rejected")
	check(Condition.evaluate({"op": "or", "args": [{"op": "var_eq", "variable": "n", "value": 1}, {"op": "var_eq", "variable": "missing", "value": 1}]}, vars, scopes).has("error"), "short circuit cannot hide invalid reference")
	var reader = Reader.new()
	var depth_tree: Dictionary = {"op": "var_eq", "variable": "n", "value": 1}
	for _i in range(7): depth_tree = {"op": "not", "arg": depth_tree}
	check(Condition.evaluate(depth_tree, vars, scopes).get("value") == false, "depth eight accepted")
	check(Condition.evaluate({"op": "not", "arg": depth_tree}, vars, scopes).has("error"), "depth nine rejected")
	var groups: Array = []
	for size in [32, 32, 32, 27]:
		var leaves: Array = []
		for _i in range(size): leaves.append({"op": "var_eq", "variable": "n", "value": 1})
		groups.append({"op": "and", "args": leaves})
	var tree: Dictionary = {"op": "and", "args": groups}
	check(Condition.evaluate(tree, vars, scopes).get("value", false), "128 expression nodes accepted")
	groups[3].args.append({"op": "var_eq", "variable": "n", "value": 1})
	check(Condition.evaluate(tree, vars, scopes).has("error"), "129 expression nodes rejected")
	for token in ["1", "1.0", "1e0", "10e-1", "9007199254740991.0", "-0.0"]:
		var value: Variant = reader.decode(token.to_utf8_buffer())
		check(reader.error.is_empty() and value is int, "exact integer token " + token)
	for token in ["9007199254740990.5", "1.00000000000000001", "1e-400", "1e999", "0e999", "9007199254740992", "1e-9223372036854775808", "1e+999999999999999999999999999999999999"]:
		reader.decode(token.to_utf8_buffer())
		check(not reader.error.is_empty(), "reject lossy numeric token " + token)
	session.state.extensions["fixture.precision"] = [0.12345678901234566, 1.0000000000000002, 1e-100]
	var storage = Save.new(args[1].path_join("saves"))
	var saved: Dictionary = session.snapshot()
	check(storage.save(session), "actual condition package saves: " + storage.error)
	var restored: Dictionary = storage.read(session, storage.last_path).get("state", {})
	check(not restored.is_empty() and restored.scopes == saved.scopes, "all three scoped maximum integers survive actual save")
	check(restored.get("extensions", {}).get("fixture.precision") == saved.extensions["fixture.precision"], "extension floats survive full precision save")
	check(session.restore(restored, 1000), "actual saved state restores")
	check(session.state.committed_effect_ids == saved.committed_effect_ids and session.state.cursor == saved.cursor, "restore never reevaluates branch or repeats effects")
	var report: Dictionary = {"checks": checks, "passed": checks.size() - failed, "failed": failed, "save_path": storage.last_path, "package_path": args[0], "real_assets": false, "full_playthrough": false}
	FileAccess.open(args[1].path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failed == 0 else 1)
