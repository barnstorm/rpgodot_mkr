@tool
class_name RPGBuiltinBank
extends RPGSoundBank
## General MIDI instruments made in code, so MIDI music always plays even without a bank file.
## One sound per GM family (programs 0-127 in 16 families of 8) and one drum kit (keys 27-87):
##   - sustained families loop a band-limited single-cycle wave (one per key range, with fewer
##     harmonics higher up so they do not alias), or a multi-cycle detuned "chorus" loop;
##   - plucked families are Karplus-Strong one-shots that end in a two-period loop;
##   - drums are one-shots built from swept sines, filtered noise and square-wave "metal".
## Every sample is generated the first time a note needs it and kept in a static cache.

## Rate of every generated sample.
const RATE := 22050
## Single-cycle table length: one cycle at RATE is 86.13 Hz (about MIDI key 40.77).
const TABLE := 256
## Cycles in a chorus loop: the detuned voices play CHORUS +- 1 cycles (about +-8.6 cents).
const CHORUS := 200
## Highest partial frequency a table may contain at the top of its key range.
const PARTIAL_LIMIT := 10000.0
## Top keys of the wave-table zones.
const ZONE_TOPS := [59, 71, 83, 95, 127]
## Root keys of the plucked zones (each zone covers the keys nearest to its root).
const PLUCK_ROOTS := [36, 48, 60, 72, 84]

## The 16 GM families. kind: "table" (looped single cycle), "chorus" (looped detuned cycles),
## "pluck" (Karplus-Strong), "noise" (looped noise). env: [attack, hold, decay, sustain, release].
const FAMILIES := [
	{"name": "Piano", "kind": "table", "partials": "piano", "env": [0.002, 0.0, 3.0, 0.0, 0.35], "db": 1.0},
	{"name": "Chromatic Percussion", "kind": "table", "partials": "bell", "env": [0.001, 0.0, 1.6, 0.0, 0.45], "db": 1.0},
	{"name": "Organ", "kind": "table", "partials": "organ", "env": [0.008, 0.0, 0.0, 1.0, 0.07], "db": 5.0},
	{"name": "Guitar", "kind": "pluck", "bright": 0.5, "rho": 0.998, "dark": 0, "env": [0.002, 0.0, 6.0, 0.0, 0.15], "db": 0.0},
	{"name": "Bass", "kind": "pluck", "bright": 0.5, "rho": 0.999, "dark": 2, "env": [0.002, 0.0, 5.0, 0.0, 0.1], "db": 0.0, "shift": -24},
	{"name": "Strings", "kind": "chorus", "partials": "saw", "env": [0.12, 0.0, 0.0, 1.0, 0.3], "db": 5.0},
	{"name": "Ensemble", "kind": "chorus", "partials": "soft_saw", "env": [0.25, 0.0, 0.0, 1.0, 0.45], "db": 5.0},
	{"name": "Brass", "kind": "table", "partials": "brass", "env": [0.05, 0.0, 0.25, 0.8, 0.15], "db": 4.0},
	{"name": "Reed", "kind": "table", "partials": "reed", "env": [0.03, 0.0, 0.0, 1.0, 0.1], "db": 4.0},
	{"name": "Pipe", "kind": "table", "partials": "flute", "env": [0.07, 0.0, 0.0, 1.0, 0.12], "db": 2.0},
	{"name": "Synth Lead", "kind": "table", "partials": "square", "env": [0.005, 0.0, 0.2, 0.85, 0.1], "db": 6.0},
	{"name": "Synth Pad", "kind": "chorus", "partials": "pad", "env": [0.5, 0.0, 0.0, 1.0, 1.0], "db": 5.0},
	{"name": "Synth Effects", "kind": "chorus", "partials": "odd", "env": [0.3, 0.0, 2.5, 0.4, 1.2], "db": 4.0},
	{"name": "Ethnic", "kind": "pluck", "bright": 0.3, "rho": 0.996, "dark": 0, "env": [0.002, 0.0, 4.0, 0.0, 0.2], "db": 1.0},
	{"name": "Percussive", "kind": "table", "partials": "mallet", "env": [0.001, 0.0, 0.45, 0.0, 0.2], "db": 0.0},
	{"name": "Sound Effects", "kind": "noise", "env": [0.08, 0.0, 0.0, 1.0, 0.4], "db": 6.0},
]

