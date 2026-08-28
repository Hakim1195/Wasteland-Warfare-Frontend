extends Node

# =================================================================================================
# SONDE §8.152 LOT 3D-D — LES BRAS ET LES MAINS GANTÉES.
#
# ╔═ LE CONTRAT QUE TOUTE L'ARCHITECTURE DE CE LOT EXISTE POUR GARANTIR ═════════════════════════╗
# ║ « the hands are welded to the weapon, the elbows follow […] it means **the hands can never    ║
# ║ slide off the grip**. »                                                                       ║
# ║                                                                                               ║
# ║ C'est vérifiable, et c'est le contrôle central du lot : **A1** pose une cible HORS DE PORTÉE  ║
# ║ et exige que la main y soit quand même, au bit près. Le clamp de portée doit modifier la cible║
# ║ INTERNE du solveur, jamais `hand.position`. Un portage qui « corrige » ça en clampant la main ║
# ║ ferait glisser la main sur la poignée à chaque extension — le défaut que leur ordre           ║
# ║ d'opérations tout entier est conçu pour rendre impossible.                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# CE QU'ELLE PROUVE AUSSI :
#   A2 le coude est GÉOMÉTRIQUEMENT juste : à `l1` de l'épaule et à `l2` de la main ;
#   A3 ⭐ le coude va VERS LE BAS ET VERS L'EXTÉRIEUR — « Elbows go down and outboard, ALWAYS » ;
#      un pôle exprimé en espace main le ferait remonter « straight through the near plane » ;
#   C1 ⭐ CHIRALITÉ : les deux mains sont bien des mains OPPOSÉES. Le sabotage historique de la
#      référence (miroir du mauvais côté) mettait l'index « au bas-arrière de la poignée au lieu
#      d'être sur la détente » ;
#   C2 le miroir n'a pas retourné les faces (volume signé positif des deux côtés) ;
#   T1 le repos de la détente correspond EXACTEMENT à `HAND_POSES.grip.fingers[0]` ;
#   F1 ⭐ le solveur de contact POSE VRAIMENT les doigts sur le tube (c'est tout son objet) ;
#   F2 ⭐ le pouce passe de l'AUTRE CÔTÉ du tube — « a C-clamp whose thumb is on the same side as
#      the fingers is a fist held NEXT TO the gun, not a grip ON it » ;
#   F3 la pose ajustée est mémorisée SOUS SA PROPRE CLÉ et survit à un aller-retour vers `open` ;
#   P1 les six poses sont bien formées et respectent la convention de signe.
#
# SABOTAGES QUI DOIVENT LA FAIRE ROUGIR :
#   1. clamper `hand.position` au lieu de la cible interne du solveur   -> A1.
#   2. exprimer le pôle de coude en espace MAIN (pôle inversé)          -> A3.
#   3. miroiter le bras GAUCHE au lieu du DROIT                         -> C1.
#   4. retirer le retournement de faces du miroir                       -> C2.
#   5. décaler le repos de la détente de 0,05 rad                       -> T1.
#   6. ne résoudre QUE l'articulation distale (pas de proximal d'abord)  -> F1.
#   7. ne pas mémoriser la pose ajustée                                 -> F3.
#
# ⚠️ LANCEMENT (headless suffit — aucun rendu, on mesure des transforms) :
#   & <godot_console> --headless --path frontend res://tools/probe_vue3d_hands.tscn
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const Hands := preload("res://scripts/game/trench_hands.gd")

const CHECKS_ATTENDUS := 20

var _fails: Array = []
var _ran := 0
var _mats := {"glove": "glove", "pad": "glove_pad", "seam": "glove_seam", "sleeve": "sleeve"}


func _ok(label: String, cond: bool, detail := "") -> void:
	_ran += 1
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _info(label: String, detail: String) -> void:
	print("  [base] %s   | %s" % [label, detail])


func _ready() -> void:
	print("\n===== SONDE §8.152 LOT 3D-D — BRAS ET MAINS =====\n")
	print("-- P. Les poses --")
	_probe_poses()
	print("\n-- C. Chiralite et construction --")
	_probe_chiralite()
	print("\n-- A. Le solveur a deux os --")
	_probe_ik()
	print("\n-- F. Le solveur de contact sur cylindre --")
	_probe_contact()
	var complet := _ran == CHECKS_ATTENDUS
	if not complet:
		print("\n[ROUGE] SONDE INCOMPLETE : %d controles joues sur %d attendus."
			% [_ran, CHECKS_ATTENDUS])
	print("\n%s" % (("TOUT VERT (%d/%d controles joues)" % [_ran, CHECKS_ATTENDUS])
		if (_fails.is_empty() and complet)
		else ("ECHEC : %d rouge(s) sur %d joues (%d attendus) -> %s"
			% [_fails.size(), _ran, CHECKS_ATTENDUS, str(_fails)])))
	get_tree().quit(0 if (_fails.is_empty() and complet) else 1)


