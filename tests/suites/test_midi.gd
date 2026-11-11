extends "res://tests/rpg_test_case.gd"
## MIDI: the Standard MIDI File reader (RPGMidiFile), the renderer (RPGMidiRenderer), the import
## plugin and the kit wiring (asset lookup, RPGAudio reverb bus, RPG Maker import). MIDI bytes are
## built here; the renderer is checked with a sine bank defined in this file.

const Importer := preload("res://addons/rpg/import/midi/rpg_midi_importer.gd")
const RMImport := preload("res://addons/rpg/editor/tools/rpg_maker_import.gd")
const TMP := "user://rpg_midi_test"
const RATE := 32000


## A bank of sine waves: 441 Hz at key 69 (22050 frames at 22050 Hz, 441 whole cycles, looped).
## `pan_by_key` / `excl_by_key` give some keys their own pan or exclusive class.
class SineBank:
	extends RPGSoundBank
	var sine := PackedFloat32Array()
	var release := 0.05
	var attack := 0.0
	var loop_mode := 1
	var pan_by_key := {}
	var excl_by_key := {}
	var missing_programs: Array = []

	func _init() -> void:
		sine.resize(22050)
		for i in 22050:
			sine[i] = sin(TAU * 441.0 * i / 22050.0) * 0.5

	func load_bank(_path: String) -> String:
		return ""

	func regions_for(_bank_no: int, program: int, key: int, _velocity: int, _drums: bool) -> Array:
		if missing_programs.has(program):
			return []
		var r := RPGSoundBank.Region.new()
		r.samples = sine
		r.sample_rate = 22050
		r.root_key = 69.0
		r.loop_mode = loop_mode
		r.loop_start = 0
		r.loop_end = 22050
		r.attack = attack
		r.release = release
		r.pan = float(pan_by_key.get(key, 0.0))
		r.exclusive_class = int(excl_by_key.get(key, 0))
		return [r]

	func bank_name() -> String:
		return "test sines"


func after_each() -> void:
	_rm_tree(TMP)


# --- SMF bytes -----------------------------------------------------------------------------------

static func vlq(v: int) -> PackedByteArray:
	var out := PackedByteArray([v & 0x7f])
	v >>= 7
	while v > 0:
		out.insert(0, (v & 0x7f) | 0x80)
		v >>= 7
	return out


## One MTrk chunk from [[delta, byte, byte, ...], ...]; an end-of-track is added after `eot_delta`.
static func track(events: Array, eot_delta := 0) -> PackedByteArray:
	var body := PackedByteArray()
	for e in events:
		body.append_array(vlq(e[0]))
		for i in range(1, e.size()):
			body.append(e[i])
	body.append_array(vlq(eot_delta))
	body.append_array(PackedByteArray([0xff, 0x2f, 0x00]))
	var out := "MTrk".to_ascii_buffer()
	out.append_array(_be32(body.size()))
	out.append_array(body)
	return out


static func smf(format: int, division: int, tracks: Array) -> PackedByteArray:
	var out := "MThd".to_ascii_buffer()
	out.append_array(_be32(6))
	out.append_array(PackedByteArray([format >> 8, format & 0xff, tracks.size() >> 8, tracks.size() & 0xff, (division >> 8) & 0xff, division & 0xff]))
	for t in tracks:
		out.append_array(t)
	return out


static func _be32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff])


## Format 0 at 480 ticks per quarter, 120 BPM (1 s = 960 ticks): `events` [[delta, bytes...]].
static func song(events: Array, eot_delta := 0) -> RPGMidiFile:
	var m := RPGMidiFile.parse(smf(0, 480, [track(events, eot_delta)]))
	return m


static func render(midi: RPGMidiFile, bank: RPGSoundBank, setup := Callable()) -> Dictionary:
	var r := RPGMidiRenderer.new()
	r.out_rate = RATE
	r.loop = true
	if setup.is_valid():
		setup.call(r)
	var pcm := r.render(midi, bank)
	return {"pcm": pcm, "r": r, "stats": r.stats}


## Zero crossings of one channel (0 left, 1 right) in [from, to) seconds.
static func crossings(pcm: PackedVector2Array, from: float, to: float, ch := 0) -> int:
	var n := 0
	var prev := 0.0
	for i in range(int(from * RATE), mini(int(to * RATE), pcm.size())):
		var s := pcm[i][ch]
		if absf(s) < 0.00001:
			continue
		if prev != 0.0 and (s < 0.0) != (prev < 0.0):
			n += 1
		prev = s
	return n


