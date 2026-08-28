extends Node

# =================================================================================================
# SONDE §8.152 LOT 3D-A + 3D-B2 — LE VOCABULAIRE DE PIÈCES D'ARMES.
#
# ╔═ CE QU'ELLE PROUVE — et le choix qui la rend utile ═══════════════════════════════════════════╗
# ║ Vérifier « la pièce n'est pas vide » ne prouve presque rien. Ce qui compte, ce sont les       ║
# ║ DÉFAUTS QUE LA RÉFÉRENCE A MESURÉS PUIS CORRIGÉS : chacun a coûté une passe de critique       ║
# ║ chez eux, chacun est invisible à la lecture du code, et chacun se re-briserait au premier     ║
# ║ « nettoyage » de constantes. La sonde les transforme en contrôles.                            ║
# ║                                                                                               ║
# ║   G1 GÉNÉRATION : chaque fonction produit de la géométrie, et elle est DÉTERMINISTE.          ║
# ║   G2 CONTRAT DE MATÉRIAUX : toute clé demandée par 3D-A existe dans le registre 3D-C. C'est   ║
# ║      le seul contrôle qui relie les deux lots — sans lui, une faute de frappe ne se verrait   ║
# ║      qu'à l'écran, en magenta, très loin d'ici.                                               ║
# ║   R1 LE FOND DES ENCOCHES DE RAIL EST EN `cavity` — « a rail read as a ladder of flat         ║
# ║      near-white bars instead of a row of cavities: THE SINGLE LOUDEST ARTEFACT on the whole   ║
# ║      weapon ».                                                                                ║
# ║   O1 LE MONTAGE D'OPTIQUE N'ENTRE JAMAIS DANS L'ALÉSAGE — sinon « a lit grey slab cut clean   ║
# ║      across the bottom third of the sight picture » en ADS.                                   ║
# ║   O2 L'ALÉSAGE EST ÉVASÉ vers l'objectif — le correctif du « drainpipe » : sans l'évasement,  ║
# ║      l'image utile tombe à 34 % du boîtier au lieu de 69 %.                                   ║
# ║   O3 L'ARRIÈRE DE L'OPTIQUE EST EN CAOUTCHOUC, pas en aluminium — le correctif de « l'anneau  ║
# ║      crème » : à 89° d'incidence, une surface d'alu s'allume quoi qu'on fasse au matériau.    ║
# ║   U1 LES DEUX BOUTS DE LA CARCASSE SONT FERMÉS — sinon on voit la culasse « flotter dans un   ║
# ║      tuyau noir » en visant.                                                                  ║
# ║   M1 LA CARTOUCHE DU CHARGEUR EST COUCHÉE LE LONG DE L'ARME, pas en travers — « rotated the   ║
# ║      other way it lances straight out through the mag's flank ».                              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# SABOTAGES QUI DOIVENT LA FAIRE ROUGIR :
#   1. `add_rail` : donner le fond d'encoche au matériau du rail au lieu de `cavity`  -> R1.
#   2. `build_optic` : remettre `mount_top = y - r_tube * 0.35`                       -> O1.
#   3. `build_optic` : rendre l'alésage droit (`r_bore_ob = r_bore_oc`)               -> O2.
#   4. `build_optic` : repasser le bandeau oculaire en `mat_body`                     -> O3.
#   5. `add_upper_receiver` : rouvrir un bout du tube (rayon final non nul)           -> U1.
#   6. `build_magazine` : retirer le `ry: PI` de la cartouche du haut                 -> M1.
#   7. une clé de matériau mal orthographiée n'importe où                             -> G2.
#
# ⚠️ LANCEMENT (headless suffit — on ne mesure que des tableaux de sommets) :
#   & <godot_console> --headless --path frontend res://tools/probe_vue3d_wparts.tscn
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const WParts := preload("res://scripts/game/trench_wparts.gd")