# ⚠️ Type de retour ANNOTÉ : sans lui, chaque `var x := _bras(...)` échoue à l'inférence. C'est
# possible ici parce que `trench_hands.gd` porte un `class_name` (cf. le pavé de son en-tête).
func _bras(side: float, opts := {}) -> TrenchHands.Arm:
	var o := {"scale": 1.0, "pose": "wrap"}
	o.merge(opts, true)
	# ⚠️ `TrenchHands.Arm` et non `Hands.Arm` : un `preload(...)` rend le SCRIPT, et l'accès à une
	# classe interne par ce chemin retombe sur le script lui-même (« Nonexistent function 'new' in
	# base 'GDScript' »). C'est le nom GLOBAL qui donne accès à la classe interne.
	return TrenchHands.Arm.new(side, _mats, o)


# =================================================================================================
# P. LES POSES
# =================================================================================================
func _probe_poses() -> void:
	var attendues := ["grip", "wrap", "clamp", "cup", "open", "pinch"]
	var manquantes := []
	var malformees := []
	for k in attendues:
		if not TrenchHands.HAND_POSES.has(k):
			manquantes.append(k)
			continue
		var p: Dictionary = TrenchHands.HAND_POSES[k]
		if not p.has("fingers") or p["fingers"].size() != 4:
			malformees.append(k + ": pas 4 doigts")
			continue
		for f in p["fingers"]:
			if f.size() != 3:
				malformees.append(k + ": pas 3 phalanges")
		if not p.has("thumb") or p["thumb"].size() != 2:
			malformees.append(k + ": pouce malforme")
		if not p.has("thumb_base") or p["thumb_base"].size() != 3:
			malformees.append(k + ": base de pouce malformee")
	_ok("P1 les six poses existent et sont bien formees",
		manquantes.is_empty() and malformees.is_empty(),
		"manquantes %s · malformees %s" % [str(manquantes), str(malformees)])

	# P2. CONVENTION DE SIGNE : les flexions sont stockées POSITIVES (elles sont appliquées
	# négatives). Une valeur négative ici retournerait le doigt vers le dos de la main.
	var negatives := []
	for k in TrenchHands.HAND_POSES:
		var p: Dictionary = TrenchHands.HAND_POSES[k]
		for i in p["fingers"].size():
			for j in 3:
				if float(p["fingers"][i][j]) < 0.0:
					negatives.append("%s.f%d.j%d" % [k, i, j])
		for j in 2:
			if float(p["thumb"][j]) < 0.0:
				negatives.append("%s.thumb%d" % [k, j])
	_ok("P2 toutes les flexions sont stockees POSITIVES (elles s'appliquent negatives)",
		negatives.is_empty(), "negatives : " + str(negatives))

	# ⚠️ BUDGET ANGULAIRE DE LA POSE `clamp` : « for a 47 mm handguard gripped 14 mm off the surface
	# that is 150-165 deg, i.e. **2.6-2.9 rad TOTAL**. Anything less and the fingertips stop in
	# mid-air short of the far side » — le défaut « detached grey slabs with daylight between them
	# and the handguard ».
	var clamp_p: Dictionary = TrenchHands.HAND_POSES["clamp"]
	var sommes := []
	var hors := []
	for i in 4:
		var somme := 0.0
		for j in 3:
			somme += float(clamp_p["fingers"][i][j])
		sommes.append("%.2f" % somme)
		if somme < 2.3 or somme > 3.0:
			hors.append("doigt %d : %.2f rad" % [i, somme])
	_ok("P3 la pose `clamp` tient dans le budget angulaire 2,3-3,0 rad par doigt",
		hors.is_empty(), "sommes : " + " · ".join(sommes) + " · hors budget : " + str(hors))


# =================================================================================================
# C. CHIRALITÉ
# =================================================================================================
	# Bout du doigt `i` (4 = le pouce) dans le repère de la MAIN, chaîne composée à la main.
static func _bout(a, i: int) -> Vector3:
	var mx: Transform3D = a.hand_inner.transform
	if i == 4:
		return a._joint_point(mx * a.thumb_root.transform, a.thumb_joints, 1,
			Vector3(0, 0, -TrenchHands.THUMB_L1 * a.scale_f))
	var spec: Dictionary = TrenchHands.FINGER_SPECS[i]
	return a._joint_point(mx * (a.finger_roots[i] as Node3D).transform, a.fingers[i], 2,
		Vector3(0, 0, -float(spec["len"][2]) * a.scale_f))


