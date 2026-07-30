extends Node

# CARTE DE PARTAGE (§8.121, LOT D) — le jeu produit son propre marketing : une image PNG
# auto-composée à la fin de chaque partie, que le joueur exporte en UN clic depuis le Rapport
# Post-Opération. DEUX formats aux layouts DISTINCTS (jamais une mise à l'échelle de l'autre) :
# 1920×1080 pour les posts « bureau » et 1080×1920 pour les stories verticales.
#
# Architecture : composition 100 % CODE dans un `SubViewport` HORS ÉCRAN, rendue puis sauvée en PNG
# (`get_texture().get_image().save_png()`). Aucune dépendance, aucun plugin, aucun asset nouveau —
# seule la MARQUE existante (`assets/images/logo_mark.svg`) est réutilisée, en filigrane, avec l'adresse du
# site : c'est un objet marketing, il DOIT ramener vers le jeu (décision produit n° 4).
#
# ⚠️ PAS de copie d'image dans le presse-papiers (décision produit n° 3) : Godot 4 n'a pas d'API
# portable pour cela (`DisplayServer.clipboard_set` ne prend que du texte). On copie donc un RÉSUMÉ
# TEXTE de la partie — collable tel quel dans un tweet ou un chat — et on ouvre le dossier des
# captures pour que le joueur récupère l'image lui-même.
#
# ⚠️ Ce module ne connaît NI le Rapport Post-Op NI `main.gd` : il ne reçoit qu'un `payload` de
# données déjà résolues (View pure §6.1). C'est ce sens unique qui autorise `operation_report.gd` à
# le précharger sans créer d'inclusion CYCLIQUE de ressources (les deux ne partagent que
# `timeline_chart.gd`).
#
# ⚠️ Module aux fonctions STATIQUES pour la composition → `tr()` n'y est pas disponible :
# `TranslationServer.translate()` est le bon appel (même piège qu'en §8.104 pour war_feed /
# objective_tracker). Les libellés DE CONTENU (verdict, titres honorifiques, noms de faction) sont
# déjà traduits par l'appelant ; seuls les intertitres de la carte sont résolus ici.

const TimelineChart := preload("res://scripts/ui/timeline_chart.gd")
const RosterHelpers := preload("res://scripts/ui/war_roster.gd")

# Deux formats, deux LAYOUTS (cf. _compose_landscape / _compose_portrait).
const FORMATS := [
	{"id": "landscape", "size": Vector2i(1920, 1080)},
	{"id": "portrait", "size": Vector2i(1080, 1920)},
]

const CAPTURE_DIR := "user://captures"
# MARQUE de la carte : `logo_mark.svg` (emblème biohazard carré, la marque CANONIQUE du jeu —
# déjà utilisée par title_splash, top_nav, warzone_ui et ww_logo). ⚠️ NE PAS reprendre
# `logo_ww.png` : ce lockup large porte du lettrage fin qui devient illisible en filigrane
# (défaut vu en capture, écarté par Hakim le 2026-07-30).
const LOGO_PATH := "res://assets/images/logo_mark.svg"
const SITE := "wasteland-warfare.com"

# Charte « Warzone Command » (§2) — mêmes valeurs qu'`operation_report.gd`, redéclarées ici parce
# que ce module est autonome (aucun preload du rapport, cf. en-tête).
const BG := Color("0f1318")
const SURFACE := Color("1a2028")
const ACCENT_CYAN := Color("36c5d9")
const ACCENT_GOLD := Color("e0b249")
const TEXT_PRIMARY := Color("eef3f7")
const TEXT_MUTED := Color("8a97a5")
const DANGER := Color("d6453f")