# ⚠️ Compte d'EXÉCUTION, pas un grep (cf. la même garde dans les deux autres sondes).
const CHECKS_ATTENDUS := 17

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
	print("\n===== SONDE §8.152 LOT 3D-A/3D-B2 — PIECES D'ARMES =====\n")
	print("-- G. Generation, determinisme, contrat de materiaux --")
	_probe_generation()
	print("\n-- R. Le rail Picatinny --")
	_probe_rail()
	print("\n-- O. L'optique point rouge (piece contractuelle §2.2bis C) --")
	_probe_optic()
	print("\n-- U. Les carcasses --")
	_probe_receivers()
	print("\n-- M. Le chargeur --")
	_probe_magazine()
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
# BANC : un assemblage par pièce, monté avec des cotes PLAUSIBLES mais INVENTÉES
# =================================================================================================
# ⚠️ Les cotes ci-dessous ne sont PAS celles des armes de `models/*.js`. C'est délibéré (leçon n°4
# du cahier : « une sonde dont les fixtures sont les valeurs de PRODUCTION ne prouve rien ») : si
# une fonction ne marchait que pour les nombres exacts du fusil, on veut le savoir ICI.
func _banc() -> Dictionary:
	var out := {}

	var a_rail = Meshgen.Assembly.new("rail")
	WParts.add_rail(a_rail, "alu", -0.09, 0.03, 0.11)
	out["add_rail"] = a_rail

	var a_barrel = Meshgen.Assembly.new("barrel")
	WParts.add_barrel(a_barrel, "steel", "cavity",
		{"y": 0.07, "zBreech": -0.11, "zMuzzle": -0.42, "rChamber": 0.0105,
		"rBarrel": 0.0071, "rGas": 0.0091, "gasAt": -0.29})
	out["add_barrel"] = a_barrel

	var a_gas = Meshgen.Assembly.new("gas")
	WParts.add_gas_block(a_gas, "steel_soot",
		{"y": 0.07, "z": -0.29, "rBarrel": 0.0071, "tubeTo": -0.14})
	out["add_gas_block"] = a_gas

	for kind in ["brake", "a2", "comp", "trilug"]:
		var a_mz = Meshgen.Assembly.new("muzzle_" + kind)
		WParts.add_muzzle_device(a_mz, "steel_soot", "cavity", kind, -0.42, 0.0071, 0.07)
		out["add_muzzle_device:" + kind] = a_mz

	var a_hg = Meshgen.Assembly.new("handguard")
	WParts.add_handguard(a_hg, "alu",
		{"matPanel": "polymer", "y": 0.07, "z0": -0.14, "z1": -0.37, "r": 0.0231,
		"sides": 8, "slatW": 0.0161, "slatT": 0.0035, "slots": 4, "braces": 3,
		"topFrom": -0.18, "topTo": -0.32})
	out["add_handguard"] = a_hg

	var a_up = Meshgen.Assembly.new("upper")
	WParts.add_upper_receiver(a_up, "alu", "steel", "cavity",
		{"zRear": 0.051, "zFront": -0.139, "bore": 0.071, "r": 0.0189,
		"portZ": -0.049, "railTop": 0.0999})
	out["add_upper_receiver"] = a_up

	var a_lo = Meshgen.Assembly.new("lower")
	WParts.add_lower_receiver(a_lo, "alu", "steel",
		{"bore": 0.071, "zRear": 0.055, "zFront": -0.084, "w": 0.0241,
		"magW": 0.0288, "magD": 0.0668, "magTop": 0.045, "magBottom": 0.004,
		"magZ": -0.054, "magTilt": 0.077, "triggerZ": -0.011, "gripAngle": 0.37})
	out["add_lower_receiver"] = a_lo

	var a_bolt = Meshgen.Assembly.new("bolt")
	WParts.add_bolt_carrier(a_bolt, "steel_bright", {"r": 0.0149, "len": 0.089, "z": 0.0})
	out["add_bolt_carrier"] = a_bolt

	var a_grip = Meshgen.Assembly.new("grip")
	WParts.add_pistol_grip(a_grip, "polymer", "rubber",
		{"y": 0.031, "z": 0.014, "angle": 0.37, "len": 0.105, "w": 0.0303})
	out["add_pistol_grip"] = a_grip

	var a_stock = Meshgen.Assembly.new("stock")
	WParts.add_carbine_stock(a_stock, "alu", "polymer", "rubber",
		{"bore": 0.071, "zFront": 0.054, "zRear": 0.239, "y": 0.059})
	out["add_carbine_stock"] = a_stock

	var a_mag = Meshgen.Assembly.new("mag")
	WParts.build_magazine(a_mag, null,
		{"w": 0.0251, "d": 0.0649, "len": 0.207, "curve": 0.029, "segs": 8, "witness": 4})
	out["build_magazine"] = a_mag

	var a_opt = Meshgen.Assembly.new("optic")
	WParts.build_optic(a_opt,
		{"rTube": 0.0151, "len": 0.0513, "hood": 0.0069, "y": 0.0, "z": 0.0,
		"railTop": -0.0387, "matBody": "alu_fine", "matSteel": "steel"})
	out["build_optic"] = a_opt

	var a_rm = Meshgen.Assembly.new("rollmark")
	WParts.add_rollmark(a_rm, "cavity", {"x": -0.0147, "y": 0.0351, "z": -0.029, "h": 0.0035})
	out["add_rollmark"] = a_rm

	var a_fs = Meshgen.Assembly.new("frontsight")
	WParts.add_front_sight(a_fs, "polymer", "alu", 0.0, 0.0999, -0.351, false)
	out["add_front_sight"] = a_fs

	var a_rs = Meshgen.Assembly.new("rearsight")
	WParts.add_rear_sight(a_rs, "polymer", "alu", 0.0, 0.0999, -0.109, false)
	out["add_rear_sight"] = a_rs

	var a_mr = Meshgen.Assembly.new("minireflex")
	WParts.build_mini_reflex(a_mr,
		{"w": 0.0243, "h": 0.0207, "len": 0.0451, "y": 0.0139, "z": 0.0137,
		"matBody": "alu_fine"})
	out["build_mini_reflex"] = a_mr

	var a_sl = Meshgen.Assembly.new("slide")
	WParts.build_slide(a_sl,
		{"w": 0.0259, "h": 0.0245, "len": 0.181, "mat": "steel_black", "zRear": 0.0513})
	out["build_slide"] = a_sl

	var a_fg = Meshgen.Assembly.new("foregrip")
	WParts.add_fore_grip(a_fg, "polymer", "rubber",
		{"y": 0.0441, "z": -0.205, "angle": 0.19, "len": 0.0571})
	out["add_fore_grip"] = a_fg

	var a_qd = Meshgen.Assembly.new("qd")
	WParts.add_qd_socket(a_qd, "alu", "steel", -0.0177, 0.0611, -0.134, "x", 0.0044)
	WParts.add_sling_loop(a_qd, "steel", 0.0163, 0.0451, 0.0871, 0.0069, {"ry": PI * 0.5})
	WParts.add_pin(a_qd, "steel", 0.0, 0.0591, 0.0751, 0.0029, 0.0271)
	WParts.add_screw(a_qd, "steel", 0.0, 0.0511, 0.0211, 0.0023, "y", 0.0071)
	out["petite_visserie"] = a_qd

	return out


