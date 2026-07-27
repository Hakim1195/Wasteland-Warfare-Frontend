extends Node
##
## AudioManager (autoload) — SFX d'interface + ambiance, avec OVERRIDE par vrais assets (R6).
##
## Deux sources, dans cet ordre de priorité :
##   1. VRAIS FICHIERS (s'ils existent) — déposés dans `res://assets/audio/sfx/<nom>.{ogg,wav,mp3}`
##      et `res://assets/audio/music/menu_ambient.{ogg,wav,mp3}`. Chargés au démarrage, AUCUN code à
##      toucher : il suffit de déposer les fichiers (cf. `assets/audio/README.md`) puis de réimporter.
##   2. PLACEHOLDERS procéduraux — si aucun fichier n'est trouvé, les sons sont SYNTHÉTISÉS au
##      démarrage (AudioStreamWAV PCM 16 bits). Sert tant que les vrais assets n'existent pas.
##
## Tout est routé sur les bus `SFX` / `Music` du `default_bus_layout.tres` (§8.43, volumes pilotés par
## `SettingsManager`). API publique :
##     AudioManager.play_sfx("click")   ·   AudioManager.start_menu_ambient()
##     AudioManager.start_battle_ambient()   (musique tendue de l'arène, §8.66)   ·   stop_ambient()
## La musique passe par un lecteur UNIQUE (`_music_player`) : démarrer une piste BASCULE le flux (le
## menu et le combat ne jouent jamais en même temps), avec cache pour ne charger/synthétiser qu'une fois.
##
## Règle d'Or §6.1 : service de présentation pur (aucune logique de jeu).

const MIX_RATE := 44100.0          # 44.1 kHz (placeholders nettement plus brillants qu'en 22 kHz)
const TAU := 6.2831853

# Override par assets réels : dossiers + extensions tentées (par ordre de préférence).
const AUDIO_DIR := "res://assets/audio"
const AUDIO_EXTS := [".ogg", ".wav", ".mp3"]
const SFX_NAMES := ["hover", "click", "confirm", "back", "sting", "die_lock", "impact",
	"explosion", "chat_ping", "finisher_steel", "finisher_orbital", "finisher_ash"]
const MUSIC_NAME := "menu_ambient"          # nappe des menus
const BATTLE_NAME := "battle_ambient"       # musique tendue de l'arène (§8.66)

# --- Musique : niveau cible et fondu d'entrée (REFONTE UI ARÈNE, lot F) ---
# MESURE (diagnostic du 2026-07-27, poste de dev) : la chaîne réelle empile TROIS atténuations —
# bus Master 0,7 (≈ −3,1 dB) × bus Music 0,46 (≈ −6,7 dB) × lecteur (−6,0 dB à l'époque), soit
# ≈ −16 dB au total : la piste JOUAIT bien (et bouclait), mais était quasi inaudible. On remonte
# donc le niveau du LECTEUR à −4 dB (« discret mais audible ») au lieu du −10 dB suggéré par le
# cahier des charges, qui aurait AGGRAVÉ le symptôme sur cette chaîne. Les volumes utilisateur
# (SettingsManager / bus) restent souverains au-dessus de cette constante.
const MUSIC_TARGET_DB := -4.0
# Niveau de départ du fondu d'entrée (inaudible) et durée du fondu.
const MUSIC_FADE_FROM_DB := -40.0
const MUSIC_FADE_TIME := 2.0

