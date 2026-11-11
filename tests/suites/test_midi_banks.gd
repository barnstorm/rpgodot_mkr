extends "res://tests/rpg_test_case.gd"
## The MIDI renderer's sound banks: RPGSf2Bank and RPGDlsBank read tiny files built here byte by
## byte (never a real bank), and RPGBuiltinBank's generated instruments.


# --- byte builders ---------------------------------------------------------------------------

func _u8(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xff])


func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v & 0xffff)
	return b


func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v & 0xffffffff)
	return b


func _name20(s: String) -> PackedByteArray:
	var b := s.to_ascii_buffer()
	b.resize(20)
	return b


func _cat(parts: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for p in parts:
		out.append_array(p)
	return out


func _chunk(id: String, body: PackedByteArray) -> PackedByteArray:
	var out := _cat([id.to_ascii_buffer(), _u32(body.size()), body])
	if body.size() % 2 == 1:
		out.append(0)
	return out


func _list(kind: String, children: Array, outer := "LIST") -> PackedByteArray:
	return _chunk(outer, _cat([kind.to_ascii_buffer()] + children))


# --- a tiny SoundFont ------------------------------------------------------------------------

const G_START := 0
const G_END := 1
const G_LOOP_START := 2
const G_LOOP_END := 3
const G_PAN := 17
const G_HOLD := 35
const G_ATTACK := 34
const G_DECAY := 36
const G_SUSTAIN := 37
const G_KEY_TO_DECAY := 40
const G_INSTRUMENT := 41
const G_KEYS := 43
const G_VELS := 44
const G_ATTEN := 48
const G_COARSE := 51
const G_FINE := 52
const G_SAMPLE := 53
const G_MODES := 54
const G_SCALE := 56
const G_EXCLUSIVE := 57
const G_ROOT := 58


func _range(lo: int, hi: int) -> int:
	return lo | (hi << 8)


## Writes zones ([[oper, amount], ...] each) as bag + generator records, starting at the given
## generator index; returns [bags, gens].
func _zones(zone_lists: Array, bags: PackedByteArray, gens: PackedByteArray) -> void:
	for zone in zone_lists:
		bags.append_array(_cat([_u16(gens.size() / 4), _u16(0)]))
		for g in zone:
			gens.append_array(_cat([_u16(g[0]), _u16(g[1])]))


func _sf2() -> PackedByteArray:
	# Samples: A = 100-frame ramp (frame i = i * 100), L = 50 frames of 1000, R = 50 of -1000.
	var smpl := PackedByteArray()
	smpl.resize(200 * 2)
	for i in 100:
		smpl.encode_s16(i * 2, i * 100)
	for i in range(100, 150):
		smpl.encode_s16(i * 2, 1000)
	for i in range(150, 200):
		smpl.encode_s16(i * 2, -1000)
	var shdr := _cat([
		_name20("A"), _u32(0), _u32(100), _u32(20), _u32(80), _u32(22050), _u8(60), _u8(10), _u16(0), _u16(1),
		_name20("L"), _u32(100), _u32(150), _u32(110), _u32(140), _u32(44100), _u8(60), _u8(0), _u16(2), _u16(4),
		_name20("R"), _u32(150), _u32(200), _u32(160), _u32(190), _u32(44100), _u8(60), _u8(0), _u16(1), _u16(2),
		_name20("EOS"), _u32(0), _u32(0), _u32(0), _u32(0), _u32(0), _u8(0), _u8(0), _u16(0), _u16(0),
	])
	var instruments := [
		["Lead", [
			[[G_ATTACK, 1200], [G_ATTEN, 100], [G_PAN, -250 & 0xffff]],  # global zone
			[[G_KEYS, _range(0, 59)], [G_MODES, 1], [G_ROOT, 57], [G_COARSE, 2], [G_FINE, -50 & 0xffff],
				[G_SUSTAIN, 200], [G_DECAY, 0], [G_KEY_TO_DECAY, 100], [G_HOLD, -1200 & 0xffff],
				[G_EXCLUSIVE, 3], [G_START, 4], [G_END, -6 & 0xffff], [G_LOOP_START, 2],
				[G_LOOP_END, -2 & 0xffff], [G_SAMPLE, 0]],
			[[G_KEYS, _range(60, 127)], [G_VELS, _range(0, 63)], [G_MODES, 3], [G_PAN, 100], [G_SAMPLE, 0]],
			[[G_KEYS, _range(60, 127)], [G_VELS, _range(64, 127)], [G_SCALE, 50], [G_SAMPLE, 0]],
		]],
		["Stereo", [[[G_SAMPLE, 1]], [[G_SAMPLE, 2]]]],
		["Drum", [[[G_KEYS, _range(36, 36)], [G_EXCLUSIVE, 1], [G_SAMPLE, 0]],
			[[G_KEYS, _range(42, 42)], [G_PAN, 300], [G_SAMPLE, 0]]]],
		["Half", [[[G_SAMPLE, 1]]]],
	]
	var presets := [
		# name, program, bank, zones
		["Lead", 0, 0, [
			[[G_KEYS, _range(10, 100)], [G_ATTACK, 1200], [G_ATTEN, 50]],  # global zone
			[[G_VELS, _range(10, 127)], [G_COARSE, 1], [G_MODES, 0], [G_INSTRUMENT, 0]]]],
		["Stereo", 1, 0, [[[G_INSTRUMENT, 1]]]],
		["Variation", 0, 8, [[[G_INSTRUMENT, 1]]]],
		["Kit", 0, 128, [[[G_INSTRUMENT, 2]]]],
		["Half", 2, 0, [[[G_INSTRUMENT, 3]]]],
	]
	var inst := PackedByteArray()
	var ibag := PackedByteArray()
	var igen := PackedByteArray()
	for i in instruments:
		inst.append_array(_cat([_name20(i[0]), _u16(ibag.size() / 4)]))
		_zones(i[1], ibag, igen)
	inst.append_array(_cat([_name20("EOI"), _u16(ibag.size() / 4)]))
	ibag.append_array(_cat([_u16(igen.size() / 4), _u16(0)]))
	igen.append_array(_u32(0))
	var phdr := PackedByteArray()
	var pbag := PackedByteArray()
	var pgen := PackedByteArray()
	for p in presets:
		phdr.append_array(_cat([_name20(p[0]), _u16(p[1]), _u16(p[2]), _u16(pbag.size() / 4), _u32(0), _u32(0), _u32(0)]))
		_zones(p[3], pbag, pgen)
	phdr.append_array(_cat([_name20("EOP"), _u16(0), _u16(0), _u16(pbag.size() / 4), _u32(0), _u32(0), _u32(0)]))
	pbag.append_array(_cat([_u16(pgen.size() / 4), _u16(0)]))
	pgen.append_array(_u32(0))
	var mod_end := PackedByteArray()
	mod_end.resize(10)
	return _list("sfbk", [
		_list("INFO", [_chunk("ifil", _cat([_u16(2), _u16(1)])), _chunk("INAM", "Test".to_ascii_buffer() + PackedByteArray([0]))]),
		_list("sdta", [_chunk("smpl", smpl)]),
		_list("pdta", [_chunk("phdr", phdr), _chunk("pbag", pbag), _chunk("pmod", mod_end),
			_chunk("pgen", pgen), _chunk("inst", inst), _chunk("ibag", ibag), _chunk("imod", mod_end),
			_chunk("igen", igen), _chunk("shdr", shdr)]),
	], "RIFF")


func _sf2_bank() -> RPGSf2Bank:
	var bank := RPGSf2Bank.new()
	var err := bank.load_bytes(_sf2(), "test.sf2")
	assert_eq(err, "", "tiny SoundFont parses")
	return bank


func test_sf2_zone_generators_and_units() -> void:
	var bank := _sf2_bank()
	assert_eq(bank.presets().size(), 5)
	var rs := bank.regions_for(0, 0, 50, 100, false)
	assert_eq(rs.size(), 1, "one zone for key 50")
	if rs.size() != 1:
		return
	var r: RPGSoundBank.Region = rs[0]
	# Address offsets: frames 4..94 of sample A, loop 22..78 -> 18..74 relative.
	assert_eq(r.samples.size(), 90)
	assert_true(absf(r.samples[0] - 400.0 / 32768.0) < 1e-6, "first frame is sample frame 4")
	assert_eq(r.loop_start, 18)
	assert_eq(r.loop_end, 74)
	assert_eq(r.loop_mode, 1, "preset-level sampleModes is ignored")
	assert_eq(r.sample_rate, 22050)
	# Root 57 (overridingRootKey), tune = coarse 2 + preset 1, fine -50 + correction 10 cents.
	assert_true(absf(r.root_key - 54.4) < 1e-4, "root key %f" % r.root_key)
	assert_eq(r.scale_tuning, 1.0)
	# 100 cB + preset 50 cB, times the 0.4 EMU factor, in dB.
	assert_true(absf(r.attenuation_db - 6.0) < 1e-4, "attenuation %f" % r.attenuation_db)
	assert_true(absf(r.pan + 0.5) < 1e-6, "global zone pan -250")
	assert_true(absf(r.attack - 4.0) < 1e-4, "attack 1200 + 1200 tc = 4 s, got %f" % r.attack)
	assert_true(absf(r.hold - 0.5) < 1e-4, "hold -1200 tc")
	assert_true(absf(r.sustain - 0.1) < 1e-6, "200 cB sustain is 0.1")
	# decay 0 tc + keynumToVolEnvDecay 100 * (60 - 50) = 1000 tc, over the 20 dB to sustain.
	assert_true(absf(r.decay - pow(2.0, 1000.0 / 1200.0) * 0.2) < 1e-4, "decay %f" % r.decay)
	assert_true(absf(r.release - 0.001) < 1e-4, "default release -12000 tc")
	assert_eq(r.exclusive_class, 3)


func test_sf2_ranges_and_layers() -> void:
	var bank := _sf2_bank()
	assert_eq(bank.regions_for(0, 0, 5, 100, false).size(), 0, "outside the preset's global key range")
	assert_eq(bank.regions_for(0, 0, 50, 5, false).size(), 0, "outside the preset zone's velocity range")
	var soft := bank.regions_for(0, 0, 70, 30, false)
	assert_eq(soft.size(), 1)
	if soft.size() == 1:
		assert_true(absf(soft[0].pan - 0.2) < 1e-6, "local pan replaces the global one")
		assert_eq(soft[0].loop_mode, 2, "sampleModes 3 loops until note-off")
		assert_eq(soft[0].samples.size(), 100)
	var loud := bank.regions_for(0, 0, 70, 100, false)
	assert_eq(loud.size(), 1)
	if loud.size() == 1:
		assert_eq(loud[0].scale_tuning, 0.5)
		# Tuning 1 semitone (preset) + 10 cents correction, folded through scaleTuning 0.5.
		assert_true(absf(loud[0].root_key - (60.0 - 1.1 / 0.5)) < 1e-4, "root %f" % loud[0].root_key)


func test_sf2_stereo_pairs_and_fallbacks() -> void:
	var bank := _sf2_bank()
	var st := bank.regions_for(0, 1, 60, 100, false)
	assert_eq(st.size(), 2, "both halves of the stereo pair")
	if st.size() == 2:
		assert_eq(st[0].pan, -1.0, "left half")
		assert_eq(st[1].pan, 1.0, "right half")
		assert_true(absf(st[0].samples[0] - 1000.0 / 32768.0) < 1e-6)
		assert_true(absf(st[1].samples[0] + 1000.0 / 32768.0) < 1e-6)
		assert_eq(st[0].loop_mode, 0, "no sampleModes: plays once")
	var half := bank.regions_for(0, 2, 60, 100, false)
	assert_eq(half.size(), 1)
	if half.size() == 1:
		assert_eq(half[0].pan, 0.0, "a stereo half alone stays centred")
	# Samples are converted once and shared.
	bank.regions_for(0, 1, 61, 100, false)
	assert_eq(bank._data.pcm.size(), 2, "L and R converted once each")
	# Bank variation, CC32 ignored, unknown variation -> bank 0, unknown program -> silence.
	assert_eq(bank.regions_for(8 * 128, 0, 60, 100, false).size(), 2, "bank 8 variation")
	assert_eq(bank.regions_for(8 * 128 + 5, 0, 60, 100, false).size(), 2, "CC32 ignored")
	assert_eq(bank.regions_for(9 * 128, 0, 50, 100, false).size(), 1, "unknown bank -> bank 0")
	assert_eq(bank.regions_for(0, 50, 60, 100, false).size(), 0, "unknown program is silent")
	# Drums: bank 128, unknown kit -> kit 0.
	var kick := bank.regions_for(0, 0, 36, 100, true)
	assert_eq(kick.size(), 1)
	if kick.size() == 1:
		assert_eq(kick[0].exclusive_class, 1)
	var hat := bank.regions_for(0, 25, 42, 100, true)
	assert_eq(hat.size(), 1, "unknown kit uses kit 0")
	if hat.size() == 1:
		assert_true(absf(hat[0].pan - 0.6) < 1e-6)
	assert_eq(bank.regions_for(0, 0, 50, 100, true).size(), 0, "no drum on that key")


func test_sf2_rejects_bad_files() -> void:
	var bank := RPGSf2Bank.new()
	assert_ne(bank.load_bytes(PackedByteArray([1, 2, 3])), "")
	assert_ne(bank.load_bytes(_list("sfbk", [_list("sdta", [])], "RIFF")), "", "no pdta")


func test_open_by_path_caches() -> void:
	var path := OS.get_user_data_dir().path_join("test_midi_banks.sf2")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_sf2())
	f.close()
	var a = RPGSoundBank.open(path)
	var b = RPGSoundBank.open(path)
	assert_true(a is RPGSf2Bank, "opens as a SoundFont: " + RPGSoundBank.last_error)
	if a is RPGSf2Bank and b is RPGSf2Bank:
		assert_true(a._data == b._data, "second open reuses the parsed file")
		assert_eq(a.bank_name(), "test_midi_banks.sf2")
	DirAccess.remove_absolute(path)
	RPGSf2Bank.clear_cache()
	assert_eq(RPGSoundBank.open(path), null, "missing file")
	assert_ne(RPGSoundBank.last_error, "")
	assert_eq(RPGSoundBank.open("song.mid"), null, "not a bank")
	assert_true(RPGSoundBank.open("builtin") is RPGBuiltinBank)
	assert_true(RPGSoundBank.open("") is RPGBuiltinBank)


