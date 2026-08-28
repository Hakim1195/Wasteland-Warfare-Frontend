extends Node

# =================================================================================================
# SONDE §8.152 LOT 3D-C — LES MATÉRIAUX D'ARME et LE MASQUE D'USURE D'ARÊTE.
#
# ╔═ CE QU'ELLE PEUT PROUVER, ET CE QU'ELLE NE PEUT PAS ══════════════════════════════════════════╗
# ║ ⛔ ELLE NE JUGE PAS LE RENDU. Aucun contrôle ici ne dit « c'est joli » ni « c'est fidèle » :   ║
# ║ le cahier §2.2quater tranche la ressemblance PAR CAPTURES, et les 9 captures de référence ne   ║
# ║ sont **pas encore déposées** dans `assets/reference/claude_of_duty/`. Prétendre valider        ║
# ║ l'apparence sans elles serait exactement la faute que le cahier interdit.                      ║
# ║                                                                                                ║
# ║ ✅ CE QU'ELLE PROUVE, ET QUI SE VÉRIFIE SANS AUCUNE IMAGE :                                    ║
# ║   M1 le registre est COMPLET et bien formé (toutes les clés attendues, tous les champs) ;      ║
# ║   M2 les TROIS CLASSES existent vraiment et sont SÉPARÉES EN TEINTE — la seule chose que       ║
# ║      leur commentaire interdit d'« harmoniser », et qui se mesure objectivement ;              ║
# ║   M3 l'anodisation n'est PAS métallique (le « single biggest mistake available on a gun ») ;   ║
# ║   M4 `cavity` n'a AUCUN lobe spéculaire (specular == 0), la raison d'être de ce matériau ;     ║
# ║   M5 l'astuce d'usure est ARITHMÉTIQUEMENT VALIDE : l'usure est toujours ≥ la base, donc la    ║
# ║      couleur de sommet reste dans [0, 1] — si elle ne l'était pas, l'usure serait écrêtée en   ║
# ║      silence et personne ne le verrait ;                                                       ║
# ║   C1 le MASQUE DE COURBURE trouve réellement les arêtes : sur une boîte chanfreinée, les       ║
# ║      sommets du chanfrein ont un masque STRICTEMENT SUPÉRIEUR à ceux du plat. C'est le seul    ║
# ║      contrôle « visuel » qui se mesure en nombres, et c'est le cœur du lot.                    ║
# ║   C2 le masque est NUL sur une surface sans arête convexe (l'intérieur d'un tube).             ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
#
# SABOTAGES QUI DOIVENT LA FAIRE ROUGIR :
#   1. donner `metallic = 1.0` à `alu`                              -> M3 rouge.
#   2. mettre `specular` de `cavity` à 0.5                          -> M4 rouge.
#   3. rendre la teinte de `polymer_tan` aussi froide que `alu`     -> M2 rouge.
#   4. neutraliser `bake_curvature` (masque constant)               -> C1 rouge.
#   5. rendre `wear_color` de `alu` plus SOMBRE que son albédo      -> M5 rouge.
#
# ⚠️ LANCEMENT (headless — aucun rendu n'est nécessaire, on lit des ressources) :
#   & <godot_console> --headless --path frontend res://tools/probe_vue3d_materials.tscn
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")

# ⚠️ Compte d'EXÉCUTION (cf. la même garde dans `probe_vue3d_meshgen`) : une sonde qui n'a rien
# joué doit rougir, pas se taire. À mettre à jour en ajoutant ou retirant un `_ok(...)`.
const CHECKS_ATTENDUS := 25

var _fails: Array = []
var _ran := 0


func _ok(label: String, cond: bool, detail := "") -> void:
	_ran += 1
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _info(label: String, detail: String) -> void:
	print("  [base] %s   | %s" % [label, detail])


