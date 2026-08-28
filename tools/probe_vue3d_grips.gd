extends Node

# =================================================================================================
# SONDE §8.152 — LA PRISE RÉELLE : LA MAIN DE SOUTIEN SUR LE VRAI GARDE-MAIN
#
# ╔═ POURQUOI CETTE SONDE EXISTE ════════════════════════════════════════════════════════════════╗
# ║ Le lot 3D-D a livré le solveur de contact avec un DÉFAUT OUVERT et chiffré : porté fidèlement,║
# ║ il enfonce la pulpe du majeur et de l'annulaire dans le garde-main sur presque toute la plage ║
# ║ de serrage, et ne tient la tolérance de 1,5 mm de la référence qu'entre 15 et 19 mm de jeu.   ║
# ║                                                                                               ║
# ║ Sa sonde ne pouvait pas trancher : la pose de main y était **inventée**. Ici elle ne l'est    ║
# ║ plus — `gripL` et `handguard` sortent du modèle d'arme réel, exactement comme leur            ║
# ║ `_fitSupportHand` les lit. C'est donc ICI que la question « le défaut mord-il pour de vrai ? »║
# ║ reçoit une réponse, arme par arme, et le lot 3D-F pourra s'y appuyer plutôt que de deviner.   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_vue3d_grips.tscn
#             --quit-after 1500
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. décaler `gripL.pos` d'un centimètre vers le tube                 -> G1 (jeu hors plage)
#  2. inverser le produit vectoriel de `hand_basis` (main gauchère)    -> G2 (paume à l'envers)
#  3. supprimer l'orthogonalisation de `back` dans `hand_basis`        -> G3 (repère cisaillé)
#  4. faire pointer `gripL.finger` le long de l'axe du tube            -> G4 (les doigts longent l'âme)
# =================================================================================================

const Weapons := preload("res://scripts/game/trench_weapons3d.gd")
const Hands := preload("res://scripts/game/trench_hands.gd")

const CHECKS_ATTENDUS := 5

var _fails: Array = []
var _joues := 0


func _ok(nom: String, cond: bool, detail := "") -> void:
	_joues += 1
	if cond:
		print("  [OK]   %s   | %s" % [nom, detail])
	else:
		_fails.append(nom)
		print("  [ROUGE] %s   | %s" % [nom, detail])


