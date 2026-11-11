@tool
class_name RPGSf2Bank
extends RPGSoundBank
## A SoundFont 2 (2.01 / 2.04) instrument bank, read from the RIFF 'sfbk' layout:
##   sdta: 'smpl' (16-bit mono sample words; a 2.04 'sm24' low byte chunk is ignored)
##   pdta: phdr pbag pmod pgen inst ibag imod igen shdr
## Presets point at instruments, instruments at samples. A note plays every instrument zone (of
## every preset zone) whose key and velocity ranges both contain it.
##
## Generator rules (SoundFont 2.04, section 8 and 9.4):
##   - a global zone (the first zone, when it has no instrument / sampleID) gives defaults that a
##     local zone's own generator replaces;
##   - preset-level values are added to the instrument-level ones, except the ranges (which
##     intersect), the index generators and the instrument-only ones (sample addresses, sampleModes,
##     exclusiveClass, overridingRootKey, keynum, velocity).
## Modulators (pmod / imod), filters, the LFOs and the modulation envelope are read past but not
## used: the renderer only plays the volume envelope.
##
## The parsed file is cached per path (and size / modified time) for the whole editor session, and
## each sample is converted to floats the first time a note uses it.

const _GEN_COUNT := 61
# Generator numbers (SoundFont 2.04 section 8.1.2).
const G_START_OFS := 0
const G_END_OFS := 1
const G_LOOP_START_OFS := 2
const G_LOOP_END_OFS := 3
const G_START_COARSE := 4
const G_END_COARSE := 12
const G_PAN := 17
const G_DELAY_VOL := 33
const G_ATTACK_VOL := 34
const G_HOLD_VOL := 35
const G_DECAY_VOL := 36
const G_SUSTAIN_VOL := 37
const G_RELEASE_VOL := 38
const G_KEY_TO_HOLD := 39
const G_KEY_TO_DECAY := 40
const G_INSTRUMENT := 41
const G_KEY_RANGE := 43
const G_VEL_RANGE := 44
const G_LOOP_START_COARSE := 45
const G_KEYNUM := 46
const G_VELOCITY := 47
const G_ATTENUATION := 48
const G_LOOP_END_COARSE := 50
const G_COARSE_TUNE := 51
const G_FINE_TUNE := 52
const G_SAMPLE_ID := 53
const G_SAMPLE_MODES := 54
const G_SCALE_TUNING := 56
const G_EXCLUSIVE := 57
const G_ROOT_KEY := 58
# A finished zone is the 61 generator values followed by these.
const Z_KEY_LO := 61
const Z_KEY_HI := 62
const Z_VEL_LO := 63
const Z_VEL_HI := 64
const Z_SAMPLE := 65
const _ZONE_SIZE := 66

## Many SoundFonts are voiced for EMU hardware, which applied only 40% of initialAttenuation; like
## FluidSynth, the attenuation in centibels is multiplied by this before use.
const ATTENUATION_FACTOR := 0.4

## Generators that only mean something at instrument level (ignored in preset zones).
const _INSTRUMENT_ONLY := [0, 1, 2, 3, 4, 12, 45, 46, 47, 50, 54, 57, 58]

# path -> {"size", "time", "data"}
static var _cache := {}
static var _cache_mutex := Mutex.new()


## One sample header ('shdr').
class Sf2Sample:
	extends RefCounted
	var name := ""
	var start := 0
	var end := 0
	var loop_start := 0
	var loop_end := 0
	var rate := 44100
	var pitch := 60
	var correction := 0
	var link := 0
	var type := 1


