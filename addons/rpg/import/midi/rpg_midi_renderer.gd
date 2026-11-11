@tool
class_name RPGMidiRenderer
extends RefCounted
## Renders an RPGMidiFile with an RPGSoundBank into stereo PCM, then into an AudioStreamWAV that
## loops from the song's loop start (CC#111) to its end. Used by the MIDI import plugin, so games
## only ever contain ordinary audio.
##   var r := RPGMidiRenderer.new()
##   var pcm := r.render(midi, bank)          # PackedVector2Array at r.out_rate
##   var stream := r.make_stream(pcm, midi)   # AudioStreamWAV (QOA or 16-bit PCM)
##   r.stats                                  # peak, notes, misses, timings
## or in one call: RPGMidiRenderer.render_file("res://.../Song.mid").
##
## How it is fast enough in GDScript: notes are not mixed sample by sample in script. Each bank
## sample becomes a 16-bit stereo AudioStreamWAV with the voice's pan baked into its two channels
## (cached per sample and pan), and every voice is a stream of one AudioStreamPolyphonic playback
## that Godot mixes in C++ (cubic resampling, loops) through AudioStreamPlayback.mix_audio(). The
## script only runs per block (64 or 256 frames) and per event: envelopes and controllers become
## set_stream_volume / set_stream_pitch_scale calls. Measured on the development machine: about
## 15-20 ns per voice-sample against about 360 ns for a typed per-sample GDScript loop.
##
## Channels: 16, channel 10 is drums (GS sysex can change that). Note on/off, program change, bank
## select (CC0 / CC32), volume (CC7), expression (CC11), pan (CC10, applied when a note starts),
## sustain pedal (CC64), modulation (CC1, a gentle vibrato), reverb send (CC91, recorded as the
## stream's "rpg_midi_reverb" metadata for RPGAudio), all notes / sound off (CC123 / CC120),
## reset controllers (CC121), RPN 0 pitch-bend range and pitch bend, and the GM / GS / XG reset
## sysex. Drum notes ignore note-off unless their sample loops (as GS synths do).
## Voices: velocity gain (v/127)^2, region attenuation, a delay/attack/hold/decay/sustain/release
## envelope (decay = time to the sustain level, release = time for a full 96 dB fall, both linear
## in dB), loop modes, exclusive classes and at most `max_voices` sounding voices (released voices
## are stolen first, then the oldest).

const DEFAULT_RATE := 32000
const MAX_VOICES := 64
## AudioStreamPolyphonic allows 128 streams; stolen voices fade out in the spare ones.
const SLOTS := 128
const BLOCK_FAST := 128
const BLOCK_SLOW := 256
## Fixed output gain: puts typical General MIDI songs around -6..-3 dBFS peak on gm.dls.
const MASTER_GAIN := 0.6
## Peaks above this level are soft-clipped (a tanh knee); peaks far above it lower the song first.
const LIMIT_KNEE := 0.8
const LIMIT_MAX_INPUT := 1.41
const EG_RANGE_DB := 96.0
## A voice's volume is updated each time its envelope has moved by this much (more for quiet
## voices: above -30 dBFS 0.3 dB, above -50 dBFS 1 dB, else 3 dB).
const STEP_DB := 0.3
## A voice fading out (released, or decaying to nothing) ends below this output level (-72 dBFS).
const CUTOFF := 0.00025
const NEVER := 1 << 62
## Fade time of stolen, exclusive-class and "all sound off" voices (for the full 96 dB).
const KILL_TIME := 0.01
const MIN_RELEASE := 0.004
## Vibrato for CC1 at 127: semitones and Hz.
const VIBRATO_DEPTH := 0.3
const VIBRATO_RATE := 5.5
## Ring-out after the end of a song that does not loop (seconds at most).
const TAIL_MAX := 3.0
const DEFAULT_REVERB := 40
const SOUND_BANK_SETTING := "rpg/audio/sound_bank"

## Output sample rate (Hz).
var out_rate := DEFAULT_RATE
## Extra gain in dB on top of MASTER_GAIN (the importer's Volume option).
var volume_db := 0.0
## Loop from the loop start to the song end (off: play once and let the last notes ring out).
var loop := true
## Compress the stream with QOA (else 16-bit PCM).
var compress := true
var max_voices := MAX_VOICES
## After render(): {peak, peak_db, peak_in_db, limited, notes, voices_max, dropped, stolen,
## missed_programs {"bank:program": count}, missed_drums {key: count}, reverb, frames, seconds,
## render_ms, mix_ms, post_ms, loop_start}.
var stats := {}
var warnings := PackedStringArray()

# Sample data: key -> 16-bit stereo bytes, shared by every render (and import thread).
static var _cache := {}
static var _cache_bytes := 0
static var _cache_mutex := Mutex.new()
const CACHE_MAX_BYTES := 256 * 1024 * 1024


