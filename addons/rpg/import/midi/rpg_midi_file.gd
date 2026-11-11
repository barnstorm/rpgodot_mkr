@tool
class_name RPGMidiFile
extends RefCounted
## A Standard MIDI File (.mid), read into one time-sorted event list for the renderer.
##   var midi := RPGMidiFile.load_file("res://assets/rtp/Music/Field1.mid")
##   if midi.error != "": push_error(midi.error)
##   for i in midi.event_count(): midi.times[i], midi.messages[i]
##
## Reads formats 0 and 1 (format 2, independent sequences, is refused with a clear error), ticks per
## quarter note and SMPTE time division, running status, sysex, meta events (tempo and end of track
## are used; the rest are skipped) and the RIFF 'RMID' wrapper.
##
## Output:
##   times      absolute seconds of every event, sorted (ties keep track order, then file order)
##   messages   channel messages packed as status | data1 << 8 | data2 << 16; a sysex event is 0xF0
##              and its bytes (after the F0) are in sysex[index]
##   length     the song length: the latest end-of-track (not the last note-off)
##   loop_start where RPG Maker XP / VX / 2003 and EasyRPG loop: the first CC#111 event, else 0
##
## Meta events are not in the event list; the tempo changes are in `tempo_map`.

## Events are sorted by tick << 22 | index, so a file may hold up to this many.
const MAX_EVENTS := 1 << 22
const MAX_TICK := (1 << 40) - 1

## Why the file could not be read ("" when it could).
var error := ""
## Things that were wrong but did not stop the read (a truncated track, an unknown chunk).
var warnings := PackedStringArray()
var format := 0
var track_count := 0
## Ticks per quarter note, or 0 for SMPTE time.
var ticks_per_quarter := 0
## SMPTE time: frames per second (24, 25, 29.97 or 30) and ticks per frame.
var smpte_fps := 0.0
var smpte_ticks := 0
var times := PackedFloat64Array()
var ticks := PackedInt64Array()
var messages := PackedInt32Array()
## Event index -> sysex bytes after the F0 (the closing F7 included when the file has it).
var sysex := {}
var length := 0.0
var length_ticks := 0
var loop_start := 0.0
## True when the song has a CC#111 loop marker.
var has_loop_marker := false
## [[tick, seconds, microseconds per quarter], ...] from tick 0 (120 BPM until the first change).
var tempo_map: Array = []


## Reads a file (res://, user:// or an absolute path). Check `error`.
static func load_file(path: String) -> RPGMidiFile:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var m := RPGMidiFile.new()
		var err := FileAccess.get_open_error()
		m.error = ("Cannot read %s (%s)." % [path, error_string(err)]) if err != OK else ("%s is empty." % path)
		return m
	return parse(bytes)


## Reads SMF bytes (or an RMID file). Check `error`.
static func parse(bytes: PackedByteArray) -> RPGMidiFile:
	var m := RPGMidiFile.new()
	m._read(bytes)
	return m


func is_valid() -> bool:
	return error == ""


func event_count() -> int:
	return messages.size()


## The events as dictionaries, for inspection and tests:
## {time, tick, status, channel, data1, data2} (sysex events also have "sysex": bytes).
func events() -> Array:
	var out := []
	for i in messages.size():
		var msg := messages[i]
		var st := msg & 0xff
		var e := {"time": times[i], "tick": ticks[i], "status": st, "channel": st & 0x0f if st < 0xf0 else -1,
			"data1": (msg >> 8) & 0x7f, "data2": (msg >> 16) & 0x7f}
		if sysex.has(i):
			e["sysex"] = sysex[i]
		out.append(e)
	return out


## Seconds at a tick, from the tempo map.
func tick_to_seconds(tick: int) -> float:
	if ticks_per_quarter <= 0:
		return tick / (smpte_fps * smpte_ticks) if smpte_fps > 0.0 and smpte_ticks > 0 else 0.0
	var seg := 0
	while seg + 1 < tempo_map.size() and int(tempo_map[seg + 1][0]) <= tick:
		seg += 1
	return _seconds_in(seg, tick)


func _seconds_in(seg: int, tick: int) -> float:
	if ticks_per_quarter <= 0:
		return tick / (smpte_fps * smpte_ticks)
	var t: Array = tempo_map[seg]
	return float(t[1]) + (tick - int(t[0])) * float(t[2]) / 1000000.0 / ticks_per_quarter


