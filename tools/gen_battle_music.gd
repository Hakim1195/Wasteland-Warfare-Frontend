extends SceneTree
##
## Générateur de la MUSIQUE DE COMBAT (arène) — tension militaire / post-apo.
## Plus SOMBRE et plus MARTIAL que le menu : tambours de guerre (toms graves), pédale-sub de dread,
## nappe de cordes dissonante (saw filtré), stabs de power-chord heavy rock épars, et risers de
## bruit aux jointures de phrase. Ré mineur (cohérent avec le menu §8.65) mais cadence i–VI–iv–V
## (l'accord V = LA majeur crée la tension, non résolue, qui retombe sur i → moteur d'angoisse).
##
## Lancé SANS --path (aucun autoload), méthode média §CLAUDE :
##   Godot…_console.exe --headless --script tools/gen_battle_music.gd
## Écrit `assets/audio/music/battle_ambient.wav` (stéréo, BOUCLE sans jointure) → l'AudioManager le
## charge en override et le joue dans l'arène via start_battle_ambient(). AUCUN code à toucher.

const MIX := 44100.0
const TAU := 6.2831853
const OUT := "C:/Users/Hamdi/Desktop/pinciopancio/Wasteland-Warfare-Frontend/assets/audio/music/battle_ambient.wav"

const TEMPO := 100.0
const BARS := 16

var _spb := 60.0 / TEMPO          # secondes par temps (noire)
var _loop_frames := 0
var L := PackedFloat32Array()
var R := PackedFloat32Array()

# Cadence de tension en RÉ mineur : i – VI – iv – V (Dm – Bb – Gm – A), répétée 4×.
const ROOTS := [38, 34, 31, 33]   # D2, Bb1, G1, A1
# Triade par accord (cordes graves dissonantes).
const PAD := [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]]   # Dm, Bb, Gm, A(maj)


func _init() -> void:
	var beat := _spb
	var bar := beat * 4.0
	var loop_len := BARS * bar
	var tail := 1.1                     # queue (réverbe/sub) repliée sur la tête → boucle sans couture
	var total := int((loop_len + tail) * MIX)
	_loop_frames = int(loop_len * MIX)
	L.resize(total); R.resize(total)

	for b in BARS:
		var t0 := b * bar
		var ci: int = b % 4
		var dyn := _dynamics(b)          # montée d'intensité par phrase
		_render_bar(b, ci, t0, beat, dyn)

	# Boom de phrase (bar 1 & 9) + riser vers chaque reprise de phrase (bar 8 & 16).
	_boom(0.0, 1.0)
	_boom(8 * bar, 0.95)
	_riser((8 * bar) - beat, beat, 0.5)
	_riser((16 * bar) - beat, beat, 0.55)

	# Repli de la queue (ce qui dépasse le point de boucle) sur le début → boucle sans jointure.
	var extra := total - _loop_frames
	for i in extra:
		L[i] += L[_loop_frames + i]
		R[i] += R[_loop_frames + i]
	L.resize(_loop_frames); R.resize(_loop_frames)

	_write_stereo_loop()
	print("BATTLE MUSIC DONE frames=", _loop_frames, " dur=", "%.1f" % loop_len, "s")
	quit()


# Phrase 1 (bars 1-8) plus aérée/menaçante ; phrase 2 (bars 9-16) plus lourde (guitare + double-toms).
func _dynamics(b: int) -> float:
	return lerpf(0.66, 1.0, float(b) / float(BARS - 1))