class Channel:
	extends RefCounted
	var program := 0
	var bank_msb := 0
	var bank_lsb := 0
	var volume := 100
	var expression := 127
	var pan := 64
	var sustain := false
	var mod := 0
	var bend := 0.0
	var bend_range := 2.0
	var rpn := 0x3fff
	var nrpn := false
	var reverb := DEFAULT_REVERB
	var drums := false
	## (volume/127)^2 * (expression/127)^2
	var gain := 0.0
	## 2^(bend/12)
	var bend_mul := 1.0
	## Bumped when the bend changes, so voices know to update their pitch.
	var pitch_serial := 0

	func reset_controllers() -> void:
		expression = 127
		mod = 0
		sustain = false
		bend = 0.0
		bend_mul = 1.0
		rpn = 0x3fff
		nrpn = false
		pitch_serial += 1
		update_gain()

	func update_gain() -> void:
		var v := volume / 127.0
		var e := expression / 127.0
		gain = v * v * e * e


class Voice:
	extends RefCounted
	var id := -1
	var ch := 0
	var key := 0
	var serial := 0
	var start := 0
	var stream: AudioStreamWAV
	var drums := false
	var excl := 0
	## master * velocity * attenuation
	var base := 0.0
	## The volume last given to the mixer (linear).
	var gain := -1.0
	## Pitch scale without bend and vibrato, and source frames per output frame per unit of it.
	var rate := 1.0
	var step_per_rate := 1.0
	var step := 1.0
	var pitch_serial := -1
	## Source position at frame pos_frame (it moves step frames per output frame).
	var pos := 0.0
	var pos_frame := 0
	## Frame at which a sample that does not loop has played out.
	var end_at := 0
	## Index in the renderer's voice list (and in _nexts, the frame of its next update).
	var idx := 0
	var dc_rate := 0.0
	var length := 0
	var loop_mode := 0
	var loop_start := 0
	var loop_end := 0
	# Envelope, in frames since the note started.
	var d_end := 0
	var a_end := 0
	var h_end := 0
	var dc_end := 0
	var sus_db := 0.0
	var sus_lin := 1.0
	var release_rate := 1.0
	var released := false
	var held := false
	var killed := false
	var dead := false
	var rel_t := 0
	var rel_db := 0.0
	var rel_rate := 0.0


var _bank: RPGSoundBank
## This render's sample streams (key -> AudioStreamWAV).
var _streams := {}
var _pb: AudioStreamPlaybackPolyphonic
var _channels: Array[Channel] = []
var _voices: Array[Voice] = []
## Per voice (same index): the frame of its next update (envelope step, stage end, pitch, end).
var _nexts := PackedInt64Array()
## ch * 128 + key -> voices started by that key and not released yet (for note-off).
var _by_key := {}
var _serial := 0
## The earliest frame at which some voice needs an update (blocks are cut short to reach it).
var _min_next := 0
## Voices not fading out after a steal (counted against max_voices).
var _live := 0
var _stopped := 0
var _frame := 0
## Pitch scale for one source frame per output frame at the stream's own rate: mixer rate / out rate.
var _rate_k := 1.0
var _target_rate := 44100.0
var _master := MASTER_GAIN
var _reverb_sum := 0.0
var _notes := 0


## Makes one of each playback object the renderer uses, on the calling thread (the main thread,
## before threaded imports start; see the importer).
static func warm_up() -> void:
	var w := AudioStreamWAV.new()
	w.data = PackedByteArray([0, 0, 0, 0])
	w.instantiate_playback()
	AudioStreamPolyphonic.new().instantiate_playback()


# --- one call ------------------------------------------------------------------------------------

## The sound bank path to use for `option` ("" = the project setting rpg/audio/sound_bank, and ""
## there = RPGSoundBank.default_path()).
static func bank_path_for(option: String) -> String:
	var p := option.strip_edges()
	if p == "":
		p = str(ProjectSettings.get_setting(SOUND_BANK_SETTING, "")).strip_edges()
	if p == "":
		p = RPGSoundBank.default_path()
	return p


## Opens the bank for `option`, falling back to the built-in instruments with a warning (a path
## can be res:// for a bank kept in the project, or absolute; an absolute path from another
## computer, such as C:/Windows/System32/drivers/gm.dls opened on Linux, is simply missing here).
## Returns {bank (or null), path, name, fallback, warning, error}; `name` says which bank renders,
## with "builtin fallback" when the wanted one could not be used.
static func open_bank(option: String) -> Dictionary:
	var path := bank_path_for(option)
	var bank := RPGSoundBank.open(path)
	if bank != null:
		return {"bank": bank, "path": path, "name": bank_label(bank, path), "fallback": false, "warning": "", "error": ""}
	var why := RPGSoundBank.last_error
	if path != "builtin" and not FileAccess.file_exists(path):
		why = "the file %s is not on this computer" % path
	if path != "builtin":
		var fallback := RPGSoundBank.open("builtin")
		if fallback != null:
			return {"bank": fallback, "path": "builtin", "fallback": true, "error": "",
				"name": "%s (builtin fallback: %s missing)" % [bank_label(fallback, "builtin"), path.get_file()],
				"warning": "Sound bank '%s' cannot be used (%s); MIDI is rendered with the built-in instruments instead. Pick a bank in Tools > Resources > MIDI sound bank." % [path, why]}
	return {"bank": null, "path": path, "name": "none", "fallback": true, "warning": "", "error": "No sound bank could be opened (%s)." % why}


