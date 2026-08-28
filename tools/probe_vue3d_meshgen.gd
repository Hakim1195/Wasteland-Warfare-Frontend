extends Node

# =================================================================================================
# SONDE §8.152 LOT 3D-0 — LE SOCLE : `trench_mathx.gd` + `trench_meshgen.gd` tiennent-ils AVANT
# qu'une seule pièce d'arme ne soit dessinée dessus ?
#
# ╔═ CE QU'ELLE PROUVE, ET LA DIFFÉRENCE ENTRE UN CONTRÔLE **DESCRIPTIF** ET UN CONTRÔLE **DUR** ═╗
# ║ La leçon n°4 du §8.152 (« une sonde dont les fixtures sont les valeurs de PRODUCTION ne       ║
# ║ prouve rien ») impose de séparer les deux, alors la sonde les sépare EXPLICITEMENT :          ║
# ║                                                                                               ║
# ║  DURS — vrais indépendamment de la façon dont le code est écrit. Ils ne peuvent PAS être      ║
# ║  satisfaits par construction, et c'est eux qui attrapent une régression :                     ║
# ║   D1 ÉTANCHÉITÉ : sur un solide fermé, chaque arête est parcourue EXACTEMENT UNE FOIS DANS    ║
# ║      CHAQUE SENS. Un trou dans le maillage, un quad sauté, une couronne de biseau mal         ║
# ║      recousue : tout ça rougit ici et NULLE PART ailleurs.                                    ║
# ║   D2 VOLUME SIGNÉ > 0, et proche du volume ANALYTIQUE calculé à la main. C'est LE contrôle    ║
# ║      du piège three.js↔Godot : un maillage globalement retourné rend un volume NÉGATIF.       ║
# ║      ⚠️ La cohérence LOCALE sens↔normale, elle, est garantie par construction (`_tri` oriente ║
# ║      d'après la normale) — la re-vérifier serait une TAUTOLOGIE. On la teste quand même en    ║
# ║      C3, mais en sachant qu'elle ne vaut que comme garde-fou de refonte, pas comme preuve.    ║
# ║   D3 AIRE DU CAPOT AJOURÉ = aire extérieure − aire du trou. Un trou silencieusement raté      ║
# ║      (triangulation qui rend zéro triangle, fente qui recoupe le contour) se voit ici.        ║
# ║   D4 CHANFREIN DE CRÊTE DU RAIL : au sommet, la largeur est `width − 2·ch`, pas `width`.      ║
# ║      C'est la mesure du « peigne à 1,35 diaphragme » de la référence, transformée en garde.   ║
# ║   D5 DÉTERMINISME : deux générations rendent des tableaux IDENTIQUES (règle n°4 du cahier).   ║
# ║                                                                                               ║
# ║  DESCRIPTIFS — des BASELINES. Ils figent ce que le code fait aujourd'hui (compte de           ║
# ║  triangles, budget) pour qu'un changement involontaire se remarque. Ils ne prouvent RIEN sur  ║
# ║  la justesse : c'est D1-D5 qui la prouvent. Étiquetés « [base] ».                             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# SABOTAGES QUI DOIVENT LA FAIRE ROUGIR (à rejouer à chaque refonte du socle) :
#   1. dans `MeshData.add_tri`, remettre l'ordre `a, b, c` (le parcours de three.js) → D2 rouge.
#   2. dans `extrude`, sauter l'émission d'une couronne de biseau                    → D1 rouge.
#   3. dans `picatinny`, forcer `ch = 0.0`                                           → D4 rouge.
#   4. dans `_bridge_one_hole`, rendre `outer` tel quel (trou ignoré)                → D3 rouge.
#   5. dans `TrenchRng.u32`, retirer un masque `& MASK32`                            → R1 rouge.
#   6. dans `MathxSpring.step`, retirer l'assèchement                                → S2 rouge.
#
# ⚠️ LANCEMENT — le headless SUFFIT (maths pures + tableaux, aucun rendu) :
#   & <godot_console> --headless --path frontend res://tools/probe_vue3d_meshgen.tscn
# =================================================================================================

const Mathx := preload("res://scripts/game/trench_mathx.gd")
const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const Springs := preload("res://scripts/game/trench_springs.gd")

# Quantum de position pour l'analyse topologique : 1 nm. Bien plus fin que la fente du « trou de
# serrure » (0,1 µm) — si deux sommets censés être confondus ne le sont pas, on veut le SAVOIR,
# pas l'absorber dans un arrondi complaisant.
const POS_QUANTUM := 1e-9

var _fails: Array = []
var _ran := 0

# ╔═ ⚠️⚠️ LE GARDE-FOU CONTRE LE FAUX VERT — né d'un vrai incident, le 2026-08-27 ═══════════════╗
# ║ Au premier lancement, `trench_mathx.gd` et `trench_meshgen.gd` ne compilaient pas. Godot a    ║
# ║ journalisé une `SCRIPT ERROR` par section, SAUTÉ les huit sections... et cette sonde a        ║
# ║ fièrement conclu **« TOUT VERT »** : `_fails` était vide, forcément — aucun contrôle n'avait  ║
# ║ tourné. C'est EXACTEMENT le faux vert que la mémoire du projet répète de traquer, et il est   ║
# ║ arrivé ici dans la première heure d'existence de la sonde.                                    ║
# ║                                                                                               ║
# ║ ⚠️ Leçon annexe, tout aussi coûteuse : **`--import` N'A PAS VU CES ERREURS**. Il n'a rien     ║
# ║ signalé sur deux scripts qui ne compilaient pas — il n'analyse que ce qu'il charge. Seul le   ║
# ║ lancement RÉEL de la scène les a sorties. Ne jamais conclure « 0 ERROR » d'un import seul.    ║
# ║                                                                                               ║
# ║ PARADE : on ne compte pas seulement les ÉCHECS, on compte les contrôles qui ont RÉELLEMENT    ║
# ║ tourné, et on exige le compte EXACT. Une section qui meurt en route (erreur de script,        ║
# ║ exception, retour prématuré) fait chuter le total ⇒ ROUGE.                                    ║
# ║ ⚠️ En ajoutant ou retirant un `_ok(...)`, METTRE À JOUR `CHECKS_ATTENDUS` — sinon la sonde    ║
# ║ rougit, ce qui est le BON sens de l'erreur : mieux vaut un rouge à expliquer qu'un vert       ║
# ║ imaginaire. (Les `_info(...)` ne comptent pas : ce sont des baselines, pas des contrôles.)    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ⚠️ C'est un compte D'EXÉCUTION, pas un `grep` de `_ok(` : les helpers `_check_solid` et
# `_check_manifold` appellent eux aussi `_ok`, plusieurs fois chacun. Détail par section :
#   R=7 · N=4 · S=9 · P=2 · topologie=8 · trous=3 · picatinny=3 · assembly=4.
const CHECKS_ATTENDUS := 40