## Peak of one channel in [from, to) seconds.
static func level(pcm: PackedVector2Array, from: float, to: float, ch := 0) -> float:
	var p := 0.0
	for i in range(int(from * RATE), mini(int(to * RATE), pcm.size())):
		p = maxf(p, absf(pcm[i][ch]))
	return p


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


# --- reader --------------------------------------------------------------------------------------

func test_format0_running_status_and_sysex() -> void:
	# Note on C4, then two more with running status, a sysex and a text meta event between.
	var m := song([
		[0, 0x90, 60, 100],
		[0, 64, 90],
		[240, 67, 80],
		[0, 0xf0, 0x05, 0x7e, 0x7f, 0x09, 0x01, 0xf7],
		[0, 0xff, 0x01, 0x03, 0x61, 0x62, 0x63],
		[240, 0x80, 60, 0],
		[0, 64, 0],
		[0, 67, 0],
	], 480)
	assert_eq(m.error, "")
	assert_eq(m.format, 0)
	assert_eq(m.event_count(), 7, "3 note ons, 3 note offs and the sysex; meta events are not events")
	var ev := m.events()
	assert_eq([ev[1].status, ev[1].data1, ev[1].data2], [0x90, 64, 90], "running status")
	assert_eq(ev[2].time, 0.25, "240 ticks at 480 per quarter and 120 BPM")
	assert_eq(ev[3].status, 0xf0)
	assert_eq(ev[3].sysex, PackedByteArray([0x7e, 0x7f, 0x09, 0x01, 0xf7]))
	assert_eq([ev[4].status, ev[4].data1], [0x80, 60])
	assert_eq([ev[5].status, ev[5].data1], [0x80, 64], "running status after a meta event")
	assert_eq(m.length, 1.0, "the song ends at its end-of-track, past the last note-off")
	assert_eq(m.loop_start, 0.0)
	assert_false(m.has_loop_marker)


func test_format1_tempo_map() -> void:
	# Track 0: 120 BPM, then 240 BPM from tick 960 (1 s). Track 1: notes at ticks 0, 960, 1440.
	var t0 := track([[0, 0xff, 0x51, 0x03, 0x07, 0xa1, 0x20], [960, 0xff, 0x51, 0x03, 0x03, 0xd0, 0x90]])
	var t1 := track([[0, 0x91, 60, 100], [960, 0x91, 62, 100], [480, 0x91, 64, 100], [480, 0x81, 64, 0]], 960)
	var m := RPGMidiFile.parse(smf(1, 480, [t0, t1]))
	assert_eq(m.error, "")
	assert_eq(m.track_count, 2)
	var times := []
	for e in m.events():
		times.append(snappedf(e.time, 0.0001))
	assert_eq(times, [0.0, 1.0, 1.25, 1.5], "tempo doubled at 1 s")
	assert_eq(snappedf(m.length, 0.0001), 2.0, "the latest end-of-track (tick 2880)")
	assert_eq(m.tick_to_seconds(1920), 1.5)


func test_smpte_division_and_bad_files() -> void:
	# 25 frames per second, 40 ticks per frame: 1000 ticks per second.
	var div := ((256 - 25) << 8) | 40
	var m := RPGMidiFile.parse(smf(0, div, [track([[500, 0x90, 60, 100], [250, 0x80, 60, 0]])]))
	assert_eq(m.error, "")
	assert_eq(m.ticks_per_quarter, 0)
	assert_eq(m.events()[0].time, 0.5)
	assert_eq(m.length, 0.75)
	var f2 := RPGMidiFile.parse(smf(2, 480, [track([]), track([])]))
	assert_true(f2.error.contains("format 2"), f2.error)
	assert_true(RPGMidiFile.parse("MThd".to_ascii_buffer()).error != "", "a cut header is an error")
	assert_true(RPGMidiFile.parse("hello world, not midi".to_ascii_buffer()).error.contains("Not a MIDI file"))
	assert_true(RPGMidiFile.load_file(TMP + "/nope.mid").error != "")
	# A track cut in the middle keeps what was read, with a warning.
	var cut := smf(0, 480, [track([[0, 0x90, 60, 100], [480, 0x80, 60, 0]])])
	cut = cut.slice(0, cut.size() - 6)
	var mc := RPGMidiFile.parse(cut)
	assert_eq(mc.error, "")
	assert_eq(mc.event_count(), 1)
	assert_false(mc.warnings.is_empty())