## "gm.dls", "GeneralUser-GS.sf2", "built-in instruments".
static func bank_label(bank: RPGSoundBank, path: String) -> String:
	if path == "builtin" or path == "":
		return bank.bank_name() if bank != null else "built-in instruments"
	return path.get_file()


## Reads, renders and wraps a MIDI file. options: sound_bank, sample_rate, loop, volume_db,
## compress. Returns {stream, error, warnings, stats, bank (path), bank_name, fallback}. Without any
## usable bank the stream is silence of the song's length (and `error` says why). The stream has
## metadata "rpg_midi_bank" (the bank that rendered it) and "rpg_midi_reverb".
static func render_file(path: String, options := {}) -> Dictionary:
	var out := {"stream": null, "error": "", "warnings": PackedStringArray(), "stats": {}, "bank": "", "bank_name": "", "fallback": false}
	var midi := RPGMidiFile.load_file(path)
	if midi.error != "":
		out.error = "%s: %s" % [path.get_file(), midi.error]
		return out
	for w in midi.warnings:
		out.warnings.append(w)
	var b := open_bank(str(options.get("sound_bank", "")))
	if b.warning != "":
		out.warnings.append(b.warning)
	if b.error != "":
		out.error = b.error
	out.bank = b.path
	out.bank_name = b.name
	out.fallback = b.fallback
	var r := RPGMidiRenderer.new()
	r.out_rate = int(options.get("sample_rate", DEFAULT_RATE))
	r.loop = bool(options.get("loop", true))
	r.volume_db = float(options.get("volume_db", 0.0))
	r.compress = bool(options.get("compress", true))
	var pcm := r.render(midi, b.bank)
	out.stream = r.make_stream(pcm, midi)
	out.stream.set_meta("rpg_midi_bank", b.name)
	out.stats = r.stats
	out.warnings.append_array(r.warnings)
	return out


# --- rendering -----------------------------------------------------------------------------------

## Renders the song (to its end-of-track; past it when `loop` is off, until the notes have rung
## out). A null bank renders silence.
func render(midi: RPGMidiFile, bank: RPGSoundBank) -> PackedVector2Array:
	var t0 := Time.get_ticks_usec()
	_bank = bank
	warnings.clear()
	stats = {"blocks": 0, "notes": 0, "voices_max": 0, "dropped": 0, "stolen": 0, "missed_programs": {}, "missed_drums": {}}
	_master = MASTER_GAIN * db_to_linear(volume_db)
	_target_rate = AudioServer.get_mix_rate()
	var speed := AudioServer.playback_speed_scale
	if speed > 0.0:
		_target_rate /= speed
	_rate_k = _target_rate / out_rate
	_channels.clear()
	for c in 16:
		var ch := Channel.new()
		_channels.append(ch)
	_reset_all()
	_voices.clear()
	_nexts.clear()
	_by_key.clear()
	_serial = 0
	_live = 0
	_min_next = 0
	_reverb_sum = 0.0
	_notes = 0
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = SLOTS
	_pb = poly.instantiate_playback()
	_pb.start(0.0)
	var end_frame := maxi(1, roundi(midi.length * out_rate))
	var hard_end := end_frame if loop else end_frame + roundi(TAIL_MAX * out_rate)
	var n_ev := midi.event_count()
	var ev_frames := PackedInt64Array()
	ev_frames.resize(n_ev)
	for i in n_ev:
		ev_frames[i] = roundi(midi.times[i] * out_rate)
	var out := PackedVector2Array()
	var ev := 0
	_frame = 0
	while _frame < hard_end:
		while ev < n_ev and ev_frames[ev] <= _frame:
			_event(midi, ev)
			ev += 1
		if _frame >= end_frame and _voices.is_empty():
			break
		var next := end_frame if _frame < end_frame else hard_end
		if ev < n_ev and ev_frames[ev] < next:
			next = ev_frames[ev]
		var n := mini(clampi(_min_next - _frame, BLOCK_FAST, BLOCK_SLOW), next - _frame)
		if n <= 0:
			continue
		_update_voices(n)
		if _voices.size() > stats.voices_max:
			stats.voices_max = _voices.size()
		if _voices.is_empty() and _stopped == 0:
			# Nothing sounds: skip to the next event in one go.
			var empty := PackedVector2Array()
			empty.resize(next - _frame)
			out.append_array(empty)
			_frame = next
			continue
		out.append_array(_pb.mix_audio(1.0, n))
		stats.blocks += 1
		_stopped = 0
		_frame += n
	# Streams still playing are stopped and mixed once more, so the playback lets go of them.
	for v in _voices:
		_pb.stop_stream(v.id)
	_pb.mix_audio(1.0, 1)
	_pb.stop()
	_pb = null
	_voices.clear()
	_nexts.clear()
	_by_key.clear()
	_streams.clear()
	var mix_us := Time.get_ticks_usec() - t0
	# Post: peak, and the limiter when needed.
	var t1 := Time.get_ticks_usec()
	var peak := peak_of(out)
	stats.peak_in_db = linear_to_db(peak) if peak > 0.0 else -INF
	stats.limited = false
	if peak > LIMIT_KNEE:
		if peak > LIMIT_MAX_INPUT:
			out = Transform2D(Vector2(LIMIT_MAX_INPUT / peak, 0), Vector2(0, LIMIT_MAX_INPUT / peak), Vector2.ZERO) * out
		_soft_clip(out)
		stats.limited = true
		peak = _soft_curve(minf(peak, LIMIT_MAX_INPUT))
	stats.peak = peak
	stats.peak_db = linear_to_db(peak) if peak > 0.0 else -INF
	stats.notes = _notes
	stats.reverb = (_reverb_sum / _notes if _notes > 0 else float(DEFAULT_REVERB)) / 127.0
	stats.frames = out.size()
	stats.seconds = out.size() / float(out_rate)
	stats.loop_start = midi.loop_start
	stats.mix_ms = mix_us / 1000.0
	stats.post_ms = (Time.get_ticks_usec() - t1) / 1000.0
	stats.render_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if not (stats.missed_programs as Dictionary).is_empty() or not (stats.missed_drums as Dictionary).is_empty():
		warnings.append("The sound bank has no instrument for %s; those notes are silent." % describe_misses(stats))
	return out


