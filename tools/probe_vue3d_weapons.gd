extends Node

# =================================================================================================
# SONDE §8.152 LOT 3D-B — LES QUATRE ARMES ASSEMBLÉES.
#
# ╔═ LE CONTRÔLE QUI COMPTE LE PLUS ICI N'EST PAS GÉOMÉTRIQUE ═══════════════════════════════════╗
# ║ `defs.js` mélange des valeurs de VUE et des valeurs de RÈGLE dans un même objet. Le cahier §0 ║
# ║ interdit de porter les secondes : chez nous `dispersion_deg`, `mag_size`, `reload_ticks` et   ║
# ║ la cadence viennent du SERVEUR à l'exécution. Recopier `magSize: 30` créerait une seconde     ║
# ║ source de vérité qui divergerait au premier rééquilibrage — en silence, et du seul côté que   ║
# ║ le joueur voit.                                                                               ║
# ║ **D1 est donc le contrôle central de ce lot** : il vérifie qu'AUCUN champ de règle n'a réussi ║
# ║ à se glisser dans le registre de vue. C'est un contrôle qu'on ne peut pas satisfaire par      ║
# ║ inadvertance, et qui rougirait le jour où quelqu'un « complèterait » le registre.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# CE QU'ELLE PROUVE AUSSI :
#   W1 les 4 armes se construisent, sont non vides et DÉTERMINISTES ;
#   W2 chaque arme porte les ancres dont le rig (3D-F) et les clips (3D-E) ont besoin ;
#   W3 la bouche est bien DEVANT la culasse (−Z), et l'axe de visée AU-DESSUS de l'âme ;
#   W4 ⭐ `vipere` n'a AUCUNE optique tubulaire — §2.2quinquies : c'est son identité de visée ;
#   W5 les pièces MOBILES sont des assemblages séparés (sans quoi rien ne peut être animé) ;
#   W6 aucune cartouche parasite : une seule douille chambrée, et PAS d'ogive ;
#   R1 le patron de recul est déterministe, borné, et sa VERTICALE est franchement positive
#      (une arme qui pique au tir serait un défaut de signe invisible autrement).
#
# SABOTAGES QUI DOIVENT LA FAIRE ROUGIR :
#   1. ajouter `"mag_size": 30` au registre de vue                       -> D1.
#   2. greffer une optique tubulaire sur `vipere`                        -> W4.
#   3. fusionner un sous-assemblage mobile dans le corps                 -> W5.
#   4. ajouter l'ogive de la cartouche chambrée                          -> W6.
#   5. inverser le signe de `pitch` dans le patron de recul              -> R1.
#   6. retirer une ancre (`muzzle`, `magSeat`…)                          -> W2.
#
# ⚠️ LANCEMENT (headless suffit) :
#   & <godot_console> --headless --path frontend res://tools/probe_vue3d_weapons.tscn
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const W3D := preload("res://scripts/game/trench_weapons3d.gd")

