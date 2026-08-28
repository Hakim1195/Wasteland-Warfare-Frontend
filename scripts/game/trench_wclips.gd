extends RefCounted

# =================================================================================================
# §8.152 — LOT 3D-E : LES CLIPS D'ANIMATION (recharge, inspection, sortie, rangement)
#
# Port de `src/weapons/clips.js` (318 l.).
#
# ╔═ CE QUE C'EST ═══════════════════════════════════════════════════════════════════════════════╗
# ║ « These are *authored keyframes*, not baked animation data. » Quatre pistes de clés + une      ║
# ║ liste d'événements, échantillonnées dans un tampon PRÉALLOUÉ :                                 ║
# ║   `weapon` : décalage ADDITIF de pose du rig entier   (m, rad)                                 ║
# ║   `lhand`  : cible du POIGNET gauche en espace ARME + orientation + nom de pose                ║
# ║   `parts`  : pilotage des pièces mobiles (chargeur, levier d'armement)                         ║
# ║   `events` : temps nommés que le système d'arme écoute (son, visuel — RIEN D'AUTRE, cf. §D)    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️ QUATRE DIVERGENCES ASSUMÉES — chacune mesurée, aucune esthétique ══════════════════════╗
# ║                                                                                               ║
# ║ A. LES CLÉS TERMINALES SONT REMISES À L'ÉCHELLE. Chez eux, 13 clés de fin portent `t: 1` EN   ║
# ║    DUR alors que toutes les autres s'écrivent `X * durée` — et l'échantillonnage se fait en    ║
# ║    SECONDES. Les tableaux de clés ne sont donc pas triés, et leur recherche de segment         ║
# ║    suppose qu'ils le sont. Mesuré en exécutant leur code :                                     ║
# ║      · `draw` (0,62 s) n'atteint JAMAIS la pose de base : il reste 0,91° de tangage, annulé    ║
# ║        d'un coup à l'arrêt du clip → un CLAQUEMENT à chaque sortie d'arme ;                    ║
# ║      · `holster` ne parcourt que 70 % de sa course : l'arme ne sort jamais du cadre ;          ║
# ║      · `reloadTac` saute à zéro d'un coup à 78 % et TÉLÉPORTE la main de 26 cm en une image ;  ║
# ║        14 % du clip (0,29 s) est du temps mort ;                                               ║
# ║      · `inspect` gèle la main d'appui sur les 45 % restants.                                   ║
# ║    ⛔ Un port fidèle échouerait la porte du cahier §5 : « la recharge se joue en entier et      ║
# ║    REVIENT à la pose de base (aucun effet qui survit) ». On écrit donc `1.0 * d` partout.      ║
# ║                                                                                               ║
# ║ B. `magVisible` NE CLIGNOTE PLUS. Leur ligne 90 est                                            ║
# ║        `magVisible = (b.magVisible ?? a.magVisible ?? 1) > 0.5 || w < 0.5`                     ║
# ║    et le `|| w < 0.5` force la visibilité sur la PREMIÈRE MOITIÉ de tout segment, y compris    ║
# ║    un segment dont les deux bornes disent « caché ». Mesuré sur `reloadTac` (2,1 s) :          ║
# ║    visible → caché 43 ms → visible 336 ms → caché 336 ms → visible. Un strobe. On échantillonne║
# ║    en ESCALIER (`w < 0.5 ? a : b`), ce qui est manifestement l'intention.                      ║
# ║                                                                                               ║
# ║ C. LA DURÉE DE RECHARGEMENT EST UN PARAMÈTRE, JAMAIS UN CHAMP DE VUE. Voir §D.                 ║
# ║                                                                                               ║
# ║ D. LES CANAUX `bolt` ET `slide` NE SONT PAS PORTÉS. Chez eux ils sont MORTS, démontré :        ║
# ║      · `res.parts.slide` est échantillonné et **lu nulle part** (`viewmodel.js:879` utilise    ║
# ║        `boltOff`) ;                                                                            ║
# ║      · `boltOff = max(stroke, boltHold, clipBolt * boltHold)` et `clipBolt ≤ 1` (l'`ease:back` ║
# ║        le fait même descendre à −0,07, jamais monter), donc le terme est TOUJOURS dominé par   ║
# ║        `boltHold`.                                                                             ║
# ║    Recopier leurs 26 littéraux `bolt:`/`slide:` en croyant qu'ils pilotent quelque chose serait ║
# ║    du bruit. L'INTENTION — culasse verrouillée en arrière quand le chargeur est vide — est     ║
# ║    réelle et se porte ailleurs : le lot 3D-F la pilotera depuis l'état SERVEUR (munitions à 0),║
# ║    et l'événement `boltrelease` de `reloadEmpty` est l'instant où elle se referme.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️ §D — LA FRONTIÈRE VUE / RÈGLES. C'EST LE PREMIER LOT DU CHANTIER QUI LA TOUCHE ════════╗
# ║                                                                                               ║
# ║ 1. `clips.js:141-142` lit `def.reloadTac ?? 2.15` et `def.reloadEmpty ?? 2.85`. Ce sont des    ║
# ║    DURÉES DE RECHARGEMENT AUTORITAIRES. Chez nous elles vivent au serveur : `reload_ticks`     ║
# ║    (30 / 40 / 44 / 50 à 20 Hz → 1,50 / 2,00 / 2,20 / 2,50 s), diffusé par `public_rules`, et   ║
# ║    c'est le SERVEUR qui remplit le chargeur à l'échéance.                                      ║
# ║    🩸 Le danger n'est pas la lecture, ce sont les DÉFAUTS : recopié tel quel, un `?? 2.15`     ║
# ║    donnerait 2,15 s d'animation pour une VIPÈRE que le serveur recharge en 1,50 s. Le joueur   ║
# ║    verrait sa main revenir au garde-main **0,65 s après** avoir été autorisé à tirer. C'est    ║
# ║    exactement le patron du §8.148 : une seconde source de vérité qui diverge en silence, du    ║
# ║    seul côté que le joueur voit. ⇒ `reload_seconds` est un **argument d'appel**, sans défaut.  ║
# ║                                                                                               ║
# ║ 2. LE SERVEUR N'A QU'UN SEUL RECHARGEMENT. Pas de distinction tactique / à sec : `_begin_      ║
# ║    reload` est appelé des deux côtés avec la même `reload_ticks`. La référence, elle, a deux   ║
# ║    durées DIFFÉRENTES (2,1 vs 2,9 sur le fusil) — et ce ratio **EST une valeur de règle** : il ║
# ║    dit « recharger à sec coûte 38 % de plus », ce que notre serveur contredit.                 ║
# ║    ⇒ On porte les DEUX clips (le « à sec » est le plus riche : il contient le réarmement),     ║
# ║    mais **calés sur la MÊME durée**. Le choix se fait sur les munitions LUES DE L'ÉTAT, pas    ║
# ║    sur un barème client.                                                                       ║
# ║                                                                                               ║
# ║ 3. 🩸 CHEZ EUX, UNE CLÉ D'ANIMATION CRÉDITE LES MUNITIONS. `index.js:445` : sur l'événement    ║
# ║    `magin`, `_completeReload()` **mute `s.mag` et `s.reserve`**. C'est le couplage vue→règle   ║
# ║    le plus grave du fichier. Chez nous le remplissage est serveur, à `reload_until_tick`.      ║
# ║    ⛔ Le gestionnaire d'événements ne doit JAMAIS écrire dans une munition, un chargeur ou une  ║
# ║    porte de tir. Les événements sont du SON et du VISUEL.                                      ║
# ║                                                                                               ║
# ║ 4. `draw` ET `holster` SONT PUREMENT DÉCORATIFS. Chez eux `setWeapon()` joue `holster` et le   ║
# ║    changement d'arme n'a lieu qu'à l'événement `end` : `holsterTime` **est** un délai de       ║
# ║    changement d'arme, donc une règle. Notre serveur change l'arme INSTANTANÉMENT. Attendre     ║
# ║    leur `end` créerait un délai purement client : le serveur tirerait avec la nouvelle arme    ║
# ║    pendant que le client afficherait encore l'ancienne, avec sa dispersion et son réticule.    ║
# ║    ⇒ Ces deux clips se jouent APRÈS un changement déjà acté. Rien n'attend leur `end`.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