func _ok(label: String, cond: bool, detail := "") -> void:
	_ran += 1
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _info(label: String, detail: String) -> void:
	print("  [base] %s   | %s" % [label, detail])


func _ready() -> void:
	print("\n===== SONDE §8.152 LOT 3D-0 — SOCLE MATHS + MAILLAGES =====\n")
	print("-- R. RNG deterministe (port de src/core/rng.js) --")
	_probe_rng()
	print("\n-- N. Noise1 (bruit en couches du balancement de repos) --")
	_probe_noise()
	print("\n-- S. Ressorts du RIG (MathxSpring / MathxSpring3) + helpers --")
	_probe_springs()
	print("\n-- P. Primitives : non-vides, budget, determinisme --")
	_probe_primitives()
	print("\n-- D1/D2. Etancheite et volume signe (le piege three.js <-> Godot) --")
	_probe_topology()
	print("\n-- D3. Extrusion ajouree : le trou existe-t-il vraiment ? --")
	_probe_holes()
	print("\n-- D4. Rail Picatinny : le chanfrein de crete est-il la ? --")
	_probe_picatinny()
	print("\n-- A. Assembly : seaux par materiau, miroir, ancres --")
	_probe_assembly()
	# ⚠️ L'ORDRE COMPTE : on juge d'abord si la sonde a TOUT joué, ensuite seulement si ce qu'elle
	# a joué est vert. Un vert sur 3 contrôles joués sur 33 n'est PAS un vert.
	var complet := _ran == CHECKS_ATTENDUS
	if not complet:
		print("\n[ROUGE] SONDE INCOMPLETE : %d controles joues sur %d attendus."
			% [_ran, CHECKS_ATTENDUS])
		print("        Une section est morte en route (erreur de script ?). Relire les lignes")
		print("        SCRIPT ERROR plus haut AVANT toute autre conclusion.")
	print("\n%s" % (("TOUT VERT (%d/%d controles joues)" % [_ran, CHECKS_ATTENDUS])
		if (_fails.is_empty() and complet)
		else ("ECHEC : %d rouge(s) sur %d joues (%d attendus) -> %s"
			% [_fails.size(), _ran, CHECKS_ATTENDUS, str(_fails)])))
	get_tree().quit(0 if (_fails.is_empty() and complet) else 1)


