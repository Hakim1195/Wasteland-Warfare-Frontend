extends Node3D

# =================================================================================================
# §8.152 — LOT 3D-F : LE RIG DU VIEWMODEL. LE CŒUR DU CHANTIER.
#
# Port de `src/weapons/viewmodel.js` (1 088 l.).
#
# ╔═ CE QUE C'EST ═══════════════════════════════════════════════════════════════════════════════╗
# ║ « Everything the player looks at for the whole game happens in this file. It is a stack of    ║
# ║ *additive procedural layers* over one base pose — no baked clips for anything continuous. »   ║
# ║                                                                                               ║
# ║   base    mélange des poses hanche / ADS / sprint / arme basse                                 ║
# ║   sway    bruits superposés à fréquences incommensurables : le repos ne boucle jamais à l'œil  ║
# ║   bob     huit couché piloté par la foulée, mis à l'échelle de la vitesse et de la posture     ║
# ║   lag     l'arme TRAÎNE derrière la rotation de la caméra, dépasse, se pose.                   ║
# ║           « This is the single detail that makes a viewmodel feel real. »                      ║
# ║   recoil  impulsion par coup, retour ressort-amortisseur                                       ║
# ║   clip    décalage additif de recharge / inspection / sortie (lot 3D-E)                        ║
# ║                                                                                               ║
# ║ « ADS alignment is computed, not authored » : le rig RÉSOUT la translation qui pose le point   ║
# ║ de visée exactement sur l'axe de la caméra au bon dégagement d'œil.                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️⚠️ L'INVARIANT §8.141.6 — LA RAISON D'ÊTRE DE LA MOITIÉ DES CHOIX DE CE FICHIER ════════╗
# ║ **LE RIG N'ÉCRIT DANS AUCUNE VARIABLE DE VISÉE, ET N'EXPOSE RIEN QUE LA VISÉE PUISSE LIRE.**  ║
# ║                                                                                               ║
# ║ 🩸 Leur architecture est INVERSÉE par rapport à la nôtre, et la cartographie l'a établi :      ║
# ║     weapons/index.js:223   get adsProgress() { return this.viewmodel?.adsT ?? 0; }             ║
# ║     weapons/index.js:662   let base = lerp(def.spreadHip, def.spreadAds, this.adsProgress);    ║
# ║     weapons/index.js:596   this._spread = ... * (1 + this.adsProgress);                        ║
# ║ Leur `viewmodel.js` n'écrit lui-même rien dans la visée — il est techniquement propre. Mais    ║
# ║ **la précision dépend d'une variable qui vit dans le rig.** Une animation qui rate une image,  ║
# ║ un `dt` aberrant, un clip qui force `wantAds = 0` : et la dispersion bouge.                    ║
# ║                                                                                               ║
# ║ Chez nous, `_ads_t` est **une ENTRÉE**, poussée par le système d'arme dans `update(dt, s)` au  ║
# ║ même titre que `s.ads`. Il est PRIVÉ, sans accesseur, et rien dans ce fichier ne rend une      ║
# ║ valeur qu'une dispersion pourrait consommer. Les sondes `probe_trench_aim` et                  ║
# ║ `probe_trench_feel_aim` doivent rester vertes après ce lot — c'est la porte du cahier §5.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️ LE RÉTICULE COLLIMATÉ N'EST **PAS** PORTÉ — ET C'EST UNE DÉCISION, PAS UN OUBLI ═══════╗
# ║ Leur `_updateReticle` dessine un point rouge sur l'axe optique, en espace caméra, avec son     ║
# ║ vignettage — un vrai collimateur. Chez eux c'est HONNÊTE : leur `boreDir` est le −Z du groupe  ║
# ║ d'arme, le groupe d'arme est un enfant du rig sans transform propre, donc **le point marque    ║
# ║ exactement l'axe du canon**, et leurs balles partent de cet axe.                               ║
# ║                                                                                               ║
# ║ ⛔ Chez nous, NON. Nos balles ne partent pas du viewmodel : le serveur les tire depuis les     ║
# ║ angles de visée (`trench_angles`), et l'invariant ci-dessus dit que le rig n'y touche jamais.  ║
# ║ Un point accroché au rig SUIVRAIT donc le balancement, le recul et la traîne, alors que le tir ║
# ║ ne les suit pas. Ce serait un **mensonge de présentation** — exactement la famille de défauts  ║
# ║ démasquée au §8.151 (le réticule kické de 10 px sans le monde, la secousse de l'ŒIL à 7 px de  ║
# ║ désaccord). Le réticule du HUD, lui, représente la vérité serveur, et il reste seul.           ║
# ║ ⚠️ À SOUMETTRE À HAKIM au lot 3D-I : si l'on veut la sensation du point rouge, la seule voie   ║
# ║ honnête est que le MONDE bouge avec l'arme, pas que le point bouge sans le monde.              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ ORDRE D'EULER. Leur composition finale est `_e.set(rx, ry, rz, 'XYZ')`. Godot compose par
# défaut en **YXZ**. Toutes les recompositions d'angles de ce fichier passent donc par
# `_quat_xyz()`, jamais par `Node3D.rotation` ni par `Basis.from_euler` sans ordre explicite.

const Mathx := preload("res://scripts/game/trench_mathx.gd")
const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const Weapons := preload("res://scripts/game/trench_weapons3d.gd")
const Clips := preload("res://scripts/game/trench_wclips.gd")
# ⚠️ `trench_hands.gd` porte un `class_name` : sa classe interne `Arm` ne se résout QUE par
# l'identifiant global `TrenchHands.Arm` (leçon du lot 3D-D — `preload(...).Arm.new()` donne
# « Nonexistent function 'new' in base 'GDScript' »). Le `preload` reste utile pour les statiques
# de niveau module comme `hand_basis`.
const Hands := preload("res://scripts/game/trench_hands.gd")

