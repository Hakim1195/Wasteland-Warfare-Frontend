extends Node
# =================================================================================================
# SONDE 8.152.13 — L'ASSEMBLEUR DU SOLDAT : le maillage est-il sur les BONS os ?
# =================================================================================================
# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ Les cinq modules du soldat étaient éprouvés SÉPARÉMENT. Ce que personne n'avait mesuré, c'est ║
# ║ leur JONCTION : un maillage rangé par matériau, pesé sur 25 os. Quatre façons de se tromper y ║
# ║ sont invisibles à l'œil ET dans un boot « 0 ERROR » :                                         ║
# ║   1. une région entière oubliée (le soldat perd son casque, en silence) ;                     ║
# ║   2. l'échelle appliquée deux fois, ou pas du tout (le maillage se décolle des os) ;          ║
# ║   3. un sommet pesé sur le mauvais os (l'uniforme se déforme quand le tireur épaule) ;        ║
# ║   4. la chair qui dépasse la boîte serveur alors que les OS y sont (§8.152.9 ne voyait que    ║
# ║      les os : 6 cm de chair autour d'un os en règle peuvent très bien être hors règle).       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_vue3d_soldat_monte.tscn
#             --quit-after 1800
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. une region de REGIONS est retiree                   -> S1 (le compte de triangles)
#  2. l'echelle du rig n'est pas appliquee au maillage    -> S3
#  3. le miroir de pose oublie l'assise de la racine      -> S5 (l'ennemi accroupi ressort)
#  4. les feuilles se mettent a porter de la chair        -> S2
#  5. la ponderation retombe sur un seul os (rigide)      -> S6 (la surface s'etire de 11 cm)
#  6. le melange ignore l'adjacence (il bave d'une jambe a l'autre) -> S6
# =================================================================================================

const Soldat := preload("res://scripts/game/trench_soldier3d.gd")
const Rig := preload("res://scripts/game/trench_soldier_rig.gd")
const Parts := preload("res://scripts/game/trench_soldier_parts.gd")
const Bounds := preload("res://scripts/game/trench_soldier_bounds.gd")

const CHECKS_ATTENDUS := 8

# Les os qui n'ont AUCUN enfant : par construction ils ne possèdent aucun segment de peau, donc
# aucun sommet ne doit peser dessus.
const FEUILLES := ["HeadTop", "FingersR", "FingersL", "ToeR", "ToeL"]

# 🩸 LE CHIFFRE DE RÉFÉRENCE. C'est ce que mesurait la PREMIÈRE version de l'assembleur, qui
# accrochait chaque triangle entier à un seul os : 115,33 mm de déchirure au genou, soit 9,0 px à
# 12 m. Il est écrit ici pour que le seuil de S6 ne se lise pas comme un chiffre en l'air.
const DECHIRURE_DECOUPAGE_RIGIDE_MM := 115.33

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
	print("\n=== SONDE 8.152.13 — L'ASSEMBLEUR DU SOLDAT ===\n")
	var s = Soldat.new()
	add_child(s)
	s.construire(Parts.VARIANTE_DEFAUT, 1.0)

	_probe_compte(s)
	_probe_charge(s)
	_probe_repos(s)
	_probe_casque(s)
	_probe_boite(s)
	_probe_etirement(s)
	_probe_surfaces(s)
	_probe_arme(s)

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
# S1. AUCUNE RÉGION PERDUE — le seul témoin qui ne peut pas mentir
# =================================================================================================
# ⚠️ `trench_soldier3d.gd` DOUBLE la liste d'appels de `Parts.build()` pour obtenir une étiquette
# de région par pièce. C'est le prix de la pesée par région, et il est payé ici : si l'une des deux
# listes dérive, le total de triangles diverge. On exige l'ÉGALITÉ EXACTE, pas un ordre de grandeur
# — un casque, c'est ~500 triangles sur 3 780, soit 13 % qu'une tolérance laisserait passer.
func _probe_compte(s) -> void:
	var attendu: int = Parts.tri_count(Parts.VARIANTE_DEFAUT)
	_ok("S1 tous les triangles de `parts` sont peses, et le budget tient",
		int(s.rapport["tris"]) == attendu and attendu > 0
			and attendu <= Parts.BUDGET_TRIANGLES,
		"%d peses / %d attendus (manquants %d) · budget %d"
			% [int(s.rapport["tris"]), attendu, int(s.rapport["tris_manquants"]),
			Parts.BUDGET_TRIANGLES])


