# SPDX-License-Identifier: MIT
extends RefCounted
## Local player preferences. Never part of a package, rules lock or saved state.
const LIMIT = 1048576
const ACTIONS = ["none", "cancel", "confirm", "up", "down", "left", "right", "previous", "next", "repeat", "auto", "guard", "items", "equipment", "escape", "status", "skills"]
const LABELS = ["禁用", "取消 / 暂停", "确认 / 交谈", "上", "下", "左", "右", "上一页", "下一页", "重复（待支持）", "围攻（待支持）", "防御", "战斗物品", "地图装备 / 战斗投掷（待支持）", "撤离", "状态", "战斗仙术"]
# Public PC scan identities, expressed against Godot's physical US key positions.
# This is a format adapter, not a raw DirectInput reader or CKey polling loop.
const SCANS = {
	0x01: KEY_ESCAPE, 0x02: KEY_1, 0x03: KEY_2, 0x04: KEY_3, 0x05: KEY_4,
	0x06: KEY_5, 0x07: KEY_6, 0x08: KEY_7, 0x09: KEY_8, 0x0a: KEY_9, 0x0b: KEY_0,
	0x0c: KEY_MINUS, 0x0d: KEY_EQUAL, 0x0e: KEY_BACKSPACE, 0x0f: KEY_TAB,
	0x10: KEY_Q, 0x11: KEY_W, 0x12: KEY_E, 0x13: KEY_R, 0x14: KEY_T, 0x15: KEY_Y,
	0x16: KEY_U, 0x17: KEY_I, 0x18: KEY_O, 0x19: KEY_P, 0x1a: KEY_BRACKETLEFT, 0x1b: KEY_BRACKETRIGHT,
	0x1c: KEY_ENTER, 0x1d: KEY_CTRL, 0x1e: KEY_A, 0x1f: KEY_S, 0x20: KEY_D, 0x21: KEY_F,
	0x22: KEY_G, 0x23: KEY_H, 0x24: KEY_J, 0x25: KEY_K, 0x26: KEY_L, 0x27: KEY_SEMICOLON,
	0x28: KEY_APOSTROPHE, 0x29: KEY_QUOTELEFT, 0x2a: KEY_SHIFT, 0x2b: KEY_BACKSLASH,
	0x2c: KEY_Z, 0x2d: KEY_X, 0x2e: KEY_C, 0x2f: KEY_V, 0x30: KEY_B, 0x31: KEY_N, 0x32: KEY_M,
	0x33: KEY_COMMA, 0x34: KEY_PERIOD, 0x35: KEY_SLASH, 0x36: KEY_SHIFT, 0x37: KEY_KP_MULTIPLY,
	0x38: KEY_ALT, 0x39: KEY_SPACE, 0x3a: KEY_CAPSLOCK, 0x3b: KEY_F1, 0x3c: KEY_F2,
	0x3d: KEY_F3, 0x3e: KEY_F4, 0x3f: KEY_F5, 0x40: KEY_F6, 0x41: KEY_F7, 0x42: KEY_F8,
	0x43: KEY_F9, 0x44: KEY_F10, 0x45: KEY_NUMLOCK, 0x46: KEY_SCROLLLOCK,
	0x47: KEY_KP_7, 0x48: KEY_KP_8, 0x49: KEY_KP_9, 0x4a: KEY_KP_SUBTRACT,
	0x4b: KEY_KP_4, 0x4c: KEY_KP_5, 0x4d: KEY_KP_6, 0x4e: KEY_KP_ADD,
	0x4f: KEY_KP_1, 0x50: KEY_KP_2, 0x51: KEY_KP_3, 0x52: KEY_KP_0, 0x53: KEY_KP_PERIOD,
	0x57: KEY_F11, 0x58: KEY_F12, 0x9c: KEY_KP_ENTER, 0x9d: KEY_CTRL,
	0xb5: KEY_KP_DIVIDE, 0xb8: KEY_ALT, 0xc7: KEY_HOME, 0xc8: KEY_UP, 0xc9: KEY_PAGEUP,
	0xcb: KEY_LEFT, 0xcd: KEY_RIGHT, 0xcf: KEY_END, 0xd0: KEY_DOWN, 0xd1: KEY_PAGEDOWN,
	0xd2: KEY_INSERT, 0xd3: KEY_DELETE
}
const DEFAULTS = [[0x01,1],[0x52,1],[0xd2,1],[0x38,1],[0xb8,1],
	[0x1c,2],[0x39,2],[0x1d,2],[0x9d,2],[0x9c,2],
	[0x48,3],[0xc8,3],[0x50,4],[0xd0,4],[0x4b,5],[0xcb,5],[0x4d,6],[0xcd,6],
	[0x49,7],[0xc9,7],[0x51,8],[0xd1,8],[0x13,9],[0x1e,10],[0x20,11],
	[0x12,12],[0x11,13],[0x10,14],[0x1f,15],[0x21,16]]