# ── Le champ de vision de base du viewmodel ────────────────────────────────────────────────────
# `fovBase = 60` chez eux. Le champ effectif est `60 * lerp(1, view_fov, ads)`.
const FOV_BASE := 60.0

# ── Les épaules, FIXES SUR LE CORPS, exprimées en espace caméra ────────────────────────────────
# « Two constraints fight here. Too far BACK and a 570 mm arm cannot reach the handguard, so the
# two-bone solve clamps and the elbow locks dead straight — the "broomstick arm". Too far FORWARD
# (a properly bladed stance) and the upper arm itself lands inside the near frustum, so a 100 mm
# wide sleeve fills half the screen. »
# ⚠️ Ils ont MESURÉ la tentative inverse : « at z=-0.075 the 89 mm forearm sleeve crosses the frame
# diagonally and hides the barrel and the muzzle ». La portée est achetée en trichant les os de
# 10 % (cf. `L_UPPER` dans `trench_hands.gd`), pas en avançant l'épaule.
const SHOULDER_R := Vector3(0.205, -0.2, 0.06)
const SHOULDER_L := Vector3(-0.2, -0.22, 0.02)

# ── Les six canaux de bruit du balancement ─────────────────────────────────────────────────────
# « Layered, incommensurate rates: the pattern does not repeat in a session. »
const NOISE_RATES := [0.13, 0.19, 0.271, 0.083, 0.117, 0.163]


# =================================================================================================
# ÉTAT
# =================================================================================================
var rig: Node3D
var arm_r
var arm_l

var weapons := {}
var active: Dictionary = {}

# ⚠️ PRIVÉS ET SANS ACCESSEUR — voir l'invariant en tête de fichier. `_ads_t` en particulier ne
# doit JAMAIS ressortir : c'est la variable que leur dispersion consomme.
var _ads_t := 0.0
var _sprint_t := 0.0
var _low_ready_t := 0.0
var _bob_phase := 0.0
var _noise_t := 0.0
var _trigger_t := 0.0

var _lag: Mathx.MathxSpring3
var _lag_rot: Mathx.MathxSpring3
var _rec_pos: Mathx.MathxSpring3
var _rec_rot: Mathx.MathxSpring3
var _jump: Mathx.MathxSpring
var _land: Mathx.MathxSpring
var _settle: Mathx.MathxSpring3

var _noise := []
var _rng: Mathx.TrenchRng

var _ang_vel_yaw := 0.0
var _ang_vel_pitch := 0.0
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _has_prev := false

# Lecture du clip en cours (lot 3D-E)
var _clip = null
var _clip_t := 0.0
var _clip_prev_t := 0.0
var _clip_res
var _on_clip_event: Callable = Callable()

# Pièces mobiles
var _bolt_cycle := 0.0
# ⚠️ La culasse verrouillée en arrière vient de l'ÉTAT SERVEUR (chargeur à 0), jamais d'une clé
# d'animation — cf. la divergence D du lot 3D-E, où l'on a démontré que leur canal `bolt` est mort.
var _bolt_hold := 0.0

var _lib: WMat


# =================================================================================================
# CONSTRUCTION
# =================================================================================================
func _init() -> void:
	name = "trench-viewmodel-rig"
	# ⚠️ Graine FIXE : le cahier §4 impose des modèles IDENTIQUES à chaque lancement
	# (reproductibilité imagediff). ⛔ jamais `randf()` global.
	_rng = Mathx.TrenchRng.new(0x8152F16)

	rig = Node3D.new()
	rig.name = "rig"
	add_child(rig)

	# ⚠️ `Arm` attend des **CLÉS** de matériau, pas des objets : il pose les maillages sans
	# matériau et tague chacun par `set_meta("mat_key", …)`. C'est DÉLIBÉRÉ — le lot 3D-D ne
	# connaît pas la bibliothèque de matériaux, et l'y faire dépendre aurait couplé la géométrie
	# des mains au registre du lot 3D-C. C'est donc ICI, au montage, qu'on les habille.
	var mats := {"glove": "glove", "pad": "glove_pad", "seam": "glove_seam",
		"sleeve": "sleeve"}
	arm_r = TrenchHands.Arm.new(1.0, mats, {
		"scale": 1.0, "shoulderX": 0.205, "shoulderY": -0.2, "shoulderZ": 0.06, "pose": "grip",
	})
	# ⚠️ 0,97 d'échelle sur le bras de soutien : c'est le bras qui traverse le champ, et un
	# avant-bras 3 % plus fin est ce qui l'empêche de manger le canon.
	arm_l = TrenchHands.Arm.new(-1.0, mats, {
		"scale": 0.97, "shoulderX": 0.2, "shoulderY": -0.22, "shoulderZ": 0.02, "pose": "clamp",
	})
	_habiller(arm_r.root)
	_habiller(arm_l.root)
	rig.add_child(arm_r.root)
	rig.add_child(arm_l.root)

	_lag = Mathx.MathxSpring3.new(5.4, 0.46)
	_lag_rot = Mathx.MathxSpring3.new(6.2, 0.42)
	_rec_pos = Mathx.MathxSpring3.new(9.0, 0.42)
	_rec_rot = Mathx.MathxSpring3.new(9.0, 0.42)
	_jump = Mathx.MathxSpring.new(5.5, 0.5)
	_land = Mathx.MathxSpring.new(7.5, 0.55)
	_settle = Mathx.MathxSpring3.new(2.2, 0.7)

	for i in 6:
		_noise.append(Mathx.Noise1.new(_rng, 512))

	_clip_res = Clips.Sample.new()


