extends RefCounted
# =================================================================================================
# LA TRANCHÉE — VUE 3D (§8.152 LOT 3D-A + 3D-B2) — LE VOCABULAIRE DE PIÈCES D'ARMES.
#
# Port de `War-Of-Indipendence/Claude-of-Duty-main/src/weapons/parts.js` (2 072 l.).
# Chaque fonction boulonne un sous-ensemble MÉCANIQUE réel sur un `Assembly`, à un décalage donné.
#
# ╔═ LA PHRASE DE LEUR EN-TÊTE QUI GOUVERNE TOUT LE FICHIER ══════════════════════════════════════╗
# ║ « Everything is authored from published dimensions (an AR-15 upper receiver really is 198 mm  ║
# ║ long with a 21.2 mm rail and a 66 mm optic height over bore), because **proportion is what    ║
# ║ the eye checks first — no amount of texture detail rescues a receiver that is 30% too fat**. »║
# ║                                                                                               ║
# ║ Conséquence pratique : **AUCUNE constante de ce fichier ne doit être arrondie ni « nettoyée »**║
# ║ Ce sont des cotes réelles. Un 0,0192 qui devient 0,02 est une carcasse 4 % trop grosse.       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# REPÈRE DE L'ARME : +X à droite, +Y en haut, **−Z vers la bouche**. L'origine est l'ancrage de la
# main de tir (la commissure du pouce, haut-arrière de la poignée) — c'est aussi ce que le rig du
# viewmodel positionne (lot 3D-F).
#
# ÉCARTS ASSUMÉS vis-à-vis de `parts.js` :
#   • `dispose()` n'existe pas : GDScript compte les références. Tous les appels sont retirés.
#   • `o.foo ?? défaut` devient `o.get("foo", défaut)`.
#   • `bevelSegments` et `curveSegments` sont ACCEPTÉS mais IGNORÉS par notre `extrude` : il pose
#     une couronne de biseau unique (l'équivalent de `bevelSegments: 1`). Sur des biseaux de 0,7 à
#     3,5 mm vus à 40 cm, la différence est sous le pixel ; à rouvrir si une capture la réclame.
#   • les fonctions qui, chez eux, rendent `{geo, mat}` rendent ici un `Dictionary` identique.
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")


# Longueur hors-tout de chaque frein de bouche, pour que l'appelant puisse implanter son canon.
const MUZZLE_LEN := {"brake": 0.062, "a2": 0.0483, "comp": 0.058, "trilug": 0.042}


# =================================================================================================
# PETITE VISSERIE
# =================================================================================================

# Goupille traversante à tête bombée (axes de démontage, axes de détente/marteau).
static func add_pin(asm, mat: String, x: float, y: float, z: float,
		r := 0.0022, length := 0.02) -> void:
	asm.add(Meshgen.rod_z(r, r, length, 12, 0.0004), mat,
		{"x": x, "y": y, "z": z, "ry": PI * 0.5})
	asm.add(Meshgen.dome(r * 1.25, 10, 0.5), mat,
		{"x": x + length * 0.5, "y": y, "z": z, "ry": -PI * 0.5})
	asm.add(Meshgen.dome(r * 1.25, 10, 0.5), mat,
		{"x": x - length * 0.5, "y": y, "z": z, "ry": PI * 0.5})


# Vis six pans creux, tête tournée vers +axe.
static func add_screw(asm, mat: String, x: float, y: float, z: float,
		r_head := 0.0022, axis := "y", length := 0.008) -> void:
	var g = Meshgen.screw(r_head, r_head * 0.55, r_head * 0.5, length, 10)
	var t := {"x": x, "y": y, "z": z}
	if axis == "y":
		t["rx"] = PI * 0.5
	elif axis == "x":
		t["ry"] = -PI * 0.5
	asm.add(g, mat, t)


# Embase QD de bretelle : une cuvette fraisée avec un insert acier.
static func add_qd_socket(asm, mat_body: String, mat_steel: String,
		x: float, y: float, z: float, axis := "x", r := 0.0055) -> void:
	var cup = Meshgen.lathe_z([
		[0, r * 0.55], [0, r * 1.5], [0.0012, r * 1.62], [0.006, r * 1.62], [0.006, r * 0.9],
	], 14)
	var inner = Meshgen.lathe_z([[0.004, 0], [0.004, r * 0.55], [0, r * 0.55]], 12)
	var t := {"x": x, "y": y, "z": z}
	if axis == "x":
		t["ry"] = PI * 0.5
	elif axis == "y":
		t["rx"] = -PI * 0.5
	asm.add(cup, mat_body, t)
	asm.add(inner, mat_steel, t)


# Passant de bretelle fixe — un œil d'acier plat.
static func add_sling_loop(asm, mat: String, x: float, y: float, z: float,
		radius := 0.008, rot := {}) -> void:
	var t := {"x": x, "y": y, "z": z}
	t.merge(rot, true)
	asm.add(Meshgen.ring(radius, 0.0016, 14, 6), mat, t)


# Une cartouche VIVE : étui laiton, épaulement, collet, ogive cuivre.
static func cartridge(case_len := 0.0446, rim_r := 0.00495, bullet_len := 0.019) -> Dictionary:
	var neck_r := rim_r * 0.72
	var brass = Meshgen.lathe_z([
		[0, 0],
		[0, rim_r],
		[0.0012, rim_r * 0.97],
		[case_len * 0.62, rim_r * 0.965],
		[case_len * 0.78, neck_r],
		[case_len, neck_r],
	], 16)
	var bullet = Meshgen.lathe_z([
		[case_len - 0.004, neck_r * 0.98],
		[case_len + bullet_len * 0.45, neck_r * 0.98],
		[case_len + bullet_len * 0.8, neck_r * 0.62],
		[case_len + bullet_len, neck_r * 0.16],
		[case_len + bullet_len + 0.0004, 0],
	], 16)
	return {"brass": brass, "bullet": bullet, "length": case_len + bullet_len}


# Douille TIRÉE — même laiton, pas d'ogive, bouche légèrement évasée.
static func empty_case(case_len := 0.0446, rim_r := 0.00495):
	var neck_r := rim_r * 0.72
	return Meshgen.lathe_z([
		[0, 0],
		[0, rim_r],
		[0.0012, rim_r * 0.97],
		[case_len * 0.62, rim_r * 0.965],
		[case_len * 0.78, neck_r],
		[case_len, neck_r * 1.02],
		[case_len, neck_r * 0.86],
		[case_len * 0.8, neck_r * 0.86],
	], 16)


# =================================================================================================
# RAILS
# =================================================================================================

# Section de Picatinny le long de Z, face supérieure à `y`.
#
# ╔═ ⚠️ LE FOND DES ENCOCHES — mesure de la référence, recopiée parce qu'elle porte un chiffre ═══╗
# ║ « A recoil slot is a 5.35 mm gap with a 3.2 mm deep floor that in real light is always in     ║
# ║ shadow. Left in the rail's own aluminium the floor caught the sky at exactly the same rate as ║
# ║ the tooth tops, so a rail read as a **ladder of flat near-white bars instead of a row of      ║
# ║ cavities — the single loudest artefact on the whole weapon**. »                               ║
# ║ La bande de fond fait exactement la largeur du pied d'une dent : elle est donc OCCULTÉE par   ║
# ║ les dents partout, sauf DANS les encoches, où elle devient le fond.                           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func add_rail(asm, mat: String, z0: float, z1: float, y: float,
		x := 0.0, opts := {}) -> void:
	var length: float = absf(z1 - z0)
	var base_h: float = opts.get("baseH", 0.0042)
	var top_h: float = opts.get("topH", 0.0032)
	var waist: float = opts.get("waist", 0.0157)
	var cz := (z0 + z1) * 0.5
	var yb := y - base_h - top_h
	asm.add(Meshgen.picatinny(length, opts), mat, {"x": x, "y": yb, "z": cz})
	if bool(opts.get("slotFloor", true)):
		var floor_g = Meshgen.box(waist * 0.99, 0.0014, length - 0.0004, 0.0002, 1)
		asm.add(floor_g, "cavity", {"x": x, "y": yb + base_h - 0.0003, "z": cz})


# =================================================================================================
# CANON + FREINS DE BOUCHE
# =================================================================================================

# Canon étagé, avec épaulement de chambre, tourillon de prise de gaz et section moletée.
# Rend le Z de bouche pour que le frein s'y boulonne.
static func add_barrel(asm, mat_steel: String, mat_cavity: String, o: Dictionary) -> Dictionary:
	var y: float = o.get("y", 0.0)
	var z_breech: float = o["zBreech"]
	var z_muzzle: float = o["zMuzzle"]
	var r_chamber: float = o.get("rChamber", 0.0112)
	var r_bore: float = o.get("rBarrel", 0.0072)
	var r_gas: float = o.get("rGas", 0.0092)
	var length := z_breech - z_muzzle
	var gas_at: float = o.get("gasAt", z_muzzle + length * 0.34)

	var profile := [
		[0, 0],
		[0, r_chamber + 0.0018],
		[0.004, r_chamber + 0.0022],
		[0.02, r_chamber + 0.0022],
		[0.022, r_chamber],
		[length * 0.24, r_chamber],
		[length * 0.26, r_bore + 0.0012],
		[z_breech - gas_at - 0.012, r_bore + 0.0012],
		[z_breech - gas_at - 0.01, r_gas],
		[z_breech - gas_at + 0.012, r_gas],
		[z_breech - gas_at + 0.014, r_bore],
		[length - 0.014, r_bore],
		[length - 0.012, r_bore + 0.0009],
		[length - 0.001, r_bore + 0.0009],
		[length, r_bore * 0.72],
	]
	# Écrit depuis la culasse vers l'avant ; on retourne pour que +axial parte vers −Z.
	asm.add(Meshgen.lathe_z(profile, o.get("seg", 22)), mat_steel,
		{"y": y, "z": z_breech, "ry": PI})

	# L'ÂME : un vrai tube sombre, pour que la couronne ne lise pas comme un point peint.
	asm.add(Meshgen.tube_z(r_bore * 0.7, r_bore * 0.42, length * 0.5, 14, 0.0002), mat_cavity,
		{"y": y, "z": z_muzzle + length * 0.25})

	# Section moletée derrière le filetage de bouche.
	if bool(o.get("knurl", true)):
		asm.add(Meshgen.knurl_band(r_bore + 0.0006, 0.012, 26, 0.00035, 3), mat_steel,
			{"y": y, "z": z_muzzle + 0.026})
	return {"gasAt": gas_at, "rBore": r_bore}


# Bloc de gaz + tube de gaz. Bloc bas profil à deux vis de calage, le tube remontant sur le canon
# jusque dans la carcasse.
static func add_gas_block(asm, mat_steel: String, o: Dictionary) -> void:
	var y: float = o.get("y", 0.0)
	var z: float = o["z"]
	var r: float = o.get("rBarrel", 0.0072)
	var w: float = o.get("w", 0.021)
	var h: float = o.get("h", 0.019)
	asm.add(Meshgen.box(w, h, o.get("len", 0.026), 0.0008, 2), mat_steel,
		{"y": y - 0.0015, "z": z})
	add_screw(asm, mat_steel, 0.0, y - h * 0.5 + 0.0015, z - 0.007, 0.0022, "y", 0.006)
	add_screw(asm, mat_steel, 0.0, y - h * 0.5 + 0.0015, z + 0.007, 0.0022, "y", 0.006)
	var tube_len: float = o["tubeTo"] - z
	asm.add(Meshgen.tube_z(0.0026, 0.0014, absf(tube_len), 10, 0.0002), mat_steel,
		{"y": y + r + 0.0052, "z": z + tube_len * 0.5})


