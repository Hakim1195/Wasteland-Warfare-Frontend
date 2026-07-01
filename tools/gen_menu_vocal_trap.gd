extends SceneTree
##
## Générateur de la MUSIQUE DE MENU — « BASE RAP » sale/street ORIGINALE, sombre et DISTORDUE
## (vibe trap dark, p.ex. l'esprit Tyga/Travis : 808 saturée, drums durs), pensée comme un
## INSTRUMENTAL sur lequel un rappeur poserait sa voix. ⚠️ **Pas de voix de synthèse** : l'utilisateur
## a jugé la voix par formants trop « robotique » (limite assumée : on ne peut PAS synthétiser une
## vraie voix humaine rappée). À la place, la mélodie/hook est portée par un **lead « sample » DARK**
## (nappes de dent-de-scie désaccordées, wobble vinyle, passe-bas poussiéreux, saturation), comme un
## échantillon chopé — c'est ce qui donne l'âme « rap » sans rien de robotique.
##
## GRANA « sporco » : 808 distordue (growl), **saturation de BUS** (drive + high-cut chaud) et une
## couche de **craquement de vinyle / souffle** = signature street/dusty.
##
## 100 % ORIGINAL & libre de droits : on s'inspire du GENRE/de la VIBE (non protégeables), JAMAIS de la
## mélodie, des accords signature, des paroles ni de l'enregistrement d'un titre existant.
##
## ⚠️ PROPRIÉTAIRE ACTIF de `assets/audio/music/menu_ambient.wav`. Les TROIS générateurs
## (celui-ci = ACTIF ; `gen_menu_trap.gd` et `gen_menu_music.gd` = archivés) visent le MÊME fichier
## → n'en lancer QU'UN (règle anti-footgun : 1 asset = 1 outil actif).
##
## Lancé SANS --path (aucun autoload), méthode média §CLAUDE :
##   Godot…_console.exe --headless --script tools/gen_menu_vocal_trap.gd
## L'AudioManager le joue tel quel via start_menu_ambient() (override, AUCUN code à toucher).

const MIX := 44100.0
const TAU := 6.2831853
const OUT := "C:/Users/Hamdi/Desktop/pinciopancio/Wasteland-Warfare-Frontend/assets/audio/music/menu_ambient.wav"

const TEMPO := 140.0               # trap @ 140 BPM, ressenti DEMI-TEMPS (clap sur le temps 3)
const BARS := 16                   # 4 cycles de 4 mesures

# --- Réglages « sporco » (à tâter à l'oreille) --------------------------------
const EOE_DRIVE := 2.0             # distorsion de la 808 (growl) — ↑ = plus sale
const BUS_PREGAIN := 0.72          # niveau d'entrée de la saturation de bus
const BUS_DRIVE := 1.75            # saturation de BUS (glue + grana) — ↑ = plus sale
const BUS_HICUT := 11000.0         # high-cut chaud (enlève le « digital brillant »)
const VINYL := 0.9                 # niveau du craquement/souffle de vinyle (0 = sec)

var _spb := 60.0 / TEMPO           # secondes par temps (noire)
var _loop_frames := 0
var L := PackedFloat32Array()
var R := PackedFloat32Array()

# Vamp sombre en RÉ mineur : i – i – VI – V (Dm – Dm – Bb – A), répété 4×. Racines MIDI pour la 808.
const ROOTS := [38, 38, 34, 33]    # D2, D2, Bb1, A1
# Pad (triade par accord, voicings médians).
const PAD := [[50, 53, 57], [50, 53, 57], [46, 50, 53], [45, 49, 52]]