# --- a tiny DLS ------------------------------------------------------------------------------

const ABS_ZERO := 0x80000000


func _tc(seconds: float) -> int:
	return roundi(1200.0 * log(seconds) / log(2.0) * 65536.0)


func _art(kind: String, conns: Array) -> PackedByteArray:
	var body := _cat([_u32(8), _u32(conns.size())])
	for c in conns:  # [source, destination, scale]
		body.append_array(_cat([_u16(c[0]), _u16(0), _u16(c[1]), _u16(0), _u32(c[2])]))
	return _chunk(kind, body)


func _wsmp(unity: int, fine: int, atten: int, loop_type: int, loop_start: int, loop_len: int) -> PackedByteArray:
	var body := _cat([_u32(20), _u16(unity), _u16(fine), _u32(atten), _u32(0), _u32(1 if loop_type >= 0 else 0)])
	if loop_type >= 0:
		body.append_array(_cat([_u32(16), _u32(loop_type), _u32(loop_start), _u32(loop_len)]))
	return _chunk("wsmp", body)


func _rgn(lo: int, hi: int, group: int, wave: int, extra: Array) -> PackedByteArray:
	var rgnh := _chunk("rgnh", _cat([_u16(lo), _u16(hi), _u16(0), _u16(127), _u16(0), _u16(group)]))
	var wlnk := _chunk("wlnk", _cat([_u16(0), _u16(0), _u32(1), _u32(wave)]))
	return _list("rgn ", [rgnh] + extra + [wlnk])


