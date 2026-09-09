# SPDX-License-Identifier: MIT
extends "res://src/native_classic_command_button.gd"
## Isolated artwork contact sheet only; never used by the game command container.
var preview_state: String = "normal"
func skin_state() -> String: return preview_state
