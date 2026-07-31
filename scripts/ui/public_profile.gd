extends Control

# =========================================================================
# Profil PUBLIC d'un autre opérateur (§8.107) — charte « Warzone Command » §2
# =========================================================================
# Écran NEUF, atteignable UNIQUEMENT en cliquant une ligne du Classement (demande produit).
# Règle d'Or §6.1 : VUE PURE — le serveur calcule, le client formate.
#
# ⚠️ FRONTIÈRE DE CONFIDENTIALITÉ. Cet écran affiche un PALMARÈS, pas un compte : ni solde, ni
# transactions, ni Pass. Ce n'est pas seulement une omission d'affichage — le serveur ne renvoie
# JAMAIS ces données pour un tiers (`PublicProfileResponse` est une liste blanche explicite, et
# /profile/finance comme /profile/pass ne lisent QUE l'utilisateur authentifié). Ne JAMAIS ajouter
# ici un appel à ces deux routes « pour compléter l'écran » : elles répondraient avec VOS données,
# affichées sous le nom de quelqu'un d'autre.
#
# ÉCRAN SÉPARÉ de `profile.tscn`, volontairement : l'écran Profil personnel est validé et ne doit
# pas être modifié pour accueillir un mode « public ». Les fabriques de style sont donc dupliquées
# ici — c'est la convention du dépôt (profile.gd, shop.gd, leaderboard.gd ont chacun les leurs).

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var header_slot: HBoxContainer
@export var content_box: VBoxContainer
@export var status_label: Label

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const TopNav = preload("res://scripts/ui/top_nav.gd")
# §8.126 — emblèmes + écran Compagnie (porteur du `static var target_tag`).
const CompanyEmblems = preload("res://scripts/ui/company_emblems.gd")
const CompanyScreen = preload("res://scripts/ui/company_screen.gd")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1)

# Miroirs EXACTS de profile.gd / leaderboard.gd (même rang → même couleur partout dans le jeu).
const DIVISION_COLORS := {
	"BRONZE": Color("cd7f32"),
	"ARGENT": Color("c0c0c0"),
	"OR": Color(0.878431, 0.698039, 0.286275, 1),
	"PLATINE": Color("9adfea"),
	"ELITE": Color(0.211765, 0.772549, 0.85098, 1),
}
# Seule ÉLITE a une clé i18n (id ASCII vs rendu accentué) — les autres s'affichent tels quels.
const DIVISION_LABELS := {"ELITE": "DIVISION_ELITE"}
const MAP_LABELS := {
	"classic_42": "MAP_CLASSIC_LABEL",
	"skirmish_atlantic": "MAP_ATLANTIC_LABEL",
}

const FACTIONS_DIR := "res://resources/factions/"
const FALLBACK_PATHS := [
	"res://resources/factions/phalangistes.tres",
	"res://resources/factions/nomades.tres",
	"res://resources/factions/rad_hunters.tres",
	"res://resources/factions/barons_ferraille.tres",
	"res://resources/factions/gardiens_eden.tres",
	"res://resources/factions/corporation_aegis.tres",
	"res://resources/factions/ecorcheurs_cendres.tres",
	"res://resources/factions/eveilles_ruche.tres",
	"res://resources/factions/ordre_eclipse.tres",
	"res://resources/factions/chasseurs_ombres.tres",
]

# Pseudo de l'opérateur à afficher, posé par l'écran APPELANT (le Classement) JUSTE AVANT le
# changement de scène. `static var` plutôt qu'un autoload : `TransitionManager.change_scene` ne
# transporte aucun paramètre, et un porteur statique sur CE script évite d'ajouter un champ
# étranger à un autoload existant (aucune modification de l'existant).
static var target_username: String = ""

