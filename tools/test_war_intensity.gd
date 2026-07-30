extends Node

# TEST §8.122 LOT A (style maison) — `war_intensity`, la jauge de tension UNIQUE.
# Module 100 % PUR (statique) : ce harnais n'instancie AUCUNE scène de jeu.
#   & <godot_console> --headless --path frontend res://tools/test_war_intensity.tscn
#
# Deux volets :
#   1. TABLEAU LISIBLE des snapshots types (début / milieu / héros mourant / PROTOCOLE FINAL) —
#      c'est la « vérification manuelle » demandée : début ≈ 0,05-0,15, fin serrée ≈ 0,7-1,0.
#   2. ASSERTS de non-régression sur la formule, le plancher de PROTOCOLE FINAL, et surtout
#      l'INDÉPENDANCE AU FRAMERATE du lissage (le piège n° 1 d'un lerp naïf).

const WI := preload("res://scripts/game/war_intensity.gd")

# Snapshots types. Chaque ligne : libellé + snapshot + fourchette ATTENDUE [min, max] (contrat de
# recette du prompt — c'est elle qui rougit si quelqu'un retouche une pondération sans réfléchir).
const CASES := [
	{
		"label": "DÉBUT DE PARTIE      ",
		"snap": {"round": 1, "alive_heroes_pv_ratio": 1.0, "my_hero_pv_ratio": 1.0,
			"zone_count": 1, "final_protocol": false},
		"min": 0.05, "max": 0.15,
	},
	{
		"label": "MILIEU DE PARTIE     ",
		"snap": {"round": 4, "alive_heroes_pv_ratio": 0.70, "my_hero_pv_ratio": 0.60,
			"zone_count": 3, "final_protocol": false},
		"min": 0.25, "max": 0.45,
	},
	{
		"label": "MON HÉROS SE MEURT   ",
		"snap": {"round": 5, "alive_heroes_pv_ratio": 0.40, "my_hero_pv_ratio": 0.10,
			"zone_count": 4, "final_protocol": false},
		"min": 0.45, "max": 0.65,
	},
	{
		"label": "PROTOCOLE FINAL      ",
		"snap": {"round": 9, "alive_heroes_pv_ratio": 0.25, "my_hero_pv_ratio": 0.20,
			"zone_count": 8, "final_protocol": true},
		"min": 0.70, "max": 1.00,
	},
]


func _ready() -> void:
	var asserts := 0

	# --- 1) Tableau lisible + fourchettes de recette --------------------------------
	print("")
	print("  SNAPSHOT                BRUTE   LISSÉE(1 s depuis 0)   FOURCHETTE")
	print("  ---------------------------------------------------------------------")
	for c in CASES:
		var raw: float = WI.compute(c["snap"])
		var smoothed: float = WI.smooth(0.0, raw, 1.0)
		print("  %s  %.3f   %.3f                  [%.2f – %.2f]"
			% [c["label"], raw, smoothed, c["min"], c["max"]])
		assert(raw >= float(c["min"]) and raw <= float(c["max"]))
		asserts += 1
	print("")
	print("[OK] 4 snapshots types dans leur fourchette de recette (%d asserts)" % asserts)

	# --- 2) Monotonie : la tension ne peut que MONTER quand la guerre empire ---------
	var prev := -1.0
	for c in CASES:
		var v: float = WI.compute(c["snap"])
		assert(v > prev)
		prev = v
		asserts += 1
	print("[OK] progression STRICTEMENT croissante début → PROTOCOLE FINAL (4 asserts)")

	# --- 3) Replis sûrs : snapshot vide / partiel → 0.0 (jamais une fausse panique) --
	assert(is_equal_approx(WI.compute({}), 0.0))
	# Héros absents (état pré-RPG) : les ratios manquants valent 1.0 → seuls round et zone pèsent.
	assert(is_equal_approx(WI.compute({"round": 8, "zone_count": 8}), WI.W_ROUND + WI.W_ZONE))
	asserts += 2
	print("[OK] snapshot vide = 0.0, état pré-RPG = round+zone seuls (2 asserts)")

	# --- 4) Clamp haut : une guerre désespérée SATURE à 1.0 (somme des poids = 1,10) --
	assert(is_equal_approx(WI.compute({"round": 99, "alive_heroes_pv_ratio": 0.0,
		"my_hero_pv_ratio": 0.0, "zone_count": 99, "final_protocol": true}), 1.0))
	asserts += 1
	print("[OK] clamp haut à 1.0 (1 assert)")

	# --- 5) PLANCHER du PROTOCOLE FINAL ---------------------------------------------
	# Cas piège : PROTOCOLE FINAL déclenché TÔT sur une partie propre. La formule seule rendrait
	# ≈ 0,38 → aucune couche musicale « high », vignette molle. Le plancher doit le remonter.
	var early_fp := {"round": 3, "alive_heroes_pv_ratio": 1.0, "my_hero_pv_ratio": 1.0,
		"zone_count": 1, "final_protocol": true}
	assert(is_equal_approx(WI.compute(early_fp), WI.FINAL_PROTOCOL_FLOOR))
	# Contre-épreuve : SANS le protocole, le même état reste bas (le plancher ne « fuit » pas).
	var early_calm := early_fp.duplicate()
	early_calm["final_protocol"] = false
	assert(WI.compute(early_calm) < 0.25)
	asserts += 2
	print("[OK] plancher PROTOCOLE FINAL = %.2f, sans fuite hors protocole (2 asserts)"
		% WI.FINAL_PROTOCOL_FLOOR)

	# --- 6) Lissage : jamais de saut, et INDÉPENDANT DU FRAMERATE --------------------
	# delta ≤ 0 (première frame / pause) → immobile.
	assert(is_equal_approx(WI.smooth(0.3, 1.0, 0.0), 0.3))
	# Un pas ne franchit jamais la cible (pas de dépassement).
	var one_step: float = WI.smooth(0.0, 1.0, 0.016)
	assert(one_step > 0.0 and one_step < 1.0)
	# Constante de temps : après 1/SMOOTH_SPEED secondes, on a rattrapé ≈ 63,2 % de l'écart.
	var tau := 1.0 / WI.SMOOTH_SPEED
	assert(absf(WI.smooth(0.0, 1.0, tau) - 0.6321) < 0.01)
	# ⚠️ LE test qui compte : 150 petits pas (≈ 144 fps) doivent atterrir au MÊME endroit qu'un
	# seul grand pas de même durée totale. Un `lerp(current, target, k)` naïf (sans exp) échouerait
	# ici — et la musique monterait 5× plus vite sur un PC rapide que sur un portable.
	var fine := 0.0
	var dt := tau / 150.0
	for _i in 150:
		fine = WI.smooth(fine, 1.0, dt)
	assert(absf(fine - WI.smooth(0.0, 1.0, tau)) < 0.005)
	# Symétrie : la descente suit exactement la même loi.
	assert(absf(WI.smooth(1.0, 0.0, tau) - (1.0 - 0.6321)) < 0.01)
	asserts += 5
	print("[OK] lissage sans saut, τ = %.1f s, INDÉPENDANT DU FRAMERATE (5 asserts)" % tau)

	print("")
	print("[OK] TEST WAR_INTENSITY (§8.122 LOT A) : %d asserts verts" % asserts)
	get_tree().quit(0)
