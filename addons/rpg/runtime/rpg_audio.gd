class_name RPGAudio
extends Node
## Music (BGM), background sound (BGS), jingles (ME, which pause the music) and sound effects.
## Sounds are named by file or by role: {"file": "Door1", "volume": 100, "pitch": 100, "pan": 0}
## or {"role": "door_open"}. Roles map to files through the project, then the profile.
##
## As in RPG Maker MV, music can be saved with its position and replayed from there
## (save_bgm / replay_bgm: battles, vehicles, save files), a jingle pauses the music and the music
## fades back in where it was, and OGG files loop from their LOOPSTART tag.
##
## MIDI music is imported as an AudioStreamWAV that already loops from the song's CC#111 (the
## loop is kept). Its reverb send (stream metadata "rpg_midi_reverb", the song's average CC91) is
## played through the "RPG Music Reverb" bus, made on demand and sent to Master, so the Master
## limiter still applies. Known limitation: RPG Maker's MIDI "tempo" changes the speed without
## changing the pitch; here a sound's pitch (pitch_scale) changes both, as it does for OGG/WAV.

const ASSETS_SCRIPT := "res://addons/rpg/core/rpg_assets.gd"
const PROFILE_SCRIPT := "res://addons/rpg/core/rpg_profile.gd"
## Quietest volume used: -80 dB is silence to the audio server (0% never becomes -inf).
const SILENT_DB := -80.0
## Music fades back in over this time after a jingle (MV's replay fade).
const RESUME_FADE := 0.5
## Ceiling of the limiter added to the Master bus when the project has no bus effects of its own.
const LIMITER_CEILING_DB := -0.3
## Bus for rendered MIDI music with a reverb send (made on demand, sent to Master).
const REVERB_BUS := "RPG Music Reverb"
## Reverb wet level at a send of 127 (the GM default of 40 gives about 0.13): modest on purpose.
const REVERB_WET := 0.4

var bgm: AudioStreamPlayer
var bgs: AudioStreamPlayer
var me: AudioStreamPlayer
var se_pool: Array[AudioStreamPlayer] = []
var current_bgm: Dictionary = {}
var current_bgs: Dictionary = {}
var master_music := 1.0
var master_sound := 1.0
var _warned: Dictionary = {}
var _cache: Dictionary = {}
var _assets: Variant = null
var _profile: Variant = null
## Where the music stopped when a jingle started (it resumes there).
var _bgm_pos := 0.0
var _bgm_fade: Tween = null


func _init() -> void:
	name = "Audio"


func _ready() -> void:
	bgm = _player("BGM")
	bgs = _player("BGS")
	me = _player("ME")
	me.finished.connect(_on_me_finished)
	for i in 8:
		se_pool.append(_player("SE%d" % i))
	if ResourceLoader.exists(ASSETS_SCRIPT):
		_assets = load(ASSETS_SCRIPT)
	ensure_master_limiter()