var _sfx: Dictionary = {}          # nom -> AudioStream (vrai fichier OU WAV synthétisé)
var _sfx_players: Array = []       # pool de AudioStreamPlayer (évite de couper un son en cours)
var _sfx_next := 0
var _music_player: AudioStreamPlayer
var _music_cache: Dictionary = {}  # base_name -> AudioStream (vrai fichier OU synthèse), chargé 1×
var _real_count := 0               # nb d'assets réels chargés (info / journal)
# Désactive la LECTURE sous le pilote audio « Dummy » de l'headless (validation CLI) — la synthèse
# des WAV reste exécutée (c'est elle qu'on valide). Même garde que SettingsManager (§8.43).
var _enabled := true


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	# Pool de lecteurs SFX (round-robin).
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = _bus_or_master("SFX")
		add_child(p)
		_sfx_players.append(p)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = _bus_or_master("Music")
	_music_player.volume_db = MUSIC_TARGET_DB
	add_child(_music_player)

	# Banque de SFX : vrai fichier prioritaire, sinon placeholder procédural.
	_sfx["hover"] = _load_override("sfx", "hover")
	if _sfx["hover"] == null: _sfx["hover"] = _make_blip(1500.0, 0.045, 0.14)
	_sfx["click"] = _load_override("sfx", "click")
	if _sfx["click"] == null: _sfx["click"] = _make_click()
	_sfx["confirm"] = _load_override("sfx", "confirm")
	if _sfx["confirm"] == null: _sfx["confirm"] = _make_chord(520.0, 780.0, 0.22)   # quinte montante
	_sfx["back"] = _load_override("sfx", "back")
	if _sfx["back"] == null: _sfx["back"] = _make_chord(660.0, 440.0, 0.18)         # descente
	_sfx["sting"] = _load_override("sfx", "sting")
	if _sfx["sting"] == null: _sfx["sting"] = _make_sting()
	# SFX de combat (Split-Screen VS, §8.66).
	_sfx["die_lock"] = _load_override("sfx", "die_lock")
	if _sfx["die_lock"] == null: _sfx["die_lock"] = _make_die_lock()
	_sfx["impact"] = _load_override("sfx", "impact")
	if _sfx["impact"] == null: _sfx["impact"] = _make_impact()

	# --- Hooks sensoriels (E9 §8.81) : 10 SFX aux moments qui comptent. Replis SYNTHÉTISÉS
	#     distincts (fréquences/durées documentées) — aucun asset requis pour livrer ; Hakim
	#     remplace en déposant assets/audio/sfx/<nom>.{ogg,wav,mp3} (mécanique _load_override).
	#     dice_lock / hit_troops = alias du feedback de combat existant (même événement). ---
	_register_sfx("your_turn", func(): return _make_chord(523.0, 784.0, 0.34))    # quinte triomphale (do→sol)
	_register_sfx("dice_lock", func(): return _make_die_lock())                    # claque sèche du dé
	_register_sfx("hit_troops", func(): return _make_impact())                     # impact sourd de pertes
	_register_sfx("hero_hit", func(): return _make_blip(320.0, 0.10, 0.22))        # coup grave encaissé
	_register_sfx("hero_down", func(): return _make_chord(300.0, 150.0, 0.55))     # chute dramatique (permadeath)
	_register_sfx("conquest", func(): return _make_chord(440.0, 880.0, 0.30))      # fanfare courte (octave)
	_register_sfx("zone_alarm", func(): return _make_blip(760.0, 0.24, 0.18))      # alerte toxique aiguë
	_register_sfx("under_attack", func(): return _make_blip(220.0, 0.18, 0.22))    # alerte défensive grave
	_register_sfx("card_draw", func(): return _make_blip(1180.0, 0.06, 0.13))      # bruissement de pioche
	_register_sfx("timer_tick", func(): return _make_blip(880.0, 0.035, 0.10))     # tic discret d'AFK

	# --- REFONTE UI ARÈNE (lot F) : nouveaux sons. Même mécanique d'override — déposer
	#     assets/audio/sfx/<nom>.{ogg,wav,mp3} remplace le repli synthétisé, ZÉRO code à toucher. ---
	# `explosion` : impact de la FLÈCHE DE GUERRE (lot D). Remplace `impact`/`hit_troops` DANS CE
	# CONTEXTE uniquement — les autres usages de ces sons restent inchangés.
	_register_sfx("explosion", func(): return _make_explosion())
	# `chat_ping` : notification de message reçu (lot B) — aigu, court, discret.
	_register_sfx("chat_ping", func(): return _make_blip(1760.0, 0.07, 0.09))
	# Stings des FINISHERS (lot D/G) : un par variante achetable ; le basique gratuit réutilise
	# `hero_down`. Repli COMMUN si l'un manque : la cinématique reste sonore quoi qu'il arrive.
	_register_sfx("finisher_steel", func(): return _make_finisher_sting(180.0, 70.0, 0.55, 1.1))
	_register_sfx("finisher_orbital", func(): return _make_finisher_sting(90.0, 900.0, 0.22, 1.3))
	_register_sfx("finisher_ash", func(): return _make_finisher_sting(140.0, 48.0, 0.75, 1.4))