# Freins de bouche. Tous reçoivent une vraie âme, une rondelle d'écrasement, des évents chanfreinés
# et une couronne : « the muzzle is the part the player stares at while firing ».
static func add_muzzle_device(asm, mat_steel: String, mat_cavity: String, kind: String,
		z_barrel_end: float, r_barrel: float, y := 0.0) -> Dictionary:
	var parts := []
	var length: float = MUZZLE_LEN.get(kind, 0.05)
	var r_out := r_barrel + 0.0038
	# Le frein se visse SUR le canon : sa face arrière est au bout du canon, la couronne se
	# retrouve `len` plus en avant.
	var z_crown := z_barrel_end - length

	if kind == "brake":
		parts.append(Meshgen.lathe_z([
			[0, r_barrel + 0.0012],
			[0.006, r_barrel + 0.0022],
			[0.008, r_out],
			[length - 0.01, r_out],
			[length - 0.008, r_out * 0.96],
			[length - 0.002, r_out * 0.96],
			[length, r_out * 0.8],
			[length, r_barrel * 0.66],
			[length - 0.006, r_barrel * 0.62],
		], 20))
		# Trois paires d'évents latéraux chanfreinés.
		for i in 3:
			var z := 0.016 + i * 0.013
			parts.append(Meshgen.box(r_out * 2.4, 0.0055, 0.0072, 0.0006, 1).translate(0, 0, z))
	elif kind == "a2":
		# Cage à oiseau A2 : bas fermé, cinq fentes.
		parts.append(Meshgen.lathe_z([
			[0, r_barrel + 0.001],
			[0.005, r_barrel + 0.002],
			[0.007, r_out * 0.92],
			[0.012, r_out],
			[length - 0.004, r_out],
			[length, r_out * 0.86],
			[length, r_barrel * 0.6],
			[length - 0.005, r_barrel * 0.58],
		], 20))
		for i in 5:
			var a := -PI * 0.44 + (float(i) / 4.0) * PI * 0.88
			parts.append(Meshgen.box(0.0032, 0.0075, 0.021, 0.0005, 1)
				.translate(0, r_out * 0.82, 0).rotate_z(a).translate(0, 0, 0.03))
	elif kind == "comp":
		# Compensateur linéaire / caisson de souffle.
		parts.append(Meshgen.lathe_z([
			[0, r_barrel + 0.0012],
			[0.005, r_barrel + 0.003],
			[0.008, r_out + 0.0016],
			[0.03, r_out + 0.0016],
			[0.031, r_out + 0.0022],
			[length - 0.003, r_out + 0.0022],
			[length, r_out + 0.0006],
			[length, r_barrel * 0.7],
			[length - 0.007, r_barrel * 0.66],
		], 20))
		parts.append(Meshgen.knurl_band(r_out + 0.0018, 0.018, 30, 0.0003, 4)
			.translate(0, 0, 0.018))
	else:
		# Tri-lug / cache-flamme, pour la classe mitraillette.
		parts.append(Meshgen.lathe_z([
			[0, r_barrel + 0.0014],
			[0.004, r_barrel + 0.0026],
			[0.006, r_out],
			[0.024, r_out],
			[0.026, r_out - 0.0012],
			[length - 0.002, r_out - 0.0012],
			[length, r_out - 0.003],
			[length, r_barrel * 0.62],
			[length - 0.005, r_barrel * 0.6],
		], 18))
		for i in 3:
			var a := (float(i) / 3.0) * TAU
			parts.append(Meshgen.box(0.0042, 0.0038, 0.012, 0.0005, 1)
				.translate(0, r_out + 0.0012, 0).rotate_z(a).translate(0, 0, 0.008))

	# Écrit de la culasse vers la couronne le long de +Z : on le retourne sur la bouche.
	asm.add(Meshgen.merge_all(parts), mat_steel, {"y": y, "z": z_crown + length, "ry": PI})

	# Rondelle d'écrasement.
	asm.add(Meshgen.lathe_z([
		[0, r_barrel + 0.0012],
		[0, r_barrel + 0.0032],
		[0.0018, r_barrel + 0.0032],
		[0.0018, r_barrel + 0.0012],
	], 16), mat_steel, {"y": y, "z": z_crown + length})

	# L'âme elle-même, et la chambre d'expansion sombre derrière.
	asm.add(Meshgen.tube_z(r_barrel * 0.66, r_barrel * 0.4, length * 0.9, 14, 0.0002), mat_cavity,
		{"y": y, "z": z_crown + length * 0.5})
	return {"len": length, "crownZ": z_crown}


# =================================================================================================
# GARDE-MAIN
# =================================================================================================

# Garde-main flottant fait de LATTES longitudinales séparées par de vrais jours, pour qu'on voie le
# canon et le bloc de gaz au travers et que la silhouette se brise.
#
# ╔═ RÉPARTITION DES MATÉRIAUX (commentaire de la référence) ═════════════════════════════════════╗
# ║ L'écrou de canon, les entretoises et l'embout sont en aluminium USINÉ (ils portent le canon) ;║
# ║ les lattes et leurs encoches M-LOK sont un jeu de panneaux POLYMÈRE moulés. C'est une vraie   ║
# ║ configuration produit, et c'est **le seul endroit de l'arme où les deux classes diélectriques ║
# ║ se touchent sur une grande surface** — ce qui rend la séparation de classes LISIBLE au tir à  ║
# ║ la hanche au lieu de théorique. (Cf. les trois classes du lot 3D-C.)                          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func add_handguard(asm, mat_alu: String, o: Dictionary) -> void:
	var mat_panel: String = o.get("matPanel", mat_alu)
	var yb: float = o.get("y", 0.0)
	var z0: float = o["z0"]  # côté carcasse (arrière, z le plus grand)
	var z1: float = o["z1"]  # côté bouche
	var length := z0 - z1
	var r_out: float = o.get("r", 0.0235)
	var sides: int = o.get("sides", 8)
	var slat_w: float = o.get("slatW", 0.0135)
	var slat_t: float = o.get("slatT", 0.0032)
	var cz := (z0 + z1) * 0.5

	# Écrou de canon / collier arrière.
	asm.add(Meshgen.lathe_z([
		[0, r_out * 0.72],
		[0, r_out + 0.0018],
		[0.0025, r_out + 0.0026],
		[0.014, r_out + 0.0026],
		[0.0165, r_out + 0.0012],
		[0.0165, r_out * 0.72],
	], 18), mat_alu, {"y": yb, "z": z0 - 0.0165})
	asm.add(Meshgen.knurl_band(r_out + 0.0028, 0.011, 34, 0.00035, 3), mat_alu,
		{"y": yb, "z": z0 - 0.0085})

	var slat = Meshgen.box(slat_w, slat_t, length - 0.019, 0.0006, 1)
	# ╔═ ⚠️ POURQUOI LE ROULIS DE L'ENCOCHE EST CUIT DANS LA GÉOMÉTRIE ═══════════════════════════╗
	# ║ `mlok_slot` est écrit comme une plaque dans le plan XY extrudée selon +Z : sa poche creuse ║
	# ║ vers −Z et son grand axe est X. `Assembly` compose ses angles d'Euler en ordre 'XYZ', qui  ║
	# ║ APPLIQUE `rz` EN PREMIER — un seul `add()` ne peut donc PAS à la fois coucher la plaque sur║
	# ║ l'axe du canon ET la faire tourner à sa position horaire sur le garde-main.                ║
	# ║ On cuit donc le roulis UNE FOIS dans la géométrie : normale → +X (radial), grand axe → Z.  ║
	# ║ Ensuite `rz: a` seul la pose sur n'importe quelle latte.                                   ║
	# ║ Sans ce roulis, les plaques restaient dans le plan XY et lisaient comme « des losanges qui ║
	# ║ flottent en saillie du garde-main » — ce qu'elles faisaient effectivement.                 ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var slot_geo = Meshgen.mlok_slot(0.026, 0.0072, 0.0018)
	slot_geo.rotate_y(PI * 0.5)
	# La latte du haut est normalement le travail du rail. `topFrom`/`topTo` permettent de demander
	# un dessus polymère nu sur la portion que la main de soutien empoigne vraiment, pour que les
	# doigts se referment sur le garde-main au lieu de passer à travers un rail.
	var top_from = o.get("topFrom", null)
	var top_to = o.get("topTo", null)
	for i in sides:
		var a := (float(i) / float(sides)) * TAU + PI / float(sides)
		var is_top: bool = absf(sin(a) - 1.0) < 0.35
		var y := sin(a) * (r_out - slat_t * 0.5)
		var x := cos(a) * (r_out - slat_t * 0.5)
		if is_top:
			if top_from == null:
				continue
			var t_len: float = absf(float(top_from) - float(top_to))
			asm.add(Meshgen.box(slat_w, slat_t, t_len, 0.0006, 1), mat_panel, {
				"x": x, "y": yb + y, "z": (float(top_from) + float(top_to)) * 0.5,
				"rz": a - PI * 0.5,
			})
			continue
		asm.add(slat, mat_panel, {"x": x, "y": yb + y, "z": cz - 0.0095, "rz": a - PI * 0.5})
		# Encoches M-LOK sur les seules lattes à 3, 6 et 9 heures, comme sur la vraie.
		var cardinal: bool = absf(cos(a)) > 0.85 or sin(a) < -0.85
		if cardinal:
			for s in int(o.get("slots", 3)):
				var sz := cz + length * 0.5 - 0.045 - s * 0.038
				if sz < z1 + 0.02:
					break
				asm.add(slot_geo, mat_panel,
					{"x": x * 1.005, "y": yb + y * 1.005, "z": sz, "rz": a})
				# Le fond de la poche : un creux sombre, pour que l'encoche soit un TROU dans le
				# panneau et non un losange en relief qui attrape la même lumière que la face.
				asm.add(Meshgen.box(0.0012, 0.0052, 0.0232, 0.0002, 1), "cavity",
					{"x": x * 0.955, "y": yb + y * 0.955, "z": sz, "rz": a})

	# Les entretoises annulaires qui lient les lattes.
	var brace_count: int = o.get("braces", 3)
	for i in brace_count:
		var z := z0 - 0.03 - (float(i) / float(maxi(1, brace_count - 1))) * (length - 0.07)
		asm.add(Meshgen.lathe_z([
			[0, r_out - slat_t],
			[0, r_out + 0.0006],
			[0.0035, r_out + 0.0006],
			[0.0035, r_out - slat_t],
		], maxi(10, sides * 2)), mat_alu, {"y": yb, "z": z})

	# Embout chanfreiné à l'avant.
	asm.add(Meshgen.lathe_z([
		[0, r_out - slat_t - 0.0008],
		[0, r_out - 0.0002],
		[0.0022, r_out - 0.0012],
		[0.0022, r_out - slat_t - 0.0008],
	], maxi(10, sides * 2)), mat_alu, {"y": yb, "z": z1 + 0.001})


# =================================================================================================
# CARCASSES
# =================================================================================================

