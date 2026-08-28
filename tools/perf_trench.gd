extends Node
# OUTIL (hors CI) — BUDGET DE PERFORMANCE du monde 3D texturé de LA TRANCHÉE.
# v2 (LOT 0 §8.151) : la MOYENNE ne suffit plus — fenêtre de JEU SIMULÉ + p50/p95/p99/pire frame
# + attribution des saccades. La moyenne du §8.139 reste en fin de passe (écart texturé/greybox).
#
# ╔═ ⚠️⚠️ ON MESURE DES MILLISECONDES, PAS DES IMAGES PAR SECONDE ════════════════════════════════╗
# ║ La session §8.139 a rendu « 13,33 ms pour les trois configurations, soit 75,00 FPS pile ».      ║
# ║ Ce n'était pas une performance : c'était la VSYNC. Trois rendus de coûts très différents        ║
# ║ affichaient le même chiffre parce qu'ils attendaient tous le même balayage écran. Un compteur   ║
# ║ de FPS ne peut PAS mesurer un rendu plus rapide que l'écran — il mesure l'écran.                ║
# ║ D'où les deux règles de ce fichier : vsync COUPÉE avant le premier chiffre, et temps de frame   ║
# ║ en ms (le budget du bon de commande : pas plus de +2 ms vs le greybox).                         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ POURQUOI LA MOYENNE MENTAIT — LA LEÇON DE LA RÉFÉRENCE (Claude-of-Duty, README §Performance) ═╗
# ║ Leur benchmark statique affichait 94 fps pendant que le JEU réel tombait à 12-17 fps, avec des ║
# ║ stalls de 728-1236 ms de compilation de shaders EN PLEINE FRAME au premier tir. « La médiane   ║
# ║ cache le problème » : une saccade de 100 ms noyée dans 600 frames de 4 ms est invisible dans    ║
# ║ une moyenne, et c'est pourtant ELLE que la main sent. D'où cette v2 :                           ║
# ║   • une fenêtre de jeu SIMULÉ (mouvements + tirs + grenade — pas une caméra qui balaie) ;       ║
# ║   • le tri du ring-buffer des delta → p50 / p95 / p99 / pire frame ;                            ║
# ║   • chaque frame > 33 ms est ATTRIBUÉE : horodatage + dernier événement notable du journal.     ║
# ║ C'est la ligne de départ du chantier : E devra la battre, C et D ne doivent pas la dégrader.    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire : en headless, rien ne rend, donc rien ne se mesure.
#   & <godot_console> --path frontend res://tools/perf_trench.tscn
# ⚠️ CONTRE-ÉPREUVE DE SABOTAGE (LOT 0) : ajouter « -- --saboter » à la ligne de commande injecte
#   une frame de ~100 ms au milieu de la fenêtre — elle DOIT ressortir en pire frame ET en
#   attribution (SABOTAGE_STALL). Sans l'argument, l'injection n'existe pas : c'est la preuve,
#   rejouable par le LOT E, que le harnais attrape bien ce qu'il prétend attraper.
#
# ╔═ §8.151 (2ter, CORRECTIF) — LA PORTE « 0 ERROR » N'ÉTAIT TENUE PAR RIEN ══════════════════════╗
# ║ 🩸 CE QUI N'ALLAIT PAS. Trois exécutions sur six se terminaient par                            ║
# ║ « ERROR: 1 resources still in use at exit » (+ « 2 ObjectDB instances were leaked at exit ») et ║
# ║ rendaient malgré tout **EXIT=0**. Le code retour ne disait rien de l'ERROR : une vraie erreur   ║
# ║ de fermeture — ou une fuite qui grossirait — serait passée inaperçue de quiconque ne lit que le ║
# ║ code retour. Circonscrit au HARNAIS, pas au jeu : la MÊME scène de duel instanciée par          ║
# ║ `probe_trench_hud` en fenêtré ne fuit rien, et aucune sonde headless ne produit une ligne ERROR.║
# ║                                                                                                 ║
# ║ ⚠️ CE QU'UN SCRIPT GODOT NE PEUT PAS FAIRE, DIT PLUTÔT QUE MAQUILLÉ : l'ERROR de sortie est     ║
# ║ émise par le moteur APRÈS `quit()`, pendant `ResourceCache::clear()` / `ObjectDB::cleanup()`.   ║
# ║ Aucun code GDScript ne s'exécute encore à cet instant, et le moteur n'expose aucun crochet de   ║
# ║ relecture de ses propres erreurs hors éditeur. On ne peut donc pas « lire l'ERROR » — on peut   ║
# ║ EXIGER que le processus soit QUIESCENT avant de quitter, et rougir sinon. C'est ce que fait la  ║
# ║ SENTINELLE DE SORTIE ci-dessous, en trois volets :                                              ║
# ║   1. TOUT CE QUE LE HARNAIS A INSTANCIÉ EST PROUVÉ MORT — un `WeakRef` par nœud construit, et   ║
# ║      la sortie exige zéro survivant (le compte d'orphelins et de nœuds doit revenir à sa        ║
# ║      référence d'avant construction) ;                                                          ║
# ║   2. LE DRAIN — on ne quitte plus une frame après le dernier `queue_free()`. Les libérations    ║
# ║      sont différées (file de suppression) et les RID partent vers le thread de rendu : on avance ║
# ║      jusqu'à ce que les compteurs d'objets NE BOUGENT PLUS pendant DRAIN_STABLE frames. C'est   ║
# ║      exactement le genre de course qui explique qu'`--verbose` (plus lent) ne reproduise pas la ║
# ║      fuite ;                                                                                    ║
# ║   3. LA FUITE DE CYCLE — trois montages/démontages IDENTIQUES du monde texturé après la mesure. ║
# ║      Le premier absorbe les allocations de première fois ; les deux suivants doivent rendre des ║
# ║      compteurs qui NE GROSSISSENT PAS. Comparer un cycle à lui-même est immunisé contre le      ║
# ║      plancher du `ResourceCache` (une texture chargée reste cachée : ce n'est pas une fuite).   ║
# ║ Et le code retour SUIT : `EXIT != 0` dès que le budget OU la sentinelle rougit.                 ║
# ║                                                                                                 ║
# ║ ⚠️ CONTRE-ÉPREUVE DE LA SENTINELLE : « -- --fuiter » fait FUIR le harnais pour de bon (les nœuds ║
# ║ construits sont détachés au lieu d'être libérés). Les trois volets doivent rougir et EXIT=1.    ║
# ║ Une garde qu'aucun sabotage ne fait rougir est exactement ce qu'on corrige ici.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