## Drum kit: key -> [sample, played frequency or 0 (the sample's own pitch), pan, exclusive class].
const DRUMS := {
	27: ["hand", 900.0, 0.0, 0], 28: ["snare", 260.0, 0.0, 0], 29: ["guiro", 0.0, 0.2, 0],
	30: ["guiro", 0.0, 0.2, 0], 31: ["wood", 1600.0, 0.0, 0], 32: ["rim", 0.0, 0.0, 0],
	33: ["wood", 2000.0, 0.0, 0], 34: ["bell", 1100.0, 0.0, 0],
	35: ["kick", 45.0, 0.0, 0], 36: ["kick", 0.0, 0.0, 0], 37: ["rim", 0.0, 0.0, 0],
	38: ["snare", 0.0, 0.0, 0], 39: ["clap", 0.0, -0.1, 0], 40: ["snare", 210.0, 0.0, 0],
	41: ["tom", 70.0, -0.4, 0], 42: ["hat_closed", 0.0, 0.3, 1], 43: ["tom", 82.0, -0.25, 0],
	44: ["hat_pedal", 0.0, 0.3, 1], 45: ["tom", 98.0, -0.1, 0], 46: ["hat_open", 0.0, 0.3, 1],
	47: ["tom", 110.0, 0.05, 0], 48: ["tom", 131.0, 0.2, 0], 49: ["crash", 0.0, -0.3, 0],
	50: ["tom", 147.0, 0.35, 0], 51: ["ride", 0.0, 0.35, 0], 52: ["china", 0.0, 0.4, 0],
	53: ["ride_bell", 0.0, 0.35, 0], 54: ["tambourine", 0.0, -0.2, 0], 55: ["splash", 0.0, -0.4, 0],
	56: ["cowbell", 0.0, 0.25, 0], 57: ["crash", 0.0, 0.4, 0], 58: ["vibraslap", 0.0, -0.3, 0],
	59: ["ride", 0.0, 0.35, 0], 60: ["hand", 420.0, 0.3, 0], 61: ["hand", 330.0, 0.3, 0],
	62: ["hand", 300.0, -0.3, 0], 63: ["hand", 270.0, -0.3, 0], 64: ["hand", 200.0, -0.3, 0],
	65: ["hand", 520.0, 0.1, 0], 66: ["hand", 400.0, 0.1, 0], 67: ["bell", 900.0, 0.4, 0],
	68: ["bell", 640.0, 0.4, 0], 69: ["shaker", 0.0, -0.4, 0], 70: ["shaker", 0.0, 0.4, 0],
	71: ["whistle", 0.0, 0.5, 2], 72: ["whistle_long", 0.0, 0.5, 2], 73: ["guiro", 0.0, -0.5, 3],
	74: ["guiro_long", 0.0, -0.5, 3], 75: ["wood", 2500.0, 0.3, 0], 76: ["wood", 1300.0, 0.4, 0],
	77: ["wood", 950.0, 0.4, 0], 78: ["cuica_up", 0.0, -0.4, 4], 79: ["cuica_down", 0.0, -0.4, 4],
	80: ["triangle", 0.0, 0.5, 5], 81: ["triangle_open", 0.0, 0.5, 5], 82: ["shaker", 0.0, 0.4, 0],
	83: ["tambourine", 0.0, 0.3, 0], 84: ["triangle_open", 0.0, -0.2, 0], 85: ["wood", 1800.0, 0.2, 0],
	86: ["tom", 60.0, -0.2, 0], 87: ["tom", 52.0, -0.2, 0],
}

## Natural frequency of the pitched drum samples (what "played frequency" is relative to).
const _DRUM_BASE := {"hand": 300.0, "snare": 185.0, "wood": 1000.0, "bell": 800.0, "kick": 55.0, "tom": 100.0}

# name -> PackedFloat32Array
static var _samples := {}
static var _mutex := Mutex.new()


func load_bank(_path: String) -> String:
	return ""


func bank_name() -> String:
	return "built-in instruments"