# Enregistre un SFX par nom : vrai fichier prioritaire (assets/audio/sfx/<nom>), sinon repli
# synthétisé (Callable() -> AudioStreamWAV). Factorise le pattern _load_override / _make_*.
func _register_sfx(sfx_name: String, synth: Callable) -> void:
	var override := _load_override("sfx", sfx_name)
	_sfx[sfx_name] = override if override != null else synth.call()


# Joue un SFX par nom (silencieux si inconnu). Round-robin sur le pool.
func play_sfx(sfx_name: String) -> void:
	if not _enabled or not _sfx.has(sfx_name) or _sfx[sfx_name] == null or _sfx_players.is_empty():
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = _sfx[sfx_name]
	p.play()


# Démarre/maintient la MUSIQUE DE MENU (bouclée) sur le bus Music. Idempotent.
func start_menu_ambient() -> void:
	_play_music(MUSIC_NAME)


# Démarre/maintient la MUSIQUE DE COMBAT de l'arène (§8.66). Bascule depuis la musique de menu sans
# coupure brutale (lecteur unique). Idempotent : rappels sans effet si déjà en cours.
func start_battle_ambient() -> void:
	_play_music(BATTLE_NAME)


func stop_ambient() -> void:
	if _music_player:
		_music_player.stop()


# Coeur de la musique : charge (override > synthèse) et met en cache la piste demandée, puis BASCULE
# le lecteur unique dessus si besoin. Ne relance pas une piste déjà en cours (évite les redémarrages).
func _play_music(base_name: String) -> void:
	if not _enabled or _music_player == null:
		return
	var stream: AudioStream = _music_cache.get(base_name)
	if stream == null:
		var real := _load_override("music", base_name)
		if real != null:
			stream = real
		elif base_name == BATTLE_NAME:
			stream = _make_battle_pad()       # repli synthétisé (si le .wav manque / headless)
		else:
			stream = _make_ambient_pad()
		_ensure_looped(stream)
		_music_cache[base_name] = stream
	if _music_player.stream != stream:
		_music_player.stream = stream
		_music_player.play()
		_fade_music_in()
	elif not _music_player.playing:
		_music_player.play()
		_fade_music_in()


# Fondu d'entrée (lot F) : la piste monte de MUSIC_FADE_FROM_DB à MUSIC_TARGET_DB en
# MUSIC_FADE_TIME. Évite l'attaque brutale au changement de scène (menu → arène) et donne une
# entrée « cinéma » à l'ambiance de guerre.
var _music_fade: Tween = null

func _fade_music_in() -> void:
	if _music_player == null:
		return
	if _music_fade != null and _music_fade.is_valid():
		_music_fade.kill()
	_music_player.volume_db = MUSIC_FADE_FROM_DB
	_music_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_music_fade.tween_property(_music_player, "volume_db", MUSIC_TARGET_DB, MUSIC_FADE_TIME)


# Libère proprement les ressources audio à l'extinction (évite des fuites de AudioStreamWAV /
# AudioStreamPlaybackWAV si un son joue encore au moment où le moteur se ferme).
func _exit_tree() -> void:
	for p in _sfx_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	_sfx.clear()
	_music_cache.clear()


# --- Override par vrais assets ------------------------------------------------

# Cherche `res://assets/audio/<category>/<name>.{ogg,wav,mp3}`. Renvoie l'AudioStream chargé, ou null
# si aucun fichier (→ l'appelant retombe sur la synthèse). Export-safe : `ResourceLoader` résout les
# `.import` / `.remap` ; on ne dépend d'aucun `class_name`.
func _load_override(category: String, base_name: String) -> AudioStream:
	for ext in AUDIO_EXTS:
		var path := "%s/%s/%s%s" % [AUDIO_DIR, category, base_name, ext]
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is AudioStream:
				_real_count += 1
				return res
	return null


