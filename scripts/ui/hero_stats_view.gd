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

# Valeur numérique COMPARABLE d'une stat (classement roster pour le repère ▲) : pct/int → champ
# direct ; intervalle PP → plafond pp_max (potentiel le plus haut). Lecture défensive (piège float §5).
static func stat_scalar(stats: Dictionary, row: Dictionary) -> float:
	if str(row["kind"]) == "range":
		return float(stats.get("pp_max", 0.0))
	return float(stats.get(row["field"], 0.0))

# Construit la RANGÉE COMPACTE de caractéristiques du DRAFT (faction_selection) : un filet cyan,
# un eyebrow « ❯ CARACTÉRISTIQUES », puis des pastilles étiquetées NIV + PV/PA/PB%/PP/RÉGÉN%.
# `hero` == null (roster pas encore là / faction sans héros) → pastilles SQUELETTE (valeurs « — »)
# à mise en page identique, remplies dès la réception du roster (aucun décalage visuel). `accent` =
# couleur de la faction (teinte des liserés). Renvoie un conteneur prêt à insérer dans IntelColumn.
static func build_compact_row(hero, font: Font, accent: Color, leader_fields := []) -> Control:
	var stats: Dictionary = {}
	var stats_max: Dictionary = {}
	var level := 0
	var power := ""
	if hero is Dictionary:
		var s = hero.get("stats", {})
		stats = s if s is Dictionary else {}
		var sm = hero.get("stats_max", {})
		stats_max = sm if sm is Dictionary else {}
		level = int(hero.get("level", 0))
		# i18n (2026-07-18) : pouvoir du héros via les clés locales TRADUITES par faction
		# (HERO_POWER_NAME/DESC_<ID>), repli sur le hero_power serveur (anglais invariant).
		power = _power_text(str(hero.get("faction_id", "")), hero)

	var box := VBoxContainer.new()
	box.name = "HeroStatsRow"
	box.add_theme_constant_override("separation", 6)

	# Filet fin cyan : sépare le bloc du dossier au-dessus (rythme de charte §2).
	WarzoneUI.add_filet(box)

	# Pouvoir du héros MIS EN AVANT (payload hero_power) : encadré teinté à l'accent de la faction,
	# au-dessus des stats — plus lisible que noyé dans le lore. Omis si le pouvoir est inconnu.
	if power != "":
		box.add_child(_make_power_block(power, font, accent))

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
	row.add_child(_make_pill("COMMON_LEVEL", lvl_txt, font, WarzoneUI.GOLD, WarzoneUI.GOLD, "", false, -1.0))

	# Une pastille par statistique. Repère ▲ doré si le héros DOMINE le roster sur cette stat
	# (leader_fields, calculé par l'écran). Barre de potentiel (actuel vs plafond niv. 50) sur PV/PA.
	for r in STAT_ROWS:
		var field := str(r["field"])
		var val_txt := format_stat(stats, r) if hero is Dictionary else PLACEHOLDER
		var is_leader: bool = leader_fields.has(field)
		var bar_ratio := -1.0
		if hero is Dictionary and str(r["kind"]) == "int":
			var cap := float(stats_max.get(field, 0.0))
			if cap > 0.0:
				bar_ratio = clampf(float(stats.get(field, 0.0)) / cap, 0.0, 1.0)
		row.add_child(_make_pill(str(r["key"]), val_txt, font, accent, WarzoneUI.TEXT, str(r["desc"]), is_leader, bar_ratio))

	return box

