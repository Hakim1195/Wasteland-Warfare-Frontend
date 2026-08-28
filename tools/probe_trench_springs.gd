extends Node

# =================================================================================================
# SONDE §8.151 LOT B — LES RESSORTS DU FEEL : `trench_springs.gd` tient-il ses promesses AVANT
# d'être branché au viewmodel (vague 2, §4.2) ?
#
# ╔═ CE QU'ELLE PROUVE ═══════════════════════════════════════════════════════════════════════════╗
# ║ 1. CONVERGENCE : un ressort rejoint SA CIBLE et s'y COLLE exactement (==, pas « à peu près »).║
# ║ 2. DT HACHÉS : une frame perdue de 33 ms et 33 pas de 1 ms produisent le MÊME mouvement       ║
# ║    visible — et, après 0,5 s, le MÊME repos bit à bit. Un ressort raide ne diverge pas.       ║
# ║ 3. BIT-STABILITÉ : après collage, N pas de plus ne changent PLUS UN BIT — la propriété que    ║
# ║    les captures du LOT E figeront au pixel.                                                   ║
# ║ 4. FORME DU RECUL : monte d'un coup (kick en DÉPLACEMENT), repasse sous 50 % en < 0,25 s,     ║
# ║    garde une queue résiduelle à 0,3 s (l'étage lent), se pose, s'assèche à ZÉRO exact.        ║
# ║ 5. HASH DÉTERMINISTE : mêmes entrées → mêmes sorties, et les MÊMES nombres que la réplique    ║
# ║    hors-moteur — si le portage 32 bits déborde quelque part, ces références rougissent.       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Les valeurs « réplique : … » citées en détail sortent d'une réplique float64 ligne à ligne du
# module (mêmes opérations, mêmes masques 32 bits, hors moteur). Ce sont des références
# INTER-IMPLÉMENTATIONS figées ici à dessein — pas des recopies de constantes du jeu.
# Le préchargement du module suffit déjà à prouver qu'il compile : si `trench_springs.gd` ne
# s'analyse pas, cette scène ne boote pas du tout.
#
# ⚠️ LANCEMENT — le headless SUFFIT (maths pures, aucun rendu, aucun SubViewport) :
#   & <godot_console> --headless --path frontend res://tools/probe_trench_springs.tscn
# =================================================================================================

const Springs := preload("res://scripts/game/trench_springs.gd")

# Le banc : les cadences de frames qu'on fait subir aux ressorts. 60 Hz nominal, 33 ms = la frame
# perdue, 1 ms = quasi-continu, 144 Hz = écran rapide.
const DT_NOMINAL := 1.0 / 60.0
const DT_HITCH := 0.033
const DT_FIN := 0.001
const DT_144 := 1.0 / 144.0

var _fails: Array = []