# Hook mélodique (4 mesures, RÉ mineur). [temps_dans_le_cycle, midi, durée_temps]. Transposé −12 au
# rendu (registre médian/chaud « sample »). Arc accrocheur : LA, descente, puis sommet RÉ, tension DO#.
const HOOK := [
	[0.0,  69, 0.75], [1.0,  69, 0.5], [2.0,  65, 1.0],   # mes.1 (Dm) : La · La · Fa
	[4.0,  67, 0.5],  [5.0,  69, 0.5], [6.0,  65, 1.5],   # mes.2 (Dm) : Sol · La · Fa(tenue)
	[8.0,  67, 0.5],  [9.0,  69, 0.5], [10.0, 74, 1.0],   # mes.3 (Bb) : Sol · La · RÉ(sommet)
	[12.0, 73, 0.5],  [13.0, 69, 0.5], [14.0, 64, 1.0],   # mes.4 (A)  : Do# · La · Mi
]
# Cycles (0..3) où le hook joue. Cycle 2 = « beat seul » (basse + drums respirent = creux de couplet).
const LEAD_CYCLES := [0, 1, 3]


func _init() -> void:
	var beat := _spb
	var bar := beat * 4.0
	var loop_len := BARS * bar
	var tail := 1.4                 # queue (808/écho/lead) repliée sur la tête → boucle sans couture
	var total := int((loop_len + tail) * MIX)
	_loop_frames = int(loop_len * MIX)
	L.resize(total); R.resize(total)

	for b in BARS:
		var t0 := b * bar
		var ci: int = b % 4
		var cyc: int = b / 4
		_render_bar(b, ci, t0, beat)

	# Hook mélodique « sample » dark, posé sur les cycles porteurs.
	for cyc in 4:
		if not LEAD_CYCLES.has(cyc):
			continue
		var c0 := cyc * 4.0 * bar
		var i := 0
		for ev in HOOK:
			var ts: float = c0 + float(ev[0]) * beat
			var dur: float = float(ev[2]) * beat
			var pan := -0.16 if (i % 2 == 0) else 0.16    # léger ping-pong stéréo
			_sample_lead(ts, dur, int(ev[1]) - 12, 0.30, pan)
			i += 1

	# Repli de la queue (808/écho/lead qui dépassent) sur le début → boucle sans jointure.
	var extra := total - _loop_frames
	for i in extra:
		L[i] += L[_loop_frames + i]
		R[i] += R[_loop_frames + i]
	L.resize(_loop_frames); R.resize(_loop_frames)

	_add_vinyl()                    # souffle + craquements de vinyle (texture street/dusty)
	_write_stereo_loop()
	print("MENU RAP BASE DONE frames=", _loop_frames, " dur=", "%.1f" % loop_len, "s")
	quit()


func _render_bar(b: int, ci: int, t0: float, beat: float) -> void:
	var bar := beat * 4.0
	var root: int = ROOTS[ci]
	var next_root: int = ROOTS[(b + 1) % 4]

	# --- 808 DISTORDUE (basse-sub + sub-octave) : tient la mesure, glisse vers l'accord suivant. ---
	_eight_o_eight(t0, bar, _nf(root - 2), _nf(root), _nf(next_root), 1.05)

	# --- Pad sombre, POUSSIÉREUX (cutoff bas) et discret : lit harmonique sous le beat ---
	for m in PAD[ci]:
		_dark_pad(t0, bar, _nf(m), 0.026)

	# --- Kick : groove hip-hop avec bounce (frappe 1 + syncopes + ghost de relance) ---
	_kick(t0 + 0.0 * beat, 1.0)
	_kick(t0 + 1.5 * beat, 0.55)                 # bounce sur le « and of 2 »
	_kick(t0 + 2.5 * beat, 0.82)                 # syncope « and of 3 »
	if b % 2 == 1:
		_kick(t0 + 3.75 * beat, 0.6)             # ghost-kick de relance (groove)
	if b % 4 == 3:
		_kick(t0 + 3.5 * beat, 0.6)              # fill avant la reprise de phrase

	# --- Backbeat demi-temps (temps 3) : clap + RULLANTE/snare superposé (crack street) ---
	_clap(t0 + 2 * beat, 0.9)
	_snare(t0 + 2 * beat, 0.55)

	# --- Hi-hats : croches avec léger SWING (groove) + rolls ---
	for e in 8:
		var swing := (beat * 0.5 * 0.12) if (e % 2 == 1) else 0.0
		var ts := t0 + e * (beat * 0.5) + swing
		var g := 0.24 * (1.0 if (e % 2 == 0) else 0.7)
		_hat(ts, beat * 0.22, g, 1.0)
	_hat_roll(t0 + 3.0 * beat, 4, beat, 0.22)
	if b % 2 == 1:
		_hat_roll(t0 + 3.5 * beat, 6, beat * 0.5, 0.20)