func _ready() -> void:
	print("\n===== SONDE §8.152 LOT 3D-C — MATERIAUX + USURE D'ARETE =====\n")
	print("-- M. Le registre --")
	_probe_registre()
	print("\n-- M. Les trois classes et leur separation en teinte --")
	_probe_classes()
	print("\n-- M. Materiaux speciaux (cavite, optique, verre) --")
	_probe_speciaux()
	print("\n-- C. Le masque de courbure : trouve-t-il les aretes ? --")
	_probe_courbure()
	print("\n-- W. L'usure appliquee a un maillage reel --")
	_probe_usure()
	var complet := _ran == CHECKS_ATTENDUS
	if not complet:
		print("\n[ROUGE] SONDE INCOMPLETE : %d controles joues sur %d attendus."
			% [_ran, CHECKS_ATTENDUS])
	print("\n%s" % (("TOUT VERT (%d/%d controles joues)" % [_ran, CHECKS_ATTENDUS])
		if (_fails.is_empty() and complet)
		else ("ECHEC : %d rouge(s) sur %d joues (%d attendus) -> %s"
			% [_fails.size(), _ran, CHECKS_ATTENDUS, str(_fails)])))
	get_tree().quit(0 if (_fails.is_empty() and complet) else 1)


# =================================================================================================
# M. LE REGISTRE
# =================================================================================================
func _probe_registre() -> void:
	# M1a. Les clés que les lots 3D-A/3D-B/3D-D vont réellement demander. ⚠️ Cette liste vient de
	# ce que `parts.js`, `models/*.js` et `hands.js` utilisent — pas d'une recopie du registre :
	# un test qui relit le registre qu'il teste ne teste rien.
	var attendues := ["alu", "alu_fine", "steel", "steel_soot", "steel_bright", "steel_black",
		"polymer", "polymer_tan", "rubber", "brass", "copper",
		"glove", "glove_pad", "glove_seam", "sleeve",
		"cavity", "optic_tube", "glass", "lens_ring", "lens_vig"]
	var manquantes := []
	for k in attendues:
		if not WMat.has_key(k):
			manquantes.append(k)
	_ok("M1a toutes les cles consommees par la reference existent",
		manquantes.is_empty(), "manquantes : " + str(manquantes))

	# M1b. Chaque entrée du registre est BIEN FORMÉE. Un champ oublié se solderait par une erreur
	# d'exécution à la génération de la première arme, très loin d'ici.
	var champs := ["class", "albedo", "roughness", "metallic", "specular",
		"wear_color", "wear_amount"]
	var incompletes := []
	for k in WMat.SPECS:
		for c in champs:
			if not WMat.SPECS[k].has(c):
				incompletes.append("%s.%s" % [k, c])
	_ok("M1b chaque entree du registre porte les 7 champs attendus",
		incompletes.is_empty(), "manquants : " + str(incompletes))

	# M1c. Les valeurs sont dans leurs bornes physiques.
	var hors := []
	for k in WMat.SPECS:
		var s: Dictionary = WMat.SPECS[k]
		if float(s["roughness"]) < 0.0 or float(s["roughness"]) > 1.0:
			hors.append(k + ".roughness")
		if float(s["metallic"]) < 0.0 or float(s["metallic"]) > 1.0:
			hors.append(k + ".metallic")
		if float(s["wear_amount"]) < 0.0 or float(s["wear_amount"]) > 1.0:
			hors.append(k + ".wear_amount")
	_ok("M1c rugosite, metallicite et amplitude d'usure restent dans [0, 1]",
		hors.is_empty(), "hors bornes : " + str(hors))

	# M5. L'astuce d'usure de `get_worn` n'est valide QUE si l'usure est au moins aussi claire que
	# la base : la couleur de sommet ne sait que FONCER. Une entrée qui viole ça verrait son usure
	# ECRETEE EN SILENCE — le pire des défauts, celui qu'on ne voit pas.
	var sombres := []
	for k in WMat.SPECS:
		var s: Dictionary = WMat.SPECS[k]
		var base: Color = s["albedo"]
		var w: Color = s["wear_color"]
		if w.r < base.r or w.g < base.g or w.b < base.b:
			sombres.append("%s (base %.4f vs usure %.4f)" % [k, base.r, w.r])
	_ok("M5 l'usure est TOUJOURS au moins aussi claire que la base (sinon ecretage silencieux)",
		sombres.is_empty(), "fautives : " + str(sombres))