# Carcasse supérieure façon AR : tube à dessus plat, rail sur la crête, assistance de fermeture et
# déflecteur à l'arrière droit, fenêtre d'éjection en creux, couloir de levier d'armement.
static func add_upper_receiver(asm, mat: String, mat_steel: String, mat_cavity: String,
		o: Dictionary) -> Dictionary:
	var z_rear: float = o["zRear"]
	var z_front: float = o["zFront"]
	var bore: float = o["bore"]
	var r: float = o.get("r", 0.0192)
	var length := z_rear - z_front
	var cz := (z_rear + z_front) * 0.5

	# ╔═ ⚠️ LES DEUX BOUTS SONT FERMÉS (rayon 0) — et ce n'est pas un détail ═════════════════════╗
	# ║ Une face annulaire laisse un trou de 19 mm droit dans la carcasse, et en ADS l'œil est à   ║
	# ║ 0,2 m derrière, en train de regarder dedans : on voit **la culasse et la cartouche chambrée║
	# ║ flotter dans un tuyau noir**. Rien de l'intérieur de la carcasse n'est censé être visible, ║
	# ║ sauf par la cavité de la fenêtre d'éjection.                                               ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	asm.add(Meshgen.lathe_z([
		[0, 0],
		[0, r * 0.98],
		[0.0022, r],
		[length * 0.52, r],
		[length * 0.54, r * 0.985],
		[length - 0.004, r * 0.985],
		[length, r * 0.93],
		[length, 0],
	], 22), mat, {"y": bore, "z": z_rear, "ry": PI})

	# Le méplat sur lequel le rail est usiné.
	asm.add(Meshgen.box(0.0235, 0.008, length - 0.002, 0.0008, 1), mat,
		{"y": bore + r - 0.0025, "z": cz})
	# Bosse du couloir de levier d'armement, à l'arrière.
	asm.add(Meshgen.box(0.0245, 0.011, 0.05, 0.0012, 2), mat,
		{"y": bore + r - 0.0075, "z": z_rear - 0.024})

	# Bossage d'assistance de fermeture (arrière droit) — vrai cylindre étagé avec sa pastille.
	asm.add(Meshgen.lathe_z([
		[0, 0], [0, 0.0055], [0.0015, 0.0062], [0.006, 0.0062],
		[0.007, 0.0048], [0.019, 0.0048], [0.019, 0],
	], 14), mat, {"x": 0.0115, "y": bore - 0.004, "z": z_rear - 0.006, "rx": 0.35})
	asm.add(Meshgen.box(0.0085, 0.0085, 0.0035, 0.0008, 2), mat_steel,
		{"x": 0.0132, "y": bore - 0.0025, "z": z_rear + 0.0025, "rx": 0.35})

	# Déflecteur à douilles : le petit coin derrière la fenêtre.
	asm.add(Meshgen.extrude([[0, 0], [0.013, 0.004], [0.013, 0.019], [0, 0.017]], 0.016,
		{"bevel": 0.0009}), mat,
		{"x": r - 0.001, "y": bore - 0.006, "z": z_rear - 0.045, "ry": PI * 0.5})

	# Fenêtre d'éjection : une cavité en creux, avec son volet en dessous.
	var port_w := 0.032
	var port_h := 0.019
	asm.add(Meshgen.box(port_h, 0.012, port_w, 0.0008, 1), mat_cavity,
		{"x": r - 0.0075, "y": bore + 0.001, "z": o["portZ"], "ry": PI * 0.5})
	asm.add(Meshgen.extrude(Meshgen.round_rect(port_w + 0.005, port_h + 0.005, 0.0022, 3), 0.0022,
		{"bevel": 0.0006}), mat,
		{"x": r - 0.0022, "y": bore + 0.001, "z": o["portZ"], "ry": PI * 0.5})
	asm.add(Meshgen.extrude(Meshgen.round_rect(port_w, port_h, 0.0018, 3), 0.003,
		{"bevel": 0.0005}), mat_cavity,
		{"x": r - 0.0042, "y": bore + 0.001, "z": o["portZ"], "ry": PI * 0.5})

	# ╔═ LE VOLET ANTI-POUSSIÈRE, PENDU OUVERT ═══════════════════════════════════════════════════╗
	# ║ « The port on its own is a dark rectangle and reads as a DECAL. What makes it read as a    ║
	# ║ MECHANISM is the cover » : un panneau embouti à LÈVRE EN RELIEF sur trois bords (cette     ║
	# ║ lèvre est la nervure de rigidité, et c'est la seule partie du volet qui attrape jamais un  ║
	# ║ éclat), monté sur ressort sur un axe sous la fenêtre, si bien qu'il pend vers le bas et    ║
	# ║ l'arrière du flanc. **Deux masses distinctes — l'axe et le panneau nervuré — là où il n'y  ║
	# ║ en avait aucune.**                                                                         ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var hinge_y := bore - 0.0092
	var hinge_x := r - 0.0035
	asm.add(Meshgen.rod_z(0.0016, 0.0016, port_w + 0.014, 10, 0.0003), mat_steel,
		{"x": hinge_x, "y": hinge_y, "z": o["portZ"]})
	# Le panneau pivote autour de l'axe : 1,35 rad le met pendu bas-dehors, dégagé du puits de
	# chargeur, là où un volet à ressort se trouve réellement.
	var cover_open := 1.35
	var cover_parts := []
	cover_parts.append(Meshgen.box(port_h + 0.004, 0.0014, port_w + 0.006, 0.0005, 1))
	for sz in [-1.0, 1.0]:
		cover_parts.append(Meshgen.box(port_h + 0.004, 0.0032, 0.0016, 0.0004, 1)
			.translate(0, 0.0009, sz * (port_w * 0.5 + 0.0022)))
	cover_parts.append(Meshgen.box(0.0018, 0.0034, port_w + 0.006, 0.0004, 1)
		.translate((port_h + 0.004) * 0.5 - 0.0009, 0.001, 0))
	var cover = Meshgen.merge_all(cover_parts)
	# Écrit couché dans le plan XZ, charnière le long de −X, puis ouvert d'un coup.
	cover.translate((port_h + 0.004) * 0.5, 0, 0).rotate_z(-cover_open)
	asm.add(cover, mat, {"x": hinge_x, "y": hinge_y, "z": o["portZ"]})

	# Le rail sur la crête.
	add_rail(asm, mat, z_front + 0.002, z_rear - 0.002, o["railTop"])
	# Goupilles de carcasse.
	add_pin(asm, mat_steel, 0.0, bore - r + 0.004, z_front + 0.014, 0.0024, r * 2.0 - 0.004)
	return {"railTop": o["railTop"]}


# L'ensemble mobile vu par la fenêtre d'éjection. Séparé parce qu'il CYCLE (lot 3D-E).
static func add_bolt_carrier(asm, mat_steel: String, o: Dictionary) -> void:
	var y: float = o.get("y", 0.0)
	var r: float = o.get("r", 0.0155)
	var length: float = o.get("len", 0.09)
	asm.add(Meshgen.lathe_z([
		[0, r * 0.6], [0, r], [0.002, r + 0.0004],
		[length * 0.45, r + 0.0004], [length * 0.47, r],
		[length, r], [length, r * 0.5],
	], 18), mat_steel, {"y": y, "z": o["z"], "ry": PI})
	asm.add(Meshgen.box(0.011, 0.0075, 0.016, 0.0006, 1), mat_steel,
		{"y": y + r + 0.0026, "z": o["z"] + length * 0.25})
	asm.add(Meshgen.box(0.006, 0.005, 0.03, 0.0005, 1), mat_steel,
		{"x": r * 0.78, "y": y + r * 0.42, "z": o["z"] + length * 0.1, "rz": 0.5})


# Carcasse inférieure AR : puits de chargeur, pontet, embase de poignée, sélecteur, goupilles.
static func add_lower_receiver(asm, mat: String, mat_steel: String, o: Dictionary) -> Dictionary:
	var bore: float = o["bore"]
	var z_rear: float = o["zRear"]
	var z_front: float = o["zFront"]
	var w: float = o.get("w", 0.0245)
	var mag_w: float = o.get("magW", 0.0295)
	var mag_d: float = o.get("magD", 0.0685)
	var mag_top: float = o.get("magTop", bore - 0.014)
	var mag_bottom: float = o.get("magBottom", bore - 0.062)
	var mag_z: float = o["magZ"]
	var mag_tilt: float = o.get("magTilt", 0.09)

	asm.add(Meshgen.box(w, 0.026, z_rear - z_front, 0.0016, 2), mat,
		{"y": bore - 0.014, "z": (z_rear + z_front) * 0.5})

	# Puits de chargeur : un tube VRAIMENT CREUX (pour que le puits soit un trou quand le chargeur
	# tombe pendant une recharge), incliné vers l'avant comme le vrai.
	var well_h := mag_top - mag_bottom
	var well_t := {"y": (mag_top + mag_bottom) * 0.5, "z": mag_z, "rx": PI * 0.5 + mag_tilt}
	asm.add(Meshgen.extrude(Meshgen.round_rect(mag_w, mag_d, 0.0075, 5), well_h, {
		"bevel": 0.0012,
		"holes": [Meshgen.round_rect(mag_w - 0.005, mag_d - 0.005, 0.006, 5)],
	}), mat, well_t)
	asm.add(Meshgen.extrude(Meshgen.round_rect(mag_w - 0.0052, mag_d - 0.0052, 0.006, 5),
		well_h - 0.004, {
			"bevel": 0.0006,
			"holes": [Meshgen.round_rect(mag_w - 0.0082, mag_d - 0.0082, 0.005, 5)],
		}), "cavity", well_t)
	asm.add(Meshgen.extrude(Meshgen.round_rect(mag_w + 0.004, mag_d + 0.005, 0.008, 5), 0.006, {
		"bevel": 0.0012,
		"holes": [Meshgen.round_rect(mag_w - 0.003, mag_d - 0.003, 0.006, 5)],
	}), mat, {
		"y": mag_bottom + 0.002,
		"z": mag_z + sin(mag_tilt) * well_h * 0.5,
		"rx": PI * 0.5 + mag_tilt,
	})

	# Tenon arrière + tour de tampon.
	asm.add(Meshgen.box(w - 0.001, 0.03, 0.026, 0.0014, 2), mat,
		{"y": bore - 0.0155, "z": z_rear - 0.012})

	# ╔═ LE PONTET — et pourquoi son contour est écrit dans le plan de PROFIL ════════════════════╗
	# ║ Le contour est écrit dans le plan LATÉRAL de l'arme (première coordonnée = avant/arrière,  ║
	# ║ seconde = haut/bas), puis tourné pour que l'extrusion traverse la carcasse. Extruder le    ║
	# ║ contour droit hors du plan XY dresserait la boucle EN TRAVERS de l'arme comme un pare-vache║
	# ║ en forme de détente : invisible de profil, et faux sous tous les autres angles.            ║
	# ║ +X dans le contour est le côté bouche, donc il se projette en −Z.                          ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var guard_outer := [
		[-0.028, 0], [0.03, 0], [0.032, -0.006], [0.028, -0.0225],
		[0.018, -0.0275], [-0.02, -0.0275], [-0.028, -0.021],
	]
	var guard_inner := [
		[-0.0225, -0.003], [0.0245, -0.003], [0.0255, -0.008], [0.022, -0.0205],
		[0.015, -0.0235], [-0.0165, -0.0235], [-0.0225, -0.019],
	]
	var guard = Meshgen.extrude(guard_outer, 0.0172,
		{"bevel": 0.0011, "bevelSegments": 2, "holes": [guard_inner]})
	guard.rotate_y(PI * 0.5)  # contour-X -> −Z (vers l'avant), extrusion -> en travers
	asm.add(guard, mat, {"y": bore - 0.026, "z": o["triggerZ"]})

	# Embase de poignée.
	asm.add(Meshgen.box(0.028, 0.012, 0.03, 0.0012, 2), mat,
		{"y": bore - 0.0255, "z": z_rear - 0.028, "rx": -float(o["gripAngle"]) * 0.5})
	return {
		"magTop": mag_top, "magBottom": mag_bottom, "magZ": mag_z,
		"magTilt": mag_tilt, "wellH": well_h, "magW": mag_w, "magD": mag_d,
	}


