extends SceneTree
##
## Générateur de la MUSIQUE DE MENU — brano ORIGINAL en style « dark melodic trap » (vibe Travis
## Scott / Tyga / Drake : 808 glissés saturés, hi-hats roulés, clap en demi-temps, mélodie de cloche
## menaçante en mineur, pad sombre). ⚠️ **Œuvre 100 % originale** : on s'inspire du GENRE/de la
## VIBE (non protégeables), JAMAIS de la mélodie/des paroles/de l'enregistrement d'un titre existant.
## Reste cohérent avec le thème dark/post-apo (ré mineur, sub cinématique).
##
## ⚠️ ALTERNATIVE ARCHIVÉE (§8.68) : ce générateur INSTRUMENTAL n'est PLUS l'actif. Le menu utilise
## désormais `gen_menu_vocal_trap.gd` (trap avec REFRAIN VOCAL synthétique, choix utilisateur). Les
## TROIS outils (`gen_menu_vocal_trap.gd` = ACTIF, celui-ci + `gen_menu_music.gd` = archivés) visent
## le MÊME fichier `menu_ambient.wav` → n'en lancer QU'UN (règle anti-footgun §8.66). Relancer
## CE script ÉCRASE le refrain vocal par l'instrumental dark trap (§8.67).
##
## Lancé SANS --path (aucun autoload), méthode média §CLAUDE :
##   Godot…_console.exe --headless --script tools/gen_menu_trap.gd
## L'AudioManager le joue tel quel via start_menu_ambient() (override, AUCUN code à toucher).

const MIX := 44100.0
const TAU := 6.2831853
const OUT := "C:/Users/Hamdi/Desktop/pinciopancio/Wasteland-Warfare-Frontend/assets/audio/music/menu_ambient.wav"

const TEMPO := 140.0               # trap @ 140 BPM, ressenti DEMI-TEMPS (clap sur le temps 3)
const BARS := 16

var _spb := 60.0 / TEMPO           # secondes par temps (noire)
var _loop_frames := 0
var L := PackedFloat32Array()
var R := PackedFloat32Array()

# Vamp sombre en RÉ mineur (harmonique) : i – i – VI – V (Dm – Dm – Bb – A), répété 4×. Le V (LA,
# sensible DO#) donne la tension « trap menaçant ». Racines MIDI pour la 808.
const ROOTS := [38, 38, 34, 33]    # D2, D2, Bb1, A1
# Pad sombre : triade par accord (voicings graves).
const PAD := [[50, 53, 57], [50, 53, 57], [46, 50, 53], [45, 49, 52]]
# Mélodie de cloche (sparse, lugubre) : [temps_dans_le_cycle_4_mesures, midi, durée_en_temps].
const MEL := [
	[0.0, 69, 0.5], [1.5, 74, 0.5], [2.5, 77, 1.0],            # mes.1 (Dm) : La4 · Ré5 · Fa5
	[4.0, 76, 1.0], [6.0, 74, 1.5],                            # mes.2 (Dm) : Mi5 · Ré5
	[8.0, 74, 0.5], [9.5, 70, 0.5], [10.5, 77, 1.0],           # mes.3 (Bb) : Ré5 · Sib4 · Fa5
	[12.0, 73, 1.0], [14.0, 76, 0.5], [15.0, 69, 1.0],         # mes.4 (A)  : Do#5 · Mi5 · La4
]


func _init() -> void:
	var beat := _spb
	var bar := beat * 4.0
	var loop_len := BARS * bar
	var tail := 1.2                 # queue (808/pad/reverb) repliée sur la tête → boucle sans couture
	var total := int((loop_len + tail) * MIX)
	_loop_frames = int(loop_len * MIX)
	L.resize(total); R.resize(total)

	for b in BARS:
		var t0 := b * bar
		var ci: int = b % 4
		_render_bar(b, ci, t0, beat)

	# Mélodie de cloche, posée sur chaque cycle de 4 mesures.
	for cyc in 4:
		var c0 := cyc * 4.0 * bar
		for ev in MEL:
			var ts: float = c0 + float(ev[0]) * beat
			var note := _nf(int(ev[1]))
			var dur: float = float(ev[2]) * beat
			var pan := -0.3 if (int(ev[1]) % 2 == 0) else 0.3
			_bell(ts, dur, note, 0.12, pan)

	# Repli de la queue (808/pad/reverb qui dépassent) sur le début → boucle sans jointure.
	var extra := total - _loop_frames
	for i in extra:
		L[i] += L[_loop_frames + i]
		R[i] += R[_loop_frames + i]
	L.resize(_loop_frames); R.resize(_loop_frames)

	_write_stereo_loop()
	print("MENU TRAP DONE frames=", _loop_frames, " dur=", "%.1f" % loop_len, "s")
	quit()


func _render_bar(b: int, ci: int, t0: float, beat: float) -> void:
	var bar := beat * 4.0
	var root: int = ROOTS[ci]
	var next_root: int = ROOTS[(b + 1) % 4]

	# --- 808 (basse-sub saturée), pièce maîtresse : tient la mesure, glisse vers l'accord suivant ---
	# Glide d'attaque (depuis 2 demi-tons sous la racine) + glide de fin vers la racine suivante.
	_eight_o_eight(t0, bar, _nf(root - 2), _nf(root), _nf(next_root), 0.95)

	# --- Pad sombre (nappe filtrée, swell lent) ---
	for m in PAD[ci]:
		_dark_pad(t0, bar, _nf(m), 0.045)

	# --- Kick (gros, sur 1 + syncope) ---
	_kick(t0 + 0 * beat, 0.95)
	_kick(t0 + 2.5 * beat, 0.7)              # syncope « and of 3 »
	if b % 4 == 3:
		_kick(t0 + 3.5 * beat, 0.6)          # fill avant la reprise de phrase

	# --- Clap / snare sur le temps 3 (backbeat demi-temps = signature trap) ---
	_clap(t0 + 2 * beat, 0.8)

	# --- Hi-hats : croches de base + rolls (doubles/triolets) en fin de mesure ---
	for e in 8:
		var ts := t0 + e * (beat * 0.5)
		var g := 0.22 * (1.0 if (e % 2 == 0) else 0.72)
		_hat(ts, beat * 0.22, g, 1.0)
	# Roll de hats : 16e sur le 4e temps, et triolets serrés à la toute fin (1 mesure sur 2).
	_hat_roll(t0 + 3.0 * beat, 4, beat, 0.22)
	if b % 2 == 1:
		_hat_roll(t0 + 3.5 * beat, 6, beat * 0.5, 0.20)