func _render_bar(b: int, ci: int, t0: float, beat: float, dyn: float) -> void:
	var root: int = ROOTS[ci]
	var heavy := b >= 8

	# --- Pédale-sub de dread (toute la mesure) ---
	_sub(t0, beat * 4.0, _nf(root - 12), 0.20 * dyn)

	# --- Nappe de cordes dissonante (swell lent, sombre) ---
	for m in PAD[ci]:
		_strings(t0, beat * 4.0, _nf(m), 0.075 * dyn)

	# --- Tambours de guerre : toms graves martelés (motif militaire) ---
	# Quarts pulsés : 1 . . . | 2 . . . avec doublettes de croches sur les temps faibles.
	var tom_root := _nf(root - 5)                 # tom accordé sous la racine
	_tom(t0 + 0 * beat, tom_root, 0.30 * dyn + 0.06)
	_tom(t0 + 1 * beat + beat * 0.5, tom_root * 0.92, 0.16 * dyn)
	_tom(t0 + 2 * beat, tom_root, 0.26 * dyn + 0.05)
	_tom(t0 + 3 * beat, tom_root * 1.06, 0.16 * dyn)
	_tom(t0 + 3 * beat + beat * 0.5, tom_root * 0.92, 0.18 * dyn)
	if heavy:
		# Doublette de toms supplémentaire (montée d'intensité phrase 2).
		_tom(t0 + 1 * beat, tom_root * 1.06, 0.18 * dyn)
		_tom(t0 + 3 * beat + beat * 0.75, tom_root, 0.14 * dyn)

	# --- Kick martial sur 1 & 3 (poids), charley off-beat dès la 2e moitié ---
	_kick(t0 + 0 * beat, 0.24 * dyn + 0.05)
	_kick(t0 + 2 * beat, 0.22 * dyn + 0.05)
	if b >= 4:
		for e in 4:
			_hat(t0 + e * beat + beat * 0.5, 0.045 * dyn)

	# --- Ostinato grave menaçant (croches, racine + quinte, saw filtré) ---
	for e in 8:
		var note := _nf(root + (0 if (e % 4 != 2) else 7))   # racine, avec une quinte au 3e pas
		var ts := t0 + e * (beat * 0.5)
		var g := 0.10 * dyn * (1.0 if (e % 2 == 0) else 0.72)
		_ostinato(ts, beat * 0.46, note, g, -0.35 if (e % 2 == 0) else 0.35)

	# --- Stabs de power-chord heavy rock (épars : temps 1, + temps 3 en phrase 2) ---
	_guitar_stab(t0, beat * 0.9, root, dyn)
	if heavy:
		_guitar_stab(t0 + 2 * beat, beat * 0.7, root, dyn * 0.85)


# --- Instruments (synthés) ----------------------------------------------------