# Parcourt un sous-arbre et applique le matériau désigné par le tag `mat_key` posé au lot 3D-D.
func _habiller(racine: Node) -> void:
	for n in racine.get_children():
		if n is MeshInstance3D and n.has_meta("mat_key"):
			(n as MeshInstance3D).material_override = _mat(String(n.get_meta("mat_key")))
		_habiller(n)


# ╔═ ⚠️ L'ASSÈCHEMENT DES MÉLANGES — ADDITION assumée, et pour la même raison qu'au lot 3D-0 ═══╗
# ║ `Mathx.damp` est une décroissance exponentielle : elle s'approche de la cible sans jamais    ║
# ║ l'atteindre. Les RESSORTS, eux, portent déjà un assèchement (deux seuils sous lesquels valeur ║
# ║ et vélocité collent NET) parce que le §8.151 avait payé la leçon : sans lui, deux captures    ║
# ║ du même repos diffèrent au dernier bit et tout imagediff devient inutilisable.                ║
# ║                                                                                               ║
# ║ 🩸 Mesuré : sans cet assèchement, la couche `trigger` reste vivante APRÈS SIX SECONDES de     ║
# ║ repos — à une valeur qui s'affiche « 0.0 » et qui n'est pas zéro. Quatre mélanges sont dans  ║
# ║ ce cas (`trigger`, `sprint`, `low_ready`, et les deux vitesses angulaires), et aucun ne se    ║
# ║ voit à l'œil : ils ne se voient que dans un contrôle qui exige le zéro BIT À BIT.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const SNAP_EPS := 1e-7

static func _damp_sec(courant: float, cible: float, taux: float, dt: float) -> float:
	var v := Mathx.damp(courant, cible, taux, dt)
	return cible if absf(v - cible) < SNAP_EPS else v


func _mat(cle: String) -> StandardMaterial3D:
	if _lib == null:
		_lib = WMat.new()
	return _lib.get_material(cle)


# =================================================================================================
# AJOUT D'UNE ARME
# =================================================================================================
# « One mesh per material per assembly: a whole rifle lands in 7-9 draw calls. »
#
# `reload_seconds` ⛔ vient du SERVEUR (`reload_ticks / tick_rate`). Voir le §D du lot 3D-E : un
# défaut ici recréerait une seconde source de vérité qui divergerait au premier rééquilibrage.
func add_weapon(weapon_id: String, reload_seconds: float) -> Dictionary:
	var modele: Dictionary = Weapons.build(weapon_id)
	var vue: Dictionary = Weapons.view_def(weapon_id)
	var noeuds: Dictionary = modele["nodes"]

	var groupe := Node3D.new()
	groupe.name = "weapon-" + weapon_id
	groupe.visible = false
	rig.add_child(groupe)

	var tris := 0
	tris += _monter(modele["body"], groupe)
	var pieces := {}
	for nom in (modele["moving"] as Dictionary):
		var sous := Node3D.new()
		sous.name = weapon_id + "-" + String(nom)
		groupe.add_child(sous)
		tris += _monter((modele["moving"] as Dictionary)[nom], sous)
		pieces[nom] = sous

	# Poser les pièces mobiles à leur transform de repos.
	for paire in [["magazine", "magSeat"], ["charging", "chargeRest"], ["bolt", "boltRest"],
			["slide", "slideRest"], ["trigger", "triggerPivot"], ["selector", "selectorPivot"]]:
		var p: String = paire[0]
		var n: String = paire[1]
		if pieces.has(p) and noeuds.has(n):
			var d: Dictionary = noeuds[n]
			(pieces[p] as Node3D).position = d["pos"]
			(pieces[p] as Node3D).quaternion = _quat_xyz(d.get("rot", Vector3.ZERO))

	var e := {
		"id": weapon_id, "vue": vue, "modele": modele, "groupe": groupe, "pieces": pieces,
		"tris": tris,
		"clips": Clips.build_clips(noeuds, vue, reload_seconds),
	"reload_s": reload_seconds,
		"sight": noeuds["sight"],
		"muzzle": noeuds["muzzle"],
		"eject": noeuds["eject"],
		"mag_seat_pos": (noeuds["magSeat"] as Dictionary)["pos"],
		"mag_seat_quat": _quat_xyz((noeuds["magSeat"] as Dictionary).get("rot", Vector3.ZERO)),
		"grip_r": noeuds["gripR"],
		"grip_l": noeuds["gripL"],
		"charge_pull": noeuds.get("chargePull", Vector3.ZERO),
		"bolt_travel": noeuds.get("boltTravel", Vector3.ZERO),
		"slide_travel": noeuds.get("slideTravel", Vector3.ZERO),
		"trigger_pull": float(noeuds.get("triggerPull", -0.3)),
		"charge_rest": noeuds.get("chargeRest", {}),
		"bolt_rest": noeuds.get("boltRest", {}),
		"slide_rest": noeuds.get("slideRest", {}),
		"mag_len": float(vue.get("mag_len", 0.2)),
		# La pose de main de soutien AJUSTÉE pour CETTE arme — voir `_ancrer_main_de_soutien`.
		# « a pose solved against one weapon's handguard cannot leak onto another's. »
		"pose_l": "cup" if not noeuds.has("handguard") else "clamp:" + weapon_id,
	}
	_ancrer_main_de_soutien(e)
	weapons[weapon_id] = e
	return e


func _monter(assemblage, parent: Node3D) -> int:
	var seaux: Dictionary = assemblage.build()
	var tris := 0
	for cle in seaux:
		var md = seaux[cle]
		var mi := MeshInstance3D.new()
		mi.mesh = Meshgen.to_array_mesh(md)
		mi.material_override = _mat(String(cle))
		mi.name = String(assemblage.name) + "-" + String(cle)
		# « The viewmodel does not cast into the cascades […] but it absolutely must RECEIVE the
		# sun shadow: without this the gun is lit at full sun while the street around it is in
		# shade, which is the single most obvious "pasted-on sticker" tell. »
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0
		parent.add_child(mi)
		tris += Meshgen.tri_count(md)
	return tris