func _probe_chiralite() -> void:
	var g := _bras(-1.0)
	var d := _bras(1.0)

	# ── C1. LES DEUX MAINS SONT DES MAINS OPPOSÉES ─────────────────────────────────────────────
	# Le maillage écrit est une main GAUCHE (pouce à +X) : c'est le bras DROIT qui reçoit le
	# miroir. On le mesure sur la position de la racine du pouce, qui doit avoir des signes
	# CONTRAIRES d'un bras à l'autre.
	var tx_g: float = g.thumb_root.position.x
	var tx_d: float = d.thumb_root.position.x
	_ok("C1 les deux mains sont des mains OPPOSEES (pouces de part et d'autre)",
		tx_g * tx_d < 0.0 and absf(tx_g) > 1e-4,
		"pouce gauche x=%.5f · pouce droit x=%.5f" % [tx_g, tx_d])

	# C1b. Les doigts suivent le même miroir que le pouce : si l'un est miroité et pas l'autre,
	# la main est chimérique et la préhension impossible.
	var fx_g: float = g.finger_roots[0].position.x
	var fx_d: float = d.finger_roots[0].position.x
	_ok("C1b l'index suit le MEME miroir que le pouce (main coherente, pas chimerique)",
		fx_g * fx_d < 0.0 and (fx_g * tx_g) > 0.0 and (fx_d * tx_d) > 0.0,
		"index gauche x=%.5f · index droit x=%.5f" % [fx_g, fx_d])

	# ── C1c. ⭐⭐ LES DEUX MAINS SONT DES MIROIRS EXACTS, BOUT DE DOIGT PAR BOUT DE DOIGT ──────
	# ⚠️ C1 et C1b ne regardent que des **positions de racine**. Elles sont vertes dès que les
	# `position` sont miroir — et elles le restent si les **rotations** ne le sont pas. Or c'est
	# précisément là que la chiralité se perd chez nous : la référence retourne la main d'un seul
	# geste (`handInner.scale.x = -1`, qui traverse tout le sous-arbre), alors que nous cuisons le
	# miroir dans le MAILLAGE et devons donc miroiter la hiérarchie à la main.
	#
	# 🩸 Mesuré par sabotage : retirer le miroir du **Z** de la base du pouce, ou celui de la
	# rotation des racines de doigts, laissait C1, C1b **et** F2 toutes VERTES. Trois contrôles
	# d'affilée aveugles au même défaut, parce que tous trois regardaient un scalaire.
	# Ici on compare les 5 BOUTS, dans les 6 poses, dans le repère de la main : le droit doit
	# valoir exactement (−x, y, z) du gauche. Aucune composante de rotation ne peut se soustraire.
	var fautes_miroir := []
	for cle in TrenchHands.HAND_POSES:
		var ag := _bras(-1.0, {"pose": cle})
		var ad := _bras(1.0, {"pose": cle})
		ag.set_pose(cle)
		ad.set_pose(cle)
		for i in 5:
			var pg := _bout(ag, i)
			var pd := _bout(ad, i)
			var ecart := (pd - Vector3(-pg.x, pg.y, pg.z)).length()
			if ecart > 1e-6:
				fautes_miroir.append("%s/bout %d : ecart %.2f mm" % [cle, i, ecart * 1000.0])
	_ok("C1c les deux mains sont des MIROIRS EXACTS (5 bouts x 6 poses, rotations comprises)",
		fautes_miroir.is_empty(),
		"%d ecart(s) : %s" % [fautes_miroir.size(), str(fautes_miroir.slice(0, 3))])

	# ── C2. LE MIROIR N'A PAS RETOURNÉ LES FACES ───────────────────────────────────────────────
	# Une échelle négative inverse le sens de parcours ; `MeshData.apply_transform` le compense en
	# retournant les faces quand le déterminant devient négatif (lot 3D-0). Si cette compensation
	# saute, la main droite est un maillage retourné — invisible en `CULL_DISABLED`, trou noir
	# sinon. Le volume signé le mesure, et il ne peut pas être satisfait par construction.
	var vol_g := _volume_gant(g)
	var vol_d := _volume_gant(d)
	_ok("C2 le miroir n'a pas retourne les faces (volume signe POSITIF des deux cotes)",
		vol_g > 0.0 and vol_d > 0.0,
		"volume gant gauche %.3f mm3 · droit %.3f mm3" % [vol_g * 1e9, vol_d * 1e9])

	_info("C3 budget", "%d triangles par bras (coque de gant + pads + coutures + 5 doigts)"
		% _tris_bras(g))

	# T1. Le repos de la détente correspond EXACTEMENT à `HAND_POSES.grip.fingers[0]`.
	# « the finger is already ON the trigger with the slack taken up, not standing off it straight »
	var t := _bras(1.0, {"pose": "grip"})
	t.set_trigger(0.0)
	var attendu: Array = TrenchHands.HAND_POSES["grip"]["fingers"][0]
	var ecarts := []
	for j in 3:
		var got: float = -t.fingers[0][j].rotation.x
		if absf(got - float(attendu[j])) > 1e-6:
			ecarts.append("j%d: %.4f vs %.4f" % [j, got, float(attendu[j])])
	_ok("T1 le repos de la detente EGALE la pose `grip` (pas de doigt qui flotte)",
		ecarts.is_empty(), "ecarts : " + str(ecarts))

	# T2. La détente ne bouge QUE l'index.
	var avant := []
	for i in range(1, 4):
		avant.append(t.fingers[i][0].rotation.x)
	t.set_trigger(1.0)
	var bouges := []
	for i in range(1, 4):
		if absf(t.fingers[i][0].rotation.x - float(avant[i - 1])) > 1e-9:
			bouges.append(i)
	_ok("T2 la detente ne bouge QUE l'index",
		bouges.is_empty() and absf(t.fingers[0][0].rotation.x + 0.85) < 1e-6,
		"autres doigts bouges : %s · index a plein %.4f" % [str(bouges),
			t.fingers[0][0].rotation.x])