var _data: Dictionary = {}
var _username: String = ""
var _factions: Dictionary = {}
var _font: SystemFont


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Nav PARTAGÉE : onglet CLASSEMENT actif — c'est de là qu'on vient, et c'est le seul accès.
	# ⚠️ active_tab réglé AVANT add_child (lu au _ready du composant).
	var nav := TopNav.new()
	nav.active_tab = "leaderboard"
	add_child(nav)
	AudioManager.start_menu_ambient()

	WarzoneUI.animate_screen_enter(self)
	WarzoneUI.add_corner_notches(panel)
	_load_factions()

	_username = str(target_username)
	NetworkManager.public_profile_loaded.connect(_on_public_profile_loaded)
	LocaleManager.locale_changed.connect(func(_code: String) -> void: _render())

	if _username == "":
		# Aucun pseudo transmis (accès direct à la scène) : état honnête, pas de requête inutile.
		_set_status(tr("PUBLIC_PROFILE_NOT_FOUND"))
		_render()
		return
	_render()
	_set_status(tr("COMMON_SYNCING"))
	NetworkManager.fetch_public_profile(_username)


func _on_public_profile_loaded(data: Dictionary, username: String) -> void:
	# Réponse d'une AUTRE demande (l'opérateur peut enchaîner deux lignes du classement) : ignorée.
	if str(username) != _username:
		return
	_data = data
	_render()
	_set_status(tr("PROFILE_STATUS_LOADED") if not data.is_empty()
		else tr("PUBLIC_PROFILE_NOT_FOUND"))


# =========================================================
# RENDU
# =========================================================
func _render() -> void:
	_build_header()
	_build_content()


func _build_header() -> void:
	if header_slot == null:
		return
	_clear(header_slot)

	# --- Gauche : identité (pseudo + niveau) ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	header_slot.add_child(left)
	left.add_child(_eyebrow(tr("PUBLIC_PROFILE_EYEBROW")))
	var name_label := _mini(str(_data.get("username", _username)).to_upper(), 34, TEXT)
	left.add_child(name_label)
	var lvl := HBoxContainer.new()
	lvl.add_theme_constant_override("separation", 8)
	left.add_child(lvl)
	lvl.add_child(_mini(tr("COMMON_LEVEL"), 16, ACCENT))
	lvl.add_child(_mini(str(int(_data.get("level", 1))), 20, GOLD))

	# --- COMPAGNIE (§8.126) : ligne CLIQUABLE vers la fiche publique de la compagnie. -------------
	# L'appartenance est publique par construction (le tag préfixe déjà ce pseudo partout, jusque
	# dans le kill feed d'un inconnu) — l'afficher ici ne divulgue rien de neuf, et rend enfin
	# consultable ce que tout le monde voyait déjà passer.
	# Absente d'un serveur non redéployé → aucune ligne (jamais un « — COMPAGNIE : AUCUNE — » qui
	# affirmerait à tort que ce joueur n'en a pas).
	var company = _data.get("company")
	if typeof(company) == TYPE_DICTIONARY and str(company.get("tag", "")) != "":
		var tag := str(company["tag"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		line.tooltip_text = tr("COMPANY_VIEW_TOOLTIP")
		line.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_company(tag))
		left.add_child(line)
		line.add_child(CompanyEmblems.make_badge(int(company.get("emblem_id", 0)), 26.0, _font))
		line.add_child(_mini("[%s]" % tag, 15, ACCENT))
		line.add_child(_mini(str(company.get("name", "")).to_upper(), 15, TEXT))

	# Retour explicite vers le Classement (seul accès à cet écran).
	var back := Button.new()
	back.text = tr("PUBLIC_PROFILE_BACK")
	back.add_theme_font_override("font", _font)
	back.add_theme_font_size_override("font_size", 14)
	back.custom_minimum_size = Vector2(260, 38)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	WarzoneUI.apply_ghost_button(back)
	WarzoneUI.wire_button_feedback(back)
	back.pressed.connect(func() -> void:
		TransitionManager.change_scene("res://scenes/ui/leaderboard.tscn"))
	left.add_child(back)

	# --- Droite : carte DIVISION (mêmes règles de rendu que le profil personnel) ---
	var season = _data.get("season", {})
	if typeof(season) != TYPE_DICTIONARY or str(season.get("division", "")) == "":
		return
	var division := str(season.get("division", ""))
	var accent: Color = DIVISION_COLORS.get(division, MUTED)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(accent))
	card.custom_minimum_size = Vector2(360, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	header_slot.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	v.add_child(_eyebrow(tr("PROFILE_STAT_DIVISION")))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	top.add_child(WarzoneUI.make_hex_badge(
		_division_name(division).substr(0, 1), _font, 20, accent, GUNMETAL, 52))
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 0)
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(labels)
	labels.add_child(_mini(_division_label(division, str(season.get("tier", ""))), 24, accent))
	labels.add_child(_mini(tr("PROFILE_RP_FORMAT")
		% _format_thousands(int(season.get("rp", 0))), 15, GOLD))

	var rank := int(season.get("global_rank", 0))
	v.add_child(_mini(tr("PROFILE_GLOBAL_RANK") + "  "
		+ ("#" + _format_thousands(rank) if rank > 0 else "—"), 14,
		TEXT if rank > 0 else MUTED))


