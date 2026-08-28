extends Node

# =================================================================================================
# SONDE §8.151 (VAGUE 2ter) — LE HUD DE COMBAT : réticule par arme, hitmarker, dégâts flottants,
# tir maintenu (cahier §4bis.1 / .2 / .3 / .5).
#
# ╔═ ⚠️⚠️ POURQUOI CETTE SONDE N'UTILISE PAS LES VALEURS DE PRODUCTION COMME SEULE FIXTURE ═══════╗
# ║ LEÇON DIRECTE DE L'ÉTAPE PRÉCÉDENTE. Le registre de production porte `dispersion_deg` 0,30 ·   ║
# ║ 0,85 · 0,45 · 0,00. Une sonde qui ne testerait QUE ces quatre-là serait VERTE sur une           ║
# ║ implémentation qui aurait recopié « 0.30 » en dur pour la VIPÈRE — la valeur attendue et la     ║
# ║ valeur trichée coïncident. Une garde qui ne peut pas distinguer la lecture du recopiage ne      ║
# ║ garde rien (§8.146 : « une garde qui ne voit qu'un délimiteur reste VERTE sur la faute »).      ║
# ║ On injecte donc, en plus des quatre armes réelles, un DOUBLE DE RÈGLES aux dispersions          ║
# ║ INVENTÉES (0,17° · 0,63° · 1,21° · 0,00°) et aux ids inventés (`essai_*`, pour qu'aucun         ║
# ║ aiguillage ne puisse s'accrocher au nom « condor »). Aucun chiffre en dur ne peut y survivre.   ║
# ║                                                                                                 ║
# ║ ⚠️ ET L'ATTENDU EST CALCULÉ PAR UNE ARITHMÉTIQUE INDÉPENDANTE : la sonde ne rappelle pas        ║
# ║ `_dispersion_pixels()` pour se comparer à elle-même (ce serait une tautologie). Elle refait le  ║
# ║ calcul de projection à la main, depuis le FOV de la CAMÉRA et la hauteur du viewport. Le jeu,   ║
# ║ lui, mesure par `project_aim` (la projection de la VISÉE, réutilisée).                          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ 🩸 ET CE N'A LONGTEMPS PAS SUFFI — LES « 0,000 px D'ÉCART » ÉTAIENT UNE IDENTITÉ ════════════╗
# ║ Première écriture de cette sonde : tout se mesurait à la visée CENTRÉE (0, 0). Or au centre,    ║
# ║ `aim_follow` valant 1 par défaut, la caméra REGARDE la visée : les deux bords du cône sont      ║
# ║ symétriques autour de l'axe optique, et la demi-distance projetée vaut `f·tan(d)` — c'est-à-    ║
# ║ dire, au chiffre près, la formule de REPLI de `_dispersion_pixels()`. Les deux « chemins »      ║
# ║ n'étaient pas deux chemins qui concordent : c'était une identité algébrique. MESURÉ par la      ║
# ║ boucle de critique : la branche `project_aim` de `_dispersion_pixels()` PUREMENT SUPPRIMÉE, la  ║
# ║ sonde restait `EXIT=0`, **58 PASS / 0 FAIL** — le sabotage était INVISIBLE, sur la propriété    ║
# ║ phare du §4bis.1 (« converti en pixels par la MÊME projection que la visée »).                  ║
# ║ Les deux arithmétiques ne divergent QUE là où la visée quitte l'axe de la caméra, c'est-à-dire  ║
# ║ dès que `aim_follow` < 1 — une valeur LÉGALE du curseur F10 (plage 0..1). La section 1bis pose  ║
# ║ donc `aim_follow = 0` (tête fixe), vise de côté, et compare à `f·(tan(a+d) − tan(a−d))/2`, la   ║
# ║ vraie demi-largeur d'un cône vu HORS AXE. Chaque mesure y est doublée d'une SENTINELLE qui      ║
# ║ vérifie que le repli `f·tan(d)` s'en écarte franchement : un contrôle dont les deux attendus    ║
# ║ coïncideraient ne prouverait rien, et c'est exactement ce qui s'était produit ici.              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ 🩸🩸 ET LA GARDE MESURAIT UNE FONCTION QUE LE DESSIN N'ÉTAIT PAS TENU D'APPELER ═════════════╗
# ║ Cet en-tête AFFIRMAIT le contraire : « on lit EXACTEMENT les fonctions que le dessin appelle…  ║
# ║ `_draw_reticle` n'a plus AUCUN chiffre à lui ». C'était FAUX en tant que garde. `_draw_reticle`║
# ║ calculait bel et bien son écartement (`var spread := _reticle_spread_px()`) — et il était le   ║
# ║ SEUL appelant de production de cette fonction. **Mesuré par la boucle de critique** : cette    ║
# ║ ligne remplacée par « var spread := 12.0 », la sonde restait `EXIT=0`, **84 PASS / 0 FAIL**,   ║
# ║ sur un réticule dont la taille peinte n'avait plus aucun rapport avec `dispersion_deg`. La     ║
# ║ section 1bis prouvait que la FORMULE d'écartement était juste ; rien ne prouvait que le        ║
# ║ PINCEAU s'en servait. Même famille de faux vert, remontée d'un cran.                           ║
# ║                                                                                                 ║
# ║ ⚠️ ET AUCUN HARNAIS GODOT NE PEUT RELIRE LES PIXELS : `--headless` rend par un pilote muet, et  ║
# ║ le moteur n'expose aucune relecture des primitives soumises à un `CanvasItem`. Tant que le      ║
# ║ pinceau DÉCIDE de quelque chose, ce qu'il décide est invérifiable — par construction.           ║
# ║ LA PRODUCTION A DONC CHANGÉ DE FORME (cf. le pavé de `_reticle_paint_list` dans trench_fp.gd) : ║
# ║ la géométrie peinte est devenue une VALEUR, et `_draw_reticle` un rejeu mécanique. La chaîne    ║
# ║ que cette sonde garde est désormais complète, et chaque maillon est contrôlé :                  ║
# ║   1. le signal `draw` du réticule EST branché sur `_draw_reticle` (contrôle d'exécution) ;      ║
# ║   2. la notification DRAW part pour de bon, même sous pilote muet (contrôle d'exécution) ;      ║
# ║   3. `_draw_reticle` ne fait que rejouer `_reticle_paint_list()` à travers `_paint_command`,    ║
# ║      sans un littéral numérique ni un argument qui ne vienne de la commande (AUDIT DE SOURCE —  ║
# ║      la contrepartie assumée de ce qu'aucun harnais ne peut observer à l'exécution) ;           ║
# ║   4. la LISTE, elle, est mesurée : c'est elle, et plus jamais `_reticle_spread_px()`, que les   ║
# ║      sections 1 et 1bis comparent à la dispersion LUE au registre.                              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# JAMAIS D'`assert` (il BLOQUE le harnais headless, §8.130) : prints PASS/FAIL puis `quit()`.

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const TuningScript := preload("res://scripts/game/trench_tuning.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

# LA SOURCE DE PRODUCTION, auditée à la lettre par la section 1quater (cf. l'en-tête).
const DUEL_SOURCE := "res://scripts/game/trench_fp.gd"

# Tolérance de la comparaison de projection, en pixels. Les deux arithmétiques sont exactes au
# centre de l'écran ; ce qui reste est de l'arrondi de matrice de projection.
const PIXEL_TOL := 0.75
# ⚠️ LA TOLÉRANCE DE LA POSITION DU RÉTICULE N'EST PAS CELLE-LÀ, et c'est important. « La croix est
# à `project_aim(visée) + secousse` » n'est pas une concordance de deux arithmétiques : c'est une
# ÉGALITÉ, terme à terme, entre ce que le HUD a posé et ce que la projection rend. Au centième de
# pixel — sinon un mensonge d'un dixième de pixel passerait, et le mensonge historique du §8.141.6
# (`aim_screen.y -= recul * 10`) ne vaut, roulis par défaut, que quelques pixels.
const EXACT_TOL := 0.01
# Pas de temps de l'entrelacement du contrôle d'invariant du pool : assez grand pour faire expirer
# les plus anciens chiffres un à un, assez petit pour que d'autres restent en vol.
const DAMAGE_STAGGER := 0.1

var _pass := 0
var _fails: Array = []
# Compteur des VRAIES notifications de dessin reçues (cf. `_real_draw`).
var _draws := 0
# Le régime de croix ORDINAIRE (cône non nul), relevé sur la première arme mesurée : c'est LUI qui
# sert de référence à la croix de PRÉCISION, plutôt qu'un 1,0/1,7 recopié de la production.
var _ordinary: Dictionary = {}


# Relevé le 2026-08-28 en headless, après la bascule du viewmodel 3D. À RELEVER À NOUVEAU
# si une section est volontairement ajoutée ou retirée — jamais à baisser pour faire passer.
const PASS_MINIMUM := 260


func _ok(label: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
	else:
		_fails.append(label)
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", label,
		("   | " + detail) if detail != "" else ""])


func _section(title: String) -> void:
	print("\n=== %s ===" % title)


func _ready() -> void:
	DuelScript.pending_room_id = "999"
	var duel = DuelScene.instantiate()
	add_child(duel)
	# ⚠️ ON COUPE LE `_process` DE L'HÔTE AVANT MÊME LA PREMIÈRE FRAME, et ce n'est pas cosmétique :
	# la section 0 mesure la croix TELLE QUE `_build_reticle()` l'a posée, c'est-à-dire avant qu'un
	# seul passage de `_process` n'ait eu l'occasion de la sauver. Coupé deux frames plus tard —
	# comme c'était le cas — ce contrôle-là ne mesurait plus rien. `set_process` est PAR NŒUD : le
	# monde 3D, lui, continue de tourner et pose sa caméra pendant les deux frames ci-dessous.
	duel.set_process(false)
	# Deux frames : la première monte les nœuds, la seconde laisse le monde 3D poser sa caméra
	# (`_cam_current` → `_camera.position` se fait dans SON `_process`, pas dans `_ready`).
	await get_tree().process_frame
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(duel._on_connection_lost)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	duel._tick_rate = 20.0
	duel._reduced_motion = false

	await _section_first_second(duel)
	await _section_reticle(duel)
	await _section_reticle_position(duel)
	_section_painter_audit(duel)
	await _section_held_fire(duel)
	_section_panels_grenade(duel)
	_section_panels_keyboard(duel)
	_section_mouse_capture(duel)
	await _section_damage(duel)
	await _section_damage_pixels(duel)
	_section_hitmarker(duel)
	_section_headshot(duel)
	_section_aide(duel)
	await _section_pixels(duel)

	print("\n%d PASS / %d FAIL" % [_pass, _fails.size()])
	# ╔═ 🩸 LE GARDE-FOU QUI MANQUAIT — ajouté au §8.152 (lot 3D-H) ═══════════════════════════╗
	# ║ Cette sonde annonçait « TOUT VERT » dès que `_fails` était vide, **sans jamais compter    ║
	# ║ ce qu'elle avait joué**. La bascule du viewmodel 3D a déplacé la grenade du clic droit    ║
	# ║ vers G : trois contrôles de la section grenade ne s'exécutaient plus du tout, la section  ║
	# ║ mourait sur une erreur de script — et la sonde disait TOUT VERT.                          ║
	# ║                                                                                          ║
	# ║ C'est exactement le défaut que le pavé du sabotage X8 décrit plus bas pour un AUTRE       ║
	# ║ contrôle, et qu'elle ne se gardait pas d'elle-même.                                       ║
	# ║ ⚠️ Un MINIMUM, pas une égalité : la passe fenêtrée en joue davantage que la passe headless ║
	# ║ (les sections de pixels). Une égalité stricte casserait la voie fenêtrée sans rien gagner.║
	# ╚══════════════════════════════════════════════════════════════════════════════════════════╝
	if _pass < PASS_MINIMUM and _fails.is_empty():
		print("INCOMPLETE : %d controles joues, %d attendus au minimum — une section est MUETTE"
			% [_pass, PASS_MINIMUM])
		get_tree().quit(1)
	print("%s" % ("TOUT VERT" if _fails.is_empty() else "ECHEC : " + ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


# =================================================================================================
# 0. LA PREMIÈRE SECONDE — AVANT QUE LE MOINDRE ÉTAT SERVEUR NE SOIT ARRIVÉ
# =================================================================================================
# ╔═ 🩸🩸 DEUX MENSONGES QUE 119 CONTRÔLES NE POUVAIENT PAS VOIR, ET LA RAISON EST LA MÊME ═══════╗
# ║ Toutes les autres sections POUSSENT un état (`_push`) avant de mesurer quoi que ce soit —      ║
# ║ `_section_reticle_position` le fait dès sa troisième ligne. Elles mesuraient donc toutes un    ║
# ║ HUD DÉJÀ INITIALISÉ, et la fenêtre qui précède le premier `trench_state` n'était gardée par    ║
# ║ RIEN. Or cette fenêtre n'est pas une frame : `trench_runner.py` attend les DEUX humains        ║
# ║ jusqu'à `CONNECT_TIMEOUT_S = 20 s` avant de créer l'état initial, et `_init_payload` envoie    ║
# ║ « state: None » jusque-là. En duel CLASSÉ, le premier connecté y passe des secondes entières.  ║
# ║                                                                                                 ║
# ║ (a) LA CROIX CLOUÉE DANS LE COIN HAUT-GAUCHE. La pose du réticule vivait DERRIÈRE le           ║
# ║     `if latest.is_empty(): return` de `_refresh_view`, et `_build_reticle()` ne posait aucune   ║
# ║     position : `_reticle.position` valait (0, 0). Pendant ce temps `_process` appelait          ║
# ║     `_world.set_aim()` sans condition — la CAMÉRA suivait la souris, la croix non.              ║
# ║ (b) LA CROIX DE PRÉCISION PEINTE POUR UNE VIPÈRE. `_dispersion_degrees()` rendait 0,0 quand    ║
# ║     l'arme était absente du registre — `_rules` vide compris — et `_reticle_is_precise()`       ║
# ║     testant `<= 0,0`, « dispersion inconnue » était rendue comme « dispersion nulle » :         ║
# ║     la promesse propre au CONDOR (« ce coup part exactement là ») affichée pour l'arme de       ║
# ║     départ à 0,30°. C'est mot pour mot ce que la décision §1.9 interdit.                        ║
# ║                                                                                                 ║
# ║ ⚠️ CETTE SECTION DOIT RESTER LA PREMIÈRE, ET NE JAMAIS POUSSER D'ÉTAT AVANT SES MESURES : sa    ║
# ║ sentinelle exige registre ET tampon vides, et c'est cette exigence qui la rend porteuse.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_first_second(duel) -> void:
	_section("0. LA PREMIERE SECONDE — registre et tampon VIDES (jusqu'a 20 s en COMPETITION)")
	var screen: Vector2 = duel.size
	var middle: Vector2 = screen * 0.5
	_ok("SENTINELLE : aucun etat serveur — registre ET tampon vides",
		duel._rules.is_empty() and duel._buffer.is_empty(),
		"_rules %d entree(s), _buffer %d etat(s), ecran %s"
		% [duel._rules.size(), duel._buffer.size(), str(screen)])

	# --- a) AVANT LE MOINDRE `_process` : `_build_reticle()` a déjà posé la croix ---------------
	# ⚠️ Le `_process` de l'hôte est coupé depuis `add_child` (cf. le pavé de `_ready`) : ce qu'on
	# lit ici est LA POSE DE CONSTRUCTION, pas le rattrapage d'une frame de jeu.
	# ⚠️ LE SEUIL EST LE QUART DE LA DIAGONALE, PAS QUELQUES PIXELS. Un réticule cloué à (0, 0)
	# peint quand même son centre à (40, 40) — la moitié de sa boîte : un contrôle « à plus de
	# 1,5 px du coin » serait resté VERT sur le défaut exact qu'il prétend garder. Mesuré.
	var corner_floor: float = screen.length() * 0.25
	_ok("A LA CONSTRUCTION : la croix n'est pas clouee au coin (0, 0) du `Control` neuf",
		_reticle_center(duel).distance_to(Vector2.ZERO) > corner_floor,
		"centre peint %s, a %.1f px du coin (plancher %.1f px)"
		% [str(_reticle_center(duel)), _reticle_center(duel).distance_to(Vector2.ZERO),
			corner_floor])
	_ok("A LA CONSTRUCTION : elle est au CENTRE de l'ecran (la visee est au repos)",
		_reticle_center(duel).distance_to(middle) < EXACT_TOL,
		"centre peint %s / attendu %s" % [str(_reticle_center(duel)), str(middle)])

	# --- b) ET LE CHEMIN DE PRODUCTION L'Y REPOSE À CHAQUE FRAME, SANS AUCUN ÉTAT ---------------
	# On la remet DÉLIBÉRÉMENT dans le coin : sans ce déplacement, le contrôle serait vert sur un
	# `_process` qui ne toucherait plus jamais au réticule (la pose de construction suffirait).
	duel._reticle.position = Vector2.ZERO
	duel._process(1.0 / 60.0)
	_ok("SANS AUCUN ETAT : `_process` repose la croix a la visee (la garde d'etat ne la saute plus)",
		_reticle_offset(duel).length() < EXACT_TOL, "ecart %s px" % str(_reticle_offset(duel)))
	_ok("SANS AUCUN ETAT : le tampon est TOUJOURS vide (rien n'a ete simule pour l'occasion)",
		duel._buffer.is_empty(), "%d etat(s)" % duel._buffer.size())

	# --- c) HORS AXE, TOUJOURS SANS ÉTAT : la croix suit la souris comme la caméra ---------------
	# `aim_follow = 0` (tête fixe) est le SEUL régime où « au centre » et « à la visée » se
	# distinguent — même raison qu'à la section 1bis, et l'attendu ne recopie aucun état du monde.
	duel._apply_tuning({"aim_follow": 0.0})
	var focal: float = (screen.y * 0.5) / tan(deg_to_rad(duel._world.camera_fov()) * 0.5)
	var yaw: float = duel._yaw_limit * 0.7
	var want: float = focal * tan(deg_to_rad(yaw))
	await _aim_at(duel, yaw)
	duel._process(1.0 / 60.0)
	var off_center: float = _reticle_center(duel).x - middle.x
	_ok("HORS AXE SANS ETAT : le controle est PORTEUR — le deport vaut franchement quelque chose",
		want >= OFFAXIS_MIN_DIVERGENCE,
		"deport attendu %.2f px (seuil %.2f px)" % [want, OFFAXIS_MIN_DIVERGENCE])
	_ok("HORS AXE SANS ETAT : la croix a QUITTE le centre de focale x tan(lacet)",
		absf(absf(off_center) - want) < PIXEL_TOL,
		"deport %.2f px / attendu %.2f px" % [off_center, want])
	_ok("HORS AXE SANS ETAT : et elle est EXACTEMENT a `project_aim(visee)`",
		_reticle_offset(duel).length() < EXACT_TOL, "ecart %s px" % str(_reticle_offset(duel)))
	duel._apply_tuning({"aim_follow": 1.0})
	await _aim_at(duel, 0.0)
	duel._process(1.0 / 60.0)

	# --- d) DISPERSION INCONNUE : croix ORDINAIRE, JAMAIS la promesse du Condor (§1.9) -----------
	# ⚠️ ON RELÈVE LE DESSIN DU DOUTE D'ABORD, registre encore vide — pousser quoi que ce soit
	# avant refermerait la seule fenêtre où « inconnu » existe.
	var unknown := _decode_cross(duel)
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	var ordinary := _decode_cross(duel)
	_push(duel, "condor", 99)
	var precise := _decode_cross(duel)
	_ok("SENTINELLE : les deux regimes de croix se DISTINGUENT vraiment (sinon rien a prouver)",
		float(precise["arm"]) > float(ordinary["arm"]) + 0.001
			and float(precise["width"]) < float(ordinary["width"]) - 0.001
			and float(precise["radius"]) < float(ordinary["radius"]) - 0.001,
		"precision %.2f/%.2f/%.2f contre ordinaire %.2f/%.2f/%.2f"
		% [float(precise["arm"]), float(precise["width"]), float(precise["radius"]),
			float(ordinary["arm"]), float(ordinary["width"]), float(ordinary["radius"])])
	_ok("REGISTRE VIDE : la croix peinte est l'ORDINAIRE (le doute ne promet rien)",
		is_equal_approx(float(unknown["arm"]), float(ordinary["arm"]))
			and is_equal_approx(float(unknown["width"]), float(ordinary["width"]))
			and is_equal_approx(float(unknown["radius"]), float(ordinary["radius"])),
		"peint %.2f/%.2f/%.2f (ordinaire %.2f/%.2f/%.2f)"
		% [float(unknown["arm"]), float(unknown["width"]), float(unknown["radius"]),
			float(ordinary["arm"]), float(ordinary["width"]), float(ordinary["radius"])])
	_ok("REGISTRE VIDE : ce n'est PAS la croix de PRECISION (aucune mecanique inventee)",
		not (is_equal_approx(float(unknown["arm"]), float(precise["arm"]))
			and is_equal_approx(float(unknown["width"]), float(precise["width"]))
			and is_equal_approx(float(unknown["radius"]), float(precise["radius"]))),
		"trait %.2f px / epaisseur %.2f / point %.2f (precision : %.2f / %.2f / %.2f)"
		% [float(unknown["arm"]), float(unknown["width"]), float(unknown["radius"]),
			float(precise["arm"]), float(precise["width"]), float(precise["radius"])])

	# … ET LE MÊME DOUTE AVEC UN REGISTRE NON VIDE : l'arme en main est absente de la liste reçue.
	# Sans ce second cas, un repli qui ne regarderait QUE « `_rules` est vide » passerait.
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _fake_weapons()}
	_push(duel, "vipere", 99)          # « vipere » n'existe pas dans le double : cône INCONNU
	var absent := _decode_cross(duel)
	_ok("ARME ABSENTE DU REGISTRE : croix ORDINAIRE elle aussi (meme doute, meme repli)",
		is_equal_approx(float(absent["arm"]), float(ordinary["arm"]))
			and is_equal_approx(float(absent["width"]), float(ordinary["width"]))
			and is_equal_approx(float(absent["radius"]), float(ordinary["radius"])),
		"peint %.2f/%.2f/%.2f" % [float(absent["arm"]), float(absent["width"]),
			float(absent["radius"])])
	_ok("ARME ABSENTE : l'ecartement retombe au trou de lisibilite (aucun cone invente)",
		absf(_painted_spread(duel) - duel.RETICLE_GAP_PX) < 0.001,
		"ecartement %.3f px / trou %.3f px" % [_painted_spread(duel), duel.RETICLE_GAP_PX])


# =================================================================================================
# 1. RÉTICULE PAR ARME (§4bis.1)
# =================================================================================================
func _section_reticle(duel) -> void:
	_section("1. RETICULE PAR ARME — 4 armes REELLES + 4 INVENTEES, au centre PUIS hors axe")
	var fov: float = duel._world.camera_fov()
	var half_h: float = duel.size.y * 0.5
	print("  (contexte : fov camera %.3f deg, demi-hauteur %.1f px, tolerance %.2f px)"
		% [fov, half_h, PIXEL_TOL])

	# --- 0) LE PINCEAU EST BRANCHÉ, ET IL PEINT POUR DE BON --------------------------------------
	# ⚠️ Les deux maillons d'EXÉCUTION de la chaîne décrite en en-tête. Sans eux, tout ce qui suit
	# mesurerait une liste que personne ne peint. `queue_redraw()` pousse un appelable dans la file
	# de messages : la notification DRAW part à la frame suivante MÊME sous `--headless` (le rendu
	# est muet, la notification ne l'est pas) — c'est vérifié ici, pas supposé.
	_ok("LE PINCEAU EST BRANCHE : `draw` du reticule est connecte a `_draw_reticle`",
		duel._reticle.draw.is_connected(duel._draw_reticle))
	await _real_draw(duel)
	_ok("LE DESSIN A LIEU : la notification DRAW part (pilote muet, notification bien vivante)",
		_draws > 0, "%d passage(s) de dessin" % _draws)

	# --- a) Les QUATRE armes du registre de PRODUCTION ------------------------------------------
	for entry in _production_weapons():
		duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
			"weapons": _production_weapons()}
		_push(duel, str(entry["id"]), 99)
		_check_reticle(duel, str(entry["id"]), float(entry["dispersion_deg"]), fov, half_h)

	# --- b) LE DOUBLE FAUSSÉ : des dispersions qui n'existent nulle part dans le dépôt ------------
	print("  --- double de regles : dispersions INVENTEES (aucun 0,30/0,45/0,85 ne peut coincider) ---")
	var fake := _fake_weapons()
	for entry in fake:
		duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
			"weapons": fake}
		_push(duel, str(entry["id"]), 99)
		_check_reticle(duel, str(entry["id"]), float(entry["dispersion_deg"]), fov, half_h)

	# --- b bis) LA PROPRIÉTÉ PHARE : « LA MÊME PROJECTION QUE LA VISÉE », MESURÉE HORS AXE --------
	await _section_offaxis(duel, fov, half_h)

	# --- c) LE PULSE : bref, POSÉ, et sans effet au repos ----------------------------------------
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	var rest: float = _painted_spread(duel)
	duel._fire_feel_kick()
	var pulsed: float = _painted_spread(duel)
	_ok("PULSE : le tir ecarte le reticule", pulsed > rest + 1.0,
		"repos %.2f px -> tir %.2f px" % [rest, pulsed])
	# ⛔ PAS DE BLOOM : trois coups d'affilée ne doivent PAS ouvrir davantage que le premier.
	duel._fire_feel_kick(0.6)
	duel._fire_feel_kick(0.6)
	var thrice: float = _painted_spread(duel)
	_ok("AUCUN BLOOM : 3 coups n'ouvrent pas plus que 1 (pose, jamais cumule)",
		absf(thrice - pulsed) < 0.001, "1 coup %.3f px / 3 coups %.3f px" % [pulsed, thrice])
	# RETOUR < CADENCE : la plus courte cadence du registre est la borne à battre.
	# ⚠️ ON AVANCE PAR FRAMES DE 1/60 s, jamais d'un seul `step(0,8)` : `TrenchSpring` plafonne à
	# 24 sous-pas de 1/360 s (66,7 ms) et ABANDONNE l'excédent — un pas géant ne mesurerait donc
	# que les 67 premières millisecondes et rendrait un résidu qui n'existe pas en jeu.
	var shortest := 999.0
	for w in duel._rules["weapons"]:
		shortest = minf(shortest, float(w["cooldown_ticks"]) / duel._tick_rate)
	for i in range(int(ceil(shortest * 60.0))):
		duel._reticle_pulse.step(1.0 / 60.0)
	var after: float = _painted_spread(duel)
	_ok("RETOUR < CADENCE : le pulse est eteint avant le tir suivant autorise",
		absf(after - rest) < 0.05,
		"cadence la plus courte %.3f s -> ecart residuel %.4f px" % [shortest, after - rest])
	duel._reticle_pulse.reset(0.0)

	# --- d) ⚠️⚠️ À QUI EST CE CÔNE ? ------------------------------------------------------------
	_section_whose_cone(duel, fov, half_h)