const CHECKS_ATTENDUS := 16

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
	print("\n===== SONDE §8.152 LOT 3D-B — LES QUATRE ARMES =====\n")
	print("-- D. La frontiere VUE / REGLES (le controle central) --")
	_probe_frontiere()
	print("\n-- W. Construction, ancres, identite de visee --")
	_probe_armes()
	print("\n-- R. Le patron de recul --")
	_probe_recul()
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
# D. LA FRONTIÈRE VUE / RÈGLES
# =================================================================================================
func _probe_frontiere() -> void:
	# ⚠️ Cette liste est celle des champs de `defs.js` qui décrivent ce que le JEU FAIT, par
	# opposition à ce que l'ŒIL VOIT. Elle est écrite ICI, en dur et à la main, exprès : c'est une
	# liste d'INTERDITS, pas un miroir du registre. Un test qui relirait le registre qu'il teste
	# ne testerait rien.
	var interdits := [
		"rpm", "burst_rpm", "burstRpm", "burst_count", "burstCount", "burst_delay",
		"mag_size", "magSize", "reserve", "damage", "penetration", "dropoff",
		"max_range", "maxRange", "muzzle_velocity", "muzzleVelocity", "drag_k", "dragK",
		"spread_hip", "spreadHip", "spread_ads", "spreadAds", "spread_per_shot",
		"spreadPerShot", "spread_max", "spreadMax", "spread_decay", "spreadDecay",
		"dispersion_deg", "reload_tac", "reloadTac", "reload_empty", "reloadEmpty",
		"reload_ticks", "modes", "caliber", "tracer_every", "tracerEvery",
	]
	var fautes := []
	for id in W3D.VIEW_DEFS:
		var d: Dictionary = W3D.VIEW_DEFS[id]
		for k in interdits:
			if d.has(k):
				fautes.append("%s.%s" % [id, k])
		# Le sous-objet `recoil` décrit la FORME du recul (une propriété de vue) : on y interdit
		# les mêmes champs de règle.
		if d.has("recoil"):
			for k in interdits:
				if d["recoil"].has(k):
					fautes.append("%s.recoil.%s" % [id, k])
	_ok("D1 AUCUN champ de REGLE n'a pu se glisser dans le registre de VUE",
		fautes.is_empty(), "intrus : " + str(fautes))

	# D2. Le registre couvre bien nos quatre armes, et sous NOS ids (pas les leurs).
	var manquantes := []
	for id in W3D.WEAPON_IDS:
		if not W3D.VIEW_DEFS.has(id):
			manquantes.append(id)
	_ok("D2 les 4 armes du registre serveur ont une definition de vue",
		manquantes.is_empty() and W3D.VIEW_DEFS.size() == 4,
		"ids : " + str(W3D.VIEW_DEFS.keys()))

	# D3. Les champs de VUE attendus par le rig (3D-F) et l'ADS (3D-F2) sont tous là.
	var requis := ["hip_pos", "hip_rot", "ads_cant", "eye_relief", "sprint_pos", "sprint_rot",
		"low_ready_pos", "low_ready_rot", "ads_time", "ads_fov", "view_fov",
		"sway_scale", "bob_scale", "mag_len", "recoil"]
	var trous := []
	for id in W3D.VIEW_DEFS:
		for k in requis:
			if not W3D.VIEW_DEFS[id].has(k):
				trous.append("%s.%s" % [id, k])
	_ok("D3 chaque arme porte les 15 champs de vue dont le rig aura besoin",
		trous.is_empty(), "manquants : " + str(trous))