const Mathx := preload("res://scripts/game/trench_mathx.gd")


# =================================================================================================
# LE TAMPON DE RÉSULTAT — un par rig, réutilisé à chaque image
# =================================================================================================
# ⚠️ Règle n°5 du cahier : « rien par frame ». Leur `sample()` alloue TROIS closures à chaque appel
# (~180/s) alors que son propre commentaire revendique « preallocated ». On utilise trois fonctions
# spécialisées et un objet réutilisé — aucune `Callable`, aucun `Dictionary` créé en vol.
class Sample extends RefCounted:
	# ⚠️ `active` n'est JAMAIS remis à false par l'échantillonnage — seul l'arrêt du clip le fait.
	# C'est leur sémantique, et l'oublier ferait persister le dernier clip indéfiniment.
	var active := false
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var lh_pos := Vector3.ZERO
	var lh_finger := Vector3.ZERO
	var lh_back := Vector3.ZERO
	var lh_pose := "wrap"
	# ⚠️ MÉCANIQUE MORTE, MAIS STRUCTURANTE — à ne pas « simplifier » en la supprimant. Aucune clé
	# ne porte de poids, donc il vaut 1 pendant 100 % de tout clip. Conséquence chez eux, et donc
	# chez nous : pendant `draw`, `holster` ET `inspect` aussi, la main d'appui est ENTIÈREMENT
	# pilotée par le clip, et la pose ajustée par arme (le `clamp:<arme>` du lot 3D-D) est
	# suspendue au profit de `wrap`.
	var lh_weight := 0.0
	var mag := 0.0
	var mag_visible := true
	var charge := 0.0

	func reset_to_rest() -> void:
		active = false
		pos = Vector3.ZERO
		rot = Vector3.ZERO
		lh_weight = 0.0
		mag = 0.0
		mag_visible = true
		charge = 0.0