## "program 0:81 (12 notes), drum key 27 (3 notes)".
static func describe_misses(s: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in s.get("missed_programs", {}):
		parts.append("program %s (%d notes)" % [k, s.missed_programs[k]])
	for k in s.get("missed_drums", {}):
		parts.append("drum key %s (%d notes)" % [k, s.missed_drums[k]])
	return ", ".join(parts)


## Wraps rendered PCM as an AudioStreamWAV: QOA when `compress` (else 16-bit PCM), looping forward
## from the song's loop start to the end when `loop`, with "rpg_midi_reverb" metadata (0..1, the
## song's average CC91 send).
func make_stream(pcm: PackedVector2Array, midi: RPGMidiFile) -> AudioStreamWAV:
	var frames := pcm.size()
	if frames == 0:
		pcm = PackedVector2Array([Vector2.ZERO])
		frames = 1
	var ls := clampi(roundi(midi.loop_start * out_rate) if midi != null else 0, 0, frames - 1)
	var opts := {
		"compress/mode": 2 if compress else 0,
		"edit/loop_mode": 2 if loop else 1,
		"edit/loop_begin": ls,
		"edit/loop_end": frames,
	}
	var stream := AudioStreamWAV.load_from_buffer(wav_bytes(pcm, out_rate), opts)
	if stream == null:
		push_error("RPG MIDI: could not build the audio stream.")
		stream = AudioStreamWAV.new()
		stream.mix_rate = out_rate
		stream.stereo = true
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = ls
		stream.loop_end = frames
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.set_meta("rpg_midi_reverb", float(stats.get("reverb", DEFAULT_REVERB / 127.0)))
	return stream


## A 32-bit float stereo WAV file in memory.
static func wav_bytes(pcm: PackedVector2Array, rate: int) -> PackedByteArray:
	return _wav_header(pcm.size() * 8, 2, rate) + pcm.to_byte_array()


static func _wav_header(data_size: int, channels: int, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)  # RIFF
	h.encode_u32(4, 36 + data_size)
	h.encode_u32(8, 0x45564157)  # WAVE
	h.encode_u32(12, 0x20746d66)  # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 3)  # IEEE float
	h.encode_u16(22, channels)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * channels * 4)
	h.encode_u16(32, channels * 4)
	h.encode_u16(34, 32)
	h.encode_u32(36, 0x61746164)  # data
	h.encode_u32(40, data_size)
	return h


## The largest absolute sample value. Godot's WAV loader normalizes in C++, so the peak is read
## back from the ratio of one loud sample before and after normalizing (about 10x faster than a
## script loop over every sample); the loop is the fallback.
static func peak_of(pcm: PackedVector2Array) -> float:
	var n := pcm.size()
	if n == 0:
		return 0.0
	var probe_i := -1
	var probe_v := 0.0
	var stride := maxi(1, n / 4096)
	for i in range(0, n, stride):
		var v := pcm[i]
		var a := maxf(absf(v.x), absf(v.y))
		if a > probe_v:
			probe_v = a
			probe_i = i
	if probe_i >= 0:
		var norm := AudioStreamWAV.load_from_buffer(wav_bytes(pcm, 8000), {"edit/normalize": true, "compress/mode": 0})
		if norm != null and norm.format == AudioStreamWAV.FORMAT_16_BITS:
			var d := norm.data
			var v := pcm[probe_i]
			var right := absf(v.y) > absf(v.x)
			var s := absi(d.decode_s16(probe_i * 4 + (2 if right else 0)))
			if s >= 64:
				return probe_v * 32768.0 / s
	var peak := 0.0
	for v in pcm:
		var a := maxf(absf(v.x), absf(v.y))
		if a > peak:
			peak = a
	return peak