func _probe_generation() -> void:
	var banc := _banc()
	var vides := []
	var total := 0
	var lignes := []
	for k in banc:
		var n: int = banc[k].total_tris()
		total += n
		lignes.append("%s=%d" % [k, n])
		if n == 0:
			vides.append(k)
	_ok("G1a chaque fonction de parts.js produit de la geometrie",
		vides.is_empty(), "vides : " + str(vides))
	_info("G1b budget triangles par piece", " · ".join(lignes))
	_info("G1c total du banc", "%d triangles" % total)

	# G2. LE CONTRAT ENTRE 3D-A ET 3D-C. Une clé mal orthographiée ici ne se verrait qu'à l'écran,
	# en magenta, très loin de sa cause.
	var cles := {}
	for k in banc:
		for m in banc[k].buckets:
			cles[m] = true
	var inconnues := []
	for m in cles:
		if not WMat.has_key(m):
			inconnues.append(m)
	_ok("G2 toutes les cles de materiau demandees existent dans le registre 3D-C",
		inconnues.is_empty(),
		"%d cles utilisees : %s · inconnues : %s"
			% [cles.size(), str(cles.keys()), str(inconnues)])

	# G3. DÉTERMINISME : deux montages successifs rendent des sommets identiques. Sans ça, deux
	# captures du même plan diffèrent et toute comparaison avec les références de Hakim est vaine.
	var banc2 := _banc()
	var divergent := ""
	for k in banc:
		var a = _fusion(banc[k])
		var b = _fusion(banc2[k])
		if a == null or b == null:
			continue
		if a.positions != b.positions or a.normals != b.normals or a.indices != b.indices:
			divergent = k
			break
	_ok("G3 determinisme : deux montages rendent des sommets identiques",
		divergent == "", "premiere divergence : " + divergent)