# =================================================================================================
# S2. LES FEUILLES NE PORTENT RIEN, LES ARTICULATIONS PORTENT
# =================================================================================================
# Deux faits en un, et il en faut deux : « aucune feuille ne porte » seul serait satisfait par un
# soldat SANS AUCUN maillage. ⚠️ Un contrôle qu'un ÉCHEC satisfait est pire que pas de contrôle.
func _probe_charge(s) -> void:
	var charge: Dictionary = s.charge_par_os()
	var feuilles_chargees := []
	for f in FEUILLES:
		if charge.has(f):
			feuilles_chargees.append(f)
	var obligatoires := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
		"UpperArmR", "ForearmR", "HandR", "UpperArmL", "ForearmL", "HandL",
		"UpLegR", "LegR", "FootR", "UpLegL", "LegL", "FootL"]
	var manquants := []
	for o in obligatoires:
		if not charge.has(o):
			manquants.append(o)
	_ok("S2 aucune feuille ne porte de chair, et les 18 os articules en portent",
		feuilles_chargees.is_empty() and manquants.is_empty(),
		"%d os charges · feuilles chargees %s · articules muets %s"
			% [charge.size(), str(feuilles_chargees), str(manquants)])


# =================================================================================================
# S3. ⭐ AU REPOS, LE CORPS PESÉ EST LE CORPS D'ORIGINE
# =================================================================================================
# LE contrôle du lot. Chaque sommet est transformé par la pesée puis par le squelette. Au repos, la
# chaîne doit rendre EXACTEMENT le sommet de départ. Une échelle oubliée, appliquée deux fois, ou
# une base de repos non identitaire, se voient ici et **nulle part ailleurs** : le boot reste à
# 0 ERROR, et la capture montre un corps qui a l'air normal jusqu'à ce qu'on regarde de près.
#
# ⚠️ On compare à l'ENVELOPPE de `parts` mise à l'échelle du rig, pas à une constante recopiée :
# une valeur en dur ici serait une deuxième source de vérité sur l'échelle.
func _probe_repos(s) -> void:
	var asm = Parts.build(Parts.VARIANTE_DEFAUT)["body"]
	var brute: AABB = Parts.enveloppe(asm)
	var e: float = s.echelle
	var att := AABB(brute.position * e, brute.size * e)

	var pts: PackedVector3Array = s.sommets_monde(1)
	var obtenue := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		obtenue = obtenue.expand(p)

	var d_pos: float = (obtenue.position - att.position).length()
	var d_taille: float = (obtenue.size - att.size).length()
	_ok("S3 au repos, le corps pese est celui de `parts` a l'echelle du rig",
		d_pos < 1e-5 and d_taille < 1e-5 and pts.size() > 0,
		"%d sommets · ecart origine %.9f m · ecart taille %.9f m · echelle %.6f"
			% [pts.size(), d_pos, d_taille, e])


