extends Node3D

# =================================================================================================
# SONDE §8.152 — LOT 3D-G : LE SOLDAT ANIMÉ, DANS LA BOÎTE
#
# La sonde `probe_vue3d_silhouette` vérifie la BOÎTE À BORNES sur des poses relevées à la main.
# Celle-ci vérifie le SOLDAT VIVANT : elle instancie l'animateur, le fait tourner sur tous ses
# clips et tous ses coups, et mesure la pose RÉELLE.
#
# ⚠️ La différence n'est pas cosmétique. Le §8.111 a payé la leçon : un boot headless « 0 ERROR »
# ne prouve RIEN de ce qui est produit. Une borne qui existe dans un fichier et une borne qui mord
# sur une pose sont deux affirmations différentes.
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_vue3d_soldier.tscn
#             --quit-after 3000
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. la borne de hanche n'est plus appliquee dans l'animateur   -> G2
#  2. le plafond de flexion rachidienne saute                    -> G3
#  3. l'ordre d'Euler retombe sur le defaut Godot (YXZ)          -> G4
#  4. la rampe de fermeture des coups uniques disparait          -> G5
#  5. le cone de regard saute                                    -> G6
#  6. les positions d'os sont posees en ABSOLU au lieu de LOCAL  -> G1
# =================================================================================================