# Sélecteur de tir ambidextre — la palette tourne autour de l'axe X.
static func selector_part(mat_alu: String, mat_steel: String, r := 0.006) -> Dictionary:
	var parts := []
	parts.append(Meshgen.rod_z(r * 0.62, r * 0.62, 0.03, 12, 0.0004).rotate_y(PI * 0.5))
	parts.append(Meshgen.lathe_z([
		[0, 0], [0, r], [0.0012, r * 1.1], [0.005, r * 1.1], [0.005, 0],
	], 12).rotate_y(-PI * 0.5).translate(0.0135, 0, 0))
	parts.append(Meshgen.extrude([
		[0, -0.0035], [0.021, -0.006], [0.024, 0.0], [0.02, 0.005], [0, 0.0045],
	], 0.0042, {"bevel": 0.0008}).rotate_y(PI * 0.5).translate(0.0185, 0, 0))
	return {"geo": Meshgen.merge_all(parts), "mat": mat_alu}


# Queue de détente courbe à face crantée ; pivote sur son axe.
# Le contour est une vue de PROFIL : +X vers l'arrière (la face que le doigt presse), −Y vers le
# bas. La lame entière est tournée à la fin pour que contour-X devienne +Z et que l'extrusion de
# 7 mm devienne la LARGEUR de la lame en travers de la carcasse — sans quoi la lame est une plaque
# dressée en travers du pontet.
static func trigger_part(mat_steel: String) -> Dictionary:
	var parts := [Meshgen.extrude([
		[-0.0045, 0.0045], [0.0048, 0.0045], [0.0056, -0.008], [0.0044, -0.0158],
		[0.0016, -0.0202], [-0.0032, -0.0192], [-0.0055, -0.011], [-0.006, -0.002],
	], 0.0072, {"bevel": 0.0007, "bevelSegments": 2})]
	# Crans sur la face où se pose la pulpe du doigt.
	for i in 6:
		# ⚠️ TOURNER SUR PLACE D'ABORD, PLACER ENSUITE : tourner après la translation ferait pivoter
		# le cran autour de l'AXE de la lame au lieu de l'incliner. (Commentaire de la référence.)
		parts.append(Meshgen.box(0.0015, 0.0011, 0.0066, 0.0003, 1)
			.rotate_z(-0.2 - i * 0.05)
			.translate(0.0049 - i * 0.0004, -0.0045 - i * 0.0026, 0))
	var geo = Meshgen.merge_all(parts)
	geo.rotate_y(-PI * 0.5)  # contour-X -> +Z (vers l'arrière), extrusion -> en travers
	return {"geo": geo, "mat": mat_steel}


# =================================================================================================
# POIGNÉE / CROSSE
# =================================================================================================

# Poignée pistolet avec renflement de paume, cannelures de doigts, bec de canard et panneaux
# texturés moulés. Bâtie sur son propre axe puis tournée de `angle`.
static func add_pistol_grip(asm, mat_poly: String, mat_rubber: String, o: Dictionary) -> void:
	var length: float = o.get("len", 0.108)
	var w: float = o.get("w", 0.031)
	var angle: float = o.get("angle", 0.38)  # inclinaison : positif recule le BAS
	var oy: float = o.get("y", 0.0)
	var oz: float = o.get("z", 0.0)

	# Profil latéral en (z, y), écrit comme UN contour fermé puis extrudé sur la largeur. Un solide
	# unique ne peut pas développer les coutures qu'une pile de tranches lofées produit, et le
	# contour est là où la forme vit vraiment : une face avant galbée avec dégagement pour les
	# doigts, une face arrière droite, un bec de canard.
	var zf := -0.0155  # face avant
	var zb := 0.0155  # face arrière
	var profile := [
		[zb + 0.004, 0.008], [zf - 0.002, 0.007], [zf - 0.0035, -0.006], [zf - 0.0015, -0.02],
		[zf - 0.003, -0.034], [zf - 0.0005, -0.05], [zf - 0.002, -0.064], [zf + 0.001, -0.08],
		[zf + 0.0035, -length + 0.004], [zf + 0.008, -length], [zb - 0.006, -length],
		[zb - 0.001, -length + 0.006], [zb + 0.001, -0.06], [zb + 0.0025, -0.03],
		[zb + 0.006, -0.012],
	]
	var core = Meshgen.extrude(profile, w,
		{"bevel": 0.0035, "bevelSegments": 3, "curveSegments": 4})
	core.rotate_y(PI * 0.5)
	asm.add(core, mat_poly, {"y": oy, "z": oz, "rx": -angle})

	# Renflement de paume des deux côtés, pour que la poignée ne soit pas une planche.
	var swell = Meshgen.blob(0.008, length * 0.62, 0.03, 0.006, 3)
	for sx in [-1.0, 1.0]:
		asm.add(swell, mat_poly, {
			"x": sx * (w * 0.5 - 0.0015), "y": oy - length * 0.42,
			"z": oz + 0.0035, "rx": -angle,
		})
	# Bec de canard derrière la détente, fondu dans la carcasse.
	asm.add(Meshgen.blob(w * 0.96, 0.02, 0.024, 0.006, 3), mat_poly,
		{"y": oy + 0.005, "z": oz + 0.012, "rx": -angle * 0.6})
	# Sur-moulage caoutchouc : panneaux latéraux + galbes de doigts sur la face avant.
	asm.add(Meshgen.blob(w * 1.03, length * 0.58, 0.019, 0.005, 3), mat_rubber,
		{"y": oy - length * 0.44, "z": oz + 0.0025, "rx": -angle})
	for i in 4:
		var t := 0.15 + i * 0.2
		var yy := oy - t * length
		var zz := oz + zf + 0.001 + sin(t * PI) * 0.001
		# Rotation À LA MAIN dans le repère incliné, pour que le galbe épouse la face avant.
		var cs := cos(-angle)
		var sn := sin(-angle)
		asm.add(Meshgen.blob(w * 0.9, 0.011, 0.007, 0.003, 3), mat_rubber, {
			"y": oy + (yy - oy) * cs - (zz - oz) * sn,
			"z": oz + (yy - oy) * sn + (zz - oz) * cs,
			"rx": -angle,
		})

	# Talon de poignée et sa vis.
	var cap_y := oy - cos(angle) * length
	var cap_z := oz + sin(angle) * length
	asm.add(Meshgen.blob(w * 0.92, 0.007, 0.031, 0.0025, 2), mat_poly,
		{"y": cap_y + 0.001, "z": cap_z, "rx": -angle})
	add_screw(asm, mat_rubber, 0.0, cap_y - 0.0015, cap_z, 0.0026, "y", 0.006)


# Crosse télescopique sur tube de crosse mil-spec : 6 crans, appui-joue, passant, levier et plaque
# de couche caoutchouc.
static func add_carbine_stock(asm, mat_alu: String, mat_poly: String, mat_rubber: String,
		o: Dictionary) -> void:
	var bore: float = o["bore"]
	var z_rear: float = o["zRear"]  # la couche
	var z_front: float = o["zFront"]  # la face de carcasse
	var y_axis: float = o.get("y", bore - 0.012)
	var tube_r := 0.0146
	var length := z_rear - z_front

	asm.add(Meshgen.tube_z(tube_r, tube_r - 0.0022, length - 0.004, 18, 0.0004), mat_alu,
		{"y": y_axis, "z": (z_rear + z_front) * 0.5})
	# Écrou crénelé + plaque d'extrémité.
	asm.add(Meshgen.lathe_z([
		[0, tube_r], [0, tube_r + 0.0034], [0.0016, tube_r + 0.0038],
		[0.0085, tube_r + 0.0038], [0.01, tube_r + 0.003], [0.01, tube_r],
	], 18), mat_alu, {"y": y_axis, "z": z_front})
	for i in 6:
		var a := (float(i) / 6.0) * TAU
		asm.add(Meshgen.box(0.0022, 0.0034, 0.006, 0.0004, 1)
			.translate(0, tube_r + 0.0032, 0).rotate_z(a)
			.translate(0, y_axis, z_front + 0.005), mat_alu, {})
	# Crans de réglage sous le tube.
	for i in 6:
		var z := z_front + 0.026 + i * 0.018
		if z > z_rear - 0.02:
			break
		asm.add(Meshgen.box(0.0075, 0.0032, 0.0075, 0.0006, 1), mat_alu,
			{"y": y_axis - tube_r + 0.0008, "z": z})

	# Corps de crosse : un profil latéral extrudé sur la largeur, pour que le busc plonge et que la
	# pointe descende comme le fait une vraie crosse télescopique.
	var body_len := 0.104
	var bz := z_rear - body_len * 0.5
	var comb_y := y_axis + 0.026
	var toe_y := y_axis - 0.042
	var outline := [
		[-body_len * 0.5, y_axis + 0.004],
		[-body_len * 0.5 + 0.012, y_axis + 0.017],
		[-body_len * 0.5 + 0.03, comb_y - 0.002],
		[body_len * 0.5 - 0.012, comb_y],
		[body_len * 0.5, comb_y - 0.006],
		[body_len * 0.5, toe_y + 0.008],
		[body_len * 0.5 - 0.008, toe_y],
		[-body_len * 0.5 + 0.028, toe_y + 0.006],
		[-body_len * 0.5 + 0.008, y_axis - 0.02],
		[-body_len * 0.5, y_axis - 0.009],
	]
	var shell_parts := []
	shell_parts.append(Meshgen.extrude(outline, 0.043, {"bevel": 0.0035, "bevelSegments": 2})
		.rotate_y(PI * 0.5))
	shell_parts.append(Meshgen.blob(0.047, 0.012, body_len * 0.66, 0.005, 3)
		.translate(0, comb_y - 0.002, -0.006))
	for sx in [-1.0, 1.0]:
		shell_parts.append(Meshgen.blob(0.005, 0.024, 0.052, 0.005, 3)
			.translate(sx * 0.0205, y_axis - 0.012, 0.004))
	asm.add(Meshgen.merge_all(shell_parts), mat_poly, {"z": bz})

	# Levier de réglage sous la crosse.
	asm.add(Meshgen.extrude([
		[-0.014, 0], [0.016, 0], [0.018, -0.007],
		[0.012, -0.011], [-0.012, -0.011], [-0.016, -0.005],
	], 0.014, {"bevel": 0.0008}), mat_poly, {"y": y_axis - 0.036, "z": bz + 0.012})

	# Plaque de couche caoutchouc, avec de vraies rainures, suivant l'inclinaison busc-pointe.
	asm.add(Meshgen.blob(0.045, 0.072, 0.013, 0.0045, 3), mat_rubber,
		{"y": y_axis - 0.008, "z": z_rear - 0.004, "rx": 0.06})
	for i in 5:
		asm.add(Meshgen.box(0.043, 0.0035, 0.005, 0.0012, 2), mat_rubber,
			{"y": y_axis + 0.02 - i * 0.0125, "z": z_rear + 0.0026, "rx": 0.06})

	add_sling_loop(asm, mat_alu, 0.0225, y_axis - 0.026, bz - 0.03, 0.0075, {"ry": PI * 0.5})
	add_qd_socket(asm, mat_poly, mat_alu, -0.0215, y_axis - 0.014, bz - 0.026, "x", 0.005)


# =================================================================================================
# CHARGEUR
# =================================================================================================

