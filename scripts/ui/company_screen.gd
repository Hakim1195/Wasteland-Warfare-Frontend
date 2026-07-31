extends Control

# =========================================================================
# ÉCRAN COMPAGNIE (§8.126) — charte « Warzone Command » §2
# =========================================================================
# La COMPAGNIE est la MAISON du joueur : un tag de 4 lettres qui préfixe son pseudo partout, un nom,
# un emblème, un roster de 20 et un classement inter-compagnies saisonnier.
#
# ⚠️ NE PAS CONFONDRE AVEC L'ESCOUADE (`squad_screen`, §8.124-125). L'escouade est l'objet de MISE
# EN FILE : éphémère, elle meurt avec la partie. La compagnie est une IDENTITÉ persistante et **ne
# se met JAMAIS en file** — aucun bouton de cet écran ne parle de matchmaking, et c'est volontaire.
#
# UN SEUL ÉCRAN, DEUX MODES (décision de conception) :
#   • `target_tag == ""` → MA compagnie (`GET /company/mine`) : code, actions de chef, quitter…
#   • `target_tag != ""` → fiche PUBLIQUE d'une autre (`GET /company/{tag}`) : ni code, ni actions.
# Deux scènes auraient dupliqué l'en-tête, le panneau d'honneur et le roster — donc trois occasions
# de les laisser diverger. Le mode public retire des éléments, il n'en réinvente aucun.
#
# Écran CODE-DRIVEN (patron `squad_screen` / `salon_screen`) : la scène .tscn est un Control racine
# nu, toute la hiérarchie est bâtie ici. Règle d'Or §6.1 : VUE pure — tout passe par NetworkManager.

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const Emblems = preload("res://scripts/ui/company_emblems.gd")
const BG_TEXTURE := preload("res://assets/images/bg_wasteland.png")
const TopNav = preload("res://scripts/ui/top_nav.gd")

# --- Palette canonique (§2, miroir squad_screen.gd / profile.gd) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)

# Miroir EXACT de profile.gd / leaderboard.gd — même rang, même couleur partout dans le jeu.
const DIVISION_COLORS := {
	"BRONZE": Color("cd7f32"),
	"ARGENT": Color("c0c0c0"),
	"OR": Color(0.878431, 0.698039, 0.286275, 1),
	"PLATINE": Color("9adfea"),
	"ELITE": Color(0.211765, 0.772549, 0.85098, 1),
}

const COPY_FLASH_DURATION := 1.6
# Débounce de la vérification LIVE du tag : 0,5 s après la dernière frappe. Interroger le serveur à
# CHAQUE caractère inonderait l'API pour un résultat qu'on jette aussitôt.
const TAG_CHECK_DEBOUNCE := 0.5
# Largeur de la colonne de droite. 340 px : de quoi lire un pseudo entier + son état sans troncature
# (« EN PARTIE » est le libellé le plus long), sans rogner la colonne de gestion.
const SIDE_PANEL_W := 340.0
# Activités affichées dans le panneau. 6 : ce qui tient sans faire défiler — le journal complet
# n'est pas l'objet, le signal « il s'est passé quelque chose » l'est.
const SIDE_EVENTS := 6

# Tag de la compagnie à consulter, posé par l'écran APPELANT juste avant le changement de scène.
# `static var` plutôt qu'un autoload : `TransitionManager.change_scene` ne transporte aucun
# paramètre, et cette voie n'ajoute aucun champ étranger à un autoload existant (même mécanique que
# `public_profile.target_username`, §8.107).
# ⚠️ REMIS À "" par `_ready` dès qu'il est lu : sans ça, revenir sur SA compagnie après avoir
# consulté celle d'un autre rouvrirait la fiche publique de l'autre.
static var target_tag: String = ""

var _font: SystemFont

# --- Nœuds bâtis en code ---
var _panel: PanelContainer
var _root: VBoxContainer
var _content: VBoxContainer
# Colonne de DROITE (§8.126.1) : résumé + qui est en ligne + activité récente.
var _side: VBoxContainer
var _status_label: Label
var _copy_button: Button = null
var _copy_flash_timer: Timer = null
var _tag_debounce: Timer = null

# --- État ---
var _company: Dictionary = {}       # fiche courante ({} = aucune)
var _rules: Dictionary = {}         # REGISTRE serveur — aucune valeur en dur ici
var _reason: String = ""            # dernier discriminant serveur (convention zéro-4xx §8.112)
var _cooldown_s: int = 0
var _public_tag: String = ""        # "" = ma compagnie ; sinon fiche publique consultée
var _view: String = "main"          # "main" | "create" | "join"
# Brouillon du formulaire de création — CONSERVÉ entre deux rendus : un refus serveur ne doit
# JAMAIS vider ce que le joueur vient de taper (contre-épreuve comportementale §8.125).
var _draft_tag: String = ""
var _draft_name: String = ""
var _draft_emblem: int = 0
var _tag_check: Dictionary = {}     # dernière réponse de /company/check_tag
var _seen_sent: bool = false        # accusé de lecture des activités : UNE fois par visite