# =================================================================================================
# M. LES TROIS CLASSES
# =================================================================================================
func _probe_classes() -> void:
	var par_classe := {1: [], 2: [], 3: []}
	for k in WMat.SPECS:
		par_classe[int(WMat.SPECS[k]["class"])].append(k)
	_ok("M2a les trois classes sont toutes peuplees",
		not par_classe[1].is_empty() and not par_classe[2].is_empty()
			and not par_classe[3].is_empty(),
		"classe 1 : %d · classe 2 : %d · classe 3 : %d"
			% [par_classe[1].size(), par_classe[2].size(), par_classe[3].size()])

	# M3. L'anodisation N'EST PAS du metal. C'est la faute que leur commentaire designe comme
	# « the single biggest mistake available on a gun » : une surface metal brossee la ferait lire
	# comme du chrome poli.
	var fautes := []
	for k in par_classe[1]:
		if float(WMat.SPECS[k]["metallic"]) > 0.01:
			fautes.append(k)
	for k in par_classe[2]:
		if float(WMat.SPECS[k]["metallic"]) > 0.01:
			fautes.append(k)
	_ok("M3 classes 1 et 2 sont DIELECTRIQUES (l'anodisation est un oxyde, pas du metal nu)",
		fautes.is_empty(), "metalliques a tort : " + str(fautes))

	# Classe 3 : `metallic` haut. `steel_soot` est l'exception DOCUMENTEE (une poudre dielectrique
	# posee sur la phosphatation), on l'exclut explicitement plutot que d'assouplir le seuil.
	var mous := []
	for k in par_classe[3]:
		if k == "steel_soot":
			continue
		if float(WMat.SPECS[k]["metallic"]) < 0.99:
			mous.append(k)
	_ok("M3b classe 3 est METALLIQUE (sauf steel_soot, exception documentee)",
		mous.is_empty(), "pas assez metalliques : " + str(mous))

	# ── M2. LA SEPARATION EN TEINTE ────────────────────────────────────────────────────────────
	# Le controle qui compte. On mesure la teinte (rouge moins bleu, normalise) : la classe 1 doit
	# etre FROIDE (bleu > rouge) et la classe 2 CHAUDE (rouge > bleu). C'est le seul indice de
	# separation qui survit a une piece large de 40 px, et c'est mesurable sans aucune image.
	var alu: Color = WMat.SPECS["alu"]["albedo"]
	var tan: Color = WMat.SPECS["polymer_tan"]["albedo"]
	var poly: Color = WMat.SPECS["polymer"]["albedo"]
	var froideur_alu := (alu.b - alu.r) / maxf(alu.r + alu.b, 1e-9)
	var chaleur_tan := (tan.r - tan.b) / maxf(tan.r + tan.b, 1e-9)
	var chaleur_poly := (poly.r - poly.b) / maxf(poly.r + poly.b, 1e-9)
	_ok("M2b l'aluminium anodise est FROID (bleu > rouge)", froideur_alu > 0.02,
		"froideur %.4f" % froideur_alu)
	_ok("M2c les polymeres sont CHAUDS (rouge > bleu)",
		chaleur_tan > 0.02 and chaleur_poly > 0.02,
		"tan %.4f · polymere %.4f" % [chaleur_tan, chaleur_poly])
	# Et surtout : les deux familles doivent etre SEPAREES, pas juste chacune de son cote.
	_ok("M2d l'ecart de teinte entre les deux familles est franc",
		(chaleur_tan + froideur_alu) > 0.15,
		"ecart total %.4f (froideur alu + chaleur tan)" % (chaleur_tan + froideur_alu))

	# Les metaux non ferreux doivent rester reconnaissables : le laiton est nettement plus jaune
	# que l'acier, sinon une douille ejectee se confond avec la culasse.
	var brass: Color = WMat.SPECS["brass"]["albedo"]
	var steel: Color = WMat.SPECS["steel"]["albedo"]
	_ok("M2e le laiton est franchement plus jaune que l'acier",
		(brass.r - brass.b) > 0.3 and absf(steel.r - steel.b) < 0.1,
		"laiton R-B %.3f · acier R-B %.3f" % [brass.r - brass.b, steel.r - steel.b])