# Chargeur boîte polymère. Légère courbure, nervures moulées, trous témoins, plaque de fond à
# ergot, lèvres d'alimentation et cartouche visible au sommet.
# Bâti dans son propre repère : origine au sommet des lèvres, +Y en haut, le corps vers le bas.
static func build_magazine(asm, mats, o: Dictionary) -> Dictionary:
	var w: float = o.get("w", 0.0255)
	var d: float = o.get("d", 0.0655)
	var length: float = o.get("len", 0.215)
	# Flèche de la courbe d'alimentation, EN MÈTRES, sur la longueur du chargeur.
	var curve: float = o.get("curve", 0.028)
	var segs: int = o.get("segs", 8)
	var poly: String = o.get("poly", "polymer")

	# Arc : y descend, z se cambre vers l'avant (−Z), et chaque tranche est tournée sur la tangente
	# locale pour que la pile lise comme UN corps courbe continu.
	var step := length / float(segs)
	var body_parts := []
	var rib_parts := []
	for i in segs:
		var t := (float(i) + 0.5) / float(segs)
		var p := _mag_at(t, length, curve)
		var taper := 1.0 - t * 0.04
		body_parts.append(
			Meshgen.extrude(Meshgen.round_rect(w * taper, d * taper, 0.0055, 5), step * 1.06,
				{"bevel": 0.0008})
			.rotate_x(PI * 0.5 + float(p["tilt"]))
			.translate(0, float(p["y"]), float(p["z"])))
		# Nervures de préhension moulées sur les flancs.
		if i > 0 and i < segs - 1:
			for sx in [-1.0, 1.0]:
				rib_parts.append(Meshgen.box(0.0018, step * 0.62, d * 0.66, 0.0005, 1)
					.rotate_x(float(p["tilt"]))
					.translate(sx * (w * taper * 0.5), float(p["y"]), float(p["z"])))

	# Lèvres d'alimentation : deux rails de part et d'autre de la bouche, plus le cran arrière.
	var lip = Meshgen.extrude([
		[-0.0032, 0], [0.0032, 0], [0.0026, 0.009], [-0.0026, 0.009],
	], d * 0.9, {"bevel": 0.0005})
	lip.rotate_y(PI * 0.5)
	for sx in [-1.0, 1.0]:
		body_parts.append(lip.clone().translate(sx * (w * 0.5 - 0.0032), -0.0015, 0))
	body_parts.append(Meshgen.box(0.008, 0.0075, 0.0055, 0.0009, 1)
		.translate(0, -0.03, d * 0.5 + 0.0015))

	# Plaque de fond + ergot, sur la tangente de l'arc.
	var end := _mag_at(1.0, length, curve)
	body_parts.append(
		Meshgen.extrude(Meshgen.round_rect(w + 0.0026, d * 0.97, 0.004, 4), 0.01, {"bevel": 0.001})
		.rotate_x(PI * 0.5 + float(end["tilt"]))
		.translate(0, float(end["y"]) - 0.0035, float(end["z"])))
	body_parts.append(Meshgen.box(w + 0.0034, 0.007, 0.013, 0.0016, 2)
		.rotate_x(float(end["tilt"]))
		.translate(0, float(end["y"]) - 0.007, float(end["z"]) - d * 0.4))
	# Patin de base, un lot de polymère légèrement différent.
	var pad = Meshgen.extrude(Meshgen.round_rect(w + 0.003, d * 0.9, 0.004, 4), 0.005,
		{"bevel": 0.0009}) \
		.rotate_x(PI * 0.5 + float(end["tilt"])) \
		.translate(0, float(end["y"]) - 0.0105, float(end["z"]))

	asm.add(Meshgen.merge_all(body_parts), poly, {})
	var ribs = Meshgen.merge_all(rib_parts)
	if ribs != null:
		asm.add(ribs, poly, {})
	asm.add(pad, "rubber", {})

	# Trous témoins : fentes sombres en creux des deux côtés.
	var holes: int = o.get("witness", 4)
	for i in holes:
		var t := 0.26 + (float(i) / float(maxi(1, holes - 1))) * 0.56
		var p := _mag_at(t, length, curve)
		for sx in [-1.0, 1.0]:
			asm.add(Meshgen.extrude(Meshgen.round_rect(0.0085, 0.0044, 0.0018, 3), 0.004,
				{"bevel": 0.0004})
				.rotate_y(PI * 0.5).rotate_x(float(p["tilt"]))
				.translate(sx * (w * 0.5 - 0.0006), float(p["y"]), float(p["z"])),
				"cavity", {})

	# ⚠️ LA CARTOUCHE DU HAUT, sous les lèvres — « the detail everyone notices ».
	# Elle est couchée le long de la PROFONDEUR du chargeur (ogive vers l'avant, −Z) comme une vraie
	# pile, et NON en travers de sa largeur ; la cartouche est écrite culot-à-0 vers +Z, donc `ry`
	# = PI la retourne ogive en avant et le culot finit contre la paroi arrière. Tournée dans
	# l'autre sens, elle transperce le flanc du chargeur.
	var case_len: float = o.get("caseLen", 0.0446)
	var bullet_len: float = o.get("bulletLen", 0.019)
	var c := cartridge(case_len, o.get("rimR", 0.00495), bullet_len)
	var cz: float = minf(d * 0.5 - 0.0025, case_len + bullet_len - d * 0.5 + 0.0015)
	asm.add(c["brass"], "brass", {"y": -0.0085, "z": cz, "ry": PI})
	asm.add(c["bullet"], "copper", {"y": -0.0085, "z": cz, "ry": PI})
	return {"len": length, "w": w, "d": d}


# La paramétrisation de l'arc du chargeur — le `at(t)` de la référence.
static func _mag_at(t: float, length: float, curve: float) -> Dictionary:
	return {
		"y": -t * length,
		"z": -curve * t * t,
		"tilt": atan2(2.0 * curve * t, length),
	}


# =================================================================================================
# OPTIQUES ET ORGANES DE VISÉE (⭐ LOT 3D-B2 — pièce contractuelle du §2.2bis C)
# =================================================================================================