# --- Lead mélodique « sample » DARK (remplace la voix) ------------------------

# Hook : nappes de dent-de-scie désaccordées + wobble vinyle + passe-bas poussiéreux + saturation
# (chaleur analogique sale), puis écho pointé. Sonne comme un échantillon chopé, RIEN de robotique.
func _sample_lead(start: float, dur: float, midi: int, gain: float, pan: float) -> void:
	var n := int(dur * MIX)
	if n <= 0:
		return
	var base := _nf(midi)
	var s := PackedFloat32Array(); s.resize(n)
	var p0 := 0.0; var p1 := 0.0; var p2 := 0.0
	var det1 := pow(2.0, 7.0 / 1200.0)        # +7 cents
	var det2 := pow(2.0, -9.0 / 1200.0)       # −9 cents
	for i in n:
		var t := float(i) / MIX
		# Wobble « bande/vinyle » : micro-dérive de hauteur (lent + un peu plus rapide) = vieux sample.
		var warble := 1.0 + 0.004 * sin(TAU * 5.7 * t) + 0.0025 * sin(TAU * 0.6 * t + 1.1)
		var f := base * warble
		p0 += TAU * f / MIX
		p1 += TAU * f * det1 / MIX
		p2 += TAU * f * det2 / MIX
		var env := minf(1.0, t * 55.0) * minf(1.0, (dur - t) * 8.0)
		s[i] = (_saw(p0) * 0.5 + _saw(p1) * 0.35 + _saw(p2) * 0.35) * env
	s = _lowpass(s, 2400.0)                    # poussiéreux/sombre (pas brillant)
	for i in n:
		s[i] = tanh(s[i] * 2.3) * 0.7          # saturation (chaleur sale)
	s = _lowpass(s, 4000.0)                    # adoucit le crunch
	var gl := gain * sqrt(0.5 * (1.0 - pan))
	var gr := gain * sqrt(0.5 * (1.0 + pan))
	_mix(start, s, gl, gr)
	_echo(s, start, gain * 0.4, pan, _spb * 0.75, 0.45, 2)


# --- Texture vinyle (souffle + craquements) -----------------------------------

# Ajoute sur toute la boucle un souffle filtré très bas + des « pops » aléatoires = grana street/dusty.
func _add_vinyl() -> void:
	if VINYL <= 0.0:
		return
	var n := _loop_frames
	var rng := RandomNumberGenerator.new(); rng.seed = 31337
	var prev := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, w, 0.25)               # passe-bas grossier → souffle « chaud »
		var hiss := prev * 0.018 * VINYL
		L[i] += hiss
		R[i] += hiss * 0.92
	# Craquements : impulsions courtes éparses (≈14/s), polarité et décroissance aléatoires.
	var pops := int(float(n) / MIX * 14.0)
	for k in pops:
		var idx := rng.randi_range(0, n - 320)
		var amp := rng.randf_range(0.04, 0.16) * VINYL
		var dk := rng.randf_range(500.0, 1500.0)
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		for j in 300:
			var v := sgn * amp * exp(-float(j) / MIX * dk)
			L[idx + j] += v
			R[idx + j] += v * 0.92


# --- Instruments (synthés) ----------------------------------------------------

func _eight_o_eight(start: float, dur: float, f_in: float, f0: float, f_next: float, gain: float) -> void:
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var ph := 0.0
	var ph_sub := 0.0
	var glide_in := 0.04
	var glide_out := 0.12
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
		ph_sub += TAU * f * 0.5 / MIX                              # une octave SOUS la 808
		# Corps 808 DISTORDU (growl : 2e+3e harm., drive poussé) + sinus de SUB grave (poids « ressenti »).
		var core := sin(ph) + 0.20 * sin(2.0 * ph) + 0.10 * sin(3.0 * ph)
		var body := tanh(core * EOE_DRIVE)
		var sub := sin(ph_sub) * 0.55
		var env := minf(1.0, t * 80.0) * minf(1.0, (dur - t) * 10.0)
		s[i] = (body * 0.9 + sub) * env
	_mix(start, s, gain, gain)