func test_cc111_loop_start_and_rmid() -> void:
	var t0 := track([[0, 0xff, 0x51, 0x03, 0x07, 0xa1, 0x20]])
	var t1 := track([[0, 0x90, 60, 100], [960, 0xb0, 111, 0], [0, 0x80, 60, 0], [480, 0xb3, 111, 0]], 960)
	var bytes := smf(1, 480, [t0, t1])
	var m := RPGMidiFile.parse(bytes)
	assert_eq(m.error, "")
	assert_true(m.has_loop_marker)
	assert_eq(m.loop_start, 1.0, "the first CC#111")
	# RIFF RMID wrapper: RIFF <size> RMID data <size> <SMF> (+ a pad byte for odd sizes).
	var riff := "RIFF".to_ascii_buffer()
	var body := "RMID".to_ascii_buffer()
	body.append_array("data".to_ascii_buffer())
	var sz := PackedByteArray()
	sz.resize(4)
	sz.encode_u32(0, bytes.size())
	body.append_array(sz)
	body.append_array(bytes)
	if bytes.size() % 2 == 1:
		body.append(0)
	sz.encode_u32(0, body.size())
	riff.append_array(sz)
	riff.append_array(body)
	var r := RPGMidiFile.parse(riff)
	assert_eq(r.error, "")
	assert_eq(r.loop_start, 1.0)
	assert_eq(r.event_count(), m.event_count())


# --- renderer ------------------------------------------------------------------------------------

func test_note_timing_and_pitch() -> void:
	var bank := SineBank.new()
	# Key 69 from 0.0 to 0.5 s, key 81 from 1.0 to 1.5 s.
	var m := song([[0, 0x90, 69, 127], [480, 0x80, 69, 0], [480, 0x90, 81, 127], [480, 0x80, 81, 0]], 480)
	var out := render(m, bank)
	var pcm: PackedVector2Array = out.pcm
	assert_eq(pcm.size(), 2 * RATE, "rendered to the end of track")
	var first := -1
	for i in range(int(0.6 * RATE), pcm.size()):
		if absf(pcm[i].x) > 0.001:
			first = i
			break
	assert_true(absf(first / float(RATE) - 1.0) <= 0.001, "the note at 1.0 s starts at %.4f s" % (first / float(RATE)))
	assert_true(level(pcm, 0.7, 0.99) < 0.0005, "silent between the notes")
	var low := crossings(pcm, 0.1, 0.4)
	var high := crossings(pcm, 1.1, 1.4)
	assert_true(absf(low - 2 * 441 * 0.3) <= 3, "key 69 plays 441 Hz: %d crossings in 0.3 s" % low)
	assert_true(absf(high / float(low) - 2.0) < 0.02, "an octave up is twice the frequency (%d vs %d)" % [high, low])
	assert_true(absf(level(pcm, 0.1, 0.4, 0) - level(pcm, 0.1, 0.4, 1)) < 0.01, "a centred note is equal left and right")


