extends SceneTree
##
## Générateur de la MUSIQUE de menu — « Interstellar » (orgue Zimmer + ostinato pulsé) avec accents
## HEAVY ROCK (power chords distordus, backbeat), teinte dark/post-apo (mineur, sub cinématique).
## Lancé SANS --path (aucun autoload), méthode média §CLAUDE :
##   Godot…_console.exe --headless --script tools/gen_menu_music.gd
## Écrit `assets/audio/music/menu_ambient.wav` (stéréo, BOUCLE sans jointure) → l'AudioManager le
## charge en override (§8.64) et le joue dans le menu via start_menu_ambient(). AUCUN code à toucher.
##
## ⚠️ ALTERNATIVE ARCHIVÉE (§8.68) : depuis le choix utilisateur, la piste de menu ACTIVE est le trap
## avec REFRAIN VOCAL synthétique de `tools/gen_menu_vocal_trap.gd`. Les TROIS outils (celui-ci,
## `gen_menu_trap.gd` instrumental §8.67, et le vocal = ACTIF) visent LE MÊME fichier
## `menu_ambient.wav` → n'en lancer QU'UN (règle anti-footgun §8.66 : 1 asset = 1 outil actif).
## Relancer CE script REMET le thème Interstellar. Conservé tel quel pour pouvoir y revenir.

const MIX := 44100.0
const TAU := 6.2831853
const OUT := "C:/Users/Hamdi/Desktop/pinciopancio/Wasteland-Warfare-Frontend/assets/audio/music/menu_ambient.wav"

const TEMPO := 88.0
const BARS := 16

var _spb := 60.0 / TEMPO          # secondes par temps (noire)
var _loop_frames := 0
var L := PackedFloat32Array()
var R := PackedFloat32Array()

# Progression épique en RÉ mineur : i - VI - III - VII (Dm - Bb - F - C), répétée 4×.
# Racines MIDI (basse/guitare).
const ROOTS := [38, 34, 41, 36]   # D2, Bb1, F2, C2
# Triades de pad (orgue) par accord.
const PAD := [[50, 53, 57], [46, 50, 53], [53, 57, 60], [48, 52, 55]]
# Notes d'arpège (orgue brillant) par accord.
const ARP := [[62, 65, 69, 74], [58, 62, 65, 70], [65, 69, 72, 77], [60, 64, 67, 72]]
# Motif d'arpège sur 16 doubles-croches (montée/descente fluide).
const ARP_STEP := [0, 1, 2, 3, 2, 3, 2, 1, 0, 1, 2, 3, 3, 2, 1, 0]


func _init() -> void:
	var beat := _spb
	var bar := beat * 4.0
	var loop_len := BARS * bar
	var tail := 0.9                     # queue repliée sur la tête (boucle sans jointure)
	var total := int((loop_len + tail) * MIX)
	_loop_frames = int(loop_len * MIX)
	L.resize(total); R.resize(total)

	for b in BARS:
		var t0 := b * bar
		var ci: int = b % 4
		var dyn := _dynamics(b)          # enveloppe de montée en intensité
		_render_bar(b, ci, t0, beat, dyn)

	# Boom cinématique sur les départs de phrase (bar 1 et bar 9).
	_boom(0.0, 0.9)
	_boom(8 * bar, 0.8)

	# Repli de la queue (réverbe/sustain qui dépasse) sur le début → boucle sans couture.
	var extra := total - _loop_frames
	for i in extra:
		L[i] += L[_loop_frames + i]
		R[i] += R[_loop_frames + i]
	L.resize(_loop_frames); R.resize(_loop_frames)

	_write_stereo_loop()
	print("MENU MUSIC DONE frames=", _loop_frames, " dur=", "%.1f" % (loop_len), "s")
	quit()


# Intensité par mesure : 1ʳᵉ moitié plus aérée, 2ᵉ moitié plus pleine (la guitare entre bar 9).
func _dynamics(b: int) -> float:
	return lerpf(0.72, 1.0, float(b) / float(BARS - 1))