func _ins(bank: int, program: int, name: String, regions: Array, arts: Array) -> PackedByteArray:
	var insh := _chunk("insh", _cat([_u32(regions.size()), _u32(bank), _u32(program)]))
	return _list("ins ", [insh, _list("lrgn", regions)] + arts + [_list("INFO", [_chunk("INAM", name.to_ascii_buffer() + PackedByteArray([0]))])])


func _wave(bits: int, rate: int, data: PackedByteArray, wsmp: PackedByteArray) -> PackedByteArray:
	var align := bits / 8
	var fmt := _chunk("fmt ", _cat([_u16(1), _u16(1), _u32(rate), _u32(rate * align), _u16(align), _u16(bits)]))
	return _list("wave", [fmt, wsmp, _chunk("data", data)])


func _dls() -> PackedByteArray:
	# Wave A: 16-bit ramp, 8 frames. Wave B: 8-bit unsigned, 6 frames, its own wsmp with a loop.
	var a := PackedByteArray()
	a.resize(16)
	for i in 8:
		a.encode_s16(i * 2, i * 4096)
	var wave_a := _wave(16, 11025, a, _wsmp(62, 0, 0, -1, 0, 0))
	var wave_b := _wave(8, 8000, PackedByteArray([128, 255, 0, 192, 64, 128]), _wsmp(48, 0, -655360, 0, 1, 4))
	# Pool order is B then A; the cue table lists A first, so wlnk 0 = A and wlnk 1 = B.
	var ptbl := _chunk("ptbl", _cat([_u32(8), _u32(2), _u32(wave_b.size()), _u32(0)]))
	var wvpl := _list("wvpl", [wave_b, wave_a])
	var inst_art := _list("lart", [_art("art1", [
		[0, 0x0206, _tc(0.25)], [0, 0x0207, 0], [0, 0x020a, 500 * 65536], [0, 0x0209, _tc(0.5)],
		[3, 0x0207, -1200 * 65536], [2, 0x0001, -960 * 65536]])])
	var inst_art2 := _list("lar2", [_art("art2", [
		[0, 0x020b, _tc(0.5)], [0, 0x020c, _tc(0.25)], [0, 0x0004, 250 * 65536], [0, 0x0001, -30 * 65536]])])
	var rgn_art := _list("lart", [_art("art1", [[0, 0x0206, _tc(0.5)], [0, 0x0209, ABS_ZERO]])])
	var piano := _ins(0, 0, "Piano", [
		_rgn(0, 63, 2, 0, [_wsmp(60, -25, -3 * 655360, 1, 2, 4)]),
		_rgn(64, 127, 0, 1, [rgn_art]),
	], [inst_art, inst_art2])
	var variation := _ins(8 << 8, 0, "Piano 2", [_rgn(0, 127, 0, 1, [])], [])
	var kit := _ins(0x80000000, 0, "Standard", [_rgn(36, 36, 1, 0, [])], [])
	var lins := _list("lins", [piano, variation, kit])
	return _list("DLS ", [_chunk("colh", _u32(3)), lins, ptbl, wvpl], "RIFF")