# ── ANCRER LA MAIN DE SOUTIEN SUR LE GARDE-MAIN, UNE FOIS, À LA CONSTRUCTION ───────────────────
# Port de `_fitSupportHand`. ⚠️ La sonde `probe_vue3d_grips` a MESURÉ le résultat sur la vraie
# géométrie : les quatre pulpes se posent à +0,4 / +0,5 / +0,6 / +0,5 mm du garde-main, et le
# pouce à +1,2 — exactement le chiffre que la référence revendique (« 0.4-0.7 mm off the
# handguard — a real grip »). Voir §8.152.5.
func _ancrer_main_de_soutien(e: Dictionary) -> void:
	var noeuds: Dictionary = (e["modele"] as Dictionary)["nodes"]
	if not noeuds.has("handguard"):
		return
	var hg: Dictionary = noeuds["handguard"]
	var gl: Dictionary = e["grip_l"]
	var q := Hands.hand_basis(gl["finger"], gl["back"])
	arm_l.set_pose("clamp")
	arm_l.fit_to_cylinder(gl["pos"], q, hg["axis"], hg["dir"], float(hg["r"]),
		{"clearance": 0.001, "poseName": e["pose_l"]})
	arm_l.set_pose(e["pose_l"])


# ╔═ ⚠️⚠️ LE PIÈGE D'ORDONNANCEMENT DU LOT 3D-H, ET SON DÉSAMORÇAGE ════════════════════╗
# ║ `_apply_weapon()` est appelé depuis `_build_layers()`, donc dans `_ready()` — **bien avant**   ║
# ║ `_on_init`. À cet instant le registre serveur est VIDE et la cadence de tick vaut encore 10  ║
# ║ alors que le contrat courant est à 20 Hz : un facteur DEUX, même si les règles étaient là.    ║
# ║                                                                                              ║
# ║ Le viewmodel 2D s'en moquait — il ne consommait aucune règle. Le rig 3D, lui, **fige la      ║
# ║ durée de rechargement dans ses clips à la construction**. Construire l'arme en `_ready()`     ║
# ║ avec un zéro donnerait une animation de rechargement instantanée, pour toujours, en silence.  ║
# ║                                                                                              ║
# ║ D'où cette méthode : reconstruire les CLIPS quand la durée change. C'est bon marché — les     ║
# ║ clips ne sont que des tables de clés, aucun maillage n'est refait — et ça évite d'avoir à   ║
# ║ retarder la construction de l'arme, qui elle est coûteuse.
# ║ ⚠️ Un zéro est IGNORÉ : c'est la valeur que rend `_reload_seconds` quand le registre est     ║
# ║ muet, et écraser des clips justes par des clips instantanés serait une régression.            ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════╝
func set_reload_seconds(weapon_id: String, secondes: float) -> bool:
	if secondes <= 0.0 or not weapons.has(weapon_id):
		return false
	var e: Dictionary = weapons[weapon_id]
	if absf(float(e.get("reload_s", -1.0)) - secondes) < 1e-9:
		return false
	e["reload_s"] = secondes
	e["clips"] = Clips.build_clips((e["modele"] as Dictionary)["nodes"], e["vue"], secondes)
	# ⚠️ Un clip en cours a été construit avec l'ANCIENNE durée : le laisser tourner ferait
	# jouer une timeline sur une table qui n'existe plus. On l'arrête.
	if _clip != null:
		stop_clip()
	return true


func set_active(weapon_id: String) -> void:
	if not weapons.has(weapon_id):
		return
	if not active.is_empty():
		(active["groupe"] as Node3D).visible = false
	active = weapons[weapon_id]
	(active["groupe"] as Node3D).visible = true
	_rec_pos.reset()
	_rec_rot.reset()
	_settle.reset()
	_bolt_cycle = 0.0
	_bolt_hold = 0.0
	arm_r.set_pose("grip")
	# La pose AJUSTÉE pour cette arme, pas celle écrite à la main.
	arm_l.set_pose(active["pose_l"])


# =================================================================================================
# LECTURE DE CLIP
# =================================================================================================
func play(nom: String) -> float:
	if active.is_empty():
		return 0.0
	var jeu: Dictionary = active["clips"]
	if not jeu.has(nom):
		return 0.0
	_clip = jeu[nom]
	_clip_t = 0.0
	_clip_prev_t = -1.0
	return _clip.duration


func stop_clip() -> void:
	_clip = null
	_clip_res.reset_to_rest()


func clip_playing() -> bool:
	return _clip != null


# ⛔ Le récepteur d'événements ne doit JAMAIS écrire dans une munition, un chargeur ou une porte de
# tir : chez eux, `magin` appelle `_completeReload()` qui mute `s.mag` et `s.reserve`. Voir §D-3.
func set_clip_event_handler(cb: Callable) -> void:
	_on_clip_event = cb


