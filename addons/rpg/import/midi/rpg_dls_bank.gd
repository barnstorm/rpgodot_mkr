@tool
class_name RPGDlsBank
extends RPGSoundBank
## A Downloadable Sounds (DLS level 1 and 2) instrument bank, such as Windows' gm.dls. Layout:
##   RIFF 'DLS '
##     colh                      instrument count
##     LIST lins > LIST ins      insh (regions, bank, program), lrgn, lart/lar2, INFO
##       LIST lrgn > LIST rgn / rgn2   rgnh (ranges, key group), wsmp, wlnk (wave index), lart/lar2
##     ptbl                      wave pool cues (byte offsets into wvpl)
##     LIST wvpl > LIST wave     fmt, wsmp (defaults for regions without one), data
## Articulation ('art1' / 'art2' connection blocks) is read for the volume envelope (EG1), the key
## number scaling of its hold and decay, pan and fixed attenuation. A region's own articulation
## replaces the instrument's. LFOs, EG2, filters, velocity curves and controller connections are
## not used by the renderer and are skipped.
##
## Units: time cents (1/65536 of a cent of time) become seconds as 2^(tc / 65536 / 1200), with
## 0x80000000 meaning 0 s; sustain is 0.1 % units * 65536 (DLS treats it as a point on the
## envelope's 96 dB scale); connection attenuation is 1/65536 cB; wsmp lAttenuation is 1/655360 dB.
##
## The parsed file is cached per path (and size / modified time); each wave is converted to floats
## the first time a note uses it.

const _ABS_ZERO := -0x80000000
## The volume envelope's range: DLS decay and release times are for a fall of this many dB.
const _EG_RANGE_DB := 96.0

# Connection sources and destinations (DLS 1 / 2).
const SRC_NONE := 0x0000
const SRC_KEYNUMBER := 0x0003
const DST_ATTENUATION := 0x0001
const DST_PAN := 0x0004
const DST_EG1_ATTACK := 0x0206
const DST_EG1_DECAY := 0x0207
const DST_EG1_RELEASE := 0x0209
const DST_EG1_SUSTAIN := 0x020a
const DST_EG1_DELAY := 0x020b
const DST_EG1_HOLD := 0x020c

# path -> {"size", "time", "data"}
static var _cache := {}
static var _cache_mutex := Mutex.new()


## The connection values one articulation sets (raw 32-bit scales; absent keys use defaults).
class DlsArt:
	extends RefCounted
	var values := {}


## Sample settings ('wsmp').
class DlsWsmp:
	extends RefCounted
	var unity := 60
	var fine := 0  # cents
	var atten_db := 0.0
	var loop_mode := 0
	var loop_start := 0
	var loop_end := 0


class DlsWave:
	extends RefCounted
	var rate := 22050
	var bits := 16
	var channels := 1
	var block_align := 2
	var data_offset := 0
	var frames := 0
	var wsmp: DlsWsmp = null
	var pcm := PackedFloat32Array()


class DlsRegion:
	extends RefCounted
	var key_lo := 0
	var key_hi := 127
	var vel_lo := 0
	var vel_hi := 127
	var key_group := 0
	var wave := -1
	var wsmp: DlsWsmp = null
	var art: DlsArt = null


class DlsInstrument:
	extends RefCounted
	var name := ""
	var bank := 0  # CC0 * 128 + CC32
	var program := 0
	var drums := false
	var regions: Array[DlsRegion] = []
	var art: DlsArt = null


class DlsData:
	extends RefCounted
	var bytes := PackedByteArray()
	var file_name := ""
	var instruments: Array[DlsInstrument] = []
	## (drums << 30 | bank << 7 | program) -> DlsInstrument (first one wins).
	var index := {}
	var waves: Array[DlsWave] = []
	var mutex := Mutex.new()


var _data: DlsData