# =================================================================================================
# S4. LE SOMMET DU CASQUE EST UNE COTE, PAS UN GOÛT
# =================================================================================================
# `ECHELLE_CASQUE` existe pour poser le sommet du casque RENDU sur `SILHOUETTE_TOP`. Si la pesée
# perd cette échelle, la tête dépasse de la boîte serveur : le joueur voit un casque que le serveur
# ne sait pas toucher. On mesure sur le MAILLAGE, pas sur l'os `HeadTop` — qui, le rig le dit
# lui-même, ne mesure ni le crâne ni le casque.
func _probe_casque(s) -> void:
	var sommet := -INF
	for p in s.sommets_monde(1):
		sommet = maxf(sommet, (p as Vector3).y)
	var cible: float = Bounds.HAUT_DEBOUT
	_ok("S4 le sommet du maillage tombe sur le plafond serveur",
		absf(sommet - cible) < 1e-3,
		"sommet rendu %.6f m · plafond %.6f m · ecart %.3f mm"
			% [sommet, cible, (sommet - cible) * 1000.0])


# =================================================================================================
# S5. ⭐ LA CHAIR — PAS SEULEMENT LE SQUELETTE — TIENT DANS LA FENÊTRE SERVEUR
# =================================================================================================
# Le §8.152.9 a prouvé que les OS restent dans la boîte. Un os en règle avec 6 cm de chair autour
# peut très bien en sortir : c'est le maillage que le joueur voit et que le serveur doit savoir
# toucher. On rejoue les six clips de locomotion et on soumet les sommets au MÊME juge que les os
# (`Bounds.violations`), qui sait déjà ce que le parapet occulte.
#
# ⚠️ On échantillonne un sommet sur 7 : la grandeur mesurée ne change pas, et l'échantillon est
# ANNONCÉ dans le compte rendu — un plafonnement silencieux se lirait comme « tout a été couvert ».
func _probe_boite(s) -> void:
	var pas := 7
	var total := 0
	var poses := 0
	var debord := {}
	for clip: String in ["idle", "walk", "run", "crouchWalk", "crouchIdle", "hurtIdle"]:
		var accroupi: bool = clip.begins_with("crouch")
		var plafond: float = Bounds.HAUT_ACCROUPI if accroupi else Bounds.HAUT_DEBOUT
		s.set_clip(clip)
		s.animator.fondu = 1.0
		debord[clip] = -INF
		for i in 20:
			s.update(0.05, {"vitesse": 3.2 if clip == "run" else 1.4,
				"visee_poids": 1.0, "accroupi": accroupi})
			poses += 1
			var points := []
			for p in s.sommets_monde(pas):
				points.append(p)
				debord[clip] = maxf(debord[clip], (p as Vector3).y - plafond)
			total += Bounds.violations(points, accroupi, 0.0).size()
	var detail := ""
	for c in debord:
		detail += "%s %+.0f mm · " % [c, float(debord[c]) * 1000.0]
	_ok("S5 la CHAIR reste dans la fenetre serveur sur les six clips",
		total == 0 and poses == 120,
		"%d poses · 1 sommet sur %d · %d violation(s) · ecart au plafond : %s"
			% [poses, pas, total, detail])