# =================================================================================================
# UN CLIP
# =================================================================================================
class Clip extends RefCounted:
	var name := ""
	var duration := 0.0
	var weapon: Array = []
	var lhand: Array = []
	var parts: Array = []
	var events: Array = []

	func _init(p_name: String, p_duration: float, ch: Dictionary) -> void:
		name = p_name
		duration = p_duration
		weapon = ch.get("weapon", [])
		lhand = ch.get("lhand", [])
		parts = ch.get("parts", [])
		events = ch.get("events", [])

	# ── LA RECHERCHE DE SEGMENT ───────────────────────────────────────────────────────────────
	# ⚠️ Rend un INDEX, pas la clé. Leur `if (b !== a)` est une comparaison de RÉFÉRENCE JS, qui
	# est vraie dès que les index diffèrent ; en GDScript l'égalité de `Dictionary` n'a pas la même
	# sémantique et il n'y a aucune raison de parier dessus. On compare les index : strictement
	# équivalent au JS, et sans ambiguïté.
	static func _segment(keys: Array, t: float) -> int:
		var i := 0
		while i < keys.size() - 1 and float((keys[i + 1] as Dictionary)["t"]) <= t:
			i += 1
		return i

	# ── LE POIDS D'INTERPOLATION ──────────────────────────────────────────────────────────────
	# ⚠️ L'assouplissement lu est celui de la clé **DESTINATION**, pas de la clé source. C'est
	# l'inversion classique : une clé `{t: 0.30, ease: 'linear'}` gouverne le segment 0,20 → 0,30.
	# ⚠️ `back` DÉPASSE 1 (`ease_out_back(t, 1.4)` culmine à ≈ 1,070 vers t ≈ 0,62) : le mélange
	# EXTRAPOLE au-delà de la clé d'arrivée. C'est voulu — c'est le claquement du chargeur — et
	# toute hypothèse « w ∈ [0,1] » dans le port serait fausse.
	static func _weight(a: Dictionary, b: Dictionary, ia: int, ib: int, t: float) -> float:
		if ia == ib:
			return 0.0
		var span := float(b["t"]) - float(a["t"])
		var w := 1.0 if span <= 1e-6 else clampf((t - float(a["t"])) / span, 0.0, 1.0)
		match String(b.get("ease", "smooth")):
			"linear":
				return w
			"out":
				return Mathx.ease_out_cubic(w)
			# ⚠️ 1.4, PAS le défaut 1.6 de `mathx.js` : `clips.js:25` l'écrase explicitement.
			"back":
				return Mathx.ease_out_back(w, 1.4)
			_:
				return Mathx.smootherstep(0.0, 1.0, w)

	func sample(t: float, out: Sample) -> void:
		out.active = true
		_sample_weapon(t, out)
		_sample_lhand(t, out)
		_sample_parts(t, out)

	func _sample_weapon(t: float, out: Sample) -> void:
		if weapon.is_empty():
			out.pos = Vector3.ZERO
			out.rot = Vector3.ZERO
			return
		var ia := _segment(weapon, t)
		var ib: int = mini(weapon.size() - 1, ia + 1)
		var a: Dictionary = weapon[ia]
		var b: Dictionary = weapon[ib]
		var w := _weight(a, b, ia, ib, t)
		out.pos = (a.get("p", Vector3.ZERO) as Vector3).lerp(b.get("p", Vector3.ZERO), w)
		out.rot = (a.get("r", Vector3.ZERO) as Vector3).lerp(b.get("r", Vector3.ZERO), w)

	func _sample_lhand(t: float, out: Sample) -> void:
		if lhand.is_empty():
			out.lh_weight = 0.0
			return
		var ia := _segment(lhand, t)
		var ib: int = mini(lhand.size() - 1, ia + 1)
		var a: Dictionary = lhand[ia]
		var b: Dictionary = lhand[ib]
		var w := _weight(a, b, ia, ib, t)
		out.lh_pos = (a["p"] as Vector3).lerp(b["p"], w)
		# ⚠️ `finger` et `back` sont LERPÉS PAR COMPOSANTE, pas slerpés : la norme se creuse au
		# milieu du segment. `hand_basis` renormalise ensuite, donc le résultat est valide mais ce
		# n'est PAS la géodésique. Ne pas « corriger » en `slerp` — ça changerait la sensation.
		out.lh_finger = (a.get("finger", Vector3.ZERO) as Vector3).lerp(b.get("finger", Vector3.ZERO), w)
		out.lh_back = (a.get("back", Vector3.ZERO) as Vector3).lerp(b.get("back", Vector3.ZERO), w)
		out.lh_pose = String(a.get("pose", "wrap")) if w < 0.5 else String(b.get("pose", "wrap"))
		out.lh_weight = lerpf(float(a.get("weight", 1.0)), float(b.get("weight", 1.0)), w)

	func _sample_parts(t: float, out: Sample) -> void:
		if parts.is_empty():
			return
		var ia := _segment(parts, t)
		var ib: int = mini(parts.size() - 1, ia + 1)
		var a: Dictionary = parts[ia]
		var b: Dictionary = parts[ib]
		var w := _weight(a, b, ia, ib, t)
		out.mag = lerpf(float(a.get("mag", 0.0)), float(b.get("mag", 0.0)), w)
		out.charge = lerpf(float(a.get("charge", 0.0)), float(b.get("charge", 0.0)), w)
		# ⚠️ DIVERGENCE B : escalier, pas « visible sur la première moitié ». Voir l'en-tête.
		out.mag_visible = bool(a.get("mag_visible", true)) if w < 0.5 \
			else bool(b.get("mag_visible", true))