# =========================================================
# COMPOSITION (statique, testable hors rendu)
# =========================================================
# `payload` (tout est FACULTATIF — une clé absente omet sa section, jamais d'erreur) :
#   verdict         String   — « VICTOIRE » / « DÉFAITE », déjà traduit
#   verdict_reason  String   — « OBJECTIF ATTEINT » / « TEMPS ÉCOULÉ »…, déjà traduit
#   is_victory      bool     — pilote l'accent (or) vs le danger (rouge)
#   podium          Array[{ name: String, color: Color, medal: String }]  (3 premiers)
#   faction_name    String   — nom EN invariant de MA faction
#   leader          String   — « GÉNÉRAL VIKTOR "IRONLINE" STAHL » (rang traduit, nom invariant)
#   portrait        Texture2D | null
#   accent          Color    — couleur d'accent de ma faction
#   titles          Array[String] — titres honorifiques gagnés, déjà traduits
#   timeline        Array[{ color: Color, points: Array[int] }]
#   betrayal_line   String   — ligne du Rapport de Trahison (LOT B), "" si aucune
#   stats           Array[[label: String, value: String]] — 3 chiffres clés
static func compose(payload: Dictionary, format_id: String) -> Control:
	var spec := _spec(format_id)
	var size := Vector2(spec["size"])
	var root := Control.new()
	root.name = "ShareCard_" + str(spec["id"])
	root.custom_minimum_size = size
	# Ancrage plein cadre : sous le SubViewport, c'est ce qui donne à la composition la taille EXACTE
	# du rendu (un Control sans ancre reste à 0×0 et le PNG sortirait vide).
	# ⚠️ PIÈGE (bug constaté, carte rendue au DOUBLE de sa taille) : il faut
	# `set_anchors_AND_OFFSETS_preset` et surtout NE PAS écrire `root.size` avant. `compose()`
	# construit un arbre DÉTACHÉ ; `set_anchors_preset` (sans les offsets) recalcule les offsets pour
	# « conserver le rect courant » contre un parent de taille 0 → `offset_right` reste à 1920, puis
	# une fois greffé dans le viewport la taille devient `ancre(1920) + offset(1920) = 3840`. Le
	# contenu se mettait alors en page sur 2× la largeur et le PNG était un cadrage tronqué.
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Thème posé sur la RACINE (hérité par toute la composition) : le SubViewport n'a pas le thème
	# de `operation_report.tscn`, la carte serait rendue dans la police par défaut de Godot.
	root.theme = _theme()

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# Liseré supérieur (ADN angulaire §2) : or en victoire, rouge en défaite.
	var hair := ColorRect.new()
	hair.color = ACCENT_GOLD if bool(payload.get("is_victory", false)) else DANGER
	hair.custom_minimum_size = Vector2(size.x, 6)
	hair.size = Vector2(size.x, 6)
	root.add_child(hair)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Marges mesurees, pas choisies : en paysage, 72 px de marge + la hauteur minimale du contenu
	# (942 px) depassaient les 1080 px du cadre et EJECTAIENT les deux derniers blocs (ligne de
	# trahison + filigrane) hors de l image. 56 px laissent ~26 px de jeu.
	var pad := 56 if str(spec["id"]) == "landscape" else 64
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	root.add_child(margin)

	if str(spec["id"]) == "portrait":
		margin.add_child(_compose_portrait(payload))
	else:
		margin.add_child(_compose_landscape(payload))
	return root


# 1920×1080 — lecture en DEUX COLONNES : mon héros à gauche (l'identité), la courbe de domination
# et le podium à droite (le récit). Le verdict barre le haut, la trahison et le filigrane le bas.
static func _compose_landscape(p: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)

	col.add_child(_header(p, 100, 30, false))
	col.add_child(_rule(_accent_of(p), 2))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 52)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 22)
	left.custom_minimum_size = Vector2(640, 0)
	left.add_child(_hero_block(p, 200, 46, 22))
	var stats := _stats_row(p, 190, 44)
	if stats != null:
		left.add_child(stats)
	body.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chart := _chart_block(p, 300, 3.0)
	if chart != null:
		right.add_child(chart)
	var podium := _podium_block(p, 30)
	if podium != null:
		right.add_child(podium)
	body.add_child(right)
	col.add_child(body)

	var betrayal := _betrayal_block(p, 30)
	if betrayal != null:
		col.add_child(betrayal)
	col.add_child(_footer(88, 26, HORIZONTAL_ALIGNMENT_RIGHT))
	return col