func _volume_gant(arm) -> float:
	# La coque du gant est le premier `MeshInstance3D` de `hand_inner`.
	for c in arm.hand_inner.get_children():
		if c is MeshInstance3D and c.name == "glove":
			var am: ArrayMesh = c.mesh
			var arr := am.surface_get_arrays(0)
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var v := 0.0
			var i := 0
			while i < idx.size():
				v += pos[idx[i]].dot(pos[idx[i + 2]].cross(pos[idx[i + 1]]))
				i += 3
			return v / 6.0
	return 0.0


func _tris_bras(arm) -> int:
	var n := 0
	for c in _tous_les_mesh(arm.root):
		var am: ArrayMesh = c.mesh
		for s in am.get_surface_count():
			n += am.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	return n


func _tous_les_mesh(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_tous_les_mesh(c))
	return out


# =================================================================================================
# A. LE SOLVEUR À DEUX OS
# =================================================================================================
func _probe_ik() -> void:
	var arm := _bras(1.0)
	var cible := Vector3(0.12, -0.18, -0.30)
	var q := Quaternion(Vector3(0, 1, 0), 0.3)
	arm.solve(cible, q)

	# ── A1. LA MAIN NE GLISSE JAMAIS, MÊME HORS DE PORTÉE ──────────────────────────────────────
	# C'est LE contrat de leur ordre d'opérations. On pose une cible à 2 m — très au-delà des
	# 0,63 m de portée du bras — et on exige que la main y soit AU BIT PRÈS. Le clamp doit agir
	# sur la cible INTERNE, jamais sur `hand.position`.
	var loin := Vector3(1.5, -1.2, -2.0)
	arm.solve(loin, q)
	# ⚠️ Comparaison APPROCHÉE, pas bit à bit : `Node3D` stocke une base et RECONSTRUIT le
	# quaternion à la lecture — l'aller-retour n'est pas exact au dernier bit. Ce qui compte ici
	# n'est pas l'égalité binaire mais que la main n'ait pas GLISSÉ ; le micron suffit largement.
	# (Premier jet : `==` strict. Il rougissait sur un solveur JUSTE — un contrôle plus serré que
	# la précision du support ne mesure que le support, comme au lot 3D-0 avec le float 32 bits.)
	var d_pos := arm.hand.position.distance_to(loin)
	var d_rot := absf(arm.hand.quaternion.dot(q))
	_ok("A1 la main est posee sur sa cible AU MICRON, meme hors de portee du bras",
		d_pos < 1e-6 and d_rot > 1.0 - 1e-6,
		# ⚠️ Pas de `%e` : GDScript ne connaît pas ce spécificateur et rend le GABARIT BRUT.
		"ecart de position %.6f mm · alignement de rotation %.9f (portee du bras %.3f m)"
			% [d_pos * 1000.0, d_rot, arm.l1 + arm.l2])

	# A2. Le coude est géométriquement juste : à `l1` de l'épaule, à `l2` de la main — pour une
	# cible ATTEIGNABLE.
	arm.solve(cible, q)
	var d1 := arm.elbow.distance_to(arm.shoulder)
	var d2 := arm.elbow.distance_to(cible)
	_ok("A2 le coude est a l1 de l'epaule et a l2 de la main",
		absf(d1 - arm.l1) < 1e-5 and absf(d2 - arm.l2) < 1e-5,
		"epaule->coude %.5f (l1 %.5f) · coude->main %.5f (l2 %.5f)"
			% [d1, arm.l1, d2, arm.l2])

	# ── A3. ⭐ LE COUDE VA VERS LE BAS ET VERS L'EXTÉRIEUR ─────────────────────────────────────
	# « Expressing the pole in HAND space is the intuitive choice and it is WRONG: the support hand
	# is rolled palm-up on the handguard, so its local "down" points at the sky and the elbow swings
	# UP — straight through the near plane, **filling half the screen with forearm**. »
	# On le vérifie sur les DEUX bras : le coude doit être sous la ligne épaule-main, et plus
	# écarté de l'axe que ne l'est cette ligne.
	var fautes := []
	for side in [-1.0, 1.0]:
		var a := _bras(side)
		var c := Vector3(0.11 * side, -0.17, -0.29)
		a.solve(c, Quaternion.IDENTITY)
		var milieu := (a.shoulder + c) * 0.5
		if a.elbow.y >= milieu.y:
			fautes.append("cote %d : le coude REMONTE (y %.4f >= milieu %.4f)"
				% [int(side), a.elbow.y, milieu.y])
		if absf(a.elbow.x) <= absf(milieu.x):
			fautes.append("cote %d : le coude ne s'ecarte pas (|x| %.4f <= %.4f)"
				% [int(side), absf(a.elbow.x), absf(milieu.x)])
	_ok("A3 le coude descend ET s'ecarte, des deux cotes (jamais vers la camera)",
		fautes.is_empty(), "fautes : " + str(fautes))

	# A4. Le solveur est stable : deux appels identiques donnent le même coude.
	var a1 := _bras(1.0)
	a1.solve(cible, q)
	var e1 := a1.elbow
	a1.solve(cible, q)
	_ok("A4 le solveur est deterministe (meme entree, meme coude)",
		a1.elbow == e1, "coude %s" % str(a1.elbow))