var profile: Dictionary = preset("classic")
var bindings: Dictionary = {}
var error: String = ""

func _init() -> void: apply(profile)

static func preset(name: String) -> Dictionary:
	return {"version":1, "preset":name, "remap":[]}

static func issue(value: Variant) -> String:
	if value is not Dictionary or value.keys().size() != 3 or value.get("version") != 1 or value.get("preset") not in ["classic","wasd","key_ini"] or value.get("remap") is not Array: return "按键配置格式不受支持。"
	if value.remap.size() > 256 or (value.preset != "key_ini" and not value.remap.is_empty()): return "按键配置条目不正确。"
	var seen: Dictionary = {}
	for row in value.remap:
		if row is not Array or row.size() != 2: return "按键配置条目不正确。"
		for number in row:
			if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or number != int(number): return "按键配置需要整数编号。"
		if not SCANS.has(int(row[0])) or int(row[1]) < 0 or int(row[1]) >= ACTIONS.size() or seen.has(int(row[0])): return "按键配置含有不支持或重复的编号。"
		seen[int(row[0])] = true
	return ""

func apply(value: Dictionary) -> bool:
	error = issue(value)
	if not error.is_empty(): return false
	profile = preset(value.preset)
	for row in value.remap: profile.remap.append([int(row[0]),int(row[1])])
	bindings.clear()
	if profile.preset == "key_ini":
		for row in profile.remap: bindings[int(row[0])] = int(row[1])
	for row in DEFAULTS:
		if not bindings.has(row[0]): bindings[row[0]] = row[1]
	if profile.preset == "wasd":
		for row in [[0x11,3],[0x1f,4],[0x1e,5],[0x20,6]]: bindings[row[0]] = row[1]
	return true

static func scan(event: InputEventKey) -> int:
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == KEY_CTRL: return 0x9d if event.location == KEY_LOCATION_RIGHT else 0x1d
	if code == KEY_ALT: return 0xb8 if event.location == KEY_LOCATION_RIGHT else 0x38
	if code == KEY_SHIFT: return 0x36 if event.location == KEY_LOCATION_RIGHT else 0x2a
	return SCANS.find_key(code) if SCANS.values().has(code) else -1

func action(event: InputEventKey) -> String:
	var identity: int = scan(event)
	return ACTIONS[bindings[identity]] if bindings.has(identity) else ""

static func key_name(identity: int) -> String:
	var side: String = "左 " if identity in [0x1d,0x2a,0x38] else ("右 " if identity in [0x9d,0x36,0xb8] else "")
	return side + OS.get_keycode_string(SCANS[identity])

func describe() -> String:
	var text: String = ""
	for identity in bindings: text += "%s → %s\n" % [key_name(identity),LABELS[bindings[identity]]]
	return text

static func import_file(path: String) -> Dictionary:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {"error":"无法读取所选 key.ini。"}
	if file.get_length() > LIMIT: return {"error":"key.ini 超过 1 MiB 限制。"}
	return parse_ini(file.get_buffer(file.get_length()))