# 1080×1920 — lecture EMPILÉE : le verdict, puis le héros en grand (le format vertical est fait
# pour un portrait), puis les chiffres, la courbe, le podium, la trahison, le filigrane centré.
# Ce n'est pas le layout paysage redimensionné : la colonne unique change l'ordre de lecture.
static func _compose_portrait(p: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 34)

	col.add_child(_header(p, 116, 34, true))
	col.add_child(_rule(_accent_of(p), 3))
	col.add_child(_hero_block(p, 300, 56, 26, true))
	var stats := _stats_row(p, 280, 54)
	if stats != null:
		col.add_child(stats)
	var chart := _chart_block(p, 380, 4.0)
	if chart != null:
		col.add_child(chart)
	var podium := _podium_block(p, 36)
	if podium != null:
		col.add_child(podium)
	var betrayal := _betrayal_block(p, 34)
	if betrayal != null:
		col.add_child(betrayal)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	col.add_child(_footer(104, 30, HORIZONTAL_ALIGNMENT_CENTER))
	return col


# =========================================================
# Briques de composition
# =========================================================

# VERDICT + raison. En paysage le logo s'installe à droite du titre ; en portrait le titre est
# centré (le logo est alors au pied, cf. _footer).
static func _header(p: Dictionary, title_px: int, reason_px: int, centered: bool) -> Control:
	var align := HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(str(p.get("verdict", "")).to_upper(), title_px,
		ACCENT_GOLD if bool(p.get("is_victory", false)) else DANGER, align)
	block.add_child(title)
	var reason := str(p.get("verdict_reason", ""))
	if reason != "":
		block.add_child(_label(reason.to_upper(), reason_px, TEXT_MUTED, align))
	# Aucun logo ici : le filigrane vit UNIQUEMENT au pied de la carte (cf. _footer). Deux
	# occurrences se disputaient l'attention avec le verdict, qui est le sujet de l'image.
	return block


# MON HÉROS : portrait + faction + meneur + badges de titres honorifiques.
static func _hero_block(p: Dictionary, portrait_px: int, name_px: int, leader_px: int,
		centered: bool = false) -> Control:
	var accent := _accent_of(p)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(SURFACE, 0.75)
	sb.border_width_left = 6
	sb.border_color = accent
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	if centered:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	var portrait = p.get("portrait")
	if portrait is Texture2D:
		var tex := TextureRect.new()
		tex.texture = portrait
		tex.custom_minimum_size = Vector2(portrait_px, portrait_px)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.clip_contents = true
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tex)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not centered:
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(_label(str(p.get("faction_name", "")).to_upper(), name_px, TEXT_PRIMARY,
		HORIZONTAL_ALIGNMENT_LEFT))
	var leader := str(p.get("leader", ""))
	if leader != "":
		info.add_child(_label(leader.to_upper(), leader_px, Color(accent, 0.92),
			HORIZONTAL_ALIGNMENT_LEFT))
	var titles = p.get("titles", [])
	if typeof(titles) == TYPE_ARRAY and not (titles as Array).is_empty():
		var badges := HBoxContainer.new()
		badges.add_theme_constant_override("separation", 8)
		for t in titles:
			badges.add_child(_badge(str(t).to_upper(), maxi(14, leader_px - 4)))
		info.add_child(badges)
	return panel


# Trois chiffres clés (KILLS / CONQUÊTES / DURÉE) en tuiles à filet supérieur cyan.
static func _stats_row(p: Dictionary, tile_w: int, value_px: int) -> Control:
	var stats = p.get("stats", [])
	if typeof(stats) != TYPE_ARRAY or (stats as Array).is_empty():
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for entry in stats:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 2:
			continue
		var tile := VBoxContainer.new()
		tile.add_theme_constant_override("separation", 2)
		tile.custom_minimum_size = Vector2(tile_w, 0)
		tile.add_child(_rule(Color(ACCENT_CYAN, 0.7), 2))
		tile.add_child(_label(str(entry[0]).to_upper(), maxi(16, value_px / 2), TEXT_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT))
		var v := _label(str(entry[1]), value_px, TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)
		v.add_theme_font_override("font", RosterHelpers._mono_font())
		tile.add_child(v)
		row.add_child(tile)
	return row


# Courbe de domination — MÊME brique que le Rapport Post-Op (timeline_chart.gd), trait épaissi :
# à 1920 px de large, les 2 px du rapport seraient un cheveu invisible.
static func _chart_block(p: Dictionary, height: int, width: float) -> Control:
	var series = p.get("timeline", [])
	if typeof(series) != TYPE_ARRAY or (series as Array).size() < 1:
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_eyebrow(_t("SHARE_CARD_TIMELINE"), 26))
	var chart := TimelineChart.new()
	chart.line_width = width
	chart.grid_alpha = 0.18
	chart.custom_minimum_size = Vector2(0, height)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(chart)
	chart.setup(series)
	return box


