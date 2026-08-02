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
	"explosion", "chat_ping", "finisher_steel", "finisher_orbital", "finisher_ash",
	# §8.122 : craquement de talkie (chat), tonnerre lointain (éclairs de zone), sting de promotion.
	"radio_crackle", "thunder_far", "promotion"]
const MUSIC_NAME := "menu_ambient"          # nappe des menus
const BATTLE_NAME := "battle_ambient"       # musique tendue de l'arène (§8.66)

# =============================================================================
# MUSIQUE DYNAMIQUE À COUCHES (§8.122, LOT B)
# =============================================================================
# Trois stems SYNCHRONES crossfadés par `war_intensity` (§8.122 LOT A). Mode activé UNIQUEMENT si
# les TROIS fichiers sont présents dans `assets/audio/music/` — sinon on garde STRICTEMENT le
# comportement historique (`battle_ambient`, lecteur unique), sans le moindre log d'erreur.
# ⚠️ CONTRAINTE DE PRODUCTION (cf. assets/audio/README.md) : les 3 fichiers doivent avoir
# EXACTEMENT la même durée et le même BPM — ils jouent en parallèle, pas en séquence.
const BATTLE_LAYER_NAMES := ["battle_base", "battle_mid", "battle_high"]
# Niveau « inaudible » d'une couche coupée (et non `mute` : un tween de dB reste continu).
const LAYER_SILENT_DB := -60.0
# Les couches mid/high jouent légèrement SOUS la base (elles s'ajoutent, elles ne la remplacent pas).
const LAYER_ACTIVE_OFFSET_DB := -2.0
const LAYER_FADE_TIME := 1.5
# Seuils d'ENTRÉE de chaque couche. La sortie se fait HYSTERESIS plus bas : sans cette bande morte,
# une intensité qui oscille autour du seuil ferait « pomper » la couche 2× par seconde.
const LAYER_MID_ON := 0.35
const LAYER_HIGH_ON := 0.65
const LAYER_HYSTERESIS := 0.05
# Resynchronisation DÉFENSIVE : trois AudioStreamPlayer indépendants peuvent dériver (décodage,
# hoquet système). On vérifie périodiquement et on recale mid/high sur la base.
const LAYER_RESYNC_PERIOD := 60.0
const LAYER_RESYNC_TOLERANCE := 0.05

# --- DUCKING (§8.122, LOT B) : la musique s'efface sous un sting, puis revient. ---
const MUSIC_DUCK_DB := -8.0
const MUSIC_DUCK_TIME := 1.2
# Répartition aller/retour du ducking : plongeon RAPIDE (le sting doit passer tout de suite),
# remontée lente (on ne veut pas entendre la musique « revenir »).
const MUSIC_DUCK_ATTACK_RATIO := 0.25

# =============================================================================
# AMBIANCES DIÉGÉTIQUES (§8.122, LOT C) — bus `Ambience`
# =============================================================================
# Boucles d'ambiance sur un bus DÉDIÉ (routé Master, slider « AMBIANCE » dans Paramètres) : elles
# ne doivent NI écraser la musique NI être coupées avec les SFX. Override par `assets/audio/amb/`.
const AMB_BUS := "Ambience"
const AMB_GEIGER := "geiger"
const AMB_WIND := "wind"
const AMB_RADIO_HUB := "radio_hub"
# Niveaux de repos (dB, appliqués AU LECTEUR — le bus et les sliders restent souverains au-dessus).
const AMB_WIND_DB := -18.0        # vent du wasteland : permanent en arène, très en dessous du reste
const AMB_RADIO_HUB_DB := -20.0   # radio militaire du QG : présente, jamais envahissante

# GEIGER — le son SIGNATURE du jeu : son volume suit la DISTANCE (en sauts d'adjacence) entre mes
# territoires et la zone contaminée. Index = distance, valeur = dB ; au-delà, coupé.
# ⚠️ Volontairement PAS piloté par `war_intensity` : le Geiger ne mesure pas la tension globale, il
# mesure « la radioactivité est à N territoires de chez moi ». Le brancher sur l'intensité le ferait
# crépiter en fin de partie même à l'autre bout de la carte — il MENTIRAIT sur ce qu'il indique.
const AMB_GEIGER_DB_BY_DISTANCE := [-6.0, -14.0, -22.0]
const AMB_GEIGER_FADE_TIME := 1.0

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