func load_bank(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Sound bank '%s' could not be opened." % path
	var size := f.get_length()
	f.close()
	var time := FileAccess.get_modified_time(path)
	_cache_mutex.lock()
	var hit: Dictionary = _cache.get(path, {})
	if not hit.is_empty() and hit.size == size and hit.time == time:
		_data = hit.data
		_cache_mutex.unlock()
		return ""
	var data := DlsData.new()
	data.file_name = path.get_file()
	var err := _parse(FileAccess.get_file_as_bytes(path), data)
	if err == "":
		_cache[path] = {"size": size, "time": time, "data": data}
		_data = data
	_cache_mutex.unlock()
	return err


## Reads a DLS file from memory (tests build tiny ones). Not cached.
func load_bytes(bytes: PackedByteArray, name := "memory.dls") -> String:
	var data := DlsData.new()
	data.file_name = name
	var err := _parse(bytes, data)
	if err == "":
		_data = data
	return err


## Drops every cached file (the next open() parses again).
static func clear_cache() -> void:
	_cache_mutex.lock()
	_cache.clear()
	_cache_mutex.unlock()


func bank_name() -> String:
	return _data.file_name if _data else "DLS bank"


## Every instrument: [{"bank": int (CC0 * 128 + CC32), "program": int, "name": String, "drums": bool}].
func presets() -> Array:
	var out := []
	if _data == null:
		return out
	for ins in _data.instruments:
		out.append({"bank": ins.bank, "program": ins.program, "name": ins.name, "drums": ins.drums})
	return out


func regions_for(bank_no: int, program: int, key: int, velocity: int, drums: bool) -> Array:
	if _data == null:
		return []
	var ins := _find(bank_no, program, drums)
	if ins == null:
		return []
	var out := []
	for rg in ins.regions:
		if key < rg.key_lo or key > rg.key_hi or velocity < rg.vel_lo or velocity > rg.vel_hi:
			continue
		var r := _make_region(ins, rg, key)
		if r != null:
			out.append(r)
	return out


func _find(bank_no: int, program: int, drums: bool) -> DlsInstrument:
	var idx := _data.index
	var d := (1 << 30) if drums else 0
	for k in [d | (bank_no << 7) | program, d | ((bank_no & ~127) << 7) | program, d | program]:
		if idx.has(k):
			return idx[k]
	if drums and idx.has(d):
		return idx[d]  # unknown kit: kit 0
	return null


func _make_region(ins: DlsInstrument, rg: DlsRegion, key: int) -> Region:
	if rg.wave < 0 or rg.wave >= _data.waves.size():
		return null
	var w := _data.waves[rg.wave]
	var pcm := _pcm(w)
	if pcm.size() < 2:
		return null
	var ws := rg.wsmp if rg.wsmp != null else w.wsmp
	if ws == null:
		ws = DlsWsmp.new()
	var r := Region.new()
	r.samples = pcm
	r.sample_rate = w.rate
	r.root_key = ws.unity - ws.fine / 100.0
	r.attenuation_db = ws.atten_db
	if ws.loop_mode > 0 and ws.loop_end - ws.loop_start >= 2 and ws.loop_end <= pcm.size():
		r.loop_mode = ws.loop_mode
		r.loop_start = ws.loop_start
		r.loop_end = ws.loop_end
	r.exclusive_class = rg.key_group
	var art := rg.art if rg.art != null else ins.art
	var v: Dictionary = art.values if art != null else {}
	# Key number scaling: the connection's scale is applied in full at key 128.
	var k := key / 128.0
	r.delay = _tc_seconds(v.get(DST_EG1_DELAY, _ABS_ZERO), 0.0)
	r.attack = _tc_seconds(v.get(DST_EG1_ATTACK, _ABS_ZERO), 0.0)
	r.hold = _tc_seconds(v.get(DST_EG1_HOLD, _ABS_ZERO), v.get(-DST_EG1_HOLD, 0) * k)
	var permille := clampf(v.get(DST_EG1_SUSTAIN, 1000 * 65536) / 65536.0, 0.0, 1000.0)
	var fall := 1.0 - permille / 1000.0  # how much of the 96 dB scale the decay falls through
	r.sustain = db_to_linear(-fall * _EG_RANGE_DB)
	r.decay = _tc_seconds(v.get(DST_EG1_DECAY, _ABS_ZERO), v.get(-DST_EG1_DECAY, 0) * k) * fall
	if v.has(DST_EG1_RELEASE):
		r.release = _tc_seconds(v[DST_EG1_RELEASE], 0.0)
	r.pan = clampf(v.get(DST_PAN, 0) / 65536.0 / 500.0, -1.0, 1.0)
	r.attenuation_db += -v.get(DST_ATTENUATION, 0) / 65536.0 / 10.0
	return r


## Time cents (raw 32-bit) plus extra scaled time cents, in seconds.
static func _tc_seconds(raw: int, extra: float) -> float:
	if raw == _ABS_ZERO:
		return 0.0
	return pow(2.0, (raw + extra) / 65536.0 / 1200.0)


## The wave as mono floats, converted once.
func _pcm(w: DlsWave) -> PackedFloat32Array:
	var d := _data
	d.mutex.lock()
	if w.pcm.is_empty() and w.frames > 0:
		var out := PackedFloat32Array()
		out.resize(w.frames)
		var b := d.bytes
		var o := w.data_offset
		var step := w.block_align
		if w.bits == 8:
			for f in w.frames:
				out[f] = (b[o + f * step] - 128) * (1.0 / 128.0)
		else:
			for f in w.frames:
				out[f] = b.decode_s16(o + f * step) * (1.0 / 32768.0)
		w.pcm = out
	d.mutex.unlock()
	return w.pcm


# --- parsing ---------------------------------------------------------------------------------

static func _id(b: PackedByteArray, o: int) -> String:
	return b.slice(o, o + 4).get_string_from_ascii()


## Child chunks of [from, to): [[id, body offset, body size, list type or ""]].
static func _children(b: PackedByteArray, from: int, to: int) -> Array:
	var out := []
	var pos := from
	while pos + 8 <= to:
		var id := _id(b, pos)
		var size := mini(b.decode_u32(pos + 4), to - pos - 8)
		var kind := ""
		if (id == "LIST" or id == "RIFF") and size >= 4:
			kind = _id(b, pos + 8)
		out.append([id, pos + 8, size, kind])
		pos += 8 + size + (size & 1)
	return out


static func _parse(b: PackedByteArray, d: DlsData) -> String:
	if b.size() < 12 or _id(b, 0) != "RIFF" or _id(b, 8) != "DLS ":
		return "'%s' is not a DLS file." % d.file_name
	d.bytes = b
	var end := mini(b.size(), 8 + b.decode_u32(4))
	var lins := Vector2i(-1, 0)
	var wvpl := Vector2i(-1, 0)
	var cues := PackedInt32Array()
	for c in _children(b, 12, end):
		if c[3] == "lins":
			lins = Vector2i(c[1] + 4, c[1] + c[2])
		elif c[3] == "wvpl":
			wvpl = Vector2i(c[1] + 4, c[1] + c[2])
		elif c[0] == "ptbl" and c[2] >= 8:
			var cb := b.decode_u32(c[1])
			var n := b.decode_u32(c[1] + 4)
			for i in mini(n, (c[2] - cb) / 4):
				cues.append(b.decode_u32(c[1] + cb + i * 4))
	if lins.x < 0 or wvpl.x < 0:
		return "'%s' is not a complete DLS file (no instruments or no wave pool)." % d.file_name
	# Wave pool: cue offsets are relative to the start of the wvpl list's data (after its type).
	var by_offset := {}
	var sequential: Array[DlsWave] = []
	for c in _children(b, wvpl.x, wvpl.y):
		if c[3] != "wave":
			continue
		var w := _read_wave(b, c[1] + 4, c[1] + c[2])
		by_offset[c[1] - 8 - wvpl.x] = w
		sequential.append(w)
	if cues.is_empty():
		d.waves = sequential
	else:
		for i in cues.size():
			var w: DlsWave = by_offset.get(cues[i], sequential[i] if i < sequential.size() else null)
			d.waves.append(w if w != null else DlsWave.new())
	for c in _children(b, lins.x, lins.y):
		if c[3] == "ins ":
			var ins := _read_instrument(b, c[1] + 4, c[1] + c[2])
			d.instruments.append(ins)
			var k := ((1 << 30) if ins.drums else 0) | (ins.bank << 7) | ins.program
			if not d.index.has(k):
				d.index[k] = ins
	if d.instruments.is_empty():
		return "'%s' has no instruments." % d.file_name
	return ""


static func _read_wave(b: PackedByteArray, from: int, to: int) -> DlsWave:
	var w := DlsWave.new()
	var format := 1
	for c in _children(b, from, to):
		var o: int = c[1]
		match c[0]:
			"fmt ":
				format = b.decode_u16(o)
				w.channels = maxi(1, b.decode_u16(o + 2))
				w.rate = b.decode_u32(o + 4)
				w.block_align = maxi(1, b.decode_u16(o + 12))
				w.bits = b.decode_u16(o + 14)
			"wsmp":
				w.wsmp = _read_wsmp(b, o, c[2])
			"data":
				w.data_offset = o
				w.frames = c[2] / w.block_align
	if format != 1 or (w.bits != 8 and w.bits != 16):
		w.frames = 0  # compressed or unusual formats are not supported; the region stays silent
	return w


static func _read_wsmp(b: PackedByteArray, o: int, size: int) -> DlsWsmp:
	var ws := DlsWsmp.new()
	if size < 20:
		return ws
	var cb := b.decode_u32(o)
	ws.unity = b.decode_u16(o + 4)
	ws.fine = b.decode_s16(o + 6)
	ws.atten_db = -b.decode_s32(o + 8) / 655360.0
	var loops := b.decode_u32(o + 16)
	if loops > 0 and cb + 16 <= size:
		var lo := o + cb
		var kind := b.decode_u32(lo + 4)
		ws.loop_start = b.decode_u32(lo + 8)
		ws.loop_end = ws.loop_start + b.decode_u32(lo + 12)
		ws.loop_mode = 2 if kind == 1 else 1  # WLOOP_TYPE_RELEASE loops until note-off
	return ws


static func _read_instrument(b: PackedByteArray, from: int, to: int) -> DlsInstrument:
	var ins := DlsInstrument.new()
	for c in _children(b, from, to):
		var o: int = c[1]
		if c[0] == "insh" and c[2] >= 12:
			var bank := b.decode_u32(o + 4)
			ins.drums = (bank & 0x80000000) != 0
			ins.bank = ((bank >> 8) & 0x7f) * 128 + (bank & 0x7f)
			ins.program = b.decode_u32(o + 8) & 0x7f
		elif c[3] == "lrgn":
			for rc in _children(b, o + 4, o + c[2]):
				if rc[3] == "rgn " or rc[3] == "rgn2":
					ins.regions.append(_read_region(b, rc[1] + 4, rc[1] + rc[2]))
		elif c[3] == "lart" or c[3] == "lar2":
			ins.art = _read_art(b, o + 4, o + c[2], ins.art)
		elif c[3] == "INFO":
			for ic in _children(b, o + 4, o + c[2]):
				if ic[0] == "INAM":
					ins.name = b.slice(ic[1], ic[1] + ic[2]).get_string_from_ascii().strip_edges()
	return ins


static func _read_region(b: PackedByteArray, from: int, to: int) -> DlsRegion:
	var rg := DlsRegion.new()
	for c in _children(b, from, to):
		var o: int = c[1]
		match c[0]:
			"rgnh":
				if c[2] >= 12:
					rg.key_lo = b.decode_u16(o)
					rg.key_hi = b.decode_u16(o + 2)
					rg.vel_lo = b.decode_u16(o + 4)
					rg.vel_hi = b.decode_u16(o + 6)
					rg.key_group = b.decode_u16(o + 10)
					if rg.vel_hi == 0 and rg.vel_lo == 0:
						rg.vel_hi = 127  # some DLS 1 writers leave the velocity range empty
			"wsmp":
				rg.wsmp = _read_wsmp(b, o, c[2])
			"wlnk":
				if c[2] >= 12:
					rg.wave = b.decode_u32(o + 8)
			"LIST":
				if c[3] == "lart" or c[3] == "lar2":
					rg.art = _read_art(b, o + 4, o + c[2], rg.art)
	return rg


## Reads the art1 / art2 chunks of a lart / lar2 list into `into` (a new one when null). Values
## are keyed by destination; key number scaling is stored under the negated destination.
static func _read_art(b: PackedByteArray, from: int, to: int, into: DlsArt) -> DlsArt:
	var art := into if into != null else DlsArt.new()
	for c in _children(b, from, to):
		if c[0] != "art1" and c[0] != "art2":
			continue
		var o: int = c[1]
		var cb := b.decode_u32(o)
		var n := b.decode_u32(o + 4)
		for i in mini(n, (c[2] - cb) / 12):
			var co := o + cb + i * 12
			var src := b.decode_u16(co)
			var ctrl := b.decode_u16(co + 2)
			var dst := b.decode_u16(co + 4)
			var scale := b.decode_s32(co + 8)
			if ctrl != SRC_NONE:
				continue
			if src == SRC_NONE:
				art.values[dst] = scale
			elif src == SRC_KEYNUMBER and (dst == DST_EG1_DECAY or dst == DST_EG1_HOLD):
				art.values[-dst] = scale
	return art