# Point rouge tubulaire (patron T2) sur montage déporté.
# Rend la position du plan de réticule pour que le rig l'aligne au centre de l'écran en ADS, plus
# le rayon d'ouverture pour le vignettage.
# Bâti centré sur (0, 0, 0) dans le repère de l'optique ; l'appelant le positionne.
static func build_optic(asm, o: Dictionary) -> Dictionary:
	var r_tube: float = o.get("rTube", 0.0155)
	var length: float = o.get("len", 0.068)
	var mat_body: String = o.get("matBody", "alu")
	var mat_steel: String = o.get("matSteel", "steel")
	var y: float = o.get("y", 0.0)
	var z: float = o.get("z", 0.0)
	var rail_top: float = o["railTop"]

	# ╔═ BUDGET DE SEGMENTS — mesuré, pas choisi au feeling ══════════════════════════════════════╗
	# ║ En ADS la bague d'objectif fait ~250 px de large : c'est la plus grande courbe de l'écran, ║
	# ║ et LE seul endroit du jeu où un polygone à 24 côtés est COMPTABLE. 56 segments mettent la  ║
	# ║ flèche de facette à 250·(1−cos 3,2°)/2 = 0,2 px, sous le seuil d'anticrénelage. Les bagues ║
	# ║ INTÉRIEURES comptent autant que l'extérieure : une frontière franche sombre/clair montre   ║
	# ║ le facettage bien plus vite qu'une surface ombrée.                                         ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var SEG := 72
	var SEG_IN := 80

	# ╔═ ⚠️⚠️ LE BUDGET D'OUVERTURE — « the whole reason the ADS frame read as a DRAINPIPE » ═════╗
	# ║ En regardant dans un tube depuis un œil fixe, l'image visible est le PLUS PETIT de deux    ║
	# ║ cônes : l'alésage oculaire vu au dégagement d'œil, et l'alésage objectif vu à              ║
	# ║ (dégagement + longueur). Avec leur ancienne géométrie — tube 70 mm, alésage droit à        ║
	# ║ 0,71·rTube, dégagement 78 mm — cela donnait :                                              ║
	# ║     oculaire   0,011 / 0,078  -> 158 px                                                    ║
	# ║     objectif   0,011 / 0,148  ->  87 px                                                    ║
	# ║ L'objectif gagnait d'un facteur 1,8, et l'image faisait 87 px pour un boîtier de 256 px :  ║
	# ║ **34 %**. Les 69 px de paroi sombre entre les deux occupaient plus d'un quart de la hauteur║
	# ║ de l'image. C'est exactement ce que décrivaient « un coin gris plat là où devrait être le  ║
	# ║ verre » et « quatre anneaux concentriques qui réduisent l'image au tiers du tube ».        ║
	# ║                                                                                            ║
	# ║ ⚠️ LE CORRECTIF N'EST NI UN MATÉRIAU NI UN COMPTE DE SEGMENTS. Un vrai point rouge s'en    ║
	# ║ sort en ayant un objectif PLUS GRAND que son ouverture de sortie : l'alésage s'ÉVASE et    ║
	# ║ l'avant du boîtier porte une cloche d'objectif. D'où :                                     ║
	# ║     alésage  12,2 mm à l'oculaire, ÉVASÉ à 16,5 mm à l'objectif                            ║
	# ║     coque    15,5 mm à l'oculaire, en cloche à 19,0 mm                                     ║
	# ║     longueur 52 mm (au lieu de 70) · dégagement 115 mm (au lieu de 78)                     ║
	# ║ ce qui aligne les deux cônes sur le même nombre — la marque d'un train optique correctement║
	# ║ diaphragmé, et la raison pour laquelle une vraie lunette n'a pas de second vignettage :    ║
	# ║     oculaire 118 px · objectif 115 px · boîtier 168 px                                     ║
	# ║ Une image de 230 px dans un boîtier de 336 px : **69 % au lieu de 34 %**.                  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var r_bore_oc := r_tube * 0.787  # 12,2 mm sur un tube de 15,5 mm
	var r_bore_ob := r_tube * 1.065  # évasé à 16,5 mm à l'objectif
	var r_bell_ob := r_tube * 1.226  # cloche d'objectif de 19,0 mm
	var z_oc := length * 0.5
	var z_ob := -length * 0.5

	# Tube principal : section droite à l'oculaire, évasement conique, puis cloche d'objectif.
	# Chaque bord porte un chanfrein de 0,3 mm — la seule chose de la silhouette qui puisse
	# accrocher une ligne spéculaire et dire que le bord a une ÉPAISSEUR.
	asm.add(Meshgen.lathe_z([
		[z_ob, r_bore_ob * 0.995],
		[z_ob + 0.0004, r_bell_ob * 0.99],
		[z_ob, r_bell_ob * 1.008],
		[z_ob + 0.0022, r_bell_ob],
		[z_ob + 0.008, r_bell_ob * 0.995],
		[z_ob + 0.014, r_tube * 1.1],
		[z_ob + 0.022, r_tube * 1.01],
		[z_ob + 0.03, r_tube],
		[z_oc - 0.012, r_tube],
		[z_oc - 0.01, r_tube * 1.05],
		[z_oc - 0.002, r_tube * 1.05],
		[z_oc - 0.0003, r_tube * 1.02],
		[z_oc, r_tube * 0.995],
		[z_oc, r_bore_oc * 1.02],
	], SEG), mat_body, {"y": y, "z": z})

	# ╔═ L'INTÉRIEUR : UN PIÈGE À LUMIÈRE, PAS UN TROU NOIR — et un CÔNE, pas un cylindre ════════╗
	# ║ `cavity` (0,0015 linéaire) n'offrait rien sur quoi la lumière d'appoint ou le rebond de    ║
	# ║ l'objectif puissent se poser. `optic_tube` est à 0,0205 linéaire, rugosité 0,9, lobe rasant║
	# ║ bridé : toujours noir, mais un noir avec un dégradé LISIBLE.                               ║
	# ║ Et comme le cône s'ouvre à l'opposé de l'œil, la paroi est vue sous un angle bien plus     ║
	# ║ rasant que celle d'un cylindre : elle occupe un anneau de 3 px au lieu d'une bande de 69 — ║
	# ║ c'est la moitié GÉOMÉTRIQUE du correctif « tuyau de descente ».                            ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	asm.add(Meshgen.lathe_z([
		[z_ob + 0.001, r_bore_ob],
		[z_ob + 0.001, r_bore_ob * 0.985],
		[z_oc - 0.009, r_bore_oc * 0.985],
		[z_oc - 0.009, r_bore_oc],
	], SEG_IN), "optic_tube", {"y": y, "z": z})
	# ⛔ AUCUN GRADIN DE BAFFLE À L'INTÉRIEUR. Trois anneaux peu profonds ont été essayés, sur la
	# théorie que chacun ombrerait le suivant. Mesuré en ADS : ils ont fait l'INVERSE. La lèvre
	# intérieure de chaque gradin est un anneau qui fait face à l'œil, et ils ont rendu quatre
	# anneaux GRIS CLAIR concentriques. Le dégradé doit venir de la PAROI, pas de géométrie
	# dans l'alésage.

	# L'ouverture utile de l'oculaire — tout l'aval (vignettage, halo, vignettage de réticule) en
	# dérive.
	var lens_r := r_bore_oc * 0.99

	# ╔═ BAGUE DE DÉGAGEMENT D'ŒIL ══════════════════════════════════════════════════════════════╗
	# ║ Une vraie lunette a un diaphragme de champ noir juste derrière la lentille oculaire :     ║
	# ║ l'épaulement entre le verre et la paroi est à l'ombre depuis toutes les directions, et     ║
	# ║ c'est LUI qui cadre l'image. Sans lui, le bord de l'ouverture est la paroi intérieure      ║
	# ║ ÉCLAIRÉE du tube, et le « verre » lit comme un trou percé. 1,2 mm de profondeur et pas     ║
	# ║ plus — au-delà c'est un anneau concentrique de plus.                                       ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	asm.add(Meshgen.lathe_z([
		[0, lens_r * 0.998],
		[0.0012, lens_r * 1.012],
		[0.0034, r_bore_oc * 1.01],
		[0.0038, r_tube * 1.0],
		[0.0038, r_bore_oc],
		[0, r_bore_oc],
	], SEG_IN), "optic_tube", {"y": y, "z": z + z_oc - 0.0045})

	# Lentilles — verre traité antireflet aux deux bouts, légèrement bombées. La teinte dépendante
	# de l'angle (verte dans l'axe, magenta à 70°) vit dans le MATÉRIAU (lot 3D-C).
	asm.add(Meshgen.lathe_z([
		[0, 0], [-0.0012, r_bore_ob * 0.58], [-0.0019, r_bore_ob * 0.985],
	], SEG_IN), "glass", {"y": y, "z": z + z_ob + 0.0055})
	asm.add(Meshgen.lathe_z([
		[0, 0], [-0.0009, lens_r * 0.6], [-0.0014, lens_r],
	], SEG_IN), "glass", {"y": y, "z": z + z_oc - 0.007, "ry": PI})

	# ╔═ LE HALO DE BORD INTÉRIEUR — un CHEVEU, et sur l'OCULAIRE seulement ══════════════════════╗
	# ║ L'indice qui dit qu'un tube contient du VERRE et non de l'air est un arc fin et très vif à ║
	# ║ un millimètre du bord de l'objectif : l'intérieur de la bague réfléchi dans la face avant. ║
	# ║ C'est une propriété de la LENTILLE, donc c'est un anneau additif de 0,4 mm posé SUR le     ║
	# ║ verre, et surtout pas une bande claire peinte sur la bague — c'est précisément le mode de  ║
	# ║ défaillance qui produisait « l'anneau crème » autour de la lèvre avant.                    ║
	# ║ ⚠️ Premier essai : 0,90 à 0,965 du rayon utile à intensité 0,55 → une bande blanche cramée ║
	# ║ de 12 px tout autour de l'image, **pire que le défaut qu'elle remplaçait**. À 0,965-0,99   ║
	# ║ elle fait 0,4 mm, soit ~4 px en ADS plein cadre.                                           ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	asm.add(Meshgen.flat_ring(lens_r * 0.965, lens_r * 0.99, SEG_IN), "lens_ring",
		{"y": y, "z": z + z_oc - 0.0066})

	# VIGNETTAGE DE TUBE : 6 à 8 % d'assombrissement vers le bord de la pupille de sortie, dû au
	# diaphragme de champ et à la paroi qui mangent les rayons extérieurs. Un disque plat à rampe
	# alpha radiale, juste derrière le verre oculaire.
	asm.add(Meshgen.disc(lens_r * 0.995, SEG_IN), "lens_vig",
		{"y": y, "z": z + z_oc - 0.0085})

	# Tourelles : dérive à droite, hausse en haut, chacune un capuchon moleté à graduation gravée.
	# ⚠️ La graduation est de la VRAIE GÉOMÉTRIE dans le repère local de la pièce, et non un décalque
	# projeté : elle ne peut donc jamais « nager » quand le viewmodel s'anime. Même raison que pour
	# le poinçon plus bas.
	var turret = Meshgen.merge_all([
		Meshgen.lathe_z([
			[0, 0.0062], [0.004, 0.0075], [0.0075, 0.0075], [0.0085, 0.0068],
			[0.0125, 0.0068], [0.0128, 0.006], [0.0128, 0],
		], 32),
		Meshgen.knurl_band(0.0072, 0.0052, 26, 0.00032, 3).translate(0, 0, 0.0102),
	])
	# Traits de clic gravés sur la jupe : 12 tirets courts en creux et un index long, taillés dans
	# le matériau `cavity` pour que chacun lise comme une ligne SOMBRE.
	var mark_parts := []
	for i in 12:
		var a := (float(i) / 12.0) * TAU
		var h: float = 0.0026 if i == 0 else 0.0014
		mark_parts.append(Meshgen.box(0.00035, h, 0.0006, 0.00008, 1)
			.rotate_z(a)
			.translate(cos(a) * (0.0075 - h * 0.42), sin(a) * (0.0075 - h * 0.42), 0))
	var marks = Meshgen.merge_all(mark_parts)
	# Hausse en haut (son +Z local finit le long de +Y), dérive à droite (+X).
	var elev := {"y": y + r_tube * 0.9, "z": z + 0.004, "rx": -PI * 0.5}
	var wind := {"x": r_tube * 0.9, "y": y, "z": z + 0.004, "ry": PI * 0.5}
	asm.add(turret, mat_body, elev)
	asm.add(turret, mat_body, wind)
	var elev_marks := elev.duplicate()
	elev_marks["y"] = float(elev["y"]) + 0.0055
	var wind_marks := wind.duplicate()
	wind_marks["x"] = float(wind["x"]) + 0.0055
	asm.add(marks, "cavity", elev_marks)
	asm.add(marks, "cavity", wind_marks)

	# Bouchon de pile / molette de luminosité, à gauche.
	asm.add(Meshgen.lathe_z([
		[0, 0.008], [0.005, 0.0092], [0.0125, 0.0092], [0.0128, 0.008], [0.0128, 0],
	], 32), mat_body, {"x": -r_tube * 0.9, "y": y, "z": z - 0.006, "ry": -PI * 0.5})
	asm.add(Meshgen.knurl_band(0.0094, 0.006, 26, 0.00028, 3), mat_body,
		{"x": -r_tube * 0.9 - 0.008, "y": y, "z": z - 0.006, "ry": -PI * 0.5})

	# ╔═ LE MONTAGE — et pourquoi il est ÉTROIT et n'entre JAMAIS dans l'alésage ═════════════════╗
	# ║ Un pied déporté fin, serré sur le rail par deux boulons. Le pied est ÉTROIT (9 mm) et      ║
	# ║ taillé en taille de guêpe : un bloc pleine largeur sous le tube est **la seule chose qui   ║
	# ║ fasse lire un point rouge comme une pièce de plomberie** quand on regarde droit dedans.    ║
	# ║ `mountTop` est TANGENT à la paroi extérieure du tube. Il valait `y − rTube*0,35`, ce qui   ║
	# ║ mettait la face supérieure du pied 5 mm AU-DESSUS du plancher de l'alésage — donc en ADS   ║
	# ║ une dalle grise éclairée coupait net le tiers inférieur de l'image.                        ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var mount_top := y - r_tube
	var mount_h := mount_top - rail_top
	asm.add(Meshgen.extrude([
		[-0.0092, 0], [0.0092, 0], [0.0105, -0.0025],
		[0.0072, -mount_h * 0.45], [0.0072, -mount_h + 0.005],
		[0.013, -mount_h + 0.0018], [0.013, -mount_h],
		[-0.013, -mount_h], [-0.013, -mount_h + 0.0018],
		[-0.0072, -mount_h + 0.005], [-0.0072, -mount_h * 0.45], [-0.0105, -0.0025],
	], 0.03, {"bevel": 0.0008}), mat_body, {"y": mount_top, "z": z + 0.002})
	# Colliers autour du tube.
	var clamp = Meshgen.lathe_z([
		[0, r_tube], [0, r_tube + 0.0035], [0.0055, r_tube + 0.0035], [0.0055, r_tube],
	], SEG)
	asm.add(clamp, mat_body, {"y": y, "z": z - 0.014})
	asm.add(clamp, mat_body, {"y": y, "z": z + 0.012})
	for cz in [z - 0.0115, z + 0.0145]:
		add_screw(asm, mat_steel, 0.0135, mount_top - 0.004, cz, 0.0028, "x", 0.01)
	# Tenon de recul + boulons de serrage sur rail.
	asm.add(Meshgen.box(0.032, 0.006, 0.03, 0.0008, 1), mat_body,
		{"y": rail_top + 0.001, "z": z + 0.002})
	add_screw(asm, mat_steel, 0.0165, rail_top + 0.001, z - 0.008, 0.003, "x", 0.012)
	add_screw(asm, mat_steel, 0.0165, rail_top + 0.001, z + 0.012, 0.003, "x", 0.012)

	# ╔═ ⚠️⚠️ LE BANDEAU OCULAIRE EN CAOUTCHOUC — le correctif de « l'anneau crème » ═════════════╗
	# ║ MESURÉ, en cartographiant radialement l'image ADS contre le rayon connu de chaque élément :║
	# ║ la bande chaude et vive que la critique appelait « un bord de MDF non peint » se trouvait  ║
	# ║ au rayon écran 225-262 px, soit le chanfrein arrière du tube et son flanc extérieur, à     ║
	# ║ 1,00-1,05 rTube. **Ce n'est PAS de l'albédo** — un oxyde anodisé à 0,003 linéaire ne peut  ║
	# ║ pas atteindre 200 sRGB — c'est le lobe spéculaire RASANT : ces deux surfaces sont presque  ║
	# ║ de chant vis-à-vis de l'œil et tombent pile dans le chemin de réflexion de la lumière de   ║
	# ║ contour chaude du viewmodel.                                                               ║
	# ║                                                                                            ║
	# ║ **Il faut DEUX choses, et aucune ne suffit seule.** Le bridage du matériau baisse           ║
	# ║ l'amplitude ; mais tant que c'est une surface d'ALUMINIUM que l'œil regarde, à 89° quelque  ║
	# ║ chose s'allumera toujours. Donc l'arrière de la lunette CESSE D'ÊTRE EN ALUMINIUM : le      ║
	# ║ bandeau caoutchouc couvre la lèvre d'alésage, tout l'anneau arrière, le chanfrein ET        ║
	# ║ descend 6 mm sur le flanc extérieur, jusqu'à 1,10 rTube — au-delà du point le plus large du║
	# ║ boîtier, si bien que **tout le cercle extérieur de l'optique en ADS est du caoutchouc       ║
	# ║ moulé**. Ce qui est aussi la fonction et la place d'un vrai pare-chocs de lunette.          ║
	# ║ `rubber` et non `cavity` : `cavity` est à 0,0015 linéaire et non éclairé, il lirait comme   ║
	# ║ un trou percé dans l'image. Le caoutchouc moulé est presque aussi sombre mais il prend le   ║
	# ║ masque d'usure et un léger dégradé — il lit comme une SURFACE.                              ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	asm.add(Meshgen.lathe_z([
		[0, r_bore_oc * 0.995],
		[0.0004, r_bore_oc * 1.03],
		[0.0009, r_tube * 1.02],
		[0.0018, r_tube * 1.075],
		[0.0055, r_tube * 1.1],
		[0.0072, r_tube * 1.09],
		[-0.0042, r_tube * 1.085],
		[-0.0048, r_tube * 1.03],
	], SEG), "rubber", {"y": y, "z": z + z_oc - 0.0012})

	# Pare-soleil d'objectif. Il chevauche la CLOCHE, donc il est plus large que le tube et (comme
	# la cloche) se projette encore à l'intérieur du bord oculaire en ADS : il ne peut jamais briser
	# la silhouette du boîtier. L'intérieur est en matériau piège-à-lumière pour la même raison que
	# l'alésage : une paroi anodisée quasi cylindrique pointée vers le ciel est l'AUTRE endroit d'où
	# venait l'anneau crème.
	var hood_len: float = o.get("hood", 0.009)
	asm.add(Meshgen.lathe_z([
		[0, r_bell_ob * 1.0],
		[0, r_bell_ob * 1.05],
		[hood_len - 0.0003, r_bell_ob * 1.05],
		[hood_len, r_bell_ob * 1.035],
		[hood_len, r_bell_ob * 0.99],
	], SEG), mat_body, {"y": y, "z": z + z_ob - hood_len + 0.0015})
	asm.add(Meshgen.tube_z(r_bell_ob * 1.035, r_bell_ob * 0.998, hood_len - 0.0008, SEG, 0.0002),
		"optic_tube", {"y": y, "z": z + z_ob - hood_len * 0.5 + 0.0015})
	# Un pare-chocs caoutchouc sur le bord de l'objectif aussi — même argument que l'oculaire, et
	# c'est la partie de l'optique qui fait face à la caméra en tir à la hanche.
	asm.add(Meshgen.lathe_z([
		[0, r_bell_ob * 1.01],
		[0.0006, r_bell_ob * 1.075],
		[0.0038, r_bell_ob * 1.08],
		[0.005, r_bell_ob * 1.03],
	], SEG), "rubber", {"y": y, "z": z + z_ob - hood_len - 0.0035})

	return {
		"center": Vector3(0, y, z),
		"lensZ": z + z_oc - 0.007,
		# La pupille de sortie contre laquelle le réticule vignette EST l'ouverture utile oculaire.
		"apertureR": lens_r * 0.94,
		"tubeR": r_tube,
		"len": length,
	}