# --- Musique dynamique à couches (LOT B) ---
# 3 lecteurs bus Music, ou [] tant que le mode couches n'a pas pu démarrer (fichiers absents).
var _battle_layers: Array = []
# Niveau NOMINAL de chaque couche (hors ducking) — le ducking s'y ajoute, il ne l'écrase pas.
var _layer_base_db: Array = []
# Couche audible ? (index 1 = mid, 2 = high ; l'index 0 = base l'est toujours). Porte l'hystérésis.
var _layer_on := [true, false, false]
var _layer_tweens: Array = []
var _layer_resync_timer: Timer = null
# Dernière intensité reçue (info / réévaluation au démarrage des couches).
var _war_intensity := 0.0

# --- Ducking (LOT B) : offset global (≤ 0 dB) appliqué au lecteur unique ET aux couches. ---
var _duck_db := 0.0
var _duck_tween: Tween = null
# Niveau nominal du lecteur unique (piloté par le fondu d'entrée, cf. _fade_music_in).
var _music_base_db := MUSIC_TARGET_DB

# --- Ambiances (LOT C) : nom -> AudioStreamPlayer bouclé sur le bus Ambience. ---
var _amb: Dictionary = {}
var _amb_cache: Dictionary = {}     # nom -> AudioStream (vrai fichier OU synthèse), 1 seule fois
var _amb_tweens: Dictionary = {}    # nom -> Tween de volume en cours
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

	# --- SENSORIEL & IMMERSION (§8.122) : 3 SFX neufs, même mécanique d'override. ---
	# `radio_crackle` (LOT C) : craquement de talkie de 80 ms qui PRÉCÈDE le chat_ping — le message
	# de chat cesse d'être un « bip d'appli » pour devenir une transmission radio.
	_register_sfx("radio_crackle", func(): return _make_radio_crackle())
	# `thunder_far` (LOT D) : détonation sourde et LOINTAINE accompagnant un éclair dans la zone.
	_register_sfx("thunder_far", func(): return _make_thunder_far())
	# `promotion` (LOT F) : arpège bref de montée de division (hub uniquement).
	_register_sfx("promotion", func(): return _make_promotion_sting())

	# --- PACTES DE NON-AGRESSION (§8.123) : 2 SFX neufs, même mécanique d'override. ---
	# `pact_sealed` : quinte JUSTE, montante et courte — la promesse. Volontairement proche du
	# `your_turn` (do→sol) mais une octave plus bas : c'est un engagement, pas une fanfare.
	_register_sfx("pact_sealed", func(): return _make_chord(262.0, 392.0, 0.30))
	# `betrayal` : DISSONANCE brève (triton fa#→do, l'intervalle le plus instable de la gamme),
	# grave et sans résolution. Il doit trancher net avec `pact_sealed` : l'oreille doit
	# comprendre AVANT de lire le bandeau que la promesse vient d'être brisée.
	_register_sfx("betrayal", func(): return _make_chord(370.0, 261.0, 0.55))

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
# §8.122 : coupe d'abord les couches de combat ET l'ambiance d'arène (on quitte l'arène pour le
# hub). Le faire ICI plutôt que dans un `_exit_tree` d'arène couvre TOUS les chemins de sortie
# (victoire, abandon, élimination, coupure réseau) — il n'y en a pas qu'un, et un vent de wasteland
# qui survivrait dans les menus serait un bug difficile à relier à sa cause.
func start_menu_ambient() -> void:
	_stop_battle_layers()
	stop_arena_ambience()
	# ⚠️ Coupe AUSSI la radio du QG. Tous les écrans hub appellent cette fonction, mais SEUL le menu
	# principal rallume la radio juste après (main_menu.gd) : c'est ce qui la confine au QG sans
	# demander à chaque sous-écran de penser à l'éteindre.
	stop_hub_ambience()
	_play_music(MUSIC_NAME)