# =================================================================================================
# IMPULSIONS
# =================================================================================================
# `pitch` / `yaw` sont le recul EN ESPACE DE VISÉE pour ce coup, issus du motif déterministe, « so
# the visual climb matches where the bullets are actually going ».
# ⚠️ Ils ARRIVENT ici, ils ne partent pas d'ici : c'est le système d'arme qui détient le motif.
func add_recoil(pitch: float, yaw: float, premier := false) -> void:
	if active.is_empty():
		return
	var r: Dictionary = (active["vue"] as Dictionary)["recoil"]
	# « Aiming braces the weapon: less travel, faster return. »
	var echelle := lerpf(1.0, 0.54, _ads_t) * (1.18 if premier else 1.0)
	var gigue := 0.86 + _rng.rand_float() * 0.3
	_rec_pos.set_freq(float(r["freq"]))
	_rec_pos.set_damping(float(r["damping"]))
	_rec_rot.set_freq(float(r["freq"]) * 0.92)
	_rec_rot.set_damping(float(r["damping"]))
	# « A velocity impulse of v0 on a spring of angular frequency w peaks at roughly v0/w, so the
	# kick amplitudes below are in real metres/radians. »
	var wp := TAU * _rec_pos.get_freq()
	var wr := TAU * _rec_rot.get_freq()
	_rec_pos.kick(
		_rng.signed() * float(r["kick_back"]) * 0.2 * echelle * wp,
		float(r["kick_up"]) * echelle * gigue * wp,
		float(r["kick_back"]) * echelle * gigue * wp)
	_rec_rot.kick(
		(pitch * 5.5 + float(r["pitch"]) * 1.4) * echelle * gigue * wr,
		(-yaw * 4.5 - _rng.signed() * float(r["yaw"]) * 0.8) * echelle * wr,
		(_rng.signed() * 0.4 + 0.6) * float(r["roll"]) * echelle * wr)
	# « Slow settling drift after a burst — the muzzle keeps wandering a little. »
	var ws := TAU * _settle.get_freq()
	_settle.kick(
		_rng.signed() * 0.0012 * echelle * ws,
		0.0018 * echelle * ws,
		_rng.signed() * 0.003 * echelle * ws)
	_bolt_cycle = 1.0


func jump() -> void:
	_jump.kick(-1.2)


func land(vitesse := 3.0) -> void:
	_land.kick(clampf(vitesse * 0.45, 0.4, 3.4))


# =================================================================================================
# MISE À JOUR PAR IMAGE
# =================================================================================================
# `s` porte TOUT ce que le rig a le droit de savoir, et rien d'autre :
#   ads, sprint, low_ready, speed, airborne, trigger, empty, cycle_time, yaw, pitch
#
# ⚠️ `crouch` a été RETIRÉ de ce contrat, et c'est un correctif, pas un oubli : il y figurait
# (recopié de leur signature) et **n'était consommé nulle part**. Une clé annoncée que personne
# ne lit est pire qu'une clé absente : l'appelant la remplit consciencieusement et croit avoir
# branché quelque chose. Chez nous la posture ne change pas la pose de l'ARME — elle change la
# hauteur de l'ŒIL, et c'est l'affaire de `trench_fp_world`, pas du rig.
# ⚠️ `cycle_time` vient du SERVEUR. Leur `_updateParts` lit `60 / w.def.rpm` : une CADENCE, donc
# une règle. Chez nous elle traverse la frontière comme entrée, jamais comme champ de vue.
func update(dt: float, s: Dictionary) -> void:
	if active.is_empty():
		return
	var vue: Dictionary = active["vue"]
	# « Defensive: a non-positive or absurd dt would integrate the whole animation stack backwards
	# (a negative step snaps ADS straight to 1). »
	dt = (dt if dt < 0.1 else 0.1) if dt > 0.0 else 0.0

	_maj_vitesse_angulaire(dt, float(s.get("yaw", 0.0)), float(s.get("pitch", 0.0)))

	# ── LES MÉLANGES ──────────────────────────────────────────────────────────────────────────
	# ⚠️ `_ads_t` est un état INTERNE de lissage ; sa CIBLE vient de `s.ads`, qui appartient au
	# système d'arme. Le rig ne décide pas de la visée, il la SUIT. Et rien ne le relit.
	var ads_rate := 1.0 / maxf(0.05, float(vue["ads_time"]))
	# « a clip that is not the draw forces the sights down » — recharger sort de la visée.
	var veut_ads := 0.0 if (_clip != null and _clip.name != "draw") else (
		1.0 if bool(s.get("ads", false)) else 0.0)
	# « Linear rate with a smootherstep shaping: a spring here reads as mushy. »
	_ads_t = clampf(_ads_t + (ads_rate if veut_ads > 0.5 else -ads_rate * 1.25) * dt, 0.0, 1.0)
	var ads := Mathx.smootherstep(0.0, 1.0, _ads_t)

	var cible_sprint := 1.0 if (bool(s.get("sprint", false)) and _clip == null) else 0.0
	_sprint_t = _damp_sec(_sprint_t, cible_sprint, 9.0, dt)
	_low_ready_t = _damp_sec(_low_ready_t,
		1.0 if bool(s.get("low_ready", false)) else 0.0, 8.0, dt)
	_trigger_t = _damp_sec(_trigger_t, 1.0 if bool(s.get("trigger", false)) else 0.0, 26.0, dt)

	# ── LA POSE DE BASE ───────────────────────────────────────────────────────────────────────
	var base_pos: Vector3 = vue["hip_pos"]
	var base_quat := _quat_xyz(vue["hip_rot"])
	if _sprint_t > 1e-3:
		base_pos = base_pos.lerp(vue["sprint_pos"], _sprint_t)
		base_quat = base_quat.slerp(_quat_xyz(vue["sprint_rot"]), _sprint_t)
	if _low_ready_t > 1e-3:
		base_pos = base_pos.lerp(vue["low_ready_pos"], _low_ready_t)
		base_quat = base_quat.slerp(_quat_xyz(vue["low_ready_rot"]), _low_ready_t)

	# ── LA POSE ADS : RÉSOLUE, PAS ÉCRITE ─────────────────────────────────────────────────────
	# « the rig solves for the translation that puts the weapon's sight node exactly on the camera
	# axis at the right eye relief, so the optic is pixel-centred at full ADS whatever the weapon. »
	if ads > 1e-4:
		var ads_quat := _quat_xyz(vue["ads_cant"])
		var vise_local: Vector3 = ads_quat * (active["sight"] as Vector3)
		var ads_pos := Vector3(0, 0, -float(vue["eye_relief"])) - vise_local
		base_pos = base_pos.lerp(ads_pos, ads)
		base_quat = base_quat.slerp(ads_quat, ads)

	# ── LES COUCHES ADDITIVES ─────────────────────────────────────────────────────────────────
	var p := Vector3.ZERO
	var r := Vector3.ZERO
	var sr := _sway(dt, float(vue["sway_scale"]), ads)
	p += sr[0]
	r += sr[1]
	var br := _bob(dt, float(vue["bob_scale"]), ads, s)
	p += br[0]
	r += br[1]
	var lr := _lag_layer(dt, ads)
	p += lr[0]
	r += lr[1]

	# ── RECUL + DÉRIVE DE REPOS ───────────────────────────────────────────────────────────────
	_rec_pos.step(dt, 0.0, 0.0, 0.0)
	_rec_rot.step(dt, 0.0, 0.0, 0.0)
	_settle.step(dt, 0.0, 0.0, 0.0)
	p += Vector3(_rec_pos.get_x(), _rec_pos.get_y(), _rec_pos.get_z())
	# ⚠️ Les axes de `settle` sont CROISÉS chez eux (`rx += settle.y`, `ry += settle.x`). Ce n'est
	# pas une coquille de leur part : la dérive de tangage est plus lente que celle de lacet, et
	# les deux ressorts n'ont pas les mêmes impulsions. On garde le croisement.
	r += Vector3(_rec_rot.get_x() + _settle.get_y(), _rec_rot.get_y() + _settle.get_x(),
		_rec_rot.get_z() + _settle.get_z())

	# ── SAUT / ATTERRISSAGE ───────────────────────────────────────────────────────────────────
	# ⚠️ Hors périmètre de jeu (le joueur est confiné, §6 du cahier) : ces ressorts resteront au
	# repos. Ils sont portés quand même, et c'est ce qui rend la CONTRE-ÉPREUVE possible — une
	# couche qui ne revient pas exactement à zéro casse la bit-stabilité des captures.
	_jump.step(dt, 0.0)
	_land.step(dt, 0.0)
	p.y -= _land.x * 0.014 + _jump.x * 0.006
	r.x -= _land.x * 0.05

	# ── CLIP ──────────────────────────────────────────────────────────────────────────────────
	if _clip != null:
		_clip_t += dt
		var tt: float = clampf(_clip_t, 0.0, _clip.duration)
		_clip.sample(tt, _clip_res)
		if _on_clip_event.is_valid():
			for nom in Clips.events_between(_clip, _clip_prev_t, tt):
				_on_clip_event.call(nom, _clip.name)
		_clip_prev_t = tt
		p += _clip_res.pos
		r += _clip_res.rot
		if _clip_t >= _clip.duration:
			stop_clip()

	# ── COMPOSITION ───────────────────────────────────────────────────────────────────────────
	rig.position = base_pos + p
	rig.quaternion = base_quat * _quat_xyz(r)
	rig.force_update_transform()

	_solve_hands()
	_maj_pieces(dt, s)