# =================================================================================================
# W. LES ARMES
# =================================================================================================
func _probe_armes() -> void:
	var armes := {}
	for id in W3D.WEAPON_IDS:
		armes[id] = W3D.build(id)

	# W1a. Construction non vide.
	var vides := []
	var lignes := []
	for id in armes:
		var n: int = armes[id]["body"].total_tris()
		for m in armes[id]["moving"]:
			n += armes[id]["moving"][m].total_tris()
		lignes.append("%s=%d" % [id, n])
		if n == 0:
			vides.append(id)
	_ok("W1a les 4 armes produisent de la geometrie", vides.is_empty(),
		"vides : " + str(vides))
	_info("W1b budget triangles par arme (corps + pieces mobiles)", " · ".join(lignes))

	# W1c. Toutes les clés de matériau existent — le contrat avec le lot 3D-C, une arme entière
	# cette fois.
	var cles := {}
	for id in armes:
		for m in armes[id]["body"].buckets:
			cles[m] = true
		for mv in armes[id]["moving"]:
			for m in armes[id]["moving"][mv].buckets:
				cles[m] = true
	var inconnues := []
	for m in cles:
		if not WMat.has_key(m):
			inconnues.append(m)
	_ok("W1c toutes les cles de materiau des 4 armes existent dans le registre",
		inconnues.is_empty(), "%d cles · inconnues : %s" % [cles.size(), str(inconnues)])

	# W1d. DÉTERMINISME : deux constructions rendent la même chose.
	var divergent := ""
	for id in W3D.WEAPON_IDS:
		var a = _fusion(W3D.build(id)["body"])
		var b = _fusion(armes[id]["body"])
		if a == null or b == null:
			continue
		if a.positions != b.positions or a.indices != b.indices:
			divergent = id
			break
	_ok("W1d determinisme : deux constructions rendent des sommets identiques",
		divergent == "", "premiere divergence : " + divergent)

	# W2. LES ANCRES. Sans elles le rig ne peut rien monter et les clips ne peuvent rien animer.
	var requis := ["muzzle", "chamber", "eject", "ejectDir", "sight", "sightAxis",
		"gripR", "gripL", "magSeat", "magDrop", "triggerPivot", "triggerPull"]
	var trous := []
	for id in armes:
		for k in requis:
			if not armes[id]["nodes"].has(k):
				trous.append("%s.%s" % [id, k])
	_ok("W2 chaque arme porte les 12 ancres dont le rig et les clips ont besoin",
		trous.is_empty(), "manquantes : " + str(trous))

	# W3. COHÉRENCE DU REPÈRE : −Z vers la bouche, axe de visée AU-DESSUS de l'âme.
	# Un signe inversé ici retournerait l'arme dans la main, et rien d'autre ne l'attraperait.
	var fautes := []
	for id in armes:
		var n: Dictionary = armes[id]["nodes"]
		var muzzle: Vector3 = n["muzzle"]
		var chamber: Vector3 = n["chamber"]
		var sight: Vector3 = n["sight"]
		if muzzle.z >= chamber.z:
			fautes.append("%s: bouche pas devant la chambre" % id)
		if sight.y <= muzzle.y:
			fautes.append("%s: axe de visee pas au-dessus de l'ame" % id)
		if Vector3(n["sightAxis"]).z >= 0.0:
			fautes.append("%s: axe de visee ne regarde pas vers -Z" % id)
	_ok("W3 repere coherent : bouche en -Z, visee au-dessus de l'ame", fautes.is_empty(),
		"fautes : " + str(fautes))

	# ── W4. ⭐ L'IDENTITÉ DE VISÉE DE CHAQUE ARME (§2.2quinquies) ────────────────────────────────
	# « Toutes les armes n'ont PAS d'optique, et c'est précisément ce qui les différencie à l'œil. »
	# Le `vipere` se reconnaît à sa hausse en U carré au-dessus de la glissière. Lui greffer un
	# point rouge l'aplatirait sur les trois autres.
	# On le mesure par la présence des seaux d'OPTIQUE TUBULAIRE (`optic_tube` + `lens_vig`), que
	# seul `build_optic` produit — le mini reflex du pistolet, lui, n'en pose aucun.
	var vipere_body = armes["vipere"]["body"]
	var a_optique_tube: bool = vipere_body.buckets.has("optic_tube") \
		or vipere_body.buckets.has("lens_vig")
	_ok("W4 `vipere` n'a AUCUNE optique tubulaire (son identite : la hausse mecanique)",
		not a_optique_tube, "seaux du pistolet : " + str(vipere_body.buckets.keys()))
	var sans_optique := []
	for id in ["frelon", "chacal", "condor"]:
		if not armes[id]["body"].buckets.has("optic_tube"):
			sans_optique.append(id)
	_ok("W4b les trois armes d'epaule ont bien leur optique tubulaire",
		sans_optique.is_empty(), "sans optique : " + str(sans_optique))

	# ── W5. LES PIÈCES MOBILES SONT DES ASSEMBLAGES RÉELLEMENT SÉPARÉS ─────────────────────────
	# Fusionnées dans le corps, plus rien ne peut être animé — et le défaut ne se verrait qu'au
	# premier rechargement, très loin d'ici.
	# ⚠️ PREMIÈRE VERSION TROP FAIBLE : elle ne vérifiait que « le chargeur n'est pas vide ». Le
	# sabotage « `magazine = body` » la laissait donc VERTE — l'assemblage était bien non vide,
	# puisque c'était le corps entier. Ce qu'il faut vérifier, c'est la SÉPARATION, pas le
	# remplissage : chaque pièce mobile doit être une INSTANCE DISTINCTE du corps et des autres.
	var immobiles := []
	for id in armes:
		var corps = armes[id]["body"]
		var mv: Dictionary = armes[id]["moving"]
		if mv.is_empty():
			immobiles.append(id + ": aucune piece mobile")
			continue
		var vues := []
		for nom in mv:
			var piece = mv[nom]
			if piece == corps:
				immobiles.append("%s.%s : FUSIONNE dans le corps" % [id, nom])
			for autre in vues:
				if piece == autre:
					immobiles.append("%s.%s : partage son assemblage avec une autre piece" % [id, nom])
			vues.append(piece)
			if piece.total_tris() == 0:
				immobiles.append("%s.%s : vide" % [id, nom])
		for obligatoire in ["magazine", "trigger"]:
			if not mv.has(obligatoire):
				immobiles.append("%s : pas de %s mobile" % [id, obligatoire])
	_ok("W5 chaque piece mobile est un assemblage DISTINCT du corps et des autres",
		immobiles.is_empty(), "fautes : " + str(immobiles))

	# ── W6. AUCUNE CARTOUCHE PARASITE ───────────────────────────────────────────────────────────
	# La cartographie l'a signalé comme piège de portage : `cartridge()` rend `{brass, bullet}` et
	# les armes n'ajoutent QUE `brass` pour la chambrée. Un portage naïf greffe une ogive qui
	# traverse la carcasse. On le mesure : le corps a du laiton, mais PAS de cuivre.
	# ⚠️ On cherche l'ogive parasite LÀ OÙ LA DOUILLE SE TROUVE — c'est-à-dire sur la culasse
	# (cf. W7). Le chargeur, lui, a bien le droit d'avoir une ogive : sa cartouche du haut est
	# entière et visible sous les lèvres.
	var parasites := []
	for id in ["frelon", "chacal", "condor"]:
		var corps = armes[id]["body"]
		var culasse = armes[id]["moving"]["bolt"]
		if not culasse.buckets.has("brass"):
			parasites.append(id + ": pas de douille chambree")
		if culasse.buckets.has("copper"):
			parasites.append(id + ": OGIVE PARASITE sur la culasse")
		if corps.buckets.has("copper"):
			parasites.append(id + ": OGIVE PARASITE dans la carcasse")
	_ok("W6 la cartouche chambree n'a que sa DOUILLE, aucune ogive parasite",
		parasites.is_empty(), "fautes : " + str(parasites))

	# ── W7. LA DOUILLE CHAMBRÉE VOYAGE AVEC LA CULASSE ─────────────────────────────────────────
	# ⚠️ Contrôle ajouté APRÈS une critique adversariale qui a trouvé le défaut : le portage
	# ajoutait la douille à `body` au lieu de `bolt`. La source (`rifle.js:297`, `smg.js:297`) la
	# met sur la CULASSE, et pour une raison mécanique : c'est la face de culasse qui l'extrait.
	# Restée dans la carcasse, elle flotterait, détachée, dès que le lot 3D-E fera cycler l'arme —
	# un défaut que rien d'autre n'aurait attrapé avant la première animation de tir.
	var mal_placees := []
	for id in ["frelon", "chacal", "condor"]:
		var mv: Dictionary = armes[id]["moving"]
		if not mv.has("bolt") or not mv["bolt"].buckets.has("brass"):
			mal_placees.append(id + " : douille absente de la culasse")
		if armes[id]["body"].buckets.has("brass"):
			mal_placees.append(id + " : douille FIGEE dans la carcasse")
	_ok("W7 la douille chambree est portee par la CULASSE, pas par la carcasse",
		mal_placees.is_empty(), "fautes : " + str(mal_placees))