static func parse_ini(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > LIMIT: return {"error":"key.ini 超过 1 MiB 限制。"}
	if bytes.has(0): return {"error":"请将 key.ini 保存为 UTF-8 或 ANSI；不支持 UTF-16。"}
	# Only the ASCII format is interpreted. ANSI/GBK/UTF-8 comment bytes are inert.
	var ascii: PackedByteArray = bytes.duplicate()
	for i in range(ascii.size()):
		if ascii[i] >= 128: ascii[i] = 32
	var rows: Array = []; var notices: Array = []; var seen: Dictionary = {}
	var section: String = ""; var found: bool = false; var line_number: int = 0
	var hex = RegEx.new(); hex.compile("^0[xX][0-9a-fA-F]{1,2}$")
	for raw in ascii.get_string_from_ascii().split("\n"):
		line_number += 1
		var line: String = raw.get_slice(";",0).strip_edges()
		if line.is_empty(): continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1,line.length()-2).strip_edges().to_lower()
			if section == "remap": found = true
			elif not notices.has("仅导入 [Remap]；其它节中的退出、重启、存档移动等设置不执行。"):
				notices.append("仅导入 [Remap]；其它节中的退出、重启、存档移动等设置不执行。")
			continue
		if section != "remap": continue
		var pair: PackedStringArray = line.split("=")
		if pair.size() != 2 or hex.search(pair[0].strip_edges()) == null or hex.search(pair[1].strip_edges()) == null:
			return {"error":"第 %d 行不是有效的十六进制扫描码=动作值。" % line_number}
		var identity: int = pair[0].strip_edges().hex_to_int(); var code: int = pair[1].strip_edges().hex_to_int()
		if not SCANS.has(identity) or code >= ACTIONS.size(): return {"error":"第 %d 行的扫描码或动作值暂不受支持；未应用任何条目。" % line_number}
		if seen.has(identity): notices.append("第 %d 行重复，保留首次配置的 %s。" % [line_number,key_name(identity)]); continue
		seen[identity] = true; rows.append([identity,code])
	if not found: return {"error":"未找到 [Remap] 节；当前配置保留。"}
	if rows.is_empty(): notices.append("空 [Remap] 将使用传统默认键。")
	return {"profile":{"version":1,"preset":"key_ini","remap":rows},"notices":notices}

func load_profile(path: String) -> bool:
	error = ""
	if not FileAccess.file_exists(path): return true
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > LIMIT: error = "无法读取本地按键配置；使用传统默认键。"; return false
	var reader = preload("res://src/native_json.gd").new()
	var candidate: Variant = reader.decode(file.get_buffer(file.get_length()))
	error = issue(candidate)
	if not error.is_empty(): return false
	return apply(candidate)

func save_profile(path: String, candidate: Dictionary) -> bool:
	error = issue(candidate)
	if not error.is_empty(): return false
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute): error = "按键配置路径是目录；当前配置保留。"; return false
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK: error = "无法创建按键配置目录。"; return false
	var suffix: String = "%s-%d" % [Time.get_datetime_string_from_system().replace(":","-"),Time.get_ticks_usec()]
	var pending: String = absolute + ".pending-" + suffix
	var file = FileAccess.open(pending,FileAccess.WRITE)
	if file == null: error = "无法保存按键配置；当前配置保留。"; return false
	file.store_string(JSON.stringify(candidate,"\t")); file.flush()
	var written: bool = file.get_error() == OK; file.close()
	if not written: error = "按键配置写入失败；当前配置保留。"; return false
	if FileAccess.file_exists(absolute) and DirAccess.copy_absolute(absolute,absolute+".backup-"+suffix) != OK:
		error = "无法备份旧按键配置；当前配置保留。"; return false
	if DirAccess.rename_absolute(pending,absolute) != OK: error = "无法替换按键配置；当前配置保留。"; return false
	return apply(candidate)