# =================================================================================================
# R. `TrenchRng` — xoshiro128**
# =================================================================================================
func _probe_rng() -> void:
	# R1. Determinisme : meme graine, meme suite. Et les valeurs restent DANS [0, 2^32) — c'est ce
	# qui rougit si un masque 32 bits saute (les entiers 64 bits de GDScript deborderaient).
	var a := Mathx.TrenchRng.new(12345)
	var b := Mathx.TrenchRng.new(12345)
	var same := true
	var in_range := true
	var seq := []
	for i in 64:
		var ua := a.u32()
		var ub := b.u32()
		if ua != ub:
			same = false
		if ua < 0 or ua >= 4294967296:
			in_range = false
		if i < 4:
			seq.append(ua)
	_ok("R1 meme graine -> meme suite, et tout tient sur 32 bits non signes",
		same and in_range, "4 premiers u32 : " + str(seq))

	# R2. Deux graines differentes divergent des le premier tirage (le SplitMix32 d'etalement fait
	# son travail : sans lui, les graines voisines donnent des debuts correles).
	var c := Mathx.TrenchRng.new(12345)
	var d := Mathx.TrenchRng.new(12346)
	_ok("R2 deux graines voisines divergent des le 1er tirage", c.u32() != d.u32())

	# R3. Bornes des convertisseurs.
	var e := Mathx.TrenchRng.new(7)
	var f_ok := true
	var s_ok := true
	var i_ok := true
	var disc_ok := true
	for i in 4000:
		var fv := e.rand_float()
		if fv < 0.0 or fv >= 1.0:
			f_ok = false
		var sv := e.signed()
		if sv < -1.0 or sv > 1.0:
			s_ok = false
		var iv := e.range_int(3, 9)
		if iv < 3 or iv > 9:
			i_ok = false
		if e.disc().length() > 1.0 + 1e-6:
			disc_ok = false
	_ok("R3 float dans [0,1), signed dans [-1,1], range_int borne INCLUSE, disc dans le disque",
		f_ok and s_ok and i_ok and disc_ok)

	# R4. `fork()` rend un flux INDEPENDANT : c'est ce qui permet de generer l'arme B sans decaler
	# d'un iota la sequence de l'arme A.
	var p := Mathx.TrenchRng.new(99)
	var child := p.fork()
	var q := Mathx.TrenchRng.new(99)
	q.u32()  # le fork a consomme exactement un tirage du parent
	_ok("R4 fork() consomme UN tirage du parent et repart sur un flux distinct",
		p.u32() == q.u32() and child.u32() != p.u32())

	# ╔═ R6/R7 — LES CONTRÔLES QUI ONT MANQUÉ AU PREMIER JET ════════════════════════════════════╗
	# ║ La passe de sabotage a démasqué une faiblesse de R1 : en retirant un masque `& MASK32`    ║
	# ║ de `TrenchRng.u32`, la sonde restait **VERTE**. Pourquoi ? Parce que R1 ne compare que    ║
	# ║ deux RNG SABOTÉS DE LA MÊME FAÇON (forcément d'accord entre eux), et ne regarde que la    ║
	# ║ SORTIE — qui reste masquée par `_imul32`. L'ÉTAT interne, lui, débordait des 32 bits, et  ║
	# ║ la pollution ne redescendait dans les tirages qu'au bout de quelques tours.               ║
	# ║                                                                                           ║
	# ║ ⚠️ LEÇON : « deux exécutions sont d'accord » ne prouve RIEN sur la justesse — seulement   ║
	# ║ sur le déterminisme. Il faut un point de comparaison EXTÉRIEUR. Les valeurs ci-dessous    ║
	# ║ viennent d'une réplique de xoshiro128**/SplitMix32 écrite HORS MOTEUR (Python, entiers    ║
	# ║ exacts) : elles ne peuvent pas dériver avec le code qu'elles surveillent.                 ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var ref := Mathx.TrenchRng.new(12345)
	var attendu := [1093274547, 203003357, 3741353573, 3803725158,
		4178738660, 810247443, 1347789520, 4037788777]
	var obtenu := []
	for i in 8:
		obtenu.append(ref.u32())
	_ok("R6 les 8 premiers tirages sont ceux de la replique hors moteur (graine 12345)",
		obtenu == attendu, "obtenu " + str(obtenu))

	# R7. Une somme de contrôle sur 1000 tirages : sensible au MOINDRE bit, et l'ÉTAT interne doit
	# rester dans les 32 bits. C'est ce couple qui attrape un masque manquant — le sabotage n°5.
	var chk := Mathx.TrenchRng.new(12345)
	var acc := 0
	var etat_borne := true
	for i in 1000:
		acc = (acc * 31 + chk.u32()) & 0xFFFFFFFF
		if chk.s0 < 0 or chk.s0 > 0xFFFFFFFF or chk.s1 < 0 or chk.s1 > 0xFFFFFFFF 				or chk.s2 < 0 or chk.s2 > 0xFFFFFFFF or chk.s3 < 0 or chk.s3 > 0xFFFFFFFF:
			etat_borne = false
	_ok("R7 somme de controle sur 1000 tirages + etat interne borne a 32 bits",
		acc == 3039700286 and etat_borne,
		"somme %d (replique hors moteur : 3039700286) · etat borne %s" % [acc, str(etat_borne)])

	# R5. `gauss()` : la reserve de Box-Muller est bien rendue, et la loi est centree reduite.
	var g := Mathx.TrenchRng.new(2024)
	var sum := 0.0
	var sum2 := 0.0
	var n := 20000
	for i in n:
		var v := g.gauss()
		sum += v
		sum2 += v * v
	var mean := sum / n
	var var_ := sum2 / n - mean * mean
	_ok("R5 gauss() centree reduite (moyenne ~0, variance ~1)",
		absf(mean) < 0.03 and absf(var_ - 1.0) < 0.06,
		"moyenne %.4f · variance %.4f" % [mean, var_])


# =================================================================================================
# N. `Noise1`
# =================================================================================================
func _probe_noise() -> void:
	var n1 := Mathx.Noise1.new(Mathx.TrenchRng.new(4242), 512)
	var n2 := Mathx.Noise1.new(Mathx.TrenchRng.new(4242), 512)
	var same := true
	var bounded := true
	for i in 400:
		var x := i * 0.37
		var v1 := n1.at(x)
		if absf(v1 - n2.at(x)) > 0.0:
			same = false
		if absf(v1) > 1.5:
			bounded = true if absf(v1) <= 1.5 else false
	_ok("N1 meme graine -> meme table -> memes valeurs (bit a bit)", same)
	_ok("N2 valeurs bornees (Catmull-Rom peut depasser un peu la table)", bounded)

	# N3. CONTINUITE — c'est la raison d'etre de `Noise1` face a `hash_noise` : le balancement de
	# repos est regarde pendant des minutes, il ne doit pas « ticker ». On mesure le plus grand
	# saut entre deux echantillons proches ; une table lue en escalier le ferait exploser.
	var max_jump := 0.0
	var prev := n1.at(0.0)
	var x := 0.0
	while x < 60.0:
		x += 0.002
		var cur := n1.at(x)
		max_jump = maxf(max_jump, absf(cur - prev))
		prev = cur
	_ok("N3 continuite : aucun saut brutal sur 60 unites echantillonnees au 1/500",
		max_jump < 0.05, "plus grand saut %.6f" % max_jump)

	# N4. fBm normalise : la somme d'octaves reste dans la meme echelle que `at()`.
	var max_fbm := 0.0
	for i in 2000:
		max_fbm = maxf(max_fbm, absf(n1.fbm(i * 0.11, 3, 0.5)))
	_ok("N4 fbm() reste normalise (pas d'accumulation d'octaves)", max_fbm < 1.6,
		"max |fbm| %.4f" % max_fbm)