# --- Instruments (synthés) ----------------------------------------------------

# 808 : sinus sub à glide (attaque depuis f_in → f0, puis fin vers f_next), légère saturation tanh
# (808 « distordu » moderne), enveloppe longue. Mono (le sub se centre).
func _eight_o_eight(start: float, dur: float, f_in: float, f0: float, f_next: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var ph := 0.0
	var glide_in := 0.04                       # glide d'attaque très court
	var glide_out := 0.12                      # glide vers la note suivante en fin de note
	for i in n:
		var t := float(i) / MIX
		var u := t / dur
		var f: float
		if t < glide_in:
			f = lerpf(f_in, f0, t / glide_in)
		elif u > (1.0 - glide_out / dur):
			f = lerpf(f0, f_next, (t - (dur - glide_out)) / glide_out)
		else:
			f = f0
		ph += TAU * f / MIX
		# Corps sinus + 2e harmonique douce, saturé.
		var raw := sin(ph) + 0.18 * sin(2.0 * ph)
		var env := minf(1.0, t * 80.0) * minf(1.0, (dur - t) * 10.0)   # attaque punchy, relâche douce
		s[i] = tanh(raw * 1.6) * env
	_mix(start, s, gain, gain)


# Pad sombre : saw désaccordé → passe-bas bas → swell. Wide.
func _dark_pad(start: float, dur: float, freq: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var p0 := 0.0; var p1 := 0.0
	var det := pow(2.0, 8.0 / 1200.0)
	for i in n:
		var t := float(i) / MIX
		var env := minf(1.0, t * 2.2) * minf(1.0, (dur - t) * 2.6)
		p0 += TAU * freq / MIX
		p1 += TAU * freq * det / MIX
		s[i] = (_saw(p0) * 0.5 + _saw(p1) * 0.5) * env
	s = _lowpass(s, 1400.0)
	_mix(start, s, gain, gain * 0.9)


# Kick trap : descente de pitch rapide + clic, court et claquant.
func _kick(start: float, gain: float) -> void:
	var dur := 0.26
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := lerpf(160.0, 48.0, clampf(t / 0.05, 0.0, 1.0))
		var env: float = exp(-t * 11.0)
		var click := exp(-t * 320.0) * 0.5
		s[i] = (sin(TAU * f * t) + click) * env
	_mix(start, s, gain, gain)


# Clap : 3 bursts de bruit passe-haut rapprochés (le « flam » du clap) + courte queue.
func _clap(start: float, gain: float) -> void:
	var dur := 0.30
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 555
	var prev := 0.0
	var offsets := [0.0, 0.011, 0.022]         # mini-décalages = texture de clap
	for i in n:
		var t := float(i) / MIX
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - prev; prev = white   # passe-haut 1er ordre grossier
		var env := 0.0
		for o in offsets:
			if t >= o:
				env += exp(-(t - o) * 55.0)
		env += exp(-t * 12.0) * 0.5            # petite queue de réverb
		s[i] = hp * env * 0.5
	_mix(start, s, gain, gain)


# Hi-hat : bruit court et brillant (passe-haut implicite via décroissance rapide). `bright` module la longueur.
func _hat(start: float, dur: float, gain: float, bright: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 2024
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - prev; prev = white
		s[i] = hp * exp(-t * (140.0 / bright))
	_mix(start, s, gain * 0.5, gain * 0.5)


# Roll de hi-hats : `count` hats égaux sur `total` secondes, avec léger crescendo (signature trap).
func _hat_roll(start: float, count: int, total: float, gain: float) -> void:
	var step := total / float(count)
	for k in count:
		var g := gain * lerpf(0.55, 1.0, float(k) / float(maxi(1, count - 1)))
		_hat(start + k * step, step * 0.9, g, 1.2)


# Cloche/pluck menaçant : sinus + harmoniques inharmoniques (timbre métallique) à décroissance,
# attaque vive. Pan stéréo.
func _bell(start: float, dur: float, freq: float, gain: float, pan: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var env: float = minf(1.0, t * 250.0) * exp(-t * 5.0)
		# Partiels inharmoniques (cloche) : 1, 2.01, 3.01, 4.7.
		var v := sin(TAU * freq * t)
		v += 0.5 * sin(TAU * freq * 2.01 * t)
		v += 0.3 * sin(TAU * freq * 3.01 * t)
		v += 0.15 * sin(TAU * freq * 4.7 * t)
		s[i] = v * env
	s = _lowpass(s, 6000.0)
	var gl: float = gain * sqrt(0.5 * (1.0 - pan))
	var gr: float = gain * sqrt(0.5 * (1.0 + pan))
	_mix(start, s, gl, gr)


# --- Utilitaires --------------------------------------------------------------

func _nf(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)


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
	var k := (0.95 / peak) * 0.88          # normalise puis garde du headroom (808 = beaucoup d'énergie)
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