# Démarre/maintient la MUSIQUE DE COMBAT de l'arène (§8.66). Bascule depuis la musique de menu sans
# coupure brutale (lecteur unique). Idempotent : rappels sans effet si déjà en cours.
# §8.122 (LOT B) : si les TROIS stems `battle_base/mid/high` sont déposés, on passe en MODE COUCHES
# (musique dynamique pilotée par war_intensity) ; sinon comportement historique, à l'identique.
func start_battle_ambient() -> void:
	# La radio du QG n'a rien à faire sur le front (symétrique de start_menu_ambient).
	stop_hub_ambience()
	if _start_battle_layers():
		return
	_play_music(BATTLE_NAME)


func stop_ambient() -> void:
	if _music_player:
		_music_player.stop()
	_stop_battle_layers()


# =============================================================================
# MUSIQUE DYNAMIQUE À COUCHES (§8.122, LOT B)
# =============================================================================

# Tente le mode couches. Renvoie true s'il est actif (déjà en cours OU démarré à l'instant), false
# si les stems manquent — l'appelant retombe alors sur `battle_ambient`. AUCUN log d'erreur : le
# mode « fichiers absents » est le cas NOMINAL tant que la production audio n'a pas livré.
func _start_battle_layers() -> bool:
	if not _battle_layers.is_empty():
		return true
	if not _enabled:
		return false
	var streams: Array = []
	for base_name in BATTLE_LAYER_NAMES:
		var s := _load_override("music", base_name)
		if s == null:
			return false        # un seul manquant → repli intégral, on ne joue JAMAIS 2 stems sur 3.
		_ensure_looped(s)
		streams.append(s)
	# Le lecteur unique se tait : les couches le remplacent intégralement.
	if _music_player:
		_music_player.stop()
	for i in streams.size():
		var p := AudioStreamPlayer.new()
		p.bus = _bus_or_master("Music")
		p.stream = streams[i]
		# Base audible d'emblée, mid/high muettes : c'est `set_war_intensity` qui les ouvrira.
		_layer_base_db.append(MUSIC_TARGET_DB if i == 0 else LAYER_SILENT_DB)
		_layer_tweens.append(null)
		add_child(p)
		_battle_layers.append(p)
		_apply_layer_volume(i)
	# ⚠️ Les trois `play()` doivent partir dans la MÊME frame : les boucles sont alignées à
	# l'échantillon près (contrainte de production), le moindre décalage s'entendrait en flanger.
	for p in _battle_layers:
		p.play()
	_layer_on = [true, false, false]
	# Resynchronisation défensive périodique (dérive de décodage / hoquet système).
	if _layer_resync_timer == null:
		_layer_resync_timer = Timer.new()
		_layer_resync_timer.wait_time = LAYER_RESYNC_PERIOD
		_layer_resync_timer.timeout.connect(_resync_battle_layers)
		add_child(_layer_resync_timer)
	_layer_resync_timer.start()
	# L'intensité courante peut déjà être haute (reprise de partie) : on applique tout de suite.
	set_war_intensity(_war_intensity)
	return true


func _stop_battle_layers() -> void:
	if _layer_resync_timer != null and is_instance_valid(_layer_resync_timer):
		_layer_resync_timer.stop()
	for t in _layer_tweens:
		if t != null and t.is_valid():
			t.kill()
	for p in _battle_layers:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.queue_free()
	_battle_layers.clear()
	_layer_base_db.clear()
	_layer_tweens.clear()
	_layer_on = [true, false, false]


# POINT D'ENTRÉE UNIQUE de la tension côté audio (§8.122 LOT A → LOT B). Appelé par main.gd à
# chaque frame (valeur déjà LISSÉE en amont) : ce corps doit rester trivial. Sans mode couches,
# on ne fait que mémoriser la valeur (elle servira si les stems arrivent en cours de session).
func set_war_intensity(v: float) -> void:
	_war_intensity = clampf(v, 0.0, 1.0)
	if _battle_layers.size() < 3:
		return
	_update_layer(1, LAYER_MID_ON)
	_update_layer(2, LAYER_HIGH_ON)