func _ready() -> void:
	_font = _make_font()
	# Lecture PUIS purge immédiate du porteur statique (cf. sa déclaration).
	_public_tag = str(target_tag)
	target_tag = ""

	WarzoneUI.animate_screen_enter(self)
	# ⚠️ LA COQUILLE D'ABORD, LA NAV ENSUITE — et l'ordre est un vrai piège, pas une préférence.
	# Cet écran est CODE-DRIVEN : son fond plein écran est un enfant ajouté par `_build_shell`. Or
	# les Control se dessinent dans l'ORDRE DE L'ARBRE — une nav ajoutée avant le fond disparaît
	# DERRIÈRE lui (défaut constaté en capture PNG : barre de navigation totalement absente, alors
	# que le boot headless annonçait 0 ERROR). Les écrans à `.tscn` (profile, leaderboard) n'ont pas
	# ce souci : leur fond vit dans la scène, donc avant tout ce que le script ajoute.
	_build_shell()

	# Nav PARTAGÉE (§8.94). §8.126.1 : la section a désormais SON onglet — il doit donc se surligner
	# lui-même. Tant qu'il n'existait pas, l'écran empruntait celui du Profil ; le laisser aurait
	# affiché « PROFIL » actif alors qu'on est sur COMPAGNIE (défaut vu en capture).
	# ⚠️ active_tab réglé AVANT add_child (lu au _ready du composant).
	var nav := TopNav.new()
	nav.active_tab = "company"
	add_child(nav)
	AudioManager.start_menu_ambient()

	NetworkManager.company_state_received.connect(_on_company_state)
	NetworkManager.company_public_loaded.connect(_on_company_public)
	NetworkManager.company_tag_checked.connect(_on_tag_checked)
	NetworkManager.session_expired.connect(_on_session_expired)
	LocaleManager.locale_changed.connect(func(_code: String) -> void: _render())

	_set_status(tr("COMMON_SYNCING"), MUTED)
	if _public_tag != "":
		NetworkManager.company_public(_public_tag)
	else:
		NetworkManager.company_mine()
	_render()


func _make_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


func _is_public() -> bool:
	return _public_tag != ""


func _is_leader() -> bool:
	return not _is_public() and bool(_company.get("is_leader", false))


# =========================================================
# COQUILLE (bâtie UNE fois ; seul `_content` est reconstruit)
# =========================================================
func _build_shell() -> void:
	var bg := TextureRect.new()
	bg.texture = BG_TEXTURE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 100.0   # sous la nav partagée
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(1300, 700)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(GUNMETAL, 0.92)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = Color(ACCENT, 0.7)
	st.set_content_margin_all(32.0)
	_panel.add_theme_stylebox_override("panel", st)
	center.add_child(_panel)
	WarzoneUI.add_corner_notches(_panel)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 14)
	_panel.add_child(_root)

	# Corps en DEUX COLONNES : la gestion à gauche, le RÉSUMÉ VIVANT à droite. La colonne de droite
	# répond à une question différente de celle de gauche — « qui est là, et qu'est-ce que j'ai
	# manqué ? » plutôt que « comment j'administre ». Les mélanger aurait noyé la première, qui est
	# pourtant celle qu'on vient consulter tous les jours.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(body)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content)

	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 12)
	_side.custom_minimum_size = Vector2(SIDE_PANEL_W, 0)
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.visible = false
	body.add_child(_side)

	WarzoneUI.add_filet(_root)

	_status_label = Label.new()
	_status_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_status_label.add_theme_font_override("font", _font)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_status_label)


# =========================================================
# RENDU — trois visages : fiche, création, adhésion
# =========================================================
func _render() -> void:
	_clear(_content)
	_copy_button = null
	_render_side()
	if _view == "create":
		_build_create_form()
		return
	if _view == "join":
		_build_join_form()
		return
	if _company.is_empty():
		_build_no_company()
		return
	_build_company_view()


# --- Sans compagnie : la porte d'entrée (CRÉER / REJOINDRE) + le panneau explicatif -------------
func _build_no_company() -> void:
	if _is_public():
		# Fiche publique introuvable (compagnie dissoute entre le clic et la réponse).
		_content.add_child(_center_note(tr("COMPANY_NOT_FOUND"), MUTED, 18))
		_content.add_child(_spacer(10))
		_content.add_child(_ghost_button(tr("COMMON_BACK"), _on_back_pressed, 200))
		return

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	_content.add_child(head)
	head.add_child(_label(tr("COMPANY_NONE"), 30, TEXT))
	# Panneau explicatif = modal calqué sur le Classement (référence maison actée §8.125).
	head.add_child(WarzoneUI.make_info_badge(self, tr("COMPANY_EXPLAIN_TITLE"),
		tr("COMPANY_EXPLAIN_BODY"), _font, 24.0))

	_content.add_child(_center_note(tr("COMPANY_NONE_HINT"), MUTED, 15))
	_content.add_child(_spacer(14))

	# Cooldown de réadhésion en cours : on le dit AVANT que le joueur ne clique sur un bouton qui
	# refusera. Un refus qu'on pouvait annoncer est un refus de trop.
	if _cooldown_s > 0:
		_content.add_child(_center_note(
			tr("COMPANY_COOLDOWN_NOTICE") % _format_duration(_cooldown_s), GOLD, 15))
		_content.add_child(_spacer(8))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_content.add_child(row)
	row.add_child(_cta_button(tr("COMPANY_CREATE"), _on_create_view_pressed, 250))
	row.add_child(_ghost_button(tr("COMPANY_JOIN"), _on_join_view_pressed, 250))