func test_release_sustain_pedal_and_bend() -> void:
	var bank := SineBank.new()
	bank.release = 0.2
	# Note off at 0.5 s: 96 dB over 0.2 s; at 0.6 s about -48 dB, gone by 0.75 s.
	var m := song([[0, 0x90, 69, 127], [480, 0x80, 69, 0]], 960)
	var pcm: PackedVector2Array = render(m, bank).pcm
	var on := level(pcm, 0.3, 0.45)
	var mid := level(pcm, 0.55, 0.56)
	assert_true(on > 0.05, "playing: %f" % on)
	assert_true(mid < on * 0.5 and mid > on * 0.0005, "releasing at 0.55 s: %f of %f" % [mid, on])
	assert_true(level(pcm, 0.75, 1.0) < 0.0002, "released")
	# Sustain pedal down at 0, note off at 0.25 s: still sounds until the pedal goes up at 1.0 s.
	var ped := song([[0, 0xb0, 64, 127], [0, 0x90, 69, 127], [240, 0x80, 69, 0], [720, 0xb0, 64, 0]], 960)
	var pp: PackedVector2Array = render(ped, bank).pcm
	assert_true(level(pp, 0.8, 0.95) > on * 0.9, "held by the pedal")
	assert_true(level(pp, 1.3, 1.5) < 0.0002, "released when the pedal goes up")
	# Pitch bend: RPN 0 range 12, bend fully up = one octave.
	var bend := song([
		[0, 0xb0, 101, 0], [0, 0xb0, 100, 0], [0, 0xb0, 6, 12], [0, 0xb0, 38, 0],
		[0, 0x90, 69, 127], [480, 0xe0, 0x7f, 0x7f], [480, 0x80, 69, 0]], 0)
	var bp: PackedVector2Array = render(bend, bank).pcm
	var a := crossings(bp, 0.1, 0.4)
	var b := crossings(bp, 0.6, 0.9)
	assert_true(absf(b / float(a) - 2.0 * 8191.0 / 8192.0 - 0.0) < 0.03, "bend +12 semitones: %d vs %d crossings" % [b, a])
	# Default range is 2 semitones.
	var bend2 := song([[0, 0x90, 69, 127], [480, 0xe0, 0x7f, 0x7f], [480, 0x80, 69, 0]], 0)
	var b2: PackedVector2Array = render(bend2, bank).pcm
	var ratio := crossings(b2, 0.6, 0.9) / float(crossings(b2, 0.1, 0.4))
	assert_true(absf(ratio - pow(2.0, 2.0 / 12.0)) < 0.02, "default bend range 2: ratio %f" % ratio)


func test_exclusive_class_and_polyphony_cap() -> void:
	var bank := SineBank.new()
	bank.release = 1.0
	bank.pan_by_key = {60: -1.0, 62: 1.0}
	bank.excl_by_key = {60: 1, 62: 1}
	# Key 60 (left only) at 0, key 62 (right only) at 0.5 s in the same exclusive class: the left
	# side stops within a few milliseconds of 0.5 s.
	var m := song([[0, 0x90, 60, 127], [480, 0x90, 62, 127], [480, 0x80, 60, 0], [0, 0x80, 62, 0]], 0)
	var pcm: PackedVector2Array = render(m, bank).pcm
	assert_true(level(pcm, 0.2, 0.45, 0) > 0.05 and level(pcm, 0.2, 0.45, 1) < 0.001, "key 60 is on the left only")
	assert_true(level(pcm, 0.53, 0.9, 0) < 0.0005, "cut off by key 62's exclusive class: %f" % level(pcm, 0.53, 0.9, 0))
	assert_true(level(pcm, 0.6, 0.9, 1) > 0.05, "key 62 plays on the right")
	# 6 notes at once with room for 4: the 2 oldest are stolen.
	var chord := []
	for k in 6:
		chord.append([0 if k == 0 else 10, 0x90, 50 + k, 100])
	chord.append([480, 0xb0, 123, 0])
	var out := render(song(chord, 0), SineBank.new(), func(r: RPGMidiRenderer) -> void: r.max_voices = 4)
	assert_eq(out.stats.stolen, 2)
	# 100 notes with the default cap of 64.
	var many := []
	for k in 100:
		many.append([0, 0x90, 20 + k, 127])
	var big := render(song(many, 480), SineBank.new())
	assert_eq(big.stats.notes, 100)
	assert_eq(big.stats.stolen, 36, "64 voices at most")
	assert_true(big.stats.voices_max <= RPGMidiRenderer.SLOTS)
	assert_eq(big.stats.dropped, 0)
	assert_true(big.stats.peak < 1.0, "no clipping: %f" % big.stats.peak)
	assert_true(big.stats.limited, "36+ loud notes go through the limiter")