# =================================================================================================
# 1quinquies. À QUI EST CE CÔNE — la propriété phare du §4bis.1, enfin départageable
# =================================================================================================
# ╔═ 🩸 LA DETTE DE GARDE : TOUTES LES FIXTURES DONNAIENT LA MÊME ARME AUX DEUX JOUEURS ══════════╗
# ║ `_push_phase` posait `weapon_id` sur le slot 1 ET sur le slot 2 ; `_push_enemy` posait         ║
# ║ « frelon » des deux côtés. « Mon cône » et « son cône » étaient donc LITTÉRALEMENT le même     ║
# ║ nombre dans chaque mesure de cette sonde : aucun des 135 contrôles ne pouvait les départager.  ║
# ║ MESURÉ par la boucle de critique : `_dispersion_degrees()` l.2466 passé de `_my_slot` à        ║
# ║ `3 - _my_slot` — un seul signe — laissait la sonde `EXIT=0`, **135 PASS / 0 FAIL**, alors que  ║
# ║ les onze autres sabotages de la même session rougissaient tous.                                ║
# ║                                                                                                 ║
# ║ ET CE N'EST PAS THÉORIQUE. Côté serveur l'escalade est PAR TIREUR                              ║
# ║ (`trench_sim.py::_credit_hit` promeut le FRELON au seuil de touches, `_apply_pick` donne le    ║
# ║ chacal/condor du choix) : les deux joueurs portent RÉGULIÈREMENT des armes différentes en      ║
# ║ partie. Sous la régression, un joueur au FRELON (0,85°) se verrait peindre la croix de         ║
# ║ PRÉCISION du CONDOR — « ce coup part exactement là » — c'est-à-dire mot pour mot le mensonge   ║
# ║ que la décision §1.9 a été écrite pour tuer.                                                    ║
# ║                                                                                                 ║
# ║ C'est la leçon de l'étape précédente REMONTÉE D'UN CRAN : les fixtures ne sont plus les        ║
# ║ VALEURS de production (le double faussé s'en charge), mais elles restaient une CONFIGURATION   ║
# ║ que la production ne rencontre jamais. D'où `_push_pair` : chaque joueur porte SON arme, et    ║
# ║ chaque fixture porte sa propre sentinelle — si les deux lignes redevenaient identiques, la     ║
# ║ garde le DIRAIT au lieu de verdir pour la pire des raisons.                                    ║
# ║ ⚠️ ET LES DEUX SLOTS SONT JOUÉS : un `_player_of(_latest(), 1)` écrit en dur serait vert au    ║
# ║ slot 1 et faux au slot 2 — c'est la moitié du dépôt qui joue slot 2.                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_whose_cone(duel, fov: float, half_h: float) -> void:
	print("  --- A QUI EST CE CONE : les deux joueurs portent des armes DIFFERENTES ---")
	var fake := _fake_weapons()
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": fake}
	var saved_slot: int = duel._my_slot
	# TROIS CÔNES DU DOUBLE FAUSSÉ, jamais un chiffre de production : l'étroit, le large, et le NUL
	# (celui qui change la FORME de la croix, pas seulement sa taille).
	var narrow := {"id": str(fake[0]["id"]), "deg": float(fake[0]["dispersion_deg"])}   # 0,17°
	var wide := {"id": str(fake[2]["id"]), "deg": float(fake[2]["dispersion_deg"])}     # 1,21°
	var zero := {"id": str(fake[3]["id"]), "deg": float(fake[3]["dispersion_deg"])}     # 0,00°
	# LA SENTINELLE GLOBALE : sans un écart FRANC entre les deux cônes, « c'est bien le mien » serait
	# satisfait par n'importe lequel des deux — exactement le faux vert qu'on referme ici.
	var gap: float = absf(_expected_px(float(narrow["deg"]), fov, half_h)
		- _expected_px(float(wide["deg"]), fov, half_h))
	_ok("SENTINELLE : les deux cones se departagent FRANCHEMENT (sinon rien a prouver)",
		gap >= OFFAXIS_MIN_DIVERGENCE,
		"%.2f deg contre %.2f deg = %.3f px d'ecart (seuil %.3f px)"
		% [float(narrow["deg"]), float(wide["deg"]), gap, OFFAXIS_MIN_DIVERGENCE])
	# Les QUATRE couples, dans les DEUX sens : la taille (étroit/large et son miroir) et la FORME
	# (le cône nul est à moi, puis il est à lui — c'est le cas que le critique décrit mot pour mot).
	var couples: Array = [
		{"mine": narrow, "his": wide}, {"mine": wide, "his": narrow},
		{"mine": zero, "his": wide}, {"mine": wide, "his": zero},
	]
	for slot in [1, 2]:
		duel._my_slot = slot
		for couple: Dictionary in couples:
			var mine: Dictionary = couple["mine"]
			var his: Dictionary = couple["his"]
			_push_pair(duel, str(mine["id"]), str(his["id"]))
			_check_owner_cross(duel, slot, mine, his, fov, half_h)
	duel._my_slot = saved_slot
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)


# UNE fixture, TROIS contrôles : la fixture est-elle bien dissymétrique · l'écartement est-il CELUI
# DE MON ARME · la FORME est-elle celle de MON cône. Aucun chiffre de production n'entre ici : les
# cônes viennent du double faussé, l'attendu en pixels de l'arithmétique indépendante `_expected_px`,
# et le régime ORDINAIRE de référence est celui relevé plus haut sur une VRAIE mesure (`_ordinary`).
func _check_owner_cross(duel, slot: int, mine: Dictionary, his: Dictionary,
		fov: float, half_h: float) -> void:
	var tag := "slot %d, moi=%s (%.2f deg) / lui=%s (%.2f deg)" \
		% [slot, str(mine["id"]), float(mine["deg"]), str(his["id"]), float(his["deg"])]
	# (1) LA FIXTURE ELLE-MÊME — relue dans l'ÉTAT POUSSÉ, jamais dans les variables locales : c'est
	# le contrôle qui aurait dû exister depuis le début, et son absence est tout le défaut.
	var latest: Dictionary = duel._latest()
	var row_mine: Dictionary = duel._player_of(latest, slot)
	var row_his: Dictionary = duel._player_of(latest, 3 - slot)
	var armed_apart: bool = str(row_mine.get("weapon", "")) == str(mine["id"]) \
		and str(row_his.get("weapon", "")) == str(his["id"]) \
		and str(mine["id"]) != str(his["id"])
	_ok("SENTINELLE DE FIXTURE — %s : l'etat pousse porte bien DEUX armes distinctes" % tag,
		armed_apart, "slot %d porte « %s », slot %d porte « %s »"
		% [slot, str(row_mine.get("weapon", "")), 3 - slot, str(row_his.get("weapon", ""))])
	# (2) L'ÉCARTEMENT PEINT est celui de MON cône — pas du sien.
	var cross := _decode_cross(duel)
	var measured: float = float(cross["spread"])
	var expected: float = duel.RETICLE_GAP_PX + _expected_px(float(mine["deg"]), fov, half_h)
	var his_px: float = duel.RETICLE_GAP_PX + _expected_px(float(his["deg"]), fov, half_h)
	_ok("A QUI EST CE CONE — %s : l'ecartement PEINT est le MIEN" % tag,
		absf(measured - expected) < PIXEL_TOL, "peint %.3f px / le mien %.3f px / le SIEN %.3f px"
		% [measured, expected, his_px])
	# (3) LA FORME suit MON cône : croix de PRÉCISION si et seulement si c'est MOI qui porte le 0°.
	# ⚠️ C'est la moitié qui compte le plus : c'est elle qui rend visible « la promesse du CONDOR
	# peinte pour l'arme de l'autre », et elle ne dépend d'aucune tolérance en pixels.
	var ref := _ordinary
	var precise: bool = float(mine["deg"]) <= 0.0
	var painted_precise: bool = not ref.is_empty() \
		and float(cross["arm"]) > float(ref["arm"]) + 0.001 \
		and float(cross["width"]) < float(ref["width"]) - 0.001 \
		and float(cross["radius"]) < float(ref["radius"]) - 0.001
	var painted_ordinary: bool = not ref.is_empty() \
		and is_equal_approx(float(cross["arm"]), float(ref["arm"])) \
		and is_equal_approx(float(cross["width"]), float(ref["width"])) \
		and is_equal_approx(float(cross["radius"]), float(ref["radius"]))
	_ok("A QUI EST CE CONE — %s : la FORME est celle de MON cone" % tag,
		painted_precise if precise else painted_ordinary,
		"peint %.2f/%.2f/%.2f, attendu %s (ordinaire : %.2f/%.2f/%.2f)"
		% [float(cross["arm"]), float(cross["width"]), float(cross["radius"]),
			"PRECISION" if precise else "ORDINAIRE",
			float(ref.get("arm", -1.0)), float(ref.get("width", -1.0)),
			float(ref.get("radius", -1.0))])


# ⚠️ TOUT SE MESURE SUR LA CROIX PEINTE, jamais sur `_reticle_spread_px()` : c'est la correction du
# faux vert de la première livraison (cf. l'en-tête). `_decode_cross` ne recopie AUCUN chiffre de
# production — il lit la géométrie soumise au pinceau et en déduit l'écartement, la longueur du
# trait, son épaisseur et le rayon du point.
func _check_reticle(duel, weapon_id: String, degrees: float, fov: float, half_h: float) -> void:
	var cross := _decode_cross(duel)
	var measured: float = float(cross["spread"])
	var expected: float = duel.RETICLE_GAP_PX + _expected_px(degrees, fov, half_h)
	_ok("%s : ecartement PEINT = dispersion %.2f deg LUE au registre" % [weapon_id, degrees],
		int(cross["arms"]) == 4 and int(cross["dots"]) == 1
			and absf(measured - expected) < PIXEL_TOL,
		"peint %.3f px / attendu %.3f px (%d traits + %d point)"
		% [measured, expected, int(cross["arms"]), int(cross["dots"])])
	# LA CROIX DE PRÉCISION SE LIT DANS LE DESSIN, PAS DANS UN BOOLÉEN. Un cône nul doit peindre un
	# trait PLUS LONG, PLUS FIN et un point PLUS PETIT que le régime ordinaire — et le régime
	# ordinaire est celui qu'on vient de relever, pas un 1,0/1,7 recopié ici.
	if degrees > 0.0 and _ordinary.is_empty():
		_ordinary = cross
	var precise: bool = degrees <= 0.0
	var ref := _ordinary
	var painted_precise: bool = not ref.is_empty() \
		and float(cross["arm"]) > float(ref["arm"]) + 0.001 \
		and float(cross["width"]) < float(ref["width"]) - 0.001 \
		and float(cross["radius"]) < float(ref["radius"]) - 0.001
	var painted_ordinary: bool = not ref.is_empty() \
		and is_equal_approx(float(cross["arm"]), float(ref["arm"])) \
		and is_equal_approx(float(cross["width"]), float(ref["width"])) \
		and is_equal_approx(float(cross["radius"]), float(ref["radius"]))
	_ok("%s : croix de PRECISION PEINTE ssi dispersion nulle" % weapon_id,
		painted_precise if precise else painted_ordinary,
		"trait %.2f px / epaisseur %.2f / point %.2f (ordinaire : %.2f / %.2f / %.2f)"
		% [float(cross["arm"]), float(cross["width"]), float(cross["radius"]),
			float(ref.get("arm", -1.0)), float(ref.get("width", -1.0)),
			float(ref.get("radius", -1.0))])


# =================================================================================================
# 1bis. LA DISPERSION SE PROJETTE HORS AXE — LE CONTRÔLE QUI REND LE §4bis.1 VÉRIFIABLE
# =================================================================================================
# ╔═ POURQUOI `aim_follow = 0` ET PAS 0,5 ════════════════════════════════════════════════════════╗
# ║ Le suivi de caméra vaut `cam_yaw = clamp(aim_yaw × follow, ±follow_max)`. À `follow = 0`, le    ║
# ║ lacet caméra vaut EXACTEMENT zéro : l'angle hors axe de la visée est donc `aim_yaw` lui-même,   ║
# ║ sans dépendre du plafond `follow_max` ni d'aucun lissage. L'attendu de la sonde ne recopie      ║
# ║ ainsi AUCUN état interne du monde 3D — juste le lacet qu'elle vient d'écrire. Un contrôle       ║
# ║ supplémentaire à `follow = 0,5` prouve ensuite que le réticule suit le CURSEUR et pas un cas    ║
# ║ particulier « tête fixe » : à mi-suivi, l'angle hors axe vaut la moitié du lacet.               ║
# ║ ⚠️ AUCUNE ÉCRITURE DE VISÉE INTERDITE ICI : `_aim_yaw` est le lacet du JOUEUR (c'est la souris  ║
# ║ qui l'écrit en jeu, `_input` l.941), pas une variable de feel. `probe_trench_aim` et            ║
# ║ `probe_trench_feel_aim` l'écrivent de la même façon pour scripter leurs séquences.              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Fractions du débattement de visée RÉEL (`_yaw_limit`, dérivé de la géométrie) : aucun angle en
# dur, et le plus grand cas testé est celui que le joueur peut vraiment atteindre.
const OFFAXIS_SHARES := [0.35, 0.70, 1.0]
# Écart MINIMAL exigé entre les deux arithmétiques pour qu'une mesure soit déclarée PORTEUSE. Deux
# fois la tolérance : en dessous, un vert ne distinguerait plus les deux formules.
const OFFAXIS_MIN_DIVERGENCE := PIXEL_TOL * 2.0


func _section_offaxis(duel, fov: float, half_h: float) -> void:
	print("  --- HORS AXE : aim_follow = 0 (tete fixe), la visee quitte le centre de l'ecran ---")
	var fake := _fake_weapons()
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": fake}
	duel._apply_tuning({"aim_follow": 0.0})
	for entry in fake:
		var cone := float(entry["dispersion_deg"])
		if cone <= 0.0:
			continue                      # un cône nul reste nul partout : rien à projeter
		_push(duel, str(entry["id"]), 99)
		var carrying := 0
		var worst := 0.0
		for share: float in OFFAXIS_SHARES:
			var yaw: float = duel._yaw_limit * share
			await _aim_at(duel, yaw)
			var measured: float = _painted_spread(duel) - duel.RETICLE_GAP_PX
			var want: float = _expected_px(cone, fov, half_h, yaw)
			var fallback: float = _expected_px(cone, fov, half_h, 0.0)
			var divergence: float = want - fallback
			worst = maxf(worst, divergence)
			if divergence >= OFFAXIS_MIN_DIVERGENCE:
				carrying += 1
			_ok("%s hors axe %.1f deg : ecartement = projection de la VISEE"
				% [str(entry["id"]), yaw], absf(measured - want) < PIXEL_TOL,
				"mesure %.3f px / attendu %.3f px (repli trigo %.3f px, ecart %.3f px)"
				% [measured, want, fallback, divergence])
		# ⚠️⚠️ LA SENTINELLE, ET ELLE EST LE CŒUR DE LA CORRECTION. Un contrôle vert dont l'attendu
		# COÏNCIDE avec ce que rendrait le sabotage ne prouve rien — c'est exactement ce qui s'est
		# produit au centre de l'écran (0,000 px d'écart, mais parce que les deux formules y sont la
		# MÊME). On exige donc, arme par arme, qu'au moins un des angles testés mette réellement les
		# deux arithmétiques en désaccord. Un cône étroit vu de peu de côté n'y suffit pas (0,46 px
		# pour 0,17° à 21°, sous la tolérance) : c'est dit ici plutôt que maquillé, et le grand
		# angle, lui, tranche.
		_ok("%s : le controle est PORTEUR — le repli trigo se trompe franchement quelque part"
			% str(entry["id"]), carrying > 0,
			"%d angle(s) porteur(s) sur %d, divergence max %.3f px (seuil %.3f px)"
			% [carrying, OFFAXIS_SHARES.size(), worst, OFFAXIS_MIN_DIVERGENCE])
	# LE SUIVI EST UN CURSEUR, PAS UN INTERRUPTEUR : à mi-suivi, l'angle hors axe est de moitié.
	var widest := float(fake[2]["dispersion_deg"])
	_push(duel, str(fake[2]["id"]), 99)
	duel._apply_tuning({"aim_follow": 0.5})
	var mid_yaw: float = duel._yaw_limit
	await _aim_at(duel, mid_yaw)
	var mid_measured: float = _painted_spread(duel) - duel.RETICLE_GAP_PX
	var mid_want: float = _expected_px(widest, fov, half_h, mid_yaw * 0.5)
	_ok("aim_follow = 0,5 : l'ecartement suit le CURSEUR (angle hors axe = moitie du lacet)",
		absf(mid_measured - mid_want) < PIXEL_TOL,
		"mesure %.3f px / attendu %.3f px" % [mid_measured, mid_want])
	_ok("aim_follow = 0,5 : ce controle est PORTEUR lui aussi",
		mid_want - _expected_px(widest, fov, half_h, 0.0) >= OFFAXIS_MIN_DIVERGENCE,
		"divergence %.3f px" % [mid_want - _expected_px(widest, fov, half_h, 0.0)])
	# RETOUR AU RÉGIME NOMINAL : visée centrée, caméra qui suit — l'état qu'attend la suite.
	duel._apply_tuning({"aim_follow": 1.0})
	await _aim_at(duel, 0.0)


# Le joueur vise : on écrit le lacet EXACTEMENT là où la souris l'écrit, on le donne au monde comme
# `_process` le ferait, puis on laisse UNE frame au monde 3D pour tourner sa caméra (`_cam_yaw` est
# posé dans SON `_process`, que la sonde n'a pas coupé — seul celui de l'hôte l'est).
func _aim_at(duel, yaw: float) -> void:
	duel._aim_yaw = yaw
	duel._aim_pitch = 0.0
	duel._world.set_aim(yaw, 0.0)
	await get_tree().process_frame


# L'ATTENDU, par une arithmétique INDÉPENDANTE de celle du jeu (cf. le pavé d'en-tête). UNE seule
# formule pour les deux régimes : la demi-largeur, en pixels, d'un cône de demi-angle `degrees` dont
# le CENTRE est à `off_axis` degrés de l'axe optique. `f = (hauteur/2) / tan(fov/2)` est la distance
# focale en pixels ; les deux bords se projettent en `f·tan(a ± d)` et la moitié de leur écart est
# le rayon cherché. À `off_axis = 0` elle se réduit à `f·tan(d)` — l'ancienne formule de la sonde,
# et aussi le repli de `_dispersion_pixels()` : c'est précisément pour ça qu'au centre les deux
# chemins ne pouvaient PAS se départager.
func _expected_px(degrees: float, fov: float, half_h: float, off_axis := 0.0) -> float:
	if degrees <= 0.0:
		return 0.0
	var focal: float = half_h / tan(deg_to_rad(fov) * 0.5)
	return absf(tan(deg_to_rad(off_axis + degrees)) - tan(deg_to_rad(off_axis - degrees))) \
		* 0.5 * focal