# Fusionne tous les seaux d'un assemblage en une seule pièce (pour les mesures globales).
func _fusion(asm):
	var tout := []
	for m in asm.buckets:
		for g in asm.buckets[m]:
			tout.append(g)
	return Meshgen.merge_all(tout)


# =================================================================================================
# R. LE RAIL
# =================================================================================================
func _probe_rail() -> void:
	var asm = Meshgen.Assembly.new("rail")
	WParts.add_rail(asm, "alu", -0.09, 0.03, 0.11)
	# R1. Le fond des encoches doit être dans le seau `cavity`, et NULLE PART ailleurs.
	_ok("R1 le fond des encoches de rail est bien en `cavity` (et non dans l'alu du rail)",
		asm.buckets.has("cavity") and asm.buckets.has("alu")
			and not asm.buckets["cavity"].is_empty(),
		"seaux : " + str(asm.buckets.keys()))

	# ⚠️ R2 et R3 lisent des seaux que le SABOTAGE de R1 fait disparaître. Une sonde qui plante à
	# ce moment-là perd le signal qu'elle venait de produire : on dégrade proprement, et le garde
	# de « contrôles joués » signalera de toute façon les contrôles manquants.
	if not (asm.buckets.has("cavity") and asm.buckets.has("alu")):
		_ok("R2 le fond d'encoche reste SOUS la crete du rail — NON MESURABLE (seau manquant)", false)
		_ok("R3 le chanfrein de crete survit a add_rail — NON MESURABLE (seau manquant)", false)
		return

	# R2. Le fond est SOUS la crête et AU-DESSUS de la base : s'il dépassait, il serait visible
	# partout au lieu d'être occulté par les dents.
	var cav = Meshgen.merge_all(asm.buckets["cavity"])
	var rail = Meshgen.merge_all(asm.buckets["alu"])
	var b_cav: AABB = cav.aabb()
	var b_rail: AABB = rail.aabb()
	var crete := b_rail.position.y + b_rail.size.y
	var sommet_cav := b_cav.position.y + b_cav.size.y
	_ok("R2 le fond d'encoche reste SOUS la crete du rail (sinon il n'est plus occulte)",
		sommet_cav < crete - 0.001 and b_cav.position.y > b_rail.position.y,
		"crete rail %.4f m · sommet du fond %.4f m" % [crete, sommet_cav])

	# R3. Le rail respecte le chanfrein de crête du lot 3D-0 (largeur au sommet < largeur max).
	var x_max := 0.0
	var y_max := -INF
	for p in rail.positions:
		x_max = maxf(x_max, absf(p.x))
		y_max = maxf(y_max, p.y)
	var x_crete := 0.0
	for p in rail.positions:
		if p.y > y_max - 1e-6:
			x_crete = maxf(x_crete, absf(p.x))
	_ok("R3 le chanfrein de crete survit au passage par add_rail",
		x_crete < x_max - 0.001,
		"demi-largeur au sommet %.5f m · demi-largeur max %.5f m" % [x_crete, x_max])