const Blockout := preload("res://scripts/game/trench_blockout.gd")
const WorldScene := preload("res://scenes/game/trench_fp_world.tscn")
const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

const WARMUP_FRAMES := 90       # compilation des shaders, montée des caches : jamais dans la mesure
const SAMPLE_FRAMES := 240

# --- Fenêtre de jeu simulé (LOT 0) ----------------------------------------------------------------
const WINDOW_SECONDS := 12.0
# Préalloué, jamais réalloué en cours de fenêtre : à ~1000 fps vsync coupée, 12 s < 12000 frames.
# Si la capacité est atteinte avant l'heure, la fenêtre s'arrête et le rapport le DIT.
const RING_CAPACITY := 20000
const STUTTER_MS := 33.0        # le seuil du bon de commande : une frame > 33 ms est une saccade
const SETTLE_SECONDS := 1.0     # l'« intro » : la scène est en place, les threads de bruit finissent
const SABOTAGE_AT_S := 6.0
const SABOTAGE_STALL_MS := 100.0
const MAX_SACCADE_LINES := 60   # au-delà, on résume — un log de 3000 lignes ne se lit pas

# --- La sentinelle de sortie (§8.151 2ter, correctif) ---------------------------------------------
const DRAIN_FRAMES := 300       # plafond DUR du drain : on ne boucle jamais sans fin
const DRAIN_STABLE := 30        # les compteurs doivent rester IMMOBILES autant de frames d'affilée
const LEAK_CYCLES := 3          # le 1er absorbe les allocations de première fois, les 2 autres jugent
const LEAK_CYCLE_FRAMES := 8    # de quoi laisser le monde se poser avant qu'on le démonte

var _duel: Control = null
var _ring := PackedFloat32Array()
var _frame_start := PackedFloat32Array()
var _frames := 0
var _events: Array = []         # {t, frame, label} — le journal corrélé aux frames
var _saboter := false
var _sabotage_done := false
# LA SENTINELLE DE SORTIE : un `WeakRef` par nœud que le harnais construit, la référence des
# compteurs prise AVANT toute construction, et le mode de sabotage qui fait fuir exprès.
var _fuiter := false
var _watched: Array = []        # Array[WeakRef] — ce que le harnais s'est engagé à rendre
var _detached: Array = []       # `--fuiter` seulement : les nœuds volontairement non libérés
var _ref_nodes := 0
var _ref_orphans := 0

# --- Le flux d'états 20 Hz (le faux serveur du scénario) ------------------------------------------
var _tick := 200
var _next_state_s := 0.0
var _enemy_pos := 3
var _enemy_hp := 100
var _enemy_aiming := true
var _stream_projectiles: Array = []
var _next_proj_id := 10
var _timeline: Array = []
var _cursor := 0


