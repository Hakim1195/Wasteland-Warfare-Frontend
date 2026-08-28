extends RefCounted

# =================================================================================================
# §8.152 — LOT 3D-G : L'ANIMATEUR DU SOLDAT ADVERSE
#
# Port de la partie RUNTIME de `src/ai/animator.js` (559 l.) : le `Poser`, l'arbre de mélange à
# trois couches, et deux des quatre solveurs d'IK.
#
# ╔═ CE QUI EST PORTÉ, ET CE QUI NE L'EST PAS — LA COUPURE VUE / RÈGLES ═════════════════════════╗
# ║ Chez eux, `agent.js` est UNE SEULE classe qui contient le maillage, l'animateur, les points de ║
# ║ vie, la perception, la précision et la cadence. Il n'y a pas de frontière du tout. Voici ce    ║
# ║ qu'on laisse dehors, et pourquoi :                                                            ║
# ║                                                                                               ║
# ║ ⛔ `_updateMuzzle()` — **L'ANIMATION DÉCIDE DE LA TRAJECTOIRE DES BALLES.** Leur `muzzleWorld` ║
# ║    et `muzzleDir` sont recalculés depuis `bones[iHandR].matrixWorld`, **après les quatre IK**, ║
# ║    puis partent dans `phys.fireBullet()` et `_testPlayerHit()`. **Bouger un os change où va la ║
# ║    balle.** Chez nous la ligne de tir vient de `trench_angles` côté serveur. Non porté.        ║
# ║                                                                                               ║
# ║ ⛔ `syncHitboxes()` — les 7 capsules de dégâts sont **replacées sur les os animés à chaque      ║
# ║    image**. Chez nous la hitbox est la boîte du serveur, figée dans une table checksumée.      ║
# ║    Ce fichier ne produit AUCUNE collision. Non porté.                                         ║
# ║                                                                                               ║
# ║ ⛔ Le LOD de rendu — leur `_updateRelevance()` est un test purement graphique dont le verdict   ║
# ║    fait sauter deux images sur trois de l'évaluation de pose. Conséquence mesurée : un ennemi  ║
# ║    hors champ courant à 4,3 m/s **tire depuis un point vieux de 3 images, soit 21 cm derrière  ║
# ║    lui** — et ces balles blessent pour de vrai. Leur commentaire affirme pourtant « only the   ║
# ║    parts that can exclusively affect pixels are skipped ». Non porté.                          ║
# ║                                                                                               ║
# ║ ⛔ `vault` — la timeline d'un clip **déplace le corps physique** de +0,42 m en vertical         ║
# ║    (`agent.js:933-939`). Et il n'y a rien à franchir dans une tranchée. Non porté.             ║
# ║                                                                                               ║
# ║ ⛔ Le tremblé de visée et la dispersion (`agent.js:741-746, 780-784`) : trois `rng.gauss()` par ║
# ║    balle tirés DANS la boucle de rendu, et un lissage indexé sur `ctx.time.elapsed`. **La      ║
# ║    précision de leur IA dépend de la fréquence d'images du client.** Non porté.                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

const Rig := preload("res://scripts/game/trench_soldier_rig.gd")
const Clips := preload("res://scripts/game/trench_soldier_clips.gd")
const Bounds := preload("res://scripts/game/trench_soldier_bounds.gd")


