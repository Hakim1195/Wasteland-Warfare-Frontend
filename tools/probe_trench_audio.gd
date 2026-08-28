extends Node

# =================================================================================================
# SONDE §8.151 (LOT A) — AUDIO v2 : familles de variantes, rotation, jitter, replis, câblage.
#
# ╔═ CE QU'ELLE PROUVE ═══════════════════════════════════════════════════════════════════════════╗
# ║  a. ROTATION : 50 lectures de `trench_shot` via le VRAI `play_sfx` → jamais deux fois la même  ║
# ║     variante d'affilée ET les 6 utilisées (lu dans `_variant_last`, l'état du manager).        ║
# ║  b. CLÉS INCONNUES : `play_sfx("cle_inconnue")` ne touche RIEN (pool, registres) — le          ║
# ║     comportement historique, à l'identique. Et une clé de MENU garde son pitch nominal 1.0.    ║
# ║  c. JITTER : le `pitch_scale` posé sur le lecteur est borné à ± 3 % — et il VARIE vraiment.    ║
# ║  d. CÂBLAGE DUEL (patron falseshot) : la culasse s'arme sur un tir RÉEL, jamais sur un clic    ║
# ║     refusé (§8.141.9), et part quand `_clock` franchit la porte de cadence ; le whizz part sur ║
# ║     l'`impact` de balle adverse MANQUÉE (damage 0) et jamais sur une touche ni une grenade.    ║
# ║  e. VAGUE 2bis (§3.6 + §4bis.4) : les 4 VOIX PAR ARME tournent comme les autres familles ; la  ║
# ║     clé de détonation suit l'arme LUE (état/événement) avec REPLI voix générique (sabotage :   ║
# ║     famille retirée du registre → repli) ; la RAFALE se présente PAR PROJECTILE — crans locaux ║
# ║     au `burst_gap_ticks` du REGISTRE, crans adverses sur les `launch_tick` SERVEUR, un refus   ║
# ║     ne planifie RIEN ; le télégraphe CONDOR adverse JOUE `trench_laser_warn` UNE fois par      ║
# ║     visée, sur le MÊME signal que son rendu — et jamais pour MON propre laser.                 ║
# ║  f. CORRECTIFS (§8.151 2bis) : le télégraphe DURE la fenêtre de danger LUE dans l'état         ║
# ║     (`laser_fire_tick`) et se TAIT à l'extinction du rayon ; le clic du CONDOR ne joue RIEN de ║
# ║     balistique (le tir se voit et s'entend UNE fois, à l'événement `fire` du serveur) ; un     ║
# ║     échange de rafales ne VOLE plus aucune voix du pool — avec son contre-essai (pool ramené   ║
# ║     à 6, la taille d'avant → il vole).                                                         ║
# ║  g. CORRECTIFS (2ᵉ tour) : les TRAÇANTES d'une rafale adverse ne s'affichent plus d'un bloc —  ║
# ║     une par projectile, au tick de SON `launch_tick` — sans effacer pour autant le tir simple  ║
# ║     ni le marqueur de grenade ; et l'événement `fire` d'une arme TÉLÉGRAPHIÉE ne repousse plus ║
# ║     la porte de cadence de `laser_lead_ticks` (le clac de culasse cessait d'être à l'heure).   ║
# ║  h. DURCISSEMENT (vague 2ter) : les barèmes de rafale des fixtures sont HORS PRODUCTION, si    ║
# ║     bien que « registre », « launch_tick serveur » et « minuterie en dur » donnent trois       ║
# ║     résultats DIFFÉRENTS — et l'HEURE de chaque cran est contrôlée, pas seulement leur nombre. ║
# ║     Plus le REPLI registre du chemin adverse (état muet), qui n'était gardé par rien.          ║
# ║  i. DURCISSEMENT (vague 2ter) : l'AMPLITUDE du feel sous rafale est MESURÉE — le cran suiveur  ║
# ║     kicke strictement MOINS que le premier (§4bis.4), le punch de FOV est POSÉ et jamais       ║
# ║     empilé, et le roulis livré à la caméra tient sous le plafond du cahier (±0,3°) même à      ║
# ║     intensité F10 maximale. Aucun de ces trois faits n'était gardé par un seul contrôle.       ║
# ║  j. DURCISSEMENT (2ᵉ tour) : le RYTHME lui-même est éprouvé. Les fixtures ANNONCENT un         ║
# ║     `tick_rate_hz` HORS production (8 Hz, puis 13 Hz pour le contre-essai), et elles le font   ║
# ║     par `_on_init` — le seul site où le client lit ce champ. La sonde n'écrit plus JAMAIS      ║
# ║     `_tick_rate`, et tous ses attendus dérivent du LITTÉRAL de la fixture : un diviseur en     ║
# ║     dur (20, 10 ou même 8) rougit. Le reste du barème (cadences, dispersions, chargeurs,       ║
# ║     télégraphe) est lui aussi hors production, et le CHACAL (rafale ×2) est enfin exercé.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ HEADLESS : `AudioManager._enabled` est faux (pilote Dummy) — la banque et la mécanique
# tournent, seule la LECTURE est coupée. La sonde force `_enabled = true` LE TEMPS DES CONTRÔLES
# (un `play()` sur le pilote Dummy est inoffensif) pour exercer le VRAI chemin de `play_sfx`,
# puis le remet. Jamais d'assert (il bloquerait le harnais) : prints PASS/FAIL + quit() propre.
#
# Lancement : & <godot_console> --headless --path frontend res://tools/probe_trench_audio.tscn
# =================================================================================================

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")

# Les comptes ATTENDUS des familles livrées par la vague 1 (§3.3) puis par la vague 2bis (§3.6 :
# les 4 voix par arme — frelon ×6, la rafale consomme vite le round-robin) — c'est l'inventaire du
# bon de commande, pas une relecture du disque : si l'usine perd une variante, la sonde rougit.
const EXPECTED_FAMILIES := {"trench_shot": 6, "trench_whizz": 4, "trench_explosion_near": 3,
	"trench_explosion_far": 3, "trench_shell": 3, "trench_step": 4,
	"trench_shot_vipere": 4, "trench_shot_frelon": 6, "trench_shot_chacal": 4,
	"trench_shot_condor": 4}
# Les familles de la vague 2bis seules — la section 6 fait tourner leur rotation une à une.
const WEAPON_FAMILIES := ["trench_shot_vipere", "trench_shot_frelon", "trench_shot_chacal",
	"trench_shot_condor"]

# ╔═ ⚠️ DURCISSEMENT VAGUE 2ter — LES BARÈMES DE FIXTURE SONT VOLONTAIREMENT HORS PRODUCTION ═════╗
# ║ 🩸 LE DÉFAUT QUE CES DEUX CONSTANTES SOLDENT. Jusqu'ici les fixtures des sections 8, 9 et 13   ║
# ║ injectaient `burst_gap_ticks: 2` et des `launch_tick` espacés de 2 ticks — EXACTEMENT le       ║
# ║ barème de production de FRELON et de CHACAL. Un « 2 » recopié en dur dans le code de jeu, ou   ║
# ║ une minuterie fixe de 0,1 s, produisaient donc les MÊMES attendus qu'une lecture du registre   ║
# ║ et qu'une lecture des `launch_tick` serveur : la garde ne pouvait PAS les distinguer.          ║
# ║ Mesuré par la boucle de critique, sabotages à l'appui :                                        ║
# ║  • `gap = 2.0` en dur dans `_local_fire_feedback`  → la sonde restait VERTE (91 PASS / 0 FAIL) ║
# ║  • `launch_tick` serveur ignorés, minuterie 0,1 s → la sonde restait VERTE (91 PASS / 0 FAIL)  ║
# ║ REMÈDE : des espacements qui n'existent NULLE PART en production. Aucun chiffre en dur ne peut ║
# ║ plus coïncider avec l'attendu — et les trois sources possibles (registre / launch_tick /       ║
# ║ minuterie) donnent trois résultats DIFFÉRENTS, donc discernables (à 8 Hz, cf. plus bas) :      ║
# ║      registre 5 ticks → +0,625 / +1,250 s   ·   launch serveur → +0,375 / +0,875 s             ║
# ║      minuterie en dur → +0,100 / +0,200 s (le barème de production : ce qu'on veut voir échouer)║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# L'espacement de rafale INJECTÉ au registre de test (le registre RÉEL dit 2 pour frelon/chacal).
const PROBE_GAP_TICKS := 5
# Les départs SERVEUR d'une rafale de test, en ticks depuis le tick de l'état (prod : 0, 2, 4).
# ⚠️ Volontairement IRRÉGULIERS (3 puis 4 ticks) : même une minuterie « au bon pas » se trahirait.
const PROBE_LAUNCH_OFFSETS := [0, 3, 7]

# ╔═ 🩸 DURCISSEMENT 2ter, 2ᵉ TOUR — LE TROISIÈME FACTEUR : LE RYTHME ANNONCÉ PAR LE SERVEUR ══════╗
# ║ CE QUE LE TOUR PRÉCÉDENT AVAIT LAISSÉ PASSER. Un cran de rafale vaut `ticks / tick_rate` :     ║
# ║ trois facteurs. Le durcissement en avait sorti DEUX de la production (l'espacement du registre ║
# ║ et les `launch_tick`) et laissé le TROISIÈME — le diviseur — à sa valeur de production (20 Hz),║
# ║ que la sonde s'écrivait ELLE-MÊME (`duel._tick_rate = 20.0`) sans jamais passer par `_on_init`,║
# ║ seul site où le client lit `tick_rate_hz`. Elle dérivait ensuite ses attendus de ce champ       ║
# ║ MÊME qu'elle contrôlait : l'anti-patron que son propre pavé condamne pour ROLL_CAP_DEG.        ║
# ║ Mesuré par la boucle de critique, sabotages à l'appui — la sonde restait VERTE (114/0) sur :   ║
# ║  • `… / 20.0` en dur dans le chemin LOCAL (`_local_fire_feedback`) ;                           ║
# ║  • `… / 20.0` en dur dans le chemin ADVERSE (`_schedule_burst_followups`) ;                    ║
# ║  • `_tick_rate = 10.0` en dur (le client cesse de lire le rythme annoncé) ;                    ║
# ║  • les SIX `"tick_rate_hz": 20` des fixtures remplacés par 7 — champ purement DÉCORATIF.       ║
# ║ REMÈDE, en trois pièces indissociables :                                                       ║
# ║  1. le rythme ANNONCÉ est hors production (8 Hz — ni les 20 Hz de la sim, ni le repli 10 Hz    ║
# ║     de `_on_init`, ni un « 2× moins vite » qui tomberait sur 10) ;                             ║
# ║  2. il entre par `_on_init` et par lui seul — la sonde n'écrit PLUS `duel._tick_rate` (grep :  ║
# ║     aucune écriture dans ce fichier), et `_init_duel` contrôle que le client l'a bien LU ;     ║
# ║  3. les attendus dérivent du LITTÉRAL ci-dessous, jamais de `duel._tick_rate`.                 ║
# ║ Et parce qu'un rythme unique s'apprend par cœur (`_tick_rate = 8.0` en dur passerait), le      ║
# ║ § 9quater re-annonce un SECOND rythme et vérifie que les crans SUIVENT : les mêmes 5 ticks     ║
# ║ valent 0,625 s à 8 Hz et 0,385 s à 13 Hz. Aucun diviseur constant ne satisfait les deux.       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const PROBE_TICK_RATE_HZ := 8.0        # production : 20 · repli du client si le champ manque : 10
const PROBE_TICK_RATE_ALT := 13.0      # le SECOND rythme annoncé (contre-essai du § 9quater)
# Le télégraphe du CONDOR de test (registre RÉEL : 10 ticks). 3 ticks / 8 Hz = 0,375 s : la fenêtre
# reste dans les bornes de pitch du manager (0,62 s de fichier → 1,653 ; doublée → 0,827).
const PROBE_LEAD_TICKS := 3

