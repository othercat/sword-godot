# SPDX-License-Identifier: MIT
extends RefCounted
## Strict bounded JSON data, never Variant object deserialization.
var error: String = ""
var _text: String
var _at: int
var _values: int
var _number_pattern = RegEx.create_from_string("^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$")

func decode(bytes: PackedByteArray) -> Variant:
	error = ""
	_at = 0
	_values = 0
	if bytes.size() > 16777216:
		error = "JSON exceeds 16 MiB"
		return null
	_text = bytes.get_string_from_utf8()
	if _text.to_utf8_buffer() != bytes:
		error = "invalid UTF-8"
		return null
	var result = _value(0)
	_space()
	if _at != _text.length() and error.is_empty():
		error = "trailing JSON input"
	return result if error.is_empty() else null

func _space() -> void:
	while _at < _text.length() and _text[_at] in [" ", "\t", "\n", "\r"]:
		_at += 1

func _take(symbol: String) -> bool:
	_space()
	if _text.substr(_at, symbol.length()) != symbol:
		return false
	_at += symbol.length()
	return true

func _value(depth: int) -> Variant:
	_values += 1
	_space()
	if depth > 64 or _values > 1000000 or _at >= _text.length():
		error = "JSON depth/value/end limit"
		return null
	match _text[_at]:
		"{":
			_at += 1
			var out: Dictionary = {}
			if _take("}"): return out
			while error.is_empty():
				_space()
				if _at >= _text.length() or _text[_at] != '"':
					error = "object key required"
					break
				var key = _string()
				if out.has(key) or not _take(":"):
					error = "duplicate key or missing colon"
					break
				out[key] = _value(depth + 1)
				if _take("}"): return out
				if not _take(","):
					error = "object comma required"
			return null
		"[":
			_at += 1
			var out: Array = []
			if _take("]"): return out
			while error.is_empty():
				out.append(_value(depth + 1))
				if _take("]"): return out
				if not _take(","):
					error = "array comma required"
			return null
		'"': return _string()
	if _take("true"): return true
	if _take("false"): return false
	if _take("null"): return null
	var start: int = _at
	while _at < _text.length() and _text[_at] in "0123456789.eE+-":
		_at += 1
		if _at - start > 64:
			error = "number token too long"
			return null
	var token: String = _text.substr(start, _at - start)
	if _number_pattern.search(token) == null:
		error = "invalid JSON value"
		return null
	if not token.contains(".") and not token.to_lower().contains("e"):
		if token.trim_prefix("-").length() > 16:
			error = "integer outside exact Native range"
			return null
		var integer: int = token.to_int()
		if absi(integer) > 9007199254740991: error = "integer outside exact Native range"
		return integer
	var exponent: int = 0
	if token.to_lower().contains("e"):
		var exponent_text: String = token.to_lower().get_slice("e", 1)
		var magnitude: String = exponent_text.trim_prefix("-").trim_prefix("+")
		while magnitude.begins_with("0") and magnitude.length() > 1: magnitude = magnitude.substr(1)
		# Reject before int conversion/abs: an int64-min exponent must not wrap.
		if magnitude.length() > 3 or magnitude.to_int() > 308:
			error = "exponent outside Native range"
			return null
		exponent = magnitude.to_int() * (-1 if exponent_text.begins_with("-") else 1)
	# Decide integrality from decimal digits, before IEEE rounding can turn a
	# fraction such as 9007199254740990.5 into an accepted integer.
	var parts: PackedStringArray = token.to_lower().split("e")
	var mantissa: String = parts[0].trim_prefix("-")
	var dot: int = mantissa.find(".")
	var scale: int = (mantissa.length() - dot - 1 if dot >= 0 else 0) - exponent
	var digits: String = mantissa.replace(".", "")
	while digits.begins_with("0") and digits.length() > 1: digits = digits.substr(1)
	while scale > 0 and digits.ends_with("0"):
		digits = digits.left(-1)
		scale -= 1
	if digits.is_empty() or digits == "0": return 0
	if scale <= 0:
		if digits.length() - scale > 16:
			error = "integer outside exact Native range"
			return null
		digits += "0".repeat(-scale)
		var integer: int = digits.to_int() * (-1 if token.begins_with("-") else 1)
		if absi(integer) > 9007199254740991: error = "integer outside exact Native range"
		return integer
	var value: float = token.to_float()
	if not is_finite(value) or absf(value) > 9007199254740991.0:
		error = "number outside exact Native range"
	elif floor(value) == value: error = "fraction would round to an integer"
	return value

func _hex4() -> int:
	if _at + 4 > _text.length():
		error = "short Unicode escape"
		return 0
	var value: int = 0
	for _i in range(4):
		var digit: int = "0123456789abcdef".find(_text[_at].to_lower())
		_at += 1
		if digit < 0:
			error = "invalid Unicode escape"
			return 0
		value = value * 16 + digit
	return value

func _string() -> String:
	_at += 1
	var out: String = ""
	while _at < _text.length() and error.is_empty():
		var character: String = _text[_at]
		_at += 1
		if character == '"': return out
		if character.unicode_at(0) < 32:
			error = "unescaped control character"
			break
		if character != "\\":
			out += character
			continue
		if _at == _text.length(): break
		var escape: String = _text[_at]
		_at += 1
		var simple = {'"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t"}
		if simple.has(escape):
			out += simple[escape]
		elif escape == "u":
			var code: int = _hex4()
			if code >= 0xD800 and code <= 0xDBFF:
				if _text.substr(_at, 2) != "\\u":
					error = "missing low surrogate"
					break
				_at += 2
				var low: int = _hex4()
				if low < 0xDC00 or low > 0xDFFF:
					error = "invalid low surrogate"
					break
				code = 0x10000 + ((code - 0xD800) << 10) + low - 0xDC00
			elif code >= 0xDC00 and code <= 0xDFFF:
				error = "unexpected low surrogate"
				break
			out += String.chr(code)
		else:
			error = "invalid escape"
	if error.is_empty(): error = "unterminated string"
	return ""