func _dls_bank() -> RPGDlsBank:
	var bank := RPGDlsBank.new()
	assert_eq(bank.load_bytes(_dls(), "test.dls"), "", "tiny DLS parses")
	return bank


func test_dls_regions_and_articulation() -> void:
	var bank := _dls_bank()
	assert_eq(bank.presets().size(), 3)
	assert_eq(bank.presets()[0].name, "Piano")
	assert_true(bank.presets()[2].drums)
	var rs := bank.regions_for(0, 0, 60, 100, false)
	assert_eq(rs.size(), 1)
	if rs.size() != 1:
		return
	var r: RPGSoundBank.Region = rs[0]
	assert_eq(r.samples.size(), 8, "16-bit wave A through the cue table")
	assert_true(absf(r.samples[1] - 4096.0 / 32768.0) < 1e-6)
	assert_eq(r.sample_rate, 11025)
	assert_true(absf(r.root_key - 60.25) < 1e-6, "unity 60, fine -25 cents")
	assert_eq(r.loop_mode, 2, "release loop")
	assert_eq(r.loop_start, 2)
	assert_eq(r.loop_end, 6)
	# wsmp 3 dB plus the articulation's -30 cB gain.
	assert_true(absf(r.attenuation_db - 6.0) < 1e-4, "attenuation %f" % r.attenuation_db)
	assert_eq(r.exclusive_class, 2)
	assert_true(absf(r.attack - 0.25) < 1e-4)
	assert_true(absf(r.delay - 0.5) < 1e-4)
	assert_true(absf(r.hold - 0.25) < 1e-4)
	assert_true(absf(r.release - 0.5) < 1e-4)
	assert_true(absf(r.pan - 0.5) < 1e-6)
	# Sustain 50 % of the 96 dB scale; decay 0 tc - 1200 * 60 / 128 tc, over half the scale.
	assert_true(absf(r.sustain - db_to_linear(-48.0)) < 1e-6, "sustain %f" % r.sustain)
	assert_true(absf(r.decay - pow(2.0, -1200.0 * 60.0 / 128.0 / 1200.0) * 0.5) < 1e-4, "decay %f" % r.decay)