# Ouvre/ferme une couche selon l'intensité, AVEC HYSTÉRÉSIS : on entre au-dessus de `on_threshold`,
# on ne sort qu'en repassant sous `on_threshold - LAYER_HYSTERESIS`. Sans cette bande morte, une
# intensité qui vibre autour du seuil déclencherait un fondu 1,5 s toutes les deux frames.
func _update_layer(index: int, on_threshold: float) -> void:
	var want_on: bool = bool(_layer_on[index])
	if not want_on and _war_intensity > on_threshold:
		want_on = true
	elif want_on and _war_intensity < on_threshold - LAYER_HYSTERESIS:
		want_on = false
	if want_on == bool(_layer_on[index]):
		return
	_layer_on[index] = want_on
	_fade_layer(index, (MUSIC_TARGET_DB + LAYER_ACTIVE_OFFSET_DB) if want_on else LAYER_SILENT_DB)


# Fondu du niveau NOMINAL d'une couche (le ducking s'y ajoute par-dessus, cf. _apply_layer_volume).
func _fade_layer(index: int, target_db: float) -> void:
	if index < 0 or index >= _battle_layers.size():
		return
	var t = _layer_tweens[index]
	if t != null and t.is_valid():
		t.kill()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(db: float) -> void:
		_layer_base_db[index] = db
		_apply_layer_volume(index), float(_layer_base_db[index]), target_db, LAYER_FADE_TIME)
	_layer_tweens[index] = tw


# Recale mid/high sur la position de lecture de la BASE si elles ont dérivé. Log silencieux (print) :
# c'est un correctif interne, jamais une erreur utilisateur.
func _resync_battle_layers() -> void:
	if _battle_layers.size() < 3 or not is_instance_valid(_battle_layers[0]):
		return
	var ref_pos: float = _battle_layers[0].get_playback_position()
	for i in range(1, _battle_layers.size()):
		var p = _battle_layers[i]
		if not is_instance_valid(p) or not p.playing:
			continue
		if absf(p.get_playback_position() - ref_pos) > LAYER_RESYNC_TOLERANCE:
			p.seek(ref_pos)
			print("[AudioManager] resynchronisation de la couche %s (dérive > %.0f ms)"
				% [BATTLE_LAYER_NAMES[i], LAYER_RESYNC_TOLERANCE * 1000.0])


# DUCKING (LOT B) : la musique plonge sous un sting puis remonte. Appelé sur les moments qui
# doivent PERCER (mise à mort de héros, PROTOCOLE FINAL, révélation théâtrale §8.121). Fonctionne
# dans LES DEUX modes — l'offset s'applique au lecteur unique comme aux couches actives.
func duck_music(amount_db: float = MUSIC_DUCK_DB, duration: float = MUSIC_DUCK_TIME) -> void:
	if not _enabled:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	var down := maxf(duration * MUSIC_DUCK_ATTACK_RATIO, 0.05)
	_duck_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_duck_tween.tween_method(_set_duck_db, _duck_db, minf(amount_db, 0.0), down)
	_duck_tween.tween_method(_set_duck_db, minf(amount_db, 0.0), 0.0, maxf(duration - down, 0.05))


func _set_duck_db(db: float) -> void:
	_duck_db = db
	_apply_music_volume()
	for i in _battle_layers.size():
		_apply_layer_volume(i)


func _apply_music_volume() -> void:
	if is_instance_valid(_music_player):
		_music_player.volume_db = _music_base_db + _duck_db


func _apply_layer_volume(index: int) -> void:
	if index < 0 or index >= _battle_layers.size():
		return
	var p = _battle_layers[index]
	if is_instance_valid(p):
		p.volume_db = float(_layer_base_db[index]) + _duck_db


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

# §8.122 (LOT B) : le fondu pilote désormais le niveau NOMINAL `_music_base_db` (et non plus
# `volume_db` en direct) — sinon un ducking déclenché PENDANT le fondu serait écrasé par lui à la
# frame suivante. Le volume réel du lecteur = nominal + offset de ducking (_apply_music_volume).
func _fade_music_in() -> void:
	if _music_player == null:
		return
	if _music_fade != null and _music_fade.is_valid():
		_music_fade.kill()
	_music_base_db = MUSIC_FADE_FROM_DB
	_apply_music_volume()
	_music_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_music_fade.tween_method(func(db: float) -> void:
		_music_base_db = db
		_apply_music_volume(), MUSIC_FADE_FROM_DB, MUSIC_TARGET_DB, MUSIC_FADE_TIME)