## Every preset: the 128 GM programs (named by family) and the drum kit.
func presets() -> Array:
	var out := []
	for p in 128:
		out.append({"bank": 0, "program": p, "name": FAMILIES[p / 8].name, "drums": false})
	out.append({"bank": 0, "program": 0, "name": "Drum Kit", "drums": true})
	return out


## Any bank and any kit fall back to the one sound of the family (or the one kit).
func regions_for(_bank_no: int, program: int, key: int, _velocity: int, drums: bool) -> Array:
	if key < 0 or key > 127:
		return []
	if drums:
		return _drum_region(key)
	if program < 0 or program > 127:
		return []
	var fam: Dictionary = FAMILIES[program / 8]
	var r := Region.new()
	var env: Array = fam.env
	r.attack = env[0]
	r.hold = env[1]
	r.decay = env[2]
	r.sustain = env[3]
	r.release = env[4]
	r.attenuation_db = fam.db
	r.sample_rate = RATE
	var name := "f%d" % (program / 8)
	match fam.kind:
		"table", "chorus":
			var z := 0
			while key > ZONE_TOPS[z]:
				z += 1
			var cycles := CHORUS if fam.kind == "chorus" else 1
			var id := "%s_z%d" % [name, z]
			r.samples = _sample(id, func() -> PackedFloat32Array:
				return _make_table(fam.partials, ZONE_TOPS[z], cycles))
			r.root_key = _key_of(float(RATE) / TABLE)
			r.loop_mode = 1
			r.loop_end = r.samples.size()
			# Piano and mallets ring longer in the bass.
			if fam.partials == "piano" or fam.partials == "bell":
				r.decay *= 1.6 - 0.25 * z
		"pluck":
			var shift: int = fam.get("shift", 0)
			var z := 0
			while z < PLUCK_ROOTS.size() - 1 and key + 0.0 > (PLUCK_ROOTS[z] + PLUCK_ROOTS[z + 1]) * 0.5 + shift:
				z += 1
			var root: int = PLUCK_ROOTS[z] + shift
			var p := roundi(RATE / _freq(root) - 0.5)
			var id := "%s_p%d" % [name, root]
			r.samples = _sample(id, func() -> PackedFloat32Array:
				return _make_pluck(p, 2.5, fam.bright, fam.rho, fam.dark, hash(id)))
			r.root_key = _key_of(RATE / (p + 0.5))
			r.loop_mode = 1
			r.loop_end = r.samples.size()
			r.loop_start = r.loop_end - (2 * p + 1)  # two periods of P + 0.5 frames
		"noise":
			r.samples = _sample(name, func() -> PackedFloat32Array: return _make_noise_loop())
			r.root_key = 60.0
			r.loop_mode = 1
			r.loop_end = r.samples.size()
	return [r]


func _drum_region(key: int) -> Array:
	if not DRUMS.has(key):
		return []
	var d: Array = DRUMS[key]
	var name: String = d[0]
	var r := Region.new()
	r.samples = _sample("d_" + name, func() -> PackedFloat32Array: return _make_drum(name))
	r.sample_rate = RATE
	# Drums play at their own pitch on their key; pitched ones are shifted to the listed frequency.
	r.root_key = key
	if d[1] > 0.0:
		r.root_key = key - 12.0 * log(d[1] / _DRUM_BASE[name]) / log(2.0)
	r.pan = d[2]
	r.exclusive_class = d[3]
	r.attack = 0.0
	r.decay = 0.0
	r.sustain = 1.0
	# A drum hit rings out after a short note-off (the sample itself decays).
	r.release = r.samples.size() / float(RATE)
	r.attenuation_db = 2.0
	return [r]


static func _sample(id: String, make: Callable) -> PackedFloat32Array:
	_mutex.lock()
	var s: PackedFloat32Array = _samples.get(id, PackedFloat32Array())
	if s.is_empty():
		s = make.call()
		_samples[id] = s
	_mutex.unlock()
	return s


static func _freq(key: float) -> float:
	return 440.0 * pow(2.0, (key - 69.0) / 12.0)


static func _key_of(freq: float) -> float:
	return 69.0 + 12.0 * log(freq / 440.0) / log(2.0)


# --- melodic waves -------------------------------------------------------------------------