# =================================================================================================
# S. Ressorts du rig et helpers scalaires
# =================================================================================================
func _probe_springs() -> void:
	# S1. Convergence : un ressort critique rejoint sa cible.
	var s := Mathx.MathxSpring.new(12.0, 1.0, 0.0)
	for i in 600:
		s.step(1.0 / 60.0, 1.0)
	_ok("S1 MathxSpring converge vers sa cible", absf(s.x - 1.0) < 1e-6,
		"valeur %.12f" % s.x)

	# ╔═ S2. L'ASSÈCHEMENT — et pourquoi le ressort de S1 ne sait PAS le tester ══════════════════╗
	# ║ L'assèchement est l'ADDITION vis-à-vis de `mathx.js` : sous epsilon, valeur ET vélocité   ║
	# ║ collent NET, ce qui rend une frame de repos bit-stable donc capturable.                   ║
	# ║                                                                                           ║
	# ║ ⚠️ La passe de sabotage a montré que le tester sur le ressort RAIDE de S1 ne prouve rien :║
	# ║ à 12 Hz, le dénominateur implicite vaut ~5,1, la vélocité est donc divisée par 5 à chaque ║
	# ║ pas et tombe dans les DÉNORMAUX puis à zéro exact toute seule en ~450 pas. Le ressort     ║
	# ║ arrive au repos exact SANS assèchement — le contrôle restait vert sur le code saboté.     ║
	# ║ On prend donc un ressort SOUPLE (2 Hz) sur 2 secondes : le dénominateur vaut ~1,46, la    ║
	# ║ queue vaut encore ~1e-20 — minuscule, mais NON NULLE. Seul l'assèchement la tue.          ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var souple := Mathx.MathxSpring.new(2.0, 1.0, 0.0)
	for i in 120:
		souple.step(1.0 / 60.0, 1.0)
	var frozen := souple.x
	for i in 60:
		souple.step(1.0 / 60.0, 1.0)
	_ok("S2 assechement : un ressort SOUPLE atteint le repos EXACT et n'y bouge plus d'un bit",
		souple.at_rest() and souple.x == frozen and souple.x == 1.0,
		"at_rest=%s · valeur %.17f" % [str(souple.at_rest()), souple.x])

	# S3. STABILITE A GRAND PAS — c'est la propriete pour laquelle la forme IMPLICITE a ete
	# choisie plutot que le sous-echantillonnage de `trench_springs.gd`. Un ressort tres raide
	# integre en UN pas de 100 ms ne doit pas diverger.
	var stiff := Mathx.MathxSpring.new(40.0, 0.6, 0.0)
	var diverged := false
	for i in 40:
		stiff.step(0.1, 1.0)
		if absf(stiff.x) > 10.0 or is_nan(stiff.x):
			diverged = true
	_ok("S3 forme implicite : stable meme a dt=100 ms sur un ressort a 40 Hz",
		not diverged, "valeur finale %.6f" % stiff.x)

	# S4. `kick()` injecte de la VELOCITE (le chemin du recul), pas un deplacement.
	var k := Mathx.MathxSpring.new(10.0, 0.5, 0.0)
	k.kick(5.0)
	var moved := k.step(1.0 / 120.0)
	_ok("S4 kick() -> la valeur part dans le sens du coup", moved > 0.0,
		"apres 1 pas : %.6f" % moved)

	# S5. Spring3 : les trois axes, le repos, et `write_to`.
	var s3 := Mathx.MathxSpring3.new(14.0, 1.0)
	s3.kick(1.0, -2.0, 0.5)
	for i in 900:
		s3.step(1.0 / 120.0, 0.0, 0.0, 0.0)
	var v3 := s3.write_to(1.0)
	_ok("S5 MathxSpring3 revient a zero sur les trois axes et s'y colle",
		s3.at_rest() and v3 == Vector3.ZERO, "write_to = %s" % str(v3))

	# S6. PONT ENTRE LES DEUX MODULES — le controle qui vaut la peine : `damp(rate)` d'ici et
	# `approach(tau)` de `trench_springs.gd` sont la MEME courbe, avec `rate == 1/tau`. Si un jour
	# quelqu'un « harmonise » les deux parametrages a l'envers, c'est ici que ca rougit.
	var by_rate: float = Mathx.damp(1.0, 0.0, 1.0 / 0.3, 0.3)
	var by_tau: float = Springs.approach(1.0, 0.0, 0.3, 0.3)
	_ok("S6 damp(rate) == approach(1/rate) — les deux parametrages disent la meme chose",
		absf(by_rate - by_tau) < 1e-12,
		"damp %.15f · approach %.15f (attendu 1/e)" % [by_rate, by_tau])

	# S7. Helpers scalaires.
	var sm0: float = Mathx.smootherstep(0.0, 1.0, 0.0)
	var sm1: float = Mathx.smootherstep(0.0, 1.0, 1.0)
	var smh: float = Mathx.smootherstep(0.0, 1.0, 0.5)
	# ⚠️ La dérivée SECONDE s'annule aux bouts : c'est CE qui distingue le 5ᵉ ordre du `smoothstep`
	# natif de Godot (3ᵉ ordre). On la mesure par différences finies près de 0.
	#
	# ⚠️ PREMIER SEUIL POSÉ ICI : « |d2| < 1e-3 ». Il rougissait sur une fonction JUSTE, et la leçon
	# vaut d'être écrite : une différence finie en h ne mesure pas f''(0), elle mesure f''(~h). Pour
	# `smootherstep`, f''(t) = 120t³ − 180t² + 60t, donc f''(h) ≈ 60h = 0,06 à h = 1e-3 — pas zéro.
	# Exiger 1e-3 revenait à exiger que la dérivée seconde soit nulle AILLEURS qu'au bord.
	#
	# Le seuil juste se lit par COMPARAISON, pas dans l'absolu : le `smoothstep` natif (3ᵉ ordre) a
	# f''(0) = 6 tout court. On exige donc les deux à la fois — la nôtre sous 0,5 ET la native
	# au-dessus de 5. Le contrôle devient DISCRIMINANT : il distingue vraiment les deux ordres, au
	# lieu de constater qu'un nombre est petit.
	var h := 1e-3
	var d2: float = (Mathx.smootherstep(0.0, 1.0, 2.0 * h)
		- 2.0 * Mathx.smootherstep(0.0, 1.0, h) + Mathx.smootherstep(0.0, 1.0, 0.0)) / (h * h)
	var d2_natif: float = (smoothstep(0.0, 1.0, 2.0 * h)
		- 2.0 * smoothstep(0.0, 1.0, h) + smoothstep(0.0, 1.0, 0.0)) / (h * h)
	_ok("S7 smootherstep : 0->0, 1->1, 0.5->0.5, et derivee seconde ~nulle au bord (vs 6 pour le natif)",
		sm0 == 0.0 and sm1 == 1.0 and absf(smh - 0.5) < 1e-12
			and absf(d2) < 0.5 and absf(d2_natif) > 5.0,
		"d2(0+) : smootherstep %.6f · smoothstep natif de Godot %.6f" % [d2, d2_natif])
	_ok("S8 ease_out_back depasse puis revient a 1",
		Mathx.ease_out_back(1.0) == 1.0 and Mathx.ease_out_back(0.72) > 1.0,
		"f(0.72) = %.6f" % Mathx.ease_out_back(0.72))
	_ok("S9 wrap_pi replie dans (-PI, PI]",
		absf(Mathx.wrap_pi(TAU + 0.3) - 0.3) < 1e-12
			and absf(Mathx.wrap_pi(PI + 0.1) - (-PI + 0.1)) < 1e-12)