# =================================================================================================
# M. LES MATÉRIAUX SPÉCIAUX
# =================================================================================================
func _probe_speciaux() -> void:
	var lib := WMat.new()
	# M4. `cavity` : la RAISON D'ETRE de ce materiau est de n'avoir AUCUN lobe speculaire. La
	# reference a du changer de classe de materiau pour l'obtenir ; Godot le donne nativement.
	var cav := lib.get_material("cavity")
	_ok("M4 `cavity` n'a aucun lobe speculaire, est mate et quasi noir",
		cav.metallic_specular == 0.0 and cav.roughness >= 0.99 and cav.albedo_color.r < 0.02,
		"specular %.3f · roughness %.3f · albedo %.4f"
			% [cav.metallic_specular, cav.roughness, cav.albedo_color.r])

	var glass := lib.get_material("glass")
	_ok("M6 le verre d'optique est transparent, tres lisse et PEU absorbant",
		glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
			and glass.roughness < 0.1
			and glass.albedo_color.a <= 0.15,
		"opacite %.3f (au-dela de 0.3 la lunette lit comme un verre fume) · roughness %.3f"
			% [glass.albedo_color.a, glass.roughness])

	var ring := lib.get_material("lens_ring")
	_ok("M7 l'anneau de lentille est ADDITIF, non eclaire, et n'ecrit pas dans la profondeur",
		ring.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
			and ring.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and ring.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED)

	var vig := lib.get_material("lens_vig")
	_ok("M8 la vignette de lentille porte bien une rampe RADIALE generee",
		vig.albedo_texture != null and vig.albedo_texture is GradientTexture2D
			and vig.albedo_texture.fill == GradientTexture2D.FILL_RADIAL)

	# Le cache doit rendre la MEME instance : sans ca, chaque piece d'arme creerait son propre
	# materiau et le nombre d'appels de dessin exploserait.
	_ok("M9 le cache rend la meme instance pour la meme cle",
		lib.get_material("alu") == lib.get_material("alu")
			and lib.get_material("alu") != lib.get_worn("alu"))

	# Une cle inconnue doit rendre un repli VISIBLE (magenta), pas une piece noire discrete.
	var inconnu := lib.get_material("_cle_qui_n_existe_pas_")
	_ok("M10 une cle inconnue rend un repli VISIBLE (magenta), pas un noir discret",
		inconnu.albedo_color.r > 0.9 and inconnu.albedo_color.b > 0.9
			and inconnu.albedo_color.g < 0.1)


# =================================================================================================
# C. LE MASQUE DE COURBURE — le cœur du lot
# =================================================================================================
func _probe_courbure() -> void:
	# Une boite CHANFREINEE : ses 12 aretes et 8 coins sont convexes, ses 6 faces sont plates.
	# Le masque doit distinguer les deux. Si ce controle est vert, l'usure d'arete a de quoi
	# s'accrocher ; s'il est rouge, toute l'arme sera uniformement mate quoi qu'on fasse ensuite.
	var g = Meshgen.box(0.03, 0.02, 0.05, 0.002, 3)
	g = Meshgen.merge_all([g])
	g.bake_curvature()
	_ok("C0 le masque est cuit pour chaque sommet",
		g.colors.size() == g.positions.size(),
		"%d couleurs pour %d sommets" % [g.colors.size(), g.positions.size()])

	# ── CLASSIFICATION PAR LA GÉOMÉTRIE, JAMAIS PAR LE MASQUE ──────────────────────────────────
	# Un test qui classerait les sommets d'après le masque qu'il mesure ne mesurerait rien. On les
	# classe donc par leur POSITION dans la construction : on ramène chaque sommet dans la boîte
	# INTÉRIEURE (demi-cotes moins le chanfrein) et on compte sur combien d'axes il en dépasse.
	#   0 ou 1 axe -> il est sur un MÉPLAT (le centre d'une face) ;
	#   2 axes     -> il est sur une ARÊTE (un quart de cylindre) ;
	#   3 axes     -> il est sur un COIN (un octant de sphère).
	# C'est exactement la construction de `box()`, donc une vérité indépendante du masque.
	var r := 0.002
	var inner := Vector3(0.03, 0.02, 0.05) * 0.5 - Vector3(r, r, r)
	var plats := []
	var aretes := []
	var coins := []
	for i in g.positions.size():
		var p: Vector3 = g.positions[i]
		var hors := 0
		for a in 3:
			if absf(p[a]) > inner[a] + 1e-6:
				hors += 1
		if hors <= 1:
			plats.append(g.colors[i].r)
		elif hors == 2:
			aretes.append(g.colors[i].r)
		else:
			coins.append(g.colors[i].r)
	var moy_plat := _moyenne(plats)
	var moy_arete := _moyenne(aretes)
	var moy_coin := _moyenne(coins)
	_ok("C1 le masque CROIT strictement du meplat vers l'arete puis vers le coin",
		plats.size() > 4 and aretes.size() > 4 and coins.size() > 4
			and moy_arete > moy_plat + 0.05 and moy_coin > moy_plat + 0.05,
		"meplat %.4f (%d) · arete %.4f (%d) · coin %.4f (%d)"
			% [moy_plat, plats.size(), moy_arete, aretes.size(), moy_coin, coins.size()])
	# Et le meplat doit vraiment etre BAS : un masque a 0,9 sur un meplat userait toute l'arme.
	_ok("C1c le meplat reste franchement bas (sinon l'usure couvre toute l'arme)",
		moy_plat < 0.35, "masque moyen sur les meplats %.4f" % moy_plat)
	_info("C1b etendue du masque", "min %.4f · max %.4f"
		% [_min_masque(g), _max_masque(g)])

	# C2. Une surface INTERIEURE (l'ame d'un tube) est concave : son masque doit rester bas.
	# Sinon l'usure viendrait eclaircir l'interieur du canon, ce qui est exactement l'inverse.
	var t = Meshgen.merge_all([Meshgen.tube_z(0.009, 0.0045, 0.06, 24)])
	t.bake_curvature()
	var interieur := []
	for i in t.positions.size():
		var p: Vector3 = t.positions[i]
		if Vector2(p.x, p.y).length() < 0.0055:
			interieur.append(t.colors[i].r)
	var moy_int := 0.0
	for v in interieur:
		moy_int += v
	moy_int /= maxf(1.0, interieur.size())
	_ok("C2 l'ame CONCAVE d'un tube garde un masque bas (l'usure n'entre pas dans le canon)",
		not interieur.is_empty() and moy_int < 0.35,
		"masque moyen interieur %.4f sur %d sommets" % [moy_int, interieur.size()])