# Force le bouclage d'un flux de musique chargé depuis un fichier (ogg/mp3 → `loop` ; wav → loop_mode).
func _ensure_looped(stream: AudioStream) -> void:
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true
	elif stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# Nombre d'IMAGES (frames), valable mono/stéréo et quel que soit le format (PCM/QOA) :
		# get_length() est en secondes → × mix_rate. (NE PAS dériver de data.size(), faux en
		# stéréo et avec compression.)
		stream.loop_end = int(stream.get_length() * stream.mix_rate)


# --- Synthèse (placeholders) --------------------------------------------------

# Bip court : sinus + enveloppe attaque rapide / décroissance exponentielle.
func _make_blip(freq: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 18.0) * minf(1.0, t * 220.0)
		# Sinus + harmonique légère (corps moins « pur », plus matériel).
		var body := sin(TAU * freq * t) + 0.25 * sin(TAU * freq * 2.0 * t)
		s[i] = body * env * vol
	return _finalize(s)


# Clic d'interface : transitoire de bruit filtré (le « tac ») + court corps tonal.
func _make_click() -> AudioStreamWAV:
	var dur := 0.08
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		# Transitoire : bruit blanc lissé (passe-bas simple) à décroissance très rapide.
		var white := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.5)
		var transient := prev * exp(-t * 90.0) * 0.5
		# Corps tonal bref.
		var body := sin(TAU * 820.0 * t) * exp(-t * 30.0) * 0.28
		s[i] = transient + body
	return _finalize(s)


# Accord de deux notes (montant ou descendant) — sert à confirm / back. Deux partiels enchaînés,
# avec un léger chevauchement et une queue de réverbération synthétique.
func _make_chord(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var half := dur * 0.5
	for i in n:
		var t := float(i) / MIX_RATE
		# Note 1 sur la première moitié, note 2 sur la seconde (avec recouvrement).
		var e0 := exp(-t * 9.0) * minf(1.0, t * 200.0)
		var e1 := exp(-maxf(0.0, t - half) * 9.0) * clampf((t - half) * 200.0, 0.0, 1.0)
		var v0 := (sin(TAU * f0 * t) + 0.3 * sin(TAU * f0 * 2.0 * t)) * e0
		var v1 := (sin(TAU * f1 * t) + 0.3 * sin(TAU * f1 * 2.0 * t)) * e1
		s[i] = (v0 + v1) * 0.26
	return _finalize(s)


# « Sting » de reveal : sub-impact + corps grave montant + accord scintillant + souffle d'attaque.
func _make_sting() -> AudioStreamWAV:
	var dur := 1.0
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase_low := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / dur
		# Sub-impact (boom de départ).
		var sub := sin(TAU * 48.0 * t) * exp(-t * 7.0) * 0.30
		# Corps grave montant (montée en tension).
		var f_low := lerpf(110.0, 330.0, pow(u, 0.6))
		phase_low += TAU * f_low / MIX_RATE
		var body := sin(phase_low) * exp(-t * 3.0) * 0.26
		# Accord cyber scintillant (tierce + quinte), entre vite, décroît.
		var shimmer := (sin(TAU * 1320.0 * t) + sin(TAU * 1760.0 * t) + 0.6 * sin(TAU * 2640.0 * t))
		shimmer *= exp(-t * 5.0) * 0.05 * minf(1.0, t * 40.0)
		# Souffle d'attaque (riser de bruit court).
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 38.0) * 0.10
		s[i] = sub + body + shimmer + noise
	return _finalize(s)


# Claque d'arrêt du dé (Split-Screen VS) : transitoire mat + corps grave qui « claque ». Sec, court.
func _make_die_lock() -> AudioStreamWAV:
	var dur := 0.10
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.6)
		var transient := prev * exp(-t * 130.0) * 0.6
		var body := (sin(TAU * 240.0 * t) + 0.5 * sin(TAU * 360.0 * t)) * exp(-t * 42.0) * 0.30
		s[i] = transient + body
	return _finalize(s)