# =================================================================================================
# P. Primitives : non-vides, budget, determinisme
# =================================================================================================
func _probe_primitives() -> void:
	var made := {
		"box(seg=1)": Meshgen.box(0.03, 0.02, 0.05, 0.0012, 1),
		"box(seg=3)": Meshgen.box(0.03, 0.02, 0.05, 0.0012, 3),
		"blob": Meshgen.blob(0.03, 0.04, 0.06),
		"lathe_z": Meshgen.lathe_z([Vector2(-0.02, 0.004), Vector2(0.0, 0.006),
			Vector2(0.02, 0.004)], 20),
		"tube_z": Meshgen.tube_z(0.009, 0.0045, 0.12, 24),
		"rod_z": Meshgen.rod_z(0.005, 0.004, 0.05, 20),
		"dome": Meshgen.dome(0.004, 16, 0.6),
		"extrude": Meshgen.extrude(Meshgen.round_rect(0.03, 0.02, 0.004, 3), 0.006),
		"ring": Meshgen.ring(0.006, 0.0012, 20, 8),
		"screw": Meshgen.screw(0.0022, 0.0011, 0.0012, 0.004),
		"knurl_band": Meshgen.knurl_band(0.008, 0.006, 20, 0.0004, 3),
		"serrations": Meshgen.serrations(0.02, 0.008, 0.03, 8),
		"picatinny": Meshgen.picatinny(0.09),
		"mlok_slot": Meshgen.mlok_slot(),
	}
	var all_non_empty := true
	var budget := 0
	var lines := []
	for k in made:
		var g = made[k]
		if g == null or g.is_empty():
			all_non_empty = false
			lines.append("%s=VIDE" % k)
			continue
		budget += g.tri_count()
		lines.append("%s=%d" % [k, g.tri_count()])
	_ok("P1 chaque primitive produit un maillage NON VIDE", all_non_empty)
	_info("P2 budget triangles par primitive", " · ".join(lines))
	_info("P3 total du banc", "%d triangles" % budget)

	# P4. DETERMINISME (regle n°4 du cahier §4) : deux generations, tableaux identiques. Sans ca,
	# deux captures du meme plan different et l'imagediff du §8.151 lot 0 ne prouve plus rien.
	var det := true
	var det_detail := ""
	for k in made:
		var g1 = made[k]
		var g2 = _rebuild(k)
		if g2 == null:
			continue
		if g1.positions != g2.positions or g1.normals != g2.normals \
				or g1.indices != g2.indices or g1.uvs != g2.uvs:
			det = false
			det_detail = "premiere divergence : " + k
			break
	_ok("P4 determinisme : deux generations rendent des tableaux IDENTIQUES", det, det_detail)


func _rebuild(key: String):
	match key:
		"box(seg=1)": return Meshgen.box(0.03, 0.02, 0.05, 0.0012, 1)
		"box(seg=3)": return Meshgen.box(0.03, 0.02, 0.05, 0.0012, 3)
		"blob": return Meshgen.blob(0.03, 0.04, 0.06)
		"lathe_z": return Meshgen.lathe_z([Vector2(-0.02, 0.004), Vector2(0.0, 0.006),
			Vector2(0.02, 0.004)], 20)
		"tube_z": return Meshgen.tube_z(0.009, 0.0045, 0.12, 24)
		"rod_z": return Meshgen.rod_z(0.005, 0.004, 0.05, 20)
		"dome": return Meshgen.dome(0.004, 16, 0.6)
		"extrude": return Meshgen.extrude(Meshgen.round_rect(0.03, 0.02, 0.004, 3), 0.006)
		"ring": return Meshgen.ring(0.006, 0.0012, 20, 8)
		"screw": return Meshgen.screw(0.0022, 0.0011, 0.0012, 0.004)
		"knurl_band": return Meshgen.knurl_band(0.008, 0.006, 20, 0.0004, 3)
		"serrations": return Meshgen.serrations(0.02, 0.008, 0.03, 8)
		"picatinny": return Meshgen.picatinny(0.09)
		"mlok_slot": return Meshgen.mlok_slot()
	return null