func _ready() -> void:
	_saboter = OS.get_cmdline_user_args().has("--saboter")
	_fuiter = OS.get_cmdline_user_args().has("--fuiter")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# LA RÉFÉRENCE DES COMPTEURS, PRISE AVANT LA PREMIÈRE CONSTRUCTION. Tout ce qui suit doit y
	# revenir : c'est la seule définition de « le harnais n'a rien laissé derrière lui » qui ne
	# dépende d'aucun chiffre écrit à la main.
	_ref_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_ref_orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("vsync : %s   (0 = DISABLED)" % DisplayServer.window_get_vsync_mode())
	print("sabotage : %s" % ("OUI (--saboter)" if _saboter else "NON"))
	print("fuite forcee : %s" % ("OUI (--fuiter)" if _fuiter else "NON"))
	print("reference sortie : %d noeuds, %d orphelins" % [_ref_nodes, _ref_orphans])

	# ⚠️ LA FENÊTRE DE JEU D'ABORD, le budget moyen ENSUITE. L'ordre n'est pas un détail : la
	# fenêtre veut le processus le plus FROID possible (c'est là que vivent les compilations de
	# pipeline du 1er tir et de la 1re explosion — l'attribution « premier_tir » que le LOT E doit
	# faire disparaître). Mesurer le greybox avant réchaufferait le monde et volerait la saccade.
	await _play_window()
	_report_window()

	# --- La mesure historique (§8.139) : écart texturé / greybox, budget +2 ms --------------------
	var greybox := await _measure(true)
	var textured := await _measure(false)
	var delta := textured - greybox
	print("\n  greybox nu ......... %6.3f ms/frame" % greybox)
	print("  monde texture ...... %6.3f ms/frame" % textured)
	print("  ecart .............. %+6.3f ms   (budget : +2,000 ms)" % delta)
	print("BUDGET|greybox_ms=%.3f|texture_ms=%.3f|ecart_ms=%.3f" % [greybox, textured, delta])
	print("\n%s" % ("DANS LE BUDGET" if delta <= 2.0 else "HORS BUDGET"))

	# ⚠️ LA SENTINELLE PASSE APRÈS TOUTES LES LIGNES DE MESURE : elle monte et démonte des mondes,
	# donc elle ne doit jamais tomber DANS une fenêtre chronométrée.
	var clean := await _exit_gate()
	print("VERDICT|budget=%s|sortie=%s" % ["OK" if delta <= 2.0 else "HORS_BUDGET",
		"PROPRE" if clean else "SALE"])
	# ⚠️ LE SABOTAGE REND SES NŒUDS APRÈS LE VERDICT, et c'est délibéré : la sentinelle a DÉJÀ
	# tranché sur des `WeakRef` vivants, le code retour est posé. Laisser au moteur un millier de
	# nœuds orphelins porteurs de RID ne prouverait rien de plus — mesuré, ça fait tomber le
	# processus en 0xC0000005 pendant l'arrêt, et un code retour de PLANTAGE n'est pas le code
	# retour d'un REFUS. On veut lire « la garde a dit non », pas « le harnais s'est écrasé ».
	for node: Node in _detached:
		node.free()
	_detached.clear()
	get_tree().quit(0 if (delta <= 2.0 and clean) else 1)


# =================================================================================================
# LA SENTINELLE DE SORTIE — « le harnais n'a rien laissé derrière lui », et ça se prouve
# =================================================================================================
# Cf. le pavé d'en-tête pour le pourquoi. Ici, le comment — et ce que chaque volet garde.
func _exit_gate() -> bool:
	print("\n=== SENTINELLE DE SORTIE ===")
	# ╔═ 🩸 LA RESSOURCE RETENUE, NOMMÉE — ET C'ÉTAIT BIEN LE HARNAIS ═══════════════════════════════╗
	# ║ `--verbose` a fini par le dire : « Resource still in use: res://assets/audio/music/           ║
	# ║ menu_ambient.wav (AudioStreamWAV) », plus deux instances fuitées                              ║
	# ║ (`AudioStreamPlaybackWAV` + `AudioStreamWAV`, compteur de références 1). Le mécanisme est     ║
	# ║ exact et sans mystère : `trench_fp.gd::_exit_tree()` REND LA RADIO DU QG en sortant           ║
	# ║ (`AudioManager.start_menu_ambient()`, symétrique de `start_battle_ambient` — c'est le bon     ║
	# ║ comportement pour le JEU, qui retourne aux menus). Le harnais, lui, ne retourne nulle part :  ║
	# ║ il libère le duel et quitte, laissant une musique EN COURS DE LECTURE. Une lecture vivante    ║
	# ║ tient son flux, et le flux tient son fichier — d'où l'ERROR au moment où le moteur vide son   ║
	# ║ cache de ressources, APRÈS le `quit()`, là où plus aucun script ne tourne.                    ║
	# ║ Rien à corriger dans le jeu : c'est au harnais d'éteindre ce qu'il a allumé.                  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	AudioManager.stop_ambient()
	AudioManager.stop_arena_ambience()
	AudioManager.stop_hub_ambience()
	# VOLET 1 + 2 : le drain, puis le relevé de ce qui a survécu à la mesure elle-même.
	var drained: bool = await _drain()
	var after_measure := _snapshot()
	var survivors := _alive()
	print("SORTIE|etape=mesure|survivants=%d|noeuds=%d(ref %d)|orphelins=%d(ref %d)|objets=%d|ressources=%d|drain=%s"
		% [survivors, int(after_measure["noeuds"]), _ref_nodes, int(after_measure["orphelins"]),
			_ref_orphans, int(after_measure["objets"]), int(after_measure["ressources"]),
			"STABLE" if drained else "JAMAIS_STABLE"])

	# VOLET 3 : la fuite de CYCLE. Trois montages/démontages identiques ; le premier absorbe les
	# allocations de première fois, les deux suivants doivent rendre des compteurs qui NE
	# GROSSISSENT PAS. On compare un cycle à lui-même : le plancher du `ResourceCache` s'annule.
	var cycles: Array = []
	for i in range(LEAK_CYCLES):
		await _leak_cycle()
		var shot := _snapshot()
		cycles.append(shot)
		print("SORTIE|etape=cycle%d|survivants=%d|noeuds=%d|orphelins=%d|objets=%d|ressources=%d"
			% [i + 1, _alive(), int(shot["noeuds"]), int(shot["orphelins"]),
				int(shot["objets"]), int(shot["ressources"])])
	var prev: Dictionary = cycles[LEAK_CYCLES - 2]
	var last: Dictionary = cycles[LEAK_CYCLES - 1]
	var growing: bool = int(last["objets"]) > int(prev["objets"]) \
		or int(last["ressources"]) > int(prev["ressources"]) \
		or int(last["noeuds"]) > int(prev["noeuds"])

	var final := _snapshot()
	var no_survivor: bool = _alive() == 0
	var nodes_back: bool = int(final["noeuds"]) <= _ref_nodes
	var orphans_back: bool = int(final["orphelins"]) <= _ref_orphans
	var clean: bool = no_survivor and nodes_back and orphans_back and drained and not growing
	print("SORTIE|survivants=%d(exige 0)|noeuds=%d(exige <=%d)|orphelins=%d(exige <=%d)|drain=%s|cycle_croissant=%s|VERDICT=%s"
		% [_alive(), int(final["noeuds"]), _ref_nodes, int(final["orphelins"]), _ref_orphans,
			"STABLE" if drained else "JAMAIS_STABLE", "OUI" if growing else "non",
			"PROPRE" if clean else "SALE"])
	if not clean:
		print("  ⚠️ SORTIE SALE — le processus n'est PAS quiescent : c'est dans cet etat que le")
		print("     moteur rend « resources still in use at exit » APRES le quit(), en silence.")
	return clean