# =================================================================================================
# CE QUI EST PEINT — LA SEULE CHOSE QU'ON AIT LE DROIT DE MESURER
# =================================================================================================
# `_reticle_paint_list()` est la transcription LITTÉRALE des primitives soumises au réticule, et
# `_draw_reticle()` n'en est que le rejeu (cf. le pavé de production). On décode donc ici la croix
# TELLE QU'ELLE EST PEINTE — sans recopier un seul chiffre de production : l'écartement est la plus
# courte distance du centre à une extrémité de trait, la longueur de trait et l'épaisseur sont
# celles de la commande, et les DIAGONALES (hors axes) sont le hitmarker.
func _decode_cross(duel) -> Dictionary:
	var center: Vector2 = duel._reticle.size * 0.5
	var out := {"arms": 0, "dots": 0, "marks": 0, "total": 0, "spread": -1.0, "arm": -1.0,
		"width": -1.0, "radius": -1.0, "color": Color(0, 0, 0, 0), "mark_color": Color(0, 0, 0, 0),
		"mark_far": 0.0, "mark_width": 0.0}
	for cmd: Dictionary in duel._reticle_paint_list():
		out["total"] = int(out["total"]) + 1
		if cmd[duel.PAINT_KIND] == duel.PAINT_DOT:
			out["dots"] = int(out["dots"]) + 1
			out["radius"] = float(cmd[duel.PAINT_RADIUS])
			continue
		var a: Vector2 = cmd[duel.PAINT_A]
		var b: Vector2 = cmd[duel.PAINT_B]
		var axis: Vector2 = (b - a).normalized()
		if absf(axis.x) < 0.001 or absf(axis.y) < 0.001:
			out["arms"] = int(out["arms"]) + 1
			var near: float = minf(center.distance_to(a), center.distance_to(b))
			out["spread"] = near if float(out["spread"]) < 0.0 \
				else minf(float(out["spread"]), near)
			out["arm"] = a.distance_to(b)
			out["width"] = float(cmd[duel.PAINT_WIDTH])
			out["color"] = cmd[duel.PAINT_COLOR]
		else:
			out["marks"] = int(out["marks"]) + 1
			out["mark_far"] = maxf(float(out["mark_far"]),
				maxf(center.distance_to(a), center.distance_to(b)))
			out["mark_width"] = float(cmd[duel.PAINT_WIDTH])
			out["mark_color"] = cmd[duel.PAINT_COLOR]
	return out


func _painted_spread(duel) -> float:
	return float(_decode_cross(duel)["spread"])


# LE VRAI PASSAGE DE DESSIN, exercé pour de bon. `queue_redraw()` ne dessine pas sur-le-champ : il
# pousse un appelable dans la file de messages, et la notification DRAW part à la frame suivante —
# y compris sous `--headless`, où seul le RENDU est muet. On compte les passages depuis un
# abonnement de la sonde au MÊME signal que la production.
func _real_draw(duel) -> void:
	if not duel._reticle.draw.is_connected(_count_draw):
		duel._reticle.draw.connect(_count_draw)
	duel._reticle.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame


func _count_draw() -> void:
	_draws += 1


# =================================================================================================
# 1ter. LA POSITION DU RÉTICULE — l'autre moitié de « LE RÉTICULE NE MENT JAMAIS »
# =================================================================================================
# ╔═ CE QUE CETTE SECTION GARDE, ET POURQUOI ELLE MANQUAIT ═══════════════════════════════════════╗
# ║ La section 1 garde la TAILLE de la croix. Sa POSITION — « le réticule est là où est la visée » ║
# ║ — n'avait AUCUNE garde dans tout le dépôt : `grep reticle` sur `probe_trench_aim`,             ║
# ║ `probe_trench_feel_aim` et `probe_trench_falseshot` rend ZÉRO occurrence, et la section 1 ne   ║
# ║ lit que l'écartement. Trois mensonges distincts passaient la porte, MESURÉS (84/0, tout vert) :║
# ║   (a) la croix CLOUÉE au centre de l'écran, qui ignore complètement la visée — elle se voit    ║
# ║       dès que `aim_follow` < 1, une valeur LÉGALE du curseur F10 ;                              ║
# ║   (b) `_shake_px` retiré du SEUL réticule : le monde tremble, la croix reste immobile — et     ║
# ║       celui-là se voit AUX RÉGLAGES PAR DÉFAUT ;                                                ║
# ║   (c) la réintroduction littérale du `aim_screen.y -= recul * 10` que le §8.141.6 a tué et que ║
# ║       le commentaire de production déclare mort.                                                ║
# ║ L'invariant tient en une ligne — la croix est à `project_aim(visée) + secousse` — et il est    ║
# ║ EXACT, pas approché : la tolérance est de 0,01 px. Un contrôle INDÉPENDANT (focale × tan, la   ║
# ║ même arithmétique que la section 1bis, qui ne passe par aucune fonction du jeu) le double, et  ║
# ║ chaque cas porte sa SENTINELLE : sans secousse mesurable, sans roulis mesurable, sans          ║
# ║ déport mesurable, le contrôle correspondant ne prouverait rien et le dit.                       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_reticle_position(duel) -> void:
	_section("1ter. LA POSITION DU RETICULE — « la croix est LA OU EST LA VISEE »")
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	var center: Vector2 = duel.size * 0.5
	_ok("REPOS COMPLET avant de mesurer (ressorts colles, secousse a zero exact)",
		await _settle(duel), "roulis %.6f deg, secousse %s"
		% [duel._cam_roll.value, str(duel._shake_px)])

	# --- a) HORS AXE : le seul régime où « au centre » et « à la visée » se distinguent -----------
	# ⚠️ ON MESURE À +yaw ET À −yaw, et l'attendu est une DISTANCE, jamais une abscisse signée : la
	# convention « lacet positif = écran vers la gauche » est un fait de la géométrie du jeu, pas
	# quelque chose qu'une garde a le droit de recopier pour se donner raison. Ce qu'on exige, c'est
	# que le déport VAILLE focale × tan(lacet) et qu'il soit SYMÉTRIQUE — deux propriétés qu'une
	# croix clouée au centre (déport nul des deux côtés) ne peut pas satisfaire.
	duel._apply_tuning({"aim_follow": 0.0})
	var yaw: float = duel._yaw_limit * 0.7
	var focal: float = (duel.size.y * 0.5) / tan(deg_to_rad(duel._world.camera_fov()) * 0.5)
	var want: float = focal * tan(deg_to_rad(yaw))
	await _aim_at(duel, yaw)
	duel._process(1.0 / 60.0)                 # LE chemin de production qui place la croix
	var plus: Vector2 = _reticle_center(duel)
	var off_plus: Vector2 = _reticle_offset(duel)
	await _aim_at(duel, -yaw)
	duel._process(1.0 / 60.0)
	var minus: Vector2 = _reticle_center(duel)
	_ok("HORS AXE : la croix a QUITTE le centre de focale x tan(lacet) — arithmetique independante",
		absf(absf(plus.x - center.x) - want) < PIXEL_TOL
			and absf(absf(minus.x - center.x) - want) < PIXEL_TOL,
		"deports %.2f et %.2f px / attendu %.2f px" % [plus.x - center.x, minus.x - center.x, want])
	_ok("HORS AXE : et il est SYMETRIQUE (la croix suit le lacet des deux cotes)",
		absf((plus.x - center.x) + (minus.x - center.x)) < PIXEL_TOL,
		"somme des deux deports %.3f px" % ((plus.x - center.x) + (minus.x - center.x)))
	_ok("HORS AXE : le controle est PORTEUR — le deport vaut franchement quelque chose",
		want >= OFFAXIS_MIN_DIVERGENCE,
		"deport %.2f px (seuil %.2f px)" % [want, OFFAXIS_MIN_DIVERGENCE])
	_ok("HORS AXE : et elle est EXACTEMENT a `project_aim(visee) + secousse`",
		off_plus.length() < EXACT_TOL, "ecart %s px" % str(off_plus))

	# --- b) LA SECOUSSE : le monde ET la croix encaissent LE MÊME vecteur -------------------------
	# Le trauma naît d'une EXPLOSION, par le chemin de production (`play_explosion` est ce que
	# l'événement `impact` d'une grenade appelle) — jamais d'une écriture dans `_shake_px`. Deux
	# détonations et `feel_shake` au MAXIMUM LÉGAL du curseur F10 : c'est le régime où la sentinelle
	# a un sens, une secousse d'un pixel ne départagerait rien.
	duel._apply_tuning({"feel_shake": 2.0})
	duel._world.play_explosion(Geo.position_x(duel._pred_pos), true)
	duel._world.play_explosion(Geo.position_x(duel._pred_pos), true)
	_ok("SECOUSSE : le controle est PORTEUR — la secousse vaut vraiment quelque chose",
		await _shake_until_visible(duel),
		"secousse %s (%.2f px)" % [str(duel._shake_px), duel._shake_px.length()])
	_ok("SECOUSSE : la croix la porte comme le monde (retirer `_shake_px` du seul reticule ROUGIT)",
		_reticle_offset(duel).length() < EXACT_TOL,
		"ecart %s px" % str(_reticle_offset(duel)))
	duel._apply_tuning({"feel_shake": 1.0})

	# --- c) LE RECUL NE DÉPLACE PAS LA CROIX (§8.141.6, et il ne reviendra pas) -------------------
	# `feel_recoil` est poussé à son MAXIMUM LÉGAL (2,0, borne du panneau F10) : c'est le régime où
	# le mensonge historique — `aim_screen.y -= recul * 10` — vaudrait le plus de pixels, donc celui
	# où la sentinelle a un sens. Rien ici n'écrit dans une variable de visée.
	_ok("REPOS COMPLET avant le controle de recul", await _settle(duel),
		"roulis %.6f deg, secousse %s" % [duel._cam_roll.value, str(duel._shake_px)])
	duel._apply_tuning({"feel_recoil": 2.0})
	duel._fire_feel_kick()
	duel._process(1.0 / 60.0)               # UNE frame : le ressort est au plus haut de son cran
	var lie: float = absf(duel._cam_roll.value) * 10.0
	_ok("RECUL : le controle est PORTEUR — le mensonge historique vaudrait des pixels",
		lie > EXACT_TOL * 20.0,
		"roulis %.4f deg -> %.2f px de croix deplacee" % [duel._cam_roll.value, lie])
	_ok("RECUL : la croix reste EXACTEMENT a la visee (aucun kick de reticule)",
		_reticle_offset(duel).length() < EXACT_TOL,
		"ecart %s px" % str(_reticle_offset(duel)))
	# … ET AUSSI UNE FOIS LE ROULIS APPLIQUÉ À LA CAMÉRA. Le monde ne tourne son image qu'à SA
	# frame suivante : sans ce second point, l'invariant ne serait vérifié que sur une image droite,
	# c'est-à-dire jamais dans le régime qui a produit le mensonge de §8.141.6.
	await get_tree().process_frame
	duel._process(1.0 / 60.0)
	_ok("RECUL : elle y reste APRES que le monde a incline l'image (roulis applique)",
		absf(duel._world._feel_roll_deg) > 0.0 and _reticle_offset(duel).length() < EXACT_TOL,
		"roulis applique %.4f deg, ecart %s px"
		% [duel._world._feel_roll_deg, str(_reticle_offset(duel))])

	# --- RETOUR AU RÉGIME NOMINAL : la suite attend une visée centrée, une caméra qui suit, et
	# surtout une secousse RETOMBÉE À ZÉRO — un résidu fausserait l'origine des chiffres flottants.
	duel._apply_tuning({"aim_follow": 1.0, "feel_recoil": 1.0})
	await _aim_at(duel, 0.0)
	_ok("RETOUR AU REPOS : secousse a ZERO exact et ressorts colles (bit-stabilite des captures)",
		await _settle(duel), "secousse %s" % str(duel._shake_px))
	duel._reticle_pulse.reset(0.0)


# Le centre de la croix PEINTE, en coordonnées d'écran.
func _reticle_center(duel) -> Vector2:
	return duel._reticle.position + duel._reticle.size * 0.5


# L'ÉCART ENTRE LA CROIX ET LA VÉRITÉ : « position peinte » moins « projection de la visée + la
# secousse que le monde a publiée ». Il doit valoir ZÉRO, toujours et exactement.
func _reticle_offset(duel) -> Vector2:
	var aim: Vector2 = duel._world.project_aim(duel._aim_yaw, duel._aim_pitch)
	return _reticle_center(duel) - aim - duel._shake_px


# ╔═ LE REPOS COMPLET — SANS LUI, DEUX MESURES PRISES À DEUX INSTANTS NE SONT PAS COMPARABLES ════╗
# ║ Le roulis de recul tourne l'IMAGE ENTIÈRE autour de l'axe de visée : tant que son ressort      ║
# ║ sonne, un point HORS CENTRE — la croix hors axe, la silhouette adverse — se déplace de plus    ║
# ║ d'un pixel d'une frame à l'autre. Et la secousse ne vaut un ZÉRO EXACT qu'une fois le trauma   ║
# ║ asséché. On avance donc par le chemin de production jusqu'au repos des deux, et on RATE fort   ║
# ║ (contrôle rouge) plutôt que de mesurer dans le bruit si le repos n'arrive pas.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _settle(duel, frames := 900) -> bool:
	for i in range(frames):
		duel._process(1.0 / 60.0)
		await get_tree().process_frame
		if duel._shake_px == Vector2.ZERO and duel._cam_roll.at_rest():
			return true
	return false


# … ET SON MIROIR : on avance jusqu'à ce que la secousse soit FRANCHE. ⚠️ Le bruit de secousse a
# deux cadences légèrement différentes sur les deux axes et repasse par ZÉRO plusieurs fois pendant
# un même trauma ; mesurer sur un de ces passages ne prouverait rien, et la phase dépend de
# `_shake_time`, c'est-à-dire des deltas RÉELS du moteur — donc de la machine. Une garde qui
# dépendrait de cette loterie serait rouge un jour sur dix pour rien.
func _shake_until_visible(duel, minimum := OFFAXIS_MIN_DIVERGENCE, frames := 90) -> bool:
	for i in range(frames):
		await get_tree().process_frame
		duel._process(1.0 / 60.0)
		if duel._shake_px.length() > minimum:
			return true
	return false


# =================================================================================================
# 1quater. L'AUDIT DU PINCEAU — le seul angle mort qui reste, refermé sur la SOURCE
# =================================================================================================
# ╔═ POURQUOI UN AUDIT DE SOURCE, ET POURQUOI CE N'EST PAS UN GREP DE CONFORT ════════════════════╗
# ║ Godot n'expose AUCUNE relecture des primitives soumises à un `CanvasItem`, et `--headless`     ║
# ║ rend par un pilote muet : les pixels du réticule sont, ici, physiquement inobservables. Ce qui ║
# ║ reste vérifiable, c'est que le pinceau N'A RIEN À LUI — et ça se lit sur la source. On isole   ║
# ║ le corps de `_draw_reticle` et de `_paint_command`, on retire les commentaires, et on exige :  ║
# ║   • aucune chaîne (donc le décommentage naïf ne peut pas se tromper) ;                         ║
# ║   • aucun LITTÉRAL NUMÉRIQUE — « var spread := 12.0 » n'a plus d'endroit où s'écrire ;         ║
# ║   • `_draw_reticle` rejoue `_reticle_paint_list()` et ne dessine RIEN par lui-même ;           ║
# ║   • chaque argument de chaque `draw_*` vient de la COMMANDE (`cmd[CLÉ]`), jamais d'ailleurs.   ║
# ║ ⚠️ L'audit ne remplace pas la mesure : il la BORNE. La liste, elle, est mesurée aux sections 1 ║
# ║ et 1bis contre la dispersion lue au registre, hors axe, sur huit armes.                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_painter_audit(duel) -> void:
	_section("1quater. AUDIT DU PINCEAU — il ne peut rien inventer")
	var file := FileAccess.open(DUEL_SOURCE, FileAccess.READ)
	var source: String = file.get_as_text() if file != null else ""
	_ok("AUDIT : la source de production est lisible", source.length() > 0,
		"%d caracteres" % source.length())
	var draw_body := _function_body(source, "_draw_reticle")
	var paint_body := _function_body(source, "_paint_command")
	_ok("AUDIT : les deux fonctions de rejeu existent",
		draw_body != "" and paint_body != "",
		"%d / %d caracteres" % [draw_body.length(), paint_body.length()])
	_ok("AUDIT : `_draw_reticle` rejoue `_reticle_paint_list()` — la liste MESUREE",
		draw_body.contains("_reticle_paint_list()"))
	_ok("AUDIT : `_draw_reticle` ne dessine RIEN lui-meme (aucun appel `draw_`)",
		not draw_body.contains("draw_line") and not draw_body.contains("draw_circle"))
	_ok("AUDIT : aucune CHAINE dans le pinceau (le decommentage ne peut pas se tromper)",
		not draw_body.contains("\"") and not paint_body.contains("\""))
	_ok("AUDIT : le pinceau n'a AUCUN chiffre a lui (« var spread := 12.0 » impossible)",
		not _has_digit(draw_body) and not _has_digit(paint_body),
		"corps audites : %d + %d caracteres" % [draw_body.length(), paint_body.length()])
	_ok("AUDIT : chaque argument de dessin vient de la COMMANDE (`cmd[CLE]`)",
		_draw_args_all_from_command(paint_body))
	# LA CONTRE-ÉPREUVE DE L'AUDIT LUI-MÊME : sur un corps SABOTÉ à la main, il doit rougir. Sans
	# elle, un extracteur qui rendrait la chaîne vide déclarerait tout conforme, pour rien.
	var sabotaged := draw_body.replace("_reticle_paint_list()", "_fake_list()") + "\n\tvar s := 12.0"
	_ok("AUDIT : l'audit lui-meme est PORTEUR (un corps sabote ne passe pas)",
		_has_digit(sabotaged) and not sabotaged.contains("_reticle_paint_list()"))


# Le corps d'une fonction, de sa signature jusqu'à la prochaine déclaration de premier niveau,
# COMMENTAIRES RETIRÉS. (L'absence de chaîne dans les deux corps audités est vérifiée à part : sans
# elle, ce découpage naïf sur « # » pourrait se tromper.)
func _function_body(source: String, name: String) -> String:
	var body: Array = []
	var inside := false
	for raw: String in source.split("\n"):
		if raw.begins_with("func "):
			if inside:
				break
			inside = raw.begins_with("func " + name + "(")
			if not inside:
				continue
		if inside:
			var line: String = raw
			var hash_at: int = line.find("#")
			if hash_at >= 0:
				line = line.substr(0, hash_at)
			body.append(line)
	return "\n".join(body)


func _has_digit(text: String) -> bool:
	for i in range(text.length()):
		var c: String = text[i]
		if c >= "0" and c <= "9":
			return true
	return false


func _draw_args_all_from_command(body: String) -> bool:
	var calls := RegEx.new()
	calls.compile("draw_[a-z_]+\\(([^)]*)\\)")
	var from_cmd := RegEx.new()
	from_cmd.compile("^cmd\\[[A-Z_]+\\]$")
	var found := calls.search_all(body)
	if found.is_empty():
		return false                        # un pinceau qui ne dessine rien n'est pas un pinceau
	for call: RegExMatch in found:
		for arg: String in call.get_string(1).split(","):
			if from_cmd.search(arg.strip_edges()) == null:
				return false
	return true


