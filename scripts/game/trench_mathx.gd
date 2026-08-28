extends RefCounted
# =================================================================================================
# LA TRANCHÉE — VUE 3D (§8.152 LOT 3D-0, moitié « maths ») — LE KIT DU RIG.
#
# Port FIDÈLE de `War-Of-Indipendence/Claude-of-Duty-main/src/weapons/mathx.js` (230 l.).
# Son en-tête donne la règle qui gouverne tout le lot : « Everything here is allocation-free after
# construction […] No `new` inside update() » — c'est la règle n°5 du cahier §4.
#
# ╔═ POURQUOI CE FICHIER EXISTE À CÔTÉ DE `trench_springs.gd`, ET NE LE DUPLIQUE PAS ═════════════╗
# ║ `trench_springs.gd` (§8.151 lot B) porte `src/player/springs.js` — un fichier DIFFÉRENT de    ║
# ║ `src/weapons/mathx.js`. Les deux existent chez la référence, côte à côte, parce qu'ils        ║
# ║ servent deux clients qui n'ont pas les mêmes besoins :                                        ║
# ║   • `springs.js`  → le FEEL du joueur (recul deux étages, flinch, secousse). Déjà porté.      ║
# ║   • `mathx.js`    → le RIG du viewmodel (couches additives de `viewmodel.js`). C'est ICI.     ║
# ║                                                                                               ║
# ║ CE FICHIER NE RE-PORTE RIEN de ce que `trench_springs.gd` tient déjà — il le PRÉLOAD :        ║
# ║   `approach` (forme tau) · `move_toward_rate` · `angle_delta` · `hash_noise` ·                ║
# ║   `TrenchSpring` · `TrenchRecoilAxis`  →  restent chez lui, seule source.                     ║
# ║ Et il n'importe pas non plus ce que Godot donne en natif : `clamp`, `clampf`, `lerp`,         ║
# ║ `smoothstep`, `TAU`, `deg_to_rad`, `fmod` (les 6 premiers exports de `mathx.js`).             ║
# ║                                                                                               ║
# ║ ⚠️ IL Y A DONC DEUX CLASSES DE RESSORT DANS LE PROJET, ET C'EST VOULU — voir `MathxSpring`.   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# CE QUI EST PORTÉ ICI (le reste de `mathx.js`, dans son ordre) :
#   `smootherstep` · `ease_out_back` · `ease_out_cubic` · `ease_in_cubic` · `ease_in_out_sine` ·
#   `damp` (forme TAUX) · `MathxSpring` · `MathxSpring3` · `Noise1` · `wrap_pi`
# PLUS une dépendance que `mathx.js` reçoit de l'extérieur et qu'il FAUT porter pour que `Noise1`
# existe : `TrenchRng`, port de `src/core/rng.js` (xoshiro128**). Cf. la règle n°4 du cahier §4 —
# « RNG déterministe […] ⛔ jamais `randf()` global ».
#
# ÉCARTS ASSUMÉS (tout le reste est ligne à ligne) :
#   • plus de chaînage (`return this`) : les mutateurs rendent `void`, style maison — même écart
#     que `trench_springs.gd` a déjà assumé.
#   • `Spring.set()` → `set_value()` : `set` est une méthode native d'Object en GDScript.
#   • `MathxSpring` gagne l'ASSÈCHEMENT sous epsilon et `at_rest()`, que `mathx.js` n'a pas. Raison
#     identique à celle inscrite dans `trench_springs.gd` : sans collage net, la queue
#     exponentielle agite des décimales indéfiniment et le viewmodel « au repos » n'est jamais
#     bit-stable pour les captures. C'est une ADDITION, elle ne change aucune trajectoire visible.
#   • `Spring3.writeTo(v, scale)` → `write_to(scale) -> Vector3` : GDScript rend les Vector3 par
#     valeur, il n'y a pas de cible à muter — et donc rien à préallouer.
#   • les entiers de `TrenchRng` sont masqués `& 0xFFFFFFFF` à chaque étape pour reproduire
#     l'arithmétique 32 BITS de JS (`|0`, `>>>`, `Math.imul`) sur les entiers 64 bits de GDScript.
#     Même technique que `hash_noise` dans `trench_springs.gd` — mêmes bits, mêmes nombres.
# =================================================================================================


# =================================================================================================
# HELPERS SCALAIRES — statiques, sans état
# =================================================================================================

