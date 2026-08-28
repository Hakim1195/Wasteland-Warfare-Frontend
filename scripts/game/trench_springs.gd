extends RefCounted
# =================================================================================================
# LA TRANCHÉE FP (§8.151 LOT B) — LES RESSORTS DU FEEL : les maths du recul cosmétique.
#
# Port FIDÈLE de `War-Of-Indipendence/Claude-of-Duty-main/src/player/springs.js` (155 l.) — la
# référence `Claude-of-Duty` du cahier §4.1. On transpose la RECETTE (oscillateur amorti
# sous-échantillonné + recul deux étages + bruit de valeur haché), ligne à ligne, pas du code
# Three.js.
#
# MODULE 100 % MATHS, sans état de jeu : il ne connaît ni le duel, ni le réseau, ni un seul nœud.
# Consommateurs prévus (vague 2, §4.2) : `trench_viewmodel.gd` (kick, traîne de visée),
# `trench_fp.gd` (flinch, shake, respiration). RIEN ne le précharge encore — il se prouve seul
# via `tools/probe_trench_springs.tscn`.
#
# ╔═ LE RECUL EST 100 % COSMÉTIQUE (décision Hakim 2026-08-26) ═══════════════════════════════════╗
# ║ Ce module n'écrit JAMAIS dans une variable de visée — il ne sait même pas qu'une visée        ║
# ║ existe. Il rend des NOMBRES ; la vague 2 les applique à des offsets de PRÉSENTATION           ║
# ║ (viewmodel, image entière, roulis) et à rien d'autre. « Le réticule ne ment jamais »          ║
# ║ (§8.141.6) : la visée envoyée au serveur reste bit-identique avec ou sans feel —              ║
# ║ `probe_trench_feel_aim` en jugera à l'application.                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ LES TROIS PROPRIÉTÉS QUI PORTENT TOUT LE LOT ════════════════════════════════════════════════╗
# ║ 1. SOUS-ÉCHANTILLONNAGE (pas interne ≤ 1/360 s) : un ressort raide intégré en Euler sur une   ║
# ║    frame perdue de 33 ms DIVERGE (mesuré sur la réplique : ×38 en un seul pas). Découpé en    ║
# ║    sous-pas, il reste stable et le mouvement VISIBLE ne dépend plus de la cadence de frames.  ║
# ║ 2. ASSÈCHEMENT : sous epsilon, valeur ET vélocité collent NET sur la cible. Sans lui, la      ║
# ║    queue exponentielle agite des décimales pendant des minutes — et le viewmodel « au         ║
# ║    repos » ne serait jamais bit-stable pour les captures du LOT E. C'est LUI qui fige.        ║
# ║ 3. DÉTERMINISME : `hash_noise` ne consomme AUCUN RNG global — même entrée, même sortie, à     ║
# ║    chaque boot. Les baselines et les sondes en dépendent.                                     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ÉCARTS ASSUMÉS vis-à-vis de `springs.js` (tout le reste est ligne à ligne) :
#   • `Spring.set()` devient `set_value()` — `set` est une méthode native d'Object en GDScript.
#   • plus de chaînage (`return this`) : les mutateurs rendent `void`, style maison.
#   • le RÉSIDU du RecoilAxis est asséché sous epsilon lui aussi (le JS le laisse asymptotique :
#     ~4 minutes de subnormaux avant le vrai zéro — le repos ne serait pas bit-stable, LOT E).
#   • `at_rest()` : seule ADDITION d'API — le témoin de repos exact que sondes et LOT E lisent.
#   • les easings (smoothstep & co) ne sont pas portés : Godot les a en natif (`smoothstep`,
#     `ease`, Tween) et le recul n'en consomme aucun. `TAU`/`DEG` idem (`TAU`, `deg_to_rad`).
#   • `hash_noise` reproduit l'arithmétique 32 BITS de JS (`|0`, `>>>`, `Math.imul`) avec des
#     masques `& 0xFFFFFFFF` sur les entiers 64 bits de GDScript — mêmes bits, mêmes nombres.
#
# Les VALEURS d'application (amplitude du kick en px, intensités des curseurs F10) appartiennent
# à la vague 2 (`trench_tuning.gd`) — ici ne vivent que les CONSTANTES DE FORME de la référence.
# =================================================================================================


# =================================================================================================
# HELPERS SCALAIRES — statiques, sans état
# =================================================================================================

# Approche exponentielle à VRAIE constante de temps : `tau` est le temps des 63 % parcourus.
# « Y arriver en un dixième de seconde environ » = tau ≈ 0.1 / 2.3. C'est l'étage LENT du recul.
static func approach(current: float, target: float, tau: float, dt: float) -> float:
	if tau <= 1e-6:
		return target
	return target + (current - target) * exp(-dt / tau)