func _render_bar(b: int, ci: int, t0: float, beat: float, dyn: float) -> void:
	var sixteenth := beat * 0.25
	var root: int = ROOTS[ci]

	# --- Pad orgue (toute la mesure, swell lent) ---
	for m in PAD[ci]:
		_organ_pad(t0, beat * 4.0, _nf(m), 0.10 * dyn)

	# --- Sub / pédale grave (poids cinématique) ---
	_sub(t0, beat * 4.0, _nf(root - 12), 0.16 * dyn)

	# --- Arpège orgue brillant (16 doubles-croches, ping-pong stéréo) ---
	for s in 16:
		var note := _nf(ARP[ci][ARP_STEP[s]])
		var ts := t0 + s * sixteenth
		var pan := -0.55 if (s % 2 == 0) else 0.55
		var g := 0.085 * dyn * (1.0 if (s % 4 == 0) else 0.78)   # accent sur les temps
		_organ_arp(ts, sixteenth * 0.95, note, g, pan)

	# --- Basse (noires, racine) ---
	for q in 4:
		_bass(t0 + q * beat, beat * 0.92, _nf(root), 0.22 * dyn)

	# --- Batterie : kick sur 1 & 3, caisse claire (backbeat) sur 2 & 4 ---
	_kick(t0 + 0 * beat, 0.20 * dyn + 0.05)
	_kick(t0 + 2 * beat, 0.20 * dyn + 0.05)
	_snare(t0 + 1 * beat, 0.18 * dyn)
	_snare(t0 + 3 * beat, 0.18 * dyn)
	# Charley/clic de croches (texture rythmique) dès la 2ᵉ moitié.
	if b >= 4:
		for e in 8:
			_hat(t0 + e * (beat * 0.5), 0.05 * dyn)

	# --- Guitare HEAVY ROCK : power chords en croches palm-mute, 2ᵉ moitié (bars 9-16) ---
	if b >= 8:
		var accent := 1.0 if b >= 12 else 0.82
		for e in 8:
			var te := t0 + e * (beat * 0.5)
			var dur := beat * 0.46
			var g := 0.16 * accent * (1.0 if (e % 2 == 0) else 0.7)
			# Double-tracking gauche/droite (léger désaccord) = largeur rock.
			_guitar_power(te, dur, root, -6.0, g, -0.7)
			_guitar_power(te, dur, root, 6.0, g, 0.7)


# --- Instruments (synthés) ----------------------------------------------------