func test_dls_region_articulation_and_8bit() -> void:
	var bank := _dls_bank()
	var rs := bank.regions_for(0, 0, 70, 100, false)
	assert_eq(rs.size(), 1)
	if rs.size() != 1:
		return
	var r: RPGSoundBank.Region = rs[0]
	assert_eq(r.samples.size(), 6, "8-bit wave B")
	assert_eq(r.samples[0], 0.0)
	assert_true(absf(r.samples[1] - 127.0 / 128.0) < 1e-6)
	assert_eq(r.samples[2], -1.0)
	assert_eq(r.sample_rate, 8000)
	assert_eq(r.root_key, 48.0, "wave-level wsmp when the region has none")
	assert_eq(r.loop_mode, 1)
	assert_eq(r.loop_start, 1)
	assert_eq(r.loop_end, 5)
	assert_true(absf(r.attenuation_db - 1.0) < 1e-4)
	# The region's own articulation replaces the instrument's completely.
	assert_true(absf(r.attack - 0.5) < 1e-4)
	assert_eq(r.release, 0.0, "absolute zero time cents")
	assert_eq(r.delay, 0.0)
	assert_eq(r.sustain, 1.0)
	assert_eq(r.pan, 0.0)


func test_dls_fallbacks_and_drums() -> void:
	var bank := _dls_bank()
	var v := bank.regions_for(8 * 128, 0, 60, 100, false)
	assert_eq(v.size(), 1)
	if v.size() == 1:
		assert_eq(v[0].samples.size(), 6, "bank 8 variation plays wave B")
	assert_eq(bank.regions_for(8 * 128 + 3, 0, 60, 100, false)[0].samples.size(), 6, "unknown CC32 -> CC32 0")
	assert_eq(bank.regions_for(5 * 128, 0, 60, 100, false)[0].samples.size(), 8, "unknown bank -> bank 0")
	assert_eq(bank.regions_for(0, 7, 60, 100, false).size(), 0, "unknown program is silent")
	var kick := bank.regions_for(0, 16, 36, 100, true)
	assert_eq(kick.size(), 1, "unknown kit -> kit 0")
	if kick.size() == 1:
		assert_eq(kick[0].exclusive_class, 1)
	assert_eq(bank.regions_for(0, 0, 37, 100, true).size(), 0)
	assert_ne(RPGDlsBank.new().load_bytes(_list("DLS ", [], "RIFF")), "", "empty DLS is refused")