# §8.126 — ouvre la fiche PUBLIQUE d'une compagnie. Même mécanique de passage de paramètre que
# l'accès à CET écran depuis le Classement (§8.107) : un `static var` sur le script cible, parce que
# `TransitionManager.change_scene` ne transporte rien. Routé par TAG, jamais par id : aucun
# identifiant séquentiel énumérable ne sort du serveur.
func _open_company(tag: String) -> void:
	AudioManager.play_sfx("click")
	CompanyScreen.target_tag = tag
	TransitionManager.change_scene("res://scenes/ui/company_screen.tscn")


func _build_content() -> void:
	if content_box == null:
		return
	_clear(content_box)

	if _data.is_empty():
		content_box.add_child(_muted_note(tr("PUBLIC_PROFILE_NOT_FOUND")))
		return

	# --- Palmarès ---
	content_box.add_child(_eyebrow(tr("PROFILE_STATS_HEADER")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(grid)

	var games := int(_data.get("games_played", 0))
	var wins := int(_data.get("wins", 0))
	var losses := int(_data.get("losses", 0))
	var ratio := 0
	if wins + losses > 0:
		ratio = int(round(100.0 * float(wins) / float(wins + losses)))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_GAMES"), str(games), TEXT))
	grid.add_child(_make_stat_card(tr("COMMON_WINS"), str(wins), GOLD))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_LOSSES"), str(losses), DANGER))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_RATIO"), "%d%%" % ratio, ACCENT))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_TOLL"),
		_format_thousands(int(_data.get("heaviest_toll", 0))), MUTED))
	var fav := str(_data.get("favorite_faction", ""))
	var fav_info: Dictionary = _factions.get(fav, {})
	grid.add_child(_make_stat_card(tr("PROFILE_FAVORITE_FACTION"),
		str(fav_info.get("name", fav)).to_upper() if fav != "" else "—",
		fav_info.get("color", ACCENT) if not fav_info.is_empty() else MUTED))
	# §8.123 — PACTES ROMPUS : donnée PUBLIQUE par construction, et c'est toute sa raison d'être —
	# une réputation ne sert à rien si personne ne peut la consulter. Carte NEUTRE (teinte muette,
	# libellé factuel) : le jeu compte, il ne juge pas. Masquée à 0 : ne rien afficher vaut mieux
	# qu'un compteur qu'on ne saurait pas distinguer d'un serveur non redéployé.
	var broken := int(_data.get("pacts_broken", 0))
	if broken > 0:
		grid.add_child(_make_stat_card(tr("PROFILE_PACTS_BROKEN"), str(broken), MUTED))

	# --- Bande de forme ---
	var form = _data.get("form", [])
	if typeof(form) == TYPE_ARRAY and not form.is_empty():
		content_box.add_child(_spacer(8))
		content_box.add_child(_eyebrow(tr("PROFILE_FORM_TITLE")))
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 5)
		content_box.add_child(strip)
		# Plus RÉCENT à droite (le serveur renvoie du plus récent au plus ancien).
		for i in range(form.size() - 1, -1, -1):
			var e = form[i]
			if typeof(e) == TYPE_DICTIONARY:
				strip.add_child(_make_form_square(bool(e.get("win", false)),
					bool(e.get("is_ranked", false))))

	# --- Par mode ---
	var modes = _data.get("modes", {})
	if typeof(modes) == TYPE_DICTIONARY and not modes.is_empty():
		content_box.add_child(_spacer(8))
		content_box.add_child(_eyebrow(tr("PROFILE_STATS_BY_MODE")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		content_box.add_child(row)
		row.add_child(_make_mode_card(tr("PROFILE_MODE_RANKED"),
			modes.get("ranked", {}), GOLD, true))
		row.add_child(_make_mode_card(tr("PROFILE_MODE_CASUAL"),
			modes.get("casual", {}), ACCENT, false))

	# --- Par personnage ---
	var factions = _data.get("factions", [])
	if typeof(factions) == TYPE_ARRAY and not factions.is_empty():
		content_box.add_child(_spacer(8))
		content_box.add_child(_eyebrow(tr("PROFILE_STATS_BY_HERO")))
		for f in factions:
			if typeof(f) == TYPE_DICTIONARY:
				content_box.add_child(_make_faction_row(f))

	# --- Par carte (§8.107) ---
	var maps = _data.get("maps", [])
	if typeof(maps) == TYPE_ARRAY and not maps.is_empty():
		content_box.add_child(_spacer(8))
		content_box.add_child(_eyebrow(tr("PROFILE_STATS_BY_MAP")))
		for m in maps:
			if typeof(m) == TYPE_DICTIONARY:
				content_box.add_child(_make_map_row(m))
		content_box.add_child(_muted_note(tr("PROFILE_MAP_LEGACY_NOTE")))


# =========================================================
# FABRIQUES (charte §2)
# =========================================================
func _make_faction_row(e: Dictionary) -> PanelContainer:
	var fid := str(e.get("faction_id", ""))
	var info: Dictionary = _factions.get(fid, {})
	var color: Color = info.get("color", ACCENT) if not info.is_empty() else ACCENT

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(color))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 2)
	h.add_child(left)
	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", 8)
	left.add_child(name_line)
	name_line.add_child(_make_dot(color))
	name_line.add_child(_mini(str(info.get("name", fid)).to_upper(), 16, TEXT))
	left.add_child(_mini(tr("PROFILE_HERO_LEVEL_FMT") % int(e.get("hero_level", 1)), 12, MUTED))

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	h.add_child(center)
	center.add_child(_mini(tr("PROFILE_GAMES_WL_FMT")
		% [int(e.get("games", 0)), int(e.get("wins", 0)), int(e.get("losses", 0))], 13, MUTED))
	var wr := int(e.get("winrate", 0))
	var wr_line := HBoxContainer.new()
	wr_line.add_theme_constant_override("separation", 10)
	center.add_child(wr_line)
	var bar := _make_ratio_bar(wr, GOLD)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wr_line.add_child(bar)
	wr_line.add_child(_mini("%d%%" % wr, 15, GOLD))

	var avg := int(e.get("avg_rank_x10", 0))
	h.add_child(_make_metric(tr("PROFILE_AVG_RANK"),
		("%.1f" % (avg / 10.0)) if avg > 0 else "—", TEXT if avg > 0 else MUTED))
	return row