# =================================================================================================
# F. LE SOLVEUR DE CONTACT
# =================================================================================================
func _probe_contact() -> void:
	# Un garde-main plausible : rayon 27,1 mm (celui du M4A1, panneaux compris), axe le long de Z.
	var rayon := 0.0271
	var axe_pt := Vector3(0.0, 0.0, 0.0)
	var axe_dir := Vector3(0, 0, 1)
	var arm := _bras(-1.0, {"pose": "clamp"})
	# La main est posée SOUS le tube, paume vers le haut — la prise en C-clamp.
	var hand_pos := Vector3(0.0, -rayon - 0.016, -0.02)
	var hand_q := Quaternion(Vector3(0, 0, 1), PI)
	# ── TÉMOIN AVANT AJUSTEMENT ────────────────────────────────────────────────────────────────
	# ⚠️ Un écart ABSOLU après ajustement dépend autant de la qualité de la pose de main qu'on
	# fournit que du solveur lui-même — et la pose d'essai ci-dessus est INVENTÉE, pas dérivée
	# d'une arme réelle (le lot 3D-F fournira les vraies). Mesurer AVANT et APRÈS sépare deux
	# questions distinctes : « le solveur travaille-t-il ? » est une propriété du CODE ; « le
	# contact est-il parfait ? » dépend d'une pose qu'on n'a pas encore.
	arm.set_pose("clamp")
	var avant_fit: Array = arm.measure_contacts(hand_pos, hand_q, axe_pt, axe_dir, rayon)
	var contacts: Array = arm.fit_to_cylinder(hand_pos, hand_q, axe_pt, axe_dir, rayon,
		{"clearance": 0.001, "poseName": "clamp"})

	# ╔═ ⚠️⚠️ CE QUE CETTE SECTION A LE DROIT D'AFFIRMER, ET CE QU'ELLE N'A PAS LE DROIT ═════════╗
	# ║ La pose de main ci-dessus est **INVENTÉE**. Chez eux elle est dérivée du nœud garde-main  ║
	# ║ de l'arme réelle (`gripL`) — nous ne l'aurons qu'au lot 3D-F. Un seuil ABSOLU sur l'écart ║
	# ║ de contact mesurerait donc autant la qualité de ma pose que celle du solveur, et le seul  ║
	# ║ moyen de le faire passer serait de RÉGLER LA POSE JUSQU'À CE QUE LE CHIFFRE PLAISE —      ║
	# ║ c'est-à-dire ajuster le test sur la réponse. Mesuré : deux poses plausibles écrites de    ║
	# ║ bonne foi donnent 5,3 mm et 18,6 mm sur le même code, sans qu'aucune ligne ne change.     ║
	# ║                                                                                           ║
	# ║ Cette section n'affirme donc que des propriétés **indépendantes de la pose** :            ║
	# ║   F1a — le solveur RAPPROCHE réellement les contacts (propriété du code) ;                ║
	# ║   F1b — il n'ENFOUIT jamais rien dans la matière (le défaut qui se VOIT) ;                ║
	# ║   F1c — le pouce atteint un optimum PROUVÉ atteignable sur cette géométrie précise.       ║
	# ║ ⚠️ Le seuil absolu sur les quatre doigts est **reporté au lot 3D-F**, avec la vraie pose. ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝

	# ── F1a. LE SOLVEUR RAPPROCHE VRAIMENT ────────────────────────────────────────────────────
	var detail := []
	var somme_avant := 0.0
	var somme_apres := 0.0
	for i in 5:
		var p: Vector3 = contacts[i]
		var d := Vector2(p.x, p.y).length() - rayon
		somme_avant += absf(float(avant_fit[i]))
		somme_apres += absf(d)
		detail.append("%.1f->%.1f" % [absf(float(avant_fit[i])) * 1000.0, absf(d) * 1000.0])
	_ok("F1a l'ajustement RAPPROCHE les 5 contacts de la surface",
		contacts.size() == 5 and somme_apres < somme_avant,
		"mm avant->apres : " + " · ".join(detail)
			+ "  (total %.1f -> %.1f mm)" % [somme_avant * 1000.0, somme_apres * 1000.0])

	# ╔═ 🩸🩸 LE DÉFAUT OUVERT DU LOT — LU, MESURÉ, NON CORRIGÉ, ET VERROUILLÉ ═══════════════════╗
	# ║ Le solveur de contact de la référence, porté FIDÈLEMENT, enfonce la pulpe du MAJEUR et   ║
	# ║ de l'ANNULAIRE **dans** le garde-main sur presque toute la plage de serrage. Balayage du  ║
	# ║ jeu main↔surface, pire enfoncement des quatre doigts (négatif = sous la surface) :        ║
	# ║                                                                                           ║
	# ║   jeu  mm │  4     6     8    10    11    12    13    14    16    18    20    24          ║
	# ║   pire mm │ -9,5  -8,5  -6,9  -5,2  -4,4  -3,5  -2,6  -1,8   0,0  -0,4  -1,8  -3,4       ║
	# ║                                                                                           ║
	# ║ Leur propre tolérance est **1,5 mm** (`g < -0.0015` dans leur coût). Elle n'est tenue      ║
	# ║ qu'entre 15 et 19 mm environ. Leur point de conception documenté est « a 47 mm handguard  ║
	# ║ gripped **14 mm** off the surface » — où l'on mesure déjà −1,8 mm, soit hors tolérance.    ║
	# ║                                                                                           ║
	# ║ 🩸 ET LA PREMIÈRE VERSION DE CE CONTRÔLE ÉTAIT UN VERT ACCIDENTEL : elle ne testait qu'un ║
	# ║ seul jeu, **16 mm**, choisi sans y penser — le SEUL de la table qui soit propre. Un point ║
	# ║ de mesure unique dans un phénomène non monotone ne mesure rien : il tire au sort.         ║
	# ║                                                                                           ║
	# ║ ⛔ POURQUOI CE N'EST PAS CORRIGÉ ICI. Trois remèdes ont été construits et mesurés         ║
	# ║ (descente par coordonnées sur le coût complet, poids d'enfouissement ×8 puis ×80,         ║
	# ║ réparation depuis le résultat séquentiel). **Aucun n'est uniformément meilleur** : ils     ║
	# ║ redressent 16→24 mm mais calent à 10-14 mm, et sous 8 mm ils échangent 7 mm de contact    ║
	# ║ de pulpe contre **14 mm de phalange enfouie** — un défaut PIRE, car il se voit. Livrer    ║
	# ║ une réécriture qu'on ne peut pas montrer meilleure serait troquer un défaut connu et      ║
	# ║ chiffré contre un défaut inconnu.                                                         ║
	# ║                                                                                           ║
	# ║ ⚠️⚠️ ACTION OBLIGATOIRE AU LOT 3D-F : c'est l'arme qui placera la main (leur `gripL` est  ║
	# ║ dérivé du nœud garde-main). **Mesurer le jeu réel produit, et le placer dans 15-19 mm**,  ║
	# ║ ou reprendre le solveur avec la vraie géométrie sous les yeux. Ne pas figer une pose de   ║
	# ║ main sans avoir relu cette table.                                                          ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝

	# ── F1b. ⭐ LE POUCE, LUI, NE S'ENFONCE JAMAIS — SUR TOUTE LA PLAGE ───────────────────────
	# Ce que le solveur du pouce (notre descente conjointe) tient et que celui des doigts ne
	# tient pas. C'est la moitié du problème qui EST résolue, et elle doit le rester.
	var jeux := [0.004, 0.006, 0.008, 0.010, 0.011, 0.012, 0.013, 0.014, 0.016, 0.018, 0.020,
		0.024]
	# Pire enfoncement des QUATRE DOIGTS, mesuré sur le port fidèle, en mm. Sert de garde-fou de
	# NON-RÉGRESSION (F1d) : on n'affirme pas que c'est bien, on affirme que ça n'empire pas.
	var reference_doigts := [-9.5, -8.5, -6.9, -5.2, -4.4, -3.5, -2.6, -1.8, 0.0, -0.4, -1.8,
		-3.4]
	var pire_pouce := 0.0
	var regressions := []
	var detail_enfoui := []
	for n in jeux.size():
		var ap := _bras(-1.0, {"pose": "clamp"})
		var cc: Array = ap.fit_to_cylinder(Vector3(0.0, -rayon - float(jeux[n]), -0.02), hand_q,
			axe_pt, axe_dir, rayon, {"clearance": 0.001, "poseName": "clamp"})
		var pire_d := 0.0
		for k in 4:
			pire_d = minf(pire_d,
				Vector2((cc[k] as Vector3).x, (cc[k] as Vector3).y).length() - rayon)
		var tp: Vector3 = cc[4]
		pire_pouce = minf(pire_pouce, Vector2(tp.x, tp.y).length() - rayon)
		# 0,2 mm de marge : au-delà, c'est le code qui a bougé, pas l'arrondi.
		if pire_d * 1000.0 < float(reference_doigts[n]) - 0.2:
			regressions.append("jeu %.0f mm : %.1f mm (repere %.1f)"
				% [float(jeux[n]) * 1000.0, pire_d * 1000.0, float(reference_doigts[n])])
		detail_enfoui.append("%.0f:%.1f" % [float(jeux[n]) * 1000.0, pire_d * 1000.0])
	_ok("F1b le POUCE ne s'enfonce jamais sous la surface, sur 12 jeux (tolerance 1,5 mm)",
		pire_pouce > -0.0015,
		"enfoncement maximal du pouce %.2f mm" % (pire_pouce * 1000.0))

	# ── F1d. ⭐ LE DÉFAUT DES DOIGTS N'EMPIRE PAS ─────────────────────────────────────────────
	# Un contrôle de NON-RÉGRESSION sur des chiffres mesurés, pas un objectif. Il rougit si une
	# retouche du solveur, des cotes de doigt ou des poses dégrade l'enfoncement de plus de
	# 0,2 mm à l'un des 12 jeux — y compris une retouche qui améliorerait ailleurs. C'est ce
	# qu'on peut affirmer honnêtement tant que la vraie pose de main n'existe pas.
	_ok("F1d l'enfoncement des doigts n'a pas REGRESSE par rapport au releve du lot",
		regressions.is_empty(),
		"mm par jeu : " + " · ".join(detail_enfoui)
			+ ("  | REGRESSIONS : " + str(regressions) if not regressions.is_empty() else ""))

	# ── F1c. ⭐ LE POUCE ATTEINT UN OPTIMUM DONT L'EXISTENCE EST PROUVÉE ──────────────────────
	# Le seul seuil ABSOLU que cette section s'autorise, et seulement parce que l'optimum a été
	# mesuré INDÉPENDAMMENT du solveur : sur cette géométrie exacte, une force brute à 5 degrés
	# de liberté (7×13×13×9×9 configurations) atteint **0,0 mm**. Exiger < 2 mm n'est donc pas un
	# seuil choisi pour passer, c'est « approche l'optimum prouvé ».
	# ⚠️ Premier jet du portage : **20,2 mm** — l'ajustement glouton de la référence perd le
	# résultat de son propre balayage de base (1,4 mm avant les deux flexions, 20,2 après).
	var bout_pouce: Vector3 = contacts[4]
	var ecart_pouce := absf(Vector2(bout_pouce.x, bout_pouce.y).length() - rayon)
	_ok("F1c le POUCE approche l'optimum prouve atteignable (< 2 mm pour un optimum a 0,0)",
		ecart_pouce < 0.002,
		"pouce a %.2f mm" % (ecart_pouce * 1000.0))

	# ── F2. ⭐ LE C-CLAMP EST LA SEULE POSE OÙ LE POUCE FRANCHIT L'AXE DE LA MAIN ─────────────
	# « The thumb wraps to the OPPOSITE side of the tube: a C-clamp whose thumb is on the same
	# side as the fingers is **a fist held next to the gun**, not a grip on it. »
	#
	# ⚠️ DEUX formulations précédentes étaient FAUSSES, et chacune l'a été pour une raison qui
	# mérite de rester écrite :
	#
	#  1ʳᵉ — angle horaire du contact du pouce autour de l'axe DU TUBE, comparé à la moyenne des
	#        doigts. Elle rougissait sur un pouce PARFAIT (0,47 mm) et verdissait sur un pouce
	#        resté à 20 mm en l'air : un contact qui n'a pas lieu a quand même une direction.
	#        **Un contrôle qu'un échec satisfait est pire que pas de contrôle du tout.**
	#  2ᵉ — « la racine du pouce est plus dorsale que celle des doigts ». Mesuré : c'est l'INVERSE
	#        (−9,0 mm contre −6,0 mm). Le métacarpe du pouce est plus PALMAIRE, pas moins. La
	#        prémisse anatomique était simplement fausse ; la mesure l'a dit tout de suite.
	#
	# La bonne propriété a été MESURÉE sur les six poses, pas devinée. Bout du pouce en X local
	# (compté vers l'extérieur depuis sa racine, donc valable pour les deux mains) :
	#     grip +82,4 · wrap +98,1 · cup +107,7 · open +92,5 · pinch +52,1 mm  → il reste
	#       de SON côté : le poing tenu à côté de l'arme.
	#     clamp **−16,8 mm** → il a franchi l'axe médian : il est passé PAR-DESSUS et redescend
	#       de l'autre bord. C'est la prise en C, et c'est la seule.
	# Un contrôle à DEUX FACES : il ne suffit pas que le C-clamp croise, il faut qu'aucune autre
	# pose ne croise — sinon la distinction ne distinguerait rien.
	var fautes_pouce := []
	for side in [-1.0, 1.0]:
		for cle in TrenchHands.HAND_POSES:
			var a := _bras(side, {"pose": cle})
			a.set_pose(cle)
			var mx: Transform3D = a.hand_inner.transform
			var dehors: float = signf((mx * a.thumb_root.transform).origin.x)
			var bout: Vector3 = a._joint_point(mx * a.thumb_root.transform, a.thumb_joints, 1,
				Vector3(0, 0, -TrenchHands.THUMB_L1 * a.scale_f))
			var franchit := bout.x * dehors < 0.0
			if franchit != (cle == "clamp"):
				fautes_pouce.append("cote %d / %s : x=%+.1f mm (franchit=%s)"
					% [int(side), cle, bout.x * dehors * 1000.0, franchit])
	_ok("F2 le C-clamp est la SEULE pose ou le pouce franchit l'axe de la main (pas un poing)",
		fautes_pouce.is_empty(), "fautes : " + str(fautes_pouce))

	# ── F3. LA POSE AJUSTÉE EST MÉMORISÉE SOUS SA PROPRE CLÉ ──────────────────────────────────
	# « a clip that swaps the support hand to 'open' and back to 'clamp' restores the FITTED clamp,
	# not the authored one. » On le vérifie : après un aller-retour, les flexions doivent être
	# celles du solveur, PAS celles écrites à la main.
	_ok("F3a la pose ajustee est bien mise en cache sous sa cle",
		arm.poses.has("clamp"), "cles en cache : " + str(arm.poses.keys()))
	var apres_fit := []
	for j in 3:
		apres_fit.append(arm.fingers[1][j].rotation.x)
	arm.set_pose("open")
	arm.set_pose("clamp")
	var identiques := true
	for j in 3:
		if absf(arm.fingers[1][j].rotation.x - float(apres_fit[j])) > 1e-9:
			identiques = false
	var ecrite: Array = TrenchHands.HAND_POSES["clamp"]["fingers"][1]
	var vaut_ecrite := absf(-arm.fingers[1][0].rotation.x - float(ecrite[0])) < 1e-9
	_ok("F3b l'aller-retour open->clamp restaure la pose AJUSTEE, pas celle ecrite a la main",
		identiques and not vaut_ecrite,
		"restauree a l'identique : %s · vaut la pose ecrite : %s"
			% [str(identiques), str(vaut_ecrite)])