## Amplitude of partial n (1 = fundamental) for a recipe.
static func _partial(recipe: String, n: int) -> float:
	match recipe:
		"piano":
			return pow(n, -1.6) * (1.0 if n % 2 == 1 else 0.8) * (0.4 if n == 7 else 1.0)
		"bell":
			return {1: 1.0, 4: 0.35, 10: 0.08}.get(n, 0.0)
		"organ":
			return {1: 1.0, 2: 0.8, 3: 0.6, 4: 0.5, 6: 0.35, 8: 0.3, 10: 0.15, 12: 0.1}.get(n, 0.0)
		"saw":
			return 1.0 / n
		"soft_saw":
			return pow(n, -1.4)
		"pad":
			return pow(n, -1.7)
		"brass":
			return pow(n, -0.9) if n <= 12 else pow(n, -0.9) * pow(0.75, n - 12)
		"reed":
			return 1.0 / n if n % 2 == 1 else 0.3 / n
		"flute":
			return {1: 1.0, 2: 0.12, 3: 0.18, 4: 0.03, 5: 0.02}.get(n, 0.0)
		"square", "odd":
			return 1.0 / n if n % 2 == 1 else 0.0
		"mallet":
			return {1: 1.0, 2: 0.5, 3: 0.25, 5: 0.1}.get(n, 0.0)
	return 1.0 if n == 1 else 0.0


## A looped wave: `cycles` == 1 is one cycle of TABLE frames; more is `cycles` cycles of the base
## voice mixed with voices of cycles - 1 and cycles + 1 (so all three loop exactly).
static func _make_table(recipe: String, top_key: int, cycles: int) -> PackedFloat32Array:
	var base := float(RATE) / TABLE
	var count := clampi(int(PARTIAL_LIMIT / _freq(top_key)), 1, TABLE / 2 - 1)
	var one := PackedFloat32Array()
	one.resize(TABLE)
	one.fill(0.0)
	for n in range(1, count + 1):
		var a := _partial(recipe, n)
		if a == 0.0:
			continue
		var w := TAU * n / TABLE
		for i in TABLE:
			one[i] += a * sin(w * i)
	var out := one
	if cycles > 1:
		out = PackedFloat32Array()
		out.resize(TABLE * cycles)
		var steps := [1.0, (cycles + 1.0) / cycles, (cycles - 1.0) / cycles]
		var gains := [1.0, 0.7, 0.7]
		out.fill(0.0)
		for v in 3:
			var step: float = steps[v]
			var g: float = gains[v]
			var pos := v * 37.0  # different start phases
			for i in out.size():
				var j := int(pos)
				var fr := pos - j
				var a := one[j % TABLE]
				out[i] += g * (a + (one[(j + 1) % TABLE] - a) * fr)
				pos += step
				if pos >= TABLE:
					pos -= TABLE
	_normalize(out)
	return out


## Karplus-Strong: a delay line of `p` frames (pitch RATE / (p + 0.5)) excited with noise and
## averaged on each pass. `bright` weights the newer frame, `rho` is the loss per pass and `dark`
## smooths the excitation that many times.
static func _make_pluck(p: int, seconds: float, bright: float, rho: float, dark: int, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	p = maxi(p, 2)
	var line := PackedFloat32Array()
	line.resize(p)
	for i in p:
		line[i] = rng.randf_range(-1.0, 1.0)
	for k in dark:
		for i in p:
			line[i] = (line[i] + line[(i + 1) % p]) * 0.5
	var mean := 0.0
	for i in p:
		mean += line[i]
	mean /= p
	for i in p:
		line[i] -= mean
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var j := 0
	for i in n:
		var a := line[j]
		var nj := j + 1 if j + 1 < p else 0
		out[i] = a
		line[j] = rho * ((1.0 - bright) * a + bright * line[nj])
		j = nj
	_normalize(out)
	return out


static func _make_noise_loop() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var out := PackedFloat32Array()
	out.resize(RATE)
	var lp := 0.0
	for i in out.size():
		lp += 0.35 * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] = lp
	# Cross-fade the end into the start so the loop does not click.
	var fade := 512
	for i in fade:
		var t := float(i) / fade
		out[out.size() - fade + i] = out[out.size() - fade + i] * (1.0 - t) + out[i] * t
	_normalize(out)
	return out