# =================================================================================================
# O. L'OPTIQUE — les trois défauts que la référence a mesurés puis corrigés
# =================================================================================================
func _probe_optic() -> void:
	var r_tube := 0.0151
	var length := 0.0513
	var rail_top := -0.0387
	var asm = Meshgen.Assembly.new("optic")
	var info: Dictionary = WParts.build_optic(asm, {
		"rTube": r_tube, "len": length, "hood": 0.0069, "y": 0.0, "z": 0.0,
		"railTop": rail_top, "matBody": "alu_fine", "matSteel": "steel",
	})
	var r_bore_oc := r_tube * 0.787
	var z_oc := length * 0.5

	# ── O1. LE MONTAGE N'ENTRE JAMAIS DANS L'ALÉSAGE ────────────────────────────────────────────
	# `mountTop` est TANGENT à la paroi du tube. Il valait `y − rTube*0,35`, ce qui mettait la face
	# du pied 5 mm AU-DESSUS du plancher de l'alésage : en ADS, une dalle grise éclairée coupait
	# net le tiers inférieur de l'image. On mesure donc le rayon MINIMAL de tout ce qui est dans le
	# matériau du corps, sur la longueur du tube : rien ne doit descendre sous l'alésage.
	var corps = Meshgen.merge_all(asm.buckets["alu_fine"])
	var r_min := INF
	for p in corps.positions:
		if absf(p.z) < z_oc - 0.002:
			r_min = minf(r_min, Vector2(p.x, p.y).length())
	_ok("O1 rien du corps de l'optique n'entre dans l'alesage (la dalle grise en ADS)",
		r_min > r_bore_oc * 0.95,
		"rayon min du corps %.5f m · plancher d'alesage %.5f m" % [r_min, r_bore_oc])

	# ── O2. L'ALÉSAGE EST ÉVASÉ vers l'objectif — le correctif du « tuyau de descente » ──────────
	# Le cône visible est le PLUS PETIT de deux : l'oculaire vu au dégagement d'œil, et l'objectif
	# vu à (dégagement + longueur). Un alésage DROIT laisse l'objectif gagner d'un facteur 1,8 et
	# l'image tombe à 34 % du boîtier. On vérifie l'évasement sur la géométrie du piège à lumière,
	# qui épouse l'alésage.
	# ╔═ ⚠️ CE CONTRÔLE A ÉTÉ VERT POUR LA MAUVAISE RAISON — deux fois ══════════════════════════╗
	# ║ 1ᵉʳ jet : « rayon MAX pour z < −0,3·len ». Le sabotage « alésage droit » passait au VERT,  ║
	# ║   parce que le seau `optic_tube` contient AUSSI la doublure du pare-soleil, montée sur la  ║
	# ║   cloche (1,23 rTube) devant l'objectif : la fenêtre mesurait ELLE, jamais l'alésage.      ║
	# ║ 2ᵉ jet : fenêtres resserrées, mais le piège à lumière n'a de sommets QU'À DEUX COTES Z     ║
	# ║   exactes (son profil n'a que 4 points, sur 2 valeurs de z) — les fenêtres tombaient entre ║
	# ║   les deux et ne trouvaient rien du tout.                                                  ║
	# ║ 3ᵉ jet, celui-ci : on vise les DEUX COTES EXACTES du profil, et on prend le rayon MINIMAL. ║
	# ║   Le pare-soleil chevauche bien la cote avant, mais il est plus LARGE que l'alésage — le    ║
	# ║   minimum l'écarte par construction.                                                       ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var trap = Meshgen.merge_all(asm.buckets["optic_tube"])
	var z_ob := -length * 0.5
	var r_avant := INF
	var r_arriere := INF
	for p in trap.positions:
		var r := Vector2(p.x, p.y).length()
		if absf(p.z - (z_ob + 0.001)) < 0.0004:
			r_avant = minf(r_avant, r)
		elif absf(p.z - (z_oc - 0.009)) < 0.0004:
			r_arriere = minf(r_arriere, r)
	_ok("O2 l'alesage s'EVASE vers l'objectif (sinon l'image ADS tombe a un tiers du boitier)",
		r_avant > r_arriere * 1.15,
		"alesage objectif %.5f m vs oculaire %.5f m (rapport %.3f)"
			% [r_avant, r_arriere, r_avant / maxf(r_arriere, 1e-9)])

	# ── O3. L'ARRIÈRE DE L'OPTIQUE EST EN CAOUTCHOUC ────────────────────────────────────────────
	# MESURÉ chez eux : la bande chaude et vive de « l'anneau crème » était le chanfrein arrière et
	# le flanc, à 1,00-1,05 rTube. Ce n'est pas de l'albédo — c'est le lobe RASANT. Tant que c'est
	# de l'ALUMINIUM que l'œil regarde à 89°, quelque chose s'allume. D'où : le bandeau caoutchouc
	# doit être la surface la plus EXTÉRIEURE de tout l'arrière de la lunette.
	var caout = Meshgen.merge_all(asm.buckets["rubber"])
	var r_caout := 0.0
	var r_corps_arriere := 0.0
	for p in caout.positions:
		if p.z > z_oc - 0.008:
			r_caout = maxf(r_caout, Vector2(p.x, p.y).length())
	for p in corps.positions:
		if p.z > z_oc - 0.008:
			r_corps_arriere = maxf(r_corps_arriere, Vector2(p.x, p.y).length())
	_ok("O3 le bandeau CAOUTCHOUC est la surface la plus exterieure a l'arriere de l'optique",
		r_caout > r_corps_arriere,
		"caoutchouc %.5f m vs corps %.5f m (rTube = %.5f)"
			% [r_caout, r_corps_arriere, r_tube])

	# O4. Les données rendues au rig sont cohérentes : l'ouverture est sous l'alésage oculaire, et
	# le plan de lentille est dans le tube.
	_ok("O4 build_optic rend une ouverture et un plan de lentille coherents",
		float(info["apertureR"]) > 0.0 and float(info["apertureR"]) < r_bore_oc
			and absf(float(info["lensZ"])) < z_oc,
		"apertureR %.5f m · lensZ %.5f m · tubeR %.5f m"
			% [info["apertureR"], info["lensZ"], info["tubeR"]])

	# O5. Le verre et le halo existent : ce sont eux qui disent « il y a du VERRE dans ce tube ».
	_ok("O5 le verre, le halo de lentille et le vignettage sont tous presents",
		asm.buckets.has("glass") and asm.buckets.has("lens_ring")
			and asm.buckets.has("lens_vig"),
		"seaux : " + str(asm.buckets.keys()))


