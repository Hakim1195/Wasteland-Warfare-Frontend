extends Node3D

# =================================================================================================
# SONDE §8.152 — LOT 3D-F : LE RIG DU VIEWMODEL
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_vue3d_rig.tscn
#             --quit-after 3000
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. exposer `_ads_t` derriere un accesseur public          -> V2 (fuite architecturale)
#  2. composer les angles en YXZ (le defaut Godot)            -> V4 (ordre d'Euler)
#  3. la pose ADS est ECRITE au lieu d'etre resolue           -> V3 (point de visee hors axe)
#  4. une couche ne revient plus exactement a zero            -> V1 (bit-stabilite)
#  5. la graine du bruit devient aleatoire                    -> V5 (determinisme)
#  6. la main de tir n'est plus soudee a la poignee           -> V6
#  7. la culasse ne se verrouille plus a sec                  -> V8
#  8. la trainee est desactivee                               -> V7
# =================================================================================================

const Rig := preload("res://scripts/game/trench_viewmodel3d.gd")
const Weapons := preload("res://scripts/game/trench_weapons3d.gd")
const Mathx := preload("res://scripts/game/trench_mathx.gd")

const CHECKS_ATTENDUS := 8

# Durée de rechargement PLAUSIBLE, passée en argument — jamais lue d'un registre de vue.
const RELOAD_S := 2.20
const DT := 1.0 / 60.0

var _fails: Array = []
var _joues := 0


func _ok(nom: String, cond: bool, detail := "") -> void:
	_joues += 1
	if cond:
		print("  [OK]   %s   | %s" % [nom, detail])
	else:
		_fails.append(nom)
		print("  [ROUGE] %s   | %s" % [nom, detail])


func _neuf(arme := "chacal"):
	var r = Rig.new()
	add_child(r)
	r.add_weapon(arme, RELOAD_S)
	r.set_active(arme)
	return r


func _etat(d := {}) -> Dictionary:
	var s := {
		"ads": false, "sprint": false, "low_ready": false, "speed": 0.0, "crouch": false,
		"airborne": false, "trigger": false, "empty": false, "cycle_time": 0.1,
		"yaw": 0.0, "pitch": 0.0,
	}
	for k in d:
		s[k] = d[k]
	return s