# --- reading -------------------------------------------------------------------------------------

func _read(bytes: PackedByteArray) -> void:
	var data := bytes
	if data.size() >= 12 and _tag(data, 0) == "RIFF" and _tag(data, 8) == "RMID":
		data = _rmid_data(data)
		if data.is_empty():
			error = "This RMID file has no MIDI 'data' chunk."
			return
	if data.size() < 14 or _tag(data, 0) != "MThd":
		error = "Not a MIDI file (no MThd header)."
		return
	var hlen := _u32(data, 4)
	if hlen < 6 or 8 + hlen > data.size():
		error = "The MIDI header is damaged."
		return
	format = _u16(data, 8)
	track_count = _u16(data, 10)
	var division := _u16(data, 12)
	if format == 2:
		error = "MIDI format 2 (several independent songs in one file) is not supported; save it as format 0 or 1."
		return
	if format > 2:
		error = "Unknown MIDI format %d." % format
		return
	if division & 0x8000:
		var fps := 256 - (division >> 8)
		smpte_fps = 29.97 if fps == 29 else float(fps)
		smpte_ticks = division & 0xff
		if smpte_fps <= 0.0 or smpte_ticks <= 0:
			error = "The MIDI header has an invalid SMPTE time division."
			return
	else:
		ticks_per_quarter = division
		if ticks_per_quarter <= 0:
			error = "The MIDI header has 0 ticks per quarter note."
			return
	# Every track's events go into the same arrays, in track order, then file order; sorting the
	# keys tick << 22 | index then keeps that order for events at the same tick.
	var ev_tick := PackedInt64Array()
	var ev_msg := PackedInt32Array()
	var ev_sysex := {}
	var tempos: Array = []
	var ends := PackedInt64Array()
	var pos := 8 + hlen
	var found := 0
	while pos + 8 <= data.size() and found < track_count:
		var tag := _tag(data, pos)
		var clen := _u32(data, pos + 4)
		var start := pos + 8
		pos = start + clen
		if tag != "MTrk":
			warnings.append("Skipped an unknown '%s' chunk." % tag.c_escape())
			continue
		if pos > data.size():
			warnings.append("Track %d is cut short; read what is there." % found)
			pos = data.size()
		ends.append(_read_track(data, start, pos, found, ev_tick, ev_msg, ev_sysex, tempos))
		found += 1
	if found == 0:
		error = "The MIDI file has no tracks."
		return
	if found < track_count:
		warnings.append("The header lists %d tracks but %d were found." % [track_count, found])
	track_count = found
	var n := ev_msg.size()
	if n >= MAX_EVENTS:
		error = "The MIDI file has too many events (%d)." % n
		return
	_build_tempo_map(tempos)
	var keys := PackedInt64Array()
	keys.resize(n)
	for i in n:
		keys[i] = (ev_tick[i] << 22) | i
	keys.sort()
	times.resize(n)
	ticks.resize(n)
	messages.resize(n)
	var loop_tick := -1
	var seg := 0
	for j in n:
		var i := keys[j] & (MAX_EVENTS - 1)
		var tick := ev_tick[i]
		var msg := ev_msg[i]
		ticks[j] = tick
		messages[j] = msg
		if ev_sysex.has(i):
			sysex[j] = ev_sysex[i]
		if loop_tick < 0 and (msg & 0xf0) == 0xb0 and ((msg >> 8) & 0x7f) == 111:
			loop_tick = tick
		# Ticks only grow here, so the tempo segment only moves forward.
		while seg + 1 < tempo_map.size() and int(tempo_map[seg + 1][0]) <= tick:
			seg += 1
		times[j] = _seconds_in(seg, tick)
	length_ticks = 0
	for t in ends:
		length_ticks = maxi(length_ticks, t)
	length = tick_to_seconds(length_ticks)
	if loop_tick >= 0:
		has_loop_marker = true
		loop_start = tick_to_seconds(loop_tick)