# =================================================================================================
# 2. TIR MAINTENU (§4bis.5) — la cadence est celle du REGISTRE, et zéro refus
# =================================================================================================
func _section_held_fire(duel) -> void:
	_section("2. TIR MAINTENU — clic tenu N secondes = plafond du registre, ZERO refus")

	# --- a) BOUT EN BOUT : le vrai `_process`, avec un vrai bouton de souris enfoncé --------------
	# ⚠️ Sans ce contrôle, la sonde pourrait être verte sur une logique que `_process` n'appelle
	# jamais. `Input.parse_input_event` fonctionne sous `--headless` (vérifié) : le masque de
	# boutons du singleton `Input` ne dépend pas du serveur d'affichage.
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	duel._clock = 0.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._shot_count = 0
	_mouse(true)
	_ok("la detection de maintien voit le bouton enfonce", duel._fire_hold_active())
	var frames := 120                      # 2,00 s à 60 Hz
	for i in range(frames):
		duel._process(1.0 / 60.0)
		duel._fire_queued = false          # l'envoi réseau est muet ici : on vide la file à la main
	_mouse(false)
	# Le JUGE, calculé à part : la cadence du registre, appliquée à la même trame de frames.
	var cadence: float = 18.0 / 20.0
	var judge := _judge_shots(frames, 1.0 / 60.0, cadence)
	_ok("BOUT EN BOUT : `_process` enchaine les tirs a la cadence du registre",
		duel._shot_count == judge, "%d tirs presentes / %d attendus (cadence %.3f s)"
		% [duel._shot_count, judge, cadence])
	_ok("BOUT EN BOUT : ZERO refus pendant tout le maintien", duel._fire_refuse == 0.0,
		"_fire_refuse = %.3f" % duel._fire_refuse)

	# --- b) LE PLAFOND SUIT LE REGISTRE (et non un chiffre en dur) -------------------------------
	# Deux cadences INVENTÉES : si le compte suivait une constante, l'une des deux rougirait.
	for ticks in [9, 37]:
		var rules := _production_weapons()
		rules[0]["cooldown_ticks"] = ticks
		duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
			"weapons": rules}
		_push(duel, "vipere", 999)
		duel._clock = 0.0
		duel._pred_fire_ready = 0.0
		duel._fire_refuse = 0.0
		var emitted := 0
		for i in range(180):               # 3,00 s
			duel._clock += 1.0 / 60.0
			duel._step_held_fire(true)
			if duel._fire_queued:
				emitted += 1
				duel._fire_queued = false
		var want := _judge_shots(180, 1.0 / 60.0, float(ticks) / 20.0)
		_ok("cadence %d ticks : %d tirs emis == plafond du registre" % [ticks, emitted],
			emitted == want, "%d emis / %d attendus" % [emitted, want])
		_ok("cadence %d ticks : ZERO refus" % ticks, duel._fire_refuse == 0.0,
			"_fire_refuse = %.3f" % duel._fire_refuse)

	# --- c) LES SIX REFUS RESTENT DES REFUS : accroupi = pas un seul tir -------------------------
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	duel._pred_stance = "down"
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_queued = false
	var crouched := 0
	for i in range(120):
		duel._clock += 1.0 / 60.0
		duel._step_held_fire(true)
		if duel._fire_queued:
			crouched += 1
			duel._fire_queued = false
	_ok("ACCROUPI : le maintien n'emet RIEN (la prediction des six refus decide)", crouched == 0,
		"%d tirs emis" % crouched)
	duel._pred_stance = "up"

	# --- d) CHARGEUR VIDE : un seul declencheur de rechargement, pas un deluge -------------------
	_push(duel, "vipere", 0)
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_queued = false
	var empties := 0
	for i in range(120):
		duel._clock += 1.0 / 60.0
		duel._step_held_fire(true)
		if duel._fire_queued:
			empties += 1
			duel._fire_queued = false
	_ok("CHARGEUR VIDE : le maintien envoie UN declencheur de rechargement, pas 120",
		empties == 1, "%d envois" % empties)

	# --- e) L'INTERRUPTEUR F10 : coupe, et le clic simple reste intact ---------------------------
	_ok("le reglage `auto_fire` existe et vaut VRAI par defaut (decision §1.8)",
		bool(TuningScript.defaults().get("auto_fire", false)))
	_push(duel, "vipere", 99)
	duel._apply_tuning({"auto_fire": false})
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_queued = false
	var off := 0
	for i in range(120):
		duel._clock += 1.0 / 60.0
		duel._step_held_fire(true)
		if duel._fire_queued:
			off += 1
			duel._fire_queued = false
	_ok("F10 `auto_fire` COUPE : un maintien n'enchaine plus rien", off == 0, "%d tirs" % off)
	duel._clock += 10.0
	duel._fire_queued = false
	duel._queue_fire()
	_ok("F10 `auto_fire` COUPE : le clic simple tire toujours", duel._fire_queued)
	duel._apply_tuning({"auto_fire": true})
	duel._fire_queued = false

	# --- f) ⚠️⚠️ HORS MANCHE — LE 7ᵉ REFUS, celui que le miroir avait oublié ----------------------
	# ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
	# ║ `trench_sim.step` sort par un `return` ANTICIPÉ pendant `PHASE_INTERMISSION` — le bandeau de  ║
	# ║ 3 s (`intermission_ticks` = 60) qui précède CHAQUE manche, la première comprise : seuls le    ║
	# ║ bookkeeping et `pick_weapon` y sont traités, tout `fire` est JETÉ. Le miroir des refus ne     ║
	# ║ regardait QUE le bloc de tir, où ce refus-là n'apparaît jamais.                               ║
	# ║ ⚠️ ET LA SENTINELLE « ZÉRO REFUS » DES CONTRÔLES CI-DESSUS NE POUVAIT PAS LE VOIR : elle lit   ║
	# ║ `_fire_refuse`, c'est-à-dire l'OPINION du client — or le client croyait ces tirs légitimes.   ║
	# ║ On mesure donc les deux choses qui existent vraiment : les messages qu'aurait reçus le        ║
	# ║ serveur, et les retours d'arme PRÉSENTÉS au joueur (`_shot_count`, posé par `_fire_feel_kick` ║
	# ║ — détonation, traçante et cran de recul partent du même point).                               ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
	duel._help_shown_once = true       # le guide F1 s'ouvre seul au 1er bandeau : hors sujet ici
	_push_phase(duel, "vipere", 99, "intermission")
	_ok("HORS MANCHE : `_fire_refusal()` refuse (miroir du `return` anticipe de la sim)",
		duel._fire_refusal() != "", "refus = « %s »" % duel._fire_refusal())
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	var inter := 0
	for i in range(180):               # 3,00 s : la fenêtre d'intermission ENTIÈRE
		duel._clock += 1.0 / 60.0
		duel._step_held_fire(true)
		if duel._fire_queued:
			inter += 1
			duel._fire_queued = false
	_ok("HORS MANCHE : gachette tenue 3,00 s -> AUCUN message `fire`", inter == 0,
		"%d messages" % inter)
	_ok("HORS MANCHE : AUCUN retour d'arme local (pas une balle presentee)",
		duel._shot_count == 0, "%d retours d'arme" % duel._shot_count)
	duel._fire_queued = false
	duel._queue_fire()
	_ok("HORS MANCHE : le clic simple ne part pas davantage", not duel._fire_queued)
	duel._fire_queued = false
	# ⚠️ ET LE REFUS N'EST PAS UN NOM DE PHASE APPRIS PAR CŒUR : une phase INVENTÉE refuse aussi.
	# Un miroir écrit `== "intermission"` serait vert au contrôle précédent et faux ici — et il le
	# resterait le jour où le serveur ajoute une phase.
	_push_phase(duel, "vipere", 99, "entracte")
	_ok("HORS MANCHE : une phase INCONNUE refuse aussi (le test porte sur « la manche tourne »)",
		duel._fire_refusal() != "", "refus = « %s »" % duel._fire_refusal())
	# LA CONTRE-ÉPREUVE, sans laquelle les quatre contrôles ci-dessus seraient verts sur un client
	# qui ne tirerait PLUS JAMAIS : le MÊME état, la MÊME arme, en manche — et le tir part.
	_push(duel, "vipere", 99)
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	duel._queue_fire()
	_ok("... et le MEME etat EN MANCHE tire (les controles ci-dessus sont PORTEURS)",
		duel._fire_queued and duel._shot_count == 1,
		"tir=%s, %d retour(s) d'arme" % [duel._fire_queued, duel._shot_count])
	duel._fire_queued = false

	# --- g) ⚠️ UN SOLDAT N'A QUE DEUX MAINS — `throw` et `fire` ne partent JAMAIS ensemble ---------
	# La branche grenade de `trench_sim.step` finit par `continue  # lancer ce tick = pas de tir ce
	# tick` : le `fire` du MÊME message est écarté en silence. `_step_held_fire` s'exécute juste
	# APRÈS `_update_grenade_aim` dans `_process` — gâchette tenue, toute grenade relâchée tombait
	# donc dans la même fenêtre de coalescence de 105 ms, et le tir était présenté avant d'être jeté.
	_push(duel, "chacal", 99)
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	duel._throw_queued = {"target_x": 1.5}
	_ok("GRENADE EN FILE : `_fire_refusal()` refuse (miroir du `continue` de la sim)",
		duel._fire_refusal() != "", "refus = « %s »" % duel._fire_refusal())
	var with_throw := 0
	for i in range(120):
		duel._clock += 1.0 / 60.0
		duel._step_held_fire(true)
		if duel._fire_queued:
			with_throw += 1
			duel._fire_queued = false
	_ok("GRENADE EN FILE : gachette tenue 2,00 s -> AUCUN tir arme", with_throw == 0,
		"%d tirs" % with_throw)
	_ok("GRENADE EN FILE : aucun retour d'arme local", duel._shot_count == 0,
		"%d retours d'arme" % duel._shot_count)

	# L'ORDRE INVERSE — le clic D'ABORD, la grenade relâchée ensuite : le refus ci-dessus n'y peut
	# rien, et c'est la charge utile elle-même qui doit trancher. On la monte par le VRAI `_process`.
	duel._throw_queued = {}
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_queued = false
	duel._queue_fire()                       # le clic passe : aucune grenade en file à cet instant
	duel._throw_queued = {"target_x": 2.5}   # …puis la grenade part dans la MÊME fenêtre d'envoi
	duel._sent_at = []
	duel._send_accum = duel.SEND_INTERVAL
	duel._process(1.0 / 60.0)
	# `_fire_queued` n'est remis à faux QUE dans le bloc d'envoi : à faux = le tir est bien parti.
	_ok("ORDRE INVERSE : le TIR part (il a deja ete presente au joueur, le jeter mentirait)",
		not duel._fire_queued)
	_ok("ORDRE INVERSE : le LANCER n'est PAS dans le meme message",
		not duel._throw_queued.is_empty(), "file de lancer : %s" % str(duel._throw_queued))
	# ⚠️ ON RELÈVE LA FILE AVANT D'AVANCER, et le contrôle suivant l'exige NON VIDE : sans ça, une
	# purge inconditionnelle de `_throw_queued` (le geste AVALÉ, précisément ce qu'on interdit)
	# rendrait « la file est vide » VRAI pour la pire des raisons — un vert par disparition.
	var pending_before: Dictionary = duel._throw_queued.duplicate()
	duel._send_accum = duel.SEND_INTERVAL
	duel._process(1.0 / 60.0)
	_ok("ORDRE INVERSE : le lancer part au message SUIVANT (aucun geste avale)",
		not pending_before.is_empty() and duel._throw_queued.is_empty(),
		"en attente avant : %s -> apres : %s" % [str(pending_before), str(duel._throw_queued)])
	duel._fire_queued = false
	duel._throw_queued = {}

	# --- h) ⚠️⚠️ LES ANGLES ÉMIS PAR LE MAINTIEN SONT CEUX DE LA VISÉE COURANTE -------------------
	# ╔═ 🩸 LA PROPRIÉTÉ PHARE DU §4bis.5 N'AVAIT AUCUNE GARDE, ET C'EST MESURÉ ═══════════════════╗
	# ║ « Le tir maintenu ne modifie pas les angles émis, seulement leur CADENCE d'émission » : le  ║
	# ║ contrat du lot le dit, la production le fait (`_queue_fire()` pose `_fire_aim` à CHAQUE tir ║
	# ║ accepté, clic comme maintien) — et RIEN ne le gardait. Les sous-sections ci-dessus ne       ║
	# ║ DÉPLACENT JAMAIS la visée entre deux crans tenus, et `probe_trench_feel_aim` — la seule     ║
	# ║ sonde qui compare les octets de `_fire_aim` — tire exclusivement par `_queue_fire()`,       ║
	# ║ jamais par `_step_held_fire`. Un gel de la visée CONFINÉ au chemin du maintien passait donc ║
	# ║ toute la batterie : 132 PASS / 0 FAIL sur un client dont chaque balle de rafale repartait   ║
	# ║ vers le point du PREMIER coup — un mensonge que le joueur ne peut attribuer qu'à lui-même.  ║
	# ║ ⚠️ ET LE CONTRÔLE N'A DE SENS QUE SI LA VISÉE BOUGE VRAIMENT ENTRE DEUX CRANS : la          ║
	# ║ sentinelle l'exige, sinon « la visée émise est la visée courante » serait satisfait par une ║
	# ║ visée immobile, c'est-à-dire par le gel lui-même.                                            ║
	# ║ ⚠️ AUCUNE ÉCRITURE DE FEEL : `_aim_yaw`/`_aim_pitch` sont le lacet et le site DU JOUEUR, ce  ║
	# ║ que `_input` écrit depuis la souris (l.941-944). C'est la lecture qui est auditée ici.      ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 999)
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._fire_aim = Vector2.ZERO
	var held_sent: Array = []            # ce que le MAINTIEN a figé, cran par cran
	var held_want: Array = []            # ce que la visée valait à cet instant précis
	for i in range(300):                 # 5,00 s : de quoi obtenir cinq crans à 0,90 s
		duel._clock += 1.0 / 60.0
		# LA SOURIS SUIT UNE CIBLE : un lacet et un site DIFFÉRENTS à chaque frame, deux périodes
		# incommensurables pour qu'aucun cran ne retombe par hasard sur la visée d'un autre.
		duel._aim_yaw = duel._yaw_limit * sin(float(i) * 0.11)
		duel._aim_pitch = duel.AIM_PITCH_LIMIT * sin(float(i) * 0.07)
		duel._step_held_fire(true)
		if duel._fire_queued:
			held_sent.append(duel._fire_aim)
			held_want.append(Vector2(duel._aim_yaw, duel._aim_pitch))
			duel._fire_queued = false
	_ok("MAINTIEN & VISEE : le controle est PORTEUR — le maintien a bien produit plusieurs crans",
		held_sent.size() >= 3, "%d cran(s) sur 5,00 s" % held_sent.size())
	var moved := 0
	for i in range(1, held_want.size()):
		if (held_want[i] as Vector2) != (held_want[i - 1] as Vector2):
			moved += 1
	_ok("MAINTIEN & VISEE : le controle est PORTEUR — la visee a BOUGE entre deux crans",
		held_want.size() >= 2 and moved == held_want.size() - 1,
		"%d changement(s) sur %d intervalle(s)" % [moved, maxi(0, held_want.size() - 1)])
	var mismatched := 0
	var worst_gap := 0.0
	for i in range(held_sent.size()):
		if (held_sent[i] as Vector2) != (held_want[i] as Vector2):
			mismatched += 1
		worst_gap = maxf(worst_gap,
			((held_sent[i] as Vector2) - (held_want[i] as Vector2)).length())
	_ok("MAINTIEN & VISEE : chaque tir tenu emet la visee de SON instant, octet pour octet",
		held_sent.size() >= 3 and mismatched == 0,
		"%d desaccord(s) sur %d cran(s), ecart max %.6f deg"
		% [mismatched, held_sent.size(), worst_gap])
	duel._fire_queued = false
	duel._fire_refuse = 0.0
	duel._shot_count = 0

	# --- i) ⚠️ PANNEAU F10 OUVERT : UN CLIC SUR UN CURSEUR NE VIDE PAS LE CHARGEUR ----------------
	# ╔═ 🩸 LE CLIC ET LE MAINTIEN N'AVAIENT PAS LA MÊME LISTE DE PORTES ══════════════════════════╗
	# ║ `_step_held_fire` fermait le panneau F10 (et son commentaire l'écrivait : « un glissé de     ║
	# ║ curseur sur un réglage ne doit pas vider un chargeur ») ; la garde d'`_input`, elle, s'était ║
	# ║ arrêtée à `_match_over / _abandon / _choice`. MESURÉ : panneau posé visible, état `playing`, ║
	# ║ cadence échue → `_input(clic gauche)` rendait `_fire_queued = true` et `_shot_count = 1`,    ║
	# ║ là où `_step_held_fire(true)` sur le MÊME état rendait `false` / `0`. En entraînement, Hakim ║
	# ║ ouvrait F10, cliquait un curseur, et son arme tirait — détonation, traçante, munition.       ║
	# ║ ⚠️ LES DEUX CHEMINS SONT MESURÉS ENSEMBLE, et c'est le point : c'est l'ASYMÉTRIE qui était   ║
	# ║ le défaut. Une garde qui n'en lirait qu'un laisserait l'autre dériver à nouveau.             ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	_push(duel, "vipere", 99)
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	# LA SENTINELLE D'ABORD : dans CET état précis, panneau FERMÉ, le clic tire pour de bon. Sans
	# elle, les deux contrôles suivants seraient verts sur un client qui ne tirerait plus jamais.
	duel._input(click)
	_ok("F10 : SENTINELLE — panneau FERME, ce clic-la tire (les controles suivants sont PORTEURS)",
		duel._tuning != null and not duel._tuning.visible
			and duel._fire_queued and duel._shot_count == 1,
		"tir=%s, %d retour(s) d'arme" % [duel._fire_queued, duel._shot_count])
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	duel._tuning.toggle()                    # LE CHEMIN DE PRODUCTION (ce que fait la touche F10)
	_ok("F10 : le panneau de reglage est bien OUVERT", duel._tuning.visible)
	duel._input(click)
	_ok("F10 OUVERT : le CLIC n'arme AUCUN tir (la porte du clic a rejoint celle du maintien)",
		not duel._fire_queued and duel._shot_count == 0,
		"tir=%s, %d retour(s) d'arme" % [duel._fire_queued, duel._shot_count])
	# ⚠️ ON REMET LES COMPTEURS À PLAT ENTRE LES DEUX CHEMINS. Sans ça, le contrôle du MAINTIEN
	# hériterait de ce que le CLIC vient de poser : il rougirait sur le défaut du clic et resterait
	# muet sur le sien. Deux chemins, deux mesures — c'est l'asymétrie même qui est le sujet ici.
	duel._fire_queued = false
	duel._shot_count = 0
	duel._step_held_fire(true)
	_ok("F10 OUVERT : le MAINTIEN n'arme rien non plus (une seule liste de portes pour les deux)",
		not duel._fire_queued and duel._shot_count == 0,
		"tir=%s, %d retour(s) d'arme" % [duel._fire_queued, duel._shot_count])
	duel._tuning.toggle()
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	duel._input(click)
	_ok("F10 REFERME : le MEME clic repart (le panneau ferme une porte, il n'en cloue aucune)",
		not duel._tuning.visible and duel._fire_queued and duel._shot_count == 1,
		"tir=%s, %d retour(s) d'arme" % [duel._fire_queued, duel._shot_count])
	duel._fire_queued = false
	duel._fire_refuse = 0.0
	duel._shot_count = 0
	await _aim_at(duel, 0.0)


# Le JUGE indépendant : combien de fois la porte de cadence s'ouvre-t-elle sur cette trame ?
func _judge_shots(frames: int, dt: float, cadence: float) -> int:
	var clock := 0.0
	var ready := 0.0
	var count := 0
	for i in range(frames):
		clock += dt
		if clock >= ready:
			count += 1
			ready = clock + cadence
	return count


# =================================================================================================
# 2bis. LES PANNEAUX FERMENT AUSSI LA GRENADE — LE 3ᵉ CHEMIN D'ACTION
# =================================================================================================
# ╔═ 🩸🩸 LE MÊME DÉFAUT QUE LA SECTION 2 (i), SUR LE CHEMIN QUI DÉPENSE UNE RESSOURCE ═══════════╗
# ║ La section 2 (i) garde les DEUX chemins de TIR (le clic et le maintien) contre les panneaux    ║
# ║ ouverts. Il en existe un TROISIÈME, issu du même `_process` et appelé juste AVANT le maintien :║
# ║ `_update_grenade_aim`. Il n'avait AUCUNE porte de panneau — rien que la posture et le stock —  ║
# ║ et AUCUN des 165 contrôles ne passait par là.                                                  ║
# ║ MESURÉ : F10 ouvert (entraînement), un clic DROIT sur un curseur → `vise = true`,              ║
# ║ `lance = true`, charge `{"target_x": 8.3}`. Idem sous la boîte « abandonner ? » et sous le     ║
# ║ panneau de CHOIX D'ARME — celui-là s'ouvre TOUT SEUL en plein combat et relâche la souris.     ║
# ║ Le coût n'est pas un chargeur qui se recharge : `stock_start` = 2, `regen_ticks` = 300 (15 s), ║
# ║ `damage_max` = 40. La moitié du stock, pour un geste que le joueur n'a pas voulu.              ║
# ║                                                                                                 ║
# ║ ⚠️ CETTE SECTION NE LIT PAS QU'UN DRAPEAU. `_aiming_grenade` est un état interne ; ce que le    ║
# ║ joueur VOIT, c'est le décalque au sol et la pose de lancer du viewmodel — et ce qu'il PAIE,     ║
# ║ c'est la charge utile mise en file. Les trois sont mesurés ensemble (leçon du §8.151.4ter :     ║
# ║ un état que rien n'oblige à devenir une image n'est pas une garde).                            ║
# ║ ⚠️ ET LES TROIS PANNEAUX SONT OUVERTS PAR LEUR CHEMIN DE PRODUCTION : `_tuning.toggle()` (F10),║
# ║ `_input(ÉCHAP)` (abandon), l'événement serveur `weapon_choice` (choix d'arme). Poser            ║
# ║ `.visible = true` à la main mesurerait un panneau que le jeu n'ouvre pas comme ça.              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_panels_grenade(duel) -> void:
	_section("2bis. LES PANNEAUX FERMENT AUSSI LA GRENADE — le 3e chemin d'action du `_process`")
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	duel._pred_stance = "up"
	duel._throw_queued = {}

	# --- LA SENTINELLE D'ABORD : panneaux FERMÉS, le geste marche pour de bon --------------------
	# Sans elle, les neuf contrôles suivants seraient TOUS verts sur un client où la grenade ne
	# partirait plus jamais — le vert par disparition, celui qu'on ne voit qu'en partie.
	_ok("SENTINELLE : les trois panneaux sont FERMES",
		not duel._abandon_overlay.visible and not duel._choice_panel.visible
			and duel._tuning != null and not duel._tuning.visible,
		"abandon=%s choix=%s F10=%s" % [duel._abandon_overlay.visible,
			duel._choice_panel.visible, duel._tuning.visible])
	var free_gesture := _grenade_gesture(duel)
	_ok("SENTINELLE : le geste ARME la visee (decalque au sol + pose de lancer)",
		bool(free_gesture["aimed"]) and bool(free_gesture["decal"]) and bool(free_gesture["pose"]),
		_gesture_detail(free_gesture))
	_ok("SENTINELLE : le relachement MET une vraie grenade en file",
		not (free_gesture["thrown"] as Dictionary).is_empty(),
		"charge = %s" % str(free_gesture["thrown"]))

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true

	# --- (a) F10 — ENTRAÎNEMENT : le clic DROIT sur un curseur de réglage ------------------------
	duel._tuning.toggle()
	_check_grenade_gate(duel, "F10", duel._tuning.visible)
	duel._tuning.toggle()

	# --- (b) ABANDON — duel CLASSÉ : la boîte « abandonner ? » est à l'écran ---------------------
	duel._input(esc)
	_check_grenade_gate(duel, "ABANDON", duel._abandon_overlay.visible)
	duel._input(esc)

	# --- (c) CHOIX D'ARME — il s'ouvre TOUT SEUL, en plein combat, et relâche la souris ----------
	duel._on_duel_event({"type": "weapon_choice", "slot": duel._my_slot,
		"options": ["chacal", "condor"]})
	_check_grenade_gate(duel, "CHOIX D ARME", duel._choice_panel.visible)
	duel._queue_pick(0)
	duel._pick_queued = ""

	# --- (d) ⚠️ LE PANNEAU QUI S'OUVRE *PENDANT* LE GESTE : on RANGE, on ne met pas en pause ------
	# C'est le cas réel du CHOIX D'ARME : personne ne l'appelle, il arrive. Geler la visée pour la
	# rendre à la fermeture relâcherait, des secondes plus tard, un lancer que le joueur ne vise
	# plus — et une grenade rendue au mauvais moment coûte autant qu'une grenade volée.
	_key(KEY_G, true)
	duel._update_grenade_aim(1.0 / 60.0)
	_ok("EN COURS DE VISEE : SENTINELLE — le decalque est bien a l'ecran AVANT l'ouverture",
		duel._aiming_grenade and duel._world._aim_decal != null
			and duel._world._aim_decal.visible,
		"vise=%s decalque=%s" % [duel._aiming_grenade,
			duel._world._aim_decal != null and duel._world._aim_decal.visible])
	duel._on_duel_event({"type": "weapon_choice", "slot": duel._my_slot,
		"options": ["chacal", "condor"]})
	duel._update_grenade_aim(1.0 / 60.0)
	_ok("EN COURS DE VISEE : le panneau RANGE la grenade (decalque eteint, pose abandonnee)",
		not duel._aiming_grenade and not duel._world._aim_decal.visible
			and not bool((duel._rig_state() as Dictionary).get("low_ready", false)),
		"vise=%s decalque=%s pose=%s" % [duel._aiming_grenade,
			duel._world._aim_decal.visible,
			bool((duel._rig_state() as Dictionary).get("low_ready", false))])
	_key(KEY_G, false)
	duel._update_grenade_aim(1.0 / 60.0)
	_ok("EN COURS DE VISEE : le relachement ne LANCE rien (le geste interrompu ne coute rien)",
		duel._throw_queued.is_empty(), "file = %s" % str(duel._throw_queued))
	duel._queue_pick(0)
	duel._pick_queued = ""
	duel._throw_queued = {}

	# --- (e) LE VERROU : la touche encore tenue à la FERMETURE ne relance rien toute seule -------
	_key(KEY_G, true)
	duel._tuning.toggle()
	duel._update_grenade_aim(1.0 / 60.0)     # sous le panneau : le geste est verrouillé
	duel._tuning.toggle()                    # … le panneau se referme, la touche est TOUJOURS tenue
	duel._update_grenade_aim(1.0 / 60.0)
	_ok("VERROU : touche encore tenue a la FERMETURE -> rien ne se rearme tout seul",
		not duel._aiming_grenade and not duel._world._aim_decal.visible,
		"vise=%s decalque=%s" % [duel._aiming_grenade, duel._world._aim_decal.visible])
	_key(KEY_G, false)
	duel._update_grenade_aim(1.0 / 60.0)
	_ok("VERROU : et le relachement ne LANCE rien non plus", duel._throw_queued.is_empty(),
		"file = %s" % str(duel._throw_queued))
	duel._throw_queued = {}

	# --- (f) LE CLAVIER EST LE MÊME CHEMIN : `G` tenu sonde la plateforme, pas l'événement -------
	# La garde d'`_input` ne peut RIEN pour lui : `_update_grenade_aim` lit `Input.is_key_pressed`
	# depuis `_process`, sans jamais passer par un événement.
	duel._input(esc)
	_ok("CLAVIER : SENTINELLE — le panneau d'abandon est bien OUVERT", duel._abandon_overlay.visible)
	var by_key := _grenade_gesture(duel, true)
	_ok("CLAVIER : `G` tenu sous l'abandon n'arme RIEN et ne lance RIEN",
		not bool(by_key["aimed"]) and not bool(by_key["decal"])
			and (by_key["thrown"] as Dictionary).is_empty(), _gesture_detail(by_key))
	duel._input(esc)

	# --- (g) CONTRE-ÉPREUVE : refermés, les deux gestes repartent -------------------------------
	# Un panneau ferme une porte, il n'en cloue aucune. Sans ces trois contrôles, tout ce qui
	# précède serait vert sur un client qui aurait simplement perdu la grenade.
	_ok("CONTRE-EPREUVE : les trois panneaux sont refermes",
		not duel._abandon_overlay.visible and not duel._choice_panel.visible
			and not duel._tuning.visible,
		"abandon=%s choix=%s F10=%s" % [duel._abandon_overlay.visible,
			duel._choice_panel.visible, duel._tuning.visible])
	var again := _grenade_gesture(duel)
	_ok("CONTRE-EPREUVE : le MEME geste SOURIS repart (visee armee, grenade en file)",
		bool(again["aimed"]) and bool(again["decal"]) and bool(again["pose"])
			and not (again["thrown"] as Dictionary).is_empty(), _gesture_detail(again))
	var again_key := _grenade_gesture(duel, true)
	_ok("CONTRE-EPREUVE : le geste CLAVIER repart aussi", bool(again_key["aimed"])
		and not (again_key["thrown"] as Dictionary).is_empty(), _gesture_detail(again_key))
	duel._throw_queued = {}
	# ⚠️ ON RANGE L'ÉTAT DE PLATEFORME ET LE CURSEUR : `_capture_mouse` a été appelé par les vrais
	# chemins d'ouverture/fermeture, et les sections suivantes lisent `Input.mouse_mode`.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# LES TROIS MÊMES MESURES POUR CHAQUE PANNEAU — l'ouverture est faite par l'appelant (chemin de