# =================================================================================================
# U. LES CARCASSES
# =================================================================================================
func _probe_receivers() -> void:
	var bore := 0.071
	var r := 0.0189
	var asm = Meshgen.Assembly.new("upper")
	WParts.add_upper_receiver(asm, "alu", "steel", "cavity",
		{"zRear": 0.051, "zFront": -0.139, "bore": bore, "r": r,
		"portZ": -0.049, "railTop": 0.0999})

	# ── U1. LES DEUX BOUTS SONT FERMÉS ──────────────────────────────────────────────────────────
	# « An annular end face leaves a 19 mm hole straight down the receiver, and in ADS the eye is
	# 0.2 m behind it looking right in: you see the BOLT CARRIER and the CHAMBERED ROUND floating
	# in a black pipe. » On le mesure : aux deux extrémités du tube, il doit exister des sommets
	# TRÈS PROCHES de l'axe — c'est la signature d'un bout refermé sur lui-même.
	var corps = Meshgen.merge_all(asm.buckets["alu"])
	# ⚠️ ON MESURE AUX COTES EXACTES DU TUBE, PAS SUR LA BOÎTE ENGLOBANTE. Premier jet de ce
	# contrôle : fenêtre prise à 4 mm des extrémités de l'AABB du seau `alu`. Il rougissait sur une
	# géométrie JUSTE, parce que l'assistance de fermeture dépasse de 13 mm DERRIÈRE la carcasse :
	# la fenêtre arrière ne voyait qu'elle (rayon mesuré 11 mm) et jamais le fond du tube.
	# Leçon : **une boîte englobante n'est pas une cote**. Pour mesurer une pièce précise, on la
	# cherche là où on l'a POSÉE.
	var z_rear := 0.051
	var z_front := -0.139
	var r_min_avant := INF
	var r_min_arriere := INF
	for p in corps.positions:
		var rr := Vector2(p.x, p.y - bore).length()
		if absf(p.z - z_front) < 0.0015:
			r_min_avant = minf(r_min_avant, rr)
		if absf(p.z - z_rear) < 0.0015:
			r_min_arriere = minf(r_min_arriere, rr)
	_ok("U1 les deux bouts de la carcasse sont FERMES (pas de tuyau noir visible en ADS)",
		r_min_avant < r * 0.2 and r_min_arriere < r * 0.2,
		"rayon min au bout avant %.5f m · au bout arriere %.5f m (rayon de carcasse %.4f)"
			% [r_min_avant, r_min_arriere, r])

	# U2. La fenêtre d'éjection existe VRAIMENT comme cavité, et le volet est là (les deux masses).
	_ok("U2 la fenetre d'ejection a sa cavite, et le volet ses deux masses",
		asm.buckets.has("cavity") and asm.buckets.has("steel")
			and not asm.buckets["cavity"].is_empty(),
		"seaux : " + str(asm.buckets.keys()))

	# U3. La carcasse INFÉRIEURE : le puits de chargeur est un VRAI trou (il doit l'être pour que
	# le puits se voie quand le chargeur tombe pendant une recharge, lot 3D-E).
	var lo = Meshgen.Assembly.new("lower")
	var lo_info: Dictionary = WParts.add_lower_receiver(lo, "alu", "steel",
		{"bore": bore, "zRear": 0.055, "zFront": -0.084, "w": 0.0241,
		"magW": 0.0288, "magD": 0.0668, "magTop": 0.045, "magBottom": 0.004,
		"magZ": -0.054, "magTilt": 0.077, "triggerZ": -0.011, "gripAngle": 0.37})
	_ok("U3 la carcasse inferieure rend les cotes du puits, et pose sa doublure en `cavity`",
		lo_info.has("wellH") and float(lo_info["wellH"]) > 0.0
			and lo.buckets.has("cavity"),
		"hauteur de puits %.4f m · seaux : %s" % [lo_info["wellH"], str(lo.buckets.keys())])