# =================================================================================================
# L'HORLOGE — pourquoi elle est à DEUX ÉTAGES
# =================================================================================================
# ╔═ 🩸 DEUX DÉFAUTS DE CADENCE, TROUVÉS PAR LE PORTAGE ET INVISIBLES CHEZ EUX ══════════════════╗
# ║                                                                                               ║
# ║ 1. **REPLIEMENT DE SPECTRE.** `recoilAdd` contient `sin(92·t)`, soit **14,64 Hz**. Échantillonné║
# ║    à 20 Hz (notre cadence de simulation), Nyquist est à 10 Hz : la fréquence se REPLIE à       ║
# ║    |14,64 − 20| = **5,36 Hz, et en sens inverse**. Le recul ne tremblerait pas plus vite, il   ║
# ║    ondulerait à contretemps.                                                                   ║
# ║                                                                                               ║
# ║ 2. **PIC D'ENVELOPPE DÉPENDANT DE LA MACHINE.** `hitAdd` culmine analytiquement à 0,711 124 à  ║
# ║    t = 1/22 s, mais le pic RÉELLEMENT ÉCHANTILLONNÉ dépend de la cadence : 0,687 à 60 Hz,      ║
# ║    0,607 à 30 Hz, et — contre-intuitivement — **0,701 à 90 Hz contre 0,687 à 120 Hz** : ce     ║
# ║    n'est même pas monotone. Chez eux, la violence d'une réaction au coup dépend du PC.          ║
# ║                                                                                               ║
# ║ CE QUI EST FAIT, ET CE QUI NE L'EST PAS — à lire tel quel, sans arrondi.                       ║
# ║                                                                                               ║
# ║ ✅ Le point 2 est RÉSOLU : les coups uniques sont ancrés sur un **compteur ENTIER de pas** et  ║
# ║ joués sur une grille `t01 = i / n` qui contient son point final. Le pic joué ne dépend donc    ║
# ║ plus de la machine — il est le même partout, ce qui rend l'imagediff possible.                 ║
# ║                                                                                               ║
# ║ ⛔ Le point 1 N'EST PAS RÉSOLU, et il ne faut pas croire le contraire. Le remède complet est   ║
# ║ une horloge à DEUX étages : ancrage entier pour les débuts, évaluation au temps de RENDU à     ║
# ║ l'intérieur du pas (`t = (tick + alpha) · SIM_DT`), ce qui remonterait Nyquist à 30 Hz à       ║
# ║ 60 images/s. **Le second étage n'est pas implémenté** : l'appelant avance d'un pas entier par  ║
# ║ appel, donc `alpha` vaut toujours 0 et `sin(92·t)` reste replié.                               ║
# ║ ⚠️ Conséquence concrète : la micro-oscillation du recul du soldat ondule à contretemps. Elle   ║
# ║ est de faible amplitude et jamais isolée à l'œil, mais **ce n'est pas une raison de l'écrire   ║
# ║ comme résolue**. À reprendre au lot 3D-H, où la fréquence de rendu est connue.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# =================================================================================================
# L'ANIMATEUR
# =================================================================================================
class Animator extends RefCounted:

	# ⚠️ Une classe interne GDScript ne peut atteindre NI les constantes NI les `preload` du script
	# qui la contient (leçon des lots 3D-0 et 3D-D). Les trois modules sont donc rechargés ici.
	const R := preload("res://scripts/game/trench_soldier_rig.gd")
	const C := preload("res://scripts/game/trench_soldier_clips.gd")
	const B := preload("res://scripts/game/trench_soldier_bounds.gd")

	var root: Node3D
	var bones := {}          # nom -> Node3D
	var repos := {}          # nom -> position locale de repos
	var echelle := 1.0

	var poser
	var _noms: Array = []

	# État de mélange
	var clip := "idle"
	var clip_precedent := "idle"
	var phase := 0.0
	var fondu := 1.0

	# Coups uniques : ancrés sur un compteur ENTIER de pas (cf. l'horloge à deux étages).
	var _recul_tick := -1
	var _recul_force := 1.0
	var _coup_tick := -1
	var _coup_region := "torso"
	var _coup_cote := 0.0
	var _coup_force := 1.0
	var _recharge_tick := -1
	var _recharge_duree := 2.35
	var _tour_tick := -1
	var _tour_sens := 1.0
	var _tick := 0

	# Mémoire des bornes qui ont besoin d'une rampe (flexion rachidienne).
	var _flexion_precedente := 0.0
	# Descente d'assise de l'image courante, pour que `points_monde()` la reflète sans dépendre
	# de la mise à jour paresseuse de l'arbre.
	var _descente := 0.0

	# 🩸 Journal des ÉCRÊTAGES. Sans lui, une borne qui mord silencieusement passerait pour une
	# absence de problème — c'est exactement ce qui rend les débordements de la référence
	# invisibles chez eux. Une sonde peut le lire.
	var ecretages := {}


	func _init(uniform_scale := 1.0) -> void:
		# ⚠️ `ECHELLE_CASQUE` recale le sommet du casque RENDU sur `SILHOUETTE_TOP`. On l'applique
		# à la RACINE du modèle, os et maillage ensemble : c'est là que leur `agent.js:117` pose
		# son échelle de variante, et c'est la seule façon que le casque et les os restent d'accord.
		echelle = R.ECHELLE_CASQUE * uniform_scale
		root = Node3D.new()
		root.name = "soldat"
		var table: Array[Dictionary] = R.resolved_bones(echelle)
		for os in table:
			var n: String = os["name"]
			_noms.append(n)
			var nd := Node3D.new()
			nd.name = n
			bones[n] = nd
		for os in table:
			var n2: String = os["name"]
			var p2: String = os["parent"]
			var pos: Vector3 = os["pos"]
			var nd: Node3D = bones[n2]
			# ⚠️ Les positions de la table sont ABSOLUES (pieds à y=0). Un `Node3D` enfant veut sa
			# position LOCALE : on retranche celle du parent. Recopier l'absolue empilerait les
			# hauteurs et mettrait la tête à plusieurs mètres — un défaut qui ne se voit qu'au RENDU,
			# jamais dans un boot headless « 0 ERROR » (leçon §8.111).
			var local := pos
			var parent_node: Node3D = root
			if p2 != "" and bones.has(p2):
				parent_node = bones[p2]
				for o2 in table:
					if String(o2["name"]) == p2:
						local = pos - (o2["pos"] as Vector3)
						break
			nd.position = local
			repos[n2] = local
			parent_node.add_child(nd)
		poser = C.Poser.new(_noms)


	# ── L'AVANCE DE PHASE ─────────────────────────────────────────────────────────────────────
	# ⚠️ Leur commentaire dit « phase driven by real ground speed **so the feet never skate** ».
	# 🩸 C'est faux, et la ligne qui le contredit est juste en dessous : le plancher `max(0.55, …)`
	# mord dès que la vitesse tombe sous 0,781 m/s, c'est-à-dire **à chaque départ et à chaque
	# arrêt**. À 0,26 m/s, le cycle joue 1,42 m de foulée pendant que le corps parcourt 0,47 m :
	# **trois fois de glissade**. On garde le plancher (c'est la sensation qu'ils ont réglée) mais
	# on ne recopie pas la phrase.
	func _stride_hz(vitesse: float) -> float:
		match clip:
			"run":
				return maxf(1.1, vitesse / 2.05)
			"walk":
				return maxf(0.55, vitesse / 1.42)
			"crouchWalk":
				return maxf(0.4, vitesse / 0.95)
			_:
				# ⚠️ 0,19 Hz n'appartient pas à `idle` : c'est le taux par défaut de TOUT clip non
				# locomoteur (`animator.js:237`). `crouchIdle` et `hurtIdle` respirent aussi à 0,19.
				return 0.19


	func set_clip(nom: String) -> void:
		if nom == clip:
			return
		clip_precedent = clip
		clip = nom
		fondu = 0.0


	# ── LES DÉCLENCHEURS DE COUPS UNIQUES ─────────────────────────────────────────────────────
	# ⛔ Aucun de ces appels ne décide de quoi que ce soit : ils REÇOIVENT un fait déjà tranché par
	# le serveur (un tir a eu lieu, un coup a porté, un rechargement a commencé) et le rendent
	# visible. Ils ne rendent rien qu'une règle puisse lire.
	func tirer(force := 1.0) -> void:
		_recul_tick = _tick
		_recul_force = force

	func encaisser(region: String, cote := 0.0, force := 1.0) -> void:
		_coup_tick = _tick
		_coup_region = region
		_coup_cote = cote
		_coup_force = clampf(force, 0.0, 1.4)

	func recharger(duree_s: float) -> void:
		_recharge_tick = _tick
		_recharge_duree = maxf(0.2, duree_s)

	func tourner(sens: float) -> void:
		_tour_tick = _tick
		_tour_sens = signf(sens)


	# =============================================================================================
	# LA MISE À JOUR
	# =============================================================================================
	# `etat` : { vitesse, visee_poids, suppression, cible_visee, cible_regard, accroupi }
	func update(dt: float, etat: Dictionary) -> void:
		dt = (dt if dt < 0.1 else 0.1) if dt > 0.0 else 0.0
		var vitesse := float(etat.get("vitesse", 0.0))
		ecretages.clear()

		phase = fposmod(phase + dt * _stride_hz(vitesse), 1.0)
		if fondu < 1.0:
			fondu = minf(1.0, fondu + dt / 0.18)

		# ── COUCHE 1 : la locomotion, en fondu enchaîné ───────────────────────────────────────
		poser.reset()
		if fondu < 1.0:
			poser.w = 1.0 - fondu
			C.locomotion(poser, clip_precedent, phase)
			poser.w = fondu
			C.locomotion(poser, clip, phase)
		else:
			poser.w = 1.0
			C.locomotion(poser, clip, phase)

		# ── COUCHE 2 : les additifs ──────────────────────────────────────────────────────────
		poser.w = 1.0
		var visee := float(etat.get("visee_poids", 0.0))
		if visee > 0.0:
			# « aiming is damped while reloading » — la visée s'efface de 60 % pendant la recharge.
			C.aim_add(poser, visee * (0.4 if _recharge_tick >= 0 else 1.0))
		var suppression := float(etat.get("suppression", 0.0))
		if suppression > 0.0:
			C.suppress_add(poser, minf(1.0, suppression))

		_additif_unique(dt, "recul")
		_additif_unique(dt, "coup")
		_additif_unique(dt, "recharge")
		_additif_unique(dt, "tour")

		# ── LES BORNES — c'est ICI que la vue se plie à la boîte serveur ──────────────────────
		_borner(dt, bool(etat.get("accroupi", false)))

		# ── ÉCRITURE DE LA POSE ──────────────────────────────────────────────────────────────
		_ecrire_pose()

		# ── LA VUE DESCEND DANS LA BOÎTE ─────────────────────────────────────────────────────
		_asseoir_dans_la_boite(bool(etat.get("accroupi", false)))

		# ── IK, BORNÉE ───────────────────────────────────────────────────────────────────────
		if etat.has("cible_regard"):
			_regarder(etat["cible_regard"])

		_tick += 1


	# ⚠️ `alpha` vaut 0 ici : l'appelant fait avancer `_tick` d'un pas par appel. Un rendu à 60 Hz
	# sur une simulation à 20 Hz passera un `alpha` fractionnaire — c'est l'étage qui supprime le
	# repliement de spectre décrit en tête de fichier.
	# ⚠️ `i` est un nombre ENTIER de pas depuis le déclenchement, et `t01 = i / n` : la grille
	# contient donc `t01 = 0` ET `t01 = 1`. C'est cette inclusion du point final qui supprime le
	# claquement — voir le pavé ci-dessus.
	func _additif_unique(_dt: float, quoi: String) -> void:
		var depart := -1
		var duree := 0.0
		match quoi:
			"recul":
				depart = _recul_tick
				duree = C.RECUL_DUREE
			"coup":
				depart = _coup_tick
				duree = C.COUP_DUREE
			"recharge":
				depart = _recharge_tick
				duree = _recharge_duree
			"tour":
				depart = _tour_tick
				duree = C.PAS_TOURNANT_DUREE
		if depart < 0:
			return
		var n := _pas_de(duree)
		var i := _tick - depart
		if i > n:
			match quoi:
				"recul":
					_recul_tick = -1
				"coup":
					_coup_tick = -1
				"recharge":
					_recharge_tick = -1
				"tour":
					_tour_tick = -1
			return
		var t01 := float(i) / float(n)
		match quoi:
			"recul":
				C.recoil_add(poser, t01 * duree, _recul_force)
			"coup":
				C.hit_add(poser, _coup_region, t01 * duree, _coup_cote, _coup_force)
			"recharge":
				C.reload_add(poser, t01)
			"tour":
				C.turn_step(poser, t01, _tour_sens)


	# ╔═ ⚠️ LES COUPS UNIQUES SONT JOUÉS SUR UNE GRILLE QUI CONTIENT SON POINT FINAL ══╗
	# ║ 🩸 Défaut de départ : `turnStep` dure 0,42 s = **8,4 pas** à 20 Hz. Le dernier échantillon
	# ║ tombe à `t01 = 0,952`, où l'enveloppe vaut encore **0,149** — et la minuterie efface le
	# ║ reste d'un coup. Claquement mesuré chez eux : 1,8° à la cuisse, **5,1° au genou**.
	# ║
	# ║ ⚠️ DEUX REMÈDES ESSAYÉS AVANT LE BON, chacun instructif :
	# ║  1. Rampe en FRACTION de durée. Atteint zéro à `t01 = 1`… mais **aucun tick n'y tombe**.
	# ║  2. Même rampe en PAS, fermant sur les 2 derniers : le pas d'avant valait la moitié d'une
	# ║     pose de 36°, soit **18° de saut** — pire que le défaut. Multiplier une grande pose par
	# ║     une rampe courte ne fait que DÉPLACER la marche.
	# ║
	# ║ Le bon remède ne touche pas l'amplitude, il change la GRILLE : durée arrondie au pas entier
	# ║ supérieur, et `t01 = i / n` — le dernier échantillon tombe **exactement sur 1**, où
	# ║ l'enveloppe du clip vaut zéro d'elle-même. Le clip se termine parce qu'on le joue jusqu'au
	# ║ bout. Prix : `turnStep` passe de 0,42 à 0,45 s. C'est du DÉCOR, aucune règle n'en dépend,
	# ║ et c'est ce qu'impose une simulation à pas fixe.
	# ╚═══════════════════════════╝
	# ⚠️ Redéclaré ici : une classe interne GDScript ne voit pas les constantes du script hôte.
	const SIM_DT_L: float = C.SIM_DT

	static func _pas_de(duree: float) -> int:
		return maxi(1, int(ceil(duree / SIM_DT_L)))


	# ── LES BORNES ────────────────────────────────────────────────────────────────────────────
	func _borner(dt: float, accroupi: bool) -> void:
		# 1. Le décalage de hanche cumulé. 🩸 CINQ couches y écrivent sans se voir, et rien ne
		# borne la somme chez eux : mesuré **−0,514 m**, plus l'IK de pied bornée à −0,32 qui
		# S'AJOUTE, soit −0,83 m et des hanches à 0,15 m du sol.
		var avant: Vector3 = poser.hip_off
		var borne_y := B.borner_hanche(avant.y)
		# ⚠️ La profondeur aussi : notre silhouette est une PLAQUE. Le budget vaut exactement un
		# quantum de visée à la distance d'engagement la plus courte.
		var bz: float = B.budget_profondeur()
		var borne_z := clampf(avant.z, -bz, bz)
		var borne_x := clampf(avant.x, -B.DEMI_LARGEUR, B.DEMI_LARGEUR)
		if not is_equal_approx(borne_y, avant.y):
			ecretages["hanche_y"] = "%.4f -> %.4f" % [avant.y, borne_y]
		if not is_equal_approx(borne_z, avant.z):
			ecretages["hanche_z"] = "%.4f -> %.4f" % [avant.z, borne_z]
		if not is_equal_approx(borne_x, avant.x):
			ecretages["hanche_x"] = "%.4f -> %.4f" % [avant.x, borne_x]
		poser.hip_off = Vector3(borne_x, borne_y, borne_z)

		# 2. La flexion rachidienne CUMULÉE, plafond ET rampe. 🩸 Leur `_aimIk` répartit 1,25 rad
		# — **71,6°** — sur trois vertèbres dont les poids somment à 1,0, en UNE SEULE IMAGE.
		var cumul := 0.0
		for n in ["Spine", "Spine1", "Spine2"]:
			cumul += (poser.delta(n) as Vector3).x
		var vise: float = B.borner_flexion_rachis(cumul, _flexion_precedente, dt)
		if absf(vise - cumul) > 1e-6:
			ecretages["rachis"] = "%.2f deg -> %.2f deg" % [cumul, vise]
			# Répartition PROPORTIONNELLE : on écrase le cumul, pas une vertèbre au hasard.
			var k: float = 0.0 if absf(cumul) < 1e-9 else vise / cumul
			for n in ["Spine", "Spine1", "Spine2"]:
				var d: Vector3 = poser.delta(n)
				poser.deltas[n] = Vector3(d.x * k, d.y, d.z)
		_flexion_precedente = vise


	func _ecrire_pose() -> void:
		for n in _noms:
			var nd: Node3D = bones[n]
			var d: Vector3 = poser.delta(n)
			# ⚠️ ORDRE 'XYZ' EXPLICITE. Laisser le YXZ par défaut de Godot décider coûte **4,85°**
			# sur `Head` pour un coup à la tête — 48 quanta de visée, ≈ 21 mm au sommet du crâne.
			nd.quaternion = C.quat_xyz(d) if d != Vector3.ZERO else Quaternion.IDENTITY
			nd.position = repos[n]
		(bones["Hips"] as Node3D).position = (repos["Hips"] as Vector3) + poser.hip_off


	# ── LES TRANSFORMS MONDE, COMPOSÉS À LA MAIN ──────────────────────────────────────────────
	# 🩸 Première version : je lisais `global_position`. Godot met les transforms globaux à jour
	# **paresseusement**, en fin d'image : juste après avoir écrit les quaternions, ils sont encore
	# ceux de l'image précédente. La mesure était donc en retard d'un pas, et l'assise corrigeait
	# une pose qui n'existait plus. Le balayage est passé de 1 344 à 782 violations — « mieux »,
	# c'est-à-dire encore faux, ce qui est le pire des états pour une garde.
	# On compose donc la chaîne SOI-MÊME, exactement comme `trench_hands.gd` le fait pour ses
	# doigts : aucune dépendance à l'arbre, aucun retard, et ça marche même hors scène.
	func _calc_monde() -> Dictionary:
		var out := {}
		for n in _noms:
			var nd: Node3D = bones[n]
			var parent := nd.get_parent()
			var pt: Transform3D = Transform3D.IDENTITY
			if parent != null and out.has(parent.name):
				pt = out[parent.name]
			# `_noms` suit l'ordre de la table : un parent est TOUJOURS composé avant son enfant.
			out[n] = pt * nd.transform
		return out


	# ── ⭐⭐ ASSEOIR LE MODÈLE DANS LA BOÎTE — la vue s'adapte, la règle jamais ────────────────
	# 🩸 MESURÉ, et c'est le défaut le plus grave que ce lot ait trouvé : ACCROUPI, leur clip ne
	# descend pas assez. `crouchIdle` baisse la tête à **1,428 m** ; notre plafond accroupi est
	# `SILHOUETTE_TOP_DOWN = **1,05**`. Le balayage a sorti 1 344 poses où le TORSE pointe à
	# 1,117 et 1,156 m au-dessus du plafond.
	#
	# ⛔ Ce n'est pas un détail d'apparence. `SILHOUETTE_TOP_DOWN` signifie « accroupi, JAMAIS
	# exposé » — c'est un invariant gardé par `crouched_is_covered()` **et par un test de sabotage
	# côté backend**. Un torse rendu à 1,156 m donnerait à voir, et à tirer, une cible que la
	# règle déclare couverte : le joueur viserait un homme et le serveur ne compterait rien.
	# C'est le pire des deux mensonges possibles.
	#
	# ⚠️ On corrige en DÉPLAÇANT LA RACINE, pas en déformant le geste. Écraser les articulations
	# jusqu'à ce que ça rentre donnerait une posture accordéon ; abaisser le modèle entier garde
	# l'animation intacte et la met simplement là où la règle la place. Les pieds passent sous le
	# niveau du sol — sans conséquence : le bas du corps est derrière le parapet de toute façon,
	# et s'accroupir dans une tranchée, c'est précisément s'enfoncer sous le parapet.
	#
	# ⚠️ Le déplacement ne fait que DESCENDRE, jamais monter : une pose déjà basse reste où elle
	# est. Une correction bidirectionnelle « recalerait » vers le haut des poses honnêtes.
	func _asseoir_dans_la_boite(accroupi: bool) -> void:
		var plafond: float = B.HAUT_ACCROUPI if accroupi else B.HAUT_DEBOUT
		var monde := _calc_monde()
		var sommet := -INF
		for n in monde:
			sommet = maxf(sommet, (monde[n] as Transform3D).origin.y)
		# Le CASQUE, pas l'os : le sommet rendu est 10,6 mm au-dessus de `HeadTop`, et c'est lui
		# que le joueur vise.
		var casque: float = sommet + (R.SOMMET_CASQUE_RENDU - 1.800) * echelle
		var descente: float = maxf(0.0, casque - plafond)
		if descente > 0.0:
			ecretages["assise"] = ("%.4f m de descente (casque %.4f -> plafond %.2f)"
				% [descente, casque, plafond])
		root.position.y = -descente
		_descente = descente


	# ── LE REGARD, DANS UN CÔNE DUR ───────────────────────────────────────────────────────────
	# 🩸 Leur `_lookAt` n'a **aucune** limite articulaire : son seul plafond est un pas par image
	# (« ~29 deg per bone per frame cap »), et mesuré, **la tête se pose derrière l'épaule et y
	# reste** (+0,211 m stable sur dix images). Un plafond de VITESSE n'est pas une limite de
	# POSITION — c'est la confusion que ce fichier ne doit pas reproduire.
	func _regarder(cible: Vector3) -> void:
		var tete: Node3D = bones["Head"]
		var origine: Vector3 = tete.global_position if tete.is_inside_tree() else Vector3.ZERO
		var v := cible - origine
		if v.length_squared() < 1e-8:
			return
		v = v.normalized()
		var lacet := rad_to_deg(atan2(v.x, v.z))
		var tangage := rad_to_deg(asin(clampf(v.y, -1.0, 1.0)))
		var borne := B.borner_regard(lacet, tangage)
		if absf(borne.x - lacet) > 1e-6 or absf(borne.y - tangage) > 1e-6:
			ecretages["regard"] = "(%.1f, %.1f) -> (%.1f, %.1f)" % [lacet, tangage, borne.x, borne.y]
		# 40 % nuque, 60 % tête — la répartition de la référence.
		(bones["Neck"] as Node3D).quaternion = C.quat_xyz(
			Vector3(-borne.y * 0.4, borne.x * 0.4, 0.0))
		(bones["Head"] as Node3D).quaternion = C.quat_xyz(
			Vector3(-borne.y * 0.6, borne.x * 0.6, 0.0))


	# =============================================================================================
	# L'ENVELOPPE RENDUE — ce que la sonde de silhouette mesure
	# =============================================================================================
	# ⚠️ Rend les positions MONDE des os, pour que la vérification porte sur la pose RÉELLE et non
	# sur les constantes qui l'ont produite. Le §8.111 a payé cette leçon : un boot headless « 0
	# ERROR » ne prouve rien du rendu.
	func points_monde() -> Array:
		var monde := _calc_monde()
		var out := []
		for n in _noms:
			out.append((monde[n] as Transform3D).origin - Vector3(0, _descente, 0))
		return out