func _make_map_row(e: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(ACCENT))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	var mid := str(e.get("map_id", ""))
	var label := tr(str(MAP_LABELS[mid])) if MAP_LABELS.has(mid) else mid
	var left := _mini(label.to_upper(), 16, TEXT)
	left.custom_minimum_size = Vector2(250, 0)
	h.add_child(left)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	h.add_child(center)
	center.add_child(_mini(tr("PROFILE_GAMES_WL_FMT")
		% [int(e.get("games", 0)), int(e.get("wins", 0)), int(e.get("losses", 0))], 13, MUTED))
	var wr := int(e.get("winrate", 0))
	var wr_line := HBoxContainer.new()
	wr_line.add_theme_constant_override("separation", 10)
	center.add_child(wr_line)
	var bar := _make_ratio_bar(wr, GOLD)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wr_line.add_child(bar)
	wr_line.add_child(_mini("%d%%" % wr, 15, GOLD))

	var avg := int(e.get("avg_rank_x10", 0))
	h.add_child(_make_metric(tr("PROFILE_AVG_RANK"),
		("%.1f" % (avg / 10.0)) if avg > 0 else "—", TEXT if avg > 0 else MUTED))
	return row


func _make_mode_card(title: String, data, accent: Color, show_rp: bool) -> PanelContainer:
	var d: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var eb := _eyebrow(title)
	eb.add_theme_color_override("font_color", accent)
	v.add_child(eb)

	var games := int(d.get("games", 0))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 24)
	v.add_child(line)
	line.add_child(_make_metric(tr("PROFILE_STAT_GAMES"), str(games), TEXT))
	line.add_child(_make_metric(tr("COMMON_WINS"), str(int(d.get("wins", 0))), GOLD))
	if show_rp:
		var rp_net := int(d.get("rp_net", 0))
		line.add_child(_make_metric(tr("PROFILE_RP_NET"),
			_signed(rp_net) if games > 0 else "—",
			GOLD if rp_net > 0 else (DANGER if rp_net < 0 else MUTED)))

	var wr := int(d.get("winrate", 0))
	var wr_line := HBoxContainer.new()
	wr_line.add_theme_constant_override("separation", 10)
	v.add_child(wr_line)
	var bar := _make_ratio_bar(wr, accent)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wr_line.add_child(bar)
	wr_line.add_child(_mini("%d%%" % wr, 15, accent))
	WarzoneUI.add_corner_notches(card)
	return card


