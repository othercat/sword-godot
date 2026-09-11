# SPDX-License-Identifier: MIT
extends RefCounted
const NAMES = ["Microsoft YaHei UI", "Noto Sans CJK SC", "PingFang SC", "sans-serif"]

static func create() -> SystemFont:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(NAMES)
	return font