func _player(n: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	add_child(p)
	return p


## Adds a hard limiter (ceiling -0.3 dB) to the Master bus so a loud battle start does not clip.
## Left alone when the project's bus layout has more buses or effects of its own.
static func ensure_master_limiter() -> void:
	if AudioServer.bus_count != 1 or AudioServer.get_bus_effect_count(0) > 0:
		return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = LIMITER_CEILING_DB
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(0, lim)


## Volume in dB for a 0..1 level, never below SILENT_DB.
static func level_db(level: float) -> float:
	if level <= 0.0001:
		return SILENT_DB
	return maxf(linear_to_db(level), SILENT_DB)


## Resolves a sound role to a file name.
func role_file(role: String) -> String:
	var rpg := get_parent()
	if rpg != null and "data" in rpg and rpg.data != null:
		var roles: Dictionary = rpg.data.project.get("sound_roles", {})
		if roles.has(role):
			return roles[role]
		if _profile == null and ResourceLoader.exists(PROFILE_SCRIPT):
			var ps: Script = load(PROFILE_SCRIPT)
			if ps.has_method("load_profile"):
				_profile = ps.load_profile(rpg.data.profile.get("profile", "rm2k"))
			elif ps.has_method("load"):
				_profile = ps.call("load", rpg.data.profile.get("profile", "rm2k"))
		if _profile != null and _profile.has_method("sound_role"):
			var f: String = _profile.sound_role(role)
			if f != "":
				return f
	return role


## `quiet`: no "not found" warning (the caller tries another kind next).
func resolve(kind: String, sound: Variant, quiet := false) -> AudioStream:
	if sound == null:
		return null
	var file := ""
	if sound is String:
		file = sound
	elif sound is Dictionary:
		file = sound.get("file", sound.get("name", ""))
		if file == "" and sound.has("role"):
			file = role_file(sound.role)
	if file == "":
		return null
	var key := kind + ":" + file
	if _cache.has(key) and (_cache[key] != null or quiet or _warned.has(key)):
		return _cache[key]
	var stream: AudioStream = null
	if file.begins_with("res://"):
		if ResourceLoader.exists(file):
			stream = load(file)
	elif _assets != null:
		if _assets.has_method("load_audio"):
			stream = _assets.load_audio(kind, file)
	if stream == null and not quiet and not _warned.has(key):
		_warned[key] = true
		push_warning("RPG audio: %s '%s' not found." % [kind, file])
	_cache[key] = stream
	return stream


static func _vol(sound: Variant) -> float:
	if sound is Dictionary:
		return level_db(float(sound.get("volume", 100)) / 100.0)
	return 0.0


## Pitch scale from the sound's pitch (100 = normal). For rendered MIDI this changes the speed
## and the pitch together, unlike RPG Maker's MIDI tempo (speed only): a known limitation.
static func _pitch(sound: Variant) -> float:
	if sound is Dictionary:
		return clampf(float(sound.get("pitch", 100)) / 100.0, 0.25, 4.0)
	return 1.0


## Volume the music player should have now (sound volume and the Music option).
func bgm_db() -> float:
	return maxf(_vol(current_bgm) + level_db(master_music), SILENT_DB)


func bgs_db() -> float:
	return maxf(_vol(current_bgs) + level_db(master_sound), SILENT_DB)


## The sound without its saved position (current_bgm never keeps one).
static func _without_pos(sound: Dictionary) -> Dictionary:
	var d := sound.duplicate()
	d.erase("pos")
	return d


## Plays music. `pos` (seconds) starts it part-way; when the same track is already playing it keeps
## playing (only volume and pitch change), unless `pos` >= 0 asks for that place.
func play_bgm(sound: Variant, pos := -1.0) -> void:
	if sound == null or (sound is Dictionary and sound.get("file", "") == "" and not sound.has("role")):
		stop_bgm()
		return
	_kill_fade()
	var wanted: Dictionary = _without_pos(sound) if sound is Dictionary else {"file": str(sound)}
	if sound is Dictionary and is_current_bgm(sound) and (bgm.playing or me.playing):
		current_bgm = wanted
		bgm.volume_db = bgm_db()
		bgm.pitch_scale = _pitch(sound)
		if pos >= 0.0:
			if bgm.playing:
				bgm.seek(pos)
			else:
				_bgm_pos = pos
		return
	var stream := resolve("music", sound)
	current_bgm = wanted
	if stream == null:
		bgm.stop()
		bgm.stream = null
		return
	_set_loop(stream)
	bgm.stream = stream
	route_reverb(bgm, stream)
	bgm.volume_db = bgm_db()
	bgm.pitch_scale = _pitch(sound)
	var at := maxf(pos, 0.0)
	if me.playing:
		# The jingle finishes first; the music then starts here (see _on_me_finished).
		bgm.stop()
		_bgm_pos = at
	else:
		bgm.play(at)


## True when `sound` names the track now set as music.
func is_current_bgm(sound: Variant) -> bool:
	if not (sound is Dictionary) or current_bgm.is_empty() or bgm.stream == null:
		return false
	return str(current_bgm.get("file", "")) == str(sound.get("file", "-")) and str(current_bgm.get("file", "")) != ""


func stop_bgm() -> void:
	_kill_fade()
	bgm.stop()
	current_bgm = {}
	_bgm_pos = 0.0


## Where the music is now (seconds); while a jingle plays, where it will resume.
func bgm_position() -> float:
	if bgm.playing:
		return bgm.get_playback_position()
	if me.playing:
		return _bgm_pos
	return 0.0


## The current music with its position ("pos", seconds), or {} when none: MV's saveBgm.
func save_bgm() -> Dictionary:
	if current_bgm.is_empty():
		return {}
	var d := current_bgm.duplicate()
	d["pos"] = bgm_position()
	return d


## Plays music saved by save_bgm from its position (MV's replayBgm). The same track already
## playing just goes on; {} stops the music.
func replay_bgm(saved: Dictionary, fade := true) -> void:
	if saved.is_empty() or str(saved.get("file", "")) == "":
		stop_bgm()
		return
	if is_current_bgm(saved) and (bgm.playing or me.playing):
		play_bgm(saved)
		return
	play_bgm(saved, float(saved.get("pos", 0.0)))
	if fade and bgm.playing:
		_fade_in_bgm(RESUME_FADE)


func fade_bgm(seconds: float) -> Signal:
	_kill_fade()
	var t := create_tween()
	_bgm_fade = t
	var from := bgm.volume_db
	# The tween always runs to its end (a waiting Fade Out Music command needs `finished`), but
	# once replaced (play_bgm, another fade) it no longer touches the music.
	var set_volume := func(v: float) -> void:
		if _bgm_fade == t:
			bgm.volume_db = v
	var done := func() -> void:
		if _bgm_fade == t:
			_bgm_fade = null
			stop_bgm()
	t.tween_method(set_volume, from, SILENT_DB, maxf(seconds, 0.01))
	t.tween_callback(done)
	return t.finished


func _fade_in_bgm(seconds: float) -> void:
	_kill_fade()
	var target := bgm_db()
	bgm.volume_db = maxf(target - 30.0, SILENT_DB)
	var t := create_tween()
	_bgm_fade = t
	var set_volume := func(v: float) -> void:
		if _bgm_fade == t:
			bgm.volume_db = v
	var done := func() -> void:
		if _bgm_fade == t:
			_bgm_fade = null
	t.tween_method(set_volume, maxf(target - 30.0, SILENT_DB), target, seconds)
	t.tween_callback(done)


## True while a fade (out, or in after a jingle) is changing the music volume.
func is_fading() -> bool:
	return _bgm_fade != null


## Stops any fade from touching the music and puts its volume back.
func _kill_fade() -> void:
	_bgm_fade = null
	if bgm != null and not current_bgm.is_empty():
		bgm.volume_db = bgm_db()


func play_bgs(sound: Variant, pos := 0.0) -> void:
	var stream := resolve("sound", sound)
	current_bgs = _without_pos(sound) if sound is Dictionary else {}
	if stream == null:
		bgs.stop()
		return
	_set_loop(stream)
	bgs.stream = stream
	bgs.volume_db = bgs_db()
	bgs.play(maxf(pos, 0.0))


func stop_bgs() -> void:
	bgs.stop()
	current_bgs = {}


## The current background sound with its position, or {}.
func save_bgs() -> Dictionary:
	if current_bgs.is_empty():
		return {}
	var d := current_bgs.duplicate()
	d["pos"] = bgs.get_playback_position() if bgs.playing else 0.0
	return d


func replay_bgs(saved: Dictionary) -> void:
	if saved.is_empty() or str(saved.get("file", "")) == "":
		stop_bgs()
		return
	if bgs.playing and str(current_bgs.get("file", "")) == str(saved.get("file", "-")):
		return
	play_bgs(saved, float(saved.get("pos", 0.0)))


func play_me(sound: Variant) -> Signal:
	# A jingle is a Music file, or else a sound effect file (sound roles name sound effects).
	var stream := resolve("music", sound, true)
	if stream == null:
		stream = resolve("sound", sound, true)
	if stream == null:
		resolve("music", sound)
	if stream == null:
		var t := create_tween()
		t.tween_interval(0.0)
		return t.finished
	stream = jingle_stream(stream)
	if bgm.playing:
		_kill_fade()
		_bgm_pos = bgm.get_playback_position()
		bgm.stop()
	me.stream = stream
	route_reverb(me, stream)
	me.volume_db = maxf(_vol(sound) + level_db(master_music), SILENT_DB)
	me.pitch_scale = _pitch(sound)
	me.play()
	return me.finished


func stop_me() -> void:
	me.stop()


func _on_me_finished() -> void:
	if bgm.stream != null and not current_bgm.is_empty():
		bgm.volume_db = bgm_db()
		bgm.play(_bgm_pos)
		_fade_in_bgm(RESUME_FADE)


func play_se(sound: Variant) -> void:
	var stream := resolve("sound", sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = null
	for candidate in se_pool:
		if not candidate.playing:
			p = candidate
			break
	if p == null:
		p = se_pool[0]
	p.stream = stream
	p.volume_db = maxf(_vol(sound) + level_db(master_sound), SILENT_DB)
	p.pitch_scale = _pitch(sound)
	p.play()


func play_role(role: String) -> void:
	play_se({"role": role})


## Music loops: a WAV that has a loop of its own (rendered MIDI loops from its CC#111) keeps it.
func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# From the length, not the data size: QOA and ADPCM data are not 1 or 2 bytes a sample.
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
		if _assets != null and _assets.has_method("apply_loop_points") and not stream.has_meta("rpg_loop_checked"):
			_assets.apply_loop_points(stream)
	elif stream is AudioStreamMP3:
		stream.loop = true


## Plays rendered MIDI with a reverb send through the reverb bus, everything else on Master.
func route_reverb(p: AudioStreamPlayer, stream: AudioStream) -> void:
	var level := float(stream.get_meta("rpg_midi_reverb", 0.0)) if stream != null else 0.0
	p.bus = reverb_bus(level) if level > 0.01 else &"Master"


## The "RPG Music Reverb" bus (an AudioEffectReverb, sent to Master), made when first needed, with
## its wet level set for `level` (a song's average CC91 send, 0..1).
static func reverb_bus(level: float) -> StringName:
	var i := AudioServer.get_bus_index(REVERB_BUS)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, REVERB_BUS)
		AudioServer.set_bus_send(i, &"Master")
		var fx := AudioEffectReverb.new()
		fx.room_size = 0.55
		fx.damping = 0.6
		fx.spread = 1.0
		fx.hipass = 0.1
		fx.dry = 1.0
		AudioServer.add_bus_effect(i, fx)
	var rv := AudioServer.get_bus_effect(i, 0) as AudioEffectReverb if AudioServer.get_bus_effect_count(i) > 0 else null
	if rv != null:
		rv.wet = clampf(level, 0.0, 1.0) * REVERB_WET
	return StringName(REVERB_BUS)


## LOOPLENGTH ending before the end of the file: jump back to the loop start there.
func _process(_delta: float) -> void:
	for p in [bgm, bgs]:
		if p == null or not p.playing or p.stream == null or not p.stream.has_meta("rpg_loop_end"):
			continue
		var end := float(p.stream.get_meta("rpg_loop_end"))
		if end > 0.0 and p.get_playback_position() >= end:
			p.seek(float(p.stream.get("loop_offset")))


## A copy of `stream` that plays once. Music streams are cached set to loop (see _set_loop and
## RPGAssets), and a jingle that loops never emits `finished`, so a "wait" jingle would hang.
static func jingle_stream(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var w: AudioStreamWAV = stream.duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_DISABLED
		return w
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		var s: AudioStream = stream.duplicate()
		s.set("loop", false)
		if s.has_meta("rpg_loop_end"):
			s.remove_meta("rpg_loop_end")
		return s
	return stream


func stop_all() -> void:
	_kill_fade()
	bgm.stop()
	bgs.stop()
	me.stop()
	for p in se_pool:
		p.stop()
	current_bgm = {}
	current_bgs = {}
	_bgm_pos = 0.0


## Drops every stream reference (game exit), so no stream outlives the audio server.
func release_streams() -> void:
	for p in [bgm, bgs, me] + se_pool:
		if p != null:
			p.stop()
			p.stream = null
	_cache.clear()