# Lissage du 5ᵉ ORDRE : dérivées PREMIÈRE **et** SECONDE nulles aux deux bouts. Godot n'a que
# `smoothstep` (3ᵉ ordre, seule la dérivée première s'annule) — d'où le portage. La différence se
# voit : au raccord d'une couche du rig, le 3ᵉ ordre laisse un à-coup d'accélération.
static func smootherstep(edge0: float, edge1: float, x: float) -> float:
	var span := edge1 - edge0
	if absf(span) < 1e-6:
		span = 1e-6
	var t := clampf((x - edge0) / span, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


# Sortie avec LÉGER DÉPASSEMENT — « used for mag slaps and bolt releases » dit la référence : le
# chargeur claque au-delà de sa place puis se pose. `k` règle l'ampleur du dépassement.
static func ease_out_back(t: float, k := 1.6) -> float:
	var p := t - 1.0
	return 1.0 + p * p * ((k + 1.0) * p + k)


static func ease_out_cubic(t: float) -> float:
	var p := 1.0 - t
	return 1.0 - p * p * p


static func ease_in_cubic(t: float) -> float:
	return t * t * t


static func ease_in_out_sine(t: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(t, 0.0, 1.0))


# ╔═ `damp` — APPROCHE EXPONENTIELLE, PARAMÉTRÉE EN **TAUX** ═════════════════════════════════════╗
# ║ `rate` est l'INVERSE de la constante de temps : « combien d'e-plis par seconde ».             ║
# ║ ⚠️ NE PAS CONFONDRE avec `TrenchSprings.approach(current, target, tau, dt)`, qui prend le TAU ║
# ║ (le temps des 63 % parcourus). Les deux sont la même courbe : `rate == 1.0 / tau`.            ║
# ║ Les deux paramétrages coexistent parce que les CONSTANTES de chaque référence sont écrites    ║
# ║ dans l'une ou dans l'autre — les convertir à la main serait la première source d'erreur de    ║
# ║ portage. On garde donc les nombres de `viewmodel.js` tels qu'ils sont écrits chez eux.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return target + (current - target) * exp(-rate * dt)


# Repli d'un angle dans (-PI, PI]. (Godot 4.3+ a `wrapf`/`angle_difference` ; porté quand même —
# le module se suffit à lui-même, comme `angle_delta` chez `trench_springs.gd`.)
static func wrap_pi(a: float) -> float:
	var r := fmod(a + PI, TAU)
	if r < 0.0:
		r += TAU
	return r - PI


# =================================================================================================
# `TrenchRng` — PRNG DÉTERMINISTE xoshiro128** (port de `src/core/rng.js`, 108 l.)
# =================================================================================================
# ╔═ POURQUOI PAS `RandomNumberGenerator` NI `randf()` ═══════════════════════════════════════════╗
# ║ L'en-tête de la référence donne la raison exacte, et c'est LA nôtre : « capture mode          ║
# ║ produces byte-identical frames ». Les maillages d'armes sont GÉNÉRÉS avec des micro-aléas     ║
# ║ (rayures, jeu de pièces) ; si ces aléas changent d'un boot à l'autre, deux captures du même   ║
# ║ plan diffèrent et l'`imagediff_trench.py` du §8.151 lot 0 ne prouve plus rien.                ║
# ║ Et un RNG GLOBAL consommé ici décalerait la séquence de tout ce qui tire dedans ailleurs.     ║
# ║ ⚠️ `RandomNumberGenerator` de Godot est un PCG32 : même contrat, mais PAS la même suite —     ║
# ║ les constantes de la référence sont calées sur CETTE suite-ci.                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
class TrenchRng:
	extends RefCounted

	const MASK32 := 0xFFFFFFFF
	# Le nombre d'or en 32 bits — la graine par défaut de la référence.
	const GOLDEN32 := 0x9E3779B9

	var s0 := 0
	var s1 := 0
	var s2 := 0
	var s3 := 0
	# Le second tirage de Box-Muller, mis de côté (`_spare` chez eux). `NAN` = rien en réserve :
	# GDScript n'a pas d'`undefined`, et NAN est la seule valeur qui ne peut pas être un vrai
	# tirage gaussien.
	var _spare := NAN

	func _init(p_seed := GOLDEN32) -> void:
		seed_with(p_seed)

	# SplitMix32 : étale UNE graine 32 bits sur les quatre mots d'état. Sans cet étalement, deux
	# graines voisines (0, 1, 2…) donnent des suites corrélées sur les premiers tirages.
	func seed_with(s: int) -> void:
		var z := s & MASK32
		for i in 4:
			z = (z + GOLDEN32) & MASK32
			var x := z
			x = _imul32(x ^ (x >> 16), 0x21F0AAAD)
			x = _imul32(x ^ (x >> 15), 0x735A2D97)
			x = (x ^ (x >> 15)) & MASK32
			match i:
				0: s0 = x
				1: s1 = x
				2: s2 = x
				_: s3 = x
		_spare = NAN

	# Entier non signé sur 32 bits — le cœur, tout le reste en dérive.
	func u32() -> int:
		var result := _imul32(_rot32(_imul32(s1, 5), 7), 9)
		var t := (s1 << 9) & MASK32
		s2 ^= s0
		s3 ^= s1
		s1 ^= s2
		s0 ^= s3
		s2 ^= t
		s3 = _rot32(s3, 11)
		return result

	# Uniforme dans [0, 1).
	func rand_float() -> float:
		return float(u32()) / 4294967296.0

	# Uniforme dans [min, max).
	func range_float(min_v: float, max_v: float) -> float:
		return min_v + (max_v - min_v) * rand_float()

	# Uniforme ENTIER dans [min, max] — bornes INCLUSES (contrat de la référence).
	func range_int(min_v: int, max_v: int) -> int:
		return min_v + (u32() % (max_v - min_v + 1))

	# Uniforme dans [-1, 1] — le tirage que `Noise1` consomme pour sa table.
	func signed() -> float:
		return rand_float() * 2.0 - 1.0

	# Normale centrée réduite (Box-Muller). Un appel sur deux ne coûte rien : la paire produit
	# deux échantillons, le second attend dans `_spare`.
	func gauss() -> float:
		if not is_nan(_spare):
			var v := _spare
			_spare = NAN
			return v
		var u := 0.0
		while u == 0.0:
			u = rand_float()
		var r := sqrt(-2.0 * log(u))
		var th := TAU * rand_float()
		_spare = r * sin(th)
		return r * cos(th)

	func pick(arr: Array) -> Variant:
		return arr[u32() % arr.size()]

	# Point uniforme DANS le disque unité (la racine sur le rayon est ce qui évite l'entassement
	# au centre) — dispersion de balle, émission de particules.
	func disc() -> Vector2:
		var r := sqrt(rand_float())
		var a := rand_float() * TAU
		return Vector2(cos(a) * r, sin(a) * r)

	# Flux INDÉPENDANT dérivé de celui-ci : un sous-système peut tirer sans décaler la séquence
	# d'un autre. C'est ce qui permet de générer l'arme B sans changer d'un iota l'arme A.
	func fork() -> TrenchRng:
		return TrenchRng.new(u32())

	# Rotation binaire à gauche sur 32 bits.
	func _rot32(x: int, k: int) -> int:
		return (((x << k) & MASK32) | (x >> (32 - k))) & MASK32

	# Le `Math.imul` de JS : produit modulo 2³². Les deux facteurs tiennent sur 32 bits, leur
	# produit sur 64 — aucun débordement avant le masque.
	func _imul32(a: int, b: int) -> int:
		return (a * b) & MASK32


# =================================================================================================
# `MathxSpring` — OSCILLATEUR AMORTI, INTÉGRATION **IMPLICITE** (le ressort du RIG)
# =================================================================================================
# ╔═ ⚠️⚠️ POURQUOI CE RESSORT N'EST PAS `TrenchSprings.TrenchSpring` ═════════════════════════════╗
# ║ Ce ne sont PAS deux écritures du même calcul — ce sont deux INTÉGRATEURS différents :         ║
# ║                                                                                               ║
# ║   `TrenchSpring` (§8.151)  : Euler semi-implicite EXPLICITE, découpé en sous-pas de 1/360 s.  ║
# ║                              Stable parce qu'on ne lui donne jamais un grand pas.             ║
# ║   `MathxSpring`  (ici)     : forme IMPLICITE — on résout v(n+1) d'un coup                     ║
# ║                              (`denom = 1 + 2·z·w·dt + w²·dt²`), puis on intègre x avec.       ║
# ║                              Inconditionnellement stable À TOUT dt, sans aucun sous-pas.      ║
# ║                                                                                               ║
# ║ Les deux sont corrects. Mais leur RÉPONSE diffère (l'implicite amortit un peu plus vite aux   ║
# ║ grands pas), et TOUTES les constantes de `viewmodel.js` — chaque `f` et chaque `z` des ~20    ║
# ║ couches du rig — ont été réglées à l'œil CONTRE CETTE COURBE-CI. Remplacer l'intégrateur en   ║
# ║ gardant les nombres, c'est garder la partition en changeant l'instrument : le cahier §4.2 le  ║
# ║ tranche (« mêmes constantes, mêmes ordres d'application »), et le §8.152 tout entier repose   ║
# ║ sur l'idée que **c'est le rig qui fait la sensation, pas les maillages**.                     ║
# ║                                                                                               ║
# ║ RÈGLE D'EMPLOI, pour que les deux ne se mélangent jamais :                                    ║
# ║   • quelque chose que `viewmodel.js` anime  →  `MathxSpring` ;                                ║
# ║   • quelque chose que `springs.js` anime    →  `TrenchSprings.TrenchSpring`.                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# `f` : fréquence propre en Hz. `z` : rapport d'amortissement (1 = critique, sans dépassement ;
# 0,5 = vif ; > 1 = mou). `kick()` injecte de la VÉLOCITÉ — c'est le chemin du recul.
class MathxSpring:
	extends RefCounted

	# L'ASSÈCHEMENT — ADDITION vis-à-vis de `mathx.js`, cf. en-tête du fichier. Sous ces deux
	# seuils, valeur ET vélocité collent NET sur la cible : c'est ce collage qui rend une frame de
	# repos bit-stable, donc capturable. Seuils repris à l'identique de `trench_springs.gd`.
	const SNAP_VALUE_EPS := 1e-7
	const SNAP_VELOCITY_EPS := 1e-6

	var f: float
	var z: float
	var x: float
	var v := 0.0
	var target: float

	func _init(p_f := 12.0, p_z := 1.0, p_value := 0.0) -> void:
		f = p_f
		z = p_z
		x = p_value
		target = p_value

	# Pose la valeur ET tue la vélocité (le `set()` de la référence, renommé : `set` est une
	# méthode native d'Object en GDScript).
	func set_value(value: float) -> void:
		x = value
		v = 0.0
		target = value

	# Coup de vélocité instantané — « the recoil impulse path » dit la référence.
	func kick(dv: float) -> void:
		v += dv

	func step(dt: float, p_target := INF) -> float:
		# `INF` = sentinelle « garde la cible courante ». La référence écrit ça avec un paramètre
		# par défaut `= this.target`, que GDScript n'autorise pas (les valeurs par défaut y sont
		# des constantes, pas des expressions sur `self`).
		if not is_inf(p_target):
			target = p_target
		var w := TAU * f
		# Euler semi-implicite sous forme IMPLICITE : on résout v(n+1) puis on intègre x avec lui.
		var denom := 1.0 + 2.0 * z * w * dt + w * w * dt * dt
		v = (v + w * w * dt * (target - x)) / denom
		x += v * dt
		if absf(x - target) < SNAP_VALUE_EPS and absf(v) < SNAP_VELOCITY_EPS:
			x = target
			v = 0.0
		return x

	# Repos EXACT (collé, pas « à peu près ») — le témoin que lisent les sondes et la porte de
	# captures. Même service que `TrenchSprings.TrenchSpring.at_rest()`.
	func at_rest() -> bool:
		return x == target and v == 0.0


# =================================================================================================
# `MathxSpring3` — TROIS ressorts indépendants partageant fréquence et amortissement
# =================================================================================================
# Sert aussi bien une POSITION qu'un triplet d'EULER — c'est le même objet chez la référence, et
# c'est voulu : une couche du rig pousse les deux de la même main.
class MathxSpring3:
	extends RefCounted

	var a: MathxSpring
	var b: MathxSpring
	var c: MathxSpring

	func _init(p_f := 12.0, p_z := 1.0) -> void:
		a = MathxSpring.new(p_f, p_z)
		b = MathxSpring.new(p_f, p_z)
		c = MathxSpring.new(p_f, p_z)

	# `set f` / `set z` de la référence : GDScript n'a pas d'accesseur sur une propriété d'une
	# classe interne sans la déclarer, donc ce sont des méthodes explicites. Écrites à chaud par
	# les curseurs de réglage sans casser l'état en vol (même contrat que `TrenchSpring`).
	func set_freq(value: float) -> void:
		a.f = value
		b.f = value
		c.f = value

	func set_damping(value: float) -> void:
		a.z = value
		b.z = value
		c.z = value

	func get_freq() -> float:
		return a.f

	func get_damping() -> float:
		return a.z

	func kick(kx: float, ky: float, kz: float) -> void:
		a.kick(kx)
		b.kick(ky)
		c.kick(kz)

	func reset() -> void:
		a.set_value(0.0)
		b.set_value(0.0)
		c.set_value(0.0)

	func step(dt: float, tx := 0.0, ty := 0.0, tz := 0.0) -> void:
		a.step(dt, tx)
		b.step(dt, ty)
		c.step(dt, tz)

	func get_x() -> float:
		return a.x

	func get_y() -> float:
		return b.x

	func get_z() -> float:
		return c.x

	# `writeTo(v, scale)` de la référence : là-bas il fallait muter un `THREE.Vector3` préexistant
	# pour ne rien allouer par frame ; ici `Vector3` est un TYPE VALEUR de Godot (sur la pile,
	# jamais sur le tas), donc le rendre par valeur ne coûte aucune allocation.
	func write_to(p_scale := 1.0) -> Vector3:
		return Vector3(a.x * p_scale, b.x * p_scale, c.x * p_scale)

	# Repos EXACT des trois axes — addition, même motif que partout ailleurs.
	func at_rest() -> bool:
		return a.at_rest() and b.at_rest() and c.at_rest()


# =================================================================================================
# `Noise1` — BRUIT DE VALEUR 1D EN COUCHES, interpolation cubique
# =================================================================================================
# ╔═ CE QUE CE BRUIT FAIT, ET POURQUOI IL N'EST PAS `hash_noise` ═════════════════════════════════╗
# ║ `TrenchSprings.hash_noise` est un hachage PUR : aucune table, aucun état, fondu de Hermite    ║
# ║ entre deux cellules. Parfait pour une secousse — court, violent, oublié aussitôt.             ║
# ║                                                                                               ║
# ║ `Noise1` est autre chose : une TABLE lissée une fois à la construction, lue en Catmull-Rom    ║
# ║ (donc C1 : la dérivée est continue, « the weapon never ticks » dit la référence). C'est ce    ║
# ║ qu'exige le BALANCEMENT DE REPOS — un mouvement lent que le joueur regarde pendant des        ║
# ║ minutes : il ne doit ni boucler visiblement, ni présenter le moindre à-coup. Un hachage       ║
# ║ Hermite a une dérivée seconde discontinue à chaque cellule ; sur une respiration à 0,2 Hz,    ║
# ║ ça se voit.                                                                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
class Noise1:
	extends RefCounted

	var size: int
	# `Float32Array` chez eux → `PackedFloat32Array` ici : MÊME précision 32 bits. Ce n'est pas un
	# détail — la table est lissée puis relue des milliers de fois, et la troncature f32 fait
	# partie des nombres qu'on reproduit.
	var t := PackedFloat32Array()

	func _init(rng: TrenchRng, p_size := 512) -> void:
		size = p_size
		t.resize(p_size)
		for i in p_size:
			t[i] = rng.signed()
		# Un lissage UNE FOIS à la construction, pour que les octaves basses soient douces plutôt
		# que hérissées. Noyau [1, 2, 1] / 4 sur la table refermée sur elle-même.
		var tmp := PackedFloat32Array()
		tmp.resize(p_size)
		for i in p_size:
			tmp[i] = (t[(i - 1 + p_size) % p_size] + t[i] * 2.0 + t[(i + 1) % p_size]) * 0.25
		t = tmp

	# Lecture en Catmull-Rom sur les 4 cellules qui encadrent x.
	func at(x: float) -> float:
		# ⚠️ `floorf`, pas `floor` : le `floor` global de GDScript est déclaré Variant, et l'inférence
		# de `fx` échoue à la compilation (« Cannot infer the type »).
		var fx := x - floorf(x)
		var i := ((floori(x) % size) + size) % size
		var a := t[(i - 1 + size) % size]
		var b := t[i]
		var c := t[(i + 1) % size]
		var d := t[(i + 2) % size]
		var t1 := fx
		var t2 := t1 * t1
		var t3 := t2 * t1
		return 0.5 * (
			(2.0 * b)
			+ (-a + c) * t1
			+ (2.0 * a - 5.0 * b + 4.0 * c - d) * t2
			+ (-a + 3.0 * b - 3.0 * c + d) * t3
		)

	# Somme d'octaves (fBm). La lacunarité IRRATIONNELLE (2,11713 au lieu de 2) est ce qui empêche
	# les octaves de se remettre en phase : sans elle, le motif se répète et l'œil l'attrape.
	# Le décalage `i * 37.19` par octave évite qu'elles partent toutes du même point de la table.
	func fbm(x: float, oct := 3, gain := 0.5) -> float:
		var sum := 0.0
		var amp := 1.0
		var norm := 0.0
		var freq := 1.0
		for i in oct:
			sum += at(x * freq + i * 37.19) * amp
			norm += amp
			amp *= gain
			freq *= 2.11713
		return sum / (norm if norm != 0.0 else 1.0)