# ── VITESSE ANGULAIRE DE LA CAMÉRA, POUR LA COUCHE DE TRAÎNE ──────────────────────────────────
# ⚠️ Chez eux elle est DÉDUITE du quaternion de l'ancre, recopié de la caméra monde. Chez nous les
# angles de visée sont l'ENTRÉE (`set_aim` existe déjà dans le viewmodel 2D et c'est le bon sens de
# circulation) : on les reçoit, on les dérive, on ne les écrit jamais.
func _maj_vitesse_angulaire(dt: float, yaw: float, pitch: float) -> void:
	if _has_prev and dt > 1e-5:
		var dy := Mathx.wrap_pi(yaw - _prev_yaw) / dt
		var dp := Mathx.wrap_pi(pitch - _prev_pitch) / dt
		# « Low-pass, then clamp: a teleport must not throw the gun off screen. »
		_ang_vel_yaw = _damp_sec(_ang_vel_yaw, clampf(dy, -9.0, 9.0), 18.0, dt)
		_ang_vel_pitch = _damp_sec(_ang_vel_pitch, clampf(dp, -9.0, 9.0), 18.0, dt)
	else:
		_ang_vel_yaw = 0.0
		_ang_vel_pitch = 0.0
	_prev_yaw = yaw
	_prev_pitch = pitch
	_has_prev = true


# ── BALANCEMENT + RESPIRATION ─────────────────────────────────────────────────────────────────
func _sway(dt: float, echelle_arme: float, ads: float) -> Array:
	var echelle := echelle_arme * lerpf(1.0, 0.22, ads) * lerpf(1.0, 1.5, _sprint_t)
	_noise_t += dt
	var t := _noise_t
	var nx: float = _noise[0].fbm(t * float(NOISE_RATES[0]), 3) * 0.55 \
		+ _noise[3].fbm(t * float(NOISE_RATES[3]) * 2.3, 2) * 0.45
	var ny: float = _noise[1].fbm(t * float(NOISE_RATES[1]), 3) * 0.55 \
		+ _noise[4].fbm(t * float(NOISE_RATES[4]) * 2.1, 2) * 0.45
	var nz: float = _noise[2].fbm(t * float(NOISE_RATES[2]), 2) * 0.6 \
		+ _noise[5].fbm(t * float(NOISE_RATES[5]) * 1.7, 2) * 0.4
	# « Breathing: a slow 0.22 Hz cycle under the noise. »
	var souffle := sin(t * 1.38) * 0.5 + sin(t * 0.61 + 1.1) * 0.25
	return [
		Vector3(nx * 0.0075, ny * 0.006 + souffle * 0.0022, nz * 0.004) * echelle,
		Vector3(ny * 0.021 + souffle * 0.006, nx * 0.028, nz * 0.017) * echelle,
	]