# ╔═ POINÇON / MARQUAGE DE CALIBRE GRAVÉ ════════════════════════════════════════════════════════╗
# ║ Une carcasse usinée en porte toujours un, et c'est l'un des très rares indices qui dise à     ║
# ║ l'œil que la surface est du MÉTAL passé sous presse plutôt qu'une coque moulée.               ║
# ║ ⚠️ Il est modélisé en VRAIS traits en creux dans le repère local de la pièce — surtout pas un ║
# ║ décalque projeté — précisément parce que le viewmodel translate et tourne à chaque frame :    ║
# ║ tout ce qui est échantillonné en espace MONDE nage à travers la carcasse.                     ║
# ║ À 0,35 m un poinçon de 4 mm fait ~12 px de haut : ce qui doit être juste, c'est le RYTHME des ║
# ║ traits et le soulignement, pas la forme des lettres. Le motif est FIXE, donc le marquage est  ║
# ║ identique bit à bit à chaque boot (reproductibilité des captures).                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func add_rollmark(asm, mat: String, o: Dictionary) -> void:
	var h: float = o.get("h", 0.0036)
	var stroke: float = o.get("stroke", 0.0006)
	var depth: float = o.get("depth", 0.0008)
	var pitch: float = o.get("pitch", 0.0017)
	var pat: Array = o.get("pattern",
		[3, 2, 3, 3, 1, 0, 2, 3, 2, 3, 0, 3, 1, 2, 3, 2, 0, 3, 3, 2])
	var n: int = o.get("count", pat.size())
	var parts := []
	for i in n:
		var p: int = pat[i % pat.size()]
		if p == 0:
			continue
		var bh := h * (0.52 + p * 0.16)
		parts.append(Meshgen.box(depth, bh, stroke, 0.00008, 1)
			.translate(0, (h - bh) * 0.5, -i * pitch))
		if p == 3:
			# Une barre transversale, pour qu'une suite de traits lise comme des lettres et non
			# comme un peigne.
			parts.append(Meshgen.box(depth, stroke * 0.85, pitch * 0.72, 0.00008, 1)
				.translate(0, (h - bh) * 0.5 + bh * 0.16, -i * pitch - pitch * 0.3))
	parts.append(Meshgen.box(depth, stroke * 0.9, (n - 1) * pitch, 0.00008, 1)
		.translate(0, -h * 0.55, -(n - 1) * pitch * 0.5))
	var g = Meshgen.merge_all(parts)
	if o.has("sx"):
		g.scale_by(float(o["sx"]), 1.0, 1.0)
	asm.add(g, mat, {"x": o.get("x", 0.0), "y": o.get("y", 0.0), "z": o.get("z", 0.0)})


# Guidon rabattable : montant, oreilles de protection, charnière, cran.
static func add_front_sight(asm, mat_steel: String, mat_alu: String,
		x: float, rail_top: float, z: float, up := true) -> void:
	asm.add(Meshgen.box(0.024, 0.008, 0.019, 0.0008, 1), mat_alu,
		{"x": x, "y": rail_top + 0.004, "z": z})
	asm.add(Meshgen.rod_z(0.0026, 0.0026, 0.026, 10, 0.0003), mat_steel,
		{"x": x, "y": rail_top + 0.008, "z": z + 0.006, "ry": PI * 0.5})

	var h: float = 0.03 if up else 0.006
	var tilt: float = 0.0 if up else -1.35
	var ear_l = Meshgen.extrude([
		[-0.0022, 0], [0.0022, 0], [0.0022, h], [0, h + 0.002], [-0.0022, h],
	], 0.0075, {"bevel": 0.0005})
	var ears := []
	for sx in [-1.0, 1.0]:
		ears.append(ear_l.clone().translate(sx * 0.0088, 0, 0))
	# Le montant lui-même.
	ears.append(Meshgen.rod_z(0.0011, 0.0009, h * 0.72, 8, 0.0002)
		.rotate_x(PI * 0.5).translate(0, h * 0.36 + 0.002, 0))
	ears.append(Meshgen.box(0.019, 0.0022, 0.0055, 0.0004, 1).translate(0, h - 0.0012, 0))
	asm.add(Meshgen.merge_all(ears), mat_steel,
		{"x": x, "y": rail_top + 0.008, "z": z, "rx": tilt})


# Hausse rabattable : œilleton, tambour de dérive, ailettes de protection.
static func add_rear_sight(asm, mat_steel: String, mat_alu: String,
		x: float, rail_top: float, z: float, up := true) -> void:
	asm.add(Meshgen.box(0.024, 0.0085, 0.022, 0.0008, 1), mat_alu,
		{"x": x, "y": rail_top + 0.0042, "z": z})
	var h: float = 0.027 if up else 0.005
	var tilt: float = 0.0 if up else 1.35
	var parts := []
	parts.append(Meshgen.extrude([
		[-0.011, 0], [0.011, 0], [0.011, h * 0.55],
		[0.006, h], [-0.006, h], [-0.011, h * 0.55],
	], 0.006, {"bevel": 0.0006}))
	parts.append(Meshgen.ring(0.0032, 0.0011, 14, 6).translate(0, h * 0.66, 0))
	# ╔═ TAMBOUR DE DÉRIVE — MOLETÉ, et la moleture n'est PAS de la décoration ═══════════════════╗
	# ║ MESURÉ : en tour lisse à 12 côtés, ce tambour de 10 mm rendait une perle spéculaire à      ║
	# ║ L = 188 au tir à la hanche, **la chose la plus brillante de toute la moitié avant de       ║
	# ║ l'arme**. C'est un métal : `specularIntensity` n'y peut RIEN (à metalness 1 l'albédo est   ║
	# ║ replié dans le F0) et baisser le F0 deux fois ne l'a déplacée que d'un cinquième de        ║
	# ║ diaphragme — **un métal convexe lisse face à la lumière du viewmodel EST un miroir par     ║
	# ║ construction, et la seule chose qui casse un miroir est la COURBURE de surface.**          ║
	# ║ Un vrai tambour est moleté pour qu'on le tourne avec les doigts mouillés. 22 cannelures    ║
	# ║ dispersent le lobe en 22 minuscules éclats au lieu d'une perle : correct ET auto-résolutif.║
	# ║ Le compte de segments passe aussi de 12 à 20 — un 12-gone sur une pièce de 10 mm à 0,44 m  ║
	# ║ de l'œil a des facettes comptables.                                                        ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var drum_g = Meshgen.merge_all([
		Meshgen.lathe_z([
			[0, 0], [0, 0.0048], [0.0035, 0.0052], [0.008, 0.0052], [0.008, 0],
		], 20),
		Meshgen.knurl_band(0.0053, 0.0042, 22, 0.00028, 3).translate(0, 0, 0.0055),
	])
	drum_g.rotate_y(PI * 0.5).translate(0.012, h * 0.3, 0)
	parts.append(drum_g)
	asm.add(Meshgen.merge_all(parts), mat_steel,
		{"x": x, "y": rail_top + 0.0085, "z": z, "rx": tilt})