# Une pastille « étiquette (haut) ▸ valeur (bas) » : fond surface, fin liseré teinté, angles DROITS
# (§2). `label_key` / `tooltip_key` = CLÉS i18n brutes (auto-traduites) ; `tooltip_key` vide → aucune
# infobulle. `is_leader` → liseré + ▲ OR (« meilleur du roster »). `bar_ratio` >= 0 → barre de
# potentiel (actuel vs plafond) sous la valeur ; < 0 → pas de barre. Infobulle → SFX de survol.
static func _make_pill(label_key: String, value_text: String, font: Font, accent: Color, value_color: Color, tooltip_key: String, is_leader: bool, bar_ratio: float) -> Control:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = SURFACE
	sb.set_border_width_all(1)
	# Liseré doré si le héros domine le roster sur cette stat, sinon teinte de la faction.
	sb.border_color = WarzoneUI.GOLD if is_leader else Color(accent, 0.75)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 6.0
	pill.add_theme_stylebox_override("panel", sb)
	if tooltip_key != "":
		pill.tooltip_text = tooltip_key  # clé brute → auto-traduite (infobulle = description joueur)
		pill.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
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

	# Ligne de valeur (centrée) + repère ▲ doré « meilleur du roster » le cas échéant.
	var vr := HBoxContainer.new()
	vr.alignment = BoxContainer.ALIGNMENT_CENTER
	vr.add_theme_constant_override("separation", 4)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_override("font", font)
	val.add_theme_font_size_override("font_size", 19)
	val.add_theme_color_override("font_color", value_color)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vr.add_child(val)
	if is_leader:
		var tri := Label.new()
		tri.text = "▲"
		tri.tooltip_text = "FS_STAT_BEST"  # clé brute → auto-traduite (infobulle du repère ▲)
		tri.add_theme_font_override("font", font)
		tri.add_theme_font_size_override("font_size", 11)
		tri.add_theme_color_override("font_color", WarzoneUI.GOLD)
		tri.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vr.add_child(tri)  # mouse_filter par défaut (STOP) → infobulle propre au repère
	v.add_child(vr)

	# Barre de potentiel (actuel vs plafond niv. 50) — PV/PA uniquement (bar_ratio >= 0).
	if bar_ratio >= 0.0:
		v.add_child(_make_mini_bar(bar_ratio))

	return pill

# Barre fine « potentiel » (actuel vs plafond niv. 50) : remplissage cyan sur fond sombre, angles
# DROITS (§2). Purement indicative → ignore la souris (l'infobulle reste celle de la pastille).
static func _make_mini_bar(ratio: float) -> Control:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 5)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.set_corner_radius_all(0)
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(0)
	fill.bg_color = WarzoneUI.ACCENT
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

# Ligne « POUVOIR » du héros par faction_id : clés locales TRADUITES (HERO_POWER_NAME_<ID> /
# HERO_POWER_DESC_<ID> — TranslationServer, helper static), repli sur hero_power serveur.
static func _power_text(fid: String, hero: Dictionary) -> String:
	if fid != "":
		var key_name := "HERO_POWER_NAME_" + fid.to_upper()
		# String(...) : translate() rend un StringName — sans le cast, le ternaire du return mêle
		# String et StringName (warning INCOMPATIBLE_TERNARY, comportement inchangé par ailleurs).
		var n := String(TranslationServer.translate(key_name))
		if n != key_name:
			var key_desc := "HERO_POWER_DESC_" + fid.to_upper()
			var d := String(TranslationServer.translate(key_desc))
			return (n + " — " + d) if d != key_desc else n
	return str(hero.get("hero_power", ""))

# Encadré « POUVOIR » mis en avant : eyebrow cyan + texte du pouvoir (backend) dans un cadre au
# liseré gauche et fond légèrement teintés à l'accent de la faction (cf. lignes de paliers §Perso).
# Le texte est du CONTENU dynamique (pas une clé i18n) → auto-traduction désactivée.
static func _make_power_block(power: String, font: Font, accent: Color) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 3)

	var eb := Label.new()
	eb.text = "FS_POWER_EYEBROW"
	eb.add_theme_font_override("font", font)
	eb.add_theme_font_size_override("font_size", 13)
	eb.add_theme_color_override("font_color", WarzoneUI.ACCENT)
	block.add_child(eb)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(accent, 0.10)
	sb.border_width_left = 3
	sb.border_color = accent
	sb.content_margin_left = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = power
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED  # contenu dynamique, pas une clé
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", WarzoneUI.TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lbl)

	block.add_child(panel)
	return block