# production), la sentinelle « le panneau est bien OUVERT » est ici pour que le trio ne puisse pas
# verdir sur un panneau qui ne se serait jamais ouvert.
func _check_grenade_gate(duel, label: String, opened: bool) -> void:
	_ok("%s : le panneau est bien OUVERT" % label, opened)
	var g := _grenade_gesture(duel)
	_ok("%s OUVERT : la visee ne s'arme PAS (ni decalque au sol, ni pose de lancer)" % label,
		not bool(g["aimed"]) and not bool(g["decal"]) and not bool(g["pose"]),
		_gesture_detail(g))
	_ok("%s OUVERT : le relachement ne LANCE rien (aucune grenade en file)" % label,
		(g["thrown"] as Dictionary).is_empty(), "file = %s" % str(g["thrown"]))


# =================================================================================================
# 2ter. LES PANNEAUX FERMENT AUSSI LE CLAVIER — LE 4ᵉ CHEMIN D'ACTION
# =================================================================================================
# ╔═ 🩸🩸 LE MÊME DÉFAUT, SUR TOUT CE QUE LE SOLDAT FAIT D'AUTRE QUE TIRER ═══════════════════════╗
# ║ Les sections 2 (i) et 2bis gardent les TROIS chemins OFFENSIFS (clic, maintien, grenade). Il en ║
# ║ restait un QUATRIÈME, et c'est le même motif exactement :                                       ║
# ║   • `_gather_move_dir()` SONDE la plateforme depuis `_process` (`Input.is_key_pressed`) —      ║
# ║     comme la grenade, donc la garde d'`_input` ne pouvait RIEN pour lui ;                       ║
# ║   • `R` (rechargement), `S`/`CTRL`/`↑`/`↓` (posture) et `2` (pansement) étaient traités         ║
# ║     AU-DESSUS de la garde d'`_input`, donc pendant le panneau.                                  ║
# ║ MESURÉ, panneau F10 ouvert : `pos 2 → 1` à la flèche DROITE, `posture = down` à la flèche BAS, ║
# ║ `reload` et `item` VRAIMENT partis dans une charge passée à `send_trench_input`. Les trois       ║
# ║ panneaux relâchent la souris : le joueur ne pouvait plus viser, mais son soldat marchait,       ║
# ║ s'accroupissait, rechargeait et se soignait. Et les HSlider du panneau F10 se pilotent AUX      ║
# ║ FLÈCHES : régler un curseur faisait faire des pas au soldat.                                    ║
# ║                                                                                                 ║
# ║ ⚠️ CE QUE CETTE SECTION LIT N'EST PAS UN DRAPEAU DE PLUS. Le déplacement est mesuré par la      ║
# ║ POSITION PRÉDITE (ce que le joueur voit bouger) ET par le champ `move` de la charge RÉELLE — le ║
# ║ bandeau F3 est rempli par `_log_input(payload)`, à l'intérieur même du bloc d'envoi, avec la    ║
# ║ charge passée à `NetworkManager.send_trench_input`. Le rechargement et le pansement sont mesurés║
# ║ ARMÉS puis CONSOMMÉS : les drapeaux ne sont vidés qu'APRÈS l'envoi, une consommation prouve donc║
# ║ que la charge les portait.                                                                      ║
# ║ ⚠️ RECENTRAGE AVANT CHAQUE PAS — le faux vert que la boucle de critique a rencontré : mesuré    ║
# ║ collé à la borne du `clampi`, un pas qui PART se lit « pos 0 → 0 » et fait conclure à une porte ║
# ║ là où il n'y a qu'un mur. Les sentinelles attrapent ce vert-là, le recentrage l'empêche.        ║
# ║ ⚠️ ET UNE PORTE PAR ACTION, PAS UNE PORTE GLOBALE : (e) exige qu'ÉCHAP, F10, F1 et F3 répondent ║
# ║ ENCORE pour FERMER les panneaux, et (d) que `2` continue de CHOISIR L'ARME sous le panneau de   ║
# ║ choix. Sans ces contrôles-là, un correctif qui clouerait `_input` en tête resterait vert en     ║
# ║ enfermant le joueur dans un panneau qu'il ne peut plus refermer.                                ║
# ╠═ 🩸🩸 ET (d) A ÉTÉ RETOURNÉE : LE SÉLECTEUR D'ARME NE GÈLE PLUS LE SOLDAT ═══════════════════╣
# ║ Cette section-ci a d'abord FIGÉ le défaut inverse : « CHOIX D ARME OUVERT : la flèche DROITE ne ║
# ║ DÉPLACE PAS le soldat » était compté PASS. Or ce panneau-là n'est pas F10 ni la boîte           ║
# ║ d'abandon : ce n'est pas le joueur qui l'ouvre, c'est le SERVEUR (`_credit_hit`, 10ᵉ coup au    ║
# ║ but), il reste 5,0 s (`choice_window_ticks` = 100 à 20 Hz) — et pendant ces 5 s la SIM CONTINUE ║
# ║ DE TOURNER : `trench_sim.step` applique `stance`, `move`, `reload` et `item` sans regarder      ║
# ║ `choice_deadline_tick`, et l'adversaire joue normalement. Le client REFUSAIT donc des entrées   ║
# ║ que le serveur, lui, honore — la désynchronisation intention-joueur / simulation du §8.141.     ║
# ║ (d) exige maintenant l'INVERSE : sous le sélecteur, le pas, la posture et le rechargement       ║
# ║ RÉPONDENT — et la porte OFFENSIVE, elle, reste fermée (le clic ne tire pas, cf. la section      ║
# ║ 2bis pour la grenade). Deux portes, deux mesures : c'est leur DIFFÉRENCE qui est le sujet.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_panels_keyboard(duel) -> void:
	_section("2ter. LES PANNEAUX FERMENT AUSSI LE CLAVIER — le 4e chemin d'action (pas, posture,"
		+ " rechargement, pansement)")
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	# Aucun bouton de souris tenu : sinon `_step_held_fire` armerait des tirs et rendrait l'envoi
	# « urgent », donc la trame de frames non déterministe.
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	_key(KEY_G, false)
	duel._fire_queued = false
	duel._throw_queued = {}
	# LE PANNEAU F10 EST RÉSERVÉ À L'ENTRAÎNEMENT (`_input`, `KEY_F10`) : sans ce drapeau, la touche
	# F10 de la sous-section (e) ne ferait rien et le contrôle mesurerait un panneau, pas une touche.
	var training_was: bool = duel._training
	duel._training = true
	# LE BANDEAU F3, ouvert PAR SA TOUCHE : c'est lui qui donne à lire la charge réellement envoyée.
	if not duel._diag.visible:
		duel._input(_key_event(KEY_F3))
	_ok("SENTINELLE : le bandeau F3 est ouvert (c'est lui qui rend la charge envoyee lisible)",
		duel._diag.visible)

	# --- (a) LA SENTINELLE D'ABORD : panneaux FERMÉS, les quatre gestes répondent ----------------
	_ok("SENTINELLE : les trois panneaux sont FERMES",
		not duel._abandon_overlay.visible and not duel._choice_panel.visible
			and duel._tuning != null and not duel._tuning.visible,
		"abandon=%s choix=%s F10=%s" % [duel._abandon_overlay.visible,
			duel._choice_panel.visible, duel._tuning.visible])
	var free_keys := _keyboard_probe(duel, true)
	_ok("SENTINELLE : le bandeau F3 a bien ete RAFRAICHI par un envoi (sinon tout ce qui suit est"
		+ " une lecture perimee)", str(free_keys["payload_move"]) != "",
		"champ `move` de la charge = « %s »" % str(free_keys["payload_move"]))
	_ok("SENTINELLE : la fleche DROITE fait un pas, et la charge porte ce pas",
		bool(free_keys["moved"]) and str(free_keys["payload_move"]) != ""
			and str(free_keys["payload_move"]) != "+0", _keys_detail(free_keys))
	_ok("SENTINELLE : la fleche BAS fait s'accroupir le soldat", free_keys["stance"] == "down",
		"posture = %s" % str(free_keys["stance"]))
	_ok("SENTINELLE : `R` arme un rechargement, et l'envoi l'EMPORTE",
		bool(free_keys["reload_armed"]) and bool(free_keys["reload_sent"]), _keys_detail(free_keys))
	_ok("SENTINELLE : `2` arme un pansement, et l'envoi l'EMPORTE",
		free_keys["item_armed"] == "bandage" and bool(free_keys["item_sent"]),
		_keys_detail(free_keys))

	var esc := _key_event(KEY_ESCAPE)

	# --- (b) F10 — ENTRAÎNEMENT : les flèches pilotent les HSlider du panneau --------------------
	duel._tuning.toggle()
	_check_keyboard_gate(duel, "F10", duel._tuning.visible, true)
	duel._tuning.toggle()

	# --- (c) ABANDON — duel CLASSÉ : la boîte « abandonner ? » est à l'écran --------------------
	duel._input(esc)
	_check_keyboard_gate(duel, "ABANDON", duel._abandon_overlay.visible, true)
	duel._input(esc)

	# --- (d) CHOIX D'ARME — il s'ouvre TOUT SEUL, en plein combat : LE SOLDAT NE GÈLE PAS -------
	# ⚠️ SANS pansement ici : sous CE panneau-là, `2` a un AUTRE rôle — il choisit l'arme. C'est
	# exactement ce que le contrôle suivant exige, et c'est ce qui interdit la porte globale.
	# ⚠️⚠️ ET LES QUATRE MESURES SONT RETOURNÉES : ce panneau-ci est posé par le SERVEUR en pleine
	# manche, pour 5,0 s pendant lesquelles la sim honore `move`/`stance`/`reload` et l'adversaire
	# continue de jouer (cf. le pavé ci-dessus). Marcher, se cacher et recharger doivent RÉPONDRE.
	# ⚠️⚠️ ET IL FAUT L'ÉCHÉANCE DU SERVEUR AVEC : contrairement à la section 2bis (qui n'appelle que
	# `_update_grenade_aim`), cette section-ci fait tourner de VRAIS `_process`, donc
	# `_refresh_view` — et `_refresh_view` REFERME le panneau de choix dès que l'état ne porte plus
	# d'échéance (`choice_deadline_tick` = 0 : « la question n'a plus lieu d'être »). MESURÉ : sans
	# cette fixture, le panneau se refermait à la première frame et les quatre contrôles mesuraient
	# un panneau FERMÉ en croyant le tenir ouvert — le vert (ici le rouge) par DISPARITION.
	_push_choice_deadline(duel)
	duel._on_duel_event({"type": "weapon_choice", "slot": duel._my_slot,
		"options": ["chacal", "condor"]})
	_check_keyboard_open(duel, "CHOIX D ARME", duel._choice_panel.visible)
	# ⚠️ L'AUTRE MOITIÉ DU REMÈDE : ce panneau NE VOLE PAS LES FLÈCHES. Ses deux boutons sont en
	# `FOCUS_NONE` — sans ça, la navigation de focus de Godot capterait ←/→ pendant que le soldat
	# marche, et `ui_accept` choisirait une arme sur un geste de déplacement. C'est ce qui retire au
	# déplacement toute raison d'être gâté ici ; ils gardent la souris et leurs touches à eux.
	var focusable := 0
	for btn: Button in duel._choice_buttons:
		if btn.focus_mode != Control.FOCUS_NONE:
			focusable += 1
	_ok("CHOIX D ARME : ses deux boutons ne prennent PAS le focus (les fleches restent au soldat)",
		duel._choice_buttons.size() == 2 and focusable == 0,
		"%d bouton(s) focalisable(s) sur %d" % [focusable, duel._choice_buttons.size()])
	# ⚠️ ET LA PORTE OFFENSIVE, ELLE, RESTE FERMÉE — c'est la DIFFÉRENCE entre les deux portes qui
	# est mesurée ici, pas l'une des deux : sous ce panneau la souris est relâchée, le lacet et le
	# site sont gelés, et un clic ne doit pas partir. (La grenade, 3ᵉ chemin, est gardée en 2bis.)
	# La posture est remise DEBOUT d'abord : `_keyboard_probe` vient d'accroupir le soldat pour de
	# bon, et « accroupi » est un refus de tir — le contrôle mesurerait la posture, pas la porte.
	duel._stance_toggle = false
	duel._pred_stance = "up"
	var choice_click := InputEventMouseButton.new()
	choice_click.button_index = MOUSE_BUTTON_LEFT
	choice_click.pressed = true
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	duel._input(choice_click)
	_ok("CHOIX D ARME OUVERT : le CLIC n'arme AUCUN tir (la porte OFFENSIVE, elle, ferme bien)",
		not duel._fire_queued and duel._shot_count == 0,
		"tir=%s, %d retour(s) d'arme" % [duel._fire_queued, duel._shot_count])
	duel._item_queued = ""
	duel._pick_queued = ""
	duel._input(_key_event(KEY_2))
	_ok("CHOIX D ARME OUVERT : `2` CHOISIT bien l'arme (le panneau garde SES touches)",
		duel._pick_queued != "" and not duel._choice_panel.visible,
		"arme = « %s » · panneau encore visible = %s" % [duel._pick_queued,
			duel._choice_panel.visible])
	_ok("CHOIX D ARME : et ce `2` n'a PAS depense de pansement (une porte par ACTION)",
		duel._item_queued == "", "file objet = « %s »" % duel._item_queued)
	duel._pick_queued = ""
	_push(duel, "vipere", 99)              # on rend l'état ORDINAIRE (plus d'échéance en attente)
	# CONTRE-ÉPREUVE DU CLIC : panneau refermé, le MÊME clic tire pour de bon. Sans elle, le
	# contrôle ci-dessus serait vert sur un client qui ne tirerait plus jamais.
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_refuse = 0.0
	duel._fire_queued = false
	duel._shot_count = 0
	duel._input(choice_click)
	_ok("CHOIX D ARME REFERME : le MEME clic repart (le controle ci-dessus etait PORTEUR)",
		duel._fire_queued and duel._shot_count == 1,
		"tir=%s, %d retour(s) d'arme" % [duel._fire_queued, duel._shot_count])
	duel._fire_queued = false
	duel._shot_count = 0
	duel._fire_refuse = 0.0

	# --- (e) ⚠️ LES TOUCHES DE PANNEAU RÉPONDENT ENCORE — sinon le joueur est ENFERMÉ ------------
	# Une porte globale en tête d'`_input` fermerait aussi la sortie. Ces quatre contrôles sont la
	# raison pour laquelle le bloc de touches est coupé en deux plutôt que gardé d'un bloc.
	duel._tuning.toggle()
	_ok("SORTIE : SENTINELLE — le panneau F10 est bien OUVERT", duel._tuning.visible)
	duel._input(_key_event(KEY_F10))
	_ok("SORTIE : la touche F10 REFERME encore le panneau", not duel._tuning.visible,
		"F10 visible = %s" % duel._tuning.visible)
	duel._input(esc)
	_ok("SORTIE : SENTINELLE — la boite d'abandon est bien OUVERTE", duel._abandon_overlay.visible)
	var diag_before: bool = duel._diag.visible
	duel._input(_key_event(KEY_F3))
	_ok("SORTIE : F3 repond ENCORE sous un panneau ouvert (le diagnostic n'est jamais coupe)",
		duel._diag.visible != diag_before, "bandeau %s -> %s" % [diag_before, duel._diag.visible])
	duel._input(_key_event(KEY_F3))
	var help_before: bool = duel._help_panel.visible
	duel._input(_key_event(KEY_F1))
	_ok("SORTIE : F1 repond ENCORE sous un panneau ouvert (le guide des commandes non plus)",
		duel._help_panel.visible != help_before,
		"guide %s -> %s" % [help_before, duel._help_panel.visible])
	duel._input(_key_event(KEY_F1))
	duel._input(esc)
	_ok("SORTIE : ECHAP REFERME encore la boite d'abandon", not duel._abandon_overlay.visible,
		"abandon visible = %s" % duel._abandon_overlay.visible)

	# --- (f) CONTRE-ÉPREUVE : refermés, les quatre gestes repartent ------------------------------
	# Un panneau ferme une porte, il n'en cloue aucune. Sans ces contrôles, tout ce qui précède
	# serait vert sur un client dont le clavier serait mort pour de bon.
	_ok("CONTRE-EPREUVE : les trois panneaux sont refermes",
		not duel._abandon_overlay.visible and not duel._choice_panel.visible
			and not duel._tuning.visible,
		"abandon=%s choix=%s F10=%s" % [duel._abandon_overlay.visible,
			duel._choice_panel.visible, duel._tuning.visible])
	var again := _keyboard_probe(duel, true)
	_ok("CONTRE-EPREUVE : le pas, la posture, le rechargement et le pansement repartent TOUS",
		bool(again["moved"]) and str(again["payload_move"]) != "+0"
			and again["stance"] == "down" and bool(again["reload_sent"])
			and bool(again["item_sent"]), _keys_detail(again))

	# ⚠️ ON RANGE CE QUE CETTE SECTION A OUVERT : le bandeau F3 est un Label OR posé sur le HUD, et
	# la section 3bis compte des pixels OR avant le masquage de la section 5.
	if duel._diag.visible:
		duel._input(_key_event(KEY_F3))
	duel._training = training_was
	duel._stance_toggle = false
	duel._pred_stance = "up"
	duel._reload_queued = false
	duel._item_queued = ""
	# ⚠️⚠️ ON REPOSE LE SOLDAT AU CENTRE *DANS LE MONDE 3D*, pas seulement dans la variable. Cette
	# section fait faire de VRAIS pas ; remettre `_pred_pos` sans rejouer `set_pose` laisserait la
	# CAMÉRA une position plus loin, et tout ce qui se projette ensuite serait décalé d'un
	# espacement exact. MESURÉ : la section 3 (h) rougissait de 352,7 px — un espacement au pixel
	# près — et la secousse de la même section, mesurée depuis une explosion posée à la position 2
	# alors que la caméra était en 1, ne franchissait plus le seuil.
	duel._pred_pos = int(duel._positions / 2)
	duel._world.set_pose(duel._pred_pos, duel._pred_stance)
	duel._refresh_pose_view()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# LES QUATRE MÊMES MESURES POUR CHAQUE PANNEAU — l'ouverture est faite par l'appelant (chemin de
# production), la sentinelle « le panneau est bien OUVERT » est ici pour que le lot ne puisse pas
# verdir sur un panneau qui ne se serait jamais ouvert.
func _check_keyboard_gate(duel, label: String, opened: bool, with_item: bool) -> void:
	_ok("%s : le panneau est bien OUVERT" % label, opened)
	var k := _keyboard_probe(duel, with_item)
	_ok("%s OUVERT : la fleche DROITE ne DEPLACE PAS le soldat, et la charge porte `move +0`"
		% label,
		not bool(k["moved"]) and str(k["payload_move"]) == "+0", _keys_detail(k))
	_ok("%s OUVERT : la fleche BAS ne fait PAS s'accroupir le soldat" % label,
		k["stance"] == "up", "posture = %s" % str(k["stance"]))
	_ok("%s OUVERT : `R` n'arme AUCUN rechargement" % label,
		not bool(k["reload_armed"]) and not bool(k["reload_sent"]), _keys_detail(k))
	if with_item:
		_ok("%s OUVERT : `2` ne depense AUCUN pansement" % label,
			k["item_armed"] == "" and not bool(k["item_sent"]), _keys_detail(k))


# LE CONTRÔLEUR MIROIR DU PRÉCÉDENT — pour le panneau que le SERVEUR ouvre en pleine manche. Les
# mêmes gestes, mesurés par les mêmes chemins, avec l'attendu INVERSE : ils RÉPONDENT. Le pansement
# n'y est pas parce que `2` appartient au panneau tant qu'il est à l'écran (cf. (d)).
func _check_keyboard_open(duel, label: String, opened: bool) -> void:
	_ok("%s : le panneau est bien OUVERT" % label, opened)
	var k := _keyboard_probe(duel, false)
	_ok("%s OUVERT : la fleche DROITE DEPLACE le soldat, et la charge PORTE ce pas" % label,
		bool(k["moved"]) and str(k["payload_move"]) != ""
			and str(k["payload_move"]) != "+0", _keys_detail(k))
	_ok("%s OUVERT : la fleche BAS fait s'accroupir le soldat (le bouton de panique du jeu)" % label,
		k["stance"] == "down", "posture = %s" % str(k["stance"]))
	_ok("%s OUVERT : `R` arme un rechargement, et l'envoi l'EMPORTE" % label,
		bool(k["reload_armed"]) and bool(k["reload_sent"]), _keys_detail(k))


