@tool
class_name RPGMarshal
extends RefCounted
## Minimal reader for Ruby Marshal 4.8 data (RPG Maker XP / VX / VX Ace .rxdata / .rvdata /
## .rvdata2 files). Original code written for this project from the public description of the
## Marshal format; it reads, it never writes, and it never runs anything from the data.
##
##   var r := RPGMarshal.parse(FileAccess.get_file_as_bytes(path))
##   if r.error == "": use r.value
##
## Ruby value -> Godot value:
##   nil / true / false        null / true / false
##   Fixnum ('i'), Bignum ('l') int (a Bignum wider than 63 bits is an error)
##   Float ('f')               float ("inf", "-inf", "nan" too)
##   String ('"')              String: UTF-8 when the bytes are valid UTF-8, else Latin-1 (XP
##                             projects in Japanese store Shift-JIS without any encoding ivar;
##                             such names come out garbled, but readable ASCII stays exact).
##                             An encoding ivar (:E / :encoding) is read and dropped.
##   Symbol (':'), symlink (';') StringName
##   Array ('[')               Array
##   Hash ('{', '}')           Dictionary (a default value '}' is read and dropped)
##   Object ('o')              Dictionary {"@class": "RPG::Tileset", "@id": ..., "@name": ...}
##                             (ivar names keep their '@')
##   Struct ('S')              Dictionary {"@class": name, member: value, ...}
##   user data ('u', _dump)    Dictionary {"@class": "Table", "@data": PackedByteArray} (Table,
##                             Color and Tone stay raw bytes; see table())
##   'U' (marshal_load), 'e' (extended), 'C' (user class): the wrapped value
##   object link ('@')         the same Godot value again (Arrays and Dictionaries are shared)
## Anything else (class / module / regexp / data references) is an error naming the type byte.

const MAJOR := 4
const MINOR := 8
const CLASS_KEY := "@class"
const DATA_KEY := "@data"
## Guard against hostile input: nesting deeper than this is an error.
const MAX_DEPTH := 256

var _b: PackedByteArray
var _pos := 0
var _symbols: Array[StringName] = []
var _objects: Array = []
var _error := ""
var _depth := 0


## Parses Marshal bytes: {value, error ("" when it worked)}.
static func parse(bytes: PackedByteArray) -> Dictionary:
	var m := RPGMarshal.new()
	m._b = bytes
	if bytes.size() < 2 or bytes[0] != MAJOR or bytes[1] != MINOR:
		return {"value": null, "error": "not Ruby Marshal 4.8 data"}
	m._pos = 2
	var v: Variant = m._read()
	if m._error != "":
		return {"value": null, "error": m._error}
	return {"value": v, "error": ""}


## Reads a file: {value, error}.
static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"value": null, "error": "cannot open %s" % path}
	return parse(FileAccess.get_file_as_bytes(path))


## Class name of a decoded object ("" for other values).
static func class_of(v: Variant) -> String:
	return str(v.get(CLASS_KEY, "")) if v is Dictionary else ""


## Decodes an RGSS Table's _dump bytes: {dims, x, y, z, values: PackedInt32Array} (values are
## signed 16-bit, index x + y * xsize + z * xsize * ysize); {} when the bytes are not a Table.
static func table(v: Variant) -> Dictionary:
	var raw: Variant = v.get(DATA_KEY) if v is Dictionary else v
	if not (raw is PackedByteArray) or (raw as PackedByteArray).size() < 20:
		return {}
	var b: PackedByteArray = raw
	var x := b.decode_s32(4)
	var y := b.decode_s32(8)
	var z := b.decode_s32(12)
	var n := b.decode_s32(16)
	if n < 0 or x < 0 or y < 0 or z < 0 or n != x * y * z or b.size() < 20 + n * 2:
		return {}
	var values := PackedInt32Array()
	values.resize(n)
	for i in n:
		values[i] = b.decode_s16(20 + i * 2)
	return {"dims": b.decode_s32(0), "x": x, "y": y, "z": z, "values": values}


func _fail(msg: String) -> Variant:
	if _error == "":
		_error = "%s at byte %d" % [msg, _pos]
	return null


func _byte() -> int:
	if _pos >= _b.size():
		_fail("unexpected end of data")
		return 0
	_pos += 1
	return _b[_pos - 1]


func _bytes(n: int) -> PackedByteArray:
	if n < 0 or _pos + n > _b.size():
		_fail("unexpected end of data")
		return PackedByteArray()
	var out := _b.slice(_pos, _pos + n)
	_pos += n
	return out


## Marshal's packed integer: 0; 1..4 little-endian bytes follow; -1..-4 negative bytes follow;
## otherwise the byte itself, offset by 5.
func _int() -> int:
	var c := _byte()
	if c >= 128:
		c -= 256
	if c == 0:
		return 0
	if c >= 5:
		return c - 5
	if c <= -5:
		return c + 5
	if c > 0:
		var v := 0
		for i in c:
			v |= _byte() << (8 * i)
		return v
	var n := -c
	var u := -1
	for i in n:
		u &= ~(0xFF << (8 * i))
		u |= _byte() << (8 * i)
	return u