# Podium des trois premiers : indicatif mono « 01 » + pastille couleur plateau + pseudo.
static func _podium_block(p: Dictionary, name_px: int) -> Control:
	var rows = p.get("podium", [])
	if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_eyebrow(_t("SHARE_CARD_PODIUM"), 26))
	for i in range((rows as Array).size()):
		var r = rows[i]
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var rank := _label(str(r.get("medal", "%02d" % (i + 1))), name_px,
			ACCENT_GOLD if i == 0 else TEXT_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		rank.add_theme_font_override("font", RosterHelpers._mono_font())
		rank.custom_minimum_size = Vector2(name_px * 2, 0)
		line.add_child(rank)
		var dot := ColorRect.new()
		dot.color = r.get("color", TEXT_MUTED)
		dot.custom_minimum_size = Vector2(name_px * 0.5, name_px * 0.5)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(dot)
		var who := _label(str(r.get("name", "")).to_upper(), name_px,
			ACCENT_GOLD if i == 0 else TEXT_PRIMARY, HORIZONTAL_ALIGNMENT_LEFT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(who)
		box.add_child(line)
	return box


# Ligne du Rapport de Trahison (LOT B) — absente si la partie n'a pas produit de coup de poignard
# ou si le serveur n'est pas encore redéployé (aucun journal d'attaques).
static func _betrayal_block(p: Dictionary, px: int) -> Control:
	var line := str(p.get("betrayal_line", ""))
	if line == "":
		return null
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT_GOLD, 0.08)
	sb.border_width_left = 4
	sb.border_color = ACCENT_GOLD
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	# Pas de glyphe ajouté ici : la ligne vient de la clé `BETRAYAL_BACKSTAB`, qui porte DÉJÀ son
	# « ✸ » (le doubler afficherait « ✸ ✸ … »).
	var l := _label(line.to_upper(), px, ACCENT_GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(l)
	return panel


# Filigrane : logo WW + adresse du site. C'est la RAISON D'ÊTRE de la carte (décision n° 4) —
# jamais omis, même sur un payload minimal.
static func _footer(logo_px: int, px: int, align: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		row.alignment = BoxContainer.ALIGNMENT_END
	var logo := _logo(logo_px)
	if logo != null:
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(logo)
	var site := _label(SITE, px, Color(TEXT_MUTED, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	site.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(site)
	return row


# MARQUE en filigrane. `width_px` est une LARGEUR : la hauteur est dérivée du ratio RÉEL de la
# texture (la marque est carrée, mais le calcul reste juste si l'asset change un jour).
static func _logo(width_px: int) -> TextureRect:
	if not ResourceLoader.exists(LOGO_PATH):
		return null
	var res = load(LOGO_PATH)
	if not (res is Texture2D):
		return null
	var tex_res := res as Texture2D
	var ratio := 1.83
	if tex_res.get_height() > 0:
		ratio = float(tex_res.get_width()) / float(tex_res.get_height())
	var tex := TextureRect.new()
	tex.texture = tex_res
	tex.custom_minimum_size = Vector2(width_px, roundf(float(width_px) / maxf(ratio, 0.1)))
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tex.modulate = Color(1, 1, 1, 0.85)
	return tex


static func _label(text: String, px: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func _eyebrow(text: String, px: int) -> Label:
	return _label("❯ " + text.to_upper(), px, ACCENT_CYAN, HORIZONTAL_ALIGNMENT_LEFT)


static func _rule(color: Color, h: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, h)
	return r


static func _badge(text: String, px: int) -> Control:
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT_GOLD, 0.12)
	sb.set_border_width_all(1)
	sb.border_color = Color(ACCENT_GOLD, 0.7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", sb)
	badge.add_child(_label(text, px, ACCENT_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	return badge


static func _accent_of(p: Dictionary) -> Color:
	var a = p.get("accent")
	return a if a is Color else ACCENT_CYAN


static func _spec(format_id: String) -> Dictionary:
	for f in FORMATS:
		if str(f["id"]) == format_id:
			return f
	return FORMATS[0]


static func _theme() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	font.font_weight = 700
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 24
	return th


# Traduction depuis un contexte STATIQUE (pas de `tr()` hors Node) — cf. piège §8.104.
static func _t(key: String) -> String:
	return TranslationServer.translate(key)


# =========================================================
# RÉSUMÉ TEXTE (presse-papiers)
# =========================================================
# À la place d'une image (impossible à copier en Godot 4, décision n° 3) : une phrase collable
# telle quelle dans un tweet / un chat, qui porte le verdict, la faction, la durée, les chiffres
# marquants — et l'adresse du site.
static func clipboard_summary(p: Dictionary) -> String:
	var tpl := _t("SHARE_CLIPBOARD_SUMMARY")
	# Clé absente (CSV non régénéré) → `translate` renvoie la clé : on n'écrit pas
	# « SHARE_CLIPBOARD_SUMMARY » dans le presse-papiers du joueur.
	if tpl == "SHARE_CLIPBOARD_SUMMARY" or tpl.find("{verdict}") < 0:
		tpl = "⚔ {verdict} — {faction} · {duration} · {kills} kills, {betrayals} ✸. {site}"
	return tpl.format({
		"verdict": str(p.get("verdict", "")).to_upper(),
		"faction": str(p.get("faction_name", "")),
		"duration": str(p.get("duration", "—")),
		"kills": str(int(p.get("kills", 0))),
		"conquests": str(int(p.get("conquests", 0))),
		"betrayals": str(int(p.get("betrayals", 0))),
		"site": SITE,
	})


# =========================================================
# EXPORT (instance — a besoin de l'arbre pour rendre)
# =========================================================
# Rend les DEUX formats et les écrit dans `user://captures`. Renvoie la liste des chemins
# RÉELLEMENT écrits (vide = échec complet : l'appelant affiche alors une erreur au lieu d'un
# « 2 images enregistrées » mensonger).
#
# Performance (contrainte du cahier des charges) : rien n'est construit tant que le joueur n'a pas
# cliqué, et chaque SubViewport est LIBÉRÉ dès son PNG écrit — aucune ressource ne reste en vie
# après l'export.
func export_pngs(payload: Dictionary) -> Array:
	var saved: Array = []
	if DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) != OK \
			and not DirAccess.dir_exists_absolute(CAPTURE_DIR):
		return saved
	var stamp := _stamp()
	for spec in FORMATS:
		var path := "%s/ww_%s_%s.png" % [CAPTURE_DIR, stamp, str(spec["id"])]
		if await _render_to_png(payload, spec, path):
			saved.append(path)
	return saved


# Horodatage de nom de fichier : `AAAAMMJJ_HHMMSS` (trié naturellement dans l'explorateur).
func _stamp() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [d["year"], d["month"], d["day"],
		d["hour"], d["minute"], d["second"]]


func _render_to_png(payload: Dictionary, spec: Dictionary, path: String) -> bool:
	# Pilote « headless » (validation CLI) : le viewport ne dessine rien → on n'écrit PAS un PNG
	# noir. Un boot headless ne peut donc pas prouver la carte : cf. tools/preview_share_card.tscn
	# (lancement FENÊTRÉ), même recette que preview_report (§8.100).
	if DisplayServer.get_name() == "headless":
		return false
	var vp := SubViewport.new()
	vp.size = spec["size"]
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var content := compose(payload, str(spec["id"]))
	# ⚠️ On ne force PAS `content.size` ici : la composition est ancrée en PLEIN CADRE, donc le
	# SubViewport la dimensionne lui-même. Forcer la taille sur un nœud à ancres opposées non égales
	# déclenche « Nodes with non-equal opposite anchors will have their size overridden » et la
	# valeur posée est de toute façon écrasée au frame suivant.
	vp.add_child(content)
	add_child(vp)
	# DEUX frames à dessein : la première laisse les conteneurs résoudre leur mise en page (sans
	# quoi tout est empilé en (0,0) sur l'image), la seconde dessine réellement. `UPDATE_ONCE` est
	# réarmé juste avant chaque attente — il se remet seul sur DISABLED après le rendu.
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var ok := false
	var tex := vp.get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			ok = img.save_png(path) == OK
	vp.queue_free()
	return ok


# Chemin ABSOLU du dossier des captures (pour `OS.shell_open`).
static func captures_dir_absolute() -> String:
	return ProjectSettings.globalize_path(CAPTURE_DIR)