# ── BALANCEMENT DE MARCHE ─────────────────────────────────────────────────────────────────────
# ⚠️ Hors périmètre de jeu : `speed` restera à 0 chez nous. La couche est portée intégralement pour
# que la contre-épreuve de bit-stabilité ait quelque chose à vérifier, et parce que la sortie de
# tranchée du §8.152 peut la réveiller sans réécriture.
func _bob(dt: float, echelle_arme: float, ads: float, s: Dictionary) -> Array:
	var vitesse := float(s.get("speed", 0.0))
	var quantite := echelle_arme * clampf(vitesse / 4.2, 0.0, 1.0) * lerpf(1.0, 0.28, ads) \
		* (0.25 if bool(s.get("airborne", false)) else 1.0)
	if vitesse > 0.05:
		# « Stride frequency scales with speed; sprint takes longer strides. »
		_bob_phase += dt * (3.1 + vitesse * 0.72) * (1.05 if bool(s.get("sprint", false)) else 1.0)
		if _bob_phase > TAU * 64.0:
			_bob_phase -= TAU * 64.0
	var bp := _bob_phase
	return [
		Vector3(sin(bp) * 0.0165, (absf(cos(bp)) - 0.6) * 0.0125, sin(bp * 2.0) * 0.0055) * quantite,
		Vector3(cos(bp * 2.0) * 0.014, sin(bp + 0.6) * 0.019, sin(bp) * 0.031) * quantite,
	]


# ── LA TRAÎNE — « the single detail that makes a viewmodel feel real » ─────────────────────────
func _lag_layer(dt: float, ads: float) -> Array:
	var e := lerpf(1.0, 0.42, ads)
	_lag.step(dt,
		clampf(-_ang_vel_yaw * 0.019, -0.05, 0.05) * e,
		clampf(_ang_vel_pitch * 0.014, -0.04, 0.04) * e,
		clampf(-absf(_ang_vel_yaw) * 0.006, -0.03, 0.03) * e)
	_lag_rot.step(dt,
		clampf(-_ang_vel_pitch * 0.075, -0.24, 0.24) * e,
		clampf(_ang_vel_yaw * 0.085, -0.3, 0.3) * e,
		clampf(-_ang_vel_yaw * 0.055, -0.2, 0.2) * e)
	return [
		Vector3(_lag.get_x(), _lag.get_y(), _lag.get_z()),
		Vector3(_lag_rot.get_x(), _lag_rot.get_y(), _lag_rot.get_z()),
	]


# =================================================================================================
# LES MAINS
# =================================================================================================
func _solve_hands() -> void:
	# Les épaules sont FIXES SUR LE CORPS : on exprime le point d'espace caméra dans l'espace du rig
	# « so the elbows do not swing when the gun moves ».
	var inv := rig.quaternion.inverse()
	arm_r.shoulder = inv * (SHOULDER_R - rig.position)
	arm_l.shoulder = inv * (SHOULDER_L - rig.position)

	var gr: Dictionary = active["grip_r"]
	arm_r.solve(gr["pos"], Hands.hand_basis(gr["finger"], gr["back"]))
	arm_r.set_trigger(_trigger_t)

	var gl: Dictionary = active["grip_l"]
	var pos: Vector3 = gl["pos"]
	var doigt: Vector3 = gl["finger"]
	var dos: Vector3 = gl["back"]
	var pose: String = active["pose_l"]
	# ⚠️ Porte BINAIRE à 0,5, et le poids vaut 1 pendant 100 % de tout clip (mécanique morte mais
	# structurante, cf. lot 3D-E) : pendant `draw`, `holster` et `inspect` aussi, la main d'appui
	# est ENTIÈREMENT pilotée par le clip et la pose ajustée par arme est suspendue.
	if _clip_res.active and _clip_res.lh_weight > 0.5:
		pos = _clip_res.lh_pos
		doigt = _clip_res.lh_finger
		dos = _clip_res.lh_back
		pose = _clip_res.lh_pose
	if pose != arm_l.pose:
		arm_l.set_pose(pose)
	arm_l.solve(pos, Hands.hand_basis(doigt, dos))