const Anim := preload("res://scripts/game/trench_soldier_anim.gd")
const Rig := preload("res://scripts/game/trench_soldier_rig.gd")
const Clips := preload("res://scripts/game/trench_soldier_clips.gd")
const Bounds := preload("res://scripts/game/trench_soldier_bounds.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

const CHECKS_ATTENDUS := 6
const DT: float = Clips.SIM_DT

# Les six clips de locomotion, et les sept régions de touche : le balayage doit être EXHAUSTIF,
# sinon il ne dit rien de la pose qu'il n'a pas visitée.
const LOCOMOTION := ["idle", "walk", "run", "crouchWalk", "crouchIdle", "hurtIdle"]
const REGIONS := ["head", "torso", "pelvis", "armR", "armL", "legR", "legL"]

var _fails: Array = []
var _joues := 0


func _ok(nom: String, cond: bool, detail := "") -> void:
	_joues += 1
	if cond:
		print("  [OK]   %s   | %s" % [nom, detail])
	else:
		_fails.append(nom)
		print("  [ROUGE] %s   | %s" % [nom, detail])


func _neuf():
	var a = Anim.Animator.new()
	add_child(a.root)
	return a


func _ready() -> void:
	print("\n=== SONDE 8.152 — LOT 3D-G : LE SOLDAT ANIME ===\n")
	_probe_montage()
	_probe_enveloppe()
	_probe_rachis()
	_probe_euler()
	_probe_fermeture()
	_probe_regard()

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
# G1. ⭐⭐ LE MONTAGE EST JUSTE : LE CASQUE CULMINE À 1,80 m, ET AUCUNE COLLISION N'EXISTE
# =================================================================================================
# Deux faits en un, parce qu'aucun ne se déduit de l'autre.
#
# a) ⚠️ Les positions de la table d'os sont ABSOLUES (pieds à y = 0). Un `Node3D` enfant veut sa
#    position LOCALE. Les recopier telles quelles EMPILE les hauteurs et met la tête à plusieurs
#    mètres — un défaut qui **ne se voit qu'au rendu** : la scène se construit sans une erreur.
#    On mesure donc le sommet MONDE, pas la constante qui a servi à le calculer.
# b) ⛔ « la hitbox reste la boîte du serveur (grep : aucune collision de maille) ». On ne fait pas
#    un grep de texte — il compterait les commentaires (leçon §8.145). On interroge l'ARBRE.
func _probe_montage() -> void:
	var a = _neuf()
	# ⚠️ AU REPOS, sans faire tourner l'animateur. Premier jet : je mesurais APRÈS un `update()`,
	# donc après que le clip `idle` ait appliqué son propre déplacement (−10 mm sur la tête). Le
	# contrôle rougissait sur un montage JUSTE, et le chiffre affiché (1,7807) n'était ni la pose
	# de repos ni rien d'identifiable — juste un mélange des deux.
	var sommet := -INF
	var bas := INF
	for p in a.points_monde():
		sommet = maxf(sommet, (p as Vector3).y)
		bas = minf(bas, (p as Vector3).y)
	# `HeadTop` est l'OS ; le sommet du CASQUE rendu est 0,6 mm plus haut (le bruit de
	# déplacement de maille, ±1,6 mm par sommet). L'os recalé tombe donc à 1,7895 et le casque à
	# 1,80 — c'est le second qui compte pour le joueur, et c'est sur lui qu'`ECHELLE_CASQUE` est
	# calibrée.
	# ⚠️ C'est un DÉCALAGE, pas un rapport. Premier jet : `sommet × (1,8106 / 1,8100)` — mais ces
	# deux nombres ne mesurent pas la même chose que l'os. L'os `HeadTop` est à **1,800** dans la
	# table ; le sommet du casque RENDU est à **1,8106**, soit **10,6 mm au-dessus de l'os**. Le
	# rapport donnait 1,7901 au lieu de 1,80 : faux de 10 mm, exactement l'épaisseur qu'il
	# prétendait modéliser.
	var casque: float = sommet + (Rig.SOMMET_CASQUE_RENDU - 1.800) * Rig.ECHELLE_CASQUE
	var collisions := []
	_scan_collisions(a.root, collisions)
	# ⚠️ Et le plus bas OS n'est PAS le sol : c'est l'orteil, à y = 0,030 dans la table. « Pieds à
	# y = 0 » parle de la SEMELLE du modèle, pas d'une articulation. Mon premier jet exigeait
	# `|bas| < 2 mm` et condamnait une table correcte. On compare donc à la valeur de la table,
	# mise à l'échelle — pas à un zéro qu'aucun os n'occupe.
	var orteil_table := 0.030
	_ok("G1 le casque culmine a 1,80 m, l'orteil est a sa cote, et l'arbre n'a AUCUNE collision",
		absf(casque - Geo.SILHOUETTE_TOP) < 0.002
			and absf(bas - orteil_table * Rig.ECHELLE_CASQUE) < 0.002 and collisions.is_empty(),
		"os sommet %.4f -> casque %.4f m · orteil %.4f (attendu %.4f) · collisions : %s"
			% [sommet, casque, bas, orteil_table * Rig.ECHELLE_CASQUE, str(collisions)])
	a.root.queue_free()


func _scan_collisions(n: Node, out: Array) -> void:
	if n is CollisionObject3D or n is CollisionShape3D or n is Area3D:
		out.append(n.name)
	for c in n.get_children():
		_scan_collisions(c, out)


# =================================================================================================
# G2. ⭐⭐⭐ L'ENVELOPPE TIENT DANS LA BOÎTE SUR **TOUT** LE BALAYAGE
# =================================================================================================
# C'est LA contre-épreuve que le cahier §5 exige. Le balayage doit être exhaustif : 6 clips × 7
# régions de touche × 2 niveaux de suppression × 3 poids de visée, chacun joué sur toute sa durée.
#
# 🩸 Rappel de ce qu'on borne : chez eux **cinq couches écrivent dans `hipOff` sans se voir** et
# rien ne borne la somme (−0,514 m mesuré), `hurtIdle` avance de 40 cm, `suppressAdd` de 27, et
# `HeadTop` sort à ±0,506 m latéralement contre 0,44 autorisés.
func _probe_enveloppe() -> void:
	var fautes := []
	var mordu := 0
	var visites := 0
	for c in LOCOMOTION:
		for region in REGIONS:
			for sup in [0.0, 1.0]:
				for visee in [0.0, 0.5, 1.0]:
					var a = _neuf()
					a.set_clip(c)
					a.encaisser(region, 1.0, 1.4)
					a.tirer(1.0)
					var accroupi: bool = c.begins_with("crouch")
					# Toute la durée du coup (0,5 s) plus une marge.
					for i in 16:
						a.update(DT, {"vitesse": 2.0, "suppression": sup,
							"visee_poids": visee, "accroupi": accroupi})
						visites += 1
						if not (a.ecretages as Dictionary).is_empty():
							mordu += 1
						var v := Bounds.violations(a.points_monde(), accroupi)
						if not v.is_empty():
							fautes.append("%s/%s/sup%.0f/vis%.1f : %s"
								% [c, region, sup, visee, str(v.slice(0, 1))])
					a.root.queue_free()
	# ⚠️ CONTRE-FACE INDISPENSABLE : les bornes doivent avoir MORDU quelque part. Un balayage où
	# rien n'est écrêté ne prouve pas que la boîte tient — il prouve qu'on n'a pas visité les
	# poses dangereuses, ce qui est le contraire de ce qu'on veut établir.
	_ok("G2 l'enveloppe tient dans la boite sur les %d poses balayees, et les bornes MORDENT"
			% visites,
		fautes.is_empty() and mordu > 0,
		"%d violation(s) : %s · ecretages declenches sur %d poses"
			% [fautes.size(), str(fautes.slice(0, 2)), mordu])


# =================================================================================================
# G3. ⭐ LA FLEXION RACHIDIENNE CUMULÉE EST PLAFONNÉE, ET RÉPARTIE PROPORTIONNELLEMENT
# =================================================================================================
# 🩸 Leur `_aimIk` répartit 1,25 rad — **71,6°** — sur trois vertèbres dont les poids somment à 1,0,
# et **en une seule image**. Vérifié : la pose est reconstruite à chaque `reset()`, donc ça ne
# s'accumule pas d'image en image — « en une seule image » est donc exact, et c'est le vrai risque.
# ⚠️ On vérifie AUSSI la répartition : écraser une seule vertèbre au hasard donnerait le bon cumul
# et une posture tordue. C'est le genre de défaut qu'un contrôle sur la somme seule laisse passer.
func _probe_rachis() -> void:
	var a = _neuf()
	a.set_clip("hurtIdle")
	var pire := 0.0
	var proportions_ok := true
	for i in 40:
		a.update(DT, {"vitesse": 0.0, "visee_poids": 1.0, "suppression": 1.0})
		var cumul := 0.0
		var parts := []
		for n in ["Spine", "Spine1", "Spine2"]:
			var d: Vector3 = a.poser.delta(n)
			cumul += d.x
			parts.append(d.x)
		pire = maxf(pire, absf(cumul))
		# Les trois vertèbres gardent le MÊME signe : une répartition proportionnelle ne peut pas
		# en retourner une seule.
		var pos_count := 0
		for v in parts:
			if float(v) > 1e-9:
				pos_count += 1
			elif float(v) < -1e-9:
				pos_count -= 1
		if absf(pos_count) != 3 and absf(cumul) > 1e-6:
			proportions_ok = false
	_ok("G3 la flexion rachidienne cumulee reste sous 28 deg et garde ses proportions",
		pire <= Bounds.FLEXION_RACHIS_MAX_DEG + 1e-6 and proportions_ok,
		"cumul max %.2f deg (plafond %.1f) · proportions conservees : %s"
			% [pire, Bounds.FLEXION_RACHIS_MAX_DEG, str(proportions_ok)])
	a.root.queue_free()


# =================================================================================================
# G4. ⭐ LES ANGLES SONT COMPOSÉS EN XYZ — 4,85° D'ÉCART SUR LA NUQUE, SINON
# =================================================================================================
# ⚠️ Chiffré au portage : laisser l'ordre YXZ par défaut de Godot décider coûte **4,85°** sur
# `Head` pour `hitAdd('head')`. C'est **48 quanta de visée**, soit ≈ 21 mm au sommet du crâne — sur
# une boîte dont la moitié de la hauteur utile fait 65 cm.
# Contrôle à deux faces, comme au lot 3D-F : les deux ordres doivent réellement DIFFÉRER sur cette
# pose (sinon le contrôle dort), et le rig doit être du bon côté.
func _probe_euler() -> void:
	var e := Vector3(-12.0, 18.0, 9.0)   # une pose à trois composantes, comme une réaction au coup
	var xyz: Quaternion = Clips.quat_xyz(e)
	var yxz := Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)),
		EULER_ORDER_YXZ).get_rotation_quaternion()
	var ecart := rad_to_deg(2.0 * acos(clampf(absf(xyz.dot(yxz)), -1.0, 1.0)))

	var a = _neuf()
	a.set_clip("idle")
	a.encaisser("head", 0.0, 1.4)
	# L'échantillon n° 1 est celui du pic d'enveloppe sur notre horloge (0,687).
	a.update(DT, {})
	a.update(DT, {})
	var d: Vector3 = a.poser.delta("Head")
	var attendu: Quaternion = Clips.quat_xyz(d)
	var obtenu: Quaternion = (a.bones["Head"] as Node3D).quaternion
	var ecart_rig := rad_to_deg(2.0 * acos(clampf(absf(obtenu.dot(attendu)), -1.0, 1.0)))
	_ok("G4 la pose est ecrite en XYZ (l'ordre COMPTE sur une pose a trois composantes)",
		ecart > 0.5 and ecart_rig < 1e-4,
		"les deux ordres different de %.2f deg · le rig est a %.6f deg du XYZ · delta Head %s"
			% [ecart, ecart_rig, str(d)])
	a.root.queue_free()