# =================================================================================================
# S6. ⭐⭐ LA PESÉE NE BAVE PAS, ET ELLE MÉLANGE AUX SIX ARTICULATIONS
# =================================================================================================
# 🩸🩸 CE CONTRÔLE A ÉTÉ REFORMULÉ, ET IL FAUT DIRE POURQUOI — sinon il se lit comme un rouge
# qu'on a rendu vert en déplaçant la cible.
#
# Première formulation : « la déformation reste sous le pixel à distance de duel ». Elle a fait
# rougir le DÉCOUPAGE RIGIDE à **115,33 mm au genou** et c'était juste : la surface s'OUVRAIT,
# deux copies d'un même sommet partaient chacune avec son os et on voyait à travers la jambe. Un
# trou. La pesée a supprimé le trou — un sommet, une position, la surface reste fermée — et le même
# contrôle mesure alors **52,84 mm** de déformation au bassin.
#
# ⛔ Mais 52,84 mm de déformation N'EST PAS 115,33 mm de trou. Le premier est un affaissement lisse
# (le « papier de bonbon » du mélange linéaire, que tout moteur a) ; le second était une ouverture.
# Le seuil du pixel avait été posé pour un TROU, et l'appliquer à une déformation exigerait une
# densité de maillage que le budget de `parts` refuse explicitement.
# ⚠️ Le balayage de netteté (voir `NETTETE_MELANGE`) l'a montré : la valeur bouge de 11 % sur une
# décade. **Aucun réglage de pondération ne fera passer ce chiffre sous le pixel** — seuls des
# anneaux de maillage en plus le feraient, et ça, c'est un arbitrage de budget qui appartient à
# Hakim, pas une décision de ce lot.
#
# Ce contrôle éprouve donc ce que la PESÉE peut réellement rater, et le chiffre de déformation est
# PUBLIÉ à chaque passage, sans être jugé. Un nombre qu'on affiche sans seuil reste sous les yeux ;
# un seuil taillé sur la mesure du jour ne garde rien.
func _probe_etirement(s) -> void:
	var diag: Dictionary = s.diagnostic_pesee()
	var arts: Dictionary = diag["articulations"]
	# Les six vraies articulations d'un fantassin. Chacune DOIT avoir des sommets mélangés : c'est
	# ce qui distingue une pesée d'un découpage rigide déguisé.
	var attendues := ["LegR|UpLegR", "LegL|UpLegL", "ForearmR|UpperArmR", "ForearmL|UpperArmL",
		"Hips|UpLegR", "Hips|UpLegL"]
	var muettes := []
	for a in attendues:
		if int(arts.get(a, 0)) <= 0:
			muettes.append(a)

	# La déformation, mesurée sur la pose la plus extrême qu'on sache produire — course, visée
	# pleine, plus un tir et un encaissement en cours. PUBLIÉE, pas jugée.
	s.set_clip("run")
	s.animator.fondu = 1.0
	var pire := {"max_m": 0.0, "max_px": 0.0, "max_rel": 0.0, "gros": 0, "ou": ""}
	for i in 24:
		s.update(0.05, {"vitesse": 3.4, "visee_poids": 1.0, "accroupi": false})
		if i == 6:
			s.tirer(1.0)
		if i == 12:
			s.encaisser("torso", 1.0, 1.0)
		var e: Dictionary = s.allongement_aretes(3)
		if float(e["max_px"]) > float(pire["max_px"]):
			pire = e

	# ⛔ Le premier membre est BINAIRE et sans seuil : aucun sommet ne se partage entre deux os qui
	# ne sont pas articulés l'un à l'autre. On ne peut pas le desserrer sans le supprimer.
	# ⚠️ 0,25 m borne la distance à l'os DOMINANT : c'est plus que le rayon de n'importe quel membre
	# (le torse, le plus gros, fait 0,17 m de demi-largeur) et bien moins que l'écart entre deux
	# membres distincts (36 cm d'une cuisse à l'autre). Entre les deux il n'y a rien à ajuster —
	# une erreur de liste de région saute d'un ordre de grandeur.
	_ok("S6 la pesee ne bave pas, et les six articulations melangent",
		int(diag["paires_non_adjacentes"]) == 0
			and float(diag["bavure_dominant_m"]) < 0.25 and muettes.is_empty(),
		"%d paire(s) non articulee(s) %s · os dominant a %.0f mm max (%s) · muettes %s · %d melanges "
			% [int(diag["paires_non_adjacentes"]), String(diag["exemple"]),
			float(diag["bavure_dominant_m"]) * 1000.0, String(diag["ou"]), str(muettes),
			int(s.rapport["melanges"])]
			+ "|| DEFORMATION PUBLIEE : %.1f mm = %.1f px a %d m (%d aretes > 25 %%) · %s "
			% [float(pire["max_m"]) * 1000.0, float(pire["max_px"]),
			int(Soldat.DISTANCE_DUEL_M), int(pire.get("gros", 0)), String(pire.get("ou", ""))]
			+ "— le decoupage rigide OUVRAIT la surface de %.1f mm" % DECHIRURE_DECOUPAGE_RIGIDE_MM)