## Everything read from one file; shared by every RPGSf2Bank opened on the same path.
class Sf2Data:
	extends RefCounted
	var bytes := PackedByteArray()
	var smpl_offset := 0
	var smpl_frames := 0
	var file_name := ""
	## [name, bank, program, first bag] per preset, terminal record included.
	var preset_names := PackedStringArray()
	var preset_banks := PackedInt32Array()
	var preset_programs := PackedInt32Array()
	var preset_bags := PackedInt32Array()
	var pbag_gen := PackedInt32Array()
	var pgen_oper := PackedInt32Array()
	var pgen_amount := PackedInt32Array()
	var inst_names := PackedStringArray()
	var inst_bags := PackedInt32Array()
	var ibag_gen := PackedInt32Array()
	var igen_oper := PackedInt32Array()
	var igen_amount := PackedInt32Array()
	var samples: Array[Sf2Sample] = []
	## bank * 128 + program -> preset index.
	var preset_index := {}
	## preset index -> PackedInt32Array of zones (_ZONE_SIZE ints each), built on first use.
	var zones := {}
	## Vector3i(sample, start, end) -> PackedFloat32Array.
	var pcm := {}
	var mutex := Mutex.new()


var _data: Sf2Data


func load_bank(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "Sound bank '%s' was not found." % path
	var size := 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Sound bank '%s' could not be opened." % path
	size = f.get_length()
	f.close()
	var time := FileAccess.get_modified_time(path)
	_cache_mutex.lock()
	var hit: Dictionary = _cache.get(path, {})
	if not hit.is_empty() and hit.size == size and hit.time == time:
		_data = hit.data
		_cache_mutex.unlock()
		return ""
	var data := Sf2Data.new()
	data.file_name = path.get_file()
	var err := _parse(FileAccess.get_file_as_bytes(path), data)
	if err == "":
		_cache[path] = {"size": size, "time": time, "data": data}
		_data = data
	_cache_mutex.unlock()
	return err


## Reads a SoundFont from memory (tests build tiny ones). Not cached.
func load_bytes(bytes: PackedByteArray, name := "memory.sf2") -> String:
	var data := Sf2Data.new()
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
	return _data.file_name if _data else "SoundFont"


## Every preset: [{"bank": int, "program": int, "name": String, "drums": bool}], file order.
func presets() -> Array:
	var out := []
	if _data == null:
		return out
	for i in _data.preset_names.size() - 1:
		out.append({"bank": _data.preset_banks[i], "program": _data.preset_programs[i],
			"name": _data.preset_names[i], "drums": _data.preset_banks[i] == 128})
	return out


func regions_for(bank_no: int, program: int, key: int, velocity: int, drums: bool) -> Array:
	if _data == null:
		return []
	var p := _find_preset(bank_no, program, drums)
	if p < 0:
		return []
	var zones := _zones_for(p)
	var out := []
	var used_samples := {}
	var i := 0
	while i < zones.size():
		if key >= zones[i + Z_KEY_LO] and key <= zones[i + Z_KEY_HI] \
				and velocity >= zones[i + Z_VEL_LO] and velocity <= zones[i + Z_VEL_HI]:
			var r := _make_region(zones, i, key)
			if r != null:
				out.append([r, zones[i + Z_SAMPLE], zones[i + G_PAN]])
				used_samples[zones[i + Z_SAMPLE]] = true
		i += _ZONE_SIZE
	var regions := []
	for entry in out:
		var r: Region = entry[0]
		var s: Sf2Sample = _data.samples[entry[1]]
		# A stereo half whose partner also sounds is panned hard to its side, unless the zone sets
		# its own pan; a half played alone stays where its pan generator puts it.
		if entry[2] == 0 and (s.type & 6) != 0 and used_samples.has(s.link):
			r.pan = -1.0 if (s.type & 4) != 0 else 1.0
		regions.append(r)
	return regions


func _find_preset(bank_no: int, program: int, drums: bool) -> int:
	var idx: Dictionary = _data.preset_index
	if drums:
		return idx.get(128 * 128 + program, idx.get(128 * 128, -1))
	# GS-style banks: the variation is CC0 (bank_no >> 7); CC32 is ignored like most GS synths do.
	var msb := bank_no >> 7
	if msb != 128 and idx.has(msb * 128 + program):
		return idx[msb * 128 + program]
	return idx.get(program, -1)


## The finished zones of preset `p` (built once, then cached).
func _zones_for(p: int) -> PackedInt32Array:
	var d := _data
	d.mutex.lock()
	if d.zones.has(p):
		var z: PackedInt32Array = d.zones[p]
		d.mutex.unlock()
		return z
	var out := PackedInt32Array()
	var pz := _read_zones(d.preset_bags[p], d.preset_bags[p + 1], d.pbag_gen, d.pgen_oper, d.pgen_amount, G_INSTRUMENT)
	var pglobal: Dictionary = pz[0]
	for zi in range(1, pz.size()):
		var z: Dictionary = pz[zi]
		var inst: int = z.link
		if inst < 0 or inst >= d.inst_bags.size() - 1:
			continue
		var pkey := _range_of(z, pglobal, "key")
		var pvel := _range_of(z, pglobal, "vel")
		# Preset offsets: global, replaced by local.
		var add: Dictionary = pglobal.gens.duplicate()
		add.merge(z.gens, true)
		var iz := _read_zones(d.inst_bags[inst], d.inst_bags[inst + 1], d.ibag_gen, d.igen_oper, d.igen_amount, G_SAMPLE_ID)
		var iglobal: Dictionary = iz[0]
		for zj in range(1, iz.size()):
			var y: Dictionary = iz[zj]
			var sid: int = y.link
			if sid < 0 or sid >= d.samples.size() or (d.samples[sid].type & 0x8000) != 0:
				continue
			var ikey := _range_of(y, iglobal, "key")
			var ivel := _range_of(y, iglobal, "vel")
			var key := Vector2i(maxi(pkey.x, ikey.x), mini(pkey.y, ikey.y))
			var vel := Vector2i(maxi(pvel.x, ivel.x), mini(pvel.y, ivel.y))
			if key.x > key.y or vel.x > vel.y:
				continue
			var g := _defaults()
			for oper in iglobal.gens:
				g[oper] = iglobal.gens[oper]
			for oper in y.gens:
				g[oper] = y.gens[oper]
			for oper in add:
				if not _INSTRUMENT_ONLY.has(oper):
					g[oper] += add[oper]
			g.append(key.x)
			g.append(key.y)
			g.append(vel.x)
			g.append(vel.y)
			g.append(sid)
			out.append_array(g)
	d.zones[p] = out
	d.mutex.unlock()
	return out


## Reads bags [from, to) as zones: [global, local...]. Each zone is {"gens": {oper: value},
## "key": Vector2i or null, "vel": ..., "link": instrument / sample index or -1}. The global entry
## is an empty zone when the list has none.
static func _read_zones(from: int, to: int, bag_gen: PackedInt32Array, oper: PackedInt32Array, amount: PackedInt32Array, link_gen: int) -> Array:
	var zones := []
	for b in range(from, to):
		if b + 1 >= bag_gen.size():
			break
		var z := {"gens": {}, "key": null, "vel": null, "link": -1}
		for gi in range(bag_gen[b], mini(bag_gen[b + 1], oper.size())):
			var o := oper[gi]
			var a := amount[gi]
			if o == G_KEY_RANGE:
				z.key = Vector2i(a & 0xff, (a >> 8) & 0xff)
			elif o == G_VEL_RANGE:
				z.vel = Vector2i(a & 0xff, (a >> 8) & 0xff)
			elif o == link_gen:
				z.link = a & 0xffff
				break  # the index generator ends a zone
			elif o < _GEN_COUNT and o != G_INSTRUMENT and o != G_SAMPLE_ID:
				z.gens[o] = _signed(a)
		zones.append(z)
	var global := {"gens": {}, "key": null, "vel": null, "link": -1}
	if not zones.is_empty() and zones[0].link < 0:
		global = zones.pop_front()
	zones.push_front(global)
	return zones


static func _range_of(z: Dictionary, global: Dictionary, which: String) -> Vector2i:
	if z[which] != null:
		return z[which]
	if global[which] != null:
		return global[which]
	return Vector2i(0, 127)


static func _signed(a: int) -> int:
	return a - 0x10000 if a >= 0x8000 else a


static func _defaults() -> PackedInt32Array:
	var g := PackedInt32Array()
	g.resize(_GEN_COUNT)
	g.fill(0)
	g[8] = 13500  # initialFilterFc
	for i in [21, 23, 25, 26, 27, 28, 30, 33, 34, 35, 36, 38]:
		g[i] = -12000
	g[G_KEYNUM] = -1
	g[G_VELOCITY] = -1
	g[G_SCALE_TUNING] = 100
	g[G_ROOT_KEY] = -1
	return g


## Timecents to seconds, clamped to the generator's legal range.
static func _tc(v: float, hi: float) -> float:
	if v <= -32768.0:
		return 0.0
	return pow(2.0, clampf(v, -12000.0, hi) / 1200.0)


func _make_region(z: PackedInt32Array, i: int, key: int) -> Region:
	var d := _data
	var s: Sf2Sample = d.samples[z[i + Z_SAMPLE]]
	var start := s.start + z[i + G_START_OFS] + 32768 * z[i + G_START_COARSE]
	var end := s.end + z[i + G_END_OFS] + 32768 * z[i + G_END_COARSE]
	var ls := s.loop_start + z[i + G_LOOP_START_OFS] + 32768 * z[i + G_LOOP_START_COARSE]
	var le := s.loop_end + z[i + G_LOOP_END_OFS] + 32768 * z[i + G_LOOP_END_COARSE]
	start = clampi(start, 0, d.smpl_frames)
	end = clampi(end, start, d.smpl_frames)
	if end - start < 2:
		return null
	var r := Region.new()
	r.samples = _pcm(z[i + Z_SAMPLE], start, end)
	r.sample_rate = s.rate if s.rate > 0 else 44100
	var modes := z[i + G_SAMPLE_MODES] & 3
	r.loop_start = clampi(ls - start, 0, end - start)
	r.loop_end = clampi(le - start, 0, end - start)
	if r.loop_end - r.loop_start >= 2:
		r.loop_mode = 1 if modes == 1 else (2 if modes == 3 else 0)
	var root: int = z[i + G_ROOT_KEY]
	if root < 0 or root > 127:
		root = s.pitch if s.pitch <= 127 else 60
	r.scale_tuning = z[i + G_SCALE_TUNING] / 100.0
	var tune: float = z[i + G_COARSE_TUNE] + (z[i + G_FINE_TUNE] + s.correction) / 100.0
	# Tuning moves the pitch up; the renderer plays (key - root_key) * scale_tuning semitones, so
	# fold it into the root key. A zone that ignores the key (scaleTuning 0) keeps its own pitch.
	r.root_key = root - (tune / r.scale_tuning if r.scale_tuning > 0.001 else 0.0)
	r.attenuation_db = maxf(0.0, z[i + G_ATTENUATION] * ATTENUATION_FACTOR / 10.0)
	r.pan = clampf(z[i + G_PAN] / 500.0, -1.0, 1.0)
	r.delay = _tc(z[i + G_DELAY_VOL], 5000.0)
	r.attack = _tc(z[i + G_ATTACK_VOL], 8000.0)
	r.hold = _tc(z[i + G_HOLD_VOL] + z[i + G_KEY_TO_HOLD] * (60 - key), 5000.0)
	var sus_cb := clampf(z[i + G_SUSTAIN_VOL], 0.0, 1440.0)
	r.sustain = pow(10.0, -sus_cb / 200.0)
	# decayVolEnv is the time for the full 100 dB fall; the envelope reaches the sustain level after
	# the matching part of it.
	r.decay = _tc(z[i + G_DECAY_VOL] + z[i + G_KEY_TO_DECAY] * (60 - key), 8000.0) * minf(sus_cb, 1000.0) / 1000.0
	r.release = _tc(z[i + G_RELEASE_VOL], 8000.0)
	r.exclusive_class = z[i + G_EXCLUSIVE]
	return r


## Sample frames [start, end) as floats, converted once and shared.
func _pcm(sample: int, start: int, end: int) -> PackedFloat32Array:
	var d := _data
	var k := Vector3i(sample, start, end)
	d.mutex.lock()
	var out: PackedFloat32Array = d.pcm.get(k, PackedFloat32Array())
	if out.is_empty():
		out.resize(end - start)
		var b := d.bytes
		var ofs := d.smpl_offset + start * 2
		for f in end - start:
			out[f] = b.decode_s16(ofs + f * 2) * (1.0 / 32768.0)
		d.pcm[k] = out
	d.mutex.unlock()
	return out


# --- parsing ---------------------------------------------------------------------------------

static func _parse(b: PackedByteArray, d: Sf2Data) -> String:
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "sfbk":
		return "'%s' is not a SoundFont 2 file." % d.file_name
	d.bytes = b
	var end := mini(b.size(), 8 + b.decode_u32(4))
	var pdta := {}
	var pos := 12
	while pos + 8 <= end:
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		var body := pos + 8
		if id == "LIST" and body + 4 <= end:
			var kind := b.slice(body, body + 4).get_string_from_ascii()
			var sub := body + 4
			var sub_end := mini(end, body + size)
			while sub + 8 <= sub_end:
				var sid := b.slice(sub, sub + 4).get_string_from_ascii()
				var ssize := b.decode_u32(sub + 4)
				if kind == "sdta" and sid == "smpl":
					d.smpl_offset = sub + 8
					d.smpl_frames = mini(ssize, sub_end - sub - 8) / 2
				elif kind == "pdta":
					pdta[sid] = Vector2i(sub + 8, mini(ssize, sub_end - sub - 8))
				sub += 8 + ssize + (ssize & 1)
		pos = body + size + (size & 1)
	for need in ["phdr", "pbag", "pgen", "inst", "ibag", "igen", "shdr"]:
		if not pdta.has(need):
			return "'%s' is not a complete SoundFont (no '%s' chunk)." % [d.file_name, need]
	if d.smpl_frames <= 0:
		return "'%s' has no sample data." % d.file_name
	var c: Vector2i = pdta.phdr
	for r in c.y / 38:
		var o := c.x + r * 38
		d.preset_names.append(_name(b, o))
		d.preset_programs.append(b.decode_u16(o + 20))
		d.preset_banks.append(b.decode_u16(o + 22))
		d.preset_bags.append(b.decode_u16(o + 24))
	for i in d.preset_names.size() - 1:
		var k := d.preset_banks[i] * 128 + d.preset_programs[i]
		if not d.preset_index.has(k):
			d.preset_index[k] = i
	_read_bags(b, pdta.pbag, d.pbag_gen)
	_read_gens(b, pdta.pgen, d.pgen_oper, d.pgen_amount)
	c = pdta.inst
	for r in c.y / 22:
		var o := c.x + r * 22
		d.inst_names.append(_name(b, o))
		d.inst_bags.append(b.decode_u16(o + 20))
	_read_bags(b, pdta.ibag, d.ibag_gen)
	_read_gens(b, pdta.igen, d.igen_oper, d.igen_amount)
	c = pdta.shdr
	for r in c.y / 46:
		var o := c.x + r * 46
		var s := Sf2Sample.new()
		s.name = _name(b, o)
		s.start = b.decode_u32(o + 20)
		s.end = b.decode_u32(o + 24)
		s.loop_start = b.decode_u32(o + 28)
		s.loop_end = b.decode_u32(o + 32)
		s.rate = b.decode_u32(o + 36)
		s.pitch = b.decode_u8(o + 40)
		s.correction = b.decode_s8(o + 41)
		s.link = b.decode_u16(o + 42)
		s.type = b.decode_u16(o + 44)
		d.samples.append(s)
	if d.preset_names.size() < 2:
		return "'%s' has no presets." % d.file_name
	return ""


static func _read_bags(b: PackedByteArray, c: Vector2i, gen_ndx: PackedInt32Array) -> void:
	gen_ndx.resize(c.y / 4)
	for r in c.y / 4:
		gen_ndx[r] = b.decode_u16(c.x + r * 4)


static func _read_gens(b: PackedByteArray, c: Vector2i, oper: PackedInt32Array, amount: PackedInt32Array) -> void:
	var n := c.y / 4
	oper.resize(n)
	amount.resize(n)
	for r in n:
		oper[r] = b.decode_u16(c.x + r * 4)
		amount[r] = b.decode_u16(c.x + r * 4 + 2)


static func _name(b: PackedByteArray, o: int) -> String:
	return b.slice(o, o + 20).get_string_from_ascii().strip_edges()