# LES QUATRE GESTES DU CLAVIER, par le chemin de PRODUCTION. Le PAS passe par un vrai état de
# plateforme (`Input.parse_input_event`) parce que `_gather_move_dir()` SONDE la plateforme depuis
# `_process` ; les trois autres passent par un vrai événement, parce que c'est `_input` qui les lit.
# ⚠️ Cette fonction n'écrit dans AUCUNE porte : elle ne remet à plat que ce qu'elle vient elle-même
# de mesurer (le verrou de pas, la posture de départ, les deux files de sortie).
func _keyboard_probe(duel, with_item: bool) -> Dictionary:
	var out := {}
	# --- LE PAS : recentré d'abord (cf. le pavé — le faux vert par SATURATION du `clampi`) -------
	duel._pred_pos = int(duel._positions / 2)
	var from_pos: int = duel._pred_pos
	_key(KEY_RIGHT, true)
	_run_send(duel)
	_key(KEY_RIGHT, false)
	out["from"] = from_pos
	out["to"] = duel._pred_pos
	out["moved"] = duel._pred_pos != from_pos
	out["payload_move"] = _journal_field(duel, "move ")
	# --- LA POSTURE : `↓` = SE CACHER (§8.137) --------------------------------------------------
	duel._stance_toggle = false
	duel._pred_stance = "up"
	duel._input(_key_event(KEY_DOWN))
	_run_send(duel)
	out["stance"] = duel._pred_stance
	duel._stance_toggle = false
	# --- LE RECHARGEMENT : armé par `_input`, EMPORTÉ par l'envoi --------------------------------
	duel._reload_queued = false
	duel._input(_key_event(KEY_R))
	out["reload_armed"] = duel._reload_queued
	_run_send(duel)
	out["reload_sent"] = bool(out["reload_armed"]) and not duel._reload_queued
	duel._reload_queued = false
	# --- LE PANSEMENT : la ressource rare (1 par manche) ----------------------------------------
	out["item_armed"] = ""
	out["item_sent"] = false
	if with_item:
		duel._item_queued = ""
		duel._input(_key_event(KEY_2))
		out["item_armed"] = duel._item_queued
		_run_send(duel)
		out["item_sent"] = str(out["item_armed"]) != "" and duel._item_queued == ""
		duel._item_queued = ""
	return out


func _keys_detail(k: Dictionary) -> String:
	return "pos %s -> %s · charge move « %s » · posture %s · reload arme=%s emporte=%s ·" \
		% [k["from"], k["to"], k["payload_move"], k["stance"], k["reload_armed"],
			k["reload_sent"]] \
		+ " objet arme=« %s » emporte=%s" % [k["item_armed"], k["item_sent"]]


# UN ENVOI COALESCÉ, ET UN SEUL. `_process` ne construit la charge que lorsque `_send_accum`
# franchit `SEND_INTERVAL` : on remet l'accumulateur et la fenêtre glissante à plat, puis on fait
# tourner juste assez de frames pour que l'envoi ait lieu. C'est LUI qui remplit le bandeau F3
# (`_log_input`) avec la charge RÉELLE passée à `NetworkManager.send_trench_input` — et qui vide,
# juste après, les drapeaux `reload` / `item`.
# ⚠️ LE BANDEAU EST EFFACÉ D'ABORD : sans ça, une frame qui n'enverrait rien laisserait lire la
# charge PRÉCÉDENTE, et la sonde mesurerait un envoi qui n'a pas eu lieu.
# ⚠️ `_pred_move_ready` est remis à zéro parce que le verrou de pas dure 0,5 s (`move_ticks`) : sans
# ça, la deuxième mesure d'une série serait bloquée par le VERROU et non par la porte de panneau.
func _run_send(duel) -> void:
	duel._diag.text = ""
	duel._send_accum = 0.0
	duel._sent_at.clear()
	duel._pred_move_ready = 0.0
	for i in range(int(ceil(duel.SEND_INTERVAL * 60.0)) + 1):
		duel._process(1.0 / 60.0)


# UN CHAMP DU BANDEAU F3, tel que `_log_input` l'a écrit depuis la charge utile. `move %+d` sort de
# `int(payload.get("move", 0))` : c'est la charge, pas une re-dérivation de la sonde.
func _journal_field(duel, prefix: String) -> String:
	var text: String = duel._diag.text
	var at := text.find(prefix)
	if at < 0:
		return ""
	var rest := text.substr(at + prefix.length())
	var stop := rest.find(" ·")
	if stop < 0:
		stop = rest.find("\n")
	if stop < 0:
		return rest.strip_edges()
	return rest.substr(0, stop).strip_edges()


func _key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev


# LA FIXTURE DU PANNEAU DE CHOIX : la même que `_push`, plus l'ÉCHÉANCE que le serveur annonce en
# même temps que la question. `_refresh_view` referme le panneau quand `choice_deadline_tick` vaut
# 0 — c'est-à-dire à la PREMIÈRE frame de `_process` pour la fixture ordinaire.
func _push_choice_deadline(duel) -> void:
	var mine: int = duel._my_slot
	var mine_row := _player_row(mine, 2, "up", "vipere", 99)
	mine_row["choice_deadline_tick"] = 100000
	duel._buffer.clear()
	duel._on_state({"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [mine_row, _player_row(3 - mine, 2, "up", _other_weapon(duel, "vipere"), 8)],
		"projectiles": [], "events": []})


# =================================================================================================
# 2quater. LA SOURIS — REFERMER UN PANNEAU NE LA REPREND PAS SI UN AUTRE TIENT L'ÉCRAN
# =================================================================================================
# ╔═ 🩸 LE CURSEUR DISPARAISSAIT SUR UNE INTERFACE QUI ATTEND UN CLIC ════════════════════════════╗
# ║ `_capture_mouse()` était un poseur NU, et ses cinq appelants raisonnaient chacun sur LEUR seul ║
# ║ panneau (`not _tuning.visible`, `not _abandon_overlay.visible`, `not _match_over`). Chemin le  ║
# ║ plus court, avec le réflexe le plus naturel qui soit, en ENTRAÎNEMENT : F10 ouvre les réglages ║
# ║ → ÉCHAP (le réflexe pour fermer un panneau) ouvre en fait « abandonner ? » → ÉCHAP à nouveau   ║
# ║ la referme et RECAPTURAIT la souris alors que F10 était TOUJOURS à l'écran. Plus de curseur,   ║
# ║ plus un seul réglage cliquable ; seul F10 remettait les choses en place. Même classe en duel   ║
# ║ CLASSÉ, où le panneau de CHOIX D'ARME s'ouvre TOUT SEUL : ses deux boutons devenaient          ║
# ║ inatteignables à la souris.                                                                    ║
# ║ AUCUNE des sections de cette sonde ne mesurait `Input.mouse_mode` après une fermeture — la     ║
# ║ 2bis le REMET même à `MOUSE_MODE_VISIBLE` à la main en fin de section. Rien ne pouvait rougir. ║
# ║                                                                                                ║
# ║ ⚠️⚠️ CE QUE CETTE SECTION LIT, ET POURQUOI CE N'EST PAS `Input.mouse_mode` SOUS PILOTE MUET.   ║
# ║ MESURÉ : sous `--headless`, `Input.mouse_mode = CAPTURED` ne retient RIEN (le pilote rend      ║
# ║ `VISIBLE`, toujours). Une section qui lirait la plateforme y serait VERTE sur « la souris      ║
# ║ reste au joueur » quoi qu'il arrive, et ROUGE sur « elle revient au duel » quoi qu'il arrive.  ║
# ║ On lit donc la DÉCISION du client (`_mouse_captured`, posé par `_capture_mouse` lui-même) —    ║
# ║ et, sous PILOTE RÉEL, deux contrôles de plus RECOLLENT cette décision à `Input.mouse_mode`.    ║
# ║ L'état ET son image, jamais l'un sans l'autre (leçon du §8.151.4ter).                          ║
# ║ ⚠️ TOUT PASSE PAR LES CHEMINS DE PRODUCTION : la touche F10, la touche ÉCHAP, l'événement      ║
# ║ serveur `weapon_choice`, le bouton du sélecteur (`_queue_pick`). Poser `.visible` à la main     ║
# ║ mesurerait un panneau que le jeu n'ouvre pas comme ça — et surtout n'appellerait aucun des     ║
# ║ sites de fermeture, c'est-à-dire précisément ce qui est en cause.                              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_mouse_capture(duel) -> void:
	_section("2quater. LA SOURIS — refermer UN panneau ne la reprend pas si un AUTRE tient l'ecran")
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "vipere", 99)
	# LE PANNEAU F10 EST RÉSERVÉ À L'ENTRAÎNEMENT : sans ce drapeau, la touche ne ferait rien et
	# les contrôles mesureraient une touche morte plutôt qu'une souris.
	var training_was: bool = duel._training
	duel._training = true
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	_key(KEY_G, false)
	var esc := _key_event(KEY_ESCAPE)
	var f10 := _key_event(KEY_F10)

	# --- SENTINELLES : l'écran est libre, et la souris SAIT revenir au duel ----------------------
	# Sans la seconde, les six contrôles « elle reste au joueur » seraient tous verts sur un client
	# qui ne capturerait plus jamais rien — le vert par disparition.
	_ok("SENTINELLE : aucune visee de grenade en cours (sinon ECHAP la rangerait au lieu d'ouvrir"
		+ " la boite d'abandon)", not duel._aiming_grenade, "vise = %s" % duel._aiming_grenade)
	_ok("SENTINELLE : les trois panneaux sont FERMES",
		not duel._abandon_overlay.visible and not duel._choice_panel.visible
			and duel._tuning != null and not duel._tuning.visible,
		"abandon=%s choix=%s F10=%s" % [duel._abandon_overlay.visible,
			duel._choice_panel.visible, duel._tuning.visible])
	duel._restore_mouse()
	_ok("SENTINELLE : ecran LIBRE -> la souris revient au duel", duel._mouse_captured,
		"capturee = %s" % duel._mouse_captured)

	# --- (a) LE CHEMIN DU DÉFAUT, TOUCHE PAR TOUCHE : F10 -> ÉCHAP -> ÉCHAP ----------------------
	duel._input(f10)
	_ok("F10 : le panneau est OUVERT et la souris est RENDUE au joueur",
		duel._tuning.visible and not duel._mouse_captured,
		"F10=%s capturee=%s" % [duel._tuning.visible, duel._mouse_captured])
	duel._input(esc)
	_ok("F10 + ECHAP : la boite « abandonner ? » s'ouvre PAR-DESSUS, souris toujours rendue",
		duel._abandon_overlay.visible and duel._tuning.visible and not duel._mouse_captured,
		"abandon=%s F10=%s capturee=%s" % [duel._abandon_overlay.visible, duel._tuning.visible,
			duel._mouse_captured])
	duel._input(esc)
	_ok("F10 + ECHAP + ECHAP : la boite se referme, F10 tient ENCORE l'ecran -> la souris RESTE"
		+ " au joueur",
		not duel._abandon_overlay.visible and duel._tuning.visible and not duel._mouse_captured,
		"abandon=%s F10=%s capturee=%s" % [duel._abandon_overlay.visible, duel._tuning.visible,
			duel._mouse_captured])
	duel._input(f10)
	_ok("F10 REFERME : plus rien ne tient l'ecran -> la souris revient au duel",
		not duel._tuning.visible and duel._mouse_captured,
		"F10=%s capturee=%s" % [duel._tuning.visible, duel._mouse_captured])

	# --- (b) MÊME CLASSE EN DUEL CLASSÉ : le sélecteur d'arme, qui s'ouvre TOUT SEUL -------------
	# Il faut l'échéance serveur avec lui : `_refresh_view` referme le panneau dès qu'elle manque.
	_push_choice_deadline(duel)
	duel._on_duel_event({"type": "weapon_choice", "slot": duel._my_slot,
		"options": ["chacal", "condor"]})
	_ok("CHOIX D ARME : le panneau s'ouvre TOUT SEUL et la souris est rendue",
		duel._choice_panel.visible and not duel._mouse_captured,
		"choix=%s capturee=%s" % [duel._choice_panel.visible, duel._mouse_captured])
	duel._input(esc)
	duel._input(esc)
	_ok("CHOIX D ARME + ECHAP + ECHAP : ses deux boutons restent CLIQUABLES (souris rendue)",
		duel._choice_panel.visible and not duel._abandon_overlay.visible
			and not duel._mouse_captured,
		"choix=%s abandon=%s capturee=%s" % [duel._choice_panel.visible,
			duel._abandon_overlay.visible, duel._mouse_captured])

	# --- (c) ET L'INVERSE : CHOISIR SON ARME par-dessus un F10 encore ouvert ---------------------
	duel._input(f10)
	_ok("SENTINELLE : F10 et le selecteur sont ouverts EN MEME TEMPS",
		duel._tuning.visible and duel._choice_panel.visible,
		"F10=%s choix=%s" % [duel._tuning.visible, duel._choice_panel.visible])
	duel._queue_pick(0)
	_ok("CHOIX FAIT sous F10 : le selecteur se ferme, F10 tient l'ecran -> la souris RESTE au"
		+ " joueur",
		not duel._choice_panel.visible and duel._tuning.visible and not duel._mouse_captured,
		"choix=%s F10=%s capturee=%s" % [duel._choice_panel.visible, duel._tuning.visible,
			duel._mouse_captured])
	duel._pick_queued = ""

	# --- (d) SOUS PILOTE RÉEL : la décision atteint bien la PLATEFORME ---------------------------
	if DisplayServer.get_name() == "headless":
		print("  (pilote muet : `Input.mouse_mode` ne retient rien sous --headless — mesure de la")
		print("   DECISION seule. Les 2 controles de plateforme s'ajoutent en FENETRE.)")
	else:
		_ok("PILOTE REEL : panneau ouvert -> `Input.mouse_mode` est VISIBLE (la decision atteint"
			+ " la plateforme)",
			Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not duel._mouse_captured,
			"mode=%d capturee=%s" % [Input.mouse_mode, duel._mouse_captured])
		duel._input(f10)
		_ok("PILOTE REEL : ecran libre -> `Input.mouse_mode` est CAPTURED",
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and duel._mouse_captured,
			"mode=%d capturee=%s" % [Input.mouse_mode, duel._mouse_captured])
		duel._input(f10)

	# --- CONTRE-ÉPREUVE : tout refermé, la souris revient au duel --------------------------------
	duel._input(f10)
	_ok("CONTRE-EPREUVE : les trois panneaux refermes -> la souris revient au duel",
		not duel._tuning.visible and not duel._choice_panel.visible
			and not duel._abandon_overlay.visible and duel._mouse_captured,
		"F10=%s choix=%s abandon=%s capturee=%s" % [duel._tuning.visible,
			duel._choice_panel.visible, duel._abandon_overlay.visible, duel._mouse_captured])

	# ⚠️ ON RANGE : le curseur est RENDU par le chemin de production (état ET plateforme d'accord),
	# et l'état serveur redevient ordinaire — plus d'échéance de choix en attente.
	duel._training = training_was
	duel._capture_mouse(false)
	_push(duel, "vipere", 99)


# =================================================================================================
# 3. DÉGÂTS FLOTTANTS (§4bis.3)
# =================================================================================================
func _section_damage(duel) -> void:
	_section("3. DEGATS FLOTTANTS — un chiffre par touche CONFIRMEE, et rien sans evenement")
	duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": _production_weapons()}
	_push(duel, "frelon", 40)
	_clear_damage(duel)

	_ok("POOL PREALLOUE : au moins 8 etiquettes bâties a la construction",
		duel._damage_pool.size() >= 8, "%d etiquettes" % duel._damage_pool.size())
	var sized := true
	for node: Label in duel._damage_pool:
		if node.size == Vector2.ZERO:
			sized = false
	_ok("TAILLE POSEE : aucune etiquette a size (0,0) (8e recidive interdite)", sized,
		"taille de la premiere : %s" % str(duel._damage_pool[0].size))

	# --- a) AUCUN EVENEMENT -> AUCUN CHIFFRE ----------------------------------------------------
	for i in range(30):
		duel._clock += 1.0 / 60.0
		duel._step_damage_numbers()
	_ok("AUCUN evenement serveur -> AUCUN chiffre", duel._damage_live.is_empty(),
		"%d chiffres en vol" % duel._damage_live.size())
	var visible_without_event := 0
	for node: Label in duel._damage_pool:
		if node.visible:
			visible_without_event += 1
	_ok("AUCUN evenement -> aucune etiquette visible", visible_without_event == 0,
		"%d visibles" % visible_without_event)

	# ⚠️⚠️ ET SURTOUT : TIRER N'EST PAS TOUCHER. C'est LE contrôle qui attrape la triche naturelle —
	# faire naître le chiffre au clic, « puisqu'on sait qu'on a tiré ». Le client sait qu'il a tiré ;
	# il ne sait NI s'il a touché NI combien (table angulaire, posture, bandage : tout est serveur).
	# Un tir ACCEPTÉ par la prédiction des six refus ne doit donc produire ni chiffre ni hitmarker.
	duel._clock += 10.0
	duel._pred_fire_ready = 0.0
	duel._fire_queued = false
	duel._queue_fire()
	_ok("TIRER n'est pas TOUCHER : un tir ACCEPTE ne cree aucun chiffre",
		duel._fire_queued and duel._damage_live.is_empty(),
		"tir emis=%s, %d chiffres" % [duel._fire_queued, duel._damage_live.size()])
	_ok("TIRER n'est pas TOUCHER : un tir ACCEPTE n'allume aucun hitmarker",
		duel._hitmarker <= 0.0, "hitmarker %.3f" % duel._hitmarker)
	duel._fire_queued = false

	# --- b) UNE touche CONFIRMEE -> UN chiffre, celui du serveur --------------------------------
	duel._on_duel_event(_hit_event(duel, 17, 42))
	_ok("UNE touche confirmee -> UN chiffre", duel._damage_live.size() == 1,
		"%d chiffres" % duel._damage_live.size())
	var first: Label = duel._damage_live[0]["node"] if duel._damage_live.size() > 0 else null
	_ok("le chiffre est celui de l'EVENEMENT (17), pas un barème local",
		first != null and first.text == "17", "texte = %s" % (first.text if first else "<rien>"))
	_ok("touche NON fatale : le chiffre est OR (pas rouge)",
		first != null and first.get_theme_color("font_color") == duel.COL_GOLD)
	# ╔═ 🩸🩸 ET IL EST *À L'ÉCRAN* — LA MOITIÉ QUI MANQUAIT, ET ELLE MANQUAIT TOUTE SEULE ═════════╗
	# ║ Tout ce qui précède mesure la MÉCANIQUE du chiffre (pool, texte, couleur, origine, montée,   ║
	# ║ extinction) et RIEN n'exigeait qu'il devienne une IMAGE. La sous-section (a) ne lit           ║
	# ║ `node.visible` que dans le sens NÉGATIF (« aucun événement → aucune étiquette visible ») ;    ║
	# ║ la section 5 « LES PIXELS » ne pouvait pas rattraper le coup puisqu'elle MASQUE tous les      ║
	# ║ enfants du HUD sauf le réticule.                                                              ║
	# ║ MESURÉ (sabotage X8) : `node.visible = true` retiré de `_spawn_damage_number` laissait la     ║
	# ║ sonde à 165/0 headless ET 171/0 fenêtrée — TOUT VERT — alors que le joueur ne voyait plus UN  ║
	# ║ SEUL chiffre. C'est la demande littérale de Hakim (« les dégâts en live ») gardée par rien.   ║
	# ║ C'est la leçon du §8.151.4ter déplacée d'un cran : là, le PINCEAU décidait et la sonde        ║
	# ║ récitait ; ici, la sonde mesure un ÉTAT que rien n'oblige à devenir une image.                ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	_ok("UNE touche confirmee -> l'etiquette est VISIBLE (pas seulement « en vol »)",
		first != null and first.visible, "visible = %s" % (str(first.visible) if first else "<rien>"))
	_ok("UNE touche confirmee -> son alpha n'est pas nul (un chiffre transparent n'existe pas)",
		first != null and first.modulate.a > 0.0,
		"alpha = %.3f" % (first.modulate.a if first else 0.0))
	_ok("UNE touche confirmee -> le HUD qui la porte est lui-meme visible", duel._hud.visible,
		"_hud.visible = %s" % duel._hud.visible)

	# --- c) RAFALE : trois touches -> trois chiffres, decales pour la lisibilite -----------------
	_clear_damage(duel)
	for d in [5, 5, 5]:
		duel._on_duel_event(_hit_event(duel, d, 60))
	_ok("RAFALE : 3 touches confirmees -> 3 chiffres (un par projectile)",
		duel._damage_live.size() == 3, "%d chiffres" % duel._damage_live.size())
	var jitters := {}
	for entry: Dictionary in duel._damage_live:
		jitters[snappedf(float(entry["jitter"]), 0.001)] = true
	_ok("RAFALE : les 3 chiffres sont decales les uns des autres (lisibilite)",
		jitters.size() == 3, "%d decalages distincts" % jitters.size())

	# --- d) COUP FATAL -> ROUGE -----------------------------------------------------------------
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 30, 0))
	var fatal: Label = duel._damage_live[0]["node"] if duel._damage_live.size() > 0 else null
	_ok("COUP FATAL (hp = 0 dans l'evenement) : le chiffre est ROUGE",
		fatal != null and fatal.get_theme_color("font_color") == duel.COL_DANGER)

	# --- e) DEGATS SUBIS et TIR REFUSE : jamais de chiffre ---------------------------------------
	_clear_damage(duel)
	duel._on_duel_event({"type": "hit", "slot": duel._my_slot, "by": 3 - duel._my_slot,
		"kind": "bullet", "damage": 25, "hp": 75})
	_ok("DEGATS SUBIS : aucun chiffre flottant, aucun hitmarker",
		duel._damage_live.is_empty() and duel._hitmarker <= 0.0,
		"%d chiffres, hitmarker %.2f" % [duel._damage_live.size(), duel._hitmarker])
	_clear_damage(duel)
	duel._pred_stance = "down"          # un refus garanti (« accroupi »)
	duel._fire_queued = false
	duel._queue_fire()
	_ok("TIR REFUSE : aucun chiffre flottant", duel._damage_live.is_empty(),
		"%d chiffres" % duel._damage_live.size())
	duel._pred_stance = "up"

	# --- f) LE POOL NE GROSSIT JAMAIS : 40 touches d'affilee -------------------------------------
	_clear_damage(duel)
	var pool_before: int = duel._damage_pool.size()
	for i in range(40):
		duel._on_duel_event(_hit_event(duel, 4, 50))
	_ok("40 touches : le pool n'a pas grossi d'une seule etiquette (aucun Label.new)",
		duel._damage_pool.size() == pool_before,
		"%d -> %d" % [pool_before, duel._damage_pool.size()])
	_ok("40 touches : le nombre de chiffres en vol reste borne par le pool",
		duel._damage_live.size() <= pool_before, "%d en vol" % duel._damage_live.size())
	# ⚠️⚠️ L'INVARIANT DU POOL — le contrôle qui a démasqué un vrai défaut pendant cette étape.
	# La première écriture prenait `_damage_pool[_damage_live.size()]` comme étiquette libre : dès
	# qu'un chiffre du MILIEU expirait, l'index retombait sur une étiquette ENCORE EN VOL et DEUX
	# entrées vivantes partageaient un Label — l'expiration de la première éteignait le chiffre de
	# la seconde en plein écran. Aucun compte total ne le voyait : il faut vérifier l'UNICITÉ.
	var used := {}
	var doubles := 0
	for entry: Dictionary in duel._damage_live:
		var id: int = (entry["node"] as Label).get_instance_id()
		if used.has(id):
			doubles += 1
		used[id] = true
	_ok("INVARIANT DU POOL : jamais deux chiffres vivants sur la MEME etiquette", doubles == 0,
		"%d partages" % doubles)
	_ok("INVARIANT DU POOL : libres + en vol == taille du pool",
		duel._damage_free.size() + duel._damage_live.size() == pool_before,
		"%d libres + %d en vol pour %d places"
		% [duel._damage_free.size(), duel._damage_live.size(), pool_before])
	# Le cas qui faisait tomber la premiere ecriture : on laisse expirer QUELQUES chiffres du
	# milieu, puis on en fait naitre d'autres — l'unicite doit tenir.
	for i in range(8):
		duel._clock += DAMAGE_STAGGER
		duel._step_damage_numbers()
		duel._on_duel_event(_hit_event(duel, 6, 44))
	var used2 := {}
	var doubles2 := 0
	for entry: Dictionary in duel._damage_live:
		var id2: int = (entry["node"] as Label).get_instance_id()
		if used2.has(id2):
			doubles2 += 1
		used2[id2] = true
	_ok("INVARIANT DU POOL : tient aussi apres des expirations ENTRELACEES", doubles2 == 0,
		"%d partages sur %d chiffres" % [doubles2, duel._damage_live.size()])

	# --- g) LE TEMPS DE SCENE PILOTE LA VIE DU CHIFFRE ------------------------------------------
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 12, 80))
	var aging: Label = duel._damage_live[0]["node"]
	var born: Vector2 = aging.position
	duel._clock += duel.DAMAGE_RISE_S * 0.5
	duel._step_damage_numbers()
	var risen: Vector2 = duel._damage_live[0]["node"].position
	_ok("le chiffre MONTE (pilote par le temps de SCENE, pas par l'horloge murale)",
		risen.y < born.y - 1.0, "y %.1f -> %.1f" % [born.y, risen.y])
	_ok("le chiffre FOND en montant", duel._damage_live[0]["node"].modulate.a <= 1.0)
	duel._clock += duel.DAMAGE_RISE_S
	duel._step_damage_numbers()
	_ok("apres ~0,6 s le chiffre a disparu", duel._damage_live.is_empty(),
		"%d en vol" % duel._damage_live.size())
	# … ET L'ÉTIQUETTE EST REDEVENUE INVISIBLE. « Il n'est plus en vol » est un fait de liste ; « il
	# n'est plus à l'écran » est un fait d'image, et c'est celui que le joueur vit. Sans ce contrôle,
	# rendre l'étiquette au pool SANS l'éteindre laisserait un chiffre figé sur la silhouette.
	_ok("… et son etiquette est REDEVENUE invisible (aucun chiffre fige a l'ecran)",
		not aging.visible, "visible = %s" % aging.visible)

	# --- h) ⚠️⚠️ D'OÙ PART LE CHIFFRE : DE LA SILHOUETTE ADVERSE, ET DE NULLE PART AILLEURS -------
	# ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
	# ║ 🩸 SANS CETTE SOUS-SECTION, LA PROMESSE DU §4bis.3 N'ÉTAIT PAS VÉRIFIABLE. `entry["from"]`    ║
	# ║ n'était lu qu'à travers le contrôle « le chiffre MONTE » — que satisfait tout aussi bien une  ║
	# ║ origine FIXE : un chiffre né au centre de l'écran monte exactement pareil. MESURÉ par la      ║
	# ║ boucle de critique : le retour de `_enemy_screen_point()` remplacé par le centre de l'écran   ║
	# ║ laissait la sonde à 84 PASS / 0 FAIL.                                                         ║
	# ║ On garde donc les deux moitiés : la DÉPENDANCE (l'origine suit la position ET la posture de   ║
	# ║ l'adversaire) et la VALEUR (elle coïncide avec la projection DIRECTE, par la caméra, du point ║
	# ║ d'arène où l'adversaire se tient — une arithmétique qui ne passe ni par `yaw_to`/`pitch_to`   ║
	# ║ ni par `project_aim` : ce n'est donc pas une tautologie).                                     ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
	var center: Vector2 = duel.size * 0.5
	var camera: Camera3D = duel._world._camera
	_ok("ORIGINE : repos complet avant de mesurer (le roulis fait bouger tout point hors centre)",
		await _settle(duel), "roulis %.6f deg, secousse %s"
		% [duel._cam_roll.value, str(duel._shake_px)])
	var origins: Array = []
	var oracles: Array = []
	for pos in range(Geo.POSITIONS):
		_push_enemy(duel, pos, "up")
		_clear_damage(duel)
		duel._on_duel_event(_hit_event(duel, 9, 70))
		origins.append(duel._damage_live[0]["from"] as Vector2)
		# L'ORACLE INDÉPENDANT : le point d'arène de l'adversaire, projeté par la CAMÉRA elle-même.
		# L'ordonnée est libre — caméra sans site ni roulis, l'abscisse écran n'en dépend pas.
		oracles.append(camera.unproject_position(Vector3(Geo.position_x(pos),
			Geo.eye_position(duel._pred_pos, duel._pred_stance).y, Geo.far_soldier_z())).x)
	var rising := true
	var falling := true
	var closest := 9999.0
	for i in range(1, origins.size()):
		var step: float = (origins[i] as Vector2).x - (origins[i - 1] as Vector2).x
		rising = rising and step > 0.0
		falling = falling and step < 0.0
		closest = minf(closest, absf(step))
	_ok("ORIGINE : le chiffre SUIT l'adversaire — 5 positions, 5 abscisses ordonnees",
		rising or falling, "abscisses %s" % str(origins.map(func(v): return roundf(v.x))))
	_ok("ORIGINE : le controle est PORTEUR — chaque pas de cote deplace franchement l'origine",
		closest > PIXEL_TOL * 4.0, "plus petit ecart entre deux positions : %.1f px" % closest)
	_ok("ORIGINE : aux extremes, elle n'est PAS au centre de l'ecran",
		absf((origins[0] as Vector2).x - center.x) > OFFAXIS_MIN_DIVERGENCE
			and absf((origins[4] as Vector2).x - center.x) > OFFAXIS_MIN_DIVERGENCE,
		"ecarts au centre : %.1f px et %.1f px"
		% [(origins[0] as Vector2).x - center.x, (origins[4] as Vector2).x - center.x])
	var worst := 0.0
	for i in range(origins.size()):
		worst = maxf(worst, absf((origins[i] as Vector2).x - float(oracles[i])))
	_ok("ORIGINE : elle coincide avec la SILHOUETTE projetee par la camera (oracle independant)",
		worst < PIXEL_TOL * 2.0, "ecart maximal %.3f px sur 5 positions" % worst)
	# LA POSTURE AUSSI : accroupi, l'adversaire ne montre plus la même bande — le chiffre naît plus
	# bas. Une origine fixe rendrait deux fois la même ordonnée.
	_push_enemy(duel, 2, "up")
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 9, 70))
	var standing: Vector2 = duel._damage_live[0]["from"]
	_push_enemy(duel, 2, "down")
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 9, 70))
	var crouched: Vector2 = duel._damage_live[0]["from"]
	_ok("ORIGINE : elle suit la POSTURE (debout / accroupi = deux ordonnees)",
		absf(standing.y - crouched.y) > PIXEL_TOL * 4.0,
		"debout y=%.1f / accroupi y=%.1f" % [standing.y, crouched.y])
	# ET ELLE ENCAISSE LA SECOUSSE COMME LE RÉTICULE : monde, croix et chiffres, LE MÊME vecteur.
	_push_enemy(duel, 3, "up")
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 9, 70))
	var calm: Vector2 = duel._damage_live[0]["from"]
	duel._apply_tuning({"feel_shake": 2.0})
	duel._world.play_explosion(Geo.position_x(duel._pred_pos), true)
	duel._world.play_explosion(Geo.position_x(duel._pred_pos), true)
	var shaking: bool = await _shake_until_visible(duel)
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 9, 70))
	var shaken: Vector2 = duel._damage_live[0]["from"]
	_ok("ORIGINE : le controle de secousse est PORTEUR", shaking,
		"secousse %s" % str(duel._shake_px))
	_ok("ORIGINE : elle encaisse la MEME secousse que le monde et la croix",
		(shaken - calm - duel._shake_px).length() < EXACT_TOL,
		"ecart %s" % str(shaken - calm - duel._shake_px))
	# Retour au repos : un résidu de secousse fausserait tout ce qui suit.
	duel._apply_tuning({"feel_shake": 1.0})
	_ok("ORIGINE : retour au repos complet", await _settle(duel),
		"secousse %s" % str(duel._shake_px))
	_push_enemy(duel, 2, "up")