func _ready() -> void:
	print("\n=== SONDE 8.152 — LOT 3D-F : LE RIG ===\n")
	_probe_bit_stabilite()
	_probe_fuite_de_visee()
	_probe_ads_resolue()
	_probe_ordre_euler()
	_probe_determinisme()
	_probe_mains_soudees()
	_probe_trainee()
	_probe_pieces_mobiles()

	print("")
	if _joues != CHECKS_ATTENDUS:
		print("INCOMPLETE : %d controles joues, %d attendus" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(1)
	elif _fails.is_empty():
		print("TOUT VERT (%d/%d controles joues)" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(0)
	else:
		print("ECHEC : %d rouge(s) sur %d joues -> %s" % [_fails.size(), _joues, str(_fails)])
		get_tree().quit(1)


# =================================================================================================
# V1. ⭐⭐ CHAQUE COUCHE S'ANNULE AU REPOS — LA PORTE DU CAHIER §5
# =================================================================================================
# « chaque couche s'annule au repos (bit-stabilité pour les captures) ; sabotage : supprimer le
# retour à zéro d'une couche → rouge ».
#
# ⚠️ On exige le ZÉRO BIT À BIT, pas « petit ». C'est possible uniquement parce que `MathxSpring`
# porte l'ASSÈCHEMENT ajouté au lot 3D-0 : sous deux seuils, valeur ET vélocité collent NET sur la
# cible. Un ressort qui décroît exponentiellement sans assèchement s'approche de zéro sans jamais
# l'atteindre, et deux captures du même repos diffèrent alors au dernier bit — ce qui rend tout
# imagediff inutilisable. Le §8.151 avait déjà payé cette leçon.
#
# ⚠️ Et on nomme la couche fautive. Un booléen global dirait « ça bouge » sans dire quoi.
func _probe_bit_stabilite() -> void:
	var r = _neuf()
	# Secouer FORT : recul, saut, atterrissage, détente, balayage de visée.
	for i in 8:
		r.add_recoil(0.01, 0.004, i == 0)
	r.jump()
	r.land(3.0)
	for i in 30:
		r.update(DT, _etat({"trigger": true, "yaw": 0.02 * i, "pitch": -0.01 * i}))
	# Puis laisser tout se poser — 6 s, largement au-delà du plus lent (2,2 Hz, `settle`).
	for i in 360:
		r.update(DT, _etat())
	var res: Dictionary = r.residus()
	var vivants := []
	for cle in res:
		var v = res[cle]
		var n: float = (v as Vector3).length() if typeof(v) == TYPE_VECTOR3 else absf(float(v))
		if n != 0.0:
			vivants.append("%s = %s" % [cle, str(v)])
	_ok("V1 toutes les couches reviennent a ZERO BIT A BIT apres 6 s de repos",
		vivants.is_empty(), "couches encore vivantes : %s" % str(vivants))
	r.queue_free()


# =================================================================================================
# V2. ⭐⭐⭐ LE RIG N'EXPOSE RIEN QUE LA DISPERSION PUISSE LIRE — L'INVARIANT §8.141.6
# =================================================================================================
# 🩸 Chez eux : `weapons/index.js:223  get adsProgress() { return this.viewmodel?.adsT ?? 0; }`,
# puis `index.js:662  lerp(def.spreadHip, def.spreadAds, this.adsProgress)`. Leur viewmodel n'écrit
# rien dans la visée — il est techniquement propre — mais **la précision dépend d'une variable qui
# vit dans le rig**. C'est l'architecture qui est inversée, pas une ligne de code.
#
# ⚠️ Ce contrôle interroge le SCRIPT, pas le fichier : un `grep` de texte compterait les
# commentaires (leçon §8.145), et ce fichier en est plein — il PARLE d'`adsT`, de `spread` et de
# `dispersion` à longueur de pavé. Seule l'introspection dit ce qui est réellement ATTEIGNABLE.
const MOTS_INTERDITS := ["ads", "spread", "dispersion", "aim", "visee", "precision", "accuracy",
	"cone", "recoil_state", "sway_state"]
func _probe_fuite_de_visee() -> void:
	var r = _neuf()
	var fuites := []
	# ⚠️ `get_method_list()` rend AUSSI les 254 méthodes de `Node3D` : le contrôle inspectait donc
	# surtout Godot, et sa contre-face « plus de 8 méthodes publiques » était satisfaite sans rien
	# prouver. On interroge l'API DU SCRIPT.
	for m in (r.get_script() as Script).get_script_method_list():
		var nom := String(m["name"])
		if nom.begins_with("_"):
			continue
		for mot in MOTS_INTERDITS:
			if nom.to_lower().contains(mot):
				fuites.append("methode " + nom)
	for pr in (r.get_script() as Script).get_script_property_list():
		var nom := String(pr["name"])
		if nom.begins_with("_") or int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		for mot in MOTS_INTERDITS:
			if nom.to_lower().contains(mot):
				fuites.append("propriete " + nom)
	# Contre-face : le contrôle doit VOIR quelque chose, sinon il ne prouve rien. On vérifie qu'il
	# trouve bien les membres publics légitimes du rig — sans quoi une introspection vide passerait
	# pour une absence de fuite.
	var publics := 0
	for m in (r.get_script() as Script).get_script_method_list():
		if not String(m["name"]).begins_with("_"):
			publics += 1
	_ok("V2 aucun membre public du rig ne porte un nom que la dispersion pourrait consommer",
		fuites.is_empty() and publics >= 8,
		"fuites : %s · %d methodes publiques DU RIG inspectees" % [str(fuites), publics])
	r.queue_free()


# =================================================================================================
# V3. ⭐⭐ LA POSE ADS EST RÉSOLUE, PAS ÉCRITE
# =================================================================================================
# « ADS alignment is computed, not authored: the rig solves for the translation that puts the
# weapon's sight node exactly on the camera axis at the right eye relief, so the optic is
# pixel-centred at full ADS whatever the weapon. »
# C'est vérifiable AU MILLIMÈTRE et pour les quatre armes : à pleine visée, le point de visée doit
# tomber sur (0, 0, −dégagement d'œil) dans l'espace du rig.
func _probe_ads_resolue() -> void:
	var fautes := []
	for id in Weapons.WEAPON_IDS:
		var r = _neuf(id)
		# Monter en visée et attendre la saturation (le taux est linéaire, 1/ads_time).
		for i in 180:
			r.update(DT, _etat({"ads": true}))
		var vue: Dictionary = Weapons.view_def(id)
		var vise: Vector3 = (Weapons.build(id)["nodes"] as Dictionary)["sight"]
		var monde: Vector3 = r.rig.transform * vise
		var attendu := Vector3(0, 0, -float(vue["eye_relief"]))
		var ecart := monde.distance_to(attendu)
		if ecart > 0.001:
			fautes.append("%s : point de visee a %.1f mm de l'axe" % [id, ecart * 1000.0])
		r.queue_free()
	_ok("V3 a pleine visee, le point de visee tombe sur l'axe au degagement d'oeil (< 1 mm)",
		fautes.is_empty(), "fautes : " + str(fautes))


# =================================================================================================
# V4. ⭐ LES ANGLES SONT COMPOSÉS EN XYZ, PAS DANS LE YXZ PAR DÉFAUT DE GODOT
# =================================================================================================
# ⚠️ Leur composition est `_e.set(rx, ry, rz, 'XYZ')` : la matrice est Rx·Ry·Rz. Godot compose
# `Node3D.rotation` et `Basis.from_euler` en YXZ par défaut. Sur la pose de hanche l'écart est
# minuscule ; sur `sprint_rot` (−0,40 ; 0,60 ; 0,20) il ne l'est plus.
#
# Contrôle à DEUX FACES, parce qu'une seule ne prouverait rien :
#   a) les deux ordres DIFFÈRENT réellement sur cette pose — sinon le contrôle serait satisfait par
#      une géométrie où l'ordre n'a pas d'importance, et il dormirait ;
#   b) le rig utilise bien celui de la référence.
func _probe_ordre_euler() -> void:
	var e: Vector3 = (Weapons.view_def("chacal") as Dictionary)["sprint_rot"]
	var xyz := Quaternion(Vector3(1, 0, 0), e.x) * Quaternion(Vector3(0, 1, 0), e.y) \
		* Quaternion(Vector3(0, 0, 1), e.z)
	var yxz := Basis.from_euler(e, EULER_ORDER_YXZ).get_rotation_quaternion()
	# Angle entre les deux orientations, en degrés.
	var ecart_ordres := rad_to_deg(2.0 * acos(clampf(absf(xyz.dot(yxz)), -1.0, 1.0)))

	var r = _neuf()
	# Sprint pur : `damp` converge, on laisse largement le temps (9 s⁻¹).
	for i in 300:
		r.update(DT, _etat({"sprint": true}))
	var d_xyz := rad_to_deg(2.0 * acos(clampf(absf(r.rig.quaternion.dot(xyz)), -1.0, 1.0)))
	var d_yxz := rad_to_deg(2.0 * acos(clampf(absf(r.rig.quaternion.dot(yxz)), -1.0, 1.0)))
	# ⚠️ Le rig ne peut PAS coïncider exactement avec la pose de sprint : le BALANCEMENT est une
	# couche continue qui ne s'annule jamais (c'est son objet — « idle never visibly loops »), et
	# elle est même amplifiée ×1,5 au sprint. Mesuré : 0,87° d'écart permanent.
	# Le seuil ABSOLU du premier jet (0,5°) ignorait cette couche et condamnait un rig JUSTE. La
	# grandeur qui a un sens est RELATIVE à l'écart entre les deux ordres : le rig doit se trouver
	# du côté XYZ, à une petite fraction de la distance qui sépare les deux candidats.
	var part := d_xyz / maxf(ecart_ordres, 1e-6)
	_ok("V4 la pose de sprint est composee en XYZ (l'ordre COMPTE ici, et c'est le bon)",
		ecart_ordres > 2.0 and part < 0.2 and d_yxz > d_xyz * 5.0,
		"les deux ordres different de %.1f deg · rig a %.2f du XYZ (%.0f %% de l'ecart) et %.2f du YXZ" % [ecart_ordres, d_xyz, part * 100.0, d_yxz])
	r.queue_free()


# =================================================================================================
# V5. LE RIG EST DÉTERMINISTE
# =================================================================================================
# Le cahier §4 : « les modèles doivent être IDENTIQUES à chaque lancement (reproductibilité
# imagediff) ; ⛔ jamais `randf()` global ». Le recul tire de l'aléa (gigue, signes) : deux rigs
# neufs nourris de la même séquence doivent finir BIT À BIT au même endroit.
func _probe_determinisme() -> void:
	var a = _neuf()
	var b = _neuf()
	var ecarts := []
	for i in 120:
		var s := _etat({"trigger": i % 20 < 3, "yaw": sin(i * 0.07) * 0.4, "ads": i > 60})
		if i % 20 == 0:
			a.add_recoil(0.009, 0.003, true)
			b.add_recoil(0.009, 0.003, true)
		a.update(DT, s)
		b.update(DT, s)
		if a.rig.position != b.rig.position or a.rig.quaternion != b.rig.quaternion:
			ecarts.append("image %d" % i)
			break
	_ok("V5 deux rigs nourris de la meme sequence sont BIT A BIT identiques",
		ecarts.is_empty(), "premiere divergence : " + str(ecarts))
	a.queue_free()
	b.queue_free()


# =================================================================================================
# V6. LES MAINS RESTENT SOUDÉES AUX PRISES
# =================================================================================================
# « two-bone IK, hands welded to the weapon's grips ». C'est le contrat du lot 3D-D vu d'ici : quoi
# que fassent les couches additives, la main de tir est A la poignée, pas près d'elle.
func _probe_mains_soudees() -> void:
	var r = _neuf()
	var pire_r := 0.0
	var pire_l := 0.0
	var gr: Dictionary = r.active["grip_r"]
	var gl: Dictionary = r.active["grip_l"]
	for i in 200:
		if i % 17 == 0:
			r.add_recoil(0.012, 0.005, i == 0)
		r.update(DT, _etat({"trigger": i % 17 < 4, "yaw": sin(i * 0.11) * 0.8,
			"pitch": cos(i * 0.09) * 0.3, "ads": i > 120}))
		pire_r = maxf(pire_r, (r.arm_r.hand.position as Vector3).distance_to(gr["pos"]))
		pire_l = maxf(pire_l, (r.arm_l.hand.position as Vector3).distance_to(gl["pos"]))
	_ok("V6 les deux mains restent EXACTEMENT sur leurs prises pendant 200 images agitees",
		pire_r < 1e-6 and pire_l < 1e-6,
		"ecart max : tir %.6f mm · soutien %.6f mm" % [pire_r * 1e6, pire_l * 1e6])
	r.queue_free()


# =================================================================================================
# V7. LA TRAÎNE TRAÎNE VRAIMENT
# =================================================================================================
# « the gun TRAILS camera rotation on a spring, overshoots, settles. This is the single detail that
# makes a viewmodel feel real. » Un balayage de visée doit produire un décalage NON NUL et de signe
# conforme, puis un retour au repos. Un contrôle qui ne vérifierait que « non nul » serait satisfait
# par du bruit ; on vérifie donc aussi le SIGNE, qui est la propriété physique.
func _probe_trainee() -> void:
	var r = _neuf()
	var yaw := 0.0
	var pire := 0.0
	var signe_correct := true
	for i in 60:
		yaw += 0.05
		r.update(DT, _etat({"yaw": yaw}))
		var lag: Vector3 = (r.residus() as Dictionary)["lag_rot"]
		if absf(lag.y) > pire:
			pire = absf(lag.y)
		# Lacet croissant -> `lag_rot.y` positif chez eux (`clamp(av.yaw * 0.085, ...)`).
		if i > 10 and lag.y <= 0.0:
			signe_correct = false
	# Puis le repos : la traîne doit se refermer EXACTEMENT.
	for i in 300:
		r.update(DT, _etat({"yaw": yaw}))
	var reste: Vector3 = (r.residus() as Dictionary)["lag_rot"]
	_ok("V7 l'arme TRAINE derriere la camera (amplitude, signe) puis se repose exactement",
		pire > 0.01 and signe_correct and reste.length() == 0.0,
		"amplitude max %.4f rad · signe correct %s · residu %s"
			% [pire, str(signe_correct), str(reste)])
	r.queue_free()


# =================================================================================================
# V8. LES PIÈCES MOBILES SUIVENT L'ÉTAT SERVEUR, PAS UNE CLÉ D'ANIMATION
# =================================================================================================
# Le lot 3D-E a démontré que le canal `bolt` de leurs clips est MORT (`clipBolt * boltHold` est
# toujours dominé par `boltHold`). L'INTENTION — culasse verrouillée en arrière à sec — est portée
# ici, et sa source est `s.empty`, c'est-à-dire l'état SERVEUR.
# Trois faits à établir, parce qu'aucun ne se déduit des deux autres :
#   a) au repos, la culasse est à sa position de repos ;
#   b) un coup la fait sortir puis revenir ;
#   c) `empty` la maintient EN ARRIERE, et ce n'est pas un effet du coup.
func _probe_pieces_mobiles() -> void:
	var r = _neuf()
	var pieces: Dictionary = r.active["pieces"]
	if not pieces.has("bolt"):
		_ok("V8 la culasse suit l'etat serveur", false, "le chacal n'a pas de piece `bolt`")
		return
	var bolt := pieces["bolt"] as Node3D
	var repos: Vector3 = (r.active["bolt_rest"] as Dictionary)["pos"]
	var course: Vector3 = r.active["bolt_travel"]

	r.update(DT, _etat())
	var au_repos := bolt.position.distance_to(repos) == 0.0

	r.add_recoil(0.01, 0.003, true)
	var sortie := 0.0
	for i in 12:
		r.update(DT, _etat())
		sortie = maxf(sortie, bolt.position.distance_to(repos))
	for i in 60:
		r.update(DT, _etat())
	var revenue := bolt.position.distance_to(repos) == 0.0

	# ⚠️ Rig NEUF : sinon un reste de cycle du coup precedent ferait passer ce controle pour la
	# mauvaise raison.
	r.queue_free()
	var r2 = _neuf()
	for i in 10:
		r2.update(DT, _etat({"empty": true}))
	var b2: Node3D = (r2.active["pieces"] as Dictionary)["bolt"]
	var verrouillee: bool = b2.position.distance_to(repos + course) < 1e-6

	# ⚠️⚠️ LA QUATRIÈME FACE, ET C'EST ELLE QUI MANQUAIT. Première version : ce contrôle
	# vérifiait que `empty` VERROUILLE, jamais que la fin de `empty` DÉVERROUILLE. Il est resté
	# VERT sur un `_bolt_hold` qui était un verrou sans porte de sortie — une fois posé, rien ne
	# le rabaissait sauf un changement d'arme, donc la culasse serait restée en arrière pour le
	# reste de la partie APRÈS chaque rechargement.
	# **Un contrôle qui n'éprouve qu'un seul sens d'une bascule n'éprouve pas la bascule.**
	for i in 30:
		r2.update(DT, _etat({"empty": false}))
	var deverrouillee: bool = b2.position.distance_to(repos) < 1e-6

	_ok("V8 la culasse : repos, cyclee, VERROUILLEE par `empty` ET DEVERROUILLEE a son retrait",
		au_repos and sortie > course.length() * 0.5 and revenue and verrouillee and deverrouillee,
		"repos %s · sortie %.1f mm sur %.1f · revenue %s · verrouillee a sec %s · DEVERROUILLEE au reappro %s"
			% [str(au_repos), sortie * 1000.0, course.length() * 1000.0, str(revenue),
				str(verrouillee), str(deverrouillee)])
	r2.queue_free()