func _ok(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== SONDE RESSORTS DU FEEL (§8.151 LOT B — trench_springs.gd) ===")
	print()
	print("--- 1. CONVERGENCE : le ressort rejoint sa cible et s'y COLLE ---")
	_probe_convergence()
	print()
	print("--- 2. DT HACHÉS : même mouvement, quelle que soit la cadence de frames ---")
	_probe_dt_haches()
	print()
	print("--- 3. BIT-STABILITÉ AU REPOS : plus un bit ne bouge (la promesse du LOT E) ---")
	_probe_bit_stabilite()
	print()
	print("--- 4. FORME DU RECUL : monte d'un coup, revient sec, se pose, s'assèche ---")
	_probe_recoil_forme()
	print()
	print("--- 5. HASH DÉTERMINISTE : le bruit du shake, rejouable au bit près ---")
	_probe_hash_noise()
	print()
	print("--- 6. HELPERS SCALAIRES : approach / move_toward_rate / angle_delta ---")
	_probe_helpers()
	print("\n%s" % ("TOUT VERT" if _fails.is_empty()
		else "ECHEC : " + str(_fails.size()) + " controle(s) rouge(s)"))
	get_tree().quit(0 if _fails.is_empty() else 1)


# =================================================================================================
# 1. CONVERGENCE — et le collage EXACT qui la termine
# =================================================================================================
func _probe_convergence() -> void:
	var ressort := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	ressort.target = 1.0
	for _i in 120:
		ressort.step(DT_NOMINAL)
	_ok("2 s a 60 Hz -> collage EXACT sur 1.0 (valeur ET velocite)",
		ressort.value == 1.0 and ressort.velocity == 0.0 and ressort.at_rest(),
		"valeur %.17f (replique : collage au pas 26, t=0.433 s)" % ressort.value)
	# Re-ciblage : le MÊME ressort, une nouvelle cible — il doit coller aussi net.
	ressort.target = 0.25
	for _i in 120:
		ressort.step(DT_NOMINAL)
	_ok("re-ciblage 0.25 -> collage EXACT a nouveau",
		ressort.value == 0.25 and ressort.velocity == 0.0,
		"valeur %.17f" % ressort.value)
	# dt <= 0 : un pas nul ou negatif ne fait RIEN (garde de la reference).
	var avant: float = ressort.value
	ressort.step(0.0)
	ressort.step(-0.016)
	_ok("dt <= 0 : aucun effet", ressort.value == avant and ressort.velocity == 0.0, "")
	# L'API « physique » de la reference, verifiee en passant : impulse() injecte de la velocite,
	# set_value() deplace sans toucher a la velocite, reset() ramene tout.
	var brut := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	brut.impulse(2.0)
	brut.step(DT_FIN)
	_ok("impulse : la velocite injectee met la valeur en mouvement",
		brut.value > 0.0 and brut.velocity > 0.0, "valeur %.9f apres 1 ms" % brut.value)
	brut.set_value(0.5)
	_ok("set_value : deplacement instantane, velocite conservee",
		brut.value == 0.5 and brut.velocity != 0.0, "")
	brut.reset(0.0)
	_ok("reset : valeur posee, velocite nulle", brut.value == 0.0 and brut.velocity == 0.0, "")


# =================================================================================================
# 2. DT HACHÉS — la frame perdue et le pas fin racontent le même mouvement
# =================================================================================================
func _probe_dt_haches() -> void:
	# Une frame perdue (33 ms, UN appel) contre la même durée en 33 pas fins.
	var gros := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	gros.target = 1.0
	gros.step(DT_HITCH)
	var fin := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	fin.target = 1.0
	for _i in 33:
		fin.step(DT_FIN)
	var ecart: float = absf(gros.value - fin.value)
	_ok("1 pas de 33 ms vs 33 pas de 1 ms : meme mouvement visible (ecart < 0.05)",
		ecart < 0.05,
		"33 ms : %.9f · 33x1 ms : %.9f · ecart %.5f (replique : 0.03037, en pleine montee)"
		% [gros.value, fin.value, ecart])
	# Conformité à la réplique float64 : mêmes opérations, mêmes nombres (aucun exp() sur ce
	# chemin — l'écart attendu est nul à l'arrondi près).
	_ok("le pas de 33 ms tombe sur le nombre de la replique",
		absf(gros.value - 0.645082158120) < 1.0e-9, "valeur %.12f" % gros.value)
	_ok("les 33 pas de 1 ms aussi",
		absf(fin.value - 0.614712452623) < 1.0e-9, "valeur %.12f" % fin.value)
	# Après 0,5 s, les DEUX cadences ont collé : repos identique BIT À BIT — le découpage des
	# frames ne laisse AUCUNE trace dans l'état final. C'est ce qui autorise les captures.
	var lent := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	lent.target = 1.0
	for _i in 15:
		lent.step(1.0 / 30.0)
	var rapide := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	rapide.target = 1.0
	for _i in 500:
		rapide.step(DT_FIN)
	_ok("apres 0.5 s, deux cadences differentes -> le MEME repos, bit a bit",
		lent.value == rapide.value and lent.value == 1.0,
		"1/30 : %.17f · 1 ms : %.17f" % [lent.value, rapide.value])
	# Le ressort RAIDE (30 Hz) : la frame perdue ne le fait pas diverger. Sans sous-pas, le même
	# Euler ferait ×38,7 en UN pas (mesuré sur la réplique) — c'est LA raison du sous-échantillon.
	var raide := Springs.TrenchSpring.new(30.0, 0.3, 0.0)
	raide.target = 1.0
	raide.step(DT_HITCH)
	_ok("ressort raide (30 Hz, zeta 0.3) + frame perdue : borne, pas d'explosion",
		is_finite(raide.value) and raide.value > 0.0 and raide.value < 1.5,
		"valeur %.9f (replique : 0.893146 ; Euler naif sans sous-pas : 38.7)" % raide.value)


# =================================================================================================
# 3. BIT-STABILITÉ AU REPOS — après le collage, plus RIEN ne bouge, a aucun dt
# =================================================================================================
func _probe_bit_stabilite() -> void:
	var ressort := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	ressort.target = 1.0
	for _i in 240:
		ressort.step(DT_NOMINAL)
	var fige: float = ressort.value
	_ok("apres 4 s, la valeur EST la cible (pas « proche » : egale)", fige == 1.0,
		"valeur %.17f" % fige)
	var intact := true
	for _i in 30:
		for d in [DT_NOMINAL, DT_HITCH, DT_FIN, DT_144]:
			ressort.step(d)
			if ressort.value != fige or ressort.velocity != 0.0:
				intact = false
	_ok("120 pas de plus, dt varies -> STRICTEMENT inchange (== bit a bit)", intact,
		"valeur %.17f" % ressort.value)
	# Un ressort jamais sollicité (cible = valeur = 0) ne bouge pas non plus : la frame de repos
	# d'un viewmodel qu'on n'a pas touché est deja bit-stable.
	var neutre := Springs.TrenchSpring.new(8.0, 0.7, 0.0)
	for _i in 60:
		neutre.step(DT_NOMINAL)
	_ok("ressort au neutre : 1 s de pas -> zero exact",
		neutre.value == 0.0 and neutre.velocity == 0.0, "")


# =================================================================================================
# 4. FORME DU RECUL — les trois temps du kick, puis le zéro exact
# =================================================================================================
func _probe_recoil_forme() -> void:
	var axe := Springs.TrenchRecoilAxis.new()
	_ok("registre : les defauts du cahier §4.1 (9.5 Hz / zeta 0.52 / tau 0.3 s / part 0.34)",
		axe.spring.freq == 9.5 and axe.spring.damping == 0.52
			and axe.residual_tau == 0.3 and axe.residual_share == 0.34,
		"freq %.2f · zeta %.2f · tau %.2f · part %.2f"
		% [axe.spring.freq, axe.spring.damping, axe.residual_tau, axe.residual_share])
	axe.kick(1.0)
	var saut: float = axe.spring.value + axe.residual
	_ok("kick en DEPLACEMENT : toute l'amplitude est la AVANT le moindre pas",
		absf(saut - 1.0) < 1.0e-12,
		"ressort %.6f + residu %.6f = %.15f" % [axe.spring.value, axe.residual, saut])
	var v1: float = axe.step(DT_FIN)
	_ok("montee instantanee : au moins 97 pour cent de l'amplitude 1 ms apres le kick", v1 > 0.97,
		"valeur %.12f (replique : 0.996517021514)" % v1)

	# La trajectoire, échantillonnée à 240 Hz sur 8 s : retour sec, queue, pose, assèchement.
	axe = Springs.TrenchRecoilAxis.new()
	axe.kick(1.0)
	var dt := 1.0 / 240.0
	var sous_moitie := -1.0
	var v_030 := -1.0
	var v_200 := -1.0
	for i in range(1, 8 * 240 + 1):
		var v: float = axe.step(dt)
		var t: float = float(i) * dt
		if sous_moitie < 0.0 and v < 0.5:
			sous_moitie = t
		if v_030 < 0.0 and t >= 0.3:
			v_030 = v
		if v_200 < 0.0 and t >= 2.0:
			v_200 = v
	_ok("revient sec : sous 50 pour cent en moins de 0.25 s",
		sous_moitie > 0.0 and sous_moitie < 0.25,
		"passage a t=%.4f s (replique : 0.0292)" % sous_moitie)
	_ok("queue residuelle : encore la a 0.3 s (l'etage lent qu'un ressort seul n'a pas)",
		v_030 > 0.06 and v_030 < 0.20,
		"valeur %.9f (replique : 0.125051142 — un ressort seul y serait a ~0.00006)" % v_030)
	_ok("conformite a la replique float64 a t=0.3 s (tolerance 1e-6, exp() compris)",
		absf(v_030 - 0.125051142094) < 1.0e-6, "valeur %.12f" % v_030)
	_ok("se pose : quasi nul a 2 s", absf(v_200) < 0.01,
		"valeur %.9f (replique : 0.000433)" % v_200)
	_ok("asseche : ZERO exact a 8 s (les deux etages colles — le repos du LOT E)",
		axe.value == 0.0 and axe.residual == 0.0 and axe.at_rest(),
		"valeur %.17f · residu %.17f" % [axe.value, axe.residual])
	# Et le repos du recul est bit-stable, comme celui du ressort nu.
	var intact := true
	for _i in 120:
		axe.step(DT_NOMINAL)
		if axe.value != 0.0:
			intact = false
	_ok("repos du recul : 120 pas de plus -> toujours zero exact", intact, "")


# =================================================================================================
# 5. HASH DÉTERMINISTE — mêmes entrées, mêmes sorties, mêmes nombres que la réplique
# =================================================================================================
func _probe_hash_noise() -> void:
	_ok("deterministe : deux appels identiques -> bit-identiques",
		Springs.hash_noise(12.34, 5) == Springs.hash_noise(12.34, 5)
			and Springs.hash_noise(-3.7, 42) == Springs.hash_noise(-3.7, 42), "")
	# Références inter-implémentations (réplique float64, masques 32 bits). Le x=0/graine=0 vaut
	# EXACTEMENT -1.0 : la cellule 0 hachée par la graine 0 reste 0 — connu et assumé.
	var refs := [
		[0.0, 0, -1.0],
		[0.5, 0, -0.073420165805146],
		[1.5, 0, -0.058203226886690],
		[2.25, 7, 0.239931236166740],
		[-3.7, 42, -0.213175653316081],
		[12.34, 5, 0.110807536808863],
	]
	var conforme := true
	var detail := ""
	for r in refs:
		var obtenu: float = Springs.hash_noise(float(r[0]), int(r[1]))
		if absf(obtenu - float(r[2])) > 1.0e-9:
			conforme = false
			detail += "hash(%s, %s) = %.15f attendu %.15f  " \
				% [str(r[0]), str(r[1]), obtenu, float(r[2])]
	_ok("6 valeurs de reference au bit pres (tolerance 1e-9)", conforme,
		detail if detail != "" else "portage 32 bits conforme a la replique")
	_ok("la graine change le bruit",
		Springs.hash_noise(3.7, 0) != Springs.hash_noise(3.7, 1),
		"graine 0 : %.9f · graine 1 : %.9f (replique : -0.456706161 / -0.220679340)"
		% [Springs.hash_noise(3.7, 0), Springs.hash_noise(3.7, 1)])
	# Balayage : borné dans [-1, 1] et PAS constant — 2000 points, x négatifs compris.
	var mini := 10.0
	var maxi := -10.0
	var premier: float = Springs.hash_noise(-25.0, 3)
	var varie := false
	for i in 2000:
		var v: float = Springs.hash_noise(-25.0 + float(i) * 0.025, 3)
		mini = minf(mini, v)
		maxi = maxf(maxi, v)
		if v != premier:
			varie = true
	_ok("balayage de 2000 points : borne dans [-1, 1] et non constant",
		mini >= -1.0 and maxi <= 1.0 and varie,
		"min %.9f · max %.9f (replique : -0.962344892 / 0.968004497)" % [mini, maxi])
	# La couture aux entiers : de part et d'autre de x=2, le fondu rend la MÊME cellule — un
	# décalage d'indice d'une cellule ferait sauter cette valeur d'un coup.
	var gauche: float = Springs.hash_noise(2.0 - 1.0e-6, 3)
	var droite: float = Springs.hash_noise(2.0 + 1.0e-6, 3)
	_ok("continuite a la couture entiere (x=2)", absf(gauche - droite) < 1.0e-4,
		"gauche %.12f · droite %.12f (replique : ecart 1.2e-12)" % [gauche, droite])


# =================================================================================================
# 6. HELPERS SCALAIRES — les trois petites fonctions que la vague 2 consommera
# =================================================================================================
func _probe_helpers() -> void:
	_ok("approach : tau nul -> collage immediat sur la cible",
		Springs.approach(0.7, 0.2, 0.0, 0.016) == 0.2, "")
	var un_tau: float = Springs.approach(1.0, 0.0, 0.3, 0.3)
	_ok("approach : apres UNE constante de temps, il reste 1/e",
		absf(un_tau - 0.367879441171442) < 1.0e-9, "valeur %.15f" % un_tau)
	_ok("move_toward_rate : avance de rate*dt, sans jamais depasser la cible",
		Springs.move_toward_rate(0.0, 1.0, 2.0, 0.25) == 0.5
			and Springs.move_toward_rate(1.0, 0.0, 2.0, 0.25) == 0.5
			and Springs.move_toward_rate(0.0, 1.0, 10.0, 0.25) == 1.0, "")
	var d1: float = Springs.angle_delta(0.1, TAU - 0.1)
	var d2: float = Springs.angle_delta(-0.1, 0.1)
	_ok("angle_delta : toujours le chemin court, signe compris",
		absf(d1 - (-0.2)) < 1.0e-9 and absf(d2 - 0.2) < 1.0e-9,
		"0.1 -> TAU-0.1 : %.12f (attendu -0.2) · -0.1 -> 0.1 : %.12f (attendu 0.2)" % [d1, d2])