# =================================================================================================
# 3bis. LES PIXELS DU CHIFFRE — « LES DÉGÂTS EN LIVE » RELUS À L'ÉCRAN
# =================================================================================================
# ╔═ POURQUOI ELLE NE PEUT PAS VIVRE DANS LA SECTION 5 ═══════════════════════════════════════════╗
# ║ La section 5 « LES PIXELS » commence par MASQUER tous les enfants du HUD sauf le réticule :    ║
# ║ elle ne verra jamais un chiffre de dégâts, par construction. C'est cette asymétrie entre les   ║
# ║ deux ajouts du §4bis qui a laissé le trou — le réticule était gardé côté image, le chiffre     ║
# ║ non. On mesure donc ICI, AVANT le masquage, et sur la MÊME méthode : une couleur lue dans      ║
# ║ `duel`, une boîte lue sur le nœud, une échelle DÉDUITE de l'image. Aucune constante recopiée.  ║
# ║ ⚠️ Sous `--headless` il n'y a rien à relire, et la section le DIT au lieu de compter des        ║
# ║ contrôles vides (règle de `probe_trench_grenade`, §8.151.3). Le total headless reste donc      ║
# ║ stable et ces contrôles s'ajoutent quand la sonde est relancée FENÊTRÉE.                       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_damage_pixels(duel) -> void:
	if DisplayServer.get_name() == "headless":
		print("\n=== 3bis. LES PIXELS DU CHIFFRE — NON APPLICABLE (affichage : %s) ==="
			% DisplayServer.get_name())
		print("  Pilote muet : aucun pixel a relire. La section 3 garde l'ETAT (etiquette VISIBLE,")
		print("  alpha non nul, HUD visible) ; CETTE section-ci relit l'IMAGE. Pour l'avoir :")
		print("    & <godot_console> --path frontend res://tools/probe_trench_hud.tscn")
		return
	_section("3bis. LES PIXELS DU CHIFFRE — « les degats en live » RELUS a l'ecran (pilote reel)")
	# L'ADVERSAIRE HORS AXE : le chiffre naît sur SA silhouette, donc loin de la croix de visée. Ce
	# n'est pas un arrangement de sonde — c'est la promesse du §4bis.3 elle-même — mais ça garantit
	# aussi que les pixels comptés sont ceux du CHIFFRE et pas ceux du hitmarker (sentinelle
	# explicite ci-dessous). Repos complet d'abord : un résidu de secousse déplacerait la boîte
	# entre la lecture du nœud et la capture.
	await _aim_at(duel, 0.0)
	_push_enemy(duel, 4, "up")
	_ok("PIXELS CHIFFRE : repos complet avant de mesurer", await _settle(duel),
		"secousse %s, roulis %.6f deg" % [str(duel._shake_px), duel._cam_roll.value])
	for case: Array in [["OR", 88, 42, duel.COL_GOLD], ["ROUGE", 64, 0, duel.COL_DANGER]]:
		var tag: String = case[0]
		var damage: int = case[1]
		var victim_hp: int = case[2]
		var want: Color = case[3]
		_clear_damage(duel)
		await get_tree().process_frame
		await get_tree().process_frame
		var before: Image = _screen()
		duel._on_duel_event(_hit_event(duel, damage, victim_hp))
		var node: Label = duel._damage_live[0]["node"] if duel._damage_live.size() > 0 else null
		await get_tree().process_frame
		await get_tree().process_frame
		var after: Image = _screen()
		if before == null or after == null or node == null:
			_ok("PIXELS CHIFFRE %s : le viewport a RENDU quelque chose" % tag, false,
				"image=%s / etiquette=%s" % [str(after != null), str(node != null)])
			continue
		var scale: float = float(after.get_width()) / duel.size.x
		var box := Rect2i(Vector2i((node.position * scale).floor()),
			Vector2i((node.size * scale).ceil()))
		var cross := Rect2i(Vector2i((duel._reticle.position * scale).floor()),
			Vector2i((duel._reticle.size * scale).ceil()))
		_ok("PIXELS %s : SENTINELLE — la boite du chiffre est DANS l'image et HORS du reticule"
			% tag,
			box.position.x >= 0 and box.position.y >= 0 and box.end.x <= after.get_width()
				and box.end.y <= after.get_height() and not box.intersects(cross),
			"boite %s / croix %s / image %dx%d"
			% [str(box), str(cross), after.get_width(), after.get_height()])
		var noise := _count_color(before, box, want)
		_ok("PIXELS %s : SENTINELLE — AVANT l'evenement, la boite est VIDE de cette couleur" % tag,
			noise == 0, "%d pixel(s) de fond" % noise)
		var painted := _count_color(after, box, want)
		_ok("PIXELS %s : la touche confirmee PEINT le chiffre A L'ECRAN" % tag, painted > 0,
			"%d pixel(s) « %s » dans la boite (fond : %d)" % [painted, str(want), noise])
		# … ET IL S'EFFACE POUR DE BON : le temps le retire de l'IMAGE, pas seulement de la liste.
		_clear_damage(duel)
		await get_tree().process_frame
		await get_tree().process_frame
		var faded: Image = _screen()
		var left := _count_color(faded, box, want) if faded != null else -1
		_ok("PIXELS %s : apres ~0,6 s la boite est REDEVENUE vide (rien ne reste peint)" % tag,
			left == 0, "%d pixel(s)" % left)
	_clear_damage(duel)
	_push_enemy(duel, 2, "up")


func _screen() -> Image:
	var texture := get_viewport().get_texture()
	return texture.get_image() if texture != null else null


# LE COMPTE DES PIXELS D'UNE COULEUR DANS UNE BOÎTE. Même tolérance que `_read_painted_row` (somme
# des écarts RVB), et la couleur vient de `duel`, jamais d'un hex recopié ici.
func _count_color(image: Image, box: Rect2i, want: Color, tol := 0.25) -> int:
	var n := 0
	for y in range(maxi(0, box.position.y), mini(image.get_height(), box.end.y)):
		for x in range(maxi(0, box.position.x), mini(image.get_width(), box.end.x)):
			var here: Color = image.get_pixel(x, y)
			if absf(here.r - want.r) + absf(here.g - want.g) + absf(here.b - want.b) < tol:
				n += 1
	return n


# =================================================================================================
# 4. HITMARKER ENRICHI (§4bis.2)
# =================================================================================================
func _section_hitmarker(duel) -> void:
	_section("4. HITMARKER — croix de KILL rouge, echelle selon les degats")
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 8, 70))
	var light: float = duel._hitmarker_scale
	_ok("touche ordinaire : hitmarker BLANC/OR", duel._hitmarker_color().r < duel.COL_DANGER.r
		or duel._hitmarker_color().g > 0.5, "couleur %s" % str(duel._hitmarker_color()))
	_ok("touche ordinaire : ce n'est pas un kill", not duel._hitmarker_kill)

	duel._on_duel_event(_hit_event(duel, 30, 40))
	var heavy: float = duel._hitmarker_scale
	_ok("ECHELLE : un coup a 30 degats marque plus grand qu'un coup a 8", heavy > light,
		"%.3f contre %.3f" % [heavy, light])
	# L'échelle est rapportée au `hp_max` DU REGISTRE : on le change, elle doit suivre.
	duel._rules["hp_max"] = 200
	duel._on_duel_event(_hit_event(duel, 30, 40))
	_ok("ECHELLE : elle est rapportee au hp_max du REGISTRE (200 -> plus petite)",
		duel._hitmarker_scale < heavy, "%.3f contre %.3f" % [duel._hitmarker_scale, heavy])
	duel._rules["hp_max"] = 100

	duel._on_duel_event(_hit_event(duel, 30, 0))
	_ok("COUP FATAL : la croix passe au ROUGE", duel._hitmarker_kill
		and duel._hitmarker_color().is_equal_approx(
			Color(duel.COL_DANGER.r, duel.COL_DANGER.g, duel.COL_DANGER.b, 1.0)),
		"couleur %s" % str(duel._hitmarker_color()))

	# --- ⚠️⚠️ LE MARQUEUR S'ÉTEINT TOUT SEUL, ET C'EST LE TEMPS QUI L'ÉTEINT ---------------------
	# ╔═════════════════════════════════════════════════════════════════════════════════════════════╗
	# ║ 🩸 LE DÉFAUT QUE CETTE SONDE NE POUVAIT PAS VOIR. Supprimer la décroissance de production     ║
	# ║ (`_hitmarker = maxf(0, _hitmarker - delta)`, dans `_decay`) laisse la croix de touche PEINTE  ║
	# ║ indéfiniment après la première touche confirmée : un « je touche » permanent. La sonde restait ║
	# ║ verte parce qu'elle remettait `_hitmarker` à zéro à la main dans `_clear_damage` — elle       ║
	# ║ mesurait un état qu'elle avait posé. La règle que la section 3 s'impose pour les chiffres     ║
	# ║ (« on vide par le chemin de production, JAMAIS à la main ») s'applique désormais ici aussi.   ║
	# ║ ET ON MESURE CE QUI EST PEINT : la présence des DIAGONALES dans la liste de peinture, pas la  ║
	# ║ valeur d'une variable — un marqueur éteint est un marqueur qui a disparu du dessin.           ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 20, 60))
	var lit := _decode_cross(duel)
	_ok("ALLUME : la touche confirmee PEINT les quatre diagonales du marqueur",
		int(lit["marks"]) == 4, "%d diagonale(s) peinte(s)" % int(lit["marks"]))
	# À MI-VIE le marqueur est encore là : sans ce point, « il s'éteint » serait vrai d'un marqueur
	# qui ne s'allumerait jamais, et les deux contrôles diraient la même chose.
	for i in range(int(floor(duel.HITMARKER_TIME * 0.5 * 60.0))):
		duel._decay(1.0 / 60.0)
	var half := _decode_cross(duel)
	_ok("A MI-VIE : le marqueur est encore peint, et il a PALI (le fondu est reel)",
		int(half["marks"]) == 4 and (half["mark_color"] as Color).a < (lit["mark_color"] as Color).a,
		"alpha %.3f -> %.3f" % [(lit["mark_color"] as Color).a, (half["mark_color"] as Color).a])
	# … et le TEMPS l'éteint, par `_decay` — le chemin de production, aucune main de la sonde.
	for i in range(int(ceil(duel.HITMARKER_TIME * 60.0)) + 2):
		duel._decay(1.0 / 60.0)
	var gone := _decode_cross(duel)
	_ok("ETEINT PAR LE TEMPS : plus une seule diagonale peinte (aucun « je touche » eternel)",
		int(gone["marks"]) == 0 and duel._hitmarker == 0.0,
		"%d diagonale(s), _hitmarker = %.4f" % [int(gone["marks"]), duel._hitmarker])
	_ok("ETEINT : la croix de visee, elle, est TOUJOURS peinte (rien d'autre n'a disparu)",
		int(gone["arms"]) == 4 and int(gone["dots"]) == 1,
		"%d traits + %d point" % [int(gone["arms"]), int(gone["dots"])])