# ╔═ ⚠️ LE BARÈME COMPLET DES FIXTURES — PLUS UNE SEULE VALEUR DE PRODUCTION ═════════════════════╗
# ║ 🩸 LE DÉFAUT QUE CETTE TABLE SOLDE. Les fixtures recopiaient encore `cooldown_ticks` 18/24/50, ║
# ║ `dispersion_deg` 0,30/0,85, `mag_size` 8/24 et `laser_lead_ticks` 10 du registre serveur — et  ║
# ║ DEUX attendus étaient écrits en dur sur ce barème (`10.9` = 10,0 + 18/20 · `600.9`). Une       ║
# ║ cadence recopiée en dur dans `_local_fire_feedback` — le défaut BLOQUANT du §1.9 du cahier —   ║
# ║ y serait donc restée invisible. Ici plus rien ne coïncide : chaque attendu se dérive de CETTE  ║
# ║ table et du rythme annoncé ci-dessus. (Registre RÉEL, `trench_sim.py` l.158-215, pour mémoire :║
# ║ vipère 18/0,30/8 · frelon 3×2 24/0,85/24 · chacal 2×2 16/0,45/20 · condor 50/0,0/4, lead 10.)  ║
# ║ ⚠️ Le CHACAL entre ici pour la première fois : jusqu'à cette passe, TOUTES les fixtures de     ║
# ║ rafale passaient par le FRELON (×3) — le cas `rounds == 2` n'était couvert par rien.           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const PROBE_WEAPONS := {
	"vipere": {"burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 7, "flight_ticks": 1,
		"laser_lead_ticks": 0, "dispersion_deg": 0.11, "mag_size": 6, "reload_ticks": 13},
	"frelon": {"burst": 3, "burst_gap_ticks": PROBE_GAP_TICKS, "cooldown_ticks": 13,
		"flight_ticks": 1, "laser_lead_ticks": 0, "dispersion_deg": 0.42, "mag_size": 17,
		"reload_ticks": 21},
	"chacal": {"burst": 2, "burst_gap_ticks": PROBE_GAP_TICKS, "cooldown_ticks": 9,
		"flight_ticks": 1, "laser_lead_ticks": 0, "dispersion_deg": 0.22, "mag_size": 11,
		"reload_ticks": 19},
	"condor": {"burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 29, "flight_ticks": 1,
		"laser_lead_ticks": PROBE_LEAD_TICKS, "dispersion_deg": 0.07, "mag_size": 3,
		"reload_ticks": 27},
}
# ╔═ ⚠️ LE PLAFOND DU CAHIER (§4.2 : « roulis caméra ± 0,3° ») — LA SPÉCIFICATION, PAS LA CONSTANTE ═╗
# ║ Volontairement PAS relu dans `trench_fp.gd` : une garde qui relit la valeur qu'elle contrôle ne ║
# ║ contrôle rien (lever `ROLL_CAP_DEG` lèverait l'attendu avec lui, et le contrôle resterait vert).║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
const CAHIER_ROLL_CAP_DEG := 0.3

var _fails: Array = []


func _ok(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[PASS]  " if cond else "[FAIL]", label,
		("   | " + detail) if detail != "" else ""])


# ⚠️ §8.151 (2bis, correctif) — ON NE DÉDUIT PLUS LE LECTEUR D'UNE ARITHMÉTIQUE. Cette sonde
# lisait `pool[(_sfx_next - 1) % taille]` et comptait les lectures par `_sfx_next == avant + 1` :
# des identités du round-robin PUR, qui prouvaient le bouclage du curseur et rien d'autre — jamais
# le VOL d'une voix encore en cours (le défaut réel), et fausses dès que l'allocation cherche un
# lecteur LIBRE au lieu du suivant. On lit donc désormais ce que le manager DÉCLARE : l'index du
# dernier lecteur servi, et un compteur MONOTONE de lectures (`(avant + 8) % 6` et `(avant + 2) % 6`
# étaient indiscernables — un compteur, lui, compte).
func _last_player() -> AudioStreamPlayer:
	var index: int = int(AudioManager._sfx_last)
	if index < 0 or index >= AudioManager._sfx_players.size():
		return AudioManager._sfx_players[0]
	return AudioManager._sfx_players[index]


# Le nombre de lectures réellement parties depuis le manager (compteur monotone).
func _plays() -> int:
	return int(AudioManager._sfx_plays)


# Les échéances de la file de crans, en SECONDES depuis une base — le détail lisible d'un rouge
# (« +0,100 / +0,200 » au lieu de « +0,250 / +0,500 » nomme le défaut sans qu'on relise le code).
func _dues(duel, base: float) -> Array:
	var out: Array = []
	for cran in duel._burst_queue:
		out.append("+%.3f" % (float(cran["due"]) - base))
	return out


# Une CONSTANTE du script de PRODUCTION, lue dans sa table de constantes — jamais recopiée ici.
# Absente = rouge explicite : une garde qui lit un fallback silencieux ne garde rien. (Le passage
# par une variable `Script` est obligatoire : GDScript refuse `get_script_constant_map()` appelé
# sur la CLASSE — et un `DuelScript.MA_CONST` direct casserait le PARSE si la constante changeait
# de nom, ce qui pendrait le harnais au lieu de le faire rougir.)
func _duel_const(const_name: String) -> float:
	var production: Script = DuelScript
	var map: Dictionary = production.get_script_constant_map()
	if not map.has(const_name):
		_ok("constante %s introuvable dans trench_fp.gd" % const_name, false)
		return 0.0
	return float(map[const_name])


# ╔═ LE MOUCHARD DE FEEL (durcissement vague 2ter) ═══════════════════════════════════════════════╗
# ║ ⚠️ POURQUOI UN MOUCHARD PLUTÔT QUE `_world._feel_roll_deg`. `trench_fp.gd` borne le roulis À LA ║
# ║ SORTIE (`set_camera_feel(clampf(_cam_roll.value, ±ROLL_CAP_DEG), …)`) et le monde le re-borne   ║
# ║ CHEZ LUI (`FEEL_ROLL_CAP_DEG`). Lire l'état du monde ne dirait donc RIEN du plafond de l'hôte : ║
# ║ le second filet masquerait la disparition du premier, et le contrôle resterait vert. On        ║
# ║ intercepte ce que l'hôte PUBLIE, en amont du filet. `_world` est déclaré `Control` : un Control ║
# ║ mouchard s'y substitue par duck-typing le temps de la mesure, puis le vrai monde revient.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
class FeelSpy extends Control:
	var rolls: Array = []
	var fovs: Array = []
	var shots := 0

	func set_camera_feel(roll_deg: float, fov_offset_deg: float) -> void:
		rolls.append(roll_deg)
		fovs.append(fov_offset_deg)

	func shake_screen_px() -> Vector2:
		return Vector2.ZERO

	func notify_local_shot(_pos: int, _yaw: float, _pitch: float, _flight_s: float,
			_count: int) -> void:
		shots += 1

	func notify_enemy_fire(_pos: int) -> void:
		pass

	func max_abs_roll() -> float:
		var m := 0.0
		for r in rolls:
			m = maxf(m, absf(float(r)))
		return m

	func max_fov() -> float:
		var m := 0.0
		for f in fovs:
			m = maxf(m, float(f))
		return m


# Le ⚙ `laser_lead_ticks` d'une arme, LU dans le registre injecté au duel — jamais recopié.
func _lead_ticks(duel, weapon_id: String) -> int:
	for weapon in duel._rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			return int(weapon.get("laser_lead_ticks", 0))
	return 0