# --- built-in instruments --------------------------------------------------------------------

func test_builtin_programs() -> void:
	assert_true(RPGSoundBank.open("builtin") is RPGBuiltinBank)
	var bank := RPGBuiltinBank.new()
	assert_eq(bank.presets().size(), 129)
	for p in 128:
		for key in [24, 60, 100]:
			var rs := bank.regions_for(0, p, key, 100, false)
			if rs.size() != 1:
				fail("program %d key %d: %d regions" % [p, key, rs.size()])
				continue
			var r: RPGSoundBank.Region = rs[0]
			if r.samples.size() < 2 or r.loop_mode == 0 or r.loop_end > r.samples.size() or r.loop_start >= r.loop_end:
				fail("program %d key %d: bad sample or loop" % [p, key])
	assert_eq(bank.regions_for(0, 128, 60, 100, false).size(), 0)
	assert_eq(bank.regions_for(5 * 128, 0, 60, 100, false).size(), 1, "any bank plays the family")
	# A single-cycle zone is in tune: TABLE frames at RATE is its root key.
	var r: RPGSoundBank.Region = bank.regions_for(0, 80, 60, 100, false)[0]
	var hz := 440.0 * pow(2.0, (r.root_key - 69.0) / 12.0)
	assert_eq(r.samples.size(), RPGBuiltinBank.TABLE, "synth lead loops one cycle")
	assert_true(absf(hz - float(r.sample_rate) / RPGBuiltinBank.TABLE) < 0.01, "root key matches the cycle length")
	# Generated once: the same key range gives the same cached data.
	assert_eq(bank.regions_for(0, 1, 61, 100, false)[0].samples, bank.regions_for(0, 2, 62, 100, false)[0].samples, "same family, same zone")