# =================================================================================================
# 5. LES PIXELS — LA CROIX TELLE QUE L'ÉCRAN LA MONTRE (pilote réel uniquement)
# =================================================================================================
# ╔═ POURQUOI CETTE SECTION EXISTE, ET POURQUOI ELLE NE PEUT PAS ÊTRE LA SEULE ═══════════════════╗
# ║ Les sections 1 et 1quater tiennent la chaîne « pinceau branché → pinceau sans rien à lui →     ║
# ║ liste mesurée ». Celle-ci la ferme par l'AUTRE bout, quand un vrai pilote d'affichage est là : ║
# ║ on relit les PIXELS de l'écran et on y remesure l'écartement de la croix, à l'échelle près —   ║
# ║ échelle DÉDUITE de l'image (`largeur_image / largeur_du_Control`), jamais recopiée.            ║
# ║ ⚠️ Sous `--headless` — le mode du harnais — il n'y a rien à relire, et la section le DIT au     ║
# ║ lieu de compter des contrôles vides : c'est la règle posée par `probe_trench_grenade`          ║
# ║ (§8.151.3, « la garde est AVANT tout `get_image()` »). Le total headless reste donc stable, et ║
# ║ les contrôles PIXELS s'ajoutent quand la sonde est relancée FENÊTRÉE.                          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_pixels(duel) -> void:
	if DisplayServer.get_name() == "headless":
		print("\n=== 5. LES PIXELS — NON APPLICABLE (affichage : %s) ===" % DisplayServer.get_name())
		print("  Pilote muet : aucun pixel a relire. La chaine reste gardee par les sections 1")
		print("  (liste peinte mesuree) et 1quater (audit du pinceau). Pour CETTE section :")
		print("    & <godot_console> --path frontend res://tools/probe_trench_hud.tscn")
		return
	_section("5. LES PIXELS — l'ecartement RELU a l'ecran (pilote reel)")
	# On ISOLE la croix : tout le reste du HUD est masqué, le monde et l'habillage sont figés.
	for child in duel._hud.get_children():
		if child != duel._reticle and child is CanvasItem:
			(child as CanvasItem).visible = false
	duel._world.set_reduced_motion(true)
	duel._ambient.set_reduced_motion(true)
	await _aim_at(duel, 0.0)
	var cases := [["vipere", _production_weapons()], ["essai_b", _fake_weapons()],
		["essai_c", _fake_weapons()]]
	for case: Array in cases:
		var weapon_id: String = case[0]
		duel._rules = {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
			"weapons": case[1]}
		_push(duel, weapon_id, 99)
		duel._process(1.0 / 60.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var texture := get_viewport().get_texture()
		var image: Image = texture.get_image() if texture != null else null
		if image == null:
			_ok("%s : le viewport a RENDU quelque chose" % weapon_id, false, "aucune image")
			continue
		var read := _read_painted_row(image, duel)
		var scale: float = float(image.get_width()) / duel.size.x
		var expected: float = _painted_spread(duel) * scale
		_ok("PIXELS %s : la croix relue a l'ecran a bien 2 traits + 1 point sur sa ligne"
			% weapon_id, int(read["runs"]) == 3,
			"%d segment(s) d'accent sur la ligne du centre" % int(read["runs"]))
		_ok("PIXELS %s : l'ecartement RELU est celui de la liste peinte" % weapon_id,
			int(read["runs"]) == 3 and absf(float(read["spread"]) - expected) < PIXEL_TOL * 3.0,
			"relu %.2f px / liste %.2f px (echelle image %.3f)"
			% [float(read["spread"]), expected, scale])


# LA LECTURE D'UNE LIGNE DE PIXELS : les segments d'accent rencontrés sur la rangée qui passe par le
# centre de la croix, bornés à la boîte du réticule. On en attend TROIS — trait gauche, point
# central, trait droit — et l'écartement est la demi-distance entre les bords intérieurs des deux
# traits. Aucune constante de production n'est recopiée : la couleur vient de `COL_ACCENT`, la
# boîte du nœud, l'échelle de l'image.
func _read_painted_row(image: Image, duel) -> Dictionary:
	var scale: float = float(image.get_width()) / duel.size.x
	var center: Vector2 = _reticle_center(duel) * scale
	var row: int = clampi(int(round(center.y)), 0, image.get_height() - 1)
	var x_from: int = clampi(int(floor(duel._reticle.position.x * scale)), 0, image.get_width() - 1)
	var x_to: int = clampi(int(ceil((duel._reticle.position.x + duel._reticle.size.x) * scale)),
		0, image.get_width() - 1)
	var accent: Color = duel.COL_ACCENT
	var runs: Array = []
	var start := -1
	for x in range(x_from, x_to + 1):
		var here: Color = image.get_pixel(x, row)
		var hit: bool = absf(here.r - accent.r) + absf(here.g - accent.g) \
			+ absf(here.b - accent.b) < 0.25
		if hit and start < 0:
			start = x
		elif not hit and start >= 0:
			runs.append([start, x - 1])
			start = -1
	if start >= 0:
		runs.append([start, x_to])
	var spread := -1.0
	if runs.size() >= 2:
		spread = (float((runs[runs.size() - 1] as Array)[0]) - float((runs[0] as Array)[1])) * 0.5
	return {"runs": runs.size(), "spread": spread}


# =================================================================================================
# FIXTURES
# =================================================================================================
# Le registre de PRODUCTION, recopié ici comme fixture de comparaison — c'est le rôle légitime d'un
# double de test (le CODE, lui, n'a le droit de connaître que ce que `trench_init` lui envoie).
func _production_weapons() -> Array:
	return [
		{"id": "vipere", "burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 18, "flight_ticks": 1,
			"laser_lead_ticks": 0, "dispersion_deg": 0.30, "mag_size": 8, "reload_ticks": 30},
		{"id": "frelon", "burst": 3, "burst_gap_ticks": 2, "cooldown_ticks": 24, "flight_ticks": 1,
			"laser_lead_ticks": 0, "dispersion_deg": 0.85, "mag_size": 24, "reload_ticks": 40},
		{"id": "chacal", "burst": 2, "burst_gap_ticks": 2, "cooldown_ticks": 16, "flight_ticks": 1,
			"laser_lead_ticks": 0, "dispersion_deg": 0.45, "mag_size": 20, "reload_ticks": 44},
		{"id": "condor", "burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 50, "flight_ticks": 1,
			"laser_lead_ticks": 10, "dispersion_deg": 0.0, "mag_size": 4, "reload_ticks": 50},
	]


# LE DOUBLE FAUSSÉ — ids ET dispersions inventés. Aucune de ces valeurs n'existe dans le dépôt :
# un `0.30` recopié en dur ne peut coïncider avec AUCUNE d'elles.
func _fake_weapons() -> Array:
	return [
		{"id": "essai_a", "burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 18, "flight_ticks": 1,
			"laser_lead_ticks": 0, "dispersion_deg": 0.17, "mag_size": 8, "reload_ticks": 30},
		{"id": "essai_b", "burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 18, "flight_ticks": 1,
			"laser_lead_ticks": 0, "dispersion_deg": 0.63, "mag_size": 8, "reload_ticks": 30},
		{"id": "essai_c", "burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 18, "flight_ticks": 1,
			"laser_lead_ticks": 0, "dispersion_deg": 1.21, "mag_size": 8, "reload_ticks": 30},
		{"id": "essai_zero", "burst": 1, "burst_gap_ticks": 0, "cooldown_ticks": 18,
			"flight_ticks": 1, "laser_lead_ticks": 0, "dispersion_deg": 0.0, "mag_size": 8,
			"reload_ticks": 30},
	]


func _hit_event(duel, damage: int, victim_hp: int) -> Dictionary:
	return {"type": "hit", "slot": 3 - duel._my_slot, "by": duel._my_slot, "kind": "bullet",
		"damage": damage, "hp": victim_hp}


# 🎯 §8.153 — le MEME evenement, mais la balle a porte a la tete. ⚠️ Le champ est AJOUTE, pas
# substitue : `_hit_event` reste sans `headshot`, et c est ce qui prouve que le drapeau absent
# vaut bien « pas un head shot » sur les ~40 controles de la section 3 qui l ignorent.
func _hit_event_head(duel, damage: int, victim_hp: int) -> Dictionary:
	var e := _hit_event(duel, damage, victim_hp)
	e["headshot"] = true
	return e


# ⚠️ ON VIDE PAR LE CHEMIN DE PRODUCTION (le temps passe, les chiffres expirent) et JAMAIS en
# touchant `_damage_live` à la main : la sonde reproduirait alors l'invariant du pool de son côté,
# et une future divergence entre les deux passerait inaperçue. Ici, si l'expiration oubliait de
# rendre l'étiquette au pool, le contrôle d'invariant plus bas le dirait.
#
# 🩸 ET LA RÈGLE NE VALAIT PAS POUR LE HITMARKER — c'était le défaut. Cette fonction remettait
# `_hitmarker = 0.0` À LA MAIN. Elle mesurait donc un état qu'elle avait elle-même posé : supprimer
# la décroissance de production (`_hitmarker = maxf(0, _hitmarker - delta)` dans `_decay`) laissait
# la croix de touche allumée POUR TOUJOURS après la première touche — un « je touche » permanent,
# le mensonge de HUD le plus direct qui soit — et la sonde restait à 84 PASS / 0 FAIL. On passe
# donc, ici aussi, par `_decay` : le temps éteint le marqueur, ou personne ne l'éteint.
func _clear_damage(duel) -> void:
	var span: float = maxf(duel.DAMAGE_RISE_S, duel.HITMARKER_TIME) + 0.1
	for i in range(int(ceil(span * 60.0))):
		duel._clock += 1.0 / 60.0
		duel._decay(1.0 / 60.0)
		duel._step_damage_numbers()


func _mouse(pressed: bool) -> void:
	_mouse_button(MOUSE_BUTTON_LEFT, pressed)


# ⚠️ LE BOUTON DROIT ET LA TOUCHE `G` SONT SONDÉS PAR LA PRODUCTION, PAS REÇUS EN ÉVÉNEMENT :
# `_update_grenade_aim` appelle `Input.is_mouse_button_pressed()` / `Input.is_key_pressed()`. La
# sonde doit donc pousser un VRAI état de plateforme, pas appeler une méthode avec un booléen — sans
# quoi elle mesurerait un chemin que le jeu n'emprunte pas. Vérifié sous `--headless` : le masque de
# boutons ET l'état clavier du singleton `Input` répondent tous les deux à `parse_input_event`.
func _mouse_button(button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


# LE GESTE DE GRENADE EN ENTIER, par le chemin de PRODUCTION : on maintient (le décalque s'arme), on
# relâche (le lancer part). Ce que la sonde lit, ce sont les TROIS choses que le joueur voit ou paie
# — le décalque au sol (`_world._aim_decal`), la pose de lancer du viewmodel, et la charge utile
# `_throw_queued` réellement mise en file. Elle n'écrit dans AUCUN état de grenade.
func _grenade_gesture(duel, by_key := false) -> Dictionary:
	# ⚠️⚠️ §8.152 (lot 3D-H) — LE CLIC DROIT N'ARME PLUS LA GRENADE : il sert à la VISÉE.
	# La grenade garde `KEY_G`, qui était déjà une liaison complète. Ce geste-ci passe donc
	# TOUJOURS par la touche, quel que soit `by_key` — le paramètre ne distingue plus deux
	# boutons mais deux CHEMINS de code, et il est conservé pour ne pas réécrire les appels.
	# 🩸 Sans ce correctif, le geste n'armait plus rien : trois contrôles de cette section
	# tombaient — et la sonde annonçait quand même TOUT VERT, faute de compter ce qu'elle joue.
	_key(KEY_G, true)
	duel._update_grenade_aim(1.0 / 60.0)
	var out := {
		"aimed": duel._aiming_grenade,
		"decal": duel._world._aim_decal != null and duel._world._aim_decal.visible,
		# ⚠️ On lisait `_viewmodel._grenade_aim`, un champ PRIVÉ de la vue — une sonde qui
		# plonge dans les entrailles d'un affichage pour apprendre un fait de JEU. On lit
		# désormais ce que le duel POUSSE à la vue : ça éprouve la plomberie, et ça survit au
		# remplacement du viewmodel.
		"pose": bool((duel._rig_state() as Dictionary).get("low_ready", false)),
	}
	_key(KEY_G, false)
	duel._update_grenade_aim(1.0 / 60.0)
	out["thrown"] = duel._throw_queued.duplicate()
	duel._throw_queued = {}                # la file de SORTIE se vide comme à la section 2
	return out


func _gesture_detail(g: Dictionary) -> String:
	return "vise=%s decalque=%s pose=%s file=%s" \
		% [g["aimed"], g["decal"], g["pose"], str(g["thrown"])]


func _push(duel, weapon_id: String, ammo: int) -> void:
	_push_phase(duel, weapon_id, ammo, "playing")


func _player_row(slot: int, pos: int, stance: String, weapon: String, ammo: int) -> Dictionary:
	return {"slot": slot, "pos": pos, "stance": stance, "hp": 100, "weapon": weapon,
		"hits_total": 0, "grenades": 2, "ammo": ammo, "bandages": 1, "aiming": true,
		"hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
		"bandage_until_tick": 0, "disconnected": false}


# LA MÊME FIXTURE, avec la POSITION et la POSTURE de l'ADVERSAIRE en paramètres — et le tampon
# d'états VIDÉ D'ABORD. ⚠️ Ce n'est pas une commodité : `_render_pair` interpole entre deux états
# DATÉS À L'HORLOGE MURALE (`_now()`), or une sonde pousse les siens dans la même milliseconde et
# `target = now − RENDER_DELAY` retombe alors sur le PLUS ANCIEN du tampon — la position rendue ne
# bougerait jamais. Avec un seul état, `_refresh_view` la lit telle quelle (`lerpf(p, p, 1)`) :
# c'est bien le chemin de production qui pose `_last_seen_enemy_pos`, sans la loterie du temps réel.
func _push_enemy(duel, pos: int, stance: String) -> void:
	duel._buffer.clear()
	var mine: int = duel._my_slot
	duel._on_state({"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [_player_row(mine, 2, "up", "frelon", 40),
			_player_row(3 - mine, pos, stance, _other_weapon(duel, "frelon"), 8)],
		"projectiles": [], "events": []})
	duel._process(1.0 / 60.0)


# ╔═ 🩸 POURQUOI L'ADVERSAIRE NE PORTE PLUS LA MÊME ARME QUE MOI ═════════════════════════════════╗
# ║ Ces deux fabriques posaient `weapon_id` sur les DEUX slots (et « frelon » des deux côtés pour   ║
# ║ `_push_enemy`). « Mon cône » et « son cône » étaient donc le même nombre dans chaque mesure de  ║
# ║ la sonde : `_dispersion_degrees()` pouvait lire l'arme de l'ADVERSAIRE sans qu'un seul des 135  ║
# ║ contrôles ne bouge — MESURÉ, `_player_of(_latest(), 3 - _my_slot)` restait TOUT VERT.           ║
# ║ Les fixtures étaient donc devenues une CONFIGURATION que la production ne rencontre jamais :    ║
# ║ côté serveur l'escalade est PAR TIREUR, les deux joueurs portent régulièrement des armes        ║
# ║ différentes. Toutes les poussées de cette sonde sont désormais DISSYMÉTRIQUES par défaut, et    ║
# ║ la section 1quinquies mesure explicitement à qui appartient le cône peint.                      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# L'ARME DE L'AUTRE : la première du registre INSTALLÉ qui ne soit pas la mienne. AUCUN id en dur —
# la fixture reste dissymétrique que le registre soit celui de production ou le double faussé, et le
# jour où l'un des deux change, elle suit sans qu'on rouvre ce fichier.
func _other_weapon(duel, mine_id: String) -> String:
	for weapon in duel._rules.get("weapons", []):
		var id := str(weapon.get("id", ""))
		if id != "" and id != mine_id:
			return id
	return mine_id


# LA FIXTURE DISSYMÉTRIQUE EXPLICITE : je choisis MON arme ET la sienne. C'est elle qui rend le
# §4bis.1 départageable — `_other_weapon` garantit « pas la même », celle-ci garantit « celles-là
# précisément », y compris le couple où c'est LUI qui porte le cône NUL (la promesse du Condor peinte
# pour l'arme de l'autre : le mensonge exact que le §1.9 interdit).
# ⚠️ Tampon VIDÉ d'abord, même raison que `_push_enemy` : deux états poussés dans la même
# milliseconde font retomber l'interpolation de rendu sur le PLUS ANCIEN.
func _push_pair(duel, weapon_mine: String, weapon_his: String) -> void:
	duel._buffer.clear()
	var mine: int = duel._my_slot
	duel._on_state({"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [_player_row(mine, 2, "up", weapon_mine, 99),
			_player_row(3 - mine, 2, "up", weapon_his, 8)],
		"projectiles": [], "events": []})


# La MÊME fixture, avec la PHASE en paramètre : `trench_sim.step` ne traite les actions offensives
# que pendant `playing`, et c'est cette fenêtre-là que le miroir des refus avait oubliée.
# ⚠️ Le slot du JOUEUR LOCAL reçoit `weapon_id`, l'AUTRE reçoit une arme différente (cf. le pavé
# ci-dessus). `_my_slot` décide : écrire « slot 1 » en dur ici rendrait la fixture muette dès que
# le joueur local est en slot 2, c'est-à-dire une partie sur deux.
func _push_phase(duel, weapon_id: String, ammo: int, phase: String) -> void:
	var mine: int = duel._my_slot
	duel._on_state({"type": "trench_state", "tick": 100, "phase": phase, "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [
			_player_row(mine, 2, "up", weapon_id, ammo),
			_player_row(3 - mine, 2, "up", _other_weapon(duel, weapon_id), 8)],
		"projectiles": [], "events": []})


# =================================================================================================
# 4bis. LE HEAD SHOT (§8.153) — le drapeau vient du SERVEUR, et il ne remultiplie rien
# =================================================================================================
# ╔═ CE QUE CETTE SECTION DOIT INTERDIRE ═════════════════════════════════════════════════════════╗
# ║ 1. qu une touche ORDINAIRE change d apparence — 95 % des tirs, et le §4 les tient deja ;      ║
# ║ 2. que le head shot AJOUTE une cinquieme forme : `_decode_cross` compte les diagonales, et un ║
# ║    marqueur a huit branches ferait passer quatre controles du §4 au rouge ;                   ║
# ║ 3. que le client RE-MULTIPLIE : le serveur envoie deja le montant majore. Un client qui       ║
# ║    referait le calcul afficherait 1,5x le chiffre reellement retire — un mensonge de HUD sur  ║
# ║    un fait de regle, et le genre qu on ne remarque qu en comptant les PV a la main ;          ║
# ║ 4. que la TETE prenne le pas sur la MORT. Un head shot fatal est d abord un mort.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_headshot(duel) -> void:
	_section("4bis. HEAD SHOT — drapeau serveur, croix distincte, aucun recalcul")
	_clear_damage(duel)

	# --- la touche ORDINAIRE, pour reference : c est elle qui ne doit pas bouger ---
	duel._on_duel_event(_hit_event(duel, 8, 70))
	var plein := _decode_cross(duel)
	var or_couleur: Color = duel._hitmarker_color()
	_ok("sans le drapeau, RIEN ne change : 4 diagonales, or, largeur 2",
		int(plein["marks"]) == 4 and not duel._hitmarker_head
		and absf(float(plein["mark_width"]) - 2.0) < EXACT_TOL
		and or_couleur.is_equal_approx(Color(duel.COL_GOLD.r, duel.COL_GOLD.g, duel.COL_GOLD.b,
			or_couleur.a)),
		"%d diagonale(s), largeur %.2f, %s" % [int(plein["marks"]),
			float(plein["mark_width"]), str(or_couleur)])

	# --- le HEAD SHOT ---
	_clear_damage(duel)
	duel._on_duel_event(_hit_event_head(duel, 18, 60))
	var tete := _decode_cross(duel)
	var couleur_tete: Color = duel._hitmarker_color()
	_ok("head shot : le drapeau SERVEUR est lu, et la croix reste a QUATRE diagonales",
		duel._hitmarker_head and int(tete["marks"]) == 4,
		"_hitmarker_head = %s, %d diagonale(s)" % [str(duel._hitmarker_head),
			int(tete["marks"])])
	_ok("head shot : la croix est PLUS GRANDE et PLUS EPAISSE que la touche ordinaire",
		float(tete["mark_far"]) > float(plein["mark_far"])
		and float(tete["mark_width"]) > float(plein["mark_width"]),
		"portee %.2f -> %.2f, largeur %.2f -> %.2f" % [float(plein["mark_far"]),
			float(tete["mark_far"]), float(plein["mark_width"]), float(tete["mark_width"])])
	_ok("head shot : la croix vire au BLANC de la charte, distinct de l or ET du rouge",
		couleur_tete.is_equal_approx(Color(duel.COL_HEADSHOT.r, duel.COL_HEADSHOT.g,
			duel.COL_HEADSHOT.b, couleur_tete.a))
		and not couleur_tete.is_equal_approx(or_couleur),
		"%s" % str(couleur_tete))

	# --- LE CHIFFRE : distinct, et surtout NON RECALCULE ---
	_ok("head shot : le chiffre affiche est EXACTEMENT celui de l evenement (aucun recalcul)",
		not duel._damage_live.is_empty()
		and str((duel._damage_live[-1]["node"] as Label).text) == "18",
		"texte « %s » pour un evenement a 18" % (str((duel._damage_live[-1]["node"] as Label).text)
			if not duel._damage_live.is_empty() else "aucun"))
	var etiquette: Label = duel._damage_live[-1]["node"]
	_ok("head shot : le chiffre est BLANC et plus grand qu une touche ordinaire",
		etiquette.get_theme_color("font_color").is_equal_approx(duel.COL_HEADSHOT)
		and etiquette.get_theme_font_size("font_size") > 22,
		"%s, %d px" % [str(etiquette.get_theme_color("font_color")),
			etiquette.get_theme_font_size("font_size")])

	# --- LA PRIORITE : un head shot FATAL est d abord un MORT ---
	_clear_damage(duel)
	duel._on_duel_event(_hit_event_head(duel, 45, 0))
	var fatal: Color = duel._hitmarker_color()
	_ok("head shot FATAL : la croix reste ROUGE (mort > tete), et les deux drapeaux sont leves",
		duel._hitmarker_kill and duel._hitmarker_head
		and fatal.is_equal_approx(Color(duel.COL_DANGER.r, duel.COL_DANGER.g, duel.COL_DANGER.b,
			fatal.a)),
		"kill=%s tete=%s %s" % [str(duel._hitmarker_kill), str(duel._hitmarker_head), str(fatal)])
	_ok("head shot FATAL : le chiffre reste ROUGE lui aussi",
		not duel._damage_live.is_empty()
		and (duel._damage_live[-1]["node"] as Label).get_theme_color("font_color")
			.is_equal_approx(duel.COL_DANGER))

	# --- LE RETOUR AU CORPS : le drapeau doit se BAISSER ---
	# ⚠️ Un drapeau qui ne redescend pas est le defaut classique de ce genre d etat : la premiere
	# touche a la tete rendrait TOUS les tirs suivants blancs, et rien ne le dirait.
	_clear_damage(duel)
	duel._on_duel_event(_hit_event(duel, 8, 52))
	_ok("apres un head shot, une touche au CORPS rebaisse le drapeau",
		not duel._hitmarker_head
		and duel._hitmarker_color().is_equal_approx(Color(duel.COL_GOLD.r, duel.COL_GOLD.g,
			duel.COL_GOLD.b, duel._hitmarker_color().a)))

	# --- LE SON : deux cles DISTINCTES, et toutes deux servies ---
	_ok("les deux sons de touche existent et sont DISTINCTS",
		AudioManager.has_sfx("trench_hitmarker") and AudioManager.has_sfx("trench_headshot"),
		"hitmarker=%s headshot=%s" % [str(AudioManager.has_sfx("trench_hitmarker")),
			str(AudioManager.has_sfx("trench_headshot"))])
	_clear_damage(duel)


# =================================================================================================
# 4ter. L AIDE F1 DIT-ELLE LA VERITE ? (§8.153.3)
# =================================================================================================
# ╔═ 🩸 CE CONTROLE NAIT D UN MENSONGE QUI A VECU DEUX LOTS ══════════════════════════════════════╗
# ║ Le §8.152.10 a retire le clic droit de la grenade pour en faire la VISEE A L OEIL. La ligne   ║
# ║ d aide, elle, a continue d annoncer « G ou CLIC DROIT (maintenir) » pendant deux lots.        ║
# ║ ⚠️ Une aide qui ment est PIRE que pas d aide : le joueur essaie, ca ne marche pas, et il en   ║
# ║ conclut que le JEU est casse. Et rien ne rougissait — un texte n a pas de type.               ║
# ║                                                                                                ║
# ║ ⛔ Ce controle lie le tableau d aide au CODE : chaque commande que le duel ecoute doit avoir   ║
# ║ sa ligne, et aucune ligne ne doit nommer une touche que le code n ecoute plus.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _section_aide(duel) -> void:
	_section("4ter. AIDE F1 — elle decrit ce que le code ecoute VRAIMENT")
	var aide := ""
	for cle: String in ["TRENCH_HELP_MOVE", "TRENCH_HELP_STANCE", "TRENCH_HELP_AIM",
			"TRENCH_HELP_FIRE", "TRENCH_HELP_ADS", "TRENCH_HELP_HEADSHOT",
			"TRENCH_HELP_GRENADE", "TRENCH_HELP_RELOAD", "TRENCH_HELP_BANDAGE"]:
		aide += tr(cle) + " | " + tr(cle + "_D") + "
"
		_ok("l aide a bien un texte pour %s" % cle,
			tr(cle) != cle and tr(cle + "_D") != cle + "_D")

	# ⛔ LE MEMBRE DUR : la grenade ne doit PLUS nommer le clic droit, et la visee DOIT le nommer.
	# Les deux ensemble — sinon une aide qui aurait simplement perdu la ligne de grenade passerait.
	var gren := tr("TRENCH_HELP_GRENADE").to_upper()
	var ads := tr("TRENCH_HELP_ADS").to_upper()
	_ok("la GRENADE ne revendique plus le clic droit (il sert la visee depuis le §8.152.10)",
		not gren.contains("DROIT") and not gren.contains("RIGHT") and not gren.contains("DESTRO"),
		"« %s »" % tr("TRENCH_HELP_GRENADE"))
	_ok("la VISEE A L OEIL, elle, le revendique",
		ads.contains("DROIT") or ads.contains("RIGHT") or ads.contains("DESTRO"),
		"« %s »" % tr("TRENCH_HELP_ADS"))
	_ok("le HEAD SHOT est documente, avec sa majoration",
		tr("TRENCH_HELP_HEADSHOT_D").contains("50"),
		"« %s »" % tr("TRENCH_HELP_HEADSHOT_D"))

	# Le compte de tirs a la tete de l ecran de fin : il LIT l etat serveur, il ne cumule rien.
	_ok("le compte de tirs a la tete a son texte, et il attend DEUX nombres",
		tr("TRENCH_HEADSHOTS") != "TRENCH_HEADSHOTS"
			and tr("TRENCH_HEADSHOTS").count("%d") == 2,
		"« %s »" % tr("TRENCH_HEADSHOTS"))