func test_peak_measure_misses_and_reverb() -> void:
	var pcm := PackedVector2Array()
	pcm.resize(50000)
	for i in range(0, 50000, 7):
		pcm[i] = Vector2(sin(i * 0.01) * 0.3, cos(i * 0.013) * 0.2)
	pcm[33333] = Vector2(0.1, -0.73)
	var loop_peak := 0.0
	for v in pcm:
		loop_peak = maxf(loop_peak, maxf(absf(v.x), absf(v.y)))
	assert_true(absf(RPGMidiRenderer.peak_of(pcm) - loop_peak) < 0.0005, "%f vs %f" % [RPGMidiRenderer.peak_of(pcm), loop_peak])
	# Missing programs are counted; CC91 is averaged over the notes.
	var bank := SineBank.new()
	bank.missing_programs = [5]
	var m := song([[0, 0xb0, 91, 127], [0, 0x90, 60, 100], [0, 0xc1, 5], [0, 0x91, 60, 100], [0, 0xb2, 91, 0], [0, 0x92, 62, 100], [480, 0x80, 60, 0]], 0)
	var out := render(m, bank)
	assert_eq(out.stats.missed_programs, {"0:5": 1})
	assert_eq(out.stats.notes, 2)
	assert_true(absf(out.stats.reverb - 127.0 / 2.0 / 127.0) < 0.001, "average of 127 and 0: %f" % out.stats.reverb)
	assert_true(str(out.r.warnings).contains("program 0:5"), str(out.r.warnings))