# Impact de combat (pertes encaissées) : sub-boom + claquement métallique bref + souffle.
func _make_impact() -> AudioStreamWAV:
	var dur := 0.45
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1919
	for i in n:
		var t := float(i) / MIX_RATE
		var f := lerpf(150.0, 50.0, clampf(t / 0.06, 0.0, 1.0))
		var boom := sin(TAU * f * t) * exp(-t * 12.0) * 0.5
		var clang := (sin(TAU * 1100.0 * t) + 0.7 * sin(TAU * 1730.0 * t)) * exp(-t * 30.0) * 0.15
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 26.0) * 0.16
		s[i] = boom + clang + noise
	return _finalize(s)


# Explosion (lot F) : impact de la flèche de guerre. Sub très court + burst de bruit filtré qui
# se referme + traînée de débris. Plus « sale » et plus grave que `impact` (pertes de troupes),
# pour que les deux ne se confondent pas à l'oreille.
func _make_explosion() -> AudioStreamWAV:
	var dur := 0.7
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8102
	var lp := 0.0        # passe-bas 1 pôle dont le coefficient se referme avec le temps
	for i in n:
		var t := float(i) / MIX_RATE
		# Sub : descente rapide 90 → 32 Hz, décroissance nette.
		var f := lerpf(90.0, 32.0, clampf(t / 0.14, 0.0, 1.0))
		var sub := sin(TAU * f * t) * exp(-t * 9.0) * 0.62
		# Burst : bruit blanc de plus en plus filtré (le souffle « s'éloigne »).
		var cut := clampf(0.55 * exp(-t * 4.5), 0.03, 0.55)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), cut)
		var burst := lp * exp(-t * 5.5) * 0.5
		# Débris : crépitement aléatoire épars sur la queue.
		var debris := 0.0
		if t > 0.12 and rng.randf() < 0.012:
			debris = rng.randf_range(-1.0, 1.0) * 0.18
		s[i] = sub + burst + debris * exp(-t * 2.0)
	return _finalize(s)


# Sting de FINISHER (lot D/G) : balayage de fréquence (montant ou descendant selon f0/f1) +
# couche de bruit dosable + queue de réverbération synthétique. Un seul générateur paramétré →
# les 3 variantes payantes sonnent DIFFÉREMMENT sans tripler le code (Règle d'Or §6.3).
func _make_finisher_sting(f0: float, f1: float, noise_mix: float, dur: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0) * 31 + int(f1)
	var phase := 0.0
	var air := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / dur
		# Balayage exponentiel f0 → f1 (montée « orbitale » ou chute « cendres »).
		var f := lerpf(f0, f1, pow(u, 0.55))
		phase += TAU * f / MIX_RATE
		var body := (sin(phase) + 0.35 * sin(phase * 2.0)) * exp(-t * 2.2) * 0.34
		# Impact d'ouverture (les 60 premières ms).
		var hit := sin(TAU * 55.0 * t) * exp(-t * 16.0) * 0.4
		# Souffle filtré, dosé par noise_mix.
		air = lerpf(air, rng.randf_range(-1.0, 1.0), 0.25)
		var noise := air * exp(-t * 3.0) * noise_mix * 0.3
		s[i] = body + hit + noise
	return _finalize(s)


# Nappe d'ambiance bouclable : accord grave désaccordé + harmoniques + LFO de filtre lent + souffle.
func _make_ambient_pad() -> AudioStreamWAV:
	var dur := 6.0   # boucle plus longue → respiration moins répétitive
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var air := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		# Trémolo + ouverture/fermeture lente (pseudo-filtre) sur les partiels aigus.
		var tremolo := 0.80 + 0.20 * sin(TAU * 0.08 * t)
		var open := 0.5 + 0.5 * sin(TAU * 0.05 * t + 1.3)
		var a := sin(TAU * 55.0 * t)                       # fondamentale
		var b := sin(TAU * 82.4 * t) * 0.55                # quinte (légèrement désaccordée)
		var c := sin(TAU * 110.0 * t) * 0.30               # octave
		var d := sin(TAU * 164.8 * t) * 0.16 * open        # partiel aigu modulé
		# Couche d'« air » : bruit très filtré, très bas (texture post-apo).
		air = lerpf(air, rng.randf_range(-1.0, 1.0), 0.02)
		s[i] = ((a + b + c + d) * 0.15 + air * 0.04) * tremolo
	# Fondu de raccord en début/fin de boucle pour masquer la jointure.
	var fade := int(MIX_RATE * 0.05)
	for i in fade:
		var g := float(i) / float(fade)
		s[i] *= g
		s[n - 1 - i] *= g
	return _finalize(s, true)


