extends "res://addons/rpg/runtime/rpg_extension.gd"
## Letter sounds (kit plugin "letter_sounds"): a short sound every N letters while a message
## types, its pitch and volume varied a little each time. Silent characters (spaces, punctuation)
## make no sound; text shown at once (OK pressed) makes none either.
##   Sound used: the "Change letter sound" command's, else the speaking actor's custom field
##   "letter_sound" (a message whose face or name is that actor's), else the setting; an empty
##   file is a built-in blip.
##   Codes: \LS[off] \LS[on] silence or resume from that point; \LS[file] another sound file;
##   \LS[pitch:120] \LS[volume:50] change it; \LS[] back to this message's sound.
##   The player turns it off with the options row "Letter Sounds".

const SECTION := "letter_sounds"
const VOICES := 3
const BLIP_RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _blip: AudioStreamWAV = null
var _rng := RandomNumberGenerator.new()
var _params: Dictionary = {}
var _count := 0
## The sound for the message being typed (a sound Dictionary; file "" = the built-in blip).
var current_sound: Dictionary = {}
## Silenced by \LS[off] until \LS[on] or the next message.
var muted := false
## The last sounds played, newest last (tests and debugging): [{file, pitch_scale, volume_db}].
var played: Array = []


func _extension_ready() -> void:
	rpg.register_text_code("LS", func(arg: String, _info: Dictionary) -> Variant: return {"action": _apply_code.bind(arg.strip_edges())})
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)


## The sound a message starts with (see the top of this file).
func sound_for(params: Dictionary) -> Dictionary:
	var s := section(SECTION)
	if s.get("sound") is Dictionary:
		return s.sound.duplicate()
	if bool(setting("actor_sounds", true)):
		var actor := speaker_actor(params)
		if actor != "":
			var v: Variant = rpg.extensions.custom_field("actors", actor, "letter_sound")
			if v is Dictionary and str(v.get("file", "")) != "":
				return v.duplicate()
	var d: Variant = setting("sound", {})
	return d.duplicate() if d is Dictionary else {}


## The actor whose face (or name) a message shows, or "".
func speaker_actor(params: Dictionary) -> String:
	var face: Variant = params.get("face")
	var name := RPGText.expand_plain(str(params.get("name", "")), rpg).strip_edges() if str(params.get("name", "")) != "" else ""
	for rec in rpg.data.records("actors"):
		var id := str(rec.get("id", ""))
		if face is Dictionary and str(face.get("sheet", "")) != "":
			var look: Dictionary = rpg.state.actor_look(id) if rpg.state.has_method("actor_look") else {}
			var sheet := str(look.get("face", rec.get("face", "")))
			var idx := int(look.get("face_index", rec.get("face_index", 0)))
			if sheet == str(face.sheet) and idx == int(face.get("index", 0)):
				return id
		if name != "" and (name == RPGText._actor_name(rpg, id) or name == str(rec.get("name", ""))):
			return id
	return ""


func on_message_opened(params: Dictionary) -> void:
	_params = params
	current_sound = sound_for(params)
	muted = false
	_count = 0


func _apply_code(arg: String) -> void:
	var low := arg.to_lower()
	if low == "off":
		muted = true
	elif low == "on":
		muted = false
	elif low == "" or low == "default":
		current_sound = sound_for(_params)
		muted = false
	elif low.begins_with("pitch:"):
		current_sound["pitch"] = clampi(low.substr(6).to_int(), 25, 400)
	elif low.begins_with("volume:"):
		current_sound["volume"] = clampi(low.substr(7).to_int(), 0, 100)
	else:
		current_sound["file"] = arg
		muted = false


## True when letter sounds play now: the player's option, and not turned off by an event.
func active() -> bool:
	return bool(option("enabled", true)) and not bool(section(SECTION).get("disabled", false))


func on_message_char(character: String, _index: int, instant: bool) -> void:
	if instant or muted or not active():
		return
	if character.strip_edges() == "" or str(setting("silent_chars", "")).contains(character):
		return
	_count += 1
	var every := maxi(1, int(section(SECTION).get("interval", setting("interval", 2))))
	if (_count - 1) % every != 0:
		return
	play(current_sound)


## Plays one blip of `sound` with the random variation from the settings.
func play(sound: Dictionary) -> void:
	var file := str(sound.get("file", ""))
	var stream: AudioStream = null
	if file != "" and rpg.audio != null and rpg.audio.has_method("resolve"):
		stream = rpg.audio.resolve("sound", sound, true)
	if stream == null:
		stream = blip()
	var pv := float(setting("pitch_variance", 10)) / 100.0
	var vv := float(setting("volume_variance", 10)) / 100.0
	var pitch := clampf(float(sound.get("pitch", 100)) / 100.0 * (1.0 + _rng.randf_range(-pv, pv)), 0.25, 4.0)
	var master: float = float(rpg.audio.master_sound) if rpg.audio != null and "master_sound" in rpg.audio else 1.0
	var vol := clampf(float(sound.get("volume", 60)) / 100.0 * (1.0 + _rng.randf_range(-vv, vv)) * master, 0.0001, 1.5)
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(vol)
	p.play()
	played.append({"file": file, "pitch_scale": pitch, "volume_db": p.volume_db})
	if played.size() > 64:
		played.pop_front()


## A 45 ms square-wave blip made in code (no asset needed).
func blip() -> AudioStreamWAV:
	if _blip != null:
		return _blip
	var n := int(BLIP_RATE * 0.045)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / BLIP_RATE
		var env := exp(-t * 60.0) * minf(1.0, float(i) / 40.0)
		var v := (1.0 if fmod(t * 740.0, 1.0) < 0.5 else -1.0) * env * 0.35
		data.encode_s16(i * 2, int(v * 32767.0))
	_blip = AudioStreamWAV.new()
	_blip.format = AudioStreamWAV.FORMAT_16_BITS
	_blip.mix_rate = BLIP_RATE
	_blip.stereo = false
	_blip.data = data
	return _blip


## "Change letter sound": on/off for the game, another sound, or the interval (0 = keep).
func change(enabled: String, sound_mode: String, sound: Variant, interval: int) -> void:
	var s := section(SECTION)
	match enabled:
		"on": s.erase("disabled")
		"off": s["disabled"] = true
	match sound_mode:
		"set":
			if sound is Dictionary:
				s["sound"] = sound.duplicate()
		"default":
			s.erase("sound")
	if interval > 0:
		s["interval"] = interval
	elif interval < 0:
		s.erase("interval")