func test_stream_loop_points_and_reverb_meta() -> void:
	var bank := SineBank.new()
	var m := song([[0, 0x90, 69, 100], [960, 0xb0, 111, 0], [960, 0x80, 69, 0]], 960)
	assert_eq(m.loop_start, 1.0)
	var out := render(m, bank)
	var r: RPGMidiRenderer = out.r
	var s := r.make_stream(out.pcm, m)
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(s.loop_begin, RATE, "loops from the CC#111 at 1.0 s")
	assert_eq(s.loop_end, 3 * RATE, "to the end of track")
	assert_eq(s.mix_rate, RATE)
	assert_true(s.stereo)
	assert_eq(s.format, AudioStreamWAV.FORMAT_QOA)
	assert_true(absf(s.get_length() - 3.0) < 0.01, str(s.get_length()))
	assert_true(absf(float(s.get_meta("rpg_midi_reverb")) - 40.0 / 127.0) < 0.001, "GM default reverb 40")
	r.compress = false
	var pcm16 := r.make_stream(out.pcm, m)
	assert_eq(pcm16.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(pcm16.data.size(), 3 * RATE * 4)
	r.loop = false
	var once := r.make_stream(out.pcm, m)
	assert_eq(once.loop_mode, AudioStreamWAV.LOOP_DISABLED)


func test_jingle_ring_out_without_loop() -> void:
	var bank := SineBank.new()
	bank.release = 0.3
	var m := song([[0, 0x90, 69, 100], [480, 0x80, 69, 0]], 0)
	var out := render(m, bank, func(r: RPGMidiRenderer) -> void: r.loop = false)
	var pcm: PackedVector2Array = out.pcm
	assert_true(pcm.size() > int(0.6 * RATE) and pcm.size() < int(1.0 * RATE), "the release rings past the end of track: %d frames" % pcm.size())


# --- import plugin, sound bank paths, kit wiring -------------------------------------------------

func test_importer_end_to_end_with_builtin_bank() -> void:
	# 1 s of a C major chord with a loop marker at 0.5 s, at 22050 Hz.
	var bytes := smf(0, 480, [track([[0, 0x90, 60, 110], [0, 64, 110], [0, 67, 110], [480, 0xb0, 111, 0], [480, 0x80, 60, 0], [0, 64, 0], [0, 67, 0]])])
	_write(TMP + "/Song.mid", bytes)
	# (EditorImportPlugin itself can only be made in the editor; _import calls import_file.)
	var opts := {}
	for o in Importer.import_options():
		opts[o.name] = o.default_value
	assert_eq(opts.keys(), ["sound_bank", "sample_rate", "loop", "volume_db", "compress"])
	var src := FileAccess.get_file_as_string("res://addons/rpg/import/midi/rpg_midi_importer.gd")
	assert_true(src.contains('PackedStringArray(["mid", "midi"])'), "imports .mid and .midi")
	assert_true(src.contains("func _can_import_threaded() -> bool:\n\treturn true"), "threaded")
	opts.sound_bank = "builtin"
	opts.sample_rate = 22050
	var err: Error = Importer.import_file(TMP + "/Song.mid", TMP + "/Song", opts)
	assert_eq(err, OK)
	var s := ResourceLoader.load(TMP + "/Song.res", "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
	assert_true(s != null, "the import saved an AudioStreamWAV")
	if s == null:
		return
	assert_eq(s.mix_rate, 22050)
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(s.loop_begin, 11025, "loops from the CC#111 at 0.5 s")
	assert_eq(s.loop_end, 22050, "to the end of track at 1.0 s")
	assert_eq(s.format, AudioStreamWAV.FORMAT_QOA)
	assert_eq(str(s.get_meta("rpg_midi_bank", "")), "built-in instruments")
	assert_true(s.has_meta("rpg_midi_reverb"))
	# The built-in instruments make sound.
	var res: Dictionary = Importer.render(TMP + "/Song.mid", opts)
	assert_true(float(res.stats.peak) > 0.02, "the built-in bank plays the chord: peak %f" % res.stats.peak)
	assert_eq(res.stats.missed_programs, {})
	# A file that is not MIDI fails with an error (and saves nothing).
	_write(TMP + "/Bad.mid", "not midi at all".to_ascii_buffer())
	assert_ne(Importer.import_file(TMP + "/Bad.mid", TMP + "/Bad", opts), OK)
	assert_false(FileAccess.file_exists(TMP + "/Bad.res"))


## A sound bank path from another computer (missing here) falls back to the built-in instruments
## with one warning naming the file; a bank kept inside the project (res://) is used.
func test_sound_bank_paths_and_fallback() -> void:
	var setting := RPGMidiRenderer.SOUND_BANK_SETTING
	var old: Variant = ProjectSettings.get_setting(setting, "")
	ProjectSettings.set_setting(setting, "C:/Nowhere/Windows/missing_bank.dls")
	var b := RPGMidiRenderer.open_bank("")
	assert_true(b.fallback, "fell back")
	assert_eq(b.path, "builtin")
	assert_true(b.bank is RPGSoundBank)
	assert_true(str(b.warning).contains("C:/Nowhere/Windows/missing_bank.dls") and str(b.warning).contains("not on this computer"), str(b.warning))
	assert_true(str(b.name).contains("builtin fallback") and str(b.name).contains("missing_bank.dls"), str(b.name))
	# The importer option wins over the setting.
	assert_eq(RPGMidiRenderer.bank_path_for("builtin"), "builtin")
	# A tiny SoundFont inside the project (made with the bank tests' builder).
	var dir := "res://tests/.midi_tmp"
	var sf2: PackedByteArray = load("res://tests/suites/test_midi_banks.gd").new()._sf2()
	_write(dir + "/tiny.sf2", sf2)
	ProjectSettings.set_setting(setting, dir + "/tiny.sf2")
	var b2 := RPGMidiRenderer.open_bank("")
	assert_false(b2.fallback, str(b2.warning))
	assert_eq(b2.path, dir + "/tiny.sf2")
	assert_true(b2.bank is RPGSf2Bank)
	assert_eq(b2.name, "tiny.sf2")
	_write(TMP + "/One.mid", smf(0, 480, [track([[0, 0x90, 60, 100], [240, 0x80, 60, 0]])]))
	var res := RPGMidiRenderer.render_file(TMP + "/One.mid", {"compress": false})
	assert_eq(str(res.stream.get_meta("rpg_midi_bank")), "tiny.sf2", "the stream says which bank rendered it")
	ProjectSettings.set_setting(setting, old)
	_rm_tree(dir)
	assert_false(DirAccess.dir_exists_absolute(dir), "temporary res:// folder removed")


func test_assets_find_midi_music_and_tools_bank_copy() -> void:
	var old_root := RPGAssets.root
	var old_bank: Variant = ProjectSettings.get_setting(RPGMidiRenderer.SOUND_BANK_SETTING, "")
	ProjectSettings.set_setting(RPGMidiRenderer.SOUND_BANK_SETTING, "builtin")
	RPGAssets.root = TMP + "/assets"
	RPGAssets.clear_cache()
	var mid := smf(0, 480, [track([[0, 0x90, 60, 100], [480, 0x80, 60, 0]])])
	_write(TMP + "/assets/rtp/Music/Theme.mid", mid)
	_write(TMP + "/assets/rtp/Music/Field.midi", mid)
	_write(TMP + "/assets/rtp/Music/Battle.mid", mid)
	_write(TMP + "/assets/rtp/Music/Battle.ogg", PackedByteArray([1, 2, 3]))
	_write(TMP + "/assets/rtp/Sound/Theme.mid", mid)
	assert_eq(RPGAssets.find("music", "Theme"), TMP + "/assets/rtp/Music/Theme.mid")
	assert_eq(RPGAssets.find("music", "Theme.mid"), TMP + "/assets/rtp/Music/Theme.mid", "with its extension too")
	assert_eq(RPGAssets.find("music", "field"), TMP + "/assets/rtp/Music/Field.midi")
	assert_eq(RPGAssets.find("music", "Battle"), TMP + "/assets/rtp/Music/Battle.ogg", "an OGG of the same name wins")
	assert_eq(RPGAssets.find("sound", "Theme"), "", "MIDI is music only")
	assert_has(RPGAssets.list("music"), "Theme")
	# Not imported (no editor here): rendered on load, looping like other music.
	var s := RPGAssets.load_audio("music", "Theme")
	assert_true(s is AudioStreamWAV, str(s))
	if s is AudioStreamWAV:
		assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		assert_eq(str(s.get_meta("rpg_midi_bank", "")), "built-in instruments")
	assert_eq(Array(RPGToolsWindow.midi_files(TMP + "/assets")).size(), 4)
	RPGAssets.root = old_root
	RPGAssets.clear_cache()
	ProjectSettings.set_setting(RPGMidiRenderer.SOUND_BANK_SETTING, old_bank)
	# Tools > Resources: an .sf2 can be copied into the project; a .dls never is.
	_write(TMP + "/outside/My Font.sf2", PackedByteArray([1, 2, 3, 4]))
	var c := RPGToolsWindow.copy_bank_into_project(TMP + "/outside/My Font.sf2", TMP + "/proj/audio/soundfonts")
	assert_eq(c.error, "")
	assert_eq(c.path, TMP + "/proj/audio/soundfonts/My Font.sf2")
	assert_true(FileAccess.file_exists(c.path))
	assert_ne(RPGToolsWindow.copy_bank_into_project("C:/Windows/System32/drivers/gm.dls", TMP + "/proj").error, "")
	assert_false(FileAccess.file_exists(TMP + "/proj/gm.dls"))


func test_audio_keeps_midi_loop_reverb_bus_and_jingle() -> void:
	var m := song([[0, 0x90, 69, 100], [480, 0xb0, 111, 0], [480, 0x80, 69, 0]], 0)
	var out := render(m, SineBank.new())
	var r: RPGMidiRenderer = out.r
	var s := r.make_stream(out.pcm, m)
	var audio := RPGAudio.new()
	tree.root.add_child(audio)
	await frames(1)
	audio._set_loop(s)
	assert_eq(s.loop_begin, RATE / 2, "the importer's loop is kept")
	assert_eq(s.loop_end, RATE)
	var once: AudioStreamWAV = RPGAudio.jingle_stream(s)
	assert_eq(once.loop_mode, AudioStreamWAV.LOOP_DISABLED, "a jingle plays once")
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD, "the cached music stream still loops")
	assert_true(once.has_meta("rpg_midi_reverb"), "the copy keeps the reverb send")
	audio.route_reverb(audio.bgm, AudioStreamWAV.new())
	assert_eq(str(audio.bgm.bus), "Master", "music without a reverb send stays on Master")
	audio.route_reverb(audio.bgm, s)
	assert_eq(str(audio.bgm.bus), RPGAudio.REVERB_BUS)
	var i := AudioServer.get_bus_index(RPGAudio.REVERB_BUS)
	assert_true(i > 0, "the reverb bus was made")
	if i > 0:
		assert_eq(str(AudioServer.get_bus_send(i)), "Master", "and sends to Master (its limiter applies)")
		var fx := AudioServer.get_bus_effect(i, 0) as AudioEffectReverb
		assert_true(fx != null and absf(fx.wet - 40.0 / 127.0 * RPGAudio.REVERB_WET) < 0.001, "wet level from the song's CC91")
	# A QOA stream without a loop of its own gets one over its whole length.
	r.loop = false
	var flat := r.make_stream(out.pcm, null)
	audio._set_loop(flat)
	assert_eq(flat.loop_end, out.pcm.size())
	audio.queue_free()
	await frames(1)
	if i > 0:
		AudioServer.remove_bus(i)