# ╔═ L'ENTRÉE PAR LA PORTE DU SERVEUR — `_on_init`, ET RIEN D'AUTRE ══════════════════════════════╗
# ║ TOUTE fixture de cette sonde passe par ici. `_on_init` est le SEUL site où `trench_fp.gd` lit  ║
# ║ `tick_rate_hz` (l.472) ; en écrivant `duel._tick_rate` à la main, la sonde court-circuitait    ║
# ║ cette lecture et rendait le champ des fixtures DÉCORATIF. Elle l'ANNONCE désormais, comme le   ║
# ║ serveur, puis elle contrôle que le client l'a LU.                                              ║
# ║ ⚠️ `geometry` est volontairement ABSENT du paquet : `_check_geometry_match` rend la main tout   ║
# ║ de suite sur un dictionnaire vide (pas de `push_error` parasite dans le harnais).              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _probe_rules(ids: Array, rate: float) -> Dictionary:
	var weapons: Array = []
	for id in ids:
		var w: Dictionary = (PROBE_WEAPONS[str(id)] as Dictionary).duplicate(true)
		w["id"] = str(id)
		weapons.append(w)
	return {"tick_rate_hz": rate, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": weapons}


func _init_duel(duel, ids: Array, rate: float, where: String) -> void:
	duel._on_init({"rules": _probe_rules(ids, rate), "your_slot": 1, "training": true,
		"opponent": {"name": "SONDE", "is_bot": true}})
	_ok("%s : rythme ANNONCE %.0f Hz, LU par le client (_on_init — la sonde n'ecrit plus _tick_rate)"
		% [where, rate], absf(float(duel._tick_rate) - rate) < 1e-6,
		"_tick_rate = %.4f" % duel._tick_rate)


# La cadence ATTENDUE d'une arme, en secondes — dérivée de la table de fixture et du rythme ANNONCÉ,
# jamais de `duel._tick_rate` (le champ même que la sonde contrôle) ni d'un délai écrit à la main.
func _probe_cadence_s(weapon_id: String, rate: float) -> float:
	return float((PROBE_WEAPONS[weapon_id] as Dictionary)["cooldown_ticks"]) / rate


# LA FENÊTRE TENUE PAR LE BOURDONNEMENT : durée réellement jouée = durée du fichier ÷ pitch posé.
# Elle doit VALOIR la fenêtre de danger — ou, si le réglage sort des bornes de pitch du manager,
# être plus COURTE qu'elle. Jamais plus longue : une alerte ne survit pas au tir qu'elle annonce.
func _check_warn_window(duel, window_s: float, warn_len: float) -> void:
	var pitch: float = float(_last_player().pitch_scale)
	var played: float = warn_len / maxf(0.001, pitch)
	var bounded: bool = pitch <= AudioManager.SFX_PITCH_MIN + 1e-6 \
		or pitch >= AudioManager.SFX_PITCH_MAX - 1e-6
	_ok("fenetre %.3f s : le bourdonnement dure %.3f s (%s)"
		% [window_s, played, "borne par le manager" if bounded else "cale sur la fenetre"],
		played <= window_s + 1e-3 and (bounded or absf(played - window_s) < 1e-3),
		"pitch pose %.4f · jeton %d" % [pitch, duel._laser_warn_token])


# L'ÉCHANGE QUI SATURAIT LE POOL, rejoué EN TEMPS RÉEL (seule façon de voir un vol : sans temps qui
# passe, tous les lecteurs sont « en lecture » et la mesure ne veut rien dire). Mes 3 crans de
# FRELON à 0 / 100 / 200 ms, les 3 crans adverses décalés de 50 ms, puis les 3 sifflements de ses
# balles qui me manquent, la culasse et le hitmarker. Renvoie le nombre de voix VOLÉES.
func _burst_exchange() -> int:
	for p in AudioManager._sfx_players:
		(p as AudioStreamPlayer).stop()
	await get_tree().process_frame
	var before: int = int(AudioManager._sfx_steals)
	for i in 3:
		AudioManager.play_sfx("trench_shot_frelon")        # mon cran
		await get_tree().create_timer(0.05).timeout
		AudioManager.play_sfx("trench_shot_frelon")        # le sien, 50 ms plus tard
		await get_tree().create_timer(0.05).timeout
	for i in 3:
		AudioManager.play_sfx("trench_whizz")
		await get_tree().create_timer(0.03).timeout
	AudioManager.play_sfx("trench_bolt")
	AudioManager.play_sfx("trench_hitmarker")
	await get_tree().create_timer(0.05).timeout
	return int(AudioManager._sfx_steals) - before


func _ready() -> void:
	print("=== SONDE AUDIO v2 (§8.151, LOT A) ===")
	var was_enabled: bool = AudioManager._enabled
	AudioManager._enabled = true

	# --- 1. LE REGISTRE : familles découvertes + la clé neuve --------------------------------------
	print("\n--- 1. registre des variantes et cle trench_bolt ---")
	for base in EXPECTED_FAMILIES:
		var got: int = (AudioManager._sfx_variants.get(base, []) as Array).size()
		_ok("famille %s : %d variante(s)" % [base, EXPECTED_FAMILIES[base]],
			got == int(EXPECTED_FAMILIES[base]), "trouve %d" % got)
	_ok("cle trench_bolt enregistree (override ou repli synthe)",
		AudioManager._sfx.get("trench_bolt") != null)
	_ok("trench_bolt.wav present sur disque (override actif)",
		AudioManager._load_override("sfx", "trench_bolt") != null)
	# §2bis : le télégraphe audible — OVERRIDE SEUL (pas de synthé : doctrine whizz, le repli est
	# le silence). Dans l'arbre RÉEL le fichier est là : la clé doit être servie.
	_ok("cle trench_laser_warn servie (trench_laser_warn.wav importe)",
		AudioManager._sfx.get("trench_laser_warn") != null)

	# --- 2. LA ROTATION : 50 lectures RÉELLES de trench_shot ---------------------------------------
	print("\n--- 2. rotation round-robin (50 tirages via play_sfx) ---")
	var seq: Array = []
	var pitches: Array = []
	for i in 50:
		AudioManager.play_sfx("trench_shot")
		seq.append(int(AudioManager._variant_last["trench_shot"]))
		pitches.append(float(_last_player().pitch_scale))
	var repeat_found := false
	var used := {}
	var out_of_range := false
	for i in seq.size():
		used[seq[i]] = true
		if seq[i] < 0 or seq[i] > 5:
			out_of_range = true
		if i > 0 and seq[i] == seq[i - 1]:
			repeat_found = true
	print("  sequence : %s" % [seq])
	_ok("jamais deux fois la meme variante d'affilee", not repeat_found)
	_ok("les 6 variantes utilisees", used.size() == 6, "utilisees : %d" % used.size())
	_ok("indices bornes [0, 5]", not out_of_range)

	# --- 3. LE JITTER : borné ± 3 %, et il varie -------------------------------------------------
	print("\n--- 3. jitter de pitch (les 50 lectures + 200 tirages directs) ---")
	var lo := 99.0
	var hi := -99.0
	for p in pitches:
		lo = minf(lo, p)
		hi = maxf(hi, p)
	for i in 200:
		var p: float = AudioManager._variant_pitch()
		lo = minf(lo, p)
		hi = maxf(hi, p)
	print("  min %.5f · max %.5f (bornes attendues : 0.97 / 1.03)" % [lo, hi])
	_ok("pitch borne a -3 %", lo >= 1.0 - AudioManager.TRENCH_PITCH_JITTER - 1e-6)
	_ok("pitch borne a +3 %", hi <= 1.0 + AudioManager.TRENCH_PITCH_JITTER + 1e-6)
	_ok("le jitter varie vraiment (pas une constante morte)", hi - lo > 0.001)

	# --- 4. CLÉS INCONNUES ET CLÉS DE MENU : comportement inchangé -------------------------------
	print("\n--- 4. cles inconnues / cles de menu ---")
	var plays_before: int = _plays()
	AudioManager.play_sfx("cle_inconnue_8151")
	_ok("cle inconnue : silence, aucune lecture", _plays() == plays_before)
	_ok("cle inconnue : aucun registre cree",
		not AudioManager._sfx_variants.has("cle_inconnue_8151")
		and not AudioManager._sfx.has("cle_inconnue_8151"))
	plays_before = _plays()
	AudioManager.play_sfx("click")
	_ok("cle de menu 'click' : UNE lecture partie", _plays() == plays_before + 1)
	_ok("cle de menu 'click' : pitch nominal 1.0 (jamais de jitter hors variantes)",
		absf(float(_last_player().pitch_scale) - 1.0) < 1e-6)

	# --- 5. CÂBLAGE DUEL : culasse et sifflement (patron falseshot, headless) ---------------------
	print("\n--- 5. cablage duel : trench_bolt (rearmement) et trench_whizz (balle manquee) ---")
	# ⚠️ Le `_ready` du duel démarre la MUSIQUE de combat (`start_battle_ambient`) : avec `_enabled`
	# forcé, `battle_ambient.wav` partirait EN BOUCLE et resterait en vie au quit — c'est lui que le
	# rapport de fuites nommait. On instancie donc le duel dans l'état headless NOMINAL (lecture
	# coupée), puis on ne rétablit la lecture que pour les contrôles qui l'observent.
	AudioManager._enabled = false
	DuelScript.pending_room_id = "999"
	var duel = DuelScene.instantiate()
	add_child(duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(duel._on_connection_lost)
	duel.set_process(false)
	AudioManager._enabled = true
	# ⚠️ LE PAQUET D'INIT, PAS UNE ÉCRITURE : `_init_duel` ANNONCE le rythme (8 Hz, hors production)
	# par `_on_init` et contrôle que le client l'a lu. La sonde n'écrit plus `duel._tick_rate`.
	_init_duel(duel, ["vipere"], PROBE_TICK_RATE_HZ, "section 5")
	_push_state(duel)
	duel._refresh_view(0.016)

	# 5a. Un tir RÉEL arme la culasse, à la porte de cadence du REGISTRE — cadence et rythme LUS de
	# la fixture (hors production tous les deux : un `18 / 20` recopié en dur ne tombe plus dessus).
	var cad_vipere: float = _probe_cadence_s("vipere", PROBE_TICK_RATE_HZ)     # 7 ticks / 8 Hz
	duel._clock = 10.0
	duel._fire_queued = false
	duel._queue_fire()
	_ok("tir reel : culasse ARMEE", duel._bolt_armed)
	_ok("porte de cadence = registre de test (10.0 + %d ticks / %.0f Hz = %.4f)"
		% [int(PROBE_WEAPONS["vipere"]["cooldown_ticks"]), PROBE_TICK_RATE_HZ, 10.0 + cad_vipere],
		absf(duel._pred_fire_ready - (10.0 + cad_vipere)) < 1e-4,
		"pred_fire_ready = %.4f" % duel._pred_fire_ready)

	# 5b. Un clic REFUSÉ (cadence) n'arme JAMAIS la culasse (§8.141.9).
	duel._bolt_armed = false
	duel._fire_queued = false
	duel._clock = 10.0 + cad_vipere * 0.5   # avant la porte : le refus « cadence » des six refus
	duel._queue_fire()
	_ok("clic refuse (cadence) : PAS de retour d'arme envoye", not duel._fire_queued)
	_ok("clic refuse (cadence) : culasse PAS armee", not duel._bolt_armed)

	# 5c. Le GUETTEUR : le clac part quand `_clock` franchit la porte — via le vrai `_process`.
	duel._bolt_armed = true
	duel._fire_queued = false
	duel._clock = 10.0 + cad_vipere + 1.0   # après la porte : la cadence est redevenue disponible
	plays_before = _plays()
	duel._process(0.0)
	_ok("guetteur : culasse desarmee au franchissement", not duel._bolt_armed)
	_ok("guetteur : trench_bolt JOUE (une lecture partie)", _plays() == plays_before + 1)
	plays_before = _plays()
	duel._process(0.0)
	_ok("guetteur : un seul clac par rearmement (pas de re-jeu)", _plays() == plays_before)

	# 5d. L'événement `fire` du SERVEUR (mon slot, tir non anticipé) arme aussi la culasse.
	duel._bolt_armed = false
	duel._fire_fx_mute = 1.0         # le retour d'arme de CE tir a déjà été joué : branche sautée
	duel._on_duel_event({"type": "fire", "slot": 1, "weapon": "vipere"})
	_ok("evenement fire serveur (mon slot) : culasse armee", duel._bolt_armed)

	# 5e. Le WHIZZ : `impact` de balle adverse MANQUÉE → la rotation whizz avance. Touche ou
	# grenade → elle ne bouge pas.
	var whizz_before: int = int(AudioManager._variant_last["trench_whizz"])
	duel._on_duel_event({"type": "impact", "kind": "vipere", "slot": 2, "target_pos": 2,
		"target_x": 0.0, "damage": 0})
	var whizz_after: int = int(AudioManager._variant_last["trench_whizz"])
	_ok("balle adverse MANQUEE : whizz joue", whizz_after != whizz_before or whizz_before < 0)
	whizz_before = whizz_after
	duel._on_duel_event({"type": "impact", "kind": "vipere", "slot": 2, "target_pos": 2,
		"target_x": 0.0, "damage": 25})
	_ok("balle adverse qui TOUCHE : pas de whizz",
		int(AudioManager._variant_last["trench_whizz"]) == whizz_before)
	duel._on_duel_event({"type": "impact", "kind": "vipere", "slot": 1, "target_pos": 2,
		"target_x": 0.0, "damage": 0})
	_ok("MA balle manquee : pas de whizz (il siffle a MON oreille, pas a la sienne)",
		int(AudioManager._variant_last["trench_whizz"]) == whizz_before)
	duel._on_duel_event({"type": "impact", "kind": "grenade", "slot": 2, "target_pos": 2,
		"target_x": 0.0, "damage": 0})
	_ok("grenade adverse : pas de whizz (l'explosion parle)",
		int(AudioManager._variant_last["trench_whizz"]) == whizz_before)

	# --- 6. VAGUE 2bis — les 4 VOIX PAR ARME tournent comme les autres familles (§3.6) -----------
	print("\n--- 6. voix par arme : rotation des 4 familles ---")
	for base in WEAPON_FAMILIES:
		_check_rotation(str(base))

	# --- 7. LA CLÉ PAR ARME, et son REPLI (arbre nu simulé par sabotage du registre) --------------
	print("\n--- 7. cle de detonation par arme + repli voix generique ---")
	_ok("frelon -> trench_shot_frelon", duel._shot_sfx_key("frelon") == "trench_shot_frelon")
	_ok("condor -> trench_shot_condor", duel._shot_sfx_key("condor") == "trench_shot_condor")
	_ok("arme inconnue -> voix generique", duel._shot_sfx_key("arme_inconnue_8151") == "trench_shot")
	_ok("id vide -> voix generique", duel._shot_sfx_key("") == "trench_shot")
	# SABOTAGE-REPLI : la famille disparaît du registre (c'est l'état d'un arbre nu/headless sans
	# fichiers) -> la clé DOIT retomber sur la voix générique, qui garde son synthé. Puis on remet.
	var saved_family: Array = AudioManager._sfx_variants["trench_shot_frelon"]
	AudioManager._sfx_variants.erase("trench_shot_frelon")
	_ok("famille absente (arbre nu simule) : REPLI voix generique",
		duel._shot_sfx_key("frelon") == "trench_shot")
	AudioManager._sfx_variants["trench_shot_frelon"] = saved_family
	_ok("registre restaure : la voix d'arme reprend",
		duel._shot_sfx_key("frelon") == "trench_shot_frelon")

	# --- 8. RAFALE LOCALE (§4bis.4) : un cran PAR PROJECTILE, au rythme du REGISTRE ---------------
	# ⚠️ Le registre injecté porte `PROBE_GAP_TICKS` (5 ticks), HORS production — cf. le pavé de la
	# constante : c'est ce qui rend un `gap = 2.0` recopié en dur DISCERNABLE d'une vraie lecture.
	print("\n--- 8. rafale locale frelon : crans au burst_gap_ticks du registre ---")
	_init_duel(duel, ["vipere", "frelon"], PROBE_TICK_RATE_HZ, "section 8")
	# ⚠️ L'attendu dérive des DEUX LITTÉRAUX de la fixture — l'espacement ET le rythme ANNONCÉ — et
	# jamais de `duel._tick_rate`, qui est précisément le champ sous contrôle (2ᵉ tour du 2ter).
	var gap_s: float = float(PROBE_GAP_TICKS) / PROBE_TICK_RATE_HZ         # 0,625 s
	print("  registre de test : %d ticks au rythme ANNONCE %.0f Hz -> +%.3f s / +%.3f s (production : 2 ticks a 20 Hz -> +0,100 s / +0,200 s)"
		% [PROBE_GAP_TICKS, PROBE_TICK_RATE_HZ, gap_s, 2.0 * gap_s])
	duel._buffer = []
	duel._on_state(_msg(300, "frelon", 24, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 100.0
	duel._pred_fire_ready = 0.0
	duel._pred_stance = "up"
	duel._fire_queued = false
	var tracers_before: int = duel._world._local_tracers.size()
	plays_before = _plays()
	duel._queue_fire()
	_ok("cran 1 IMMEDIAT : UNE tracante au clic (plus la gerbe des 3)",
		duel._world._local_tracers.size() == tracers_before + 1)
	_ok("cran 1 : UNE detonation (voix frelon via play_sfx)", _plays() == plays_before + 1)
	_ok("2 crans PLANIFIES pour les projectiles 2 et 3", duel._burst_queue.size() == 2)
	var due_ok := false
	# L'espacement RÉELLEMENT mesuré à ce rythme — repris tel quel au § 9quater, où il est comparé
	# à celui d'un AUTRE rythme annoncé (deux mesures, aucun littéral relu).
	var measured_gap_hz := 0.0
	if duel._burst_queue.size() == 2:
		# `PROBE_GAP_TICKS` / le rythme ANNONCÉ — le miroir de `_fire_burst`. Un « 2 » recopié en
		# dur donnerait 100,1 / 100,2 ; un diviseur « 20 » en dur, 100,25 / 100,5 ; un `_tick_rate`
		# figé à 10, 100,5 / 101,0. Aucun ne tombe sur 100,625 / 101,250 : la garde les voit tous.
		measured_gap_hz = float(duel._burst_queue[0]["due"]) - 100.0
		due_ok = absf(measured_gap_hz - gap_s) < 1e-4 \
			and absf(float(duel._burst_queue[1]["due"]) - (100.0 + 2.0 * gap_s)) < 1e-4
	_ok("cadence des crans = burst_gap_ticks du REGISTRE (+%.3f s / +%.3f s, hors production)"
		% [gap_s, 2.0 * gap_s], due_ok, "dus : %s" % [_dues(duel, 100.0)])

	# Un clic REFUSÉ (cadence pas prête) PENDANT la rafale ne planifie RIEN (§8.141.9).
	duel._fire_queued = false
	duel._clock = 100.05
	duel._queue_fire()
	_ok("refus (cadence) pendant la rafale : AUCUN cran ni tracante ajoutes",
		duel._burst_queue.size() == 2
		and duel._world._local_tracers.size() == tracers_before + 1
		and not duel._fire_queued)

	# ⚠️ L'HEURE COMPTE, PAS SEULEMENT LE COMPTE. Au barème de PRODUCTION (2 ticks = 0,100 s) les
	# DEUX crans seraient déjà dus ici : ce contrôle négatif est l'autre moitié de la garde du
	# registre — il rougit sur un chiffre en dur même si le contrôle des `due` était contourné.
	plays_before = _plays()
	duel._clock = 100.0 + gap_s - 0.01
	duel._process(0.0)
	_ok("avant l'heure du cran 2 (t = +%.3f s) : RIEN ne part, la file reste a 2" % (gap_s - 0.01),
		duel._burst_queue.size() == 2 and _plays() == plays_before
		and duel._world._local_tracers.size() == tracers_before + 1)
	# Le POMPAGE : cran 2 par le VRAI `_process` (la preuve du câblage), cran 3 en direct.
	plays_before = _plays()
	duel._clock = 100.0 + gap_s
	duel._process(0.0)
	_ok("cran 2 a son heure via _process : detonation + tracante, file a 1",
		duel._burst_queue.size() == 1
		and duel._world._local_tracers.size() == tracers_before + 2
		and _plays() == plays_before + 1)
	plays_before = _plays()
	duel._clock = 100.0 + 2.0 * gap_s - 0.01
	duel._step_burst_queue()
	_ok("avant l'heure du cran 3 : RIEN ne part, la file reste a 1",
		duel._burst_queue.size() == 1 and _plays() == plays_before
		and duel._world._local_tracers.size() == tracers_before + 2)
	plays_before = _plays()
	duel._clock = 100.0 + 2.0 * gap_s
	duel._step_burst_queue()
	_ok("cran 3 : file videe, 3e detonation, 3e tracante",
		duel._burst_queue.is_empty()
		and duel._world._local_tracers.size() == tracers_before + 3
		and _plays() == plays_before + 1)

	# Le chargeur BORNE la rafale, comme côté sim (`rounds = min(burst, ammo)`).
	duel._buffer = []
	duel._on_state(_msg(300, "frelon", 2, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 200.0
	duel._pred_fire_ready = 0.0
	duel._fire_queued = false
	duel._queue_fire()
	_ok("chargeur a 2 balles : UN seul cran suiveur planifie (min(burst, ammo))",
		duel._burst_queue.size() == 1)
	duel._burst_queue = []

	# --- 9. RAFALE ADVERSE : les launch_tick PAR PROJECTILE du serveur font foi -------------------
	# ⚠️ Les départs sont ceux de `PROBE_LAUNCH_OFFSETS` (0/3/7 ticks), IRRÉGULIERS et HORS
	# production : ni le barème du registre injecté (5 ticks) ni une minuterie de 0,1 s ne peuvent
	# tomber dessus. Les trois sources possibles rendent trois résultats DIFFÉRENTS — c'est tout
	# l'objet de ce durcissement (le sabotage « minuterie 0,1 s » passait inaperçu avant lui).
	print("\n--- 9. rafale adverse : crans cales sur les launch_tick serveur ---")
	duel._buffer = []
	duel._clock = 300.0
	plays_before = _plays()
	var burst_projs: Array = []
	for i in 3:
		var launch: int = 400 + int(PROBE_LAUNCH_OFFSETS[i])
		burst_projs.append({"id": 11 + i, "kind": "frelon", "owner_slot": 2, "from_pos": 2,
			"target_pos": 2, "launch_tick": launch, "impact_tick": launch + 1,
			"aim_yaw": 0.0, "aim_pitch": 0.0, "target_x": 0.0})
	duel._on_state(_msg(400, "frelon", 24, 0, 0, burst_projs,
		[{"type": "fire", "slot": 2, "weapon": "frelon", "rounds": 3, "ammo": 21}]))
	_ok("depart de feu adverse : detonation 1 IMMEDIATE (le danger s'annonce)",
		_plays() == plays_before + 1)
	# Les retards ATTENDUS, dérivés des `launch_tick` posés ci-dessus ET du rythme ANNONCÉ (jamais
	# de `duel._tick_rate`, le champ sous contrôle) : +3 et +7 ticks à 8 Hz.
	var d2: float = float(PROBE_LAUNCH_OFFSETS[1]) / PROBE_TICK_RATE_HZ    # 0,375 s
	var d3: float = float(PROBE_LAUNCH_OFFSETS[2]) / PROBE_TICK_RATE_HZ    # 0,875 s
	print("  launch_tick serveur : 400 / %d / %d -> +%.3f s / +%.3f s (registre : +%.3f / +%.3f · minuterie : +0,100 / +0,200)"
		% [400 + int(PROBE_LAUNCH_OFFSETS[1]), 400 + int(PROBE_LAUNCH_OFFSETS[2]),
			d2, d3, gap_s, 2.0 * gap_s])
	var enemy_due_ok := false
	if duel._burst_queue.size() == 2:
		enemy_due_ok = absf(float(duel._burst_queue[0]["due"]) - (300.0 + d2)) < 1e-4 \
			and absf(float(duel._burst_queue[1]["due"]) - (300.0 + d3)) < 1e-4
	_ok("2 crans adverses PLANIFIES sur les launch_tick SERVEUR (+%.3f s / +%.3f s — ni minuterie, ni registre)"
		% [d2, d3], duel._burst_queue.size() == 2 and enemy_due_ok,
		"dus : %s" % [_dues(duel, 300.0)])
	# LES CRANS PARTENT À L'HEURE DU SERVEUR, UN PAR UN — le compte ne suffit pas : une minuterie
	# de 0,1 s les aurait déjà tous lâchés avant le premier de ces deux contrôles négatifs.
	plays_before = _plays()
	duel._clock = 300.0 + d2 - 0.01
	duel._step_burst_queue()
	_ok("avant le launch_tick du 2e projectile : RIEN ne part",
		duel._burst_queue.size() == 2 and _plays() == plays_before)
	plays_before = _plays()
	duel._clock = 300.0 + d2
	duel._step_burst_queue()
	_ok("cran adverse 2 EXACTEMENT au launch_tick serveur (+%.3f s)" % d2,
		duel._burst_queue.size() == 1 and _plays() == plays_before + 1)
	plays_before = _plays()
	duel._clock = 300.0 + d3 - 0.01
	duel._step_burst_queue()
	_ok("avant le launch_tick du 3e projectile : RIEN ne part",
		duel._burst_queue.size() == 1 and _plays() == plays_before)
	plays_before = _plays()
	duel._clock = 300.0 + d3
	duel._step_burst_queue()
	_ok("cran adverse 3 EXACTEMENT au launch_tick serveur (+%.3f s), file videe" % d3,
		duel._burst_queue.is_empty() and _plays() == plays_before + 1)

	# --- 9bis. LE REPLI REGISTRE du chemin adverse (il n'etait garde par RIEN) --------------------
	# ╔═ CE QU'ELLE PROUVE ══════════════════════════════════════════════════════════════════════╗
	# ║ `_schedule_burst_followups` date ses crans sur les `launch_tick` de l'état arrivé dans le  ║
	# ║ MÊME message ; si cet état ne porte AUCUN départ futur (harnais minimal, paquet exotique), ║
	# ║ le repli est `burst_gap_ticks` DU REGISTRE — la valeur même que `_fire_burst` a utilisée.  ║
	# ║ Cette seconde lecture du registre n'avait jusqu'ici aucun contrôle : un chiffre en dur y    ║
	# ║ serait passé inaperçu. Le registre de test disant 5 ticks, un « 2 » rendrait +0,100 s.      ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 9bis. rafale adverse sans projectiles dans l'etat : repli sur le REGISTRE ---")
	duel._buffer = []
	duel._burst_queue = []
	duel._clock = 350.0
	plays_before = _plays()
	duel._on_state(_msg(450, "frelon", 24, 0, 0, [],
		[{"type": "fire", "slot": 2, "weapon": "frelon", "rounds": 3, "ammo": 21}]))
	_ok("etat muet : la detonation 1 part quand meme", _plays() == plays_before + 1)
	var fallback_ok := false
	if duel._burst_queue.size() == 2:
		fallback_ok = absf(float(duel._burst_queue[0]["due"]) - (350.0 + gap_s)) < 1e-4 \
			and absf(float(duel._burst_queue[1]["due"]) - (350.0 + 2.0 * gap_s)) < 1e-4
	_ok("etat muet : les 2 crans retombent sur le burst_gap_ticks du REGISTRE (+%.3f s / +%.3f s)"
		% [gap_s, 2.0 * gap_s], duel._burst_queue.size() == 2 and fallback_ok,
		"dus : %s" % [_dues(duel, 350.0)])
	duel._burst_queue = []

	# --- 9ter. LE CHACAL (rafale ×2) et le repli `rounds <= 1` -----------------------------------
	# ╔═ CE QU'ELLE PROUVE ══════════════════════════════════════════════════════════════════════╗
	# ║ 🩸 Jusqu'à cette passe, TOUTES les fixtures de rafale passaient par le FRELON (×3) : le cas ║
	# ║ `rounds == 2` — la rafale du CHACAL, une arme du registre RÉEL — et le retour anticipé      ║
	# ║ `rounds <= 1` (tir simple : rien à planifier) n'étaient exercés par AUCUN contrôle. Un      ║
	# ║ `range(2)` écrit en dur à la place de `range(rounds - 1)`, ou une garde `rounds < 3`,       ║
	# ║ seraient passés inaperçus dans les deux sens (cran de trop / cran manquant).                ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 9ter. chacal (rafale x2) : UN cran suiveur ; tir simple : AUCUN ---")
	_init_duel(duel, ["vipere", "chacal"], PROBE_TICK_RATE_HZ, "section 9ter")
	# a. LOCAL — mon CHACAL : `burst` vaut 2, donc UN seul cran, à l'espacement du registre.
	duel._buffer = []
	duel._on_state(_msg(460, "chacal", 11, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 360.0
	duel._pred_fire_ready = 0.0
	duel._pred_stance = "up"
	duel._fire_queued = false
	duel._queue_fire()
	var chacal_local_ok := false
	if duel._burst_queue.size() == 1:
		chacal_local_ok = absf(float(duel._burst_queue[0]["due"]) - (360.0 + gap_s)) < 1e-4
	_ok("chacal LOCAL (burst 2) : UN cran suiveur, a +%.3f s" % gap_s,
		duel._burst_queue.size() == 1 and chacal_local_ok, "dus : %s" % [_dues(duel, 360.0)])
	# b. ADVERSE — l'événement `fire` annonce `rounds: 2` : UN cran, daté au launch_tick serveur.
	duel._buffer = []
	duel._burst_queue = []
	duel._clock = 370.0
	var chacal_projs: Array = [{"id": 41, "kind": "chacal", "owner_slot": 2, "from_pos": 2,
		"target_pos": 2, "launch_tick": 470 + int(PROBE_LAUNCH_OFFSETS[1]),
		"impact_tick": 471 + int(PROBE_LAUNCH_OFFSETS[1]), "aim_yaw": 0.0, "aim_pitch": 0.0,
		"target_x": 0.0}]
	duel._on_state(_msg(470, "chacal", 11, 0, 0, chacal_projs,
		[{"type": "fire", "slot": 2, "weapon": "chacal", "rounds": 2, "ammo": 9}]))
	var chacal_enemy_ok := false
	if duel._burst_queue.size() == 1:
		chacal_enemy_ok = absf(float(duel._burst_queue[0]["due"]) - (370.0 + d2)) < 1e-4
	_ok("chacal ADVERSE (rounds 2) : UN cran, au launch_tick serveur (+%.3f s)" % d2,
		duel._burst_queue.size() == 1 and chacal_enemy_ok, "dus : %s" % [_dues(duel, 370.0)])
	# c. LE REPLI `rounds <= 1` : un tir SIMPLE se fait entendre et ne planifie RIEN.
	duel._burst_queue = []
	duel._buffer = []
	plays_before = _plays()
	duel._on_state(_msg(480, "chacal", 11, 0, 0, [],
		[{"type": "fire", "slot": 2, "weapon": "vipere", "rounds": 1, "ammo": 5}]))
	_ok("tir SIMPLE adverse (rounds 1) : la detonation part, AUCUN cran planifie",
		duel._burst_queue.is_empty() and _plays() == plays_before + 1,
		"%d cran(s), %d lecture(s)" % [duel._burst_queue.size(), _plays() - plays_before])
	duel._burst_queue = []

	# --- 9quater. LE RYTHME ANNONCÉ FAIT LOI : même registre, AUTRE tick_rate_hz ------------------
	# ╔═ 🩸 LE CONTRE-ESSAI QUI TUE LE « PAR CŒUR » ══════════════════════════════════════════════╗
	# ║ Une garde qui n'éprouve qu'UN rythme peut être satisfaite par une constante : il suffirait  ║
	# ║ d'écrire `_tick_rate = 8.0` (ou `/ 8.0`) dans le code de jeu pour la rendre verte — le      ║
	# ║ défaut même qu'on solde, déplacé d'un chiffre. On RE-ANNONCE donc le duel à un SECOND       ║
	# ║ rythme SANS toucher au registre d'armes : les MÊMES 5 ticks d'espacement et les MÊMES       ║
	# ║ `launch_tick` doivent rendre des échéances DIFFÉRENTES (0,625 s à 8 Hz, 0,385 s à 13 Hz).   ║
	# ║ Le dernier contrôle ne relit AUCUN littéral : il compare deux amplitudes MESURÉES — leur    ║
	# ║ rapport vaut l'inverse du rapport des rythmes, et vaut 1,0 pour n'importe quel diviseur     ║
	# ║ constant. C'est le patron de l'atténuation du feel (§15), appliqué au temps.                ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 9quater. second rythme annonce : les crans SUIVENT le tick_rate du serveur ---")
	_init_duel(duel, ["vipere", "frelon"], PROBE_TICK_RATE_ALT, "section 9quater")
	var gap_alt: float = float(PROBE_GAP_TICKS) / PROBE_TICK_RATE_ALT       # 0,385 s
	var d2_alt: float = float(PROBE_LAUNCH_OFFSETS[1]) / PROBE_TICK_RATE_ALT
	var d3_alt: float = float(PROBE_LAUNCH_OFFSETS[2]) / PROBE_TICK_RATE_ALT
	# a. MA rafale, au nouveau rythme — mêmes ticks, autres secondes.
	duel._buffer = []
	duel._on_state(_msg(490, "frelon", 17, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 380.0
	duel._pred_fire_ready = 0.0
	duel._pred_stance = "up"
	duel._fire_queued = false
	duel._queue_fire()
	var alt_local_ok := false
	var measured_gap_alt := 0.0
	if duel._burst_queue.size() == 2:
		measured_gap_alt = float(duel._burst_queue[0]["due"]) - 380.0
		alt_local_ok = absf(measured_gap_alt - gap_alt) < 1e-4 \
			and absf(float(duel._burst_queue[1]["due"]) - (380.0 + 2.0 * gap_alt)) < 1e-4
	_ok("rafale LOCALE a %.0f Hz : +%.3f s / +%.3f s (les MEMES %d ticks valaient +%.3f s a %.0f Hz)"
		% [PROBE_TICK_RATE_ALT, gap_alt, 2.0 * gap_alt, PROBE_GAP_TICKS, gap_s,
			PROBE_TICK_RATE_HZ], duel._burst_queue.size() == 2 and alt_local_ok,
		"dus : %s" % [_dues(duel, 380.0)])
	# b. LA rafale ADVERSE au nouveau rythme : les `launch_tick` se convertissent avec LUI.
	duel._buffer = []
	duel._burst_queue = []
	duel._clock = 390.0
	duel._on_state(_msg(500, "frelon", 17, 0, 0, _enemy_burst(500),
		[{"type": "fire", "slot": 2, "weapon": "frelon", "rounds": 3, "ammo": 14}]))
	var alt_enemy_ok := false
	if duel._burst_queue.size() == 2:
		alt_enemy_ok = absf(float(duel._burst_queue[0]["due"]) - (390.0 + d2_alt)) < 1e-4 \
			and absf(float(duel._burst_queue[1]["due"]) - (390.0 + d3_alt)) < 1e-4
	_ok("rafale ADVERSE a %.0f Hz : +%.3f s / +%.3f s (a %.0f Hz : +%.3f / +%.3f)"
		% [PROBE_TICK_RATE_ALT, d2_alt, d3_alt, PROBE_TICK_RATE_HZ, d2, d3],
		duel._burst_queue.size() == 2 and alt_enemy_ok, "dus : %s" % [_dues(duel, 390.0)])
	# c. LE RAPPORT DE DEUX MESURES — aucun littéral relu, aucun diviseur constant ne le satisfait.
	_ok("la cadence SUIT le rythme annonce : rapport des DEUX MESURES == %.0f/%.0f (un diviseur en dur donnerait 1,000)"
		% [PROBE_TICK_RATE_ALT, PROBE_TICK_RATE_HZ],
		measured_gap_hz > 0.0 and measured_gap_alt > 0.0
		and absf(measured_gap_hz / measured_gap_alt
			- PROBE_TICK_RATE_ALT / PROBE_TICK_RATE_HZ) < 1e-4,
		"%.4f s a %.0f Hz contre %.4f s a %.0f Hz -> rapport %.4f"
		% [measured_gap_hz, PROBE_TICK_RATE_HZ, measured_gap_alt, PROBE_TICK_RATE_ALT,
			measured_gap_hz / maxf(1e-9, measured_gap_alt)])
	duel._burst_queue = []

	# --- 10. TÉLÉGRAPHE CONDOR AUDIBLE : une fois par visee, CALE SUR LA FENETRE, jamais pour moi --
	print("\n--- 10. trench_laser_warn : le telegraphe adverse s'entend, et il dure ce que dure le danger ---")
	# Le registre porte le CONDOR et son ⚙ `laser_lead_ticks` : la sonde POSE `laser_fire_tick` à
	# `tick + lead` — exactement ce que fait la sim (`trench_sim.step`) — et ne recopie aucune durée.
	_init_duel(duel, ["frelon", "condor"], PROBE_TICK_RATE_HZ, "section 10")
	var lead: int = _lead_ticks(duel, "condor")
	var warn_len: float = AudioManager.sfx_length("trench_laser_warn")
	print("  duree du fichier : %.4f s · laser_lead_ticks (registre) : %d ticks" % [warn_len, lead])
	_ok("le registre injecte porte bien un CONDOR telegraphie", lead > 0 and warn_len > 0.0)

	duel._laser_warn_latch = false
	duel._laser_warn_token = -1
	duel._buffer = []
	duel._on_state(_msg(500, "frelon", 24, 0, 0, [], []))
	plays_before = _plays()
	duel._refresh_view(0.016)
	_ok("aucun laser : silence", _plays() == plays_before)

	# FENÊTRE NOMINALE : `laser_lead_ticks` de la fixture ÷ le rythme ANNONCÉ (3 ticks / 8 Hz =
	# 0,375 s) — ni le 10/20 de production, ni une durée recopiée.
	duel._buffer = []
	duel._on_state(_msg(500, "frelon", 24, 0, 500 + lead, [], []))
	plays_before = _plays()
	duel._refresh_view(0.016)
	var warn_idx: int = int(AudioManager._sfx_last)
	_ok("le laser adverse COMMENCE : trench_laser_warn joue (meme signal que le rendu)",
		_plays() == plays_before + 1 and duel._laser_warn_latch)
	_check_warn_window(duel, float(lead) / PROBE_TICK_RATE_HZ, warn_len)

	plays_before = _plays()
	duel._refresh_view(0.016)
	duel._refresh_view(0.016)
	_ok("UNE lecture par visee (verrou tenu tant que le rayon dure)", _plays() == plays_before)

	# LE RAYON S'ÉTEINT : le verrou se relâche ET la voix se TAIT — l'alerte ne survit pas au tir.
	duel._buffer = []
	duel._on_state(_msg(500 + lead + 10, "frelon", 24, 0, 500 + lead, [], []))
	duel._refresh_view(0.016)
	_ok("rayon eteint (tir parti) : verrou relache", not duel._laser_warn_latch)
	_ok("rayon eteint : la VOIX du telegraphe est coupee (elle ne bourdonne pas apres la balle)",
		not (AudioManager._sfx_players[warn_idx] as AudioStreamPlayer).playing
		and (AudioManager._sfx_players[warn_idx] as AudioStreamPlayer).stream == null,
		"lecteur #%d" % warn_idx)
	_ok("jeton rendu apres l'arret (rien a re-couper)", duel._laser_warn_token == -1)

	# ⚙ LE RÉGLAGE SUIVI, PAS RECOPIÉ : une fenêtre DEUX FOIS plus longue → le bourdonnement dure
	# deux fois plus longtemps. Si la durée venait du fichier, le pitch serait le même aux deux.
	duel._buffer = []
	duel._on_state(_msg(600, "frelon", 24, 0, 600 + lead * 2, [], []))
	duel._refresh_view(0.016)
	var pitch_long: float = float(_last_player().pitch_scale)
	_check_warn_window(duel, float(lead * 2) / PROBE_TICK_RATE_HZ, warn_len)
	duel._buffer = []
	duel._on_state(_msg(700, "frelon", 24, 0, 700, [], []))
	duel._refresh_view(0.016)          # rayon éteint : on relâche le verrou proprement
	duel._buffer = []
	duel._on_state(_msg(800, "frelon", 24, 0, 800 + lead, [], []))
	plays_before = _plays()
	duel._refresh_view(0.016)
	var pitch_short: float = float(_last_player().pitch_scale)
	_ok("NOUVELLE visee : le telegraphe re-avertit", _plays() == plays_before + 1)
	_ok("fenetre DOUBLE -> bourdonnement DEUX FOIS plus lent (la duree vient de la SIM, pas du .wav)",
		absf(pitch_short - 2.0 * pitch_long) < 1e-3,
		"pitch %.4f (fenetre %.3f s) contre %.4f (fenetre %.3f s)"
		% [pitch_short, float(lead) / PROBE_TICK_RATE_HZ, pitch_long,
			float(lead * 2) / PROBE_TICK_RATE_HZ])

	duel._buffer = []
	duel._on_state(_msg(900, "frelon", 24, 0, 900, [], []))
	duel._refresh_view(0.016)
	duel._buffer = []
	duel._on_state(_msg(1000, "frelon", 24, 1000 + lead, 0, [], []))
	duel._laser_warn_latch = false
	plays_before = _plays()
	duel._refresh_view(0.016)
	_ok("MON propre laser : SILENCE (c'est un avertissement de CIBLE)",
		_plays() == plays_before and not duel._laser_warn_latch)

	# --- 11. CONDOR : LE CLIC ARME UN LASER, IL NE TIRE PAS (correctif du faux coup SONORE) -------
	# ╔═ CE QU'ELLE PROUVE ══════════════════════════════════════════════════════════════════════╗
	# ║ Le code refusait DÉJÀ la traçante au clic du condor (« son clic ARME UN LASER, la balle ne ║
	# ║ part que 0,5 s plus tard ») mais jouait la détonation, le recul et la frame de tir. Puis    ║
	# ║ `_fire_fx_mute` (0,45 s) expirait AVANT l'événement `fire` du serveur (`laser_lead_ticks`   ║
	# ║ = 10 ticks = 0,50 s) : le vrai tir rejouait tout. UN coup = DEUX détonations de 1,15 s.     ║
	# ║ On vérifie donc les deux moitiés : rien au clic, TOUT (et une seule fois) au tir réel.      ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 11. condor : le clic ARME, il ne tire pas (une seule detonation, a l'heure) ---")
	duel._reduced_motion = false       # le cran de recul doit pouvoir se compter
	duel._buffer = []
	duel._on_state(_msg(1100, "condor", 5, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 400.0
	duel._pred_fire_ready = 0.0
	duel._pred_stance = "up"
	duel._fire_queued = false
	duel._fire_fx_mute = 0.0
	var condor_tracers: int = duel._world._local_tracers.size()
	var condor_shots: int = int(duel._shot_count)
	plays_before = _plays()
	duel._queue_fire()
	_ok("clic CONDOR : AUCUNE detonation (le faux coup sonore a disparu)",
		_plays() == plays_before, "%d lecture(s)" % (_plays() - plays_before))
	_ok("clic CONDOR : AUCUN cran de recul (le compteur de tirs ne bouge pas)",
		int(duel._shot_count) == condor_shots)
	_ok("clic CONDOR : AUCUNE tracante (la garde d'origine, toujours tenue)",
		duel._world._local_tracers.size() == condor_tracers)
	_ok("clic CONDOR : AUCUN cran de rafale planifie", duel._burst_queue.is_empty())
	_ok("clic CONDOR : PAS de fenetre de mute (rien n'a ete joue, rien a museler)",
		duel._fire_fx_mute <= 0.0, "_fire_fx_mute = %.3f" % duel._fire_fx_mute)
	_ok("clic CONDOR : le tir PART quand meme (le serveur le recevra)", duel._fire_queued)
	# Ce que le clic a VRAIMENT produit côté serveur : la cadence consommée — celle de la FIXTURE
	# (29 ticks), au rythme ANNONCÉ (8 Hz). Le barème de production (50 / 20 Hz) rendrait 402,5.
	var cad_condor: float = _probe_cadence_s("condor", PROBE_TICK_RATE_HZ)
	_ok("clic CONDOR : cadence consommee des le clic (registre de test : %d ticks / %.0f Hz)"
		% [int(PROBE_WEAPONS["condor"]["cooldown_ticks"]), PROBE_TICK_RATE_HZ],
		absf(duel._pred_fire_ready - (400.0 + cad_condor)) < 1e-4,
		"pred_fire_ready = %.4f (attendu %.4f)" % [duel._pred_fire_ready, 400.0 + cad_condor])
	# … ET LE TIR RÉEL, 0,5 s plus tard : l'événement `fire` du serveur joue tout, UNE fois.
	plays_before = _plays()
	condor_shots = int(duel._shot_count)
	duel._on_duel_event({"type": "fire", "slot": 1, "weapon": "condor", "rounds": 1, "ammo": 4})
	_ok("tir CONDOR reel : UNE detonation, a l'heure de la balle",
		_plays() == plays_before + 1, "%d lecture(s)" % (_plays() - plays_before))
	_ok("tir CONDOR reel : UN cran de recul", int(duel._shot_count) == condor_shots + 1)

	# --- 12. LE POOL DE VOIX : une rafale ne VOLE plus la queue d'une detonation ------------------
	# ╔═ CE QU'ELLE PROUVE ══════════════════════════════════════════════════════════════════════╗
	# ║ L'échange FRELON/FRELON (3 + 3 détonations en 250 ms) + les sifflements + la culasse tenait ║
	# ║ dans 6 voix… en ÉCRASANT les lecteurs encore en cours. Aucune vérification ne le voyait :   ║
	# ║ elles étaient toutes arithmétiques (`_sfx_next % taille`), et le bouclage d'un curseur ne   ║
	# ║ dit RIEN du vol. On rejoue donc la scène en TEMPS RÉEL et on lit le compteur de vols.       ║
	# ║ SABOTAGE : le pool ramené à sa taille d'AVANT (6) → la même scène vole des voix.            ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 12. pool de voix : l'echange de rafales ne tronque plus rien ---")
	_ok("pool dimensionne (%d lecteurs)" % AudioManager.SFX_POOL_SIZE,
		AudioManager._sfx_players.size() == AudioManager.SFX_POOL_SIZE)
	var steals: int = await _burst_exchange()
	_ok("echange FRELON/FRELON + sifflements + culasse : AUCUNE voix volee",
		steals == 0, "%d vol(s)" % steals)
	# SABOTAGE — le pool d'avant (6 lecteurs) : la même scène DOIT voler. Sans ce contre-essai, un
	# contrôle qui ne rougit jamais ne prouve rien.
	var full_pool: Array = AudioManager._sfx_players.duplicate()
	var full_gen: Array = AudioManager._sfx_gen.duplicate()
	for p in full_pool:
		(p as AudioStreamPlayer).stop()
	AudioManager._sfx_players = full_pool.slice(0, 6)
	AudioManager._sfx_gen = full_gen.slice(0, 6)
	AudioManager._sfx_next = 0
	var sabotage_steals: int = await _burst_exchange()
	AudioManager._sfx_players = full_pool
	AudioManager._sfx_gen = full_gen
	AudioManager._sfx_next = 0
	_ok("SABOTAGE (pool ramene a 6, la taille d'avant) : la scene VOLE des voix",
		sabotage_steals > 0, "%d vol(s)" % sabotage_steals)

	# --- 13. LES TRAÇANTES DE LA RAFALE : une balle pas encore partie ne se dessine pas -----------
	# ╔═ CE QU'ELLE PROUVE ══════════════════════════════════════════════════════════════════════╗
	# ║ L'effet mitraillette n'était corrigé QU'À MOITIÉ côté ADVERSE : son, lueur de canon et cran ║
	# ║ de recul pulsaient par projectile, mais `_refresh_view` poussait TOUTE la rafale dans les   ║
	# ║ traçantes dès le tick du clic (les 3 balles sont dans l'état du tick T, `launch_tick`       ║
	# ║ T/T+2/T+4). La victime entendait 3 détonations sur 200 ms en voyant 3 balles au canon dès   ║
	# ║ la 1ʳᵉ frame. On compte donc les traçantes RÉELLEMENT rendues (nœuds visibles du monde),    ║
	# ║ état par état.                                                                              ║
	# ║ ⚠️ LE CONTRÔLE 13d EST LE GARDE-FOU DU REMÈDE : filtrer sur `render_tick` (la lettre de la  ║
	# ║ correction proposée) aurait effacé TOUTES les traçantes adverses — `flight_ticks` vaut 1,   ║
	# ║ la balle quitte l'état au tick suivant son départ, et `render_tick` vit un tick en arrière. ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 13. tracantes de rafale : une par projectile, a son launch_tick ---")
	_init_duel(duel, ["vipere", "frelon"], PROBE_TICK_RATE_HZ, "section 13")
	duel._burst_queue = []
	duel._world._local_tracers = []
	# ⚠️ DURCISSEMENT 2ter : les départs viennent de `PROBE_LAUNCH_OFFSETS` (0/3/7), pas du 0/2/4 de
	# production — et ils sont IRRÉGULIERS. Une garde qui daterait les traçantes sur « 2 ticks » ou
	# sur un pas constant, au lieu du `launch_tick` de CHAQUE projectile, se trahirait ici.
	var t2: int = 400 + int(PROBE_LAUNCH_OFFSETS[1])
	var t3: int = 400 + int(PROBE_LAUNCH_OFFSETS[2])
	# a. L'ÉTAT DU CLIC (tick 400) porte les 3 balles : UNE SEULE est partie.
	_ok("etat du clic (tick 400, launch 400/%d/%d) : UNE tracante rendue, pas 3" % [t2, t3],
		_visible_tracers(duel, 400, _enemy_burst(400)) == 1)
	# b. Les ticks INTERMÉDIAIRES : la balle 1 a impacté, la 2 n'est pas encore partie → écran net.
	_ok("tick 401 (entre deux balles) : AUCUNE tracante — la rafale respire",
		_visible_tracers(duel, 401, _enemy_burst(400).slice(1)) == 0)
	_ok("tick %d (juste AVANT le depart de la balle 2) : AUCUNE tracante" % (t2 - 1),
		_visible_tracers(duel, t2 - 1, _enemy_burst(400).slice(1)) == 0)
	# c. Les départs 2 et 3, chacun à SON tick.
	_ok("tick %d (depart de la balle 2) : UNE tracante" % t2,
		_visible_tracers(duel, t2, _enemy_burst(400).slice(1)) == 1)
	_ok("tick %d (juste AVANT le depart de la balle 3) : AUCUNE tracante" % (t3 - 1),
		_visible_tracers(duel, t3 - 1, _enemy_burst(400).slice(2)) == 0)
	_ok("tick %d (depart de la balle 3) : UNE tracante" % t3,
		_visible_tracers(duel, t3, _enemy_burst(400).slice(2)) == 1)
	# d. NON-RÉGRESSION — le tir simple adverse est TOUJOURS rendu (le remède littéral l'effaçait).
	var single: Array = [{"id": 90, "kind": "vipere", "owner_slot": 2, "from_pos": 2,
		"target_pos": 2, "launch_tick": 500, "impact_tick": 501, "aim_yaw": 0.0,
		"aim_pitch": 0.0, "target_x": 0.0}]
	_ok("tir SIMPLE adverse (launch == tick de l'etat) : la tracante est RENDUE",
		_visible_tracers(duel, 500, single) == 1)
	# f. LE TAMPON DE RENDU RÉEL (2 états, cible à mi-chemin) — la mesure qui SÉPARE les deux gardes.
	#    Avec un seul état poussé, `render_tick` VAUT le tick de l'état : la garde du tick d'état et
	#    celle de `render_tick` y sont indiscernables. En vol il y a toujours ≥ 2 états et la cible
	#    de rendu vit RENDER_DELAY en arrière — c'est LÀ que le remède littéral efface tout.
	_ok("tampon REEL (render_tick a mi-chemin) : la tracante adverse est TOUJOURS rendue",
		_visible_tracers_buffered(duel, 700, [{"id": 92, "kind": "vipere", "owner_slot": 2,
			"from_pos": 2, "target_pos": 2, "launch_tick": 700, "impact_tick": 701,
			"aim_yaw": 0.0, "aim_pitch": 0.0, "target_x": 0.0}]) == 1)
	_ok("tampon REEL + rafale complete dans l'etat : UNE tracante, pas 3",
		_visible_tracers_buffered(duel, 800, _enemy_burst(800)) == 1)
	# e. La grenade garde son marqueur inconditionnel (la garde ne s'applique qu'aux balles).
	var nade: Array = [{"id": 91, "kind": "grenade", "owner_slot": 2, "from_pos": 2,
		"target_pos": 2, "launch_tick": 600, "impact_tick": 630, "aim_yaw": 0.0,
		"aim_pitch": 0.0, "target_x": 0.0}]
	duel._buffer = []
	duel._on_state(_msg(600, "frelon", 24, 0, 0, nade, []))
	duel._refresh_view(0.016)
	_ok("grenade adverse : marqueur toujours visible (la garde ne touche que les balles)",
		duel._world._markers[0].visible)

	# --- 14. CADENCE CONDOR : l'evenement `fire` date le CLIC, pas le depart de la balle ----------
	# ╔═ CE QU'ELLE PROUVE ══════════════════════════════════════════════════════════════════════╗
	# ║ `trench_sim.step` pose `fire_ready_tick = tick + cooldown_ticks` AU CLIC, avant la branche  ║
	# ║ laser ; l'événement `fire` du CONDOR, lui, n'est émis qu'au tir échu (`laser_lead_ticks`    ║
	# ║ plus tard). Recaler la porte sur la cadence ENTIÈRE à cet instant la repoussait de 0,5 s —  ║
	# ║ et depuis que `_arm_bolt` s'y branche, le clac de culasse annonçait « prête » une           ║
	# ║ demi-seconde APRÈS la disponibilité réelle. La sonde compare la porte AVANT/APRÈS.          ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 14. reconciliation de cadence : le CONDOR ne repousse plus sa propre porte ---")
	_init_duel(duel, ["vipere", "condor"], PROBE_TICK_RATE_HZ, "section 14")
	var lead_c: int = _lead_ticks(duel, "condor")
	var lead_c_s: float = float(lead_c) / PROBE_TICK_RATE_HZ
	duel._buffer = []
	duel._on_state(_msg(1200, "condor", 4, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 500.0
	duel._pred_fire_ready = 0.0
	duel._pred_stance = "up"
	duel._fire_queued = false
	duel._fire_fx_mute = 0.0
	duel._queue_fire()
	var predicted: float = duel._pred_fire_ready       # 500 + 29/8 = 503,625 (section 11)
	# LE TIR RÉEL arrive `laser_lead_ticks` plus tard : c'est là que le serveur émet `fire`.
	duel._clock = 500.0 + lead_c_s
	duel._fire_fx_mute = 1.0                           # on n'observe QUE la porte, pas le son
	duel._on_duel_event({"type": "fire", "slot": 1, "weapon": "condor", "rounds": 1, "ammo": 3})
	_ok("CONDOR : la porte confirmee == la porte predite au clic (pas de demi-seconde en plus)",
		absf(duel._pred_fire_ready - predicted) < 1e-4,
		"predite %.4f · confirmee %.4f" % [predicted, duel._pred_fire_ready])
	# LA MESURE DU DÉFAUT D'AVANT : la cadence ENTIÈRE à cet instant = la porte + laser_lead_ticks.
	_ok("l'ancien recalage retardait d'EXACTEMENT laser_lead_ticks (%d ticks = %.3f s)"
		% [lead_c, lead_c_s],
		absf((duel._clock + duel._cadence_seconds("condor")) - predicted - lead_c_s) < 1e-4,
		"ancienne porte %.4f contre %.4f"
		% [duel._clock + duel._cadence_seconds("condor"), predicted])
	# NON-RÉGRESSION : une arme SANS télégraphe garde la cadence entière — celle de la FIXTURE, au
	# rythme ANNONCÉ (le `600.9` d'avant recopiait le 18/20 de production : plus rien ne coïncide).
	duel._clock = 600.0
	duel._on_duel_event({"type": "fire", "slot": 1, "weapon": "vipere", "rounds": 1, "ammo": 7})
	_ok("arme ordinaire (lead 0) : porte = cadence ENTIERE du registre de test (600 + %d/%.0f)"
		% [int(PROBE_WEAPONS["vipere"]["cooldown_ticks"]), PROBE_TICK_RATE_HZ],
		absf(duel._pred_fire_ready - (600.0 + cad_vipere)) < 1e-4,
		"pred_fire_ready = %.4f (attendu %.4f)" % [duel._pred_fire_ready, 600.0 + cad_vipere])
	duel._fire_fx_mute = 0.0

	# --- 15. L'AMPLITUDE DU FEEL SOUS RAFALE : l'attenuation MESUREE, et le plafond -------------
	# ╔═ 🩸 CE QUE CETTE SECTION SOLDE ══════════════════════════════════════════════════════════╗
	# ║ Le cahier §4bis.4 exige que le cran de recul d'un coup SUIVEUR soit ATTÉNUÉ et que le      ║
	# ║ cumul reste BORNÉ. La mise en œuvre était correcte (`BURST_KICK_SCALE`, plafond de roulis  ║
	# ║ en sortie, punch de FOV POSÉ) — mais AUCUN contrôle ne mesurait une amplitude : ils        ║
	# ║ comptaient tous des incréments de `_shot_count`. Mettre `BURST_KICK_SCALE` à 1,0, c'est-   ║
	# ║ à-dire SUPPRIMER l'atténuation exigée, n'aurait fait rougir personne. Ici on mesure les    ║
	# ║ nombres, par le VRAI chemin (clic prédit puis pompage de la file), et on les compare :     ║
	# ║  • entre eux (le suiveur contre le premier) — aucune constante relue, donc `1.0` rougit ;  ║
	# ║  • au plafond du CAHIER (±0,3°) — pas à `ROLL_CAP_DEG`, qu'un sabotage lèverait avec lui.  ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
	print("\n--- 15. feel de rafale : le cran suiveur kicke MOINS, et le roulis reste borne ---")
	_init_duel(duel, ["vipere", "frelon"], PROBE_TICK_RATE_HZ, "section 15")
	var burst_scale: float = _duel_const("BURST_KICK_SCALE")
	var fov_punch_deg: float = _duel_const("FOV_PUNCH_DEG")
	duel._reduced_motion = false          # sans quoi `_fire_feel_kick` rend la main sans rien poser
	duel._feel_fov_punch = true
	duel._feel_recoil = 1.0
	duel._buffer = []
	duel._on_state(_msg(1300, "frelon", 24, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 700.0
	duel._pred_fire_ready = 0.0
	duel._pred_stance = "up"
	duel._fire_queued = false
	duel._fire_fx_mute = 0.0
	duel._cam_roll.reset()
	duel._fov_punch.reset()
	duel._queue_fire()
	# ⚠️ `step(0.0)` n'intègre RIEN et ne décroît RIEN (garde `dt <= 0` des deux étages) : il ne fait
	# que recomposer `value = ressort + résidu`. On lit donc l'amplitude POSÉE, jamais datée.
	var first_roll: float = absf(duel._cam_roll.step(0.0))
	var first_fov: float = duel._fov_punch.value
	_ok("cran 1 : le kick de roulis EXISTE (une mesure muette ne prouverait rien)",
		first_roll > 0.0, "|roulis| = %.5f deg" % first_roll)
	_ok("cran 1 : le punch de FOV EXISTE", first_fov > 0.0, "FOV +%.4f deg" % first_fov)
	_ok("2 crans suiveurs planifies (c'est bien une rafale qu'on mesure)",
		duel._burst_queue.size() == 2)
	# Ressorts remis à zéro : on compare des amplitudes NUES, pas le cumul du cran 1 (qui mesurerait
	# autre chose). Le cran suiveur part par le VRAI pompage de la file, pas par un appel direct.
	duel._cam_roll.reset()
	duel._fov_punch.reset()
	plays_before = _plays()
	duel._clock = 700.0 + gap_s
	duel._step_burst_queue()
	var follow_roll: float = absf(duel._cam_roll.step(0.0))
	var follow_fov: float = duel._fov_punch.value
	_ok("cran suiveur : une detonation est bien partie (c'est le VRAI chemin qu'on mesure)",
		_plays() == plays_before + 1 and duel._burst_queue.size() == 1)
	_ok("cran suiveur : le kick existe encore (une attenuation n'est pas une suppression)",
		follow_roll > 0.0, "|roulis| = %.5f deg" % follow_roll)
	# ⚠️ LE CONTRÔLE QUI MANQUAIT. Il ne relit AUCUNE constante : il compare deux amplitudes
	# mesurées. Porter `BURST_KICK_SCALE` à 1,0 — supprimer l'atténuation du cahier — le fait rougir.
	_ok("ATTENUATION REELLE : le cran suiveur kicke STRICTEMENT moins que le premier",
		follow_roll < first_roll - 1e-9,
		"suiveur %.5f contre premier %.5f (rapport %.4f)"
		% [follow_roll, first_roll, follow_roll / maxf(1e-9, first_roll)])
	_ok("l'attenuation vaut exactement BURST_KICK_SCALE du code de production (%.2f)" % burst_scale,
		absf(follow_roll - first_roll * burst_scale) < 1e-6,
		"attendu %.5f, mesure %.5f" % [first_roll * burst_scale, follow_roll])
	_ok("punch de FOV : le cran suiveur POSE une valeur plus BASSE (jamais empilee)",
		follow_fov > 0.0 and follow_fov < first_fov - 1e-9,
		"suiveur +%.4f contre premier +%.4f" % [follow_fov, first_fov])

	# 15c. LE PLAFOND SOUS RAFALE, à intensité F10 MAXIMALE — sur ce que l'hôte PUBLIE (le mouchard).
	duel._buffer = []
	duel._on_state(_msg(1400, "frelon", 24, 0, 0, [], []))
	duel._burst_queue = []
	duel._clock = 800.0
	duel._pred_fire_ready = 0.0
	duel._pred_stance = "up"
	duel._fire_queued = false
	duel._fire_fx_mute = 0.0
	duel._feel_recoil = 2.0               # le maximum que `_apply_tuning` laisse passer (clampf 0..2)
	duel._cam_roll.reset()
	duel._fov_punch.reset()
	var real_world = duel._world
	var spy := FeelSpy.new()
	add_child(spy)
	duel._world = spy
	var raw_max := 0.0
	duel._queue_fire()
	duel._step_feel(0.0)
	raw_max = maxf(raw_max, absf(duel._cam_roll.value))
	for i in range(1, 3):
		duel._clock = 800.0 + float(i) * gap_s
		duel._step_burst_queue()
		duel._step_feel(0.0)
		raw_max = maxf(raw_max, absf(duel._cam_roll.value))
	var delivered: float = spy.max_abs_roll()
	var fov_delivered: float = spy.max_fov()
	var poses: int = spy.rolls.size()
	var spy_shots: int = spy.shots
	duel._world = real_world
	spy.queue_free()
	_ok("les 3 projectiles de la rafale ont bien ete presentes (mouchard : %d tirs)" % spy_shots,
		spy_shots == 3)
	# Une borne ne prouve rien si le scénario ne la sollicite jamais : on le vérifie AVANT de la lire.
	_ok("le scenario SOLLICITE vraiment le plafond (roulis brut cumule %.5f deg > %.2f)"
		% [raw_max, CAHIER_ROLL_CAP_DEG], raw_max > CAHIER_ROLL_CAP_DEG + 1e-6)
	_ok("PLAFOND TENU : le roulis PUBLIE par l'hote ne depasse jamais le cahier (±%.2f deg)"
		% CAHIER_ROLL_CAP_DEG, delivered <= CAHIER_ROLL_CAP_DEG + 1e-6,
		"max publie %.5f deg sur %d poses" % [delivered, poses])
	_ok("le clamp MORD vraiment (le brut deborde, le publie est borne)",
		delivered < raw_max - 1e-9, "publie %.5f contre brut %.5f" % [delivered, raw_max])
	_ok("le plafond du code de production EST celui du cahier (ROLL_CAP_DEG = %.3f)"
		% _duel_const("ROLL_CAP_DEG"), _duel_const("ROLL_CAP_DEG") <= CAHIER_ROLL_CAP_DEG + 1e-6)
	_ok("punch de FOV sous rafale : POSE, jamais empile (max publie +%.4f <= +%.4f deg)"
		% [fov_delivered, fov_punch_deg], fov_delivered <= fov_punch_deg + 1e-6)
	duel._feel_recoil = 1.0

	AudioManager._enabled = was_enabled

	# SORTIE PROPRE — le rapport « resources still in use at exit » nommait ce qu'on laissait en
	# vie : un playback dont la libération (au pas de mixage du pilote Dummy) course le quit. On
	# laisse donc les DERNIERS one-shots s'achever ET le minuteur des retombées (0,4 s) passer,
	# on libère le duel, puis on coupe et purge NOUS-MÊMES les lecteurs — l'`_exit_tree` du
	# manager le fait aussi, mais APRÈS le point où le moteur compte les ressources.
	await get_tree().create_timer(2.0).timeout
	duel.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for p in AudioManager._sfx_players:
		p.stop()
		p.stream = null
	if AudioManager._music_player != null:
		AudioManager._music_player.stop()
		AudioManager._music_player.stream = null
	await get_tree().process_frame

	print("\n%s" % ("TOUT VERT" if _fails.is_empty()
		else "ECHEC : %d controle(s) rouge(s) : %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _push_state(duel) -> void:
	duel._on_state({"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": 8, "bandages": 1, "aiming": true, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": 2, "stance": "up", "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": 8, "bandages": 1, "aiming": true, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false}],
		"projectiles": [], "events": []})


# §2bis — la ROTATION d'une famille, éprouvée par le VRAI `play_sfx` (patron de la section 2) :
# 3 tours complets -> jamais deux fois la même variante d'affilée, TOUTES servies, indices bornés.
func _check_rotation(base: String) -> void:
	if not AudioManager._sfx_variants.has(base):
		_ok("famille %s decouverte sur disque" % base, false)
		return
	var variants: int = (AudioManager._sfx_variants[base] as Array).size()
	var seq: Array = []
	for i in variants * 3:
		AudioManager.play_sfx(base)
		seq.append(int(AudioManager._variant_last[base]))
	var repeat_found := false
	var used := {}
	var bounded := true
	for i in seq.size():
		used[seq[i]] = true
		if int(seq[i]) < 0 or int(seq[i]) >= variants:
			bounded = false
		if i > 0 and seq[i] == seq[i - 1]:
			repeat_found = true
	_ok("%s : %d tirages — jamais 2x d'affilee, %d/%d variantes servies, indices bornes"
		% [base, seq.size(), used.size(), variants],
		not repeat_found and used.size() == variants and bounded)


# §2bis (correctif) — LES 3 PROJECTILES D'UNE RAFALE FRELON, tels que la sim les écrit AU MÊME
# TICK : `_fire_burst` fait `launch = tick + i × burst_gap_ticks` et `_spawn` les APPEND tout de
# suite. L'espacement (2 ticks) est celui du registre injecté au duel — pas un barème recopié.
# ⚠️ DURCISSEMENT 2ter : l'espacement ne vient plus d'un `2` recopié (le barème de production) mais
# de `PROBE_LAUNCH_OFFSETS` — irrégulier et introuvable au registre réel.
func _enemy_burst(tick: int) -> Array:
	var out: Array = []
	for i in 3:
		var launch: int = tick + int(PROBE_LAUNCH_OFFSETS[i])
		out.append({"id": 71 + i, "kind": "frelon", "owner_slot": 2, "from_pos": 2,
			"target_pos": 2, "launch_tick": launch, "impact_tick": launch + 1,
			"aim_yaw": 0.0, "aim_pitch": 0.0, "target_x": 0.0})
	return out


# §2bis (correctif) — LE COMPTE DES TRAÇANTES RÉELLEMENT RENDUES, mesuré sur les nœuds du monde
# (pas sur le tableau intermédiaire : ce qui compte est ce qui s'affiche). Un état isolé est poussé
# — `_render_pair` rend alors [latest, latest, 1.0], donc `render_tick` == le tick de cet état.
func _visible_tracers(duel, tick: int, projectiles: Array) -> int:
	duel._buffer = []
	duel._world._local_tracers = []
	duel._on_state(_msg(tick, "frelon", 24, 0, 0, projectiles, []))
	duel._refresh_view(0.016)
	var count := 0
	for node in duel._world._tracers:
		if (node as MeshInstance3D).visible:
			count += 1
	return count


# §2bis (correctif) — LE MÊME COMPTE, AVEC LE TAMPON DE RENDU RÉEL. Une sonde qui pousse UN SEUL
# état lit `render_tick` == le tick de cet état (`_render_pair` rend alors [latest, latest, 1.0]) :
# elle ne voit PAS le retard de `RENDER_DELAY`, et deux gardes très différentes y paraissent
# identiques (mesuré : le remède « launch > render_tick » passe cette sonde-là et efface pourtant
# toutes les traçantes en vol). On fabrique donc le tampon à la main — deux états espacés d'un
# tick, horodatés pour que la cible de rendu tombe À MI-CHEMIN : le régime réel du duel, et la
# marge (± 25 ms) met le contrôle à l'abri du jitter d'horloge. §8.151 — « respecter le tampon ».
func _visible_tracers_buffered(duel, tick: int, projectiles: Array) -> int:
	var now: float = duel._now()
	duel._world._local_tracers = []
	duel._buffer = [
		{"at": now - 0.075, "data": _msg(tick - 1, "frelon", 24, 0, 0, [], [])},
		{"at": now - 0.025, "data": _msg(tick, "frelon", 24, 0, 0, projectiles, [])}]
	duel._refresh_view(0.016)
	var count := 0
	for node in duel._world._tracers:
		if (node as MeshInstance3D).visible:
			count += 1
	return count


# §2bis — un message d'état PARAMÉTRÉ (armes/chargeur/lasers/projectiles/événements) : le gabarit
# de `_push_state`, ouvert aux scénarios de rafale et de télégraphe des sections 8-10.
func _msg(tick: int, my_weapon: String, my_ammo: int, laser_mine: int, laser_theirs: int,
		projectiles: Array, events: Array) -> Dictionary:
	return {"type": "trench_state", "tick": tick, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 100, "weapon": my_weapon,
				"hits_total": 0, "grenades": 2, "ammo": my_ammo, "bandages": 1, "aiming": true,
				"hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": laser_mine,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": 2, "stance": "up", "hp": 100, "weapon": "frelon",
				"hits_total": 0, "grenades": 2, "ammo": 24, "bandages": 1, "aiming": true,
				"hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": laser_theirs,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false}],
		"projectiles": projectiles, "events": events}