# =============================================================================
# AMBIANCES DIÉGÉTIQUES (§8.122, LOT C) — bus `Ambience`
# =============================================================================
# API publique :
#   start_arena_ambience() / stop_arena_ambience()   — vent permanent + Geiger (arène)
#   set_zone_proximity(distance)                     — volume du Geiger (0 = chez moi, -1 = coupé)
#   start_hub_ambience()   / stop_hub_ambience()     — radio militaire du QG (menu principal SEUL)

# Vent du wasteland + Geiger (muet tant qu'aucune proximité n'est annoncée). Idempotent.
func start_arena_ambience() -> void:
	_play_amb(AMB_WIND, AMB_WIND_DB)
	_play_amb(AMB_GEIGER, LAYER_SILENT_DB)

func stop_arena_ambience() -> void:
	_stop_amb(AMB_WIND)
	_stop_amb(AMB_GEIGER)

# Radio militaire du QG — menu principal UNIQUEMENT (elle s'arrête en entrant dans un sous-écran).
func start_hub_ambience() -> void:
	_play_amb(AMB_RADIO_HUB, AMB_RADIO_HUB_DB)

func stop_hub_ambience() -> void:
	_stop_amb(AMB_RADIO_HUB)

# GEIGER PROPORTIONNEL À LA MENACE. `distance` = nombre de sauts d'adjacence entre MES territoires
# et le territoire contaminé le plus proche (0 = un des miens est DANS la zone). Toute valeur
# négative ou ≥ la taille de la table coupe le Geiger. Fondu d'une seconde entre paliers : le
# danger « s'approche » à l'oreille au lieu de sauter d'un cran.
func set_zone_proximity(distance: int) -> void:
	var db := LAYER_SILENT_DB
	if distance >= 0 and distance < AMB_GEIGER_DB_BY_DISTANCE.size():
		db = float(AMB_GEIGER_DB_BY_DISTANCE[distance])
	_fade_amb(AMB_GEIGER, db, AMB_GEIGER_FADE_TIME)

# Démarre (ou réveille) une boucle d'ambiance à un niveau donné. Le flux est chargé/synthétisé UNE
# fois puis mis en cache. Idempotent : rappeler ne redémarre pas la boucle en cours.
func _play_amb(amb_name: String, db: float) -> void:
	var stream := _ensure_amb_stream(amb_name)
	if not _enabled or stream == null:
		return
	var p: AudioStreamPlayer = _amb.get(amb_name)
	if p == null or not is_instance_valid(p):
		p = AudioStreamPlayer.new()
		p.bus = _bus_or_master(AMB_BUS)
		p.stream = stream
		add_child(p)
		_amb[amb_name] = p
	p.volume_db = db
	if not p.playing:
		p.play()

func _stop_amb(amb_name: String) -> void:
	var t = _amb_tweens.get(amb_name)
	if t != null and t.is_valid():
		t.kill()
	_amb_tweens.erase(amb_name)
	var p: AudioStreamPlayer = _amb.get(amb_name)
	if p != null and is_instance_valid(p):
		p.stop()

# Fondu du volume d'une ambiance DÉJÀ démarrée (sans effet si elle ne tourne pas : on ne veut pas
# qu'un `set_zone_proximity` reçu hors arène ressuscite le Geiger).
func _fade_amb(amb_name: String, target_db: float, duration: float) -> void:
	var p: AudioStreamPlayer = _amb.get(amb_name)
	if p == null or not is_instance_valid(p) or not p.playing:
		return
	if absf(p.volume_db - target_db) < 0.01:
		return
	var t = _amb_tweens.get(amb_name)
	if t != null and t.is_valid():
		t.kill()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "volume_db", target_db, duration)
	_amb_tweens[amb_name] = tw

