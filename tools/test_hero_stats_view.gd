extends Node

# TEST — Vue partagée des caractéristiques (hero_stats_view.gd) : SOURCE UNIQUE STAT_ROWS + formatage
# + classement roster (▲) et rangée de pastilles compacte du draft (pouvoir, ▲, barres de potentiel).
# Pattern maison (cf. test_e1_roster) :
#   & <godot_console> --headless --path frontend res://tools/test_hero_stats_view.tscn
# Succès = lignes « [OK] … » + code retour 0 + AUCUNE ligne ERROR.

const HeroStatsView := preload("res://scripts/ui/hero_stats_view.gd")

# Stub d'un héros (clés canoniques du payload GET /api/v1/heroes). Nombres en FLOAT pour reproduire
# le piège JSON §5 (JSON.parse_string → float) : le formatage DOIT rendre des entiers / % / intervalles.
const STUB_HERO := {
	"faction_id": "phalanges_acier",
	"faction_name": "Les Phalangistes",
	"hero_power": "Bouclier de phalange : réduit les dégâts de zone de 20%.",
	"level": 14.0,
	"stats": {"pv_max": 60.0, "pa": 4.0, "pb": 0.3, "pp_min": 1.0, "pp_max": 3.0, "regen": 0.1},
	"stats_max": {"pv_max": 120.0, "pa": 9.0, "pb": 0.6, "pp_min": 2.0, "pp_max": 6.0, "regen": 0.25},
}

func _ready() -> void:
	var font := SystemFont.new()

	# 1) STAT_ROWS = source unique, 5 lignes dans l'ordre PV / PA / PB / PP / RÉGÉN.
	assert(HeroStatsView.STAT_ROWS.size() == 5)
	assert(str(HeroStatsView.STAT_ROWS[0]["field"]) == "pv_max")
	assert(str(HeroStatsView.STAT_ROWS[4]["field"]) == "regen")
	print("[OK] STAT_ROWS : 5 lignes ordonnees (3 asserts)")

	# 2) format_stat : entier (PV/PA), pourcentage (PB/Régén), intervalle (PP) — jamais de float brut.
	var stats: Dictionary = STUB_HERO["stats"]
	assert(HeroStatsView.format_stat(stats, HeroStatsView.STAT_ROWS[0]) == "60")     # PV
	assert(HeroStatsView.format_stat(stats, HeroStatsView.STAT_ROWS[1]) == "4")      # PA
	assert(HeroStatsView.format_stat(stats, HeroStatsView.STAT_ROWS[2]) == "30%")    # PB
	assert(HeroStatsView.format_stat(stats, HeroStatsView.STAT_ROWS[3]) == "[1, 3]") # PP
	assert(HeroStatsView.format_stat(stats, HeroStatsView.STAT_ROWS[4]) == "10%")    # RÉGÉN
	print("[OK] format_stat : int / %% / intervalle (5 asserts)")

	# 3) format_stat DÉFENSIF : stats vide → zéros propres (aucun crash, aucun float brut à l'écran).
	assert(HeroStatsView.format_stat({}, HeroStatsView.STAT_ROWS[0]) == "0")
	assert(HeroStatsView.format_stat({}, HeroStatsView.STAT_ROWS[2]) == "0%")
	assert(HeroStatsView.format_stat({}, HeroStatsView.STAT_ROWS[3]) == "[0, 0]")
	print("[OK] format_stat defensif : stats vide (3 asserts)")

	# 3bis) stat_scalar : valeur comparable pour le classement roster (▲) ; PP → plafond pp_max.
	assert(HeroStatsView.stat_scalar(stats, HeroStatsView.STAT_ROWS[0]) == 60.0)  # PV
	assert(HeroStatsView.stat_scalar(stats, HeroStatsView.STAT_ROWS[3]) == 3.0)   # PP → pp_max
	print("[OK] stat_scalar : classement roster (2 asserts)")

	# 4) build_compact_row(héros complet + leader ▲ + barres PV/PA) : 6 pastilles + encadré POUVOIR.
	var row_full = HeroStatsView.build_compact_row(STUB_HERO, font, Color.RED, ["pv_max", "pa"])
	add_child(row_full)  # entrée dans l'arbre → auto-traduction des clés i18n (ne doit rien casser)
	var pills_full := _find_flow(row_full)
	assert(pills_full != null)
	assert(pills_full.get_child_count() == 6)
	assert(_has_power_block(row_full))  # hero_power renseigné → encadré POUVOIR présent
	print("[OK] build_compact_row(hero + power + ▲ + barres) : 6 pastilles (3 asserts)")

	# 5) build_compact_row(null) : squelette de MÊME structure (6 pastilles « — »), sans encadré, no crash.
	var row_skel = HeroStatsView.build_compact_row(null, font, Color.RED)
	add_child(row_skel)
	var pills_skel := _find_flow(row_skel)
	assert(pills_skel != null)
	assert(pills_skel.get_child_count() == 6)
	assert(not _has_power_block(row_skel))  # pas de héros → pas d'encadré POUVOIR
	print("[OK] build_compact_row(null) : squelette 6 pastilles sans power (3 asserts)")

	# 6) i18n : les clés ajoutées sont bien compilées (.translation) dans les 3 langues — pas de
	# repli sur la clé brute (vérif locale-indépendante : on interroge chaque ressource directement).
	for loc in ["fr", "en", "it"]:
		var t = load("res://translations/ui_strings.%s.translation" % loc)
		assert(t != null)
		assert(str(t.get_message("FS_STAT_BEST")) != "" and str(t.get_message("FS_STAT_BEST")) != "FS_STAT_BEST")
		assert(str(t.get_message("FS_POWER_EYEBROW")) != "" and str(t.get_message("FS_POWER_EYEBROW")) != "FS_POWER_EYEBROW")
		assert(str(t.get_message("FS_STATS_EYEBROW")) != "" and str(t.get_message("FS_STATS_EYEBROW")) != "FS_STATS_EYEBROW")
	print("[OK] i18n : FS_STAT_BEST / FS_POWER_EYEBROW / FS_STATS_EYEBROW compilees FR/EN/IT (12 asserts)")

	print("[OK] TEST HERO_STATS_VIEW : 31 asserts verts")
	get_tree().quit(0)

# Retrouve le HFlowContainer (rangée de pastilles) dans le bloc construit.
func _find_flow(root: Node) -> HFlowContainer:
	for child in root.get_children():
		if child is HFlowContainer:
			return child
	return null

# Vrai si le bloc contient l'encadré POUVOIR (seul enfant VBoxContainer du bloc).
func _has_power_block(root: Node) -> bool:
	for child in root.get_children():
		if child is VBoxContainer:
			return true
	return false
