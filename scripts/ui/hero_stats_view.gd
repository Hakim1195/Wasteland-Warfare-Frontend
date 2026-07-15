extends RefCounted

# =========================================================
# Vue partagée des CARACTÉRISTIQUES d'un héros — charte « Warzone Command » (§2)
# =========================================================
# SOURCE UNIQUE de vérité pour l'ordre, les libellés (i18n CHAR_STAT_*) et le formatage des
# statistiques de héros (PV / PA / PB / PP / RÉGÉN). Mutualisée (DRY) entre :
#   - characters_screen.gd  → détail complet (colonnes ACTUEL / NIV. 50 + descriptions),
#   - faction_selection.gd  → rangée compacte de pastilles au DRAFT de faction.
# Chargée par preload (PAS via class_name) — même prudence cache d'import que warzone_ui.gd.
# Règle d'Or §6.1 : rendu PUR (aucune logique de jeu) ; lecture DÉFENSIVE des nombres (piège float §5).
#
# ⚠️ Fonctions STATIQUES : pas de tr() ici (indisponible hors instance). On pose les CLÉS i18n
# brutes dans `text` / `tooltip_text` — l'auto-traduction des Control (activée par défaut) les
# résout à l'entrée dans l'arbre (même motif que characters_screen._section_header).

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

# Surface secondaire (#1A2028) — fond des pastilles (la charte réserve le gunmetal au grand panneau).
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)
# Valeur affichée tant que la stat est inconnue (roster asynchrone) — glyphe neutre, hors i18n.
const PLACEHOLDER := "—"

# Ordre + libellés : abréviation (`key`), nom complet (`name`), description joueur (`desc`), clé
# backend lue dans stats / stats_max (`field`) et type de formatage (`kind`). Tout est i18n (FR/EN/IT).
# Les 5 lignes : PV (int), PA (int), PB (pourcentage), PP (intervalle pp_min/pp_max), RÉGÉN (pourcentage).
const STAT_ROWS := [
	{"key": "CHAR_STAT_PV", "name": "CHAR_STAT_PV_NAME", "desc": "CHAR_STAT_PV_DESC", "field": "pv_max", "kind": "int"},
	{"key": "CHAR_STAT_PA", "name": "CHAR_STAT_PA_NAME", "desc": "CHAR_STAT_PA_DESC", "field": "pa", "kind": "int"},
	{"key": "CHAR_STAT_PB", "name": "CHAR_STAT_PB_NAME", "desc": "CHAR_STAT_PB_DESC", "field": "pb", "kind": "pct"},
	{"key": "CHAR_STAT_PP", "name": "CHAR_STAT_PP_NAME", "desc": "CHAR_STAT_PP_DESC", "field": "pp", "kind": "range"},
	{"key": "CHAR_STAT_REGEN", "name": "CHAR_STAT_REGEN_NAME", "desc": "CHAR_STAT_REGEN_DESC", "field": "regen", "kind": "pct"},
]

# Formate une stat selon son type : entier brut (PV/PA), pourcentage (PB/Régén) ou intervalle
# [min, max] (PP). Lecture DÉFENSIVE (piège JSON float §5) : jamais de float brut à l'écran.
static func format_stat(stats: Dictionary, row: Dictionary) -> String:
	match str(row["kind"]):
		"pct":
			return "%d%%" % int(round(float(stats.get(row["field"], 0.0)) * 100.0))
		"range":
			return "[%d, %d]" % [int(stats.get("pp_min", 0)), int(stats.get("pp_max", 0))]
		_:
			return str(int(stats.get(row["field"], 0)))

# Construit la RANGÉE COMPACTE de caractéristiques du DRAFT (faction_selection) : un filet cyan,
# un eyebrow « ❯ CARACTÉRISTIQUES », puis des pastilles étiquetées NIV + PV/PA/PB%/PP/RÉGÉN%.
# `hero` == null (roster pas encore là / faction sans héros) → pastilles SQUELETTE (valeurs « — »)
# à mise en page identique, remplies dès la réception du roster (aucun décalage visuel). `accent` =
# couleur de la faction (teinte des liserés). Renvoie un conteneur prêt à insérer dans IntelColumn.
static func build_compact_row(hero, font: Font, accent: Color) -> Control:
	var stats: Dictionary = {}
	var level := 0
	if hero is Dictionary:
		var s = hero.get("stats", {})
		stats = s if s is Dictionary else {}
		level = int(hero.get("level", 0))

	var box := VBoxContainer.new()
	box.name = "HeroStatsRow"
	box.add_theme_constant_override("separation", 6)

	# Filet fin cyan : sépare le bloc stats de la description au-dessus (rythme de charte §2).
	WarzoneUI.add_filet(box)

	# Eyebrow « ❯ CARACTÉRISTIQUES » (clé brute → auto-traduite FR/EN/IT à l'entrée dans l'arbre).
	var eyebrow := Label.new()
	eyebrow.text = "FS_STATS_EYEBROW"
	eyebrow.add_theme_font_override("font", font)
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", WarzoneUI.ACCENT)
	box.add_child(eyebrow)

	# Rangée de pastilles : HFlowContainer → repli automatique sur une 2e ligne si la carte est étroite.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	box.add_child(row)

	# Pastille NIVEAU (teinte OR, comme le compteur de la charte). Pas d'infobulle (libellé explicite).
	var lvl_txt := str(level) if level > 0 else PLACEHOLDER
	row.add_child(_make_pill("COMMON_LEVEL", lvl_txt, font, WarzoneUI.GOLD, WarzoneUI.GOLD, ""))

	# Une pastille par statistique (valeur réelle si le héros est connu, sinon squelette « — »).
	for r in STAT_ROWS:
		var val_txt := format_stat(stats, r) if hero is Dictionary else PLACEHOLDER
		row.add_child(_make_pill(str(r["key"]), val_txt, font, accent, WarzoneUI.TEXT, str(r["desc"])))

	return box

# Une pastille « étiquette (haut) ▸ valeur (bas) » : fond surface, fin liseré teinté, angles DROITS
# (§2). `label_key` / `tooltip_key` = CLÉS i18n brutes (auto-traduites) ; `tooltip_key` vide → aucune
# infobulle. Infobulle présente → SFX de survol (neutralisé sous headless — cf. warzone_ui).
static func _make_pill(label_key: String, value_text: String, font: Font, accent: Color, value_color: Color, tooltip_key: String) -> Control:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = SURFACE
	sb.set_border_width_all(1)
	sb.border_color = Color(accent, 0.75)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 6.0
	pill.add_theme_stylebox_override("panel", sb)
	if tooltip_key != "":
		pill.tooltip_text = tooltip_key  # clé brute → auto-traduite (infobulle = description joueur)
		pill.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE  # la pastille (PanelContainer) capte le survol/infobulle
	pill.add_child(v)

	var lbl := Label.new()
	lbl.text = label_key
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", WarzoneUI.MUTED)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_override("font", font)
	val.add_theme_font_size_override("font_size", 19)
	val.add_theme_color_override("font_color", value_color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(val)

	return pill