# Flux d'une ambiance : vrai fichier (`assets/audio/amb/<nom>.{ogg,wav,mp3}`) prioritaire, sinon
# placeholder synthétisé. Mis en cache. ⚠️ La synthèse tourne MÊME en headless (`_enabled` faux) :
# c'est elle qu'on valide en CLI — seule la LECTURE est désactivée.
func _ensure_amb_stream(amb_name: String) -> AudioStream:
	if _amb_cache.has(amb_name):
		return _amb_cache[amb_name]
	var stream := _load_override("amb", amb_name)
	if stream == null:
		match amb_name:
			AMB_GEIGER: stream = _make_geiger()
			AMB_WIND: stream = _make_wind()
			AMB_RADIO_HUB: stream = _make_radio_hub()
			_: return null
	_ensure_looped(stream)
	_amb_cache[amb_name] = stream
	return stream


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
	# §8.122 : couches de musique dynamique (LOT B) + boucles d'ambiance (LOT C).
	_stop_battle_layers()
	for amb_name in _amb.keys():
		var ap = _amb[amb_name]
		if is_instance_valid(ap):
			ap.stop()
			ap.stream = null
	_amb.clear()
	_amb_cache.clear()
	_amb_tweens.clear()
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


# =============================================================================
# SYNTHÈSE DES AMBIANCES (§8.122, LOT C) — placeholders bouclables
# =============================================================================
# Même contrat que les SFX : ces générateurs ne servent QUE tant qu'aucun vrai fichier n'est déposé
# dans `assets/audio/amb/`. Tous les RNG sont à GRAINE FIXE → la boucle est identique à chaque
# lancement, donc rigoureusement bouclable (une graine aléatoire produirait un raccord audible).

# GEIGER — le son signature. Clics APÉRIODIQUES suivant un processus de POISSON (intervalles
# exponentiels), chacun étant un burst de bruit de 2 à 4 ms. C'est l'irrégularité qui fait
# « compteur Geiger » : un train de clics régulier sonnerait comme un métronome.
# `density` = nombre moyen de clics par seconde (paramétrable, cf. cahier des charges).
func _make_geiger(density: float = 14.0) -> AudioStreamWAV:
	var dur := 4.0
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3141
	var t := 0.0
	while true:
		# Intervalle exponentiel : -ln(u) / λ. Le plancher 1e-6 évite un log(0) = -inf.
		t += -log(maxf(rng.randf(), 1e-6)) / maxf(density, 0.1)
		# Marge de fin : le burst le plus long (4 ms) doit tenir AVANT la jointure de boucle.
		if t > dur - 0.01:
			break
		var start := int(t * MIX_RATE)
		var burst := maxi(int(MIX_RATE * rng.randf_range(0.002, 0.004)), 4)
		var gain := rng.randf_range(0.45, 1.0)
		for k in burst:
			var i := start + k
			if i >= n:
				break
			# Décroissance sur la durée du burst : un « tac » sec, jamais un souffle.
			var env := exp(-float(k) / float(burst) * 5.0)
			s[i] += rng.randf_range(-1.0, 1.0) * env * gain * 0.65
	return _finalize(s, true)


# VENT DU WASTELAND — bruit blanc TRÈS filtré (passe-bas 1 pôle) modulé par deux LFO lents
# (respiration + rafales). Le gain compense la perte du filtre ; le clamp de `_finalize` fait
# garde-fou.
func _make_wind(dur: float = 8.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6060
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.03)
		# Respiration lente (0,05 Hz) × rafales (0,17 Hz) — jamais en phase, donc jamais de cycle
		# perceptible malgré une boucle courte.
		var breath := 0.55 + 0.45 * sin(TAU * 0.05 * t)
		var gust := 0.75 + 0.25 * sin(TAU * 0.17 * t + 2.1)
		s[i] = lp * breath * gust * 4.2
	_loop_seam(s, 0.08)
	return _finalize(s, true)