# UN CYCLE DE MONTAGE/DÉMONTAGE du monde TEXTURÉ — identique d'un cycle à l'autre, c'est tout
# l'intérêt : ce qu'un cycle alloue, le suivant doit le retrouver déjà là.
func _leak_cycle() -> void:
	var world = WorldScene.instantiate()
	add_child(world)
	world.set_pose(2, "up", true)
	for i in range(LEAK_CYCLE_FRAMES):
		await get_tree().process_frame
	_release(world)
	await _drain()


# LA LIBÉRATION, EN UN SEUL ENDROIT — et elle prend un `WeakRef` au passage : sans lui, « le nœud a
# été libéré » ne serait qu'une intention. ⚠️ `--fuiter` DÉTACHE au lieu de libérer : le nœud reste
# vivant, orphelin, référencé — la fuite exacte que la sentinelle doit voir.
func _release(node: Node) -> void:
	_watched.append(weakref(node))
	if _fuiter:
		remove_child(node)
		_detached.append(node)
		return
	node.queue_free()


func _alive() -> int:
	var n := 0
	for ref: WeakRef in _watched:
		if ref.get_ref() != null:
			n += 1
	return n


# ⚠️ LE COMPTE D'OBJETS EST NET DES `WeakRef` DE LA SENTINELLE. Un `WeakRef` est un objet lui aussi :
# chaque cycle en ajoute un, et une sentinelle qui les compterait verrait le total grossir de 1 par
# cycle — elle rougirait sur SA PROPRE COMPTABILITÉ. Mesuré avant correction : 1765 / 1766 / 1767,
# c'est-à-dire trois cycles « croissants » qui n'avaient rien fuité du tout. Le faux positif le plus
# bête qui soit, et il aurait discrédité la garde entière au premier usage.
func _snapshot() -> Dictionary:
	return {
		"objets": int(Performance.get_monitor(Performance.OBJECT_COUNT)) - _watched.size(),
		"noeuds": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphelins": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"ressources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


# LE DRAIN — on ne quitte plus une frame après le dernier `queue_free()`. La suppression est
# DIFFÉRÉE (file de suppression de la `SceneTree`) et les RID partent vers le thread de rendu : on
# avance jusqu'à ce que les quatre compteurs ne bougent plus pendant DRAIN_STABLE frames d'affilée,
# ET que plus aucun nœud surveillé ne réponde. Plafond DUR : le drain ne boucle jamais sans fin, il
# rend `false` et la sentinelle le DIT.
func _drain() -> bool:
	var stable := 0
	var last := {}
	for i in range(DRAIN_FRAMES):
		await get_tree().process_frame
		var now := _snapshot()
		if _alive() == 0 and not last.is_empty() and _same(now, last):
			stable += 1
			if stable >= DRAIN_STABLE:
				return true
		else:
			stable = 0
		last = now
	return false


# ⚠️ COMPARAISON CHAMP PAR CHAMP, jamais `a == b` : l'égalité de `Dictionary` en GDScript compare
# l'INSTANCE, pas le contenu — deux relevés identiques y seraient déclarés différents, et le drain
# ne se stabiliserait jamais.
func _same(a: Dictionary, b: Dictionary) -> bool:
	for key in ["objets", "noeuds", "orphelins", "ressources"]:
		if int(a[key]) != int(b[key]):
			return false
	return true


# =================================================================================================
# LA FENÊTRE DE JEU SIMULÉ — mouvements + tirs + une grenade, scriptés (patron probe_trench_*)
# =================================================================================================
# ╔═ CE QUE LA FENÊTRE JOUE, ET POURQUOI PAR LES VRAIS CHEMINS ═══════════════════════════════════╗
# ║ Le duel COMPLET est instancié (monde 3D + ambiance + viewmodel + HUD + étalonnage), son        ║
# ║ `_process` reste ALLUMÉ (l'envoi réseau tombe en silence, socket fermé — vérifié dans          ║
# ║ `send_trench_input`), et le scénario passe par les entrées du jeu : `_queue_fire()` pour mes   ║
# ║ tirs (refus prédits compris), `_on_duel_event` pour les tirs/touches adverses, `_on_state` à   ║
# ║ 20 Hz pour le flux serveur, `_stance_toggle` pour la posture. Un harnais qui appellerait       ║
# ║ directement les fonctions de rendu mesurerait un jeu qui n'existe pas.                          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _play_window() -> void:
	SettingsManager.set_comfort("reduced_motion", false)
	SettingsManager.set_comfort("ui_scale", 1.0)
	DuelScript.pending_room_id = "999"
	_duel = DuelScene.instantiate()
	add_child(_duel)
	await get_tree().process_frame
	# Mise en scène blanche (patron preview_trench) : pas de backend → on coupe le bandeau et les
	# tentatives de reconnexion avant qu'ils ne polluent la fenêtre.
	if NetworkManager.server_connection_lost.is_connected(_duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(_duel._on_connection_lost)
	_duel._conn_banner.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_duel._on_init({"rules": _rules_20hz(), "your_slot": 1, "training": false,
		"opponent": {"name": "KOVACS", "is_bot": true}})
	# Une PAIRE d'états pour amorcer l'interpolation (tampon de rendu §8.141) — puis le flux 20 Hz
	# prend le relais DANS la fenêtre.
	_push_state()
	await get_tree().create_timer(0.06).timeout
	_tick += 1
	_push_state()
	# L'« intro » : on laisse la scène finir de se poser (textures de bruit sur thread, préchauffe
	# des particules d'ambiance). C'est l'équivalent de l'écran VS — le LOT E y logera son prewarm.
	await get_tree().create_timer(SETTLE_SECONDS).timeout

	_ring.resize(RING_CAPACITY)
	_frame_start.resize(RING_CAPACITY)
	_timeline = _build_timeline()
	_next_state_s = 0.0

	var elapsed := 0.0
	while elapsed < WINDOW_SECONDS and _frames < RING_CAPACITY:
		# ⚠️ Le scénario s'exécute APRÈS t0 : son coût (ingestion d'états 20 Hz comprise) fait
		# partie de la frame mesurée, exactement comme l'ingestion WebSocket en partie réelle.
		var t0 := Time.get_ticks_usec()
		_script_actions(elapsed)
		if _saboter and not _sabotage_done and elapsed >= SABOTAGE_AT_S:
			# LA CONTRE-ÉPREUVE : une attente active de ~100 ms DANS la frame. Elle doit ressortir
			# en pire frame ET en attribution — sinon le harnais est un faux témoin.
			_sabotage_done = true
			_log_event(elapsed, "SABOTAGE_STALL_%dms" % int(SABOTAGE_STALL_MS))
			var until := t0 + int(SABOTAGE_STALL_MS * 1000.0)
			while Time.get_ticks_usec() < until:
				pass
		await get_tree().process_frame
		var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		_frame_start[_frames] = elapsed
		_ring[_frames] = dt_ms
		_frames += 1
		elapsed += dt_ms / 1000.0

	# ⚠️ PAR `_release()`, jamais `queue_free()` en direct : c'est lui qui prend le `WeakRef` dont la
	# sentinelle de sortie a besoin pour PROUVER que ce duel est bien mort (cf. le pavé d'en-tête).
	_release(_duel)
	_duel = null
	await get_tree().process_frame


# Le SCÉNARIO — temps en secondes DE FENÊTRE. Chaque entrée est un événement notable du journal :
# c'est lui qui nomme les saccades. Cadence VIPÈRE 0,90 s → tirs espacés d'au moins 1,2 s (marge).
func _build_timeline() -> Array:
	return [
		{"t": 0.5, "kind": "tir", "label": "premier_tir"},
		{"t": 1.7, "kind": "tir", "label": "tir_2"},
		{"t": 2.3, "kind": "pas", "pos": 3, "label": "pas_droite"},
		{"t": 2.6, "kind": "pas_adverse", "pos": 2, "label": "pas_adverse_1"},
		{"t": 2.9, "kind": "tir", "label": "tir_3"},
		{"t": 3.2, "kind": "tir_adverse", "label": "tir_adverse_1"},
		{"t": 3.6, "kind": "touche", "label": "hitmarker_confirme"},
		{"t": 4.1, "kind": "tir", "label": "tir_4"},
		{"t": 4.4, "kind": "pas", "pos": 2, "label": "pas_gauche"},
		{"t": 4.8, "kind": "grenade_air", "label": "grenade_adverse_lancee"},
		{"t": 5.3, "kind": "tir", "label": "tir_5"},
		{"t": 5.4, "kind": "pas_adverse", "pos": 3, "label": "pas_adverse_2"},
		{"t": 5.6, "kind": "degat", "label": "degat_recu"},
		{"t": 6.3, "kind": "explosion", "label": "explosion_grenade_recue"},
		{"t": 6.9, "kind": "tir", "label": "tir_6"},
		{"t": 7.4, "kind": "stance", "down": true, "label": "accroupi"},
		{"t": 7.9, "kind": "stance", "down": false, "label": "debout"},
		{"t": 8.0, "kind": "pas_adverse", "pos": 4, "label": "pas_adverse_3"},
		{"t": 8.3, "kind": "grenade_mienne", "label": "grenade_mienne_lancee"},
		{"t": 8.7, "kind": "tir", "label": "tir_7"},
		{"t": 9.2, "kind": "pas", "pos": 3, "label": "pas_droite_2"},
		{"t": 9.8, "kind": "explosion_loin", "label": "explosion_grenade_envoyee"},
		{"t": 10.4, "kind": "tir", "label": "tir_8"},
		{"t": 10.6, "kind": "pas_adverse", "pos": 3, "label": "pas_adverse_4"},
		{"t": 11.2, "kind": "tir_adverse", "label": "tir_adverse_2"},
	]


func _script_actions(t: float) -> void:
	# --- Le flux d'états 20 Hz. Après une saccade, PLUSIEURS états tombent dans la même frame —
	# c'est ce que ferait la socket en livrant son retard, on ne le lisse surtout pas.
	var pushed := 0
	while t >= _next_state_s and pushed < 5:
		_tick += 1
		_push_state()
		_next_state_s += 0.05
		pushed += 1

	# --- Les actions du scénario, dans l'ordre, sans en sauter ------------------------------------
	while _cursor < _timeline.size() and t >= float(_timeline[_cursor]["t"]):
		var entry: Dictionary = _timeline[_cursor]
		_cursor += 1
		_run_action(entry, t)

	# --- La visée BALAIE en continu (celle du joueur qui suit sa cible) — via les variables que la
	# souris alimente, le `_process` du duel pousse lui-même vers la caméra.
	_duel._aim_yaw = sin(t * 1.7) * 38.0
	_duel._aim_pitch = sin(t * 0.9) * 6.0 - 1.0


func _run_action(entry: Dictionary, t: float) -> void:
	var label := str(entry["label"])
	match str(entry["kind"]):
		"tir":
			# Le VRAI chemin du clic : refus prédits, visée figée, retour d'arme, traçante locale.
			_duel._queue_fire()
		"pas":
			# La prédiction locale de position, comme `_process` l'applique sur une flèche.
			_duel._pred_pos = int(entry["pos"])
			_duel._world.set_pose(_duel._pred_pos, _duel._pred_stance)
			_duel._refresh_pose_view()
		"stance":
			# La posture passe par le VRAI drapeau : c'est `_process` qui fera le changement.
			_duel._stance_toggle = bool(entry["down"])
		"pas_adverse":
			_enemy_pos = int(entry["pos"])
		"tir_adverse":
			_duel._on_duel_event({"type": "fire", "slot": 2, "weapon": "vipere"})
			_spawn_enemy_bullet()
		"touche":
			_enemy_hp = maxi(0, _enemy_hp - 12)
			_duel._on_duel_event({"type": "hit", "slot": 2, "by": 1, "hp": _enemy_hp})
		"degat":
			_duel._on_duel_event({"type": "hit", "slot": 1, "by": 2, "hp": 76})
		"grenade_air":
			# La grenade adverse : événement + projectile dans le flux (cloche + marqueur au sol).
			# Vol 1,5 s = 30 ticks — le plancher du registre, cohérent avec l'impact à t+1,5 s.
			_duel._on_duel_event({"type": "grenade_thrown", "slot": 2})
			_stream_projectiles.append({"id": _next_proj_id, "kind": "grenade", "owner_slot": 2,
				"from_pos": _enemy_pos, "target_x": Geo.position_x(2), "launch_tick": _tick,
				"impact_tick": _tick + 30, "aim_yaw": 0.0, "aim_pitch": 0.0,
				"expire_tick": _tick + 30})
			_next_proj_id += 1
		"grenade_mienne":
			_duel._on_duel_event({"type": "grenade_thrown", "slot": 1})
			_stream_projectiles.append({"id": _next_proj_id, "kind": "grenade", "owner_slot": 1,
				"from_pos": _duel._pred_pos, "target_x": Geo.position_x(_enemy_pos),
				"launch_tick": _tick, "impact_tick": _tick + 30, "aim_yaw": 0.0, "aim_pitch": 0.0,
				"expire_tick": _tick + 30})
			_next_proj_id += 1
		"explosion":
			# L'explosion naît de l'ÉVÉNEMENT serveur (règle §8.141) — particules, secousse, audio.
			_duel._on_duel_event({"type": "impact", "kind": "grenade", "slot": 2,
				"target_x": Geo.position_x(2)})
		"explosion_loin":
			_duel._on_duel_event({"type": "impact", "kind": "grenade", "slot": 1,
				"target_x": Geo.position_x(_enemy_pos)})
	_log_event(t, label)


# Une balle adverse dans le flux d'états : vol 1 tick (règle d'or §8.141.2), retirée du flux 3
# états après l'impact — la traçante vit ~0,15 s, comme en partie.
func _spawn_enemy_bullet() -> void:
	_stream_projectiles.append({"id": _next_proj_id, "kind": "vipere", "owner_slot": 2,
		"from_pos": _enemy_pos, "target_pos": _duel._pred_pos, "launch_tick": _tick,
		"impact_tick": _tick + 1, "aim_yaw": 0.0, "aim_pitch": -1.0, "expire_tick": _tick + 4})
	_next_proj_id += 1


func _push_state() -> void:
	var projectiles: Array = []
	var alive: Array = []
	for proj in _stream_projectiles:
		if _tick <= int(proj["expire_tick"]):
			alive.append(proj)
			var clean: Dictionary = proj.duplicate()
			clean.erase("expire_tick")
			projectiles.append(clean)
	_stream_projectiles = alive
	_duel._on_state({
		"type": "trench_state", "tick": _tick, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": _duel._pred_pos, "stance": _duel._pred_stance, "hp": 88,
				"weapon": "vipere", "hits_total": 2, "grenades": 2, "ammo": 8, "bandages": 1,
				"aiming": true, "hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": 0,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": _enemy_pos, "stance": "up", "hp": _enemy_hp, "weapon": "vipere",
				"hits_total": 1, "grenades": 1, "ammo": 8, "bandages": 1, "aiming": _enemy_aiming,
				"hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": 0,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false},
		],
		"projectiles": projectiles, "events": [],
	})