# Orgue de pad : drawbars (sinus 1/2/3/4 + quinte) + swell lent + léger chorus. Wide.
func _organ_pad(start: float, dur: float, freq: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var env := minf(1.0, t * 3.0) * minf(1.0, (dur - t) * 4.0)   # attaque/relâche doux
		var trem := 0.92 + 0.08 * sin(TAU * 4.5 * t)
		var v := sin(TAU * freq * t)
		v += 0.5 * sin(TAU * freq * 2.0 * t)
		v += 0.33 * sin(TAU * freq * 1.5 * t)     # quinte (couleur orgue)
		v += 0.22 * sin(TAU * freq * 4.0 * t)
		var chorus := sin(TAU * (freq * 1.004) * t) * 0.4   # battement = chorus
		s[i] = (v + chorus) * env * trem
	s = _lowpass(s, 2400.0)
	_mix(start, s, gain * 0.92, gain * 1.0)        # léger décalage L/R = largeur


# Sub grave / pédale (sinus + harmonique douce).
func _sub(start: float, dur: float, freq: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var env := minf(1.0, t * 6.0) * minf(1.0, (dur - t) * 6.0)
		s[i] = (sin(TAU * freq * t) + 0.18 * sin(TAU * freq * 2.0 * t)) * env
	_mix(start, s, gain, gain)


# Arpège orgue brillant (attaque vive, décroissance, pan).
func _organ_arp(start: float, dur: float, freq: float, gain: float, pan: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var env: float = minf(1.0, t * 300.0) * exp(-t * 6.0)
		var v := sin(TAU * freq * t) + 0.5 * sin(TAU * freq * 2.0 * t) + 0.25 * sin(TAU * freq * 3.0 * t)
		s[i] = v * env
	s = _lowpass(s, 7000.0)
	var gl: float = gain * sqrt(0.5 * (1.0 - pan))
	var gr: float = gain * sqrt(0.5 * (1.0 + pan))
	_mix(start, s, gl, gr)


# Basse : triangle/sinus + un peu de saw filtré (corps).
func _bass(start: float, dur: float, freq: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / MIX
		var env: float = minf(1.0, t * 120.0) * exp(-t * 3.5)
		ph += TAU * freq / MIX
		var saw := 2.0 * (fposmod(ph, TAU) / TAU) - 1.0
		s[i] = (sin(ph) * 0.8 + saw * 0.2) * env
	s = _lowpass(s, 1600.0)
	_mix(start, s, gain, gain)


# Kick : descente de pitch sinus + clic d'attaque.
func _kick(start: float, gain: float) -> void:
	var dur := 0.28
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := lerpf(125.0, 45.0, clampf(t / 0.08, 0.0, 1.0))
		var env: float = exp(-t * 9.0)
		var click := exp(-t * 220.0) * 0.5
		s[i] = (sin(TAU * f * t) + click) * env
	_mix(start, s, gain, gain)


# Caisse claire : burst de bruit filtré (passe-haut grossier) + corps tonal.
func _snare(start: float, gain: float) -> void:
	var dur := 0.20
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX
		var env: float = exp(-t * 22.0)
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - prev; prev = white          # passe-haut 1er ordre simple
		var body := sin(TAU * 190.0 * t) * 0.3
		s[i] = (hp * 0.8 + body) * env
	_mix(start, s, gain, gain)


# Charley fermé : bruit très court et brillant.
func _hat(start: float, gain: float) -> void:
	var dur := 0.045
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	for i in n:
		var t := float(i) / MIX
		s[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 80.0)
	_mix(start, s, gain * 0.5, gain * 0.5)


# Power chord guitare distordue : saw (racine + quinte + octave) → tanh (disto) → passe-bas (HP de
# baffle), enveloppe palm-mute (attaque vive, chug court). `cents` = désaccord pour le double-tracking.
func _guitar_power(start: float, dur: float, root_midi: int, cents: float, gain: float, pan: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var det := pow(2.0, cents / 1200.0)
	var f0 := _nf(root_midi) * det
	var f1 := _nf(root_midi + 7) * det
	var f2 := _nf(root_midi + 12) * det
	var p0 := 0.0; var p1 := 0.0; var p2 := 0.0
	for i in n:
		var t := float(i) / MIX
		var env: float = minf(1.0, t * 400.0) * exp(-t * 7.0)    # chug palm-mute
		p0 += TAU * f0 / MIX; p1 += TAU * f1 / MIX; p2 += TAU * f2 / MIX
		var raw := 0.6 * _saw(p0) + 0.5 * _saw(p1) + 0.35 * _saw(p2)
		var dist := tanh(raw * 3.2)                              # saturation = distorsion
		s[i] = dist * env
	s = _lowpass(s, 3200.0)
	var gl: float = gain * sqrt(0.5 * (1.0 - pan))
	var gr: float = gain * sqrt(0.5 * (1.0 + pan))
	_mix(start, s, gl, gr)


# Boom cinématique sub (impact de phrase).
func _boom(start: float, gain: float) -> void:
	var dur := 1.4
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := lerpf(70.0, 38.0, clampf(t / 0.3, 0.0, 1.0))
		s[i] = sin(TAU * f * t) * exp(-t * 2.2)
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
	var k := (0.95 / peak) * 0.86          # normalise puis garde du headroom
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
