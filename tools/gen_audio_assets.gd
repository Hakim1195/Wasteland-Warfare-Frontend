extends SceneTree
##
## Générateur des SFX d'interface + de combat — lancé SANS --path (aucun autoload).
##   Godot…_console.exe --headless --script tools/gen_audio_assets.gd
##
## Synthétise puis ÉCRIT sur disque (.wav PCM 16 bits, AudioStreamWAV.save_to_wav) les 7 SFX, plus
## soignés que les placeholders runtime de l'AudioManager (réverbe à échos, filtrage passe-bas).
## Déposés dans assets/audio/sfx/ → l'AudioManager les charge en override (§8.64), AUCUN code à toucher.
## ⚠️ Les MUSIQUES sont produites ailleurs : menu = `gen_menu_music.gd` (§8.65), arène =
## `gen_battle_music.gd` (§8.66). Cet outil ne touche PAS au dossier `music/`.

const MIX := 44100.0
const TAU := 6.2831853
const ROOT := "C:/Users/Hamdi/Desktop/pinciopancio/Wasteland-Warfare-Frontend/assets/audio"

func _init() -> void:
	_save_mono(_hover(), ROOT + "/sfx/hover.wav", 0.50)
	_save_mono(_click(), ROOT + "/sfx/click.wav", 0.72)
	_save_mono(_confirm(), ROOT + "/sfx/confirm.wav", 0.85)
	_save_mono(_back(), ROOT + "/sfx/back.wav", 0.80)
	_save_mono(_sting(), ROOT + "/sfx/sting.wav", 0.95)
	# SFX de combat (Split-Screen VS) :
	_save_mono(_die_lock(), ROOT + "/sfx/die_lock.wav", 0.80)   # claque d'arrêt du dé
	_save_mono(_impact(), ROOT + "/sfx/impact.wav", 0.90)       # pertes / coup encaissé
	# ⚠️ La MUSIQUE n'est PLUS produite ici : `menu_ambient` est désormais la vraie piste « Interstellar »
	# de `gen_menu_music.gd` (§8.65) et `battle_ambient` celle de `gen_battle_music.gd` (§8.66). Ne pas
	# réécrire de musique depuis cet outil (il écraserait ces pistes par l'ancienne nappe 8 s).
	print("AUDIO ASSETS DONE (SFX uniquement)")
	quit()


# --- SFX ----------------------------------------------------------------------

# Survol : tick aigu doux, très court (sinus + harmonique, attaque très rapide).
func _hover() -> PackedFloat32Array:
	var n := int(MIX * 0.05)
	var s := PackedFloat32Array(); s.resize(n)
	for i in n:
		var t := float(i) / MIX
		var env: float = exp(-t * 26.0) * minf(1.0, t * 400.0)
		var body := sin(TAU * 1760.0 * t) + 0.22 * sin(TAU * 3520.0 * t)
		s[i] = body * env * 0.5
	return _lowpass(s, 9000.0)


# Clic : transitoire de bruit filtré (le « tac ») + corps tonal bref + courte queue.
func _click() -> PackedFloat32Array:
	var n := int(MIX * 0.09)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1337
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX
		var white := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.45)
		var transient := prev * exp(-t * 110.0) * 0.6
		var body := (sin(TAU * 880.0 * t) + 0.3 * sin(TAU * 1320.0 * t)) * exp(-t * 34.0) * 0.3
		s[i] = transient + body
	return _echoes(_lowpass(s, 7000.0), 0.10)


# Validation : accord montant (quinte) — deux notes enchaînées + queue de réverbe.
func _confirm() -> PackedFloat32Array:
	return _echoes(_chord(523.25, 783.99, 0.30), 0.22)   # do5 -> sol5


# Retour : accord descendant, plus doux.
func _back() -> PackedFloat32Array:
	return _echoes(_chord(659.25, 440.0, 0.24), 0.18)     # mi5 -> la4


