# SPDX-License-Identifier: MIT
extends SceneTree
## The original-source admission report: readable content facts, capability
## rows decided by the real owners (the formal session's own guard, the
## opening chain, the missing audio backend), and the capability-satisfied
## branch on an author package. Headless; the app dialog mirrors this report.
const Admission = preload("res://src/native_pal98_original_admission.gd")

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _capability(report: Dictionary, name: String) -> Dictionary:
	for cap in report.get("capabilities", []):
		if cap.name == name: return cap
	return {}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3 or FileAccess.file_exists(args[2]) or DirAccess.dir_exists_absolute(args[2]): quit(2); return

	# Named refusal before any success path.
	var missing: Dictionary = Admission.inspect(args[0] + ".definitely-missing")
	check(missing.has("error") and str(missing.error).contains("package admission refused"),
		"a missing package is refused by name: " + str(missing.get("error", "")))

	# The admitted original-source author sample.
	var report: Dictionary = Admission.inspect(args[0])
	check(not report.has("error"), "the admitted original package admits: " + str(report.get("error", "")))
	if report.has("error"): finish(args); return
	var readable: Dictionary = report.readable
	check(readable.source_id == "source.pal98.complete-package",
		"the original provenance identity is reported: " + str(readable.source_id))
	check(readable.map20_readable and readable.map12_readable and readable.scene1_readable
		and readable.night_palette_readable and readable.day_palette_rgb6 == 768
		and readable.data3_bytes == 900 and readable.graphics_fingerprint.length() == 64,
		"the readable content facts come from real reads: " + str(readable))
	var session_cap: Dictionary = _capability(report, "ordinary_session_play")
	check(not session_cap.is_empty() and not session_cap.present
		and str(session_cap.detail).contains("original_source_only"),
		"the formal session's own guard is the reported play gap: " + str(session_cap.get("detail", "")))
	var audio_cap: Dictionary = _capability(report, "audio_backend")
	check(not audio_cap.is_empty() and not audio_cap.present
		and str(audio_cap.detail).contains("no audio backend"),
		"the audio row reports the real backend absence: " + str(audio_cap.get("detail", "")))
	var chain_cap: Dictionary = _capability(report, "original_opening_chain")
	check(not chain_cap.is_empty() and not chain_cap.present
		and chain_cap.get("scope") == "diagnostic_probe" and not str(chain_cap.detail).is_empty(),
		"reaching a request with unverified initialization is diagnostic, not complete original capability")
	check(not report.playable, "the original package is honestly reported not formally playable")
	var text: String = Admission.summary(report)
	check(text.contains("[缺] ordinary_session_play") and text.contains("[缺] original_opening_chain")
		and text.contains("当前可正式试玩：false"),
		"the display summary mirrors the report rows")

	# The capability-satisfied branch: an author package activates the formal session.
	var author: Dictionary = Admission.inspect(args[1])
	check(not author.has("error"), "the author package admits: " + str(author.get("error", "")))
	if not author.has("error"):
		var author_session: Dictionary = _capability(author, "ordinary_session_play")
		check(author_session.present,
			"the author package satisfies the formal session branch: " + str(author_session.get("detail", "")))
		check(author.playable == author_session.present and author.playable,
			"irrelevant original-only rows do not block an admitted author session")
		check(not Admission.summary(author).is_empty(), "author summary supports absent optional original fields")

	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_original_admission",
		"scope": "original-source capability inspection through real owners; app dialog mirrors this report",
		"checks": checks, "passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