# Repli synthétisé de la MUSIQUE DE COMBAT (si battle_ambient.wav absent / headless) : drone grave de
# dread + pouls de tom martelé. Volontairement plus sombre et martial que la nappe de menu.
# Lot F — AMBIANCE DE GUERRE enrichie : boucle allongée à 9,6 s (le motif se répète deux fois moins
# souvent, donc s'entend beaucoup moins), drone à deux couches battantes, et PERCUSSIONS LOINTAINES
# aléatoires mais DÉTERMINISTES (RNG à graine fixe → la boucle reste rigoureusement bouclable, sans
# discontinuité au raccord).
func _make_battle_pad() -> AudioStreamWAV:
	var dur := 9.6                 # 16 temps à 100 BPM (boucle de pouls, 2× plus longue)
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var air := 0.0
	var beat := dur / 16.0         # 16 frappes de tom sur la boucle
	# Impacts LOINTAINS pré-tirés (position + gain) : « la guerre gronde au loin ».
	var far_hits: Array = []
	var far_rng := RandomNumberGenerator.new()
	far_rng.seed = 907
	for k in 7:
		# Jamais dans les 0,4 dernières secondes : la queue doit tenir dans la boucle.
		far_hits.append({"t": far_rng.randf_range(0.2, dur - 1.2),
			"gain": far_rng.randf_range(0.06, 0.16),
			"f": far_rng.randf_range(48.0, 96.0)})
	for i in n:
		var t := float(i) / MIX_RATE
		# Drone grave dissonant (racine D + seconde mineure désaccordée = tension) + battement lent.
		var beatmod := 0.88 + 0.12 * sin(TAU * 0.07 * t)
		var drone := (sin(TAU * 36.7 * t) + 0.45 * sin(TAU * 55.0 * t)
			+ 0.20 * sin(TAU * 58.3 * t) + 0.14 * sin(TAU * 73.4 * t)) * beatmod
		# Tom martelé : impulsion grave à pitch descendant, une par temps.
		var bt := fposmod(t, beat)
		var tom := sin(TAU * lerpf(140.0, 70.0, clampf(bt / 0.05, 0.0, 1.0)) * bt) * exp(-bt * 9.0) * 0.5
		# Percussions LOINTAINES (détonations sourdes) : sub court + souffle très filtré.
		var far := 0.0
		for h in far_hits:
			var dt: float = t - float(h["t"])
			if dt >= 0.0 and dt < 1.0:
				far += sin(TAU * float(h["f"]) * dt) * exp(-dt * 5.0) * float(h["gain"])
		# Couche d'« air » (bruit très filtré, très bas).
		air = lerpf(air, rng.randf_range(-1.0, 1.0), 0.02)
		s[i] = (drone * 0.13 + air * 0.04 + tom * 0.30 + far)
	# Fondu de raccord de boucle.
	var fade := int(MIX_RATE * 0.04)
	for i in fade:
		var g := float(i) / float(fade)
		s[i] *= g
		s[n - 1 - i] *= g
	return _finalize(s, true)


# Conversion float [-1,1] -> PCM 16 bits LE -> AudioStreamWAV (boucle facultative).
func _finalize(samples: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


# Renvoie le nom du bus s'il existe, sinon « Master » (garde-fou : jamais d'« Invalid bus »,
# même si le default_bus_layout n'était pas chargé — même esprit que SettingsManager §8.43).
func _bus_or_master(bus_name: String) -> String:
	return bus_name if AudioServer.get_bus_index(bus_name) != -1 else "Master"