# Deux notes (montant/descendant) avec recouvrement, harmoniques et léger vibrato.
func _chord(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var n := int(MIX * dur)
	var s := PackedFloat32Array(); s.resize(n)
	var half := dur * 0.45
	for i in n:
		var t := float(i) / MIX
		var vib := 1.0 + 0.004 * sin(TAU * 5.5 * t)
		var e0: float = exp(-t * 8.0) * minf(1.0, t * 240.0)
		var e1: float = exp(-maxf(0.0, t - half) * 8.0) * clampf((t - half) * 240.0, 0.0, 1.0)
		var v0 := (sin(TAU * f0 * vib * t) + 0.32 * sin(TAU * f0 * 2.0 * t) + 0.12 * sin(TAU * f0 * 3.0 * t)) * e0
		var v1 := (sin(TAU * f1 * vib * t) + 0.32 * sin(TAU * f1 * 2.0 * t) + 0.12 * sin(TAU * f1 * 3.0 * t)) * e1
		s[i] = (v0 + v1) * 0.26
	return s


# « Sting » de reveal : sub-impact + corps grave montant + accord scintillant + riser de bruit + queue.
func _sting() -> PackedFloat32Array:
	var dur := 1.25
	var n := int(MIX * dur)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var phase_low := 0.0
	for i in n:
		var t := float(i) / MIX
		var u := t / dur
		var sub := sin(TAU * 46.0 * t) * exp(-t * 6.0) * 0.34
		var f_low := lerpf(110.0, 330.0, pow(u, 0.55))
		phase_low += TAU * f_low / MIX
		var body := sin(phase_low) * exp(-t * 2.6) * 0.24
		var sh := sin(TAU * 1318.5 * t) + sin(TAU * 1760.0 * t) + 0.55 * sin(TAU * 2637.0 * t)
		sh *= exp(-t * 4.2) * 0.045 * minf(1.0, t * 36.0)
		# Riser de bruit qui monte vers l'impact puis s'efface.
		var riser_env := pow(clampf(u * 1.8, 0.0, 1.0), 2.0) * exp(-maxf(0.0, t - 0.3) * 10.0)
		var noise := rng.randf_range(-1.0, 1.0) * riser_env * 0.08
		s[i] = sub + body + sh + noise
	return _echoes(s, 0.28)


# Claque d'arrêt du dé (« die lock ») : transitoire mat (bois/os) + corps tonal court qui « claque »
# sur sa valeur. Sec, percussif, satisfaisant — joué à chaque dé qui se verrouille.
func _die_lock() -> PackedFloat32Array:
	var n := int(MIX * 0.11)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX
		# Transitoire : bruit lissé à décroissance très rapide (le « tac » du dé qui pose).
		var white := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.6)
		var transient := prev * exp(-t * 130.0) * 0.7
		# Corps tonal mat (deux partiels graves désaccordés) → impression de matière.
		var body := (sin(TAU * 240.0 * t) + 0.5 * sin(TAU * 360.0 * t)) * exp(-t * 42.0) * 0.32
		s[i] = transient + body
	return _echoes(_lowpass(s, 5200.0), 0.07)


# Impact de combat (« coup encaissé ») : sub-boom + claquement métallique bref + souffle.
# Joué à la révélation des pertes (gros « −N » du Split-Screen VS).
func _impact() -> PackedFloat32Array:
	var dur := 0.5
	var n := int(MIX * dur)
	var s := PackedFloat32Array(); s.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1919
	for i in n:
		var t := float(i) / MIX
		# Sub-boom (descente de pitch).
		var f := lerpf(150.0, 50.0, clampf(t / 0.06, 0.0, 1.0))
		var boom := sin(TAU * f * t) * exp(-t * 12.0) * 0.5
		# Claquement métallique (deux partiels inharmoniques) très bref.
		var clang := (sin(TAU * 1100.0 * t) + 0.7 * sin(TAU * 1730.0 * t)) * exp(-t * 30.0) * 0.16
		# Souffle d'impact (bruit filtré court).
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 26.0) * 0.18
		s[i] = boom + clang + noise
	return _echoes(_lowpass(s, 6500.0), 0.18)


# --- Traitements --------------------------------------------------------------

# Filtre passe-bas un pôle (réchauffe / arrondit les transitoires).
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


# Queue de réverbe : prolonge le buffer puis ajoute 3 échos discrets (non récursifs = stables),
# légèrement filtrés. `amount` = niveau global de la queue.
func _echoes(dry: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var tail := int(MIX * 0.45)
	var out := PackedFloat32Array(); out.resize(dry.size() + tail)
	for i in dry.size():
		out[i] = dry[i]
	var taps := [[0.085, 0.45], [0.150, 0.28], [0.230, 0.16]]
	for tap in taps:
		var d := int(MIX * tap[0])
		var g: float = tap[1] * amount
		for i in range(d, out.size()):
			if i - d < dry.size():
				out[i] += dry[i - d] * g
	return _lowpass(out, 8000.0)


# --- Écriture WAV -------------------------------------------------------------

func _save_mono(s: PackedFloat32Array, path: String, gain: float) -> void:
	_normalize(s, 0.97)
	for i in s.size():
		s[i] *= gain
	var bytes := PackedByteArray(); bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX)
	wav.stereo = false
	wav.data = bytes
	var err := wav.save_to_wav(path)
	print("  ", path.get_file(), " frames=", s.size(), " err=", err)


func _normalize(s: PackedFloat32Array, target: float) -> void:
	var peak := 0.0001
	for i in s.size():
		peak = maxf(peak, absf(s[i]))
	var k := target / peak
	for i in s.size():
		s[i] *= k