static func _soft_curve(a: float) -> float:
	if a <= LIMIT_KNEE:
		return a
	return LIMIT_KNEE + (1.0 - LIMIT_KNEE) * tanh((a - LIMIT_KNEE) / (1.0 - LIMIT_KNEE))


## Soft clipping above LIMIT_KNEE (never reaches 1.0).
static func _soft_clip(pcm: PackedVector2Array) -> void:
	for i in pcm.size():
		var v := pcm[i]
		if absf(v.x) > LIMIT_KNEE or absf(v.y) > LIMIT_KNEE:
			pcm[i] = Vector2(signf(v.x) * _soft_curve(absf(v.x)), signf(v.y) * _soft_curve(absf(v.y)))


# --- events --------------------------------------------------------------------------------------

func _reset_all() -> void:
	for i in 16:
		var c := _channels[i]
		c.program = 0
		c.bank_msb = 0
		c.bank_lsb = 0
		c.volume = 100
		c.pan = 64
		c.reverb = DEFAULT_REVERB
		c.bend_range = 2.0
		c.drums = i == 9
		c.reset_controllers()


func _event(midi: RPGMidiFile, i: int) -> void:
	var msg := midi.messages[i]
	var st := msg & 0xff
	var d1 := (msg >> 8) & 0x7f
	var d2 := (msg >> 16) & 0x7f
	if st == 0xf0:
		_sysex(midi.sysex.get(i, PackedByteArray()))
		return
	var ch := st & 0x0f
	var c := _channels[ch]
	match st & 0xf0:
		0x90:
			if d2 > 0:
				_note_on(ch, d1, d2)
			else:
				_note_off(ch, d1)
		0x80:
			_note_off(ch, d1)
		0xb0:
			_control(ch, c, d1, d2)
		0xc0:
			c.program = d1
		0xe0:
			c.bend = ((d1 | (d2 << 7)) - 8192) / 8192.0 * c.bend_range
			c.bend_mul = pow(2.0, c.bend / 12.0)
			c.pitch_serial += 1
			_touch(ch)


func _control(ch: int, c: Channel, cc: int, v: int) -> void:
	match cc:
		0:
			c.bank_msb = v
		32:
			c.bank_lsb = v
		1:
			c.mod = v
			c.pitch_serial += 1
			_touch(ch)
		7:
			c.volume = v
			c.update_gain()
			_touch(ch)
		11:
			c.expression = v
			c.update_gain()
			_touch(ch)
		10:
			c.pan = v
		64:
			c.sustain = v >= 64
			if not c.sustain:
				for voice in _voices:
					if voice.ch == ch and voice.held:
						voice.held = false
						_release(voice)
		91:
			c.reverb = v
		101:
			c.rpn = (c.rpn & 0x7f) | (v << 7)
			c.nrpn = false
		100:
			c.rpn = (c.rpn & 0x3f80) | v
			c.nrpn = false
		98, 99:
			c.nrpn = true
		6:
			if not c.nrpn and c.rpn == 0:
				c.bend_range = v + fmod(c.bend_range, 1.0)
		38:
			if not c.nrpn and c.rpn == 0:
				c.bend_range = floorf(c.bend_range) + v / 100.0
		120:
			for voice in _voices:
				if voice.ch == ch:
					_kill(voice)
		121:
			c.reset_controllers()
			_touch(ch)
			for voice in _voices:
				if voice.ch == ch and voice.held:
					voice.held = false
					_release(voice)
		123, 124, 125, 126, 127:
			for voice in _voices:
				if voice.ch == ch and not voice.released:
					_note_off_voice(c, voice)


func _sysex(d: PackedByteArray) -> void:
	if d.size() < 4:
		return
	# Universal GM System On / GM2 On: 7E <dev> 09 01|03.
	if d[0] == 0x7e and d[2] == 0x09 and (d[3] == 0x01 or d[3] == 0x03):
		_reset_all()
		return
	# Roland GS: 41 <dev> 42 12 <addr hi mid lo> <value> <checksum>.
	if d.size() >= 9 and d[0] == 0x41 and d[2] == 0x42 and d[3] == 0x12:
		var hi := d[4]
		var mid := d[5]
		var lo := d[6]
		if hi == 0x40 and mid == 0x00 and lo == 0x7f:
			_reset_all()
		elif hi == 0x40 and (mid & 0xf0) == 0x10 and lo == 0x15:
			# "Use for rhythm part": part 1x (x 0 = part 10, 1-9 = parts 1-9, A-F = parts 11-16).
			var part := mid & 0x0f
			var ch := 9 if part == 0 else (part - 1 if part <= 9 else part)
			_channels[ch].drums = d[7] != 0
		return
	# Yamaha XG System On: 43 1n 4C 00 00 7E 00.
	if d.size() >= 7 and d[0] == 0x43 and (d[1] & 0xf0) == 0x10 and d[2] == 0x4c and d[3] == 0 and d[4] == 0 and d[5] == 0x7e:
		_reset_all()