func _moyenne(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func _min_masque(g) -> float:
	var v := 1.0
	for c in g.colors:
		v = minf(v, c.r)
	return v


func _max_masque(g) -> float:
	var v := 0.0
	for c in g.colors:
		v = maxf(v, c.r)
	return v


# =================================================================================================
# W. L'USURE APPLIQUÉE
# =================================================================================================
func _probe_usure() -> void:
	var lib := WMat.new()
	var g = Meshgen.merge_all([Meshgen.box(0.03, 0.02, 0.05, 0.002, 3)])
	var ok := WMat.apply_wear_mask(g, "alu")
	_ok("W1 apply_wear_mask accepte une cle du registre et cuit les couleurs",
		ok and g.colors.size() == g.positions.size())

	# Les couleurs de sommet doivent rester dans [0, 1] : c'est la condition de validite de
	# l'astuce (cf. `get_worn`). Un depassement serait ECRETE EN SILENCE par le moteur.
	var hors := 0
	var vu_clair := false
	var vu_sombre := false
	for c in g.colors:
		if c.r < 0.0 or c.r > 1.0 or c.g < 0.0 or c.g > 1.0 or c.b < 0.0 or c.b > 1.0:
			hors += 1
		if c.r > 0.95:
			vu_clair = true
		if c.r < 0.9:
			vu_sombre = true
	_ok("W2 les couleurs de sommet restent dans [0, 1] ET couvrent vraiment les deux extremes",
		hors == 0 and vu_clair and vu_sombre,
		"%d hors bornes · usure vue %s · base vue %s" % [hors, str(vu_clair), str(vu_sombre)])

	# Le materiau use doit LIRE la couleur de sommet — sans ce drapeau, tout le masque est ignore
	# et l'arme entiere prend la couleur d'usure : bien plus claire que voulu, partout.
	var m := lib.get_worn("alu")
	var m_nu := lib.get_material("alu")
	var spec: Dictionary = WMat.SPECS["alu"]
	_ok("W3 le materiau USE lit la couleur de sommet, et porte l'albedo d'USURE (pas de base)",
		m.vertex_color_use_as_albedo and not m_nu.vertex_color_use_as_albedo
			and m.albedo_color.r > spec["albedo"].r,
		"albedo use %.5f > albedo de base %.5f" % [m.albedo_color.r, spec["albedo"].r])

	# Une cle SANS usure (les optiques) doit etre refusee proprement, pas cuire un masque inutile.
	_ok("W4 une cle sans usure (materiau special) est refusee proprement",
		not WMat.apply_wear_mask(g, "glass"))