func _make_form_square(win: bool, is_ranked: bool) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(18, 18)
	box.tooltip_text = (tr("PROFILE_RESULT_VICTORY") if win else tr("PROFILE_RESULT_DEFEAT")) \
		+ ("  ·  " + tr("PROFILE_MODE_RANKED") if is_ranked else "")
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = GOLD if win else DANGER
	if is_ranked:
		sb.set_border_width_all(1)
		sb.border_color = ACCENT
	box.add_theme_stylebox_override("panel", sb)
	return box


func _make_stat_card(label: String, value: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(value_color))
	card.custom_minimum_size = Vector2(175, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(_eyebrow(label))
	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", _font)
	val.add_theme_font_size_override("font_size", 30)
	val.add_theme_color_override("font_color", value_color)
	v.add_child(val)
	WarzoneUI.add_corner_notches(card)
	return card


func _make_metric(label: String, value: String, color: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.custom_minimum_size = Vector2(92, 0)
	v.add_child(_mini(label, 11, MUTED))
	v.add_child(_mini(value, 16, color))
	return v


func _make_dot(color: Color) -> PanelContainer:
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = color
	dot.add_theme_stylebox_override("panel", sb)
	return dot


func _make_ratio_bar(percent: int, color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 8)
	pb.min_value = 0
	pb.max_value = 100
	pb.value = clampi(percent, 0, 100)
	pb.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = SURFACE
	bg.set_corner_radius_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(0)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


func _make_card_style(accent: Color = ACCENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.border_width_left = 3
	sb.border_color = accent
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	return sb


func _eyebrow(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ACCENT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _mini(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _muted_note(text: String) -> Label:
	var l := _mini(text, 13, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


# =========================================================
# UTILITAIRES (miroirs de profile.gd / leaderboard.gd)
# =========================================================
func _division_name(division: String) -> String:
	if DIVISION_LABELS.has(division):
		return tr(str(DIVISION_LABELS[division]))
	return division


func _division_label(division: String, tier: String) -> String:
	if division == "":
		return "—"
	if tier == "":
		return _division_name(division)
	return tr("DIVISION_TIER_FMT").format({"division": _division_name(division), "tier": tier})


func _signed(v: int) -> String:
	return ("+" + _format_thousands(v)) if v > 0 else ("-" + _format_thousands(absi(v)) if v < 0 else "0")


func _format_thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	if value < 0:
		out = "-" + out
	return out


func _load_factions() -> void:
	var paths := _scan_faction_paths()
	if paths.is_empty():
		paths = FALLBACK_PATHS.duplicate()
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		if res != null and res.get("id") != null:
			_factions[str(res.id)] = {
				"name": str(res.get("name")),
				"color": res.get("accent_color") if res.get("accent_color") != null else ACCENT,
			}


func _scan_faction_paths() -> Array:
	var out := []
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var fn := file_name
			if fn.ends_with(".remap"):
				fn = fn.trim_suffix(".remap")
			if fn.ends_with(".tres"):
				var full := FACTIONS_DIR + fn
				if not out.has(full):
					out.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