func _note_off(ch: int, key: int) -> void:
	var c := _channels[ch]
	var k := ch * 128 + key
	var list: Array = _by_key.get(k, [])
	if list.is_empty():
		return
	for v: Voice in list:
		if not v.released and not v.held:
			_note_off_voice(c, v)
	# Held voices are released by the pedal, drum hits play out: none needs this key any more.
	_by_key.erase(k)


func _note_off_voice(c: Channel, v: Voice) -> void:
	# Drum hits play out, unless the sample loops (it would never end).
	if v.drums and v.loop_mode == 0:
		return
	if c.sustain:
		v.held = true
	else:
		_release(v)


func _note_on(ch: int, key: int, vel: int) -> void:
	var c := _channels[ch]
	if _bank == null:
		return
	var regions := _bank.regions_for(c.bank_msb * 128 + c.bank_lsb, c.program, key, vel, c.drums)
	if regions.is_empty():
		if c.drums:
			stats.missed_drums[key] = int(stats.missed_drums.get(key, 0)) + 1
		else:
			var k := "%d:%d" % [c.bank_msb * 128 + c.bank_lsb, c.program]
			stats.missed_programs[k] = int(stats.missed_programs.get(k, 0)) + 1
		return
	_notes += 1
	_reverb_sum += c.reverb
	# A melodic key struck again releases its previous note; exclusive classes cut each other off.
	var excl := []
	for r in regions:
		var region: RPGSoundBank.Region = r
		if region.exclusive_class != 0:
			excl.append(region.exclusive_class)
	if not excl.is_empty():
		for v in _voices:
			if v.ch == ch and not v.killed and v.excl != 0 and excl.has(v.excl):
				_kill(v)
	var k := ch * 128 + key
	if not c.drums and _by_key.has(k):
		for v: Voice in _by_key[k]:
			if not v.released:
				v.held = false
				_release(v)
	_by_key[k] = []
	_make_room(regions.size())
	var vel_gain := (vel / 127.0) * (vel / 127.0)
	for r in regions:
		_start_voice(ch, c, key, vel_gain, r)


## Keeps the sounding voices under max_voices: released ones go first, then the oldest.
func _make_room(need: int) -> void:
	var live := _live
	while live + need > max_voices and live > 0:
		var pick: Voice = null
		for v in _voices:
			if v.killed:
				continue
			if pick == null or (v.released and not pick.released) or (v.released == pick.released and v.serial < pick.serial):
				pick = v
		if pick == null:
			break
		_kill(pick)
		stats.stolen += 1
		live -= 1
	# Stolen voices still fade in their own slots; free the oldest ones when the mixer is full.
	while _voices.size() + _stopped + need > SLOTS:
		var oldest: Voice = null
		for v in _voices:
			if v.killed and (oldest == null or v.serial < oldest.serial):
				oldest = v
		if oldest == null:
			break
		_pb.stop_stream(oldest.id)
		_remove_voice(oldest.idx)
		_stopped += 1


## The channel's voices update in the next block (volume, pitch).
func _touch(ch: int) -> void:
	for v in _voices:
		if v.ch == ch:
			_nexts[v.idx] = _frame
	_min_next = _frame


## Removes voice i (the last voice takes its place).
func _remove_voice(i: int) -> void:
	var last := _voices.size() - 1
	_voices[i].idx = -1
	if i != last:
		var moved := _voices[last]
		_voices[i] = moved
		moved.idx = i
		_nexts[i] = _nexts[last]
	_voices.resize(last)
	_nexts.resize(last)


## Brings the voice's source position up to frame `f` (wrapping inside its loop while it loops).
func _advance(v: Voice, f: int) -> void:
	v.pos += v.step * (f - v.pos_frame)
	v.pos_frame = f
	if (v.loop_mode == 1 or (v.loop_mode == 2 and not v.released)) and v.pos >= v.loop_end:
		v.pos = v.loop_start + fmod(v.pos - v.loop_start, v.loop_end - v.loop_start)


## Where a sample that does not loop (any more) runs out, at the voice's current pitch.
func _set_end(v: Voice) -> void:
	if v.loop_mode == 0 or (v.loop_mode == 2 and v.released):
		v.end_at = v.pos_frame + ceili(maxf(0.0, v.length + 4 - v.pos) / maxf(v.step, 0.000001))
	else:
		v.end_at = NEVER