static func _normalize(s: PackedFloat32Array, peak := 0.9) -> void:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m > 0.0:
		var g := peak / m
		for i in s.size():
			s[i] *= g


# --- drums -----------------------------------------------------------------------------------

## The six square waves of the classic analogue cymbal and hi-hat (Hz).
const _METAL := [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]


static func _make_drum(name: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	match name:
		"kick":
			return _sweep(rng, 0.45, 150.0, 55.0, 0.035, 0.22, 0.25, 0.004)
		"tom":
			return _sweep(rng, 0.7, 160.0, 100.0, 0.06, 0.28, 0.12, 0.01)
		"hand":
			return _sweep(rng, 0.3, 380.0, 300.0, 0.02, 0.09, 0.1, 0.006)
		"snare":
			var body := _sweep(rng, 0.35, 240.0, 185.0, 0.02, 0.07, 0.0, 0.0)
			var noise := _noise(rng, 0.35, 0.11, 0.25, 0.8, [], 0.0)
			return _mix([body, noise], [0.7, 1.0])
		"rim":
			var click := _tone([1700.0, 450.0], [1.0, 0.6], 0.12, 0.018)
			return _mix([click, _noise(rng, 0.12, 0.012, 0.3, 0.9, [], 0.0)], [1.0, 0.5])
		"clap":
			return _clap(rng)
		"hat_closed":
			return _noise(rng, 0.12, 0.035, 0.35, 0.95, _METAL, 0.6)
		"hat_pedal":
			return _noise(rng, 0.18, 0.06, 0.35, 0.95, _METAL, 0.6)
		"hat_open":
			return _noise(rng, 0.8, 0.32, 0.35, 0.95, _METAL, 0.6)
		"crash":
			return _noise(rng, 2.0, 0.9, 0.5, 0.85, _METAL, 0.45)
		"splash":
			return _noise(rng, 0.9, 0.35, 0.5, 0.85, _METAL, 0.45)
		"china":
			return _noise(rng, 1.6, 0.7, 0.6, 0.7, _METAL, 0.7)
		"ride":
			return _mix([_noise(rng, 1.8, 0.8, 0.5, 0.9, _METAL, 0.8), _tone([3200.0, 4700.0], [0.3, 0.2], 1.8, 0.6)], [1.0, 0.5])
		"ride_bell":
			return _mix([_tone([700.0, 1050.0, 1630.0, 2400.0], [1.0, 0.6, 0.5, 0.3], 1.2, 0.5), _noise(rng, 1.2, 0.5, 0.5, 0.9, _METAL, 0.8)], [1.0, 0.3])
		"tambourine":
			return _mix([_noise(rng, 0.35, 0.12, 0.6, 0.95, [], 0.0), _tone([6000.0, 7400.0, 8100.0], [0.5, 0.4, 0.3], 0.35, 0.12)], [1.0, 0.7])
		"cowbell":
			return _tone([540.0, 800.0, 1620.0, 2400.0], [1.0, 0.8, 0.2, 0.15], 0.4, 0.12)
		"vibraslap":
			var v := _noise(rng, 0.8, 0.4, 0.4, 0.8, [], 0.0)
			for i in v.size():
				v[i] *= 0.5 + 0.5 * absf(sin(TAU * 28.0 * i / RATE))
			return v
		"bell":
			return _tone([800.0, 2144.0, 3300.0], [1.0, 0.5, 0.15], 0.45, 0.18)
		"shaker":
			return _noise(rng, 0.12, 0.04, 0.4, 0.97, [], 0.0)
		"whistle":
			return _whistle(0.25)
		"whistle_long":
			return _whistle(0.7)
		"guiro":
			return _guiro(rng, 0.18)
		"guiro_long":
			return _guiro(rng, 0.5)
		"wood":
			return _mix([_tone([1000.0, 2750.0], [1.0, 0.2], 0.12, 0.035), _noise(rng, 0.12, 0.006, 0.3, 0.6, [], 0.0)], [1.0, 0.3])
		"cuica_up":
			return _glide(320.0, 640.0, 0.28)
		"cuica_down":
			return _glide(600.0, 300.0, 0.32)
		"triangle":
			return _tone([4000.0, 4920.0, 7950.0], [1.0, 0.4, 0.3], 0.25, 0.07)
		"triangle_open":
			return _tone([4000.0, 4920.0, 7950.0], [1.0, 0.4, 0.3], 1.8, 0.7)
	return PackedFloat32Array([0.0, 0.0])


## A sine whose pitch falls from f0 to f1 (time constant `sweep`) and decays with `decay`, plus a
## noise burst (`noise` level, `noise_decay`) for the stick.
static func _sweep(rng: RandomNumberGenerator, seconds: float, f0: float, f1: float, sweep: float, decay: float, noise: float, noise_decay: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f1 + (f0 - f1) * exp(-t / sweep)
		phase += TAU * f / RATE
		var s := sin(phase) * exp(-t / decay)
		if noise > 0.0:
			s += rng.randf_range(-1.0, 1.0) * noise * exp(-t / noise_decay)
		out[i] = s
	_fade_tail(out)
	_normalize(out)
	return out


## Noise (one-pole high-passed by `hp` 0..1 and low-passed with coefficient `lp`), optionally with
## square-wave partials `metal` at level `metal_level`, decaying with `decay`.
static func _noise(rng: RandomNumberGenerator, seconds: float, decay: float, hp: float, lp: float, metal: Array, metal_level: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var smooth := 0.0
	var phases := PackedFloat32Array()
	phases.resize(metal.size())
	phases.fill(0.0)
	for i in n:
		var x := rng.randf_range(-1.0, 1.0)
		if metal_level > 0.0:
			var m := 0.0
			for k in metal.size():
				phases[k] = fmod(phases[k] + metal[k] * 3.17 / RATE, 1.0)
				m += 1.0 if phases[k] < 0.5 else -1.0
			x = x * (1.0 - metal_level) + m / metal.size() * metal_level * 2.0
		low += hp * (x - low)
		var high := x - low
		smooth += lp * (high - smooth)
		out[i] = smooth * exp(-float(i) / RATE / decay)
	_fade_tail(out)
	_normalize(out)
	return out


## Decaying sines at `freqs` with `amps`.
static func _tone(freqs: Array, amps: Array, seconds: float, decay: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in freqs.size():
			s += amps[k] * sin(TAU * freqs[k] * t) * exp(-t / (decay / (1.0 + k * 0.5)))
		out[i] = s
	_fade_tail(out)
	_normalize(out)
	return out


static func _clap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.3 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / RATE
		# Three quick claps 11 ms apart, then the room tail.
		var env := exp(-fmod(t, 0.011) / 0.003) if t < 0.033 else exp(-(t - 0.033) / 0.07)
		var x := rng.randf_range(-1.0, 1.0)
		low += 0.3 * (x - low)
		band += 0.6 * ((x - low) - band)
		out[i] = band * env
	_fade_tail(out)
	_normalize(out)
	return out


static func _whistle(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (2300.0 + 40.0 * sin(TAU * 7.0 * t)) / RATE
		out[i] = sin(phase) * minf(1.0, t / 0.01) * minf(1.0, (seconds - t) / 0.05)
	_normalize(out, 0.6)
	return out


static func _guiro(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		low += 0.4 * (x - low)
		out[i] = (x - low) * exp(-fmod(t, 0.022) / 0.006) * minf(1.0, (seconds - t) / 0.03)
	_normalize(out)
	return out


static func _glide(f0: float, f1: float, seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / seconds) / RATE
		out[i] = (sin(phase) + 0.3 * sin(2.0 * phase)) * minf(1.0, t / 0.01) * exp(-t / (seconds * 0.6))
	_fade_tail(out)
	_normalize(out)
	return out


static func _mix(parts: Array, gains: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	for k in parts.size():
		var p: PackedFloat32Array = parts[k]
		var g: float = gains[k]
		for i in p.size():
			out[i] += p[i] * g
	_normalize(out)
	return out


## Ramps the last 5 ms to zero so a one-shot never ends on a click.
static func _fade_tail(s: PackedFloat32Array) -> void:
	var fade := mini(s.size(), int(0.005 * RATE))
	for i in fade:
		s[s.size() - 1 - i] *= float(i) / fade