# Avance à VITESSE CONSTANTE (`rate` en unités/s), pour ce qui ne doit PAS avoir de queue
# asymptotique. Même contrat que le `move_toward(a, b, delta)` natif, mais en débit × temps.
static func move_toward_rate(current: float, target: float, rate: float, dt: float) -> float:
	var d := target - current
	var step_len := rate * dt
	if d > step_len:
		return current + step_len
	if d < -step_len:
		return current - step_len
	return target


# Plus court écart angulaire SIGNÉ, en radians. (Godot 4.3+ a `angle_difference` en natif — porté
# quand même : le module se suffit à lui-même et la sonde le fige contre la réplique float64.)
static func angle_delta(from: float, to: float) -> float:
	var d := fmod(to - from, TAU)
	if d > PI:
		d -= TAU
	elif d < -PI:
		d += TAU
	return d


# =================================================================================================
# `hash_noise` — BRUIT DE VALEUR 1D DÉTERMINISTE (le shake et la respiration, sans toucher au RNG)
# =================================================================================================
# ╔═ POURQUOI PAS `randf()` NI `FastNoiseLite` ═══════════════════════════════════════════════════╗
# ║ Le shake doit être REJOUABLE : même frame, même valeur — les baselines et la bit-stabilité    ║
# ║ du LOT E l'exigent. Et un RNG global consommé ici décalerait tout le reste du jeu qui tire    ║
# ║ dedans. Un hachage entier pur n'a ni graine partagée, ni état, ni allocation.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ PORTAGE 32 BITS : en JS, `|0`, `>>>` et `Math.imul` travaillent modulo 2³². GDScript a des
# entiers 64 bits — chaque étape est donc masquée `& 0xFFFFFFFF` pour retomber sur les MÊMES
# bits. (Fidèle pour |graine| < 2²⁴ : au-delà, c'est la RÉFÉRENCE qui perd des bits — son
# `seed * 374761393` est un produit float64. Nos graines sont de petits entiers.)

# Bruit lissé dans [-1, 1] : fondu de Hermite entre les deux cellules entières qui encadrent x.
# Aux entiers, la valeur EST celle de la cellule — la couture est invisible.
static func hash_noise(x: float, noise_seed: int = 0) -> float:
	var xi := floori(x)
	var f := x - float(xi)
	var u := f * f * (3.0 - 2.0 * f)
	return _hash_cell(xi, noise_seed) * (1.0 - u) + _hash_cell(xi + 1, noise_seed) * u


# La cellule : avalanche entière (façon xxHash) -> un float déterministe dans [-1, 1].
static func _hash_cell(i: int, noise_seed: int) -> float:
	var n := (i ^ (noise_seed * 374761393)) & 0xFFFFFFFF
	n = _imul32(n ^ (n >> 15), 0x2C1B3C6D)
	n = _imul32(n ^ (n >> 12), 0x297A2D39)
	n = (n ^ (n >> 15)) & 0xFFFFFFFF
	return (float(n) / 4294967296.0) * 2.0 - 1.0