func _fusion(asm):
	var tout := []
	for m in asm.buckets:
		for g in asm.buckets[m]:
			tout.append(g)
	return Meshgen.merge_all(tout)


# =================================================================================================
# R. LE PATRON DE RECUL
# =================================================================================================
func _probe_recul() -> void:
	var lignes := []
	var fautes := []
	var non_det := []
	for id in W3D.WEAPON_IDS:
		var p := W3D.build_recoil_pattern(id)
		var q := W3D.build_recoil_pattern(id)
		if p != q:
			non_det.append(id)
		var n := p.size() / 2
		var pitch_min := INF
		var pitch_max := -INF
		var yaw_abs := 0.0
		for i in n:
			pitch_min = minf(pitch_min, p[i * 2])
			pitch_max = maxf(pitch_max, p[i * 2])
			yaw_abs = maxf(yaw_abs, absf(p[i * 2 + 1]))
		lignes.append("%s: %d coups, cabrage %.4f-%.4f rad, derive max %.4f rad"
			% [id, n, pitch_min, pitch_max, yaw_abs])
		# ⚠️ LE SIGNE. Un recul doit CABRER (pitch positif). Un signe inversé ferait piquer l'arme
		# au tir : personne ne le verrait dans le code, tout le monde le sentirait manette en main.
		if pitch_min <= 0.0:
			fautes.append(id + ": le recul ne cabre pas")
		# Bornes de bon sens : au-delà, ce n'est plus un recul, c'est un bug d'unité.
		if pitch_max > 0.1 or yaw_abs > 0.1:
			fautes.append(id + ": amplitude hors de toute plausibilite")
	_ok("R1 le recul CABRE sur les 4 armes, et reste dans des bornes plausibles",
		fautes.is_empty(), "fautes : " + str(fautes))
	_ok("R2 le patron de recul est DETERMINISTE (meme graine, meme suite)",
		non_det.is_empty(), "non deterministes : " + str(non_det))
	for l in lignes:
		_info("R3 patron", l)

	# R4. Chaque arme a sa PROPRE signature : deux armes qui partagent leur patron seraient
	# indiscernables au tir, ce qui annulerait tout l'intérêt d'un recul apprenable.
	var a := W3D.build_recoil_pattern("chacal")
	var b := W3D.build_recoil_pattern("frelon")
	var identiques := true
	for i in mini(a.size(), b.size()):
		if absf(a[i] - b[i]) > 1e-9:
			identiques = false
			break
	_ok("R4 deux armes ne partagent pas le meme patron de recul", not identiques)