# Levier d'armement AR : verrou, barre en T, ailes nervurées. Bouge d'une seule pièce (lot 3D-E).
static func charging_handle_part():
	var parts := []
	parts.append(Meshgen.box(0.028, 0.0055, 0.052, 0.0008, 1).translate(0, 0, 0.012))
	parts.append(Meshgen.rod_z(0.0055, 0.0055, 0.07, 12, 0.0005).translate(0, -0.0022, -0.02))
	var wing = Meshgen.extrude([
		[0, -0.005], [0.02, -0.0075], [0.024, -0.002], [0.024, 0.004], [0.0, 0.004],
	], 0.0055, {"bevel": 0.0007})
	parts.append(wing.clone().rotate_y(PI * 0.5).translate(0.012, 0.0, 0.034))
	parts.append(wing.clone().rotate_y(-PI * 0.5).translate(-0.012, 0.0, 0.034))
	for i in 3:
		for sx in [-1.0, 1.0]:
			parts.append(Meshgen.box(0.0022, 0.0075, 0.0016, 0.0003, 1)
				.translate(sx * (0.017 + i * 0.003), 0.0, 0.031 + i * 0.0022))
	# ╔═ LE VERROU ══════════════════════════════════════════════════════════════════════════════╗
	# ║ « A charging handle without one is a T-shaped tab and reads as a MOULDED LUG ; the latch   ║
	# ║ is what says "this part is a MECHANISM that has to be released before it moves". »         ║
	# ║ C'est un levier crochu séparé, sur l'aile GAUCHE — le côté qui fait face à la caméra dans  ║
	# ║ la pose de tir à la hanche — pivotant sur une goupille visible, le crochet SAILLANT hors   ║
	# ║ de l'aile pour qu'il BRISE la silhouette au lieu d'y creuser une rainure.                  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	parts.append(Meshgen.extrude([
		[0, -0.0032], [0.0165, -0.0042], [0.0205, -0.0018],
		[0.0205, 0.0026], [0.0155, 0.0042], [0, 0.0034],
	], 0.0042, {"bevel": 0.0006}).rotate_y(-PI * 0.5).translate(-0.0125, 0.0012, 0.0335))
	# Le crochet qui engage l'épaulement de carcasse : saillant de 1,6 mm, pointant vers l'avant.
	parts.append(Meshgen.box(0.0038, 0.0052, 0.0032, 0.0005, 1)
		.translate(-0.0295, 0.0006, 0.0292))
	# Goupille de pivot à travers l'aile, et pastille de doigt sur la queue du levier.
	parts.append(Meshgen.rod_z(0.0011, 0.0011, 0.0072, 8, 0.0002)
		.rotate_y(PI * 0.5).translate(-0.0135, 0.0012, 0.0356))
	parts.append(Meshgen.box(0.0028, 0.0062, 0.0075, 0.0004, 1)
		.translate(-0.0316, 0.0014, 0.0345))
	return Meshgen.merge_all(parts)


# Poignée avant verticale / inclinée, pour la mitraillette.
static func add_fore_grip(asm, mat_poly: String, mat_rubber: String, o: Dictionary) -> void:
	var length: float = o.get("len", 0.062)
	var angle: float = o.get("angle", 0.25)
	var parts := []
	for i in 5:
		var t := float(i) / 4.0
		parts.append(Meshgen.blob(0.026 - t * 0.003, length / 5.0 + 0.003,
			0.03 - t * 0.004, 0.005, 3).translate(0, -t * length, t * 0.008))
	asm.add(Meshgen.merge_all(parts), mat_poly, {"y": o["y"], "z": o["z"], "rx": angle})
	var grip_parts := []
	for i in 4:
		var t := 0.15 + i * 0.23
		grip_parts.append(Meshgen.box(0.024, 0.006, 0.0055, 0.002, 2)
			.translate(0, -t * length, -0.013))
	asm.add(Meshgen.merge_all(grip_parts), mat_rubber,
		{"y": o["y"], "z": o["z"], "rx": angle})


# Mini viseur reflex (patron RMR) : cadre ouvert à fenêtre inclinée, capot, boîtier d'émetteur,
# tiroir de pile et deux vis de montage.
static func build_mini_reflex(asm, o: Dictionary) -> Dictionary:
	var w: float = o.get("w", 0.0246)
	var h: float = o.get("h", 0.021)
	var length: float = o.get("len", 0.0455)
	var y: float = o.get("y", 0.0)
	var z: float = o.get("z", 0.0)
	var mat_body: String = o.get("matBody", "alu")
	var glass_tilt: float = o.get("tilt", 0.16)  # fenêtre inclinée vers l'arrière, comme la vraie

	asm.add(Meshgen.extrude(Meshgen.round_rect(w, length, 0.003, 3), 0.0042, {"bevel": 0.0007}),
		mat_body, {"y": y + 0.002, "z": z, "rx": PI * 0.5})

	# Deux flancs qui s'effilent vers l'avant, réunis par le capot.
	var wall = Meshgen.extrude([
		[-length * 0.5, 0], [length * 0.42, 0], [length * 0.46, h * 0.52],
		[length * 0.3, h * 0.86], [-length * 0.42, h], [-length * 0.5, h * 0.92],
	], 0.0036, {"bevel": 0.0007})
	for sx in [-1.0, 1.0]:
		asm.add(wall, mat_body,
			{"x": sx * (w * 0.5 - 0.0018), "y": y + 0.004, "z": z, "ry": PI * 0.5})

	asm.add(Meshgen.box(w, 0.0035, 0.011, 0.0008, 1), mat_body,
		{"y": y + h * 0.98, "z": z - length * 0.36})
	asm.add(Meshgen.blob(w - 0.007, 0.0075, 0.012, 0.0016, 2), mat_body,
		{"y": y + 0.0075, "z": z - length * 0.3})
	asm.add(Meshgen.lathe_z([[0, 0], [0, 0.0016], [0.0012, 0.0018], [0.0012, 0]], 10),
		"steel_bright", {"y": y + 0.0105, "z": z - length * 0.28, "rx": -0.5})

	add_screw(asm, "steel", 0.0, y + 0.004, z + length * 0.4, 0.0026, "y", 0.008)
	add_screw(asm, "steel", w * 0.5 - 0.002, y + h * 0.5, z + length * 0.28, 0.0022, "x", 0.006)
	add_screw(asm, "steel", 0.0, y + h * 0.86, z + length * 0.1, 0.0022, "y", 0.006)

	# La fenêtre : une vraie vitre, inclinée vers l'arrière, dans un cadre biseauté.
	var glass_w := w - 0.007
	var glass_h := h * 0.72
	asm.add(Meshgen.extrude(Meshgen.round_rect(glass_w, glass_h, 0.0015, 3), 0.0012,
		{"bevel": 0.0003}), "glass",
		{"y": y + h * 0.56, "z": z + length * 0.14, "rx": glass_tilt})
	asm.add(Meshgen.extrude(Meshgen.round_rect(glass_w + 0.0028, glass_h + 0.0028, 0.0018, 3),
		0.0022, {
			"bevel": 0.0005,
			"holes": [Meshgen.round_rect(glass_w - 0.0002, glass_h - 0.0002, 0.0014, 3)],
		}), mat_body, {"y": y + h * 0.56, "z": z + length * 0.14, "rx": glass_tilt})

	return {
		"center": Vector3(0, y + h * 0.56, z + length * 0.14),
		"lensZ": z + length * 0.14,
		"apertureR": minf(glass_w, glass_h) * 0.46,
		"windowW": glass_w * 0.46,
		"windowH": glass_h * 0.46,
		"tilt": glass_tilt,
	}


# Glissière de pistolet : un bloc usiné, crans de préhension avant et arrière, allègements,
# fenêtre d'éjection, capot de chambre, queues d'aronde de visée et face de culasse.
# Bâtie dans le repère de la glissière, origine sur l'axe du canon, pour que le rig la fasse
# reculer droit selon +Z.
static func build_slide(asm, o: Dictionary) -> Dictionary:
	var w: float = o.get("w", 0.0262)
	var h: float = o.get("h", 0.0248)
	var length: float = o.get("len", 0.183)
	var mat: String = o.get("mat", "steel")
	var z_rear: float = o.get("zRear", 0.052)
	var z_front := z_rear - length
	var cz := (z_rear + z_front) * 0.5
	var bore := 0.0

	asm.add(Meshgen.box(w, h, length, 0.0016, 2), mat, {"y": bore + 0.0015, "z": cz})
	asm.add(Meshgen.box(w - 0.008, 0.004, length - 0.02, 0.0012, 2), mat,
		{"y": bore + h * 0.5 + 0.0025, "z": cz - 0.004})
	# Biseau de nez.
	asm.add(Meshgen.extrude([
		[-w * 0.5, -h * 0.5], [w * 0.5, -h * 0.5], [w * 0.5, h * 0.34],
		[w * 0.36, h * 0.5], [-w * 0.36, h * 0.5], [-w * 0.5, h * 0.34],
	], 0.016, {"bevel": 0.0012}), mat, {"y": bore + 0.0015, "z": z_front + 0.008})

	# Crans de préhension, avant et arrière.
	for pair in [[z_rear - 0.006, 7], [z_front + 0.03, 5]]:
		for i in int(pair[1]):
			asm.add(Meshgen.box(w + 0.0006, h * 0.62, 0.0026, 0.0006, 1), mat,
				{"y": bore + 0.0015, "z": float(pair[0]) - i * 0.0052})

	# Allègements sur les flancs.
	for sx in [-1.0, 1.0]:
		asm.add(Meshgen.extrude(Meshgen.round_rect(0.042, h * 0.4, 0.004, 3), 0.0016,
			{"bevel": 0.0005}), mat,
			{"x": sx * (w * 0.5 - 0.0004), "y": bore + 0.001, "z": cz - 0.012, "ry": PI * 0.5})

	# Fenêtre d'éjection avec une vraie cavité et un capot de chambre.
	var port_w := 0.036
	var port_h := 0.0135
	asm.add(Meshgen.box(0.01, port_h, port_w, 0.0008, 1), "cavity",
		{"x": w * 0.5 - 0.006, "y": bore + 0.004, "z": z_rear - 0.05, "ry": PI * 0.5})
	asm.add(Meshgen.extrude(Meshgen.round_rect(port_w + 0.004, port_h + 0.004, 0.002, 3), 0.002, {
		"bevel": 0.0005,
		"holes": [Meshgen.round_rect(port_w, port_h, 0.0016, 3)],
	}), mat, {"x": w * 0.5 - 0.0009, "y": bore + 0.004, "z": z_rear - 0.05, "ry": PI * 0.5})

	# Face de culasse + extracteur.
	asm.add(Meshgen.box(w - 0.006, h - 0.008, 0.004, 0.0008, 1), "steel_bright",
		{"y": bore + 0.001, "z": z_rear - 0.032})

	# ⭐ ORGANES DE VISÉE MÉCANIQUES — §2.2quinquies : le P-19 n'a AUCUNE OPTIQUE, sa hausse en U
	# carré est nettement visible au-dessus de la glissière. C'est ce qui le distingue à l'œil des
	# trois autres armes, et il ne faut surtout pas l'« harmoniser » en lui greffant un point rouge.
	asm.add(Meshgen.extrude([
		[-0.009, 0], [0.009, 0], [0.009, 0.0055], [0.0022, 0.0055],
		[0.0022, 0.0022], [-0.0022, 0.0022], [-0.0022, 0.0055], [-0.009, 0.0055],
	], 0.0055, {"bevel": 0.0004}), "steel_bright",
		{"y": bore + h * 0.5 + 0.0045, "z": z_rear - 0.012})
	for sx in [-1.0, 1.0]:
		asm.add(Meshgen.dome(0.0011, 8, 0.5), "steel_bright",
			{"x": sx * 0.0055, "y": bore + h * 0.5 + 0.0075, "z": z_rear - 0.0148, "ry": PI})
	asm.add(Meshgen.box(0.0035, 0.0062, 0.0042, 0.0004, 1), "steel_bright",
		{"y": bore + h * 0.5 + 0.0055, "z": z_front + 0.014})
	asm.add(Meshgen.dome(0.0013, 8, 0.5), "steel_bright",
		{"y": bore + h * 0.5 + 0.0058, "z": z_front + 0.0118, "ry": PI})

	return {
		"zRear": z_rear, "zFront": z_front, "w": w, "h": h, "len": length,
		"sightY": bore + h * 0.5 + 0.0065,
	}
