extends Node

# TEST — Vue partagée des caractéristiques (hero_stats_view.gd) : SOURCE UNIQUE STAT_ROWS + formatage,
# et rangée de pastilles compacte du draft (faction_selection). Pattern maison (cf. test_e1_roster) :
#   & <godot_console> --headless --path frontend res://tools/test_hero_stats_view.tscn
# Succès = lignes « [OK] … » + code retour 0 + AUCUNE ligne ERROR.

const HeroStatsView := preload("res://scripts/ui/hero_stats_view.gd")

# Stub d'un héros (clés canoniques du payload GET /api/v1/heroes). Nombres en FLOAT pour reproduire
# le piège JSON §5 (JSON.parse_string → float) : le formatage DOIT rendre des entiers / % / intervalles.
const STUB_HERO := {
	"faction_id": "phalanges_acier",
	"faction_name": "Les Phalangistes",
	"level": 14.0,
	"stats": {"pv_max": 60.0, "pa": 4.0, "pb": 0.3, "pp_min": 1.0, "pp_max": 3.0, "regen": 0.1},
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

	# 4) build_compact_row(héros) : 1 pastille NIVEAU + 5 pastilles stats = 6 (dans le HFlowContainer).
	var row_full = HeroStatsView.build_compact_row(STUB_HERO, font, Color.RED)
	add_child(row_full)  # entrée dans l'arbre → auto-traduction des clés i18n (ne doit rien casser)
	var pills_full := _find_flow(row_full)
	assert(pills_full != null)
	assert(pills_full.get_child_count() == 6)
	print("[OK] build_compact_row(hero) : 6 pastilles (2 asserts)")

	# 5) build_compact_row(null) : squelette de MÊME structure (6 pastilles « — »), aucun crash.
	var row_skel = HeroStatsView.build_compact_row(null, font, Color.RED)
	add_child(row_skel)
	var pills_skel := _find_flow(row_skel)
	assert(pills_skel != null)
	assert(pills_skel.get_child_count() == 6)
	print("[OK] build_compact_row(null) : squelette 6 pastilles (2 asserts)")

	print("[OK] TEST HERO_STATS_VIEW : 15 asserts verts")
	get_tree().quit(0)

# Retrouve le HFlowContainer (rangée de pastilles) dans le bloc construit.
func _find_flow(root: Node) -> HFlowContainer:
	for child in root.get_children():
		if child is HFlowContainer:
			return child
	return null