# Pad : saw désaccordé → passe-bas BAS (poussiéreux, sombre) → swell.
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
	s = _lowpass(s, 1500.0)
	_mix(start, s, gain, gain * 0.9)


func _kick(start: float, gain: float) -> void:
	var dur := 0.26
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var f := lerpf(160.0, 48.0, clampf(t / 0.05, 0.0, 1.0))
		var env: float = exp(-t * 11.0)
		var click := exp(-t * 320.0) * 0.5
		s[i] = tanh((sin(TAU * f * t) + click) * 1.3) * env    # léger overdrive (punch street)
	_mix(start, s, gain, gain)


func _clap(start: float, gain: float) -> void:
	var dur := 0.30
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 555
	var prev := 0.0
	var offsets := [0.0, 0.011, 0.022]
	for i in n:
		var t := float(i) / MIX
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - prev; prev = white
		var env := 0.0
		for o in offsets:
			if t >= o:
				env += exp(-(t - o) * 55.0)
		env += exp(-t * 12.0) * 0.5
		s[i] = hp * env * 0.5
	_mix(start, s, gain, gain)


# Rullante/snare superposé au clap : bruit large à décroissance + corps tonal (180/330 Hz) = « crack »
# net (couleur hip-hop), court.
func _snare(start: float, gain: float) -> void:
	var dur := 0.18
	var n := int(dur * MIX)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 9001
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX
		var white := rng.randf_range(-1.0, 1.0)
		var hp := white - prev; prev = white            # passe-haut grossier = « pschtt »
		var noise := hp * exp(-t * 26.0) * 0.7
		var body := sin(TAU * 180.0 * t) * exp(-t * 38.0) * 0.4
		body += sin(TAU * 330.0 * t) * exp(-t * 42.0) * 0.2
		s[i] = noise + body
	_mix(start, s, gain, gain)


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


func _hat_roll(start: float, count: int, total: float, gain: float) -> void:
	var step := total / float(count)
	for k in count:
		var g := gain * lerpf(0.55, 1.0, float(k) / float(maxi(1, count - 1)))
		_hat(start + k * step, step * 0.9, g, 1.2)


# Écho stéréo : `taps` copies décroissantes du buffer, retardées de `delay` s, pan alterné (ping-pong).
func _echo(s: PackedFloat32Array, start: float, base_gain: float, pan: float, delay: float, fb: float, taps: int) -> void:
	for k in range(1, taps + 1):
		var g: float = base_gain * pow(fb, float(k))
		var p: float = pan if (k % 2 == 1) else -pan
		var gl: float = g * sqrt(0.5 * (1.0 - p))
		var gr: float = g * sqrt(0.5 * (1.0 + p))
		_mix(start + delay * float(k), s, gl, gr)


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
	# 1) Pré-normalisation à un niveau connu → saturation de bus prévisible.
	var peak0 := 0.0001
	for i in n:
		peak0 = maxf(peak0, maxf(absf(L[i]), absf(R[i])))
	var pg := BUS_PREGAIN / peak0
	# 2) Saturation de BUS (« sporco » street : distorsion douce qui colle + salit le tout).
	for i in n:
		L[i] = tanh(L[i] * pg * BUS_DRIVE)
		R[i] = tanh(R[i] * pg * BUS_DRIVE)
	# 3) High-cut chaud (enlève le « digital brillant », rapproche du son cassette/vinyle).
	L = _lowpass(L, BUS_HICUT)
	R = _lowpass(R, BUS_HICUT)
	# 4) Normalisation finale + headroom.
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, maxf(absf(L[i]), absf(R[i])))
	var k := (0.95 / peak) * 0.92
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