# =================================================================================================
# D1 / D2. TOPOLOGIE — le controle qui ne peut PAS etre satisfait par construction
# =================================================================================================
func _probe_topology() -> void:
	# La boite SANS chanfrein : volume EXACT connu a la main, aucune approximation polygonale.
	var pb := Meshgen.box(0.03, 0.02, 0.05, 0.0, 1)
	# ⚠️ TOLÉRANCE 1e-5, PAS 1e-9 : `PackedVector3Array` stocke des **float 32 bits**. 0,03 · 0,02
	# et 0,05 ne sont pas représentables exactement, et le volume hérite d'environ 1e-7 d'erreur
	# RELATIVE. Exiger 1e-9 faisait rougir une géométrie parfaitement juste — un contrôle plus
	# serré que la précision du support ne mesure que le support.
	_check_solid("D2a boite sans chanfrein", pb, 0.03 * 0.02 * 0.05, 1e-5)

	# La boite CHANFREINEE : fermee, orientee, et un peu plus petite que la boite pleine (le
	# chanfrein enleve de la matiere aux 12 aretes et aux 8 coins).
	var bx := Meshgen.box(0.03, 0.02, 0.05, 0.002, 4)
	var v_full := 0.03 * 0.02 * 0.05
	var v_bx := bx.signed_volume()
	_check_manifold("D1b boite chanfreinee (seg=4)", bx)
	_ok("D2b boite chanfreinee : volume positif et INFERIEUR a la boite pleine (matiere enlevee)",
		v_bx > 0.0 and v_bx < v_full and v_bx > v_full * 0.95,
		"volume %.3f mm3 vs boite pleine %.3f mm3 (%.2f %%)"
			% [v_bx * 1e9, v_full * 1e9, 100.0 * v_bx / v_full])

	# Le TORE : volume analytique 2·PI²·R·t².
	# ⚠️ Segmentation FINE volontairement : un tore facetté SOUS-estime toujours le volume du tore
	# lisse (polygone inscrit). À 40x20 le déficit est de ~2 %, ce qui noie le signal qu'on veut
	# mesurer. À 64x32 il tombe sous 0,3 %, et une tolérance de 1 % devient un vrai contrôle.
	var tor := Meshgen.ring(0.006, 0.0012, 64, 32)
	_check_solid("D2c tore", tor, 2.0 * PI * PI * 0.006 * 0.0012 * 0.0012, 0.01)

	# L'EXTRUSION : plaque a coins arrondis, biseautee sur les deux faces.
	var plate := Meshgen.extrude(Meshgen.round_rect(0.03, 0.02, 0.004, 4), 0.006,
		{"bevel": 0.0008})
	_check_manifold("D1d extrusion biseautee", plate)
	var area := absf(Meshgen.polygon_area(_poly(Meshgen.round_rect(0.03, 0.02, 0.004, 4))))
	var v_plate := plate.signed_volume()
	_ok("D2d extrusion : volume positif, un peu sous aire x profondeur (les biseaux rognent)",
		v_plate > 0.0 and v_plate < area * 0.006 and v_plate > area * 0.006 * 0.90,
		"volume %.3f mm3 vs aire x profondeur %.3f mm3" % [v_plate * 1e9, area * 0.006 * 1e9])

	# ⚠️ NON FERMES PAR NATURE, et c'est le comportement de la reference : un tour laisse ses deux
	# bouts de profil ouverts. On le CONSTATE ici pour que personne ne « corrige » un faux defaut.
	var tube := Meshgen.tube_z(0.009, 0.0045, 0.12, 24)
	var rep := _manifold_report(tube)
	_info("D1e tube_z : ouvert par construction (les bouts du profil)",
		"aretes de bord %d · aretes non-manifold %d" % [rep.boundary, rep.nonmanifold])


func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.push_back(Vector2(float(p[0]), float(p[1])))
	return out


# Un solide doit etre : ferme, oriente, et de volume proche de la valeur analytique.
func _check_solid(label: String, g, expected: float, tol_rel: float) -> void:
	_check_manifold(label.replace("D2", "D1"), g)
	var v: float = g.signed_volume()
	var rel: float = absf(v - expected) / maxf(absf(expected), 1e-18)
	# ⚠️ Les volumes sont affichés en **mm³** (×1e9) : GDScript ne supporte PAS `%e` dans son
	# formatage de chaînes (« unsupported format character »), et un `%f` sur 3e-5 n'affiche rien
	# de lisible. Le mm³ est en plus l'unité naturelle des pièces d'arme.
	_ok("%s : volume signe POSITIF et conforme a l'analytique" % label,
		v > 0.0 and rel <= tol_rel,
		"mesure %.4f mm3 · attendu %.4f mm3 · ecart %.4f %%"
			% [v * 1e9, expected * 1e9, rel * 100.0])


func _check_manifold(label: String, g) -> void:
	var rep := _manifold_report(g)
	_ok("%s : etanche (chaque arete parcourue une fois dans chaque sens)" % label,
		rep.boundary == 0 and rep.nonmanifold == 0,
		"aretes de bord %d · aretes non-manifold %d · triangles %d"
			% [rep.boundary, rep.nonmanifold, g.tri_count()])


# Compte les aretes DIRIGEES par POSITION (pas par index : la soudure duplique volontairement les
# sommets d'arete franche). Sur un solide ferme et coherent, chaque couple (u,v) apparait une fois
# et son oppose (v,u) une fois.
func _manifold_report(g) -> Dictionary:
	var ids := {}
	var vid := PackedInt32Array()
	vid.resize(g.positions.size())
	for i in g.positions.size():
		var p: Vector3 = g.positions[i]
		var key := "%d|%d|%d" % [roundi(p.x / POS_QUANTUM), roundi(p.y / POS_QUANTUM),
			roundi(p.z / POS_QUANTUM)]
		if not ids.has(key):
			ids[key] = ids.size()
		vid[i] = ids[key]
	var n_ids := ids.size()
	# Clef d'arete ENTIERE (u * n + v) plutot qu'une chaine : `for key in dir` rend un Variant, dont
	# `.split()` n'a pas de type inferable — et surtout, on parcourt ici des dizaines de milliers
	# d'aretes, ou les operations sur chaines coutent cher pour rien.
	var dir := {}
	var i := 0
	while i < g.indices.size():
		var t := [vid[g.indices[i]], vid[g.indices[i + 1]], vid[g.indices[i + 2]]]
		for k in 3:
			var u: int = t[k]
			var v: int = t[(k + 1) % 3]
			var key := u * n_ids + v
			dir[key] = int(dir.get(key, 0)) + 1
		i += 3
	var boundary := 0
	var nonmanifold := 0
	for key in dir.keys():
		var ki := int(key)
		if int(dir[key]) > 1:
			nonmanifold += 1
		var u := ki / n_ids
		var v := ki % n_ids
		if not dir.has(v * n_ids + u):
			boundary += 1
	return {"boundary": boundary, "nonmanifold": nonmanifold}