func _log_event(t: float, label: String) -> void:
	_events.append({"t": t, "frame": _frames, "label": label})


# =================================================================================================
# LE RAPPORT — sortie texte STABLE et PARSABLE (les lots C/D/E se comparent à ces lignes)
# =================================================================================================
func _report_window() -> void:
	print("\n=== PERF TRANCHEE v2 (LOT 0 §8.151) — FENETRE DE JEU SIMULE ===")
	print("  scenario : 8 tirs + 4 pas + posture + 2 tirs adverses + 2 grenades (1 recue, 1 envoyee)")
	if _frames == 0:
		print("PERF|frames=0|ERREUR=fenetre vide")
		return
	if _frames >= RING_CAPACITY:
		print("  ⚠️ capacite du ring atteinte (%d frames) : fenetre TRONQUEE avant %0.1f s"
			% [RING_CAPACITY, WINDOW_SECONDS])

	var sorted := _ring.slice(0, _frames)
	sorted.sort()
	var worst_idx := 0
	for i in range(_frames):
		if _ring[i] > _ring[worst_idx]:
			worst_idx = i
	var stutters: Array = []
	for i in range(_frames):
		if _ring[i] > STUTTER_MS:
			stutters.append(i)
	var duration := _frame_start[_frames - 1] + _ring[_frames - 1] / 1000.0

	print("PERF|frames=%d|duree_s=%.3f|p50_ms=%.3f|p95_ms=%.3f|p99_ms=%.3f|pire_ms=%.3f|pire_frame=%d|pire_t_s=%.3f|saccades_sup_33ms=%d"
		% [_frames, duration, _pct(sorted, 0.50), _pct(sorted, 0.95), _pct(sorted, 0.99),
			_ring[worst_idx], worst_idx, _frame_start[worst_idx], stutters.size()])

	# Le repère que le LOT E devra battre : la pire frame dans la demi-seconde qui SUIT le 1er tir.
	for event in _events:
		if str(event["label"]) == "premier_tir":
			var t_evt := float(event["t"])
			var worst_after := 0.0
			for i in range(_frames):
				if _frame_start[i] >= t_evt and _frame_start[i] <= t_evt + 0.5:
					worst_after = maxf(worst_after, _ring[i])
			print("PREMIER_TIR|t_s=%.3f|pire_frame_ms=%.3f" % [t_evt, worst_after])
			break

	# --- L'ATTRIBUTION : chaque saccade, datée et rattachée au dernier événement notable ----------
	var shown := 0
	for i in stutters:
		if shown >= MAX_SACCADE_LINES:
			print("SACCADE|tronque=%d" % (stutters.size() - shown))
			break
		var attribution := "aucun_evenement"
		var age_ms := -1.0
		for event in _events:
			if float(event["t"]) <= _frame_start[i] + 0.0005:
				attribution = str(event["label"])
				age_ms = (_frame_start[i] - float(event["t"])) * 1000.0
			else:
				break
		shown += 1
		print("SACCADE|n=%d|frame=%d|t_s=%.3f|duree_ms=%.3f|evt=%s|age_ms=%.1f"
			% [shown, i, _frame_start[i], _ring[i], attribution, age_ms])

	# --- Le journal complet (la matière première de l'attribution, relisible après coup) ----------
	for event in _events:
		print("EVT|t_s=%.3f|frame=%d|label=%s" % [float(event["t"]), int(event["frame"]),
			str(event["label"])])