# RADIO MILITAIRE DU QG — souffle de porteuse + bips épars + fragments de « voix » (deux formants
# sinusoïdaux sous enveloppe courte). Volontairement INDISTINCT : on doit croire entendre un
# joueur au loin, jamais comprendre un mot (aucune langue → aucun problème d'i18n).
func _make_radio_hub(dur: float = 10.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1204
	# Évènements pré-tirés (position, type) : bips courts et fragments de voix.
	var events: Array = []
	var ev_rng := RandomNumberGenerator.new()
	ev_rng.seed = 77
	for k in 5:
		events.append({"t": ev_rng.randf_range(0.3, dur - 1.4), "beep": true,
			"f": ev_rng.randf_range(900.0, 1500.0), "gain": ev_rng.randf_range(0.05, 0.11)})
	for k in 4:
		events.append({"t": ev_rng.randf_range(0.3, dur - 1.4), "beep": false,
			"f": ev_rng.randf_range(210.0, 330.0), "gain": ev_rng.randf_range(0.06, 0.12)})
	var hiss := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		# Souffle de porteuse : bruit passe-bandé « à la radio » (filtré deux fois, très bas).
		hiss = lerpf(hiss, rng.randf_range(-1.0, 1.0), 0.25)
		var v := hiss * 0.055
		for e in events:
			var dt: float = t - float(e["t"])
			if dt < 0.0:
				continue
			if bool(e["beep"]):
				if dt < 0.09:
					v += sin(TAU * float(e["f"]) * dt) * exp(-dt * 26.0) * float(e["gain"])
			elif dt < 0.55:
				# « Voix » : fondamentale + 2 formants, enveloppe en cloche + trémolo de syllabe.
				var env := sin(PI * dt / 0.55)
				var syl := 0.6 + 0.4 * sin(TAU * 7.0 * dt)
				var f: float = float(e["f"])
				var body := sin(TAU * f * dt) + 0.5 * sin(TAU * f * 3.4 * dt) \
					+ 0.3 * sin(TAU * f * 7.1 * dt)
				v += body * env * syl * float(e["gain"]) * 0.5
		s[i] = v
	_loop_seam(s, 0.06)
	return _finalize(s, true)


# CRAQUEMENT DE TALKIE (SFX one-shot, LOT C) : 80 ms de bruit filtré haché par des sauts
# d'amplitude brutaux — c'est la DISCONTINUITÉ qui fait « transmission », pas le timbre.
func _make_radio_crackle() -> AudioStreamWAV:
	var dur := 0.08
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var lp := 0.0
	var gate := 1.0
	for i in n:
		var t := float(i) / MIX_RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.45)
		# Porte aléatoire : re-tirée ~toutes les 3 ms → hachures irrégulières.
		if i % 130 == 0:
			gate = rng.randf_range(0.15, 1.0)
		s[i] = lp * gate * exp(-t * 14.0) * 0.42
	return _finalize(s)


# TONNERRE LOINTAIN (SFX one-shot, LOT D) : sub très grave + grondement de bruit fortement filtré,
# attaque MOLLE (l'orage est loin, il n'y a pas de claquement). Joué à -24 dB par l'appelant.
func _make_thunder_far() -> AudioStreamWAV:
	var dur := 1.6
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8421
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		# Attaque en 120 ms (pas de transitoire), longue traîne.
		var env := minf(t / 0.12, 1.0) * exp(-t * 2.2)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.02)
		var rumble := lp * 5.0
		var sub := sin(TAU * lerpf(42.0, 26.0, minf(t / 0.8, 1.0)) * t) * 0.45
		s[i] = (rumble + sub) * env * 0.55
	return _finalize(s)


# STING DE PROMOTION (SFX one-shot, LOT F) : arpège ascendant bref (quinte + octave) sur un lit de
# scintillement. Court (0,7 s) — c'est une ponctuation, pas une fanfare.
func _make_promotion_sting() -> AudioStreamWAV:
	var dur := 0.7
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [523.25, 659.25, 783.99, 1046.50]   # do — mi — sol — do (majeur, montant)
	var step := 0.11
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for k in notes.size():
			var dt := t - float(k) * step
			if dt < 0.0:
				continue
			var f: float = float(notes[k])
			v += (sin(TAU * f * dt) + 0.25 * sin(TAU * f * 2.0 * dt)) \
				* exp(-dt * 7.0) * minf(dt * 300.0, 1.0) * 0.22
		s[i] = v
	return _finalize(s)


# Fondu de raccord de boucle : atténue les `seconds` premières et dernières secondes pour masquer
# la discontinuité d'un générateur à ÉTAT (filtre récursif) dont la fin ne rejoint pas le début.
func _loop_seam(samples: PackedFloat32Array, seconds: float) -> void:
	@warning_ignore("integer_division")  # division entière VOULUE : un nombre d'échantillons.
	var fade := mini(int(MIX_RATE * seconds), samples.size() / 2)
	for i in fade:
		var g := float(i) / float(fade)
		samples[i] *= g
		samples[samples.size() - 1 - i] *= g


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