# --- Fiche : en-tête, panneau d'honneur, roster, actions ----------------------------------------
func _build_company_view() -> void:
	var tag := str(_company.get("tag", ""))
	var emblem := int(_company.get("emblem_id", 0))

	# EN-TÊTE : emblème + [TAG] nom + rang inter-compagnies.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	_content.add_child(head)
	head.add_child(Emblems.make_badge(emblem, 84.0, _font))

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 2)
	head.add_child(titles)
	titles.add_child(_label("[%s]" % tag, 20, ACCENT))
	titles.add_child(_label(str(_company.get("name", "")).to_upper(), 32, TEXT))
	var rank := int(_company.get("rank", 0))
	if rank > 0:
		titles.add_child(_label(tr("COMPANY_RANK_LABEL") % rank, 14, GOLD))

	if not _is_public():
		head.add_child(_build_code_block())

	WarzoneUI.add_filet(_content)

	# PANNEAU D'HONNEUR (§1.5) — trois mesures, pas une de plus tant que l'adoption n'est pas mesurée.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	var top_n := int(_rules.get("score_top_n", 10))
	grid.add_child(_stat_card(tr("COMPANY_SCORE_LABEL") % top_n,
		_format_thousands(int(_company.get("season_score", 0))), GOLD))
	grid.add_child(_stat_card(tr("COMPANY_WINS_LABEL"),
		str(int(_company.get("season_wins", 0))), TEXT))
	var avg := str(_company.get("avg_division", ""))
	grid.add_child(_stat_card(tr("COMPANY_AVG_DIVISION"),
		str(_company.get("avg_division_label", "—")),
		DIVISION_COLORS.get(avg, MUTED)))

	WarzoneUI.add_filet(_content)

	# ROSTER.
	var members: Array = _company.get("members", [])
	var cap := int(_rules.get("roster_cap", 20))
	var header := _label("%s  %d/%d" % [tr("COMPANY_ROSTER"), members.size(), cap], 15, ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_content.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for m in members:
		if typeof(m) == TYPE_DICTIONARY:
			list.add_child(_member_row(m))

	# ACTIONS — aucune en mode public (on ne gouverne pas la maison des autres).
	WarzoneUI.add_filet(_content)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_content.add_child(actions)
	if _is_public():
		actions.add_child(_ghost_button(tr("COMMON_BACK"), _on_back_pressed, 200))
		return
	if _is_leader():
		actions.add_child(_ghost_button(tr("COMPANY_CODE_REGEN"), _on_regen_pressed, 200))
	actions.add_child(_ghost_button(tr("COMPANY_LEAVE"), _on_leave_pressed, 200, DANGER))


# Bloc CODE (membres seulement) : le code en évidence + COPIER. Même geste et même mot que le salon
# privé et l'escouade — `SALON_COPY` est une clé PARTAGÉE, délibérément.
func _build_code_block() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label(tr("COMPANY_CODE_LABEL"), 12, MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	var code := _label(_spaced(str(_company.get("join_code", ""))), 30, GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(code)
	_copy_button = _ghost_button(tr("SALON_COPY"), _on_copy_pressed, 150)
	_copy_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_copy_button)
	return box


# Une ligne de roster : pseudo, division, ancienneté, libellé CHEF, actions du chef.
func _member_row(m: Dictionary) -> PanelContainer:
	var is_leader_row := bool(m.get("is_leader", false))
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GOLD, 0.10) if is_leader_row else SURFACE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = Color(GOLD, 0.5) if is_leader_row else Color(ACCENT, 0.22)
	sb.set_content_margin_all(8.0)
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	# PRÉSENCE (§8.126.1) — pastille avant le pseudo : pleine et or = en partie, creuse et cyan = au
	# QG, absente = hors ligne. Un ROND ASCII, jamais un pictogramme (tofu avec la police condensée).
	var status := str(m.get("status", "offline"))
	if status != "offline":
		var in_game := status == "in_game"
		var dot := _label("●" if in_game else "○", 13, GOLD if in_game else ACCENT,
			HORIZONTAL_ALIGNMENT_CENTER, 16.0)
		dot.tooltip_text = tr("COMPANY_STATUS_IN_GAME") if in_game else tr("COMPANY_STATUS_ONLINE")
		h.add_child(dot)
	else:
		# Gouttière RÉSERVÉE même hors ligne : sans elle, les pseudos danseraient horizontalement
		# d'un rafraîchissement à l'autre au gré des connexions.
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(16, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(gap)

	var who := _label(str(m.get("name", "—")).to_upper(), 17,
		TEXT if status != "offline" else MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(who)

	# « CHEF » en LIBELLÉ, pas en pictogramme : préférence produit actée §8.125 (aucun emoji
	# décoratif dans l'UI de ce chantier).
	if is_leader_row:
		h.add_child(_label(tr("COMPANY_LEADER_LABEL"), 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 90.0))

	var division := str(m.get("division", ""))
	var div_text := str(m.get("division_label", division))
	# Vue MEMBRE : le RP exact accompagne la division. Vue PUBLIQUE : le serveur renvoie 0 et on
	# n'affiche donc RIEN de plus — ce n'est pas un masquage d'affichage, la donnée n'arrive pas.
	var rp := int(m.get("season_rp", 0))
	if rp > 0:
		div_text += "  ·  %s" % _format_thousands(rp)
	h.add_child(_label(div_text, 14, DIVISION_COLORS.get(division, MUTED),
		HORIZONTAL_ALIGNMENT_RIGHT, 200.0))

	var joined := _short_date(str(m.get("joined_at", "")))
	if joined != "":
		h.add_child(_label(joined, 12, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 100.0))

	# Actions de chef, ligne par ligne — jamais sur sa propre ligne (partir a sa propre route).
	if _is_leader() and not is_leader_row:
		var uid := int(m.get("user_id", 0))
		var who_name := str(m.get("name", ""))
		if uid > 0:
			h.add_child(_mini_action(tr("COMPANY_TRANSFER"),
				func() -> void: _confirm(tr("COMPANY_CONFIRM_TRANSFER") % who_name,
					func() -> void: NetworkManager.company_transfer(uid))))
			h.add_child(_mini_action(tr("COMPANY_KICK"),
				func() -> void: _confirm(tr("COMPANY_CONFIRM_KICK") % who_name,
					func() -> void: NetworkManager.company_kick(uid)), DANGER))
	return row


# =========================================================
# COLONNE DE DROITE (§8.126.1) — résumé vivant de la compagnie
# =========================================================
# Trois blocs, dans l'ordre où on les lit : ce qu'EST la compagnie · qui est LÀ · ce qui s'est PASSÉ.
# Masquée sans compagnie (il n'y aurait rien à résumer) et sur la vue PUBLIQUE (le serveur ne
# renvoie ni présence ni journal pour un clan tiers — et ne doit pas).
func _render_side() -> void:
	if _side == null:
		return
	_clear(_side)
	var show := not _company.is_empty() and not _is_public() and _view == "main"
	_side.visible = show
	if not show:
		return

	_side.add_child(_side_card_summary())
	_side.add_child(_side_card_online())
	_side.add_child(_side_card_activity())


func _side_card(title: String, accent: Color) -> Array:
	"""Carte de colonne : renvoie [PanelContainer, VBoxContainer de contenu]. Fabrique commune —
	trois cartes qui se ressemblent doivent se ressembler par construction, pas par recopie."""
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.border_width_left = 3
	sb.border_color = accent
	sb.set_content_margin_all(12.0)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(_label(title, 12, ACCENT))
	return [card, v]


func _side_card_summary() -> PanelContainer:
	var built := _side_card(tr("COMPANY_SIDE_SUMMARY"), ACCENT)
	var v: VBoxContainer = built[1]

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(Emblems.make_badge(int(_company.get("emblem_id", 0)), 40.0, _font))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	titles.add_child(_label("[%s]" % str(_company.get("tag", "")), 13, ACCENT))
	var name_lbl := _label(str(_company.get("name", "")).to_upper(), 17, TEXT)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(name_lbl)

	v.add_child(_side_row(tr("COMPANY_RANK_EYEBROW"),
		"#%d" % int(_company.get("rank", 0)) if int(_company.get("rank", 0)) > 0 else "—", GOLD))
	v.add_child(_side_row(tr("COMPANY_COL_SCORE"),
		_format_thousands(int(_company.get("season_score", 0))), GOLD))
	v.add_child(_side_row(tr("COMPANY_COL_MEMBERS"),
		"%d/%d" % [int(_company.get("member_count", 0)), int(_rules.get("roster_cap", 20))], TEXT))
	v.add_child(_side_row(tr("COMPANY_AVG_DIVISION"),
		str(_company.get("avg_division_label", "—")),
		DIVISION_COLORS.get(str(_company.get("avg_division", "")), MUTED)))
	return built[0]


func _side_card_online() -> PanelContainer:
	# Les PRÉSENTS d'abord : c'est la raison d'être de ce panneau. Un joueur ouvre sa compagnie pour
	# savoir avec qui jouer MAINTENANT, pas pour relire un palmarès.
	var members: Array = _company.get("members", [])
	var present := []
	for m in members:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("status", "offline")) != "offline":
			present.append(m)

	var built := _side_card("%s  %d/%d" % [tr("COMPANY_ONLINE_TITLE"), present.size(),
		members.size()], ACCENT if present.is_empty() else GOLD)
	var v: VBoxContainer = built[1]
	if present.is_empty():
		v.add_child(_label(tr("COMPANY_ONLINE_NONE"), 13, MUTED))
		return built[0]

	for m in present:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		v.add_child(line)
		var in_game := str(m.get("status", "")) == "in_game"
		# Pastille pleine = en partie (or), creuse = au QG (cyan). Un ROND, pas un pictogramme :
		# tout glyphe hors ASCII rend en tofu avec la police condensée de la charte.
		var dot := _label("●" if in_game else "○", 12, GOLD if in_game else ACCENT)
		dot.custom_minimum_size = Vector2(14, 0)
		line.add_child(dot)
		var who := _label(str(m.get("name", "")).to_upper(), 14, TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(who)
		line.add_child(_label(tr("COMPANY_STATUS_IN_GAME") if in_game
			else tr("COMPANY_STATUS_ONLINE"), 11, GOLD if in_game else MUTED,
			HORIZONTAL_ALIGNMENT_RIGHT))
	return built[0]


func _side_card_activity() -> PanelContainer:
	var events: Array = _company.get("events", [])
	var unread := int(_company.get("unread_events", 0))
	var title := tr("COMPANY_ACTIVITY_TITLE")
	if unread > 0:
		title += "  ●%d" % unread
	var built := _side_card(title, GOLD if unread > 0 else ACCENT)
	var v: VBoxContainer = built[1]
	if events.is_empty():
		v.add_child(_label(tr("COMPANY_ACTIVITY_NONE"), 13, MUTED))
		return built[0]
	for i in min(SIDE_EVENTS, events.size()):
		var e = events[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		# Les `unread` premières lignes sont les NOUVEAUTÉS (le journal est servi du plus récent au
		# plus ancien) : teintées, le reste en muet. Le joueur voit d'un coup d'œil ce qu'il a manqué.
		var fresh: bool = i < unread
		var line := _label(_event_text(e), 12, TEXT if fresh else MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(line)
	return built[0]


func _side_row(label: String, value: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(label, 12, MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(_label(value, 15, color, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


# Phrase d'une activité, COMPOSÉE CÔTÉ CLIENT depuis `kind` + les deux pseudos. Le serveur n'envoie
# jamais de texte affichable (règle R4) : c'est ce qui permet à la même ligne de journal de se lire
# en trois langues sans qu'aucune ne transite par le réseau.
func _event_text(e: Dictionary) -> String:
	var actor := str(e.get("actor", "")).to_upper()
	var target := str(e.get("target", "")).to_upper()
	match str(e.get("kind", "")):
		"created": return tr("COMPANY_EV_CREATED") % actor
		"joined": return tr("COMPANY_EV_JOINED") % actor
		"left": return tr("COMPANY_EV_LEFT") % actor
		"kicked": return tr("COMPANY_EV_KICKED") % [target, actor]
		"transferred": return tr("COMPANY_EV_TRANSFERRED") % [actor, target]
		"renamed": return tr("COMPANY_EV_RENAMED") % [actor, target]
		_: return ""


# --- Formulaire de CRÉATION ---------------------------------------------------------------------
func _build_create_form() -> void:
	_content.add_child(_center_note(tr("COMPANY_CREATE_TITLE"), ACCENT, 24))
	_content.add_child(_spacer(6))

	# TAG — 4 lettres, DÉFINITIF. Le dire ici, pas après coup.
	_content.add_child(_label(tr("COMPANY_TAG_HINT"), 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var tag_input := LineEdit.new()
	tag_input.text = _draft_tag
	tag_input.max_length = int(_rules.get("tag_len", 4))
	tag_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_input.add_theme_font_override("font", _font)
	tag_input.add_theme_font_size_override("font_size", 34)
	tag_input.custom_minimum_size = Vector2(0, 56)
	tag_input.text_changed.connect(_on_tag_typed)
	_content.add_child(tag_input)

	# Verdict LIVE de disponibilité (débounce 0,5 s) — vert/rouge, jamais muet.
	var verdict := _tag_verdict_text()
	_content.add_child(_center_note(verdict["text"], verdict["color"], 13))

	_content.add_child(_spacer(6))
	_content.add_child(_label(tr("COMPANY_NAME_HINT"), 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var name_input := LineEdit.new()
	name_input.text = _draft_name
	name_input.max_length = int(_rules.get("name_max", 24))
	name_input.add_theme_font_override("font", _font)
	name_input.add_theme_font_size_override("font_size", 20)
	name_input.custom_minimum_size = Vector2(0, 44)
	name_input.text_changed.connect(func(t: String) -> void: _draft_name = t)
	_content.add_child(name_input)

	_content.add_child(_spacer(8))
	_content.add_child(_label(tr("COMPANY_EMBLEM_HINT"), 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_content.add_child(_build_emblem_grid(_draft_emblem,
		func(i: int) -> void:
			_draft_emblem = i
			_render()))

	_content.add_child(_spacer(10))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	row.add_child(_cta_button(tr("COMPANY_CREATE_CONFIRM"), _on_create_confirm, 240))
	row.add_child(_ghost_button(tr("COMMON_CANCEL"), _on_form_cancel, 180))


# --- Formulaire d'ADHÉSION ----------------------------------------------------------------------
func _build_join_form() -> void:
	_content.add_child(_center_note(tr("COMPANY_JOIN_TITLE"), ACCENT, 24))
	_content.add_child(_center_note(tr("COMPANY_JOIN_HINT"), MUTED, 14))
	_content.add_child(_spacer(10))

	var input := LineEdit.new()
	input.placeholder_text = tr("SQUAD_CODE_PLACEHOLDER")
	input.max_length = 5
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_override("font", _font)
	input.add_theme_font_size_override("font_size", 34)
	input.custom_minimum_size = Vector2(0, 56)
	input.text_submitted.connect(func(t: String) -> void: _submit_join(t))
	_content.add_child(input)

	_content.add_child(_spacer(10))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	# Le bouton reste TOUJOURS cliquable après un refus (contre-épreuve comportementale §8.125) :
	# aucune désactivation, aucun verrou local — le serveur seul décide, et il répond en 200.
	row.add_child(_cta_button(tr("COMPANY_JOIN_CONFIRM"),
		func() -> void: _submit_join(input.text), 240))
	row.add_child(_ghost_button(tr("COMMON_CANCEL"), _on_form_cancel, 180))


func _build_emblem_grid(selected: int, on_pick: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in Emblems.count(int(_rules.get("emblem_count", 0))):
		var cell := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.22) if i == selected else Color(0, 0, 0, 0)
		sb.set_corner_radius_all(0)
		sb.set_border_width_all(2 if i == selected else 0)
		sb.border_color = ACCENT
		sb.set_content_margin_all(3.0)
		cell.add_theme_stylebox_override("panel", sb)
		cell.add_child(Emblems.make_badge(i, 44.0, _font))
		# Bouton transparent superposé : capte le clic sur toute la vignette (patron des badges de
		# division du Classement — le contenu ignore la souris, le bouton est ajouté en DERNIER).
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, empty)
		var index := i
		btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("click")
			on_pick.call(index))
		btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
		cell.add_child(btn)
		grid.add_child(cell)
	return grid


# Verdict affiché sous le champ TAG. Trois états, jamais muet : trop court (on attend), disponible,
# indisponible/mal formé.
func _tag_verdict_text() -> Dictionary:
	var need := int(_rules.get("tag_len", 4))
	if _draft_tag.strip_edges().length() < need:
		return {"text": tr("COMPANY_TAG_WAITING") % need, "color": MUTED}
	if str(_tag_check.get("tag", "")) != _draft_tag.strip_edges().to_upper():
		return {"text": tr("COMMON_SYNCING"), "color": MUTED}
	if bool(_tag_check.get("available", false)):
		return {"text": tr("COMPANY_TAG_FREE"), "color": ACCENT}
	return {"text": _reason_text(str(_tag_check.get("reason", "invalid_tag"))), "color": DANGER}


# =========================================================
# RÉSEAU
# =========================================================
func _on_company_state(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree() or _is_public():
		return
	if not ok:
		_set_status(tr("NET_SERVER_UNREACHABLE"), DANGER)
		return
	var c = data.get("company")
	_company = c if typeof(c) == TYPE_DICTIONARY else {}
	if typeof(data.get("rules")) == TYPE_DICTIONARY:
		_rules = data["rules"]
	_reason = str(data.get("reason", ""))
	_cooldown_s = int(data.get("cooldown_s", 0))
	_mark_seen_once()

	# Un succès ramène TOUJOURS à la fiche (ou à l'état « sans compagnie ») ; un refus LAISSE le
	# formulaire tel qu'il est, avec la saisie du joueur intacte — contre-épreuve §8.125 : un
	# formulaire qui se vide sur un refus fait recommencer, donc fait abandonner.
	if _reason == "" or _reason == "no_company":
		_view = "main"
		_draft_tag = ""
		_draft_name = ""
		_tag_check = {}

	_render()
	# La ligne de statut ne sert qu'aux REFUS et à l'attente réseau : en cas de succès elle se TAIT.
	# Le panneau lui-même est la confirmation — annoncer « chargé » sous une fiche déjà à l'écran
	# n'apprend rien et occupe une ligne qui doit rester réservée aux mauvaises nouvelles.
	if _reason != "" and _reason != "no_company":
		_set_status(_reason_text(_reason), DANGER)
	else:
		_set_status("", MUTED)


func _on_company_public(data: Dictionary, tag: String) -> void:
	# Réponse d'une AUTRE demande (l'opérateur peut enchaîner deux lignes du classement) : ignorée.
	if not is_inside_tree() or tag != _public_tag:
		return
	var c = data.get("company")
	_company = c if typeof(c) == TYPE_DICTIONARY else {}
	_render()
	# Idem : silence sur succès, message SEULEMENT si la compagnie est introuvable.
	_set_status("" if not _company.is_empty() else tr("COMPANY_NOT_FOUND"), MUTED)


# ACCUSÉ DE LECTURE (§8.126.1) — UNE fois par visite, à la première fiche reçue. Le refaire à chaque
# action (exclure, renommer…) enverrait une requête d'écriture pour rien : on a déjà tout lu.
func _mark_seen_once() -> void:
	if _seen_sent or _company.is_empty():
		return
	_seen_sent = true
	NetworkManager.company_mark_seen()
	# La pastille de la nav est mise à jour LOCALEMENT plutôt que par un second aller-retour : on
	# connaît déjà les deux nombres, et deux requêtes concurrentes n'auraient aucun ordre garanti
	# (le badge aurait pu répondre AVANT que l'accusé ne soit enregistré, et rester allumé).
	# `online_count` inclut l'appelant ; la pastille, elle, ne se compte jamais soi-même.
	NetworkManager.company_badge_loaded.emit({
		"company": true,
		"online": maxi(0, int(_company.get("online_count", 0)) - 1),
		"unread": 0,
	})


func _on_tag_checked(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	_tag_check = data
	if _view == "create":
		_render()


func _on_session_expired() -> void:
	if not is_inside_tree():
		return
	AuthManager.session_notice = tr("AUTH_SESSION_EXPIRED")
	AuthManager.clear_session()
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")


# =========================================================
# ACTIONS
# =========================================================
func _on_create_view_pressed() -> void:
	_view = "create"
	_reason = ""
	_render()
	_set_status("", MUTED)


func _on_join_view_pressed() -> void:
	_view = "join"
	_reason = ""
	_render()
	_set_status("", MUTED)


func _on_form_cancel() -> void:
	_view = "main"
	_reason = ""
	_render()
	_set_status("", MUTED)


func _on_tag_typed(text: String) -> void:
	_draft_tag = text.to_upper()
	# Débounce : on n'interroge le serveur que 0,5 s après la DERNIÈRE frappe.
	if _tag_debounce == null:
		_tag_debounce = Timer.new()
		_tag_debounce.one_shot = true
		_tag_debounce.timeout.connect(func() -> void:
			if _draft_tag.strip_edges().length() == int(_rules.get("tag_len", 4)):
				NetworkManager.company_check_tag(_draft_tag))
		add_child(_tag_debounce)
	_tag_debounce.start(TAG_CHECK_DEBOUNCE)


func _on_create_confirm() -> void:
	NetworkManager.company_create(_draft_tag, _draft_name, _draft_emblem)
	_set_status(tr("COMMON_SYNCING"), MUTED)


func _submit_join(code: String) -> void:
	if code.strip_edges() == "":
		_set_status(_reason_text("unavailable"), DANGER)
		return
	NetworkManager.company_join(code)
	_set_status(tr("COMMON_SYNCING"), MUTED)


func _on_regen_pressed() -> void:
	_confirm(tr("COMPANY_CONFIRM_REGEN"), func() -> void: NetworkManager.company_regen_code())


func _on_leave_pressed() -> void:
	# Le rappel du cooldown fait PARTIE de la confirmation : quitter est libre, mais revenir coûte
	# 24 h — le joueur doit le lire avant de cliquer, pas après.
	_confirm(tr("COMPANY_CONFIRM_LEAVE"), func() -> void: NetworkManager.company_leave())


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(str(_company.get("join_code", "")))
	if _copy_button == null:
		return
	_copy_button.text = tr("SALON_COPIED")
	if _copy_flash_timer == null:
		_copy_flash_timer = Timer.new()
		_copy_flash_timer.one_shot = true
		_copy_flash_timer.timeout.connect(func() -> void:
			if _copy_button != null and is_instance_valid(_copy_button):
				_copy_button.text = tr("SALON_COPY"))
		add_child(_copy_flash_timer)
	_copy_flash_timer.start(COPY_FLASH_DURATION)


func _on_back_pressed() -> void:
	TransitionManager.change_scene("res://scenes/ui/leaderboard.tscn")


# Confirmation modale — MÊME construction que le panneau d'explication (voile plein écran + panneau
# gunmetal bordé cyan), avec DEUX boutons au lieu d'une fermeture au clic : une action destructive
# (exclure, transférer, quitter) ne doit jamais partir sur un clic distrait.
func _confirm(message: String, on_yes: Callable) -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.6)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)

	var pan := PanelContainer.new()
	pan.custom_minimum_size = Vector2(560, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = ACCENT
	st.set_content_margin_all(28.0)
	pan.add_theme_stylebox_override("panel", st)
	center.add_child(pan)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	pan.add_child(col)
	col.add_child(_center_note(message, TEXT, 16))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(_cta_button(tr("COMMON_CONFIRM"), func() -> void:
		veil.queue_free()
		on_yes.call()
		_set_status(tr("COMMON_SYNCING"), MUTED), 180))
	row.add_child(_ghost_button(tr("COMMON_CANCEL"), func() -> void: veil.queue_free(), 180))


# =========================================================
# FABRIQUES / UTILITAIRES (charte §2)
# =========================================================
func _label(text: String, size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, min_w: float = 0.0) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if min_w > 0.0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _center_note(text: String, color: Color, size: int) -> Label:
	var l := _label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _stat_card(title: String, value: String, color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = Color(color, 0.5)
	sb.set_content_margin_all(12.0)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	# Rythme eyebrow → valeur (§2).
	v.add_child(_label(title, 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label(value, 24, color, HORIZONTAL_ALIGNMENT_CENTER))
	return card


func _cta_button(text: String, on_pressed: Callable, width: float) -> Button:
	var btn := Button.new()
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.text = "❯ " + text
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(14.0)
	normal.bg_color = Color(ACCENT, 0.16)
	normal.set_border_width_all(2)
	normal.border_color = ACCENT
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.32)
	hover.shadow_color = Color(ACCENT, 0.5)
	hover.shadow_size = 12
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.55)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.custom_minimum_size = Vector2(width, 50)
	btn.pressed.connect(on_pressed)
	WarzoneUI.wire_button_sfx(btn)
	return btn


func _ghost_button(text: String, on_pressed: Callable, width: float,
		tint: Color = ACCENT) -> Button:
	var btn := Button.new()
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.text = text
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(width, 44)
	WarzoneUI.apply_ghost_button(btn)
	if tint != ACCENT:
		btn.add_theme_color_override("font_hover_color", tint)
	btn.pressed.connect(on_pressed)
	WarzoneUI.wire_button_sfx(btn)
	return btn


func _mini_action(text: String, on_pressed: Callable, tint: Color = ACCENT) -> Button:
	var btn := _ghost_button(text, on_pressed, 92.0, tint)
	btn.custom_minimum_size = Vector2(92, 30)
	btn.add_theme_font_size_override("font_size", 12)
	return btn


# « K7RD2 » → « K 7 R D 2 » (miroir exact du salon privé et de l'escouade : un code se dicte).
func _spaced(code: String) -> String:
	if code == "":
		return "—"
	var out := ""
	for i in code.length():
		if i > 0:
			out += " "
		out += code[i]
	return out


func _format_thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return ("-" if value < 0 else "") + out


# Reliquat de cooldown en « 7 H » / « 45 MIN » — le client FORMATE, le serveur COMPTE (il envoie des
# secondes, jamais un texte : règle R4).
func _format_duration(seconds: int) -> String:
	if seconds >= 3600:
		return tr("COMMON_HOURS_SHORT") % int(ceil(seconds / 3600.0))
	return tr("COMMON_MINUTES_SHORT") % max(1, int(ceil(seconds / 60.0)))


# « 2026-07-31T10:00:00Z » → « 2026-07-31 ». Vide si la date est absente ou illisible : on n'invente
# pas une ancienneté.
func _short_date(iso: String) -> String:
	return iso.substr(0, 10) if iso.length() >= 10 else ""


# Discriminant serveur → message. AUCUN texte affichable ne vient du serveur (règle R4) : il envoie
# une RAISON, le client choisit les mots — et donc la langue.
func _reason_text(reason: String) -> String:
	match reason:
		"tag_taken": return tr("COMPANY_ERR_TAG_TAKEN")
		"invalid_tag": return tr("COMPANY_ERR_INVALID_TAG")
		"invalid_name": return tr("COMPANY_ERR_INVALID_NAME")
		"invalid_emblem": return tr("COMPANY_ERR_INVALID_EMBLEM")
		"unavailable": return tr("COMPANY_ERR_UNAVAILABLE")
		"already_member": return tr("COMPANY_ERR_ALREADY_MEMBER")
		"cooldown": return tr("COMPANY_COOLDOWN_NOTICE") % _format_duration(max(1, _cooldown_s))
		"banned": return tr("COMPANY_ERR_BANNED")
		"not_leader": return tr("COMPANY_ERR_NOT_LEADER")
		"not_member": return tr("COMPANY_ERR_NOT_MEMBER")
		_: return tr("COMPANY_ERR_UNAVAILABLE")


func _set_status(text: String, color: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_label.visible = text != ""


func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