# =================================================================================================
# CONSTRUCTION DES CLIPS D'UNE ARME
# =================================================================================================
# `nodes`          : le dictionnaire de nœuds d'attache de `trench_weapons3d.build()`
# `view_def`       : `VIEW_DEFS[<arme>]` — VALEURS DE VUE UNIQUEMENT
# `reload_seconds` : ⛔ SANS DÉFAUT, et c'est le point. Vient de `reload_ticks / tick_rate`, donc
#                    du SERVEUR. Voir §D-1 : un défaut ici serait une seconde source de vérité.
# ╔═ ⚠️ DIVERGENCE E — LE RÉARMEMENT EST RESSERRÉ POUR RENDRE DU TEMPS AU RETOUR ════════════════╗
# ║ Effet de bord de la divergence A, et il ne pouvait apparaître qu'APRÈS elle : chez eux le    ║
# ║ dernier segment de `reloadEmpty` — la main qui lâche le levier d'armement et revient au       ║
# ║ garde-main — **ne jouait jamais**, bloqué par la clé `t: 1` hors d'ordre. Son rythme n'a donc ║
# ║ jamais été éprouvé, ni par eux, ni par leur critique.                                         ║
# ║                                                                                               ║
# ║ Une fois la clé remise à l'échelle, il joue — et il est deux fois trop rapide. MESURÉ, pointe ║
# ║ de déplacement de la main d'appui par image à 60 Hz (`chacal`, rechargement de 2,2 s) :       ║
# ║                                                                                               ║
# ║     inspection 2,1 mm · sortie 14,1 · rangement 14,8 · **tactique 44,0** · **à sec 83,2**      ║
# ║                                                                                               ║
# ║ La cause est structurelle : le retour du rechargement tactique dispose de **0,14·d** pour une ║
# ║ course courte, celui du rechargement à sec de **0,07·d** pour une course plus longue — parce   ║
# ║ que la phase de réarmement a été tassée contre une clé terminale qui n'avait pas d'importance.║
# ║                                                                                               ║
# ║ Le remède n'invente aucun geste : il APPLIQUE au rechargement à sec la vitesse de retour que  ║
# ║ le fichier s'est lui-même donnée dans son autre rechargement. La phase de réarmement, prise   ║
# ║ en bloc, passe de [0,82 ; 0,93] à **[0,82 ; 0,87]** — les proportions internes conservées      ║
# ║ par une transformation affine unique, écrite ci-dessous et appliquée à TOUT ce qui compose la  ║
# ║ phase : clés de main, clés de levier, et les deux événements. Le source garde donc les nombres ║
# ║ DE LA RÉFÉRENCE, lisibles, et la recompression reste un objet unique et auditable.             ║
# ║ ⚠️ PREMIER ESSAI FAUX : la fenêtre visée était [0,78 ; 0,87], donc le DÉBUT du réarmement était║
# ║ avancé. La pointe est passée de 83 à **121 mm** — le maximum avait simplement changé de place, ║
# ║ de la sortie vers l'APPROCHE du levier, à qui il ne restait plus que 0,03·d. Le temps rendu au ║
# ║ retour doit être pris sur le RÂTELAGE (trois petits gestes de 50 à 70 mm, largement au-dessus  ║
# ║ de leur budget), jamais sur l'approche. Un seuil global ne dit PAS où est le défaut : sans la  ║
# ║ trace de l'instant de la pointe (`t=1,67 s`), la correction serait repartie dans le décor.     ║
# ║   → mesuré après : pointe du retour à **51 mm/image**, du même ordre que les 44 du tactique.   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const REARM_DE := 0.82
const REARM_A := 0.93
const REARM_DE2 := 0.82
const REARM_A2 := 0.87