func test_builtin_drums() -> void:
	var bank := RPGBuiltinBank.new()
	for key in range(35, 82):
		var rs := bank.regions_for(0, 0, key, 100, true)
		if rs.size() != 1 or rs[0].samples.size() < 100:
			fail("drum key %d has no sound" % key)
			continue
		var peak := 0.0
		for v in rs[0].samples:
			peak = maxf(peak, absf(v))
		if peak < 0.1 or peak > 1.0:
			fail("drum key %d peak %f" % [key, peak])
	var closed: RPGSoundBank.Region = bank.regions_for(0, 0, 42, 100, true)[0]
	var open: RPGSoundBank.Region = bank.regions_for(0, 0, 46, 100, true)[0]
	assert_ne(closed.exclusive_class, 0, "hi-hats choke each other")
	assert_eq(closed.exclusive_class, open.exclusive_class)
	assert_true(open.samples.size() > closed.samples.size(), "open hat rings longer")
	assert_eq(bank.regions_for(0, 0, 36, 100, true)[0].exclusive_class, 0)
	assert_eq(bank.regions_for(0, 40, 38, 100, true).size(), 1, "any kit")
	assert_eq(bank.regions_for(0, 0, 10, 100, true).size(), 0, "no drum on key 10")
	# Toms rise in pitch from low floor to high tom.
	var low: RPGSoundBank.Region = bank.regions_for(0, 0, 41, 100, true)[0]
	var high: RPGSoundBank.Region = bank.regions_for(0, 0, 50, 100, true)[0]
	assert_true(50 - high.root_key > 41 - low.root_key, "high tom plays higher")