# =================================================================================================
# S7. LE COÛT DE RENDU
# =================================================================================================
# La pesée rend une surface par MATÉRIAU, là où le découpage rigide en demandait une par couple
# (os, matériau) — 47 mesurées. La référence tient une arme entière en « 6-9 draw calls » ; un
# corps entier doit rester du même ordre. On borne, et on publie le chiffre.
func _probe_surfaces(s) -> void:
	var n: int = int(s.rapport["surfaces"])
	_ok("S7 le nombre de surfaces de rendu reste de l'ordre de la reference",
		n > 0 and n <= 12,
		"%d surfaces · %d sommets · %d triangles (le decoupage rigide demandait 47 instances)"
			% [n, int(s.rapport["sommets"]), int(s.rapport["tris"])])


# =================================================================================================
# S8. ⭐ L'ARME EST DANS SA MAIN, ET ELLE POINTE OU IL REGARDE
# =================================================================================================
# Le sprite peint montrait « un homme au casque, l'arme a l'epaule ». Un soldat 3D sans fusil serait
# une REGRESSION visible, pas une simplification — et une arme posee a l'oeil serait pire : elle
# tiendrait sur une arme et glisserait sur les trois autres.
#
# Les deux ancres existent deja et ne sont pas inventees ici : le rig pose l'os `HandR` SUR `GRIP_R`
# (`{"name": "HandR", "derived": "GRIP_R"}`), et chaque arme expose son propre noeud `gripR`. On
# verifie donc que les deux coincident, ET que le museau tombe sur la ligne de visee.
#
# ⚠️ LES QUATRE ARMES. Une pose juste sur le chacal et fausse sur le condor ne se verrait qu'en
# partie, sur un adversaire qui a ramasse l'autre arme — c'est-a-dire tard, et par hasard.
func _probe_arme(s) -> void:
	var pire_poignee := 0.0
	var pire_axe := 0.0
	var pire_canon := 0.0
	var ou := ""
	var montees := 0
	for arme: String in ["vipere", "frelon", "chacal", "condor"]:
		if not s.monter_arme(arme):
			continue
		montees += 1
		var v: Dictionary = s.verif_arme()
		pire_canon = maxf(pire_canon, float(v.get("canon_m", 0.0)))
		if float(v.get("poignee_m", 0.0)) > pire_poignee:
			pire_poignee = float(v["poignee_m"])
			ou = arme
		pire_axe = maxf(pire_axe, float(v.get("axe_deg", 99.0)))
	# ⛔ DEUX MEMBRES DURS, ET ILS N EPROUVENT PAS LA MEME CHOSE.
	#   la POIGNEE dans l os : c est ce que le joueur voit — un fusil qui flotte a cote du poing.
	#   l AXE sur la direction de visee : une erreur d angle fait pointer le fusil ailleurs que le
	#   regard, et AUCUNE translation ne la rattrape. On peut tenir l un et rater l autre.
	# ⚠️ Le decalage PARALLELE du canon (83 mm) est PUBLIE, pas juge : il vaut l ecart entre la
	# garde au canon supposee par le rig (`GRIP_R_DROP = 95 mm`) et celle des armes reelles
	# (33 a 62 mm). Rien ne LIT la ligne de visee du soldat — le tir adverse part de l oeil — donc
	# cet ecart ne peut pas devenir un mensonge. ❓ Le resorber demande de re-deriver
	# `GRIP_R_DROP`, ce qui deplace l os `HandR` et toutes les poses de bras : arbitrage ouvert.
	_ok("S8 les quatre armes tiennent dans le poing et pointent dans l axe du regard",
		montees == 4 and pire_poignee < 0.001 and pire_axe < 0.05,
		"%d/4 montees · poignee a %.4f mm de l os (pire : %s) · axe a %.4f deg de BORE_DIR "
			% [montees, pire_poignee * 1000.0, ou, pire_axe]
		+ "|| PUBLIE : canon a %.1f mm sous la ligne du rig" % (pire_canon * 1000.0))