# =================================================================================================
# D3. EXTRUSION AJOUREE — le trou est-il vraiment perce ?
# =================================================================================================
func _probe_holes() -> void:
	# Les deux contours du banc : une plaque 30 x 20 mm percee d'un trou 16 x 8 mm.
	var outer := _poly(Meshgen.round_rect(0.03, 0.02, 0.004, 3))
	var hole := _poly(Meshgen.round_rect(0.016, 0.008, 0.002, 3))
	# ── D3-0. LA ROUTE REJETÉE, ET LE CHIFFRE QUI L'A FAIT REJETER ─────────────────────────────
	# `trench_meshgen` NE trianguse PAS les faces percées par un « trou de serrure » donné à
	# `Geometry2D.triangulate_polygon`. Ce contrôle garde la MESURE qui a tranché, parce qu'elle est
	# contre-intuitive et qu'un futur relecteur voudra « simplifier » en y revenant :
	#
	#   le découpeur d'oreilles rend le BON NOMBRE de triangles (n − 2, tout a l'air normal), mais
	#   la somme de leurs aires DÉPASSE l'aire réelle de ~6 % — des triangles se chevauchent.
	#
	# ⚠️ C'est le contre-exemple le plus net de la session : le premier contrôle posé ici ne
	# demandait qu'un COMPTE de triangles, et il était VERT sur une triangulation fausse. Compter
	# n'est pas mesurer.
	var keyhole := _keyhole(outer, hole, 0.0)
	var tri_kh := Geometry2D.triangulate_polygon(keyhole)
	var a_kh := 0.0
	var ki := 0
	while ki < tri_kh.size():
		a_kh += absf((keyhole[tri_kh[ki + 1]] - keyhole[tri_kh[ki]])
			.cross(keyhole[tri_kh[ki + 2]] - keyhole[tri_kh[ki]])) * 0.5
		ki += 3
	var a_ring := absf(Meshgen.polygon_area(outer)) - absf(Meshgen.polygon_area(hole))
	_info("D3-0 route REJETEE (trou de serrure + triangulate_polygon)",
		"%d triangles rendus (compte correct) MAIS aire %.2f mm2 pour %.2f mm2 reels = %+.1f %% "
			% [tri_kh.size() / 3, a_kh * 1e6, a_ring * 1e6,
				100.0 * (a_kh - a_ring) / a_ring]
			+ "de chevauchement -> d'ou la couture d'anneau du module")

	# D3-1. L'aire du capot vaut bien extERIEUR moins TROU. C'est LE controle qui attrape un trou
	# silencieusement ignore : la piece se genere, se boote, s'affiche — et est pleine.
	var depth := 0.006
	var g := Meshgen.extrude(Meshgen.round_rect(0.03, 0.02, 0.004, 3), depth,
		{"bevel": 0.0006, "holes": [Meshgen.round_rect(0.016, 0.008, 0.002, 3)]})
	_ok("D3-1 l'extrusion ajouree n'est pas vide", g != null and not g.is_empty(),
		"%d triangles" % (0 if g == null else g.tri_count()))
	var a_out := absf(Meshgen.polygon_area(outer))
	var a_hole := absf(Meshgen.polygon_area(hole))
	var v := g.signed_volume()
	var v_expected := (a_out - a_hole) * depth
	var v_full := a_out * depth
	_ok("D3-2 volume ~ (aire exterieure - aire du trou) x profondeur, PAS la piece pleine",
		v > 0.0 and absf(v - v_expected) < v_expected * 0.12 and v < v_full * 0.90,
		"mesure %.3f mm3 · ajoure attendu %.3f mm3 · plein si le trou etait rate %.3f mm3"
			% [v * 1e9, v_expected * 1e9, v_full * 1e9])
	_check_manifold("D1f extrusion ajouree", g)


# Reconstruit un « trou de serrure » pour la MESURE D3-0. ⚠️ Ce n'est plus la technique du module —
# il coud désormais les deux boucles. Ce helper ne survit ici que pour continuer à mesurer la route
# rejetée, et faire mentir quiconque la reproposerait.
func _keyhole(outer: PackedVector2Array, hole_in: PackedVector2Array,
		slit: float) -> PackedVector2Array:
	var hole := hole_in.duplicate()
	hole.reverse()
	var bi := 0
	var bj := 0
	var bd := INF
	for i in outer.size():
		for j in hole.size():
			var d := outer[i].distance_squared_to(hole[j])
			if d < bd:
				bd = d
				bi = i
				bj = j
	var dir := hole[bj] - outer[bi]
	var off := Vector2(-dir.y, dir.x).normalized() * slit
	var out := PackedVector2Array()
	for i in bi + 1:
		out.push_back(outer[i])
	for k in hole.size() + 1:
		out.push_back(hole[(bj + k) % hole.size()] + off)
	out.push_back(outer[bi] + off)
	# ⚠️ `bi + 1`, PAS `bi` : `outer[bi]` vient d'être poussé à la ligne précédente pour refermer
	# la fente. Repartir de `bi` le pousserait UNE SECONDE FOIS D'AFFILÉE — donc une arête de
	# longueur nulle dans le polygone, sur laquelle le découpeur d'oreilles fabrique des triangles
	# dégénérés et des triangles qui se CHEVAUCHENT. Le défaut ne se voit pas à l'écran : il se
	# mesure (D1f a compté 40 arêtes de bord et 40 arêtes non-manifold sur une plaque percée).
	# Un contour fermé correct contient `n_ext + n_trou + 2` sommets, pas + 3.
	for i in range(bi + 1, outer.size()):
		out.push_back(outer[i])
	return out