static func _rearm(f: float) -> float:
	return REARM_DE2 + (f - REARM_DE) * (REARM_A2 - REARM_DE2) / (REARM_A - REARM_DE)


static func build_clips(nodes: Dictionary, view_def: Dictionary, reload_seconds: float) -> Dictionary:
	var grip: Dictionary = nodes["gripL"]
	var seat: Vector3 = (nodes["magSeat"] as Dictionary)["pos"]
	var mag_len := float(view_def.get("mag_len", 0.2))

	# Orientation de la main d'appui, selon qu'elle tient l'ARME ou un CHARGEUR.
	var wrap_finger: Vector3 = grip.get("finger", Vector3(0.82, 0.5, -0.28))
	var wrap_back: Vector3 = grip.get("back", Vector3(-0.5, 0.32, -0.8))
	var mag_finger := Vector3(0.1, 0.72, -0.68)
	var mag_back := Vector3(-0.86, 0.34, -0.38)
	var hg: Vector3 = grip["pos"]

	# Les points que la main d'appui visite, tous en espace ARME et tous dérivés du siège de
	# chargeur — c'est ce qui fait qu'une même timeline pilote une carabine et un pistolet.
	var at_mag := Vector3(seat.x + 0.012, seat.y - mag_len * 0.62, seat.z + 0.012)
	var below_gun := Vector3(seat.x + 0.05, seat.y - mag_len * 1.5, seat.z + 0.09)
	var off_frame := Vector3(seat.x + 0.11, seat.y - mag_len * 2.0, seat.z + 0.16)
	var mag_high := Vector3(seat.x + 0.006, seat.y - mag_len * 0.78, seat.z + 0.008)
	var seated := Vector3(seat.x, seat.y - mag_len * 0.62, seat.z)

	# ⚠️ Le mot `charge` désigne DEUX choses dans leur fichier : ici une POSITION de saisie du
	# levier d'armement, et plus bas un scalaire 0..1 de course. On désambiguïse au portage.
	var a_le_levier: bool = nodes.has("chargeRest")
	var prise_levier := Vector3.ZERO
	if a_le_levier:
		var cr: Vector3 = (nodes["chargeRest"] as Dictionary)["pos"]
		prise_levier = Vector3(cr.x - 0.02, cr.y + 0.008, cr.z + 0.03)

	# ⚠️ DIVERGENCE C : UNE SEULE durée pour les deux rechargements. Voir §D-2.
	var d := maxf(0.2, reload_seconds)

	var out := {}

	# ── RECHARGEMENT TACTIQUE (chargeur partiel) ──────────────────────────────────────────────
	out["reload_tac"] = Clip.new("reload_tac", d, {
		"weapon": [
			{"t": 0.0, "p": Vector3.ZERO, "r": Vector3.ZERO},
			{"t": 0.12 * d, "p": Vector3(0.014, -0.026, 0.03), "r": Vector3(-0.14, 0.3, 0.42)},
			{"t": 0.50 * d, "p": Vector3(0.016, -0.03, 0.026), "r": Vector3(-0.1, 0.34, 0.5)},
			{"t": 0.72 * d, "p": Vector3(0.012, -0.022, 0.022), "r": Vector3(-0.12, 0.26, 0.44)},
			{"t": 0.78 * d, "p": Vector3(0.008, -0.008, 0.014), "r": Vector3(-0.05, 0.18, 0.3),
				"ease": "back"},
			{"t": 1.0 * d, "p": Vector3.ZERO, "r": Vector3.ZERO},
		],
		"lhand": [
			{"t": 0.0, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap"},
			{"t": 0.10 * d, "p": at_mag, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
			{"t": 0.20 * d, "p": at_mag, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
			{"t": 0.30 * d, "p": below_gun, "finger": mag_finger, "back": mag_back,
				"pose": "pinch", "ease": "out"},
			{"t": 0.42 * d, "p": off_frame, "finger": mag_finger, "back": mag_back, "pose": "open"},
			{"t": 0.56 * d, "p": off_frame, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
			{"t": 0.68 * d, "p": below_gun, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
			{"t": 0.76 * d, "p": mag_high, "finger": mag_finger, "back": mag_back,
				"pose": "pinch", "ease": "out"},
			{"t": 0.80 * d, "p": seated, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
			{"t": 0.86 * d, "p": seated - Vector3(0, 0.012, 0), "finger": mag_finger,
				"back": mag_back, "pose": "open"},
			{"t": 1.0 * d, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap",
				"ease": "out"},
		],
		"parts": [
			{"t": 0.0, "mag": 0.0, "mag_visible": true},
			{"t": 0.16 * d, "mag": 0.0, "mag_visible": true},
			{"t": 0.20 * d, "mag": 1.0, "mag_visible": true},
			{"t": 0.30 * d, "mag": 1.0, "mag_visible": true, "ease": "linear"},
			{"t": 0.34 * d, "mag": 1.0, "mag_visible": false},
			{"t": 0.66 * d, "mag": 1.0, "mag_visible": false},
			{"t": 0.68 * d, "mag": 1.0, "mag_visible": true},
			{"t": 0.79 * d, "mag": 1.0, "mag_visible": true, "ease": "out"},
			{"t": 0.81 * d, "mag": 0.0, "mag_visible": true},
			{"t": 1.0 * d, "mag": 0.0, "mag_visible": true},
		],
		"events": [
			{"t": 0.020 * d, "name": "start"},
			{"t": 0.200 * d, "name": "magout"},
			{"t": 0.340 * d, "name": "magdrop"},
			{"t": 0.810 * d, "name": "magin"},
			{"t": 0.880 * d, "name": "slap"},
			{"t": 0.995 * d, "name": "end"},
		],
	})

	# ── RECHARGEMENT À SEC (avec réarmement) ──────────────────────────────────────────────────
	var vide_lhand := [
		{"t": 0.0, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap"},
		{"t": 0.08 * d, "p": at_mag, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
		{"t": 0.16 * d, "p": at_mag, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
		{"t": 0.26 * d, "p": below_gun, "finger": mag_finger, "back": mag_back,
			"pose": "open", "ease": "out"},
		{"t": 0.36 * d, "p": off_frame, "finger": mag_finger, "back": mag_back, "pose": "open"},
		{"t": 0.48 * d, "p": off_frame, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
		{"t": 0.58 * d, "p": below_gun, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
		{"t": 0.66 * d, "p": mag_high, "finger": mag_finger, "back": mag_back,
			"pose": "pinch", "ease": "out"},
		{"t": 0.70 * d, "p": seated, "finger": mag_finger, "back": mag_back, "pose": "pinch"},
		{"t": 0.75 * d, "p": seated - Vector3(0, 0.01, 0), "finger": mag_finger,
			"back": mag_back, "pose": "open"},
	]
	if a_le_levier:
		# ⚠️ Le commentaire de la référence dit « Pistol: the support hand racks the slide from
		# above » pour l'autre branche. C'est vrai PAR ACCIDENT : la condition réelle est
		# « toute arme sans nœud `chargeRest` ». Notre CONDOR est extrapolé du fusil ; s'il
		# naissait un jour sans `chargeRest`, il réarmerait en actionnant une culasse à glissière
		# de pistolet, SILENCIEUSEMENT. Vérifié le 2026-08-28 : il en a bien un.
		var lf := Vector3(0.55, 0.2, 0.81)
		var lb := Vector3(-0.2, 0.94, -0.27)
		vide_lhand.append_array([
			{"t": _rearm(0.82) * d, "p": prise_levier - Vector3(0, 0, 0.01), "finger": lf, "back": lb,
				"pose": "pinch", "ease": "out"},
			{"t": _rearm(0.87) * d, "p": prise_levier, "finger": lf, "back": lb, "pose": "pinch"},
			{"t": _rearm(0.90) * d, "p": prise_levier + Vector3(0, 0, 0.07), "finger": lf, "back": lb,
				"pose": "pinch", "ease": "linear"},
			{"t": _rearm(0.93) * d, "p": prise_levier + Vector3(0, 0, 0.02), "finger": lf, "back": lb,
				"pose": "open", "ease": "out"},
		])
	else:
		# Pistolet : la main d'appui arme la culasse par le dessus.
		var pf := Vector3(0.7, -0.3, 0.65)
		var pb := Vector3(0.1, 0.94, 0.32)
		vide_lhand.append_array([
			{"t": _rearm(0.82) * d, "p": Vector3(-0.02, seat.y + 0.06, seat.z - 0.05), "finger": pf,
				"back": pb, "pose": "pinch", "ease": "out"},
			{"t": _rearm(0.88) * d, "p": Vector3(-0.02, seat.y + 0.06, seat.z - 0.02), "finger": pf,
				"back": pb, "pose": "pinch", "ease": "linear"},
			{"t": _rearm(0.92) * d, "p": Vector3(-0.02, seat.y + 0.06, seat.z - 0.06), "finger": pf,
				"back": pb, "pose": "open", "ease": "out"},
		])
	vide_lhand.append({"t": 1.0 * d, "p": hg, "finger": wrap_finger, "back": wrap_back,
		"pose": "wrap", "ease": "out"})

	out["reload_empty"] = Clip.new("reload_empty", d, {
		"weapon": [
			{"t": 0.0, "p": Vector3.ZERO, "r": Vector3.ZERO},
			{"t": 0.10 * d, "p": Vector3(0.016, -0.03, 0.032), "r": Vector3(-0.16, 0.34, 0.46)},
			{"t": 0.44 * d, "p": Vector3(0.018, -0.034, 0.028), "r": Vector3(-0.12, 0.38, 0.54)},
			{"t": 0.70 * d, "p": Vector3(0.014, -0.026, 0.024), "r": Vector3(-0.14, 0.3, 0.48)},
			{"t": 0.72 * d, "p": Vector3(0.01, -0.014, 0.018), "r": Vector3(-0.06, 0.24, 0.38),
				"ease": "back"},
			{"t": 0.86 * d, "p": Vector3(0.006, -0.012, 0.016), "r": Vector3(-0.02, 0.42, 0.22)},
			{"t": 0.92 * d, "p": Vector3(0.004, -0.006, 0.022), "r": Vector3(0.02, 0.44, 0.18),
				"ease": "linear"},
			{"t": 1.0 * d, "p": Vector3.ZERO, "r": Vector3.ZERO, "ease": "out"},
		],
		"lhand": vide_lhand,
		"parts": [
			{"t": 0.0, "mag": 0.0, "mag_visible": true},
			{"t": 0.12 * d, "mag": 0.0, "mag_visible": true},
			{"t": 0.16 * d, "mag": 1.0, "mag_visible": true},
			{"t": 0.26 * d, "mag": 1.0, "mag_visible": true, "ease": "linear"},
			{"t": 0.30 * d, "mag": 1.0, "mag_visible": false},
			{"t": 0.56 * d, "mag": 1.0, "mag_visible": false},
			{"t": 0.58 * d, "mag": 1.0, "mag_visible": true},
			{"t": 0.69 * d, "mag": 1.0, "mag_visible": true, "ease": "out"},
			{"t": 0.71 * d, "mag": 0.0, "mag_visible": true},
			{"t": _rearm(0.86) * d, "mag": 0.0, "mag_visible": true, "charge": 0.0},
			{"t": _rearm(0.90) * d, "mag": 0.0, "mag_visible": true, "charge": 1.0, "ease": "linear"},
			{"t": _rearm(0.915) * d, "mag": 0.0, "mag_visible": true, "charge": 0.0, "ease": "back"},
			{"t": 1.0 * d, "mag": 0.0, "mag_visible": true, "charge": 0.0},
		],
		"events": [
			{"t": 0.020 * d, "name": "start"},
			{"t": 0.160 * d, "name": "magout"},
			{"t": 0.300 * d, "name": "magdrop"},
			{"t": 0.710 * d, "name": "magin"},
			{"t": _rearm(0.900) * d, "name": "charge"},
			{"t": _rearm(0.917) * d, "name": "boltrelease"},
			{"t": 0.995 * d, "name": "end"},
		],
	})

	# ── INSPECTION ────────────────────────────────────────────────────────────────────────────
	var insp := float(view_def.get("inspect_time", 3.0))
	out["inspect"] = Clip.new("inspect", insp, {
		"weapon": [
			{"t": 0.0, "p": Vector3.ZERO, "r": Vector3.ZERO},
			{"t": 0.16 * insp, "p": Vector3(-0.03, -0.012, 0.075), "r": Vector3(0.1, -0.62, -0.34)},
			{"t": 0.34 * insp, "p": Vector3(-0.026, -0.006, 0.085), "r": Vector3(-0.05, -0.78, -0.5)},
			{"t": 0.52 * insp, "p": Vector3(0.01, -0.02, 0.07), "r": Vector3(0.22, 0.5, 0.9)},
			{"t": 0.70 * insp, "p": Vector3(0.012, -0.024, 0.055), "r": Vector3(0.3, 0.62, 1.15)},
			{"t": 0.86 * insp, "p": Vector3(-0.006, -0.01, 0.03), "r": Vector3(0.06, -0.18, 0.2)},
			{"t": 1.0 * insp, "p": Vector3.ZERO, "r": Vector3.ZERO, "ease": "out"},
		],
		"lhand": [
			{"t": 0.0, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap"},
			{"t": 0.30 * insp, "p": hg + Vector3(-0.01, -0.01, 0.03), "finger": wrap_finger,
				"back": wrap_back, "pose": "clamp"},
			{"t": 0.55 * insp, "p": hg + Vector3(0.01, -0.02, -0.02), "finger": wrap_finger,
				"back": wrap_back, "pose": "wrap"},
			{"t": 1.0 * insp, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap",
				"ease": "out"},
		],
		"parts": [
			{"t": 0.0, "mag": 0.0, "mag_visible": true},
			{"t": 1.0 * insp, "mag": 0.0, "mag_visible": true},
		],
		"events": [{"t": 0.995 * insp, "name": "end"}],
	})

	# ── SORTIE D'ARME ─────────────────────────────────────────────────────────────────────────
	var dr := float(view_def.get("draw_time", 0.62))
	out["draw"] = Clip.new("draw", dr, {
		"weapon": [
			{"t": 0.0, "p": Vector3(0.05, -0.3, 0.14), "r": Vector3(-0.85, 0.5, 0.55)},
			{"t": 0.55 * dr, "p": Vector3(0.01, -0.03, 0.02), "r": Vector3(-0.1, 0.06, 0.06),
				"ease": "out"},
			{"t": 0.78 * dr, "p": Vector3(-0.004, 0.008, -0.006), "r": Vector3(0.04, -0.02, -0.02)},
			{"t": 1.0 * dr, "p": Vector3.ZERO, "r": Vector3.ZERO, "ease": "out"},
		],
		"lhand": [
			{"t": 0.0, "p": hg + Vector3(-0.02, -0.09, 0.06), "finger": wrap_finger,
				"back": wrap_back, "pose": "open"},
			{"t": 0.60 * dr, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap",
				"ease": "out"},
			{"t": 1.0 * dr, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap"},
		],
		"parts": [{"t": 0.0, "mag": 0.0, "mag_visible": true}],
		"events": [{"t": 0.995 * dr, "name": "end"}],
	})

	# ── RANGEMENT ─────────────────────────────────────────────────────────────────────────────
	var ho := float(view_def.get("holster_time", 0.4))
	out["holster"] = Clip.new("holster", ho, {
		"weapon": [
			{"t": 0.0, "p": Vector3.ZERO, "r": Vector3.ZERO},
			{"t": 0.25 * ho, "p": Vector3(0.004, 0.014, -0.01), "r": Vector3(0.08, -0.04, -0.05)},
			{"t": 1.0 * ho, "p": Vector3(0.05, -0.32, 0.15), "r": Vector3(-0.9, 0.55, 0.6),
				"ease": "out"},
		],
		"lhand": [
			{"t": 0.0, "p": hg, "finger": wrap_finger, "back": wrap_back, "pose": "wrap"},
			{"t": 1.0 * ho, "p": hg + Vector3(-0.02, -0.1, 0.07), "finger": wrap_finger,
				"back": wrap_back, "pose": "open", "ease": "out"},
		],
		"parts": [{"t": 0.0, "mag": 0.0, "mag_visible": true}],
		"events": [{"t": 0.995 * ho, "name": "end"}],
	})

	return out


# =================================================================================================
# LES ÉVÉNEMENTS FRANCHIS ENTRE DEUX INSTANTS
# =================================================================================================
# ⚠️ Fenêtre `prev < t <= now`, avec `prev = -1` à la mise en route pour que l'événement à t=0 parte.
# ⚠️ Si un pas de temps dépasse la durée du clip, TOUS les événements restants partent dans la même
# image, dans l'ordre du tableau. C'est leur comportement, on le garde : dédupliquer ferait
# disparaître un son de rechargement sur un hoquet d'image.
# ⛔ Ce que l'appelant en fait : du SON et du VISUEL. Voir §D-3 — chez eux, `magin` **crédite les
# munitions**, et c'est le couplage vue→règle le plus grave du fichier de référence.
static func events_between(clip: Clip, prev: float, now: float) -> Array:
	var out := []
	for e in clip.events:
		var et := float((e as Dictionary)["t"])
		if et > prev and et <= now:
			out.append(String((e as Dictionary)["name"]))
	return out