# Sub grave / pédale de dread (sinus + sous-harmonique douce, très lent).
func _sub(start: float, dur: float, freq: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var env: float = minf(1.0, t * 5.0) * minf(1.0, (dur - t) * 5.0)
		s[i] = (sin(TAU * freq * t) + 0.22 * sin(TAU * freq * 0.5 * t)) * env
	_mix(start, s, gain, gain)


# Cordes graves dissonantes : saw additif → passe-bas → swell très lent. Wide (léger décalage L/R).
func _strings(start: float, dur: float, freq: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var p0 := 0.0; var p1 := 0.0
	var det := pow(2.0, 7.0 / 1200.0)              # 7 cents de désaccord (ensemble de cordes)
	for i in n:
		var t := float(i) / MIX
		var env := minf(1.0, t * 1.6) * minf(1.0, (dur - t) * 2.2)   # attaque/relâche lentes
		var trem := 0.90 + 0.10 * sin(TAU * 3.2 * t)
		p0 += TAU * freq / MIX
		p1 += TAU * freq * det / MIX
		s[i] = (_saw(p0) * 0.5 + _saw(p1) * 0.5) * env * trem
	s = _lowpass(s, 1900.0)
	_mix(start, s, gain * 1.0, gain * 0.9)


# Tom de guerre : sinus à pitch descendant + transitoire de bruit (peau), corps mat.
func _tom(start: float, freq: float, gain: float) -> void:
	var dur := 0.42
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 17
	for i in n:
		var t := float(i) / MIX
		var f := lerpf(freq * 1.7, freq, clampf(t / 0.06, 0.0, 1.0))   # « pock » de pitch
		var env: float = exp(-t * 7.0)
		var skin := rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.25  # frappe de peau
		s[i] = (sin(TAU * f * t) + skin) * env
	s = _lowpass(s, 2200.0)
	_mix(start, s, gain, gain)


# Kick : descente de pitch sinus + clic d'attaque.
func _kick(start: float, gain: float) -> void:
	var dur := 0.30
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := lerpf(130.0, 42.0, clampf(t / 0.08, 0.0, 1.0))
		var env: float = exp(-t * 8.5)
		var click := exp(-t * 240.0) * 0.5
		s[i] = (sin(TAU * f * t) + click) * env
	_mix(start, s, gain, gain)


# Charley fermé : bruit très court et brillant (off-beat).
func _hat(start: float, gain: float) -> void:
	var dur := 0.04
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 808
	for i in n:
		var t := float(i) / MIX
		s[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 90.0)
	_mix(start, s, gain * 0.5, gain * 0.5)


# Ostinato grave : saw filtré, attaque vive, court (chug menaçant), pan.
func _ostinato(start: float, dur: float, freq: float, gain: float, pan: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / MIX
		var env: float = minf(1.0, t * 220.0) * exp(-t * 5.5)
		ph += TAU * freq / MIX
		s[i] = (_saw(ph) * 0.7 + sin(ph) * 0.3) * env
	s = _lowpass(s, 1500.0)
	var gl: float = gain * sqrt(0.5 * (1.0 - pan))
	var gr: float = gain * sqrt(0.5 * (1.0 + pan))
	_mix(start, s, gl, gr)


# Stab de power-chord distordu (racine + quinte + octave) → tanh (disto) → passe-bas. Double-track L/R.
func _guitar_stab(start: float, dur: float, root_midi: int, dyn: float) -> void:
	for side in [-1.0, 1.0]:
		var cents: float = 7.0 * side
		var det := pow(2.0, cents / 1200.0)
		var f0 := _nf(root_midi) * det
		var f1 := _nf(root_midi + 7) * det
		var f2 := _nf(root_midi + 12) * det
		var n := int(dur * MIX)
		var s := PackedFloat32Array(); s.resize(n)
		var p0 := 0.0; var p1 := 0.0; var p2 := 0.0
		for i in n:
			var t := float(i) / MIX
			var env: float = minf(1.0, t * 350.0) * exp(-t * 4.5)
			p0 += TAU * f0 / MIX; p1 += TAU * f1 / MIX; p2 += TAU * f2 / MIX
			var raw := 0.6 * _saw(p0) + 0.5 * _saw(p1) + 0.35 * _saw(p2)
			s[i] = tanh(raw * 3.4) * env
		s = _lowpass(s, 3000.0)
		var g := 0.15 * dyn
		var pan: float = 0.7 * side
		var gl: float = g * sqrt(0.5 * (1.0 - pan))
		var gr: float = g * sqrt(0.5 * (1.0 + pan))
		_mix(start, s, gl, gr)


# Boom cinématique sub (impact de phrase).
func _boom(start: float, gain: float) -> void:
	var dur := 1.5
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := lerpf(72.0, 36.0, clampf(t / 0.3, 0.0, 1.0))
		s[i] = sin(TAU * f * t) * exp(-t * 2.0)
	_mix(start, s, gain, gain)


# Riser de tension : bruit filtré dont le filtre s'ouvre (crescendo) vers la jointure de phrase.
func _riser(start: float, dur: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 303
	var y := 0.0
	for i in n:
		var t := float(i) / MIX
		var u := t / dur
		var cutoff := lerpf(400.0, 6000.0, u * u)      # ouverture du filtre = montée
		var dt := 1.0 / MIX
		var rc := 1.0 / (TAU * cutoff)
		var alpha := dt / (rc + dt)
		y += alpha * (rng.randf_range(-1.0, 1.0) - y)
		s[i] = y * pow(u, 1.5)                          # enveloppe crescendo
	_mix(start, s, gain, gain)


# --- Utilitaires --------------------------------------------------------------

func _nf(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _saw(phase: float) -> float:
	return 2.0 * (fposmod(phase, TAU) / TAU) - 1.0


func _mix(start: float, s: PackedFloat32Array, gl: float, gr: float) -> void:
	var off := int(start * MIX)
	var total := L.size()
	for i in s.size():
		var idx := off + i
		if idx >= 0 and idx < total:
			L[idx] += s[i] * gl
			R[idx] += s[i] * gr


func _lowpass(s: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var dt := 1.0 / MIX
	var rc := 1.0 / (TAU * cutoff)
	var alpha := dt / (rc + dt)
	var out := PackedFloat32Array(); out.resize(s.size())
	var y := 0.0
	for i in s.size():
		y += alpha * (s[i] - y)
		out[i] = y
	return out


func _write_stereo_loop() -> void:
	var n := L.size()
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, maxf(absf(L[i]), absf(R[i])))
	var k := (0.95 / peak) * 0.84          # normalise puis garde du headroom
	var bytes := PackedByteArray(); bytes.resize(n * 4)
	for i in n:
		bytes.encode_s16(i * 4, int(clampf(L[i] * k, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(R[i] * k, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX)
	wav.stereo = true
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	var err := wav.save_to_wav(OUT)
	print("  saved ", OUT.get_file(), " err=", err)
