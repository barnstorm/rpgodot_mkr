@tool
class_name RPGSoundBank
extends RefCounted
## A General MIDI instrument bank that the MIDI renderer plays notes with. One of:
##   RPGDlsBank     a DLS level 1/2 file (Windows' C:/Windows/System32/drivers/gm.dls, the Microsoft
##                  GS Wavetable set RPG Maker 2000/2003 and XP played their MIDI through)
##   RPGSf2Bank     an SF2 SoundFont (for example GeneralUser GS)
##   RPGBuiltinBank simple instruments made in code (always available; no files, no licence)
## The renderer only uses this interface:
##   var bank := RPGSoundBank.open(path)          # null when the file cannot be read (see last_error)
##   var regions := bank.regions_for(bank_no, program, key, velocity, drums)
## and plays every returned Region at once (SF2 stereo pairs and layered zones come back as several).
##
## Units are already converted for the renderer: seconds, linear 0..1 levels, semitones, frames.

## Why the last open() failed ("" when it did not).
static var last_error := ""


## One playable sample zone for a note.
class Region:
	extends RefCounted
	## Mono sample data, -1..1. Shared between regions that use the same sample: never modify it.
	var samples := PackedFloat32Array()
	## The sample's own rate (Hz).
	var sample_rate := 22050
	## The MIDI key that plays the sample at its own rate, with fine tuning folded in (semitones,
	## so 60.25 is middle C a quarter tone sharp).
	var root_key := 60.0
	## How far the pitch moves per key: 1.0 normally, 0.0 for sounds that never change pitch
	## (SF2 scaleTuning / 100).
	var scale_tuning := 1.0
	## 0 = play once, 1 = loop for as long as the voice sounds, 2 = loop until note-off, then play
	## the rest of the sample (SF2 sampleModes 3).
	var loop_mode := 0
	## Loop start and end in sample frames (end exclusive). Only used when loop_mode > 0.
	var loop_start := 0
	var loop_end := 0
	## Fixed attenuation of this zone in dB (positive is quieter). Velocity is the renderer's job.
	var attenuation_db := 0.0
	## -1 left .. 0 centre .. 1 right (added to the channel's CC10 pan by the renderer).
	var pan := 0.0
	## Volume envelope, seconds and a linear sustain level (0..1 of the peak).
	var delay := 0.0
	var attack := 0.0
	var hold := 0.0
	var decay := 0.0
	var sustain := 1.0
	var release := 0.05
	## Notes with the same non-zero class cut each other off on the channel (open/closed hi-hat).
	var exclusive_class := 0


## Opens a bank by path: ".sf2", ".dls", or "builtin". Returns null (and sets last_error) on failure.
static func open(path: String) -> RPGSoundBank:
	last_error = ""
	var p := path.strip_edges()
	var script_path := ""
	if p == "" or p == "builtin":
		script_path = "res://addons/rpg/import/midi/rpg_builtin_bank.gd"
	else:
		match p.get_extension().to_lower():
			"sf2": script_path = "res://addons/rpg/import/midi/rpg_sf2_bank.gd"
			"dls": script_path = "res://addons/rpg/import/midi/rpg_dls_bank.gd"
			_:
				last_error = "'%s' is not a sound bank (use an .sf2 or .dls file, or builtin)." % p
				return null
	if not ResourceLoader.exists(script_path):
		last_error = "Sound bank support is missing (%s)." % script_path.get_file()
		return null
	var cls: Script = load(script_path)
	var bank: RPGSoundBank = cls.new()
	var err := bank.load_bank(p)
	if err != "":
		last_error = err
		return null
	return bank


## The default bank when a project names none: Windows' gm.dls when it exists, else builtin.
static func default_path() -> String:
	var dls := OS.get_environment("WINDIR").path_join("System32/drivers/gm.dls").replace("\\", "/")
	if OS.get_name() == "Windows" and FileAccess.file_exists(dls):
		return dls
	return "builtin"


## Subclasses: read the file. Returns "" on success or a message for the maker.
func load_bank(_path: String) -> String:
	return "load_bank() is not implemented."


## Subclasses: the regions to play for a note. `bank_no` is the MIDI bank (CC0 * 128 + CC32);
## `drums` is true on MIDI channel 10. Fall back the way GM synths do: an unknown bank variation
## uses bank 0 with the same program, an unknown drum kit uses kit 0, and an unknown program
## returns [] (the note is silent).
func regions_for(_bank_no: int, _program: int, _key: int, _velocity: int, _drums: bool) -> Array:
	return []


## A short name for messages ("gm.dls", "GeneralUser-GS.sf2", "built-in instruments").
func bank_name() -> String:
	return "sound bank"