func _raw_string() -> PackedByteArray:
	return _bytes(_int())


static func _text(b: PackedByteArray) -> String:
	if b.is_empty():
		return ""
	var s := b.get_string_from_utf8()
	if s.to_utf8_buffer() == b:
		return s
	# Not UTF-8 (Shift-JIS from a Japanese XP project): one character per byte.
	var out := ""
	for x in b:
		out += char(x)
	return out


func _symbol_body() -> StringName:
	var s := StringName(_text(_raw_string()))
	_symbols.append(s)
	return s


func _symbol() -> StringName:
	var t := _byte()
	match t:
		0x3A:  # ':'
			return _symbol_body()
		0x3B:  # ';'
			var i := _int()
			if i < 0 or i >= _symbols.size():
				_fail("bad symbol link %d" % i)
				return &""
			return _symbols[i]
		0x49:  # 'I' symbol with an encoding ivar
			var s := _symbol()
			_skip_ivars()
			return s
	_fail("expected a symbol, got type 0x%02x" % t)
	return &""


## Reads `count` ivar pairs and drops them (encoding flags on strings and symbols).
func _skip_ivars() -> void:
	var n := _int()
	for i in n:
		_symbol()
		_read()
		if _error != "":
			return


func _register(v: Variant) -> int:
	_objects.append(v)
	return _objects.size() - 1


func _read() -> Variant:
	if _error != "":
		return null
	_depth += 1
	if _depth > MAX_DEPTH:
		return _fail("data nested too deeply")
	var v: Variant = _read_value()
	_depth -= 1
	return v


func _read_value() -> Variant:
	var t := _byte()
	if _error != "":
		return null
	match t:
		0x30:  # '0'
			return null
		0x54:  # 'T'
			return true
		0x46:  # 'F'
			return false
		0x69:  # 'i'
			return _int()
		0x3A, 0x3B:  # ':' ';'
			_pos -= 1
			return _symbol()
		0x22:  # '"'
			var s := _text(_raw_string())
			_register(s)
			return s
		0x49:  # 'I': the next value, then its ivars
			var inner: Variant = _read()
			var n := _int()
			for i in n:
				var key := _symbol()
				var val: Variant = _read()
				# Encoding flags (:E, :encoding) say how to read a String; other ivars are kept on
				# decoded objects (Dictionaries) only.
				if inner is Dictionary and key != &"E" and key != &"encoding":
					inner[str(key)] = val
			return inner
		0x5B:  # '['
			var n2 := _int()
			var arr := []
			_register(arr)
			for i in n2:
				arr.append(_read())
				if _error != "":
					return null
			return arr
		0x7B, 0x7D:  # '{' '}'
			var n3 := _int()
			var d := {}
			_register(d)
			for i in n3:
				var k: Variant = _read()
				var val2: Variant = _read()
				if _error != "":
					return null
				d[k] = val2
			if t == 0x7D:
				_read()  # default value
			return d
		0x6F:  # 'o'
			var cls := _symbol()
			var obj := {CLASS_KEY: str(cls)}
			_register(obj)
			var n4 := _int()
			for i in n4:
				var key2 := _symbol()
				obj[str(key2)] = _read()
				if _error != "":
					return null
			return obj
		0x53:  # 'S' struct
			var cls2 := _symbol()
			var st := {CLASS_KEY: str(cls2)}
			_register(st)
			var n5 := _int()
			for i in n5:
				var key3 := _symbol()
				st[str(key3)] = _read()
				if _error != "":
					return null
			return st
		0x75:  # 'u' user data (_dump): kept as bytes
			var cls3 := _symbol()
			var data := _raw_string()
			var ud := {CLASS_KEY: str(cls3), DATA_KEY: data}
			_register(ud)
			return ud
		0x55:  # 'U' marshal_load: class, then the dumped value
			var cls4 := _symbol()
			var slot := _register(null)
			var inner2: Variant = _read()
			var wrapped := {CLASS_KEY: str(cls4), DATA_KEY: inner2}
			_objects[slot] = wrapped
			return wrapped
		0x65:  # 'e' extended by a module: module name, then the value
			_symbol()
			return _read()
		0x43:  # 'C' instance of a user subclass of String/Array/Hash
			_symbol()
			return _read()
		0x40:  # '@' object link
			var i2 := _int()
			if i2 < 0 or i2 >= _objects.size():
				return _fail("bad object link %d" % i2)
			return _objects[i2]
		0x66:  # 'f'
			var fs := _text(_raw_string())
			var f := 0.0
			match fs:
				"inf":
					f = INF
				"-inf":
					f = -INF
				"nan":
					f = NAN
				_:
					f = fs.to_float()
			_register(f)
			return f
		0x6C:  # 'l' bignum: sign, length in 16-bit words, little-endian bytes
			var sign := _byte()
			var words := _int()
			if words * 2 > 8:
				return _fail("integer too large")
			var bb := _bytes(words * 2)
			var v := 0
			for i in bb.size():
				v |= bb[i] << (8 * i)
			if v < 0:
				return _fail("integer too large")
			v = -v if sign == 0x2D else v
			_register(v)
			return v
	return _fail("unsupported Marshal type 0x%02x" % t)