# Le `Math.imul` de JS : produit modulo 2³². Les deux facteurs tiennent sur 32 bits, leur produit
# sur 64 — aucun débordement possible avant le masque.
static func _imul32(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF


# =================================================================================================
# `TrenchSpring` — OSCILLATEUR HARMONIQUE AMORTI, piloté en (fréquence Hz, amortissement zeta)
# =================================================================================================
#   zeta < 1 : sous-amorti, dépasse et revient — le punch d'un recul ;
#   zeta = 1 : critique, le plus rapide SANS dépassement — traîne de visée, FOV punch.
# `impulse()` injecte de la vélocité (le coup « physique ») ; `set_value()` déplace instantanément.
# Les champs sont publics et relus À CHAQUE PAS : les curseurs F10 de la vague 2 pourront écrire
# `freq`/`damping` à chaud sans casser l'état en vol.
class TrenchSpring:
	# Pas d'intégration MAXIMAL — le cœur de la stabilité. 24 sous-pas × 1/360 s = 66,7 ms
	# couverts : au-delà (frame catastrophique), l'excédent de temps est ABANDONNÉ — mieux vaut
	# dilater un feel cosmétique qu'intégrer un pas instable. Comportement de la référence.
	const MAX_SUB_DT := 1.0 / 360.0
	const MAX_SUB_STEPS := 24
	# L'ASSÈCHEMENT : sous ces deux seuils, on colle NET sur la cible (valeur ET vélocité).
	# C'est ce collage qui rend le repos bit-stable — la propriété que le LOT E capture au pixel.
	const SNAP_VALUE_EPS := 1e-7
	const SNAP_VELOCITY_EPS := 1e-6
	# Reliquat de boucle : en dessous, le temps restant est du bruit d'arrondi, pas un sous-pas.
	const REMAINDER_EPS := 1e-7

	var freq: float
	var damping: float
	var value: float
	var velocity := 0.0
	var target := 0.0

	func _init(p_freq := 8.0, p_damping := 0.7, p_value := 0.0) -> void:
		freq = p_freq
		damping = p_damping
		value = p_value

	func reset(p_value := 0.0) -> void:
		value = p_value
		velocity = 0.0

	# Le coup PHYSIQUE : injecte de la vélocité. (Le RecoilAxis, lui, kick en DÉPLACEMENT.)
	func impulse(v: float) -> void:
		velocity += v

	# Déplacement instantané, vélocité conservée — le `set()` de la référence, renommé parce que
	# `set` est une méthode native d'Object.
	func set_value(v: float) -> void:
		value = v

	func step(dt: float) -> float:
		if dt <= 0.0:
			return value
		var w := TAU * freq
		var k := w * w
		var c := 2.0 * damping * w
		# Sous-pas semi-implicites (vélocité d'abord) : un ressort raide traverse une frame
		# perdue sans broncher — l'intégration ne voit jamais un pas plus long que 1/360 s.
		var remaining := dt
		var guard := 0
		while remaining > REMAINDER_EPS and guard < MAX_SUB_STEPS:
			guard += 1
			var h := minf(remaining, MAX_SUB_DT)
			remaining -= h
			var a := -k * (value - target) - c * velocity
			velocity += a * h
			value += velocity * h
		# L'assèchement : tuer la sonnerie dénormale pour des frames de repos bit-stables.
		if absf(value - target) < SNAP_VALUE_EPS and absf(velocity) < SNAP_VELOCITY_EPS:
			value = target
			velocity = 0.0
		return value

	# Vrai quand le ressort est COLLÉ (repos EXACT, pas « à peu près ») — le témoin que la porte
	# de captures du LOT E et les sondes lisent. Seule addition à l'API de la référence.
	func at_rest() -> bool:
		return value == target and velocity == 0.0


# =================================================================================================
# `TrenchRecoilAxis` — LE RECUL DEUX ÉTAGES : ressort sous-amorti rapide + résidu exponentiel lent
# =================================================================================================
# ╔═ POURQUOI DEUX ÉTAGES ════════════════════════════════════════════════════════════════════════╗
# ║ Un vrai recul d'arme fait TROIS choses : il monte instantanément, il revient sec, puis il se  ║
# ║ POSE. Un ressort seul ne sait en faire que deux — l'étage lent (exponentielle tau 0,3 s,      ║
# ║ 34 % du coup) tient la « queue » pendant que le ressort (9,5 Hz, zeta 0,52) claque            ║
# ║ l'aller-retour. Mesuré sur un kick unitaire : sous 50 % en ~0,03 s, encore ~12,5 % à 0,3 s.   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Le kick est en DÉPLACEMENT, pas en vélocité : plus sec à l'œil ET à l'oreille — la référence a
# tranché pareil. Défauts = le réglage du cahier §4.1 : freq 9,5 / zeta 0,52 / tau 0,3 / part 0,34.
# ⚠️ `value` n'est recalculée qu'au `step()` : lue entre un `kick()` et le pas suivant, elle rend
# encore l'état d'avant — exactement comme la référence.
class TrenchRecoilAxis:
	# Sous ce seuil le résidu colle à zéro — ÉCART VOULU vis-à-vis de la référence (cf. en-tête) :
	# sans lui, l'exponentielle traîne des subnormaux ~4 minutes et le repos n'est jamais exact.
	const RESIDUAL_SNAP_EPS := 1e-7
	# Garde de l'approche exponentielle : une constante de temps nulle = collage immédiat.
	const TAU_EPS := 1e-6

	var spring: TrenchSpring
	var residual := 0.0
	var residual_tau: float
	var residual_share: float
	var value := 0.0

	func _init(p_freq := 9.5, p_damping := 0.52, p_residual_tau := 0.3,
			p_residual_share := 0.34) -> void:
		spring = TrenchSpring.new(p_freq, p_damping, 0.0)
		residual_tau = p_residual_tau
		residual_share = p_residual_share

	func reset() -> void:
		spring.reset(0.0)
		residual = 0.0
		value = 0.0

	# `amount` : un angle en radians — ou des pixels pour un axe de position du viewmodel 2D.
	func kick(amount: float) -> void:
		# Kick en DÉPLACEMENT : la position saute d'un coup, le ressort n'a plus qu'à revenir.
		spring.value += amount * (1.0 - residual_share)
		residual += amount * residual_share

	func step(dt: float) -> float:
		spring.step(dt)
		# `approach(residual, 0, residual_tau, dt)`, recopié en une ligne : la classe interne
		# reste autonome — elle ne dépend d'aucun membre du script englobant.
		if residual_tau <= TAU_EPS:
			residual = 0.0
		else:
			residual *= exp(-dt / residual_tau)
		if absf(residual) < RESIDUAL_SNAP_EPS:
			residual = 0.0
		value = spring.value + residual
		return value

	# Repos EXACT des deux étages — même service que `TrenchSpring.at_rest`, pour le LOT E.
	func at_rest() -> bool:
		return spring.at_rest() and residual == 0.0