func _start_voice(ch: int, c: Channel, key: int, vel_gain: float, region: RPGSoundBank.Region) -> void:
	if region.samples.size() < 2 or region.sample_rate <= 0:
		return
	if _voices.size() + _stopped >= SLOTS:
		stats.dropped += 1
		return
	var pan := clampf((c.pan - 64) / 63.0 + region.pan, -1.0, 1.0)
	var stream := _stream_for(region, pan)
	if stream.data.is_empty():
		return
	var v := Voice.new()
	v.loop_mode = region.loop_mode if region.loop_mode > 0 and region.loop_end - region.loop_start >= 2 and region.loop_end <= region.samples.size() else 0
	if v.loop_mode == 2:
		# Its loop is switched off at note-off: it needs its own stream.
		stream = stream.duplicate() as AudioStreamWAV
	v.stream = stream
	v.ch = ch
	v.key = key
	v.drums = c.drums
	v.excl = region.exclusive_class
	_serial += 1
	v.serial = _serial
	v.start = _frame
	v.base = _master * vel_gain * db_to_linear(-region.attenuation_db)
	var semis := clampf((key - region.root_key) * region.scale_tuning, -96.0, 96.0)
	v.rate = _rate_k * pow(2.0, semis / 12.0)
	v.step_per_rate = region.sample_rate / _target_rate
	v.length = region.samples.size()
	v.loop_start = region.loop_start
	v.loop_end = region.loop_end
	var rate := float(out_rate)
	v.d_end = roundi(region.delay * rate)
	v.a_end = v.d_end + roundi(region.attack * rate)
	v.h_end = v.a_end + roundi(region.hold * rate)
	v.dc_end = v.h_end + roundi(region.decay * rate)
	v.sus_lin = clampf(region.sustain, 0.0, 1.0)
	v.sus_db = maxf(linear_to_db(v.sus_lin), -EG_RANGE_DB) if v.sus_lin > 0.0 else -EG_RANGE_DB
	v.release_rate = EG_RANGE_DB / (maxf(region.release, MIN_RELEASE) * rate)
	if v.dc_end > v.h_end:
		v.dc_rate = -v.sus_db / (v.dc_end - v.h_end)
	var pitch := v.rate * c.bend_mul
	v.step = pitch * v.step_per_rate
	v.pitch_serial = c.pitch_serial
	v.pos_frame = _frame
	_set_end(v)
	v.id = _pb.play_stream(stream, 0.0, -120.0, pitch)
	if v.id == AudioStreamPlaybackPolyphonic.INVALID_ID:
		stats.dropped += 1
		return
	v.idx = _voices.size()
	_voices.append(v)
	_nexts.append(_frame)
	_by_key[ch * 128 + key].append(v)
	_live += 1
	_min_next = _frame


## The voice's level before release (linear), at `t` frames since it started.
func _held_level(v: Voice, t: int) -> float:
	if t < v.d_end:
		return 0.0
	if t < v.a_end:
		return float(t - v.d_end) / (v.a_end - v.d_end)
	if t < v.h_end:
		return 1.0
	if t < v.dc_end:
		return db_to_linear(v.sus_db * float(t - v.h_end) / (v.dc_end - v.h_end))
	return v.sus_lin


func _release(v: Voice) -> void:
	if v.released or v.idx < 0:
		return
	if v.loop_mode == 2:
		_advance(v, _frame)
	v.released = true
	var t := _frame - v.start
	var lvl := _held_level(v, t)
	v.rel_t = t
	v.rel_db = linear_to_db(lvl) if lvl > 0.000016 else -EG_RANGE_DB
	v.rel_rate = v.release_rate
	if v.loop_mode == 2 and v.stream != null:
		v.stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_set_end(v)
	_nexts[v.idx] = _frame
	_min_next = _frame


## Fades a voice out fast (stolen, exclusive class, all sound off).
func _kill(v: Voice) -> void:
	if v.killed or v.idx < 0:
		return
	var t := _frame - v.start
	var db: float
	if v.released:
		db = v.rel_db - (t - v.rel_t) * v.rel_rate
	else:
		var lvl := _held_level(v, t)
		db = linear_to_db(lvl) if lvl > 0.000016 else -EG_RANGE_DB
	v.released = true
	v.killed = true
	_live -= 1
	v.held = false
	v.rel_t = t
	v.rel_db = db
	v.rel_rate = EG_RANGE_DB / (KILL_TIME * out_rate)
	_nexts[v.idx] = _frame
	_min_next = _frame