## Reads one MTrk chunk into the event arrays. Returns its end-of-track tick.
func _read_track(d: PackedByteArray, pos: int, end: int, track: int, ev_tick: PackedInt64Array, ev_msg: PackedInt32Array, ev_sysex: Dictionary, tempos: Array) -> int:
	var tick := 0
	var running := 0
	var end_tick := -1
	while pos < end:
		var v := _vlq(d, pos, end)
		if v[1] < 0:
			warnings.append("Track %d ends in the middle of an event." % track)
			break
		tick = mini(tick + v[0], MAX_TICK)
		pos = v[1]
		if pos >= end:
			warnings.append("Track %d ends in the middle of an event." % track)
			break
		var b := d[pos]
		if b == 0xff:
			if pos + 1 >= end:
				break
			var typ := d[pos + 1]
			var lv := _vlq(d, pos + 2, end)
			if lv[1] < 0 or lv[1] + lv[0] > end:
				warnings.append("Track %d has a cut-off meta event." % track)
				break
			var at: int = lv[1]
			var ln: int = lv[0]
			pos = at + ln
			if typ == 0x51 and ln >= 3:
				tempos.append([tick, tempos.size(), (d[at] << 16) | (d[at + 1] << 8) | d[at + 2]])
			elif typ == 0x2f:
				end_tick = tick
				break
			continue
		if b == 0xf0 or b == 0xf7:
			var sv := _vlq(d, pos + 1, end)
			if sv[1] < 0 or sv[1] + sv[0] > end:
				warnings.append("Track %d has a cut-off sysex event." % track)
				break
			if b == 0xf0:
				ev_sysex[ev_msg.size()] = d.slice(sv[1], sv[1] + sv[0])
				ev_tick.append(tick)
				ev_msg.append(0xf0)
			pos = sv[1] + sv[0]
			continue
		var status := running
		if b & 0x80:
			if b > 0xef:
				warnings.append("Track %d has an invalid byte 0x%02X; the rest of the track is skipped." % [track, b])
				break
			status = b
			running = b
			pos += 1
		elif running == 0:
			warnings.append("Track %d has data without a status byte; the rest of the track is skipped." % track)
			break
		var hi := status & 0xf0
		var count := 1 if hi == 0xc0 or hi == 0xd0 else 2
		if pos + count > end:
			warnings.append("Track %d ends in the middle of an event." % track)
			break
		var d1 := d[pos] & 0x7f
		var d2 := d[pos + 1] & 0x7f if count == 2 else 0
		pos += count
		ev_tick.append(tick)
		ev_msg.append(status | (d1 << 8) | (d2 << 16))
	if end_tick < 0:
		end_tick = tick
		warnings.append("Track %d has no end-of-track event." % track)
	return end_tick


func _build_tempo_map(tempos: Array) -> void:
	tempo_map = [[0, 0.0, 500000]]
	if ticks_per_quarter <= 0:
		return
	tempos.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	for t in tempos:
		var last: Array = tempo_map[-1]
		var tick: int = t[0]
		var usec: int = maxi(1, t[2])
		var secs: float = float(last[1]) + (tick - int(last[0])) * float(last[2]) / 1000000.0 / ticks_per_quarter
		if tick == int(last[0]):
			tempo_map[-1] = [tick, last[1], usec]
		else:
			tempo_map.append([tick, secs, usec])


## The SMF bytes inside a RIFF RMID file ("data" chunk), or empty.
static func _rmid_data(d: PackedByteArray) -> PackedByteArray:
	var pos := 12
	while pos + 8 <= d.size():
		var tag := _tag(d, pos)
		var ln := d.decode_u32(pos + 4)
		if tag == "data":
			return d.slice(pos + 8, mini(pos + 8 + ln, d.size()))
		pos += 8 + ln + (ln & 1)
	return PackedByteArray()


## [value, next position], or [0, -1] when it runs past `end`.
static func _vlq(d: PackedByteArray, pos: int, end: int) -> Array:
	var v := 0
	for i in 4:
		if pos >= end:
			return [0, -1]
		var b := d[pos]
		pos += 1
		v = (v << 7) | (b & 0x7f)
		if (b & 0x80) == 0:
			return [v, pos]
	return [v, pos]


static func _tag(d: PackedByteArray, pos: int) -> String:
	if pos + 4 > d.size():
		return ""
	return d.slice(pos, pos + 4).get_string_from_ascii()


static func _u32(d: PackedByteArray, pos: int) -> int:
	return (d[pos] << 24) | (d[pos + 1] << 16) | (d[pos + 2] << 8) | d[pos + 3]


static func _u16(d: PackedByteArray, pos: int) -> int:
	return (d[pos] << 8) | d[pos + 1]