# =================================================================================================
# M. LE CHARGEUR
# =================================================================================================
func _probe_magazine() -> void:
	var w := 0.0251
	var d := 0.0649
	var asm = Meshgen.Assembly.new("mag")
	WParts.build_magazine(asm, null,
		{"w": w, "d": d, "len": 0.207, "curve": 0.029, "segs": 8, "witness": 4})

	# ── M1. LA CARTOUCHE DU HAUT EST COUCHÉE LE LONG DE L'ARME ──────────────────────────────────
	# « It lies along the magazine's DEPTH axis (bullet forward, -Z) like a real stack, not across
	# its width. […] Rotated the other way it LANCES STRAIGHT OUT through the mag's flank. »
	# Une cartouche de ~63 mm dans un chargeur large de 25 mm : si elle était en travers, sa boîte
	# englobante déborderait la largeur de plusieurs centimètres. C'est immédiatement mesurable.
	var laiton = Meshgen.merge_all(asm.buckets["brass"])
	var b: AABB = laiton.aabb()
	_ok("M1 la cartouche du haut est couchee selon la PROFONDEUR, pas en travers de la largeur",
		b.size.z > b.size.x * 2.0 and b.size.x < w,
		"etendue de la douille : X %.4f m · Z %.4f m (largeur du chargeur %.4f m)"
			% [b.size.x, b.size.z, w])

	# M2. Seule la DOUILLE est visible sous les lèvres — l'ogive est dans un autre seau (`copper`),
	# et les deux doivent être au MÊME endroit : une ogive orpheline ou décalée est un défaut que
	# le rapport de cartographie a explicitement signalé comme piège de portage.
	var cuivre = Meshgen.merge_all(asm.buckets["copper"])
	var bc: AABB = cuivre.aabb()
	_ok("M2 l'ogive cuivre est bien dans le prolongement de la douille laiton",
		absf(bc.get_center().x - b.get_center().x) < 0.002
			and bc.get_center().z < b.get_center().z,
		"centre laiton z %.4f · centre ogive z %.4f (l'ogive doit etre plus en AVANT)"
			% [b.get_center().z, bc.get_center().z])

	# M3. Les trous témoins sont de vraies cavités des DEUX côtés.
	var temoins = Meshgen.merge_all(asm.buckets["cavity"])
	var bt: AABB = temoins.aabb()
	_ok("M3 les trous temoins sont perces des DEUX cotes du chargeur",
		temoins != null and bt.size.x > w * 0.9,
		"etendue en X des temoins %.4f m (largeur du chargeur %.4f m)" % [bt.size.x, w])