func _ready() -> void:
	print("\n=== SONDE 8.152 — LA PRISE REELLE SUR LE GARDE-MAIN ===\n")
	var jeux := {}
	var fautes_repere := []
	var fautes_ortho := []
	var fautes_axe := []
	var fautes_contact := []
	var lignes := []

	for id in Weapons.WEAPON_IDS:
		var m: Dictionary = Weapons.build(id)
		var n: Dictionary = m["nodes"]
		# Le pistolet n'a pas de garde-main : chez eux `_fitSupportHand` s'arrête tout de suite
		# (`if (... || w.id === 'pistol') return;`). Sa main d'appui est en COUPE, pas en C.
		if not n.has("handguard"):
			lignes.append("%s : aucun noeud `handguard` — comme chez eux (le pistolet tient a deux mains en coupe, le PM par sa poignee verticale) : hors sujet" % id)
			continue
		var hg: Dictionary = n["handguard"]
		var gl: Dictionary = n["gripL"]
		var pos: Vector3 = gl["pos"]
		var finger: Vector3 = gl["finger"]
		var back: Vector3 = gl["back"]
		var q := TrenchHands.hand_basis(finger, back)
		var b := Basis(q)

		# ── G1. LE JEU RÉEL À LA LIGNE DES JOINTURES ─────────────────────────────────────────
		# 🩸 PREMIÈRE VERSION FAUSSE, et l'erreur méritait d'être faite : elle mesurait le jeu au
		# POIGNET et trouvait **72,9 mm**, ce qui aurait pu passer pour « la main flotte à 7 cm ».
		# Elle mesurait simplement la mauvaise grandeur. La référence est explicite : « `pos =
		# contact - 0.098 * finger` (**targets are WRISTS**) » — le poignet est à 98 mm derrière
		# les jointures, par construction. Le nombre qui décrit la prise est celui des JOINTURES.
		#
		# Et ce nombre, la référence le donne : « the knuckle line **14.5 mm** off the surface »,
		# puis « The wrist target is **8 mm CLOSER** to the tube than the derivation above gives
		# (14.5 mm of knuckle standoff -> **6.5 mm**) ». Le déplacement est MESURÉ et assumé : à
		# 14,5 mm « the four fingertips landed 0.4-0.7 mm off the handguard — a real grip — but the
		# PALM stood 29 mm clear of it », c'est-à-dire une main posée À CÔTÉ du garde-main avec du
		# jour derrière. Ils ont donc choisi 6,5 mm, en acceptant que le talon de la paume
		# **traverse le tube de ~9 mm** — « which is what a glove does when it is squeezing
		# something ». ⚠️ Une interpénétration n'est donc PAS un défaut en soi ici : c'est une
		# DÉCISION, sur la paume. Ce qui doit rester propre, ce sont les CONTACTS DE PULPE.
		var axe: Vector3 = (hg["dir"] as Vector3).normalized()
		var jointures: Vector3 = pos + finger.normalized() * 0.098
		var d: Vector3 = jointures - (hg["axis"] as Vector3)
		d -= axe * d.dot(axe)
		var jeu: float = d.length() - float(hg["r"])
		jeux[id] = jeu

		# ── G2. LA PAUME REGARDE LE TUBE ──────────────────────────────────────────────────────
		# Les doigts s'enroulent vers le −Y local (côté palmaire, cf. `FINGER_SPECS`). Pour que la
		# main SERRE le tube et ne lui tourne pas le dos, ce −Y doit pointer vers l'axe.
		var vers_axe := (-d).normalized()
		var paume := -b.y
		var cos_paume := paume.dot(vers_axe)
		if cos_paume < 0.25:
			fautes_repere.append("%s : cos(paume, axe) = %.3f" % [id, cos_paume])

		# ── G3. ⭐ LE REPÈRE RESPECTE LES DEUX DIRECTIONS ÉCRITES ────────────────────────────
		# 🩸 PREMIÈRE VERSION : UN CONTRÔLE QUI NE POUVAIT PAS ÉCHOUER. Elle vérifiait que la base
		# rendue est orthonormée… en la relisant depuis le quaternion. Or `Basis.get_rotation_
		# quaternion()` **orthonormalise lui-même** : la base relue l'est TOUJOURS, quelle qu'ait
		# été l'entrée. Le sabotage qui supprime le Gram-Schmidt de `hand_basis` la laissait donc
		# VERTE. Elle mesurait la conversion de Godot, pas notre code.
		#
		# Le vrai contrat, lui, est falsifiable, et il tient en deux égalités :
		#   • le −Z de la main EST la direction des doigts écrite dans le modèle ;
		#   • le +Y de la main EST la composante de `back` orthogonale à cet axe.
		# Sans le Gram-Schmidt, l'orthonormalisation de secours de Godot part de X et **déplace Z**
		# pour rattraper : les doigts ne pointent plus où le modèle le dit, et ça se mesure.
		var attendu_y := (back - (-finger.normalized()) * back.dot(-finger.normalized())).normalized()
		var err := maxf((-b.z - finger.normalized()).length(), (b.y - attendu_y).length())
		if err > 1e-6:
			# ⚠️ Pas de `%e` : GDScript ne connaît pas ce spécificateur et rend le GABARIT BRUT au
				# lieu du nombre — le contrôle rougit bien, mais son message ne dit plus rien.
				fautes_ortho.append("%s : ecart %.4f mm" % [id, err * 1000.0])

		# ── G4. LES DOIGTS TRAVERSENT L'AXE, ILS NE LE LONGENT PAS ───────────────────────────
		# 🩸 C'est le défaut qui a coûté le plus cher au lot 3D-D : la pose d'essai inventée avait
		# les doigts PARALLÈLES à l'axe du tube. Ils pouvaient s'en approcher, jamais l'envelopper,
		# et les 5 mm de jour observés étaient un artefact de la POSE, pas du solveur. Une prise
		# n'existe que si la direction des doigts a une composante franche en travers de l'âme.
		var le_long := absf(finger.normalized().dot(axe))
		if le_long > 0.5:
			fautes_axe.append("%s : |cos(doigts, axe)| = %.3f" % [id, le_long])

		# ── G5. ⭐⭐ LE SOLVEUR SUR LA VRAIE GÉOMÉTRIE ────────────────────────────────────────
		# La question que le lot 3D-D a laissée ouverte, posée là où elle a un sens. Leur chiffre
		# de référence est net : « the four fingertips landed **0.4-0.7 mm** off the handguard — a
		# real grip ». On accepte 3 mm : au-delà, c'est le défaut « detached grey slabs with
		# daylight between them and the handguard » qu'ils décrivent.
		var bras = TrenchHands.Arm.new(-1.0, {"pose": "clamp"})
		add_child(bras.root)
		var contacts: Array = bras.fit_to_cylinder(pos, q, hg["axis"], hg["dir"],
			float(hg["r"]), {"clearance": 0.001, "poseName": "clamp:" + str(id)})
		var pires := []
		var pire_doigt := 0.0
		for k in contacts.size():
			var pc: Vector3 = contacts[k]
			var dk: Vector3 = pc - (hg["axis"] as Vector3)
			dk -= axe * dk.dot(axe)
			var e: float = dk.length() - float(hg["r"])
			pires.append("%+.1f" % (e * 1000.0))
			if k < 4:
				pire_doigt = maxf(pire_doigt, absf(e))
		if pire_doigt > 0.003:
			fautes_contact.append("%s : pire pulpe %.1f mm" % [id, pire_doigt * 1000.0])
		bras.root.queue_free()

		lignes.append("%s : jointures a %4.1f mm · cos(paume,axe) %+.3f · contacts (mm) %s"
			% [id, jeu * 1000.0, cos_paume, " ".join(pires)])

	for l in lignes:
		print("     " + l)
	print("")

	# La plage où le solveur du lot 3D-D tient la tolérance de 1,5 mm de la référence. Bornes
	# MESURÉES (table du §8.152.4), pas choisies : propre à 16 et 18 mm, hors tolérance dès 14 et
	# dès 20. On garde une demi-marge de chaque côté.
	# La référence pose son point de fonctionnement à **6,5 mm** aux jointures, après un
	# déplacement mesuré de 8 mm depuis 14,5. On accepte 4 à 16 mm : assez large pour ne pas
	# figer un réglage esthétique, assez étroit pour attraper une prise qui décolle ou qui
	# traverse. ⚠️ Ce contrôle borne la POSE ÉCRITE ; c'est G5 qui juge le RÉSULTAT.
	var hors := []
	for id in jeux:
		var j: float = float(jeux[id])
		if j < 0.004 or j > 0.016:
			hors.append("%s : %.1f mm" % [id, j * 1000.0])
	_ok("G1 la ligne des jointures est a 4-16 mm de la surface (leur point : 6,5 mm)",
		hors.is_empty() and not jeux.is_empty(),
		"hors plage : %s · %d arme(s) mesuree(s)" % [str(hors), jeux.size()])
	_ok("G2 la paume regarde le tube sur chaque arme (elle ne lui tourne pas le dos)",
		fautes_repere.is_empty(), "fautes : " + str(fautes_repere))
	_ok("G3 le repere respecte les deux directions ecrites (doigts en -Z, dos en +Y)",
		fautes_ortho.is_empty(), "fautes : " + str(fautes_ortho))
	_ok("G5 les PULPES se posent sur le vrai garde-main (leur repere : 0,4-0,7 mm ; seuil 3 mm)",
		fautes_contact.is_empty(), "fautes : " + str(fautes_contact))
	_ok("G4 les doigts TRAVERSENT l'axe du tube, ils ne le longent pas",
		fautes_axe.is_empty(), "fautes : " + str(fautes_axe))

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