# =================================================================================================
# G5. ⭐ LES COUPS UNIQUES SONT **FINIS** QUAND LA MINUTERIE LES ARRÊTE
# =================================================================================================
# 🩸 Défaut de la référence : `turnStep` dure 0,42 s = **8,4 pas** à 20 Hz. Le dernier
# échantillon joué laisse l'enveloppe à **0,149** — 15 % de son pic — et la minuterie efface le
# reste d'un coup. C'est une TRONCATURE : le clip n'a pas fini, on le coupe.
#
# ⚠️⚠️ CE CONTRÔLE A ÉTÉ REFORMULÉ TROIS FOIS, ET LES DEUX PREMIÈRES MESURAIENT AUTRE CHOSE :
#
#  1. « le plus grand saut sur toute la durée < 6° ». Rougissait à **28,9°** — mais c'était la
#     MONTÉE : l'enveloppe de `hitAdd` atteint son plein en 45 ms, moins d'un pas de simulation.
#     Une réaction au coup DOIT claquer (577 °/s, la moitié de ce qu'une nuque encaisse sous
#     impact). *Un contrôle qui mélange l'attaque et l'expiration condamne l'intention en même
#     temps que le défaut.*
#
#  2. « le plus grand saut sur la QUEUE < 2° ». Meilleur, mais il mesurait encore la RAIDEUR du
#     mouvement, pas la troncature. `turn_step` est un `sin(πt)` : sa pente est maximale à la
#     fin par construction, et à 20 Hz sa dernière descente vaut 11,6° au genou **même quand le
#     clip se referme parfaitement**. Un pied qui se repose va vite ; ce n'est pas un défaut.
#
#  3. La bonne question : **le clip est-il FINI quand on l'arrête ?** On compare le résidu du
#     dernier échantillon joué au PIC du même clip. Sous 5 %, il ne restait rien à jouer et la
#     minuterie n'a rien coupé. C'est exactement le défaut d'origine (15 %), et ça ne dit rien
#     de la vitesse du geste — qui n'est pas l'affaire de ce contrôle.
func _probe_fermeture() -> void:
	var mesures := {}
	for quoi in ["tour", "recul", "coup"]:
		var a = _neuf()
		a.set_clip("idle")
		var duree := 0.0
		match quoi:
			"tour":
				a.tourner(1.0)
				duree = Clips.PAS_TOURNANT_DUREE
			"recul":
				a.tirer(1.0)
				duree = Clips.RECUL_DUREE
			"coup":
				a.encaisser("legR", 1.0, 1.4)
				duree = Clips.COUP_DUREE
		var n: int = int(ceil(duree / DT))
		# La pose de repos, pour isoler la contribution du COUP UNIQUE de celle du clip de fond.
		var b = _neuf()
		b.set_clip("idle")
		var pic := 0.0
		var residu := 0.0
		for i in n + 1:
			a.update(DT, {})
			b.update(DT, {})
			var amp := 0.0
			for os in ["UpLegR", "LegR", "FootR", "Head", "Neck", "Spine2", "Hips"]:
				var d: Vector3 = a.poser.delta(os) - b.poser.delta(os)
				amp = maxf(amp, d.length())
			pic = maxf(pic, amp)
			if i == n:
				residu = amp
		mesures[quoi] = [residu, pic, 0.0 if pic < 1e-9 else residu / pic]
		a.root.queue_free()
		b.root.queue_free()
	var fautes := []
	var detail := []
	for k in mesures:
		var m: Array = mesures[k]
		detail.append("%s %.2f/%.2f deg = %.1f %%"
			% [k, float(m[0]), float(m[1]), float(m[2]) * 100.0])
		if float(m[2]) > 0.05:
			fautes.append("%s : %.1f %% du pic reste au dernier pas" % [k, float(m[2]) * 100.0])
	_ok("G5 chaque coup unique est FINI quand la minuterie l'arrete (residu < 5 % du pic)",
		fautes.is_empty(), "residu/pic : " + " · ".join(detail))