# =================================================================================================
# LES PIÈCES MOBILES
# =================================================================================================
func _maj_pieces(dt: float, s: Dictionary) -> void:
	var pieces: Dictionary = active["pieces"]

	# ⛔ `cycle_time` est une CADENCE — donc une RÈGLE. Leur `_updateParts` lit `60 / w.def.rpm`.
	# Chez nous elle arrive dans `s`, depuis le serveur. Le repli 0,1 s n'est PAS un barème : c'est
	# une valeur de sécurité pour que la culasse bouge quand même si l'appelant a oublié, et elle
	# ne décide de rien de jouable.
	if _bolt_cycle > 0.0:
		var cycle: float = maxf(0.045, float(s.get("cycle_time", 0.1)) * 0.62)
		_bolt_cycle = maxf(0.0, _bolt_cycle - dt / cycle)
	var cyc := _bolt_cycle
	# « 1 -> 0 over the cycle: out fast, back with a small bounce. »
	var course: float = (1.0 - cyc) / 0.45 if cyc > 0.55 else cyc / 0.55
	# La culasse verrouillée en arrière vient de l'ÉTAT SERVEUR, pas d'une clé d'animation.
	# 🩸 PREMIÈRE VERSION : UN VERROU SANS PORTE DE SORTIE.
	# Elle écrivait `_bolt_hold = 1.0 if empty else _bolt_hold` — c'est-à-dire qu'une fois
	# posé, RIEN ne le rabaissait, sauf un changement d'arme. Après un rechargement, la culasse
	# serait restée verrouillée en arrière pour le reste de la partie. Le contrôle V8 était
	# VERT : il vérifiait que `empty` verrouille, jamais que la fin de `empty` déverrouille.
	# ⚠️ Un contrôle qui n'éprouve qu'un seul sens d'une bascule n'éprouve pas la bascule.
	#
	# Le latch était de mon invention : chez eux `boltHold` est posé par `index.js` sur un clic à
	# vide et effacé par l'événement `boltrelease`. Chez nous `empty` vient de l'ÉTAT SERVEUR
	# (munitions à 0) et le serveur remplit le chargeur à `reload_until_tick` : le suivre
	# directement donne le bon comportement ET supprime l'état à maintenir.
	_bolt_hold = 1.0 if bool(s.get("empty", false)) else 0.0
	var decalage: float = maxf(course, _bolt_hold)

	if pieces.has("bolt") and not (active["bolt_rest"] as Dictionary).is_empty():
		(pieces["bolt"] as Node3D).position = (active["bolt_rest"] as Dictionary)["pos"] \
			+ (active["bolt_travel"] as Vector3) * decalage
	if pieces.has("slide") and not (active["slide_rest"] as Dictionary).is_empty():
		(pieces["slide"] as Node3D).position = (active["slide_rest"] as Dictionary)["pos"] \
			+ (active["slide_travel"] as Vector3) * decalage
	if pieces.has("charging") and not (active["charge_rest"] as Dictionary).is_empty():
		var tire: float = _clip_res.charge if _clip_res.active else 0.0
		(pieces["charging"] as Node3D).position = (active["charge_rest"] as Dictionary)["pos"] \
			+ (active["charge_pull"] as Vector3) * tire
	if pieces.has("trigger"):
		(pieces["trigger"] as Node3D).quaternion = _quat_xyz(
			Vector3(float(active["trigger_pull"]) * _trigger_t, 0, 0))

	if pieces.has("magazine"):
		var en_main: float = _clip_res.mag if _clip_res.active else 0.0
		var mag := pieces["magazine"] as Node3D
		mag.visible = _clip_res.mag_visible if _clip_res.active else true
		if en_main > 1e-4:
			_mag_dans_la_main(mag, en_main)
		else:
			mag.position = active["mag_seat_pos"]
			mag.quaternion = active["mag_seat_quat"]


# « The hand target is a WRIST in weapon space, so the magazine has to be offset into the palm
# (about 62 mm along the hand's -Z, the metacarpal axis) before the along-the-magazine offset —
# otherwise the mag is gripped by thin air behind the hand. »
func _mag_dans_la_main(mag: Node3D, poids: float) -> void:
	var q := Hands.hand_basis(_clip_res.lh_finger, _clip_res.lh_back)
	var cible: Vector3 = _clip_res.lh_pos + q * Vector3(0, float(active["mag_len"]) * 0.62, -0.062)
	mag.position = (active["mag_seat_pos"] as Vector3).lerp(cible, poids)
	mag.quaternion = (active["mag_seat_quat"] as Quaternion).slerp(q, poids)


# =================================================================================================
# LE CHAMP DE VISION DU VIEWMODEL
# =================================================================================================
# ⚠️ Rendu au lieu d'être écrit dans une caméra : le rig ne possède pas la caméra. Le lot 3D-H
# branchera ça sur le `SubViewport`. Rendre plutôt qu'écrire, c'est aussi ce qui empêche le rig
# d'acquérir un effet de bord observable de plus.
func view_fov() -> float:
	if active.is_empty():
		return FOV_BASE
	return FOV_BASE * lerpf(1.0, float((active["vue"] as Dictionary)["view_fov"]),
		Mathx.smootherstep(0.0, 1.0, _ads_t))


# =================================================================================================
# LA RECOMPOSITION D'ANGLES — ORDRE XYZ, PAS LE YXZ DE GODOT
# =================================================================================================
# ⚠️⚠️ Leur composition finale est `_e.set(rx, ry, rz, 'XYZ')` : la matrice est Rx·Ry·Rz. Godot
# compose `Node3D.rotation` et `Basis.from_euler` en **YXZ** par défaut. Sur les poses de hanche
# l'écart est petit ; sur `sprint_rot` (−0,40 ; 0,60 ; 0,20) il ne l'est plus du tout. C'est le même
# piège que la base du pouce au lot 3D-D, et il ne se voit dans aucun booléen.
static func _quat_xyz(e: Vector3) -> Quaternion:
	return Quaternion(Vector3(1, 0, 0), e.x) * Quaternion(Vector3(0, 1, 0), e.y) \
		* Quaternion(Vector3(0, 0, 1), e.z)


# =================================================================================================
# ÉTAT DE REPOS — pour la contre-épreuve de BIT-STABILITÉ
# =================================================================================================
# Le cahier §5 exige : « chaque couche s'annule au repos (bit-stabilité pour les captures) ;
# sabotage : supprimer le retour à zéro d'une couche → rouge ». Cette fonction rend la contribution
# de CHAQUE couche séparément, pour qu'une sonde puisse dire LAQUELLE ne se referme pas.
func residus() -> Dictionary:
	return {
		"lag": Vector3(_lag.get_x(), _lag.get_y(), _lag.get_z()),
		"lag_rot": Vector3(_lag_rot.get_x(), _lag_rot.get_y(), _lag_rot.get_z()),
		"rec_pos": Vector3(_rec_pos.get_x(), _rec_pos.get_y(), _rec_pos.get_z()),
		"rec_rot": Vector3(_rec_rot.get_x(), _rec_rot.get_y(), _rec_rot.get_z()),
		"settle": Vector3(_settle.get_x(), _settle.get_y(), _settle.get_z()),
		"jump": _jump.x,
		"land": _land.x,
		"bolt_cycle": _bolt_cycle,
		"trigger": _trigger_t,
	}