## Once per block: envelopes into volumes, bends and vibrato into pitch, finished voices out.
## Only the voices whose `next` frame has come are looked at; each then says when it next needs
## an update (its envelope has moved STEP_DB, a stage ends, its sample runs out).
func _update_voices(n: int) -> void:
	var f := _frame
	var t_mid := f + (n >> 1)
	var min_next := NEVER
	var i := _voices.size() - 1
	while i >= 0:
		var due := _nexts[i]
		if due > f:
			if due < min_next:
				min_next = due
			i -= 1
			continue
		var v := _voices[i]
		var t := t_mid - v.start
		var lvl := 0.0
		var nx := NEVER
		var c := _channels[v.ch]
		var g0 := v.base * c.gain
		var step_db := STEP_DB if v.gain > 0.03 or v.gain < 0.0 else (1.0 if v.gain > 0.003 else 3.0)
		if v.released:
			var db := v.rel_db - (t - v.rel_t) * v.rel_rate
			if db <= -EG_RANGE_DB:
				v.dead = true
			else:
				lvl = db_to_linear(db)
				if g0 * lvl < CUTOFF:
					v.dead = true
				nx = f + maxi(1, int(step_db / v.rel_rate))
		elif t < v.d_end:
			nx = v.start + v.d_end
		elif t < v.a_end:
			lvl = float(t - v.d_end) / (v.a_end - v.d_end)
			nx = f + 1
		elif t < v.h_end:
			lvl = 1.0
			nx = v.start + v.h_end
		elif t < v.dc_end:
			lvl = db_to_linear(v.sus_db * float(t - v.h_end) / (v.dc_end - v.h_end))
			if v.sus_lin < 0.001 and g0 * lvl < CUTOFF:
				v.dead = true
			nx = mini(v.start + v.dc_end, f + maxi(1, int(step_db / maxf(v.dc_rate, 0.000001))))
		elif v.sus_db <= -EG_RANGE_DB:
			v.dead = true
		else:
			lvl = v.sus_lin
		if f >= v.end_at:
			v.dead = true
		if v.dead:
			_pb.stop_stream(v.id)
			_stopped += 1
			if not v.killed:
				_live -= 1
			_remove_voice(i)
			i -= 1
			continue
		var g := g0 * lvl
		if absf(g - v.gain) > v.gain * 0.01 + 0.0000001:
			_pb.set_stream_volume(v.id, linear_to_db(g) if g > 0.0000001 else -140.0)
			v.gain = g
		if c.mod > 0:
			var vib := c.mod / 127.0 * VIBRATO_DEPTH * sin(TAU * VIBRATO_RATE * t / out_rate)
			_set_pitch(v, f, v.rate * c.bend_mul * pow(2.0, vib / 12.0))
			v.pitch_serial = -1
			nx = f + 1
		elif v.pitch_serial != c.pitch_serial:
			_set_pitch(v, f, v.rate * c.bend_mul)
			v.pitch_serial = c.pitch_serial
		if v.end_at < nx:
			nx = v.end_at
		_nexts[i] = nx
		if nx < min_next:
			min_next = nx
		i -= 1
	_min_next = min_next


func _set_pitch(v: Voice, f: int, p: float) -> void:
	_advance(v, f)
	_pb.set_stream_pitch_scale(v.id, p)
	v.step = p * v.step_per_rate
	_set_end(v)


# --- sample streams ------------------------------------------------------------------------------

## A 16-bit stereo stream of the region's sample with the pan baked in. The converted bytes are
## cached for every render (plain data only: no audio objects outlive the audio server); the
## stream objects only for this render.
func _stream_for(r: RPGSoundBank.Region, pan: float) -> AudioStreamWAV:
	var pan_q := roundi(pan * 32.0)
	var s := r.samples
	var n := s.size()
	var probe := [n, r.sample_rate, r.loop_mode, r.loop_start, r.loop_end, pan_q]
	for k in 8:
		probe.append(s[(n - 1) * k / 7])
	var key := hash(probe)
	var w: AudioStreamWAV = _streams.get(key)
	if w != null:
		return w
	_cache_mutex.lock()
	var bytes: PackedByteArray = _cache.get(key, PackedByteArray())
	_cache_mutex.unlock()
	if bytes.is_empty():
		var theta := (pan_q / 32.0 + 1.0) * PI / 4.0
		bytes = _stereo_bytes(r, cos(theta), sin(theta))
		_cache_mutex.lock()
		if _cache_bytes > CACHE_MAX_BYTES:
			_cache.clear()
			_cache_bytes = 0
		_cache[key] = bytes
		_cache_bytes += bytes.size()
		_cache_mutex.unlock()
	w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = r.sample_rate
	w.data = bytes
	if r.loop_mode > 0 and r.loop_end - r.loop_start >= 2 and r.loop_end <= n:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = r.loop_start
		w.loop_end = r.loop_end
	_streams[key] = w
	return w


## Drops the cached sample streams.
static func clear_cache() -> void:
	_cache_mutex.lock()
	_cache.clear()
	_cache_bytes = 0
	_cache_mutex.unlock()


## 16-bit interleaved stereo bytes of the region's sample times (gl, gr).
static func _stereo_bytes(r: RPGSoundBank.Region, gl: float, gr: float) -> PackedByteArray:
	var src := r.samples
	var looped := r.loop_mode == 1 and r.loop_end - r.loop_start >= 2 and r.loop_end <= src.size()
	if looped:
		# The data stops at the loop end, followed by the loop's first frames, so interpolation
		# across the jump reads the right neighbours.
		src = src.slice(0, r.loop_end) + src.slice(r.loop_start, mini(r.loop_start + 8, r.loop_end))
	# Mono floats -> (s, 0) pairs (Image does the interleave in C++) -> (s * gl, s * gr) -> 16 bit
	# (Godot's WAV loader converts float WAV data in C++).
	var img := Image.create_from_data(src.size(), 1, false, Image.FORMAT_RF, src.to_byte_array())
	img.convert(Image.FORMAT_RGF)
	var pairs := img.get_data().to_vector2_array()
	var stereo := Transform2D(Vector2(gl, gr), Vector2.ZERO, Vector2.ZERO) * pairs
	var w := AudioStreamWAV.load_from_buffer(wav_bytes(stereo, maxi(r.sample_rate, 1)), {"compress/mode": 0, "edit/loop_mode": 1})
	return w.data if w != null else PackedByteArray()