# =================================================================================================
# G6. ⭐ LE REGARD RESTE DANS UN CÔNE **ABSOLU**
# =================================================================================================
# 🩸 Leur `_lookAt` n'a **aucune** limite articulaire : son seul plafond est un pas par image
# (« ~29 deg per bone per frame cap »). Mesuré : **la tête se pose derrière l'épaule et Y RESTE**
# (+0,211 m stable sur dix images). Un plafond de VITESSE n'est pas une limite de POSITION — et
# c'est précisément la confusion qu'un contrôle sur une seule image ne verrait pas.
# On vise donc DERRIÈRE le soldat et on laisse tourner : le cône doit tenir dans la durée.
func _probe_regard() -> void:
	var a = _neuf()
	a.set_clip("idle")
	var pire_lacet := 0.0
	var pire_tangage := 0.0
	for i in 30:
		# Une cible franchement derrière et au-dessus : le cas que leur code laisse passer.
		a.update(DT, {"cible_regard": Vector3(0.0, 4.0, -6.0)})
		var q: Quaternion = (a.bones["Head"] as Node3D).quaternion
		var e := Basis(q).get_euler(EULER_ORDER_YXZ)
		pire_lacet = maxf(pire_lacet, absf(rad_to_deg(e.y)))
		pire_tangage = maxf(pire_tangage, absf(rad_to_deg(e.x)))
	var mordu: bool = (a.ecretages as Dictionary).has("regard")
	_ok("G6 le regard reste dans son cone ABSOLU meme sur une cible derriere le soldat",
		pire_lacet <= Bounds.REGARD_LACET_MAX_DEG + 1.0
			and pire_tangage <= Bounds.REGARD_TANGAGE_MAX_DEG + 1.0 and mordu,
		"lacet max %.1f (cone %.0f) · tangage max %.1f (cone %.0f) · le cone a mordu : %s"
			% [pire_lacet, Bounds.REGARD_LACET_MAX_DEG, pire_tangage,
				Bounds.REGARD_TANGAGE_MAX_DEG, str(mordu)])
	a.root.queue_free()