# =================================================================================================
# D4. RAIL PICATINNY — le chanfrein de crete (la lecon mesuree de la reference)
# =================================================================================================
func _probe_picatinny() -> void:
	var length := 0.09
	var width := 0.0212
	var ch := 0.0015
	var pitch := 0.01055
	var slot := 0.00535
	var g := Meshgen.picatinny(length)
	var teeth: int = maxi(1, floori((length + slot) / pitch))

	# La largeur maximale de l'arme, tout en haut du rail, DOIT etre `width - 2*ch` : c'est la
	# correction qui a supprime le « peigne a 1,35 diaphragme ». Si quelqu'un remet un meplat
	# pleine largeur, ce controle rougit — et c'est exactement le sabotage n°3.
	var y_max := -INF
	var x_max_global := 0.0
	for p in g.positions:
		y_max = maxf(y_max, p.y)
		x_max_global = maxf(x_max_global, absf(p.x))
	var x_at_top := 0.0
	for p in g.positions:
		if p.y > y_max - 1e-6:
			x_at_top = maxf(x_at_top, absf(p.x))
	_ok("D4-1 au SOMMET du rail, la demi-largeur vaut (width/2 - chanfrein), pas width/2",
		absf(x_at_top - (width * 0.5 - ch)) < 2e-4,
		"mesure %.5f m · attendu %.5f m · pleine largeur (le defaut) %.5f m"
			% [x_at_top, width * 0.5 - ch, width * 0.5])
	_ok("D4-2 la pleine largeur existe bien plus bas (les flancs ne sont pas rabotes)",
		absf(x_max_global - width * 0.5) < 2e-4,
		"demi-largeur max %.5f m" % x_max_global)

	# ── Les encoches sont-elles de VRAIS vides dans la silhouette ? ─────────────────────────────
	# ⚠️ PREMIÈRE MÉTRIQUE, FAUSSE, gardée en mémoire ici parce qu'elle est instructive : compter
	# les « trous » entre deux cotes Z consécutives de la crête. Elle a rendu **17 intervalles pour
	# 9 dents**. Ce n'était pas le rail qui était faux, c'était la mesure : à l'intérieur d'UNE
	# dent, la crête n'est présente qu'entre ±(dent/2 − biseau), et le vide central entre les deux
	# arêtes de biseau (4,7 mm) ressemblait à une encoche (5,35 mm). La métrique comptait donc une
	# fausse encoche par dent, plus les 8 vraies : 9 + 8 = 17.
	#
	# MÉTRIQUE JUSTE : on ne regarde plus des POINTS mais l'OCCUPATION. Chaque triangle dont les
	# trois sommets sont sur la crête couvre un intervalle en Z ; on fait l'union de ces intervalles.
	# Un rail correct occupe autant de segments que de dents, et laisse au total plus de la moitié
	# de sa longueur VIDE en haut. Un rail dont les encoches auraient disparu occuperait tout.
	var spans := []
	var i := 0
	while i < g.indices.size():
		var a := g.positions[g.indices[i]]
		var b := g.positions[g.indices[i + 1]]
		var c := g.positions[g.indices[i + 2]]
		i += 3
		if a.y > y_max - 1e-6 and b.y > y_max - 1e-6 and c.y > y_max - 1e-6:
			spans.append(Vector2(minf(a.z, minf(b.z, c.z)), maxf(a.z, maxf(b.z, c.z))))
	spans.sort_custom(func(u, v): return u.x < v.x)
	var merged := []
	for sp in spans:
		if merged.is_empty() or sp.x > merged[-1].y + 1e-6:
			merged.append(sp)
		else:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, sp.y))
	var covered := 0.0
	for sp in merged:
		covered += sp.y - sp.x
	_ok("D4-3 la crete est decoupee en %d segments (un par dent) et laisse le rail majoritairement vide"
			% teeth,
		merged.size() == teeth and covered < length * 0.6,
		"segments mesures %d · crete occupee %.2f mm sur %.2f mm de rail (%.1f %%)"
			% [merged.size(), covered * 1000.0, length * 1000.0, 100.0 * covered / length])


# =================================================================================================
# A. `Assembly`
# =================================================================================================
func _probe_assembly() -> void:
	var asm := Meshgen.Assembly.new("banc")
	var cube := Meshgen.box(0.01, 0.01, 0.01, 0.0, 1)
	asm.add(cube, "acier", {"x": 0.02})
	asm.add(cube, "acier", {"x": -0.02})
	asm.add(cube, "polymere", {"y": 0.03})
	asm.node("muzzle", 0.0, 0.0, -0.3)
	var tris_before := asm.total_tris()
	var built := asm.build()
	_ok("A1 les pieces sont rangees PAR MATERIAU (2 seaux ici)", built.size() == 2,
		"seaux : " + str(built.keys()))
	_ok("A2 les ancres nommees survivent au build()",
		asm.get_node("muzzle").get("pos") == Vector3(0, 0, -0.3))
	_ok("A3 total_tris() compte avant fusion", tris_before == 3 * cube.tri_count(),
		"%d triangles pour 3 cubes de %d" % [tris_before, cube.tri_count()])

	# A4. LE MIROIR RETOURNE BIEN LES FACES. Une piece mise en miroir par `sx = -1` sans inversion
	# du sens de parcours serait retournee — invisible en `CULL_DISABLED`, trou noir sinon. Le
	# volume signe du seau reste POSITIF si le retournement a eu lieu.
	var asm2 := Meshgen.Assembly.new("miroir")
	asm2.add_mirrored(cube, "acier", {"x": 0.02})
	var built2 := asm2.build()
	var v2: float = built2["acier"].signed_volume()
	_ok("A4 add_mirrored : la copie miroir a ses faces RETOURNEES (volume total positif)",
		v2 > 0.0, "volume des deux cubes %.4f mm3 (attendu ~%.4f mm3)" % [v2 * 1e9, 2.0 * 1e-6 * 1e9])