# Percentile au rang le plus proche sur le tableau TRIÉ : pas d'interpolation, pas de surprise.
func _pct(sorted: PackedFloat32Array, p: float) -> float:
	var idx := clampi(int(ceil(p * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return sorted[idx]


# Le barème 20 Hz du jour (§8.141.5 : mêmes durées en secondes qu'à 10 Hz, ticks doublés), la
# géométrie LUE dans le registre partagé — recopier une cote en dur recréerait la désynchronisation
# que `_check_geometry_match` traque (§8.141.6).
func _rules_20hz() -> Dictionary:
	return {
		"tick_rate_hz": 20, "rounds_to_win": 2, "round_ticks": 1800, "positions": Geo.POSITIONS,
		"hp_max": 100, "move_ticks": 10, "intermission_ticks": 60, "grace_disconnect_ticks": 200,
		"afk_ticks": 400,
		"grenade": {"stock_start": 2, "stock_max": 3, "regen_ticks": 300, "radius_m": 2.5,
			"damage_max": 40, "flight_base_s": 0.9, "flight_per_metre_s": 0.07,
			"flight_floor_ticks": 30, "target_margin_m": 1.5},
		"weapons": [
			{"id": "vipere", "name_key": "WEAPON_VIPERE", "burst": 1, "damage": 12,
				"cooldown_ticks": 18, "flight_ticks": 1, "laser_lead_ticks": 0,
				"dispersion_deg": 0.30, "mag_size": 8, "reload_ticks": 30},
			{"id": "frelon", "name_key": "WEAPON_FRELON", "burst": 3, "damage": 5,
				"cooldown_ticks": 24, "flight_ticks": 1, "laser_lead_ticks": 0,
				"dispersion_deg": 0.85, "mag_size": 24, "reload_ticks": 40},
			{"id": "chacal", "name_key": "WEAPON_CHACAL", "burst": 2, "damage": 8,
				"cooldown_ticks": 16, "flight_ticks": 1, "laser_lead_ticks": 0,
				"dispersion_deg": 0.45, "mag_size": 20, "reload_ticks": 44},
			{"id": "condor", "name_key": "WEAPON_CONDOR", "burst": 1, "damage": 30,
				"cooldown_ticks": 50, "flight_ticks": 1, "laser_lead_ticks": 10,
				"dispersion_deg": 0.0, "mag_size": 4, "reload_ticks": 50},
		],
		"escalation": {"frelon_hits": 4, "choice_hits": 10, "choice_options": ["chacal", "condor"],
			"choice_window_ticks": 100},
		"bandage": {"enabled": true, "per_round": 1, "heal": 25, "channel_ticks": 40},
		"geometry": {"version": Geo.TABLE_VERSION, "aim_quantum_deg": 0.1,
			"positions": Geo.POSITIONS, "no_mans_land": Geo.NO_MANS_LAND,
			"position_spacing": Geo.POSITION_SPACING, "parapet_y": Geo.PARAPET_Y,
			"eye_up": Geo.EYE_UP, "eye_down": Geo.EYE_DOWN},
	}


# =================================================================================================
# LA MESURE HISTORIQUE (§8.139) — écart texturé / greybox, inchangée
# =================================================================================================
func _measure(greybox: bool) -> float:
	Blockout.force_greybox = greybox
	var world = WorldScene.instantiate()
	add_child(world)
	world.set_pose(2, "up", true)
	for i in range(WARMUP_FRAMES):
		await get_tree().process_frame
	# La visée BALAIE pendant la mesure : une caméra immobile ne fait travailler ni le tri, ni le
	# recouvrement, ni le pavage triplanaire sous des angles rasants — elle mesurerait le cas le
	# plus favorable et l'appellerait « la performance ».
	# ⚠️ On chronomètre la FRAME ENTIÈRE (mur à mur), et non `Performance.TIME_PROCESS` : ce dernier
	# ne compte que le script, or tout ce que ce lot ajoute est du travail de RENDU.
	var total := 0.0
	for i in range(SAMPLE_FRAMES):
		world.set_aim(sin(float(i) * 0.05) * 32.0, sin(float(i) * 0.017) * 14.0)
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		total += float(Time.get_ticks_usec() - t0) / 1000.0
	_release(world)
	await get_tree().process_frame
	return total / float(SAMPLE_FRAMES)
