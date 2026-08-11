extends Control

# =========================================================================
# HUB ÉVÉNEMENTS — quatre onglets (§8.134), charte « Warzone Command » §2
# =========================================================================
# La destination CANONIQUE de tout ce qui est « en ce moment » dans le jeu :
#   PARTIES     — les mutateurs §8.132 (ce qui change dans les règles ce week-end) ;
#   PERSONNAGES — le personnage GRATUIT de la semaine, jusqu'ici enterré dans la Boutique ;
#   BONUS       — tournois et offres exceptionnelles (coquille prête, VIDE au lancement) ;
#   DÉFIS       — les missions quotidiennes/hebdo, qui quittent la barre de navigation.
#
# ⚠️ CET ÉCRAN REMPLACE UN PLACEHOLDER, PUIS S'EST REFONDU. `scenes/ui/events.tscn` portait
# `section_placeholder.gd`, puis l'écran §8.132 à page unique. On REPREND toujours la même scène :
# l'onglet de navigation, l'uid et les chemins existants restent valides, et il n'y a jamais deux
# écrans « Événements » dans le dépôt.
#
# ⚠️⚠️ AUCUNE VALEUR D'ÉVÉNEMENT EN DUR. Nom, description, dates, type, effets, vedette : tout
# descend du serveur (`NetworkManager.events_config`, alimenté par `GET /squad/playlists`). Le
# client ne sait même pas combien d'événements existent, ni lequel mettre en avant — `featured_id`
# est calculé SERVEUR. C'est ce qui permet d'ouvrir un événement en éditant un registre backend.
#
# ACQUIS §8.132 CONSERVÉS : ordre coquille-puis-nav (leçon §8.126), cache `events_config` peint
# immédiatement, `_render()` sur `locale_changed`. Le TIMER unique d'1 s, lui, a disparu : le temps
# est désormais l'affaire du composant `countdown_label` (un seul afficheur de temps dans tout le
# hub — c'est ça, la cohérence).
#
# Règle d'Or §6.1 : VUE pure — aucune règle de jeu ici, uniquement du rendu.

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const TopNav = preload("res://scripts/ui/top_nav.gd")
const EventRulesModal = preload("res://scripts/ui/event_rules_modal.gd")
const CountdownLabel = preload("res://scripts/ui/countdown_label.gd")
const MissionsPanel = preload("res://scripts/ui/missions_panel.gd")

# --- Palette canonique (§2, miroir company_screen.gd) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)

const BAR_H := TopNav.NAV_H

# Types d'événement — MIROIR EXACT du registre serveur (`events.TYPE_*`). Le client ne s'en sert que
# pour RANGER dans le bon onglet ; il n'en déduit aucune règle, aucun effet, aucune date.
const TYPE_MATCH := "match"
const TYPE_CHARACTER := "character"
const TYPE_BONUS := "bonus"

# Onglets, data-driven (patron de la TabsBar de settings.gd / shop.gd). `type` = les événements que
# l'onglet montre ; "" pour DÉFIS, qui n'affiche pas d'événements du tout.
const TAB_DEFS := [
	{"id": "matches", "key": "EVENTS_TAB_MATCHES", "type": TYPE_MATCH},
	{"id": "characters", "key": "EVENTS_TAB_CHARACTERS", "type": TYPE_CHARACTER},
	{"id": "bonus", "key": "EVENTS_TAB_BONUS", "type": TYPE_BONUS},
	{"id": "missions", "key": "MENU_TAB_MISSIONS", "type": ""},
]
const DEFAULT_TAB := "matches"

# Onglet d'OUVERTURE, posé par l'appelant AVANT le changement de scène (patron §8.107, comme
# `CompanyScreen.target_tag`). PURGÉ à la lecture : sans ça, un joueur qui revient au hub par
# l'onglet de nav rouvrirait l'onglet où l'avait mené sa dernière notification.
static var target_tab: String = ""

# LA TRANCHÉE (§8.136) : « REJOUER » depuis l'écran de fin de duel — l'onglet BONUS s'ouvre et la
# file repart tout seul. Posé par `trench_fp.gd`, purgé à la lecture (même hygiène que target_tab).
static var pending_trench_requeue: bool = false

# Id de l'événement-porte du mini-jeu — MIROIR du registre serveur (`events.py`), utilisé UNIQUEMENT
# pour reconnaître « la carte bonus active est LA TRANCHÉE » et monter le panneau d'actions dessous.
const TRENCH_EVENT_ID := "trench_week"

var _font: Font
var _tabs_bar: HBoxContainer = null
var _tab_buttons: Dictionary = {}
var _pages: Dictionary = {}          # id d'onglet -> VBoxContainer (contenu de la page)
var _active_tab: String = DEFAULT_TAB
# Panneau DÉFIS : monté UNE SEULE FOIS et conservé (il porte un claim en vol et son propre cycle
# réseau — le reconstruire à chaque `_render()` annulerait un claim sous les doigts du joueur).
var _missions_panel: Node = null


func _ready() -> void:
	_font = _make_font()
	WarzoneUI.animate_screen_enter(self)

	# ⚠️ LA COQUILLE D'ABORD, LA NAV ENSUITE (leçon §8.126) : les Control se dessinent dans l'ORDRE
	# DE L'ARBRE. Le fond plein écran vit dans le `.tscn`, mais le panneau central est ajouté par ce
	# script — une nav montée AVANT lui passerait derrière.
	_active_tab = str(target_tab) if str(target_tab) != "" else DEFAULT_TAB
	target_tab = ""
	if not _has_tab(_active_tab):
		_active_tab = DEFAULT_TAB
	_build_shell()

	var nav := TopNav.new()
	nav.active_tab = "events"
	add_child(nav)
	AudioManager.start_menu_ambient()

	NetworkManager.events_loaded.connect(_on_events)
	LocaleManager.locale_changed.connect(_on_locale_changed)

	# LA TRANCHÉE (§8.136) : signaux de la file dédiée + classement d'événement. Connectés à l'écran
	# (pas au panneau) : le panneau survit aux _render() mais l'écran reste l'unique abonné.
	NetworkManager.trench_queue_result.connect(_on_trench_queue_result)
	NetworkManager.event_signup_result.connect(_on_event_signup_result)
	NetworkManager.trench_status_updated.connect(_on_trench_status)
	NetworkManager.trench_left.connect(_on_trench_left)
	NetworkManager.trench_training_result.connect(_on_trench_training_result)
	NetworkManager.trench_leaderboard_loaded.connect(_on_trench_leaderboard)
	NetworkManager.title_equipped.connect(_on_trench_title_equipped)

	# La nav lance déjà `fetch_events()` de son côté ; on peint immédiatement le cache s'il existe
	# (navigation depuis un autre écran hub) pour ne pas afficher un écran vide une demi-seconde.
	_render()

	# REJOUER depuis l'écran de fin de duel : onglet BONUS + remise en file immédiate.
	if pending_trench_requeue:
		pending_trench_requeue = false
		_show_tab("bonus")
		_trench_join()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


func _has_tab(id: String) -> bool:
	for t in TAB_DEFS:
		if str(t.get("id")) == id:
			return true
	return false


# =========================================================
# COQUILLE & ONGLETS
# =========================================================
func _build_shell() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = BAR_H
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 620)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(GUNMETAL, 0.92)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = Color(ACCENT, 0.7)
	st.set_content_margin_all(32.0)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	root.add_child(_label(_t("NAV_EVENTS"), 13, ACCENT))
	root.add_child(_label(_t("EVENT_SCREEN_TITLE"), 34, TEXT))

	# --- Barre d'onglets (construite en code, comme settings.gd/shop.gd — pas de TabContainer :
	# aucun helper d'onglets n'existe dans `warzone_ui.gd`, et le style natif de TabContainer ne se
	# plie pas à l'ADN angulaire de la charte sans plus de code que ceci). ---
	_tabs_bar = HBoxContainer.new()
	_tabs_bar.add_theme_constant_override("separation", 4)
	root.add_child(_tabs_bar)
	for t in TAB_DEFS:
		var btn := _make_tab_button(t)
		_tabs_bar.add_child(btn)
		_tab_buttons[str(t.get("id"))] = btn
	WarzoneUI.add_filet(root)

	# --- Pages : toutes créées, une seule VISIBLE. Les garder montées évite de reconstruire le
	# panneau DÉFIS (et son claim en vol) à chaque aller-retour entre onglets. ---
	var stack := MarginContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(stack)
	for t in TAB_DEFS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		page.visible = false
		stack.add_child(page)
		_pages[str(t.get("id"))] = page
	_show_tab(_active_tab)


func _make_tab_button(t: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = str(t.get("key"))     # clé i18n BRUTE → Godot traduit ET re-traduit tout seul.
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 16)
	_style_tab(btn, str(t.get("id")) == _active_tab)
	WarzoneUI.wire_button_sfx(btn)
	btn.pressed.connect(_show_tab.bind(str(t.get("id"))))
	return btn


func _style_tab(btn: Button, active: bool) -> void:
	var st := StyleBoxFlat.new()
	st.set_corner_radius_all(0)
	st.bg_color = Color(ACCENT, 0.10) if active else Color(1, 1, 1, 0.0)
	st.content_margin_left = 18.0
	st.content_margin_right = 18.0
	st.content_margin_top = 9.0
	st.content_margin_bottom = 9.0
	if active:
		st.border_width_bottom = 3
		st.border_color = ACCENT
	var hover := st.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.16)
	hover.border_width_bottom = 3
	hover.border_color = ACCENT if active else Color(ACCENT, 0.5)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", st)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)


func _show_tab(id: String) -> void:
	if not _has_tab(id):
		id = DEFAULT_TAB
	_active_tab = id
	for tab_id in _pages:
		_pages[tab_id].visible = tab_id == id
	for tab_id in _tab_buttons:
		_style_tab(_tab_buttons[tab_id], tab_id == id)


# =========================================================
# RENDU
# =========================================================
func _on_events(_data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement de scène.
	_render()


func _on_locale_changed(_code: String) -> void:
	if is_inside_tree():
		_render()


func _render() -> void:
	if _pages.is_empty():
		return
	var cfg: Dictionary = NetworkManager.events_config
	var actives: Array = cfg.get("active", []) if typeof(cfg.get("active")) == TYPE_ARRAY else []
	var upcoming: Array = cfg.get("upcoming", []) if typeof(cfg.get("upcoming")) == TYPE_ARRAY else []

	_render_event_tab("matches", TYPE_MATCH, actives, upcoming)
	_render_characters_tab(_dict(cfg.get("character", {})))
	_render_event_tab("bonus", TYPE_BONUS, actives, upcoming)
	_render_missions_tab()


# PARTIES et BONUS partagent le MÊME rendu : un futur événement `bonus` s'affichera sans une ligne
# de code neuve. C'est exactement ce que « la coquille est prête » veut dire.
func _render_event_tab(tab_id: String, type_id: String, actives: Array, upcoming: Array) -> void:
	var page: VBoxContainer = _pages.get(tab_id)
	if page == null:
		return
	# LA TRANCHÉE (§8.136) : le panneau d'actions SURVIT aux _render() (il porte une recherche de
	# duel en vol — même doctrine que _missions_panel). On le détache AVANT la purge, on le remonte
	# après la carte si l'événement est toujours actif.
	if tab_id == "bonus" and _trench_panel != null and is_instance_valid(_trench_panel) \
			and _trench_panel.get_parent() == page:
		page.remove_child(_trench_panel)
	_clear(page)

	var mine: Array = []
	for e in actives:
		var entry := _dict(e)
		if str(entry.get("type", "")) == type_id:
			mine.append(entry)
	var soon: Array = []
	for e in upcoming:
		var entry := _dict(e)
		if str(entry.get("type", "")) == type_id and not _contains_id(mine, str(entry.get("id", ""))):
			soon.append(entry)

	if not mine.is_empty():
		page.add_child(_event_card(mine[0], true))
	elif not soon.is_empty():
		page.add_child(_event_card(soon[0], false))
		soon.remove_at(0)
	else:
		page.add_child(_empty_state(
			"EVENTS_BONUS_EMPTY" if type_id == TYPE_BONUS else "EVENT_NONE_PLANNED",
			"EVENTS_BONUS_EMPTY_HINT" if type_id == TYPE_BONUS else ""))

	# LA TRANCHÉE active → le panneau d'actions (file, entraînement, top 50, ma progression).
	if tab_id == "bonus":
		if _contains_id(mine, TRENCH_EVENT_ID):
			page.add_child(_ensure_trench_panel())
			# Le panneau SURVIT aux rendus (il porte une recherche en vol) : son prix d'entrée doit
			# donc être repeint ICI, à chaque rendu, et pas seulement à sa construction — un frais
			# réglé à chaud côté serveur (TUNABLE §8.143) arrive par un simple `fetch_events`.
			_refresh_trench_fee()
			_refresh_trench_signup()
			NetworkManager.fetch_trench_leaderboard()
		elif _trench_panel != null and is_instance_valid(_trench_panel):
			# Fenêtre refermée : le panneau meurt avec elle (la file serveur est déjà purgée).
			_trench_stop_poll()
			_trench_panel.queue_free()
			_trench_panel = null

	# --- CALENDRIER : les prochaines opérations, en heure LOCALE du joueur ---
	if not soon.is_empty():
		page.add_child(_spacer(6))
		page.add_child(_label(_t("EVENT_CALENDAR_TITLE"), 13, ACCENT))
		for entry in soon:
			page.add_child(_calendar_row(entry))

	# --- NOTE DE PÉRIMÈTRE : permanente sur l'onglet PARTIES, même quand rien n'est programmé ---
	if type_id == TYPE_MATCH:
		page.add_child(_spacer(8))
		WarzoneUI.add_filet(page)
		var scope := _label(_t("EVENT_SCOPE_NOTE"), 13, MUTED)
		scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_child(scope)


# --- Onglet PERSONNAGES ------------------------------------------------------------------------
# Structure en LISTE dès le départ (exigence du chantier) : la carte du personnage gratuit est la
# PREMIÈRE ENTRÉE, pas un cas particulier. Les futurs événements `character` viendront s'empiler
# dessous sans refonte.
func _render_characters_tab(character: Dictionary) -> void:
	var page: VBoxContainer = _pages.get("characters")
	if page == null:
		return
	_clear(page)
	if character.is_empty() or str(character.get("faction_id", "")) == "":
		page.add_child(_empty_state("COMMON_SYNCING", ""))
		return
	page.add_child(_free_character_card(character))


func _render_missions_tab() -> void:
	var page: VBoxContainer = _pages.get("missions")
	if page == null:
		return
	# ⚠️ MONTÉ UNE SEULE FOIS, et JAMAIS purgé par `_render()` : ce panneau possède son propre cycle
	# réseau et un verrou de claim EN VOL. Le reconstruire à la réception d'une config d'événements
	# (qui n'a rien à voir) annulerait un claim en cours sous les doigts du joueur.
	if _missions_panel != null and is_instance_valid(_missions_panel):
		return
	_missions_panel = MissionsPanel.new()
	_missions_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_missions_panel)


# =========================================================
# CARTES
# =========================================================
# Carte d'événement, cliquable → modal de règles. Liseré OR si l'opération est en cours, CYAN si
# elle est à venir : la couleur seule dit « ça se joue maintenant » ou « prépare-toi ».
func _event_card(event: Dictionary, is_active: bool) -> Control:
	var accent: Color = GOLD if is_active else ACCENT
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(0, 200)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SURFACE, 0.85)
	st.set_corner_radius_all(0)
	# Liseré fin sur trois côtés, ÉPAIS à gauche : la barre verticale de couleur est la signature
	# des cartes de la charte (§2). ⚠️ `set_border_width_all` D'ABORD — l'appeler après écraserait
	# la largeur gauche.
	st.set_border_width_all(1)
	st.border_width_left = 4
	st.border_color = accent
	st.set_content_margin_all(22.0)
	var hover := st.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.10)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", st)
	WarzoneUI.wire_button_sfx(btn)
	btn.pressed.connect(func() -> void:
		EventRulesModal.open(self, event, is_active, _font))

	# Le contenu est posé PAR-DESSUS le bouton (un Button ne prend pas d'enfants de mise en page) :
	# un VBox en plein cadre, transparent aux clics, pour que tout le pavé reste cliquable.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 22.0
	box.offset_top = 18.0
	box.offset_right = -22.0
	box.offset_bottom = -18.0
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	box.add_child(_label(_eyebrow_text(event, is_active), 13, accent))
	box.add_child(_label(_t(str(event.get("name_key", ""))).to_upper(), 30, TEXT))
	var desc := _label(_t(str(event.get("desc_key", ""))), 16, MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	box.add_child(_spacer(2))

	# Compte à rebours : vers la FIN si l'opération est en cours, vers le DÉBUT sinon.
	var cd = CountdownLabel.make(18, accent)
	box.add_child(cd)
	cd.set_target(int(event.get("ends_at_epoch", 0)) if is_active
		else int(event.get("starts_at_epoch", 0)),
		"COUNTDOWN_ENDS_IN" if is_active else "COUNTDOWN_STARTS_IN")
	# La fenêtre vient de basculer : on redemande la configuration plutôt que d'afficher un rebours
	# figé. Le serveur mémoïse 60 s → aucun risque de marteler l'API.
	cd.expired.connect(func() -> void: NetworkManager.fetch_events())

	box.add_child(_label(_t("EVENT_OPEN_RULES"), 13, MUTED))
	return btn


# --- Carte « PERSONNAGE GRATUIT DE LA SEMAINE » ------------------------------------------------
# ⚠️ VUE PURE sur la rotation : le tirage vient de `rotation.py`, le compteur de parties de
# `access.py`. Rien n'est recalculé ici — pas même le « 5 » du plafond, qui descend du serveur.
func _free_character_card(character: Dictionary) -> Control:
	var faction_id := str(character.get("faction_id", ""))
	var faction = _resolve_faction(faction_id)
	var accent: Color = faction.accent_color if (faction != null
		and faction.get("accent_color") != null) else GOLD

	var pan := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SURFACE, 0.85)
	st.set_corner_radius_all(0)
	st.set_border_width_all(1)
	st.border_width_left = 4
	st.border_color = accent
	st.set_content_margin_all(22.0)
	pan.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	pan.add_child(row)

	# Portrait du héros — `hero_path` est un CHEMIN (pattern characters_screen/main_menu), pas une
	# texture. Chargé défensivement : ressource absente ou chemin périmé → aucun cadre, la mise en
	# page se referme proprement plutôt que d'afficher un carré vide.
	var img_path := ""
	if faction != null and faction.get("hero_path") != null:
		img_path = str(faction.get("hero_path"))
	var portrait_tex: Texture2D = null
	if img_path != "" and ResourceLoader.exists(img_path):
		portrait_tex = load(img_path) as Texture2D
	if portrait_tex != null:
		var frame := PanelContainer.new()
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fst := StyleBoxFlat.new()
		fst.bg_color = Color(accent, 0.08)
		fst.set_corner_radius_all(0)
		fst.set_border_width_all(1)
		fst.border_color = Color(accent, 0.55)
		fst.set_content_margin_all(3)
		frame.add_theme_stylebox_override("panel", fst)
		var tex := TextureRect.new()
		tex.texture = portrait_tex
		tex.custom_minimum_size = Vector2(128, 128)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(tex)
		row.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)

	box.add_child(_label(_t("EVENTS_EYEBROW_CHARACTER"), 13, accent))
	box.add_child(_label(_t("EVENT_FREE_CHAR_TITLE"), 26, TEXT))
	if faction != null and faction.get("name") != null:
		var hero := WarzoneUI.faction_leader_title(faction)
		var who := str(faction.name).to_upper()
		if hero != "":
			who = "%s — %s" % [hero.to_upper(), who]
		box.add_child(_label(who, 18, accent))

	var cd = CountdownLabel.make(18, MUTED)
	box.add_child(cd)
	cd.set_target(int(character.get("ends_at_epoch", 0)), "COUNTDOWN_ENDS_IN")
	cd.expired.connect(func() -> void: NetworkManager.fetch_events())

	# COMPTEUR PERSONNEL. `null` = la question ne se pose pas (faction déjà possédée, ou joueur non
	# authentifié) → on affiche « FACTION POSSÉDÉE » plutôt qu'un « 0/5 » mensonger.
	var left = character.get("free_games_left", null)
	if left == null:
		box.add_child(_label(_t("EVENT_FACTION_OWNED"), 15, MUTED))
	else:
		var maxi_games := int(character.get("free_games_max", 0))
		box.add_child(_label(_t("EVENT_FREE_GAMES_LEFT") % [int(left), maxi_games],
			15, GOLD if int(left) > 0 else MUTED))

	var cta_row := HBoxContainer.new()
	cta_row.add_theme_constant_override("separation", 10)
	box.add_child(cta_row)
	cta_row.add_child(_cta(_t("EVENT_TRY_CTA"), accent, func() -> void:
		# « L'ESSAYER » mémorise le personnage puis part en recherche : le draft proposera celui-là
		# en premier (même mécanique que l'écran Personnages, §8.93).
		if faction_id != "":
			SettingsManager.set_selected_faction(faction_id)
		TransitionManager.change_scene("res://scenes/ui/search_screen.tscn")))
	cta_row.add_child(_cta(_t("EVENT_SHOP_CTA"), MUTED, func() -> void:
		TransitionManager.change_scene("res://scenes/ui/shop.tscn")))
	return pan


func _cta(label: String, color: Color, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(190, 46)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
	WarzoneUI.apply_ghost_button(btn)
	btn.add_theme_color_override("font_color", color)
	WarzoneUI.wire_button_sfx(btn)
	btn.pressed.connect(on_pressed)
	return btn


# Ligne de calendrier : nom + fenêtre datée en heure LOCALE du joueur (conversion depuis l'epoch
# UTC — on n'affiche JAMAIS une heure serveur brute, elle serait fausse pour la moitié du monde).
func _calendar_row(event: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var chevron := _label("❯", 14, ACCENT)
	chevron.custom_minimum_size = Vector2(18, 0)
	row.add_child(chevron)
	var name_lbl := _label(_t(str(event.get("name_key", ""))).to_upper(), 16, TEXT)
	name_lbl.custom_minimum_size = Vector2(280, 0)
	row.add_child(name_lbl)
	var when := _label(_window_label(int(event.get("starts_at_epoch", 0)),
		int(event.get("ends_at_epoch", 0))), 15, MUTED)
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(when)
	return row


# État vide SOIGNÉ : un titre et, si l'onglet le mérite, une ligne sobre qui dit ce qui viendra là.
# Jamais un cadre nu — un écran vide sans explication se lit comme une panne.
func _empty_state(title_key: String, hint_key: String) -> Control:
	var pan := PanelContainer.new()
	pan.custom_minimum_size = Vector2(0, 180)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SURFACE, 0.6)
	st.set_corner_radius_all(0)
	st.set_border_width_all(1)
	st.border_color = Color(MUTED, 0.5)
	st.set_content_margin_all(24.0)
	pan.add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	pan.add_child(box)
	var l := _label(_t(title_key), 20, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	if hint_key != "":
		var h := _label(_t(hint_key), 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(h)
	return pan


# =========================================================
# LA TRANCHÉE (§8.136) — panneau d'actions de l'onglet BONUS
# =========================================================
# Monté SOUS la carte de l'événement quand `trench_week` est ACTIF : les deux CTA (file /
# entraînement), l'état de recherche (poll 2 s, mêmes états d'affichage que search_screen), MA
# progression de niveau d'événement et le top 50. AUCUNE valeur en dur : paliers, plafonds et
# classement descendent du serveur (`/trench/leaderboard`).
# §8.137 — le duel se joue désormais à la PREMIÈRE PERSONNE : la vue de côté v1
# (`trench_duel.tscn`) est sortie du flux et retirée du dépôt. Le contrat d'entrée est inchangé —
# on pose `pending_room_id` avant de changer de scène (patron `CompanyScreen.target_tag`).
const TrenchDuelScript := preload("res://scripts/game/trench_fp.gd")

var _trench_panel: PanelContainer = null
var _trench_status_label: Label = null
var _trench_enter_btn: Button = null
# INSCRIPTION A L'EVENEMENT (chantier CORRECTIFS ECONOMIQUES) — l'etape « S'INSCRIRE » n'existe
# QUE si le serveur la demande (`event_signup.required`). ⚑ A frais nul, ou pour un detenteur du
# Pass (exonere), ce bouton n'apparait JAMAIS : le joueur ne voit aucune etape, ne clique rien, et
# ne sait meme pas que le mecanisme existe. « Frais 0 = friction 0 » n'est pas une optimisation,
# c'est la condition pour que le deploiement soit invisible.
var _trench_signup_btn: Button = null
var _trench_cancel_btn: Button = null
var _trench_training_btn: Button = null
var _trench_progress_box: VBoxContainer = null
var _trench_board_box: VBoxContainer = null
var _trench_poll: Timer = null
var _trench_searching := false
# PRIX D'ENTRÉE de la file d'événement (chantier MODÈLE ÉCONOMIQUE) — ligne posée SOUS les CTA,
# repeuplée à chaque `_render()` depuis `NetworkManager.events_config.event_queue_fee`. Masquée
# quand l'entrée est gratuite : jamais « 0 COINS ».
var _trench_fee_label: Label = null


func _ensure_trench_panel() -> PanelContainer:
	if _trench_panel != null and is_instance_valid(_trench_panel):
		return _trench_panel
	var pan := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SURFACE, 0.7)
	st.set_corner_radius_all(0)
	st.set_border_width_all(1)
	st.border_color = Color(GOLD, 0.55)
	st.set_content_margin_all(18.0)
	pan.add_theme_stylebox_override("panel", st)
	pan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trench_panel = pan

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pan.add_child(box)

	# --- Rangée d'actions : ENTRER / ANNULER / ENTRAÎNEMENT + ligne d'état ---
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	# L'inscription se lit AVANT ENTRER — c'est l'ordre des gestes, et donc l'ordre a l'ecran.
	_trench_signup_btn = _cta("", GOLD, _trench_signup)
	_trench_signup_btn.visible = false
	row.add_child(_trench_signup_btn)
	_trench_enter_btn = _cta(_t("TRENCH_ENTER_CTA"), GOLD, _trench_join)
	row.add_child(_trench_enter_btn)
	_trench_cancel_btn = _cta(_t("TRENCH_CANCEL_SEARCH"), MUTED, _trench_cancel)
	_trench_cancel_btn.visible = false
	row.add_child(_trench_cancel_btn)
	_trench_training_btn = _cta(_t("TRENCH_TRAINING_CTA"), ACCENT, _trench_training)
	row.add_child(_trench_training_btn)
	_trench_status_label = _label("", 14, MUTED)
	_trench_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trench_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_trench_status_label)
	# PRIX D'ENTRÉE, juste sous la rangée ENTRER / ANNULER / ENTRAÎNEMENT — donc à côté du bouton
	# qu'il conditionne, et AVANT le clic (§7.3 : le joueur ne découvre jamais un péage au moment
	# d'agir). Le texte est posé par `_refresh_trench_fee`, appelé à chaque rendu.
	_trench_fee_label = _label("", 13, GOLD)
	_trench_fee_label.visible = false
	box.add_child(_trench_fee_label)
	var note := _label(_t("TRENCH_VS_BOT_NOTE"), 12, MUTED)
	box.add_child(note)

	# --- Ma progression (peuplée par /trench/leaderboard, bloc `me`) ---
	_trench_progress_box = VBoxContainer.new()
	_trench_progress_box.add_theme_constant_override("separation", 4)
	box.add_child(_trench_progress_box)

	# --- Top 50 ---
	WarzoneUI.add_filet(box)
	box.add_child(_label(_t("TRENCH_LEADERBOARD_TITLE"), 13, ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 130)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_trench_board_box = VBoxContainer.new()
	_trench_board_box.add_theme_constant_override("separation", 2)
	_trench_board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_trench_board_box)

	# Poll de file (2 s — même cadence que search_screen). Enfant de l'ÉCRAN : il meurt au
	# changement de scène, jamais de poll fantôme.
	if _trench_poll == null:
		_trench_poll = Timer.new()
		_trench_poll.wait_time = 2.0
		_trench_poll.timeout.connect(func() -> void: NetworkManager.trench_queue_status())
		add_child(_trench_poll)
	return pan


# Peint le prix d'entrée de la file d'événement. TROIS états, et le premier est le plus important :
#   • frais à 0 (ou bloc absent d'un serveur antérieur) → RIEN. Surtout pas « 0 COINS » : écrire la
#     gratuité en prix la transforme en tarif.
#   • frais dû → « 120 COINS » en or (le serveur a DÉJÀ appliqué le Pass du lecteur).
#   • frais dû mais nul avec un Pass → on ajoute « GRATUIT AVEC LE PASS », qui est un avantage
#     contractuel du Pass de saison, pas un argument de vente inventé ici.
func _refresh_trench_fee() -> void:
	if _trench_fee_label == null or not is_instance_valid(_trench_fee_label):
		return
	var block: Dictionary = _dict(NetworkManager.events_config.get("event_queue_fee", {}))
	var fee := int(block.get("fee", 0))
	var fee_base := int(block.get("fee_base", fee))
	# 🩸 LA GARDE PORTE SUR LE PLEIN TARIF (chantier CORRECTIFS ÉCONOMIQUES). Sortir sur `fee <= 0`
	# éteignait le label pour un détenteur de Pass — or l'événement est la surface où le Pass
	# EXONÈRE TOTALEMENT : l'avantage contractuel le plus visible du produit était le seul à
	# n'afficher strictement rien. Frais réellement éteint (base à 0) → silence, comme avant.
	if fee_base <= 0:
		_trench_fee_label.visible = false
		_trench_fee_label.text = ""
		return
	var hint: Dictionary = WarzoneUI.fee_pass_hint(fee, fee_base,
		int(block.get("fee_with_pass", fee)))
	var text := ""
	if fee > 0:
		text = _t("FEE_LABEL") % fee
	if String(hint.get("text", "")) != "":
		text += ("  ·  " if text != "" else "") + String(hint["text"])
	_trench_fee_label.text = text
	_trench_fee_label.visible = text != ""


func _trench_join() -> void:
	if _trench_searching:
		return
	_trench_set_status(_t("COMMON_SYNCING"), MUTED)
	NetworkManager.trench_queue_join()


func _trench_signup() -> void:
	if _trench_searching:
		return
	_trench_set_status(_t("COMMON_SYNCING"), MUTED)
	# L'id vient du bloc serveur, jamais d'une constante d'ecran : le prochain evenement bonus
	# reutilisera ce bouton sans une ligne de plus ici.
	NetworkManager.event_signup(_trench_event_id())


func _trench_event_id() -> String:
	var active = NetworkManager.events_config.get("active", [])
	if typeof(active) == TYPE_ARRAY:
		for ev in active:
			if typeof(ev) == TYPE_DICTIONARY and str(ev.get("type", "")) == "bonus":
				return str(ev.get("id", ""))
	return "trench_week"   # repli : le seul evenement bonus inscriptible a ce jour.


# Peint l'etape d'inscription. TROIS etats, et le premier est de loin le plus frequent :
#   • rien a faire (frais eteint, deja inscrit, ou detenteur du Pass exonere) → AUCUN bouton ;
#   • inscription due → « S'INSCRIRE — N COINS », en or, AVANT le bouton ENTRER ;
#   • detenteur avec un prix configure → l'entree est OFFERTE : on ne demande rien, mais la ligne
#     de prix (juste dessous) le DIT (« OFFERT · PASS »), sinon l'avantage serait invisible.
func _refresh_trench_signup() -> void:
	if _trench_signup_btn == null or not is_instance_valid(_trench_signup_btn):
		return
	var block: Dictionary = _dict(NetworkManager.events_config.get("event_signup", {}))
	var required := bool(block.get("required", false))
	_trench_signup_btn.visible = required and not _trench_searching
	if required:
		_trench_signup_btn.text = _t("EVENT_SIGNUP_CTA") % int(block.get("fee", 0))
	# Le bouton ENTRER reste VISIBLE et CLIQUABLE : le serveur refusera proprement
	# (`signup_required`) et le joueur comprendra pourquoi. Le griser aurait fabrique un mur muet.


func _on_event_signup_result(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree():
		return
	if ok and bool(data.get("enrolled", false)):
		_trench_set_status(_t("EVENT_SIGNUP_DONE"), GOLD)
		# L'etat d'inscription vit dans la config d'evenements : on la redemande pour que le
		# bouton disparaisse et que la ligne de prix se mette a jour d'un seul coup.
		NetworkManager.fetch_events()
		return
	var reason := str(data.get("reason", ""))
	if reason == "insufficient_coins":
		_trench_set_status(_t("FEE_INSUFFICIENT"), GOLD)
	elif reason == "event_closed":
		_trench_set_status(_t("TRENCH_EVENT_CLOSED"), MUTED)
		NetworkManager.fetch_events()
	else:
		_trench_set_status(_t("NET_UNKNOWN_ERROR"), MUTED)


func _trench_cancel() -> void:
	NetworkManager.trench_queue_leave()


func _trench_training() -> void:
	if _trench_searching:
		return
	_trench_set_status(_t("COMMON_SYNCING"), MUTED)
	NetworkManager.trench_training_start()


func _trench_set_status(text: String, color: Color) -> void:
	if _trench_status_label != null and is_instance_valid(_trench_status_label):
		_trench_status_label.text = text
		_trench_status_label.add_theme_color_override("font_color", color)


func _trench_set_searching(searching: bool) -> void:
	_trench_searching = searching
	if _trench_enter_btn != null and is_instance_valid(_trench_enter_btn):
		_trench_enter_btn.visible = not searching
		_trench_cancel_btn.visible = searching
		_trench_training_btn.disabled = searching
	if searching:
		if _trench_poll != null:
			_trench_poll.start()
	else:
		_trench_stop_poll()


func _trench_stop_poll() -> void:
	if _trench_poll != null and is_instance_valid(_trench_poll):
		_trench_poll.stop()


func _on_trench_queue_result(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree():
		return
	var reason := str(data.get("reason", ""))
	if ok and bool(data.get("queued", false)):
		_trench_set_searching(true)
		_trench_set_status(_t("TRENCH_SEARCHING"), GOLD)
	elif reason == "event_closed":
		_trench_set_searching(false)
		_trench_set_status(_t("TRENCH_EVENT_CLOSED"), MUTED)
		NetworkManager.fetch_events()  # la fenêtre a bougé : la carte doit suivre.
	elif reason == "in_room" and str(data.get("room_mode", "")) == "trench":
		# Un duel m'attend déjà (reconnexion) : on y retourne directement.
		_go_to_duel(int(data.get("room_id", 0)))
	elif reason == "banned":
		_trench_set_searching(false)
		_trench_set_status(_t("SQUAD_ERR_BANNED"), MUTED)
	elif reason == "signup_required":
		# LE GATE D'INSCRIPTION : on n'entre pas dans les activites d'un evenement sans s'y etre
		# inscrit. Message en OR (une information, pas une panne) et on rafraichit l'etat pour que
		# le bouton « S'INSCRIRE » apparaisse dans la seconde — un refus qui ne montre pas le geste
		# a faire est un cul-de-sac.
		_trench_set_searching(false)
		_trench_set_status(_t("EVENT_SIGNUP_REQUIRED"), GOLD)
		NetworkManager.fetch_events()
	elif reason == "insufficient_coins":
		# FRAIS D'ENTRÉE impayable — information, pas panne : EN OR, et on rappelle que le mode
		# CASUAL reste gratuit (aucun péage n'a jamais touché les modes cœur). On rafraîchit aussi
		# le prix affiché : s'il vient de changer à chaud, autant que le joueur voie le vrai.
		_trench_set_searching(false)
		_trench_set_status(_t("FEE_INSUFFICIENT"), GOLD)
		_refresh_trench_fee()
		_refresh_trench_signup()
	else:
		_trench_set_searching(false)
		_trench_set_status(_t("NET_UNKNOWN_ERROR"), MUTED)


func _on_trench_status(data: Dictionary) -> void:
	if not is_inside_tree() or not _trench_searching:
		return
	var state := str(data.get("state", "idle"))
	match state:
		"searching", "extending", "starting":
			var since := int(data.get("since_s", 0))
			_trench_set_status(_t("TRENCH_SEARCHING") + "  ·  %ds" % since,
				GOLD if state != "extending" else ACCENT)
		"ready", "in_game":
			var rid = data.get("room_id")
			if rid != null:
				_trench_set_searching(false)
				_go_to_duel(int(rid))
		"event_closed":
			_trench_set_searching(false)
			_trench_set_status(_t("TRENCH_EVENT_CLOSED"), MUTED)
			NetworkManager.fetch_events()
		"idle":
			# Ticket disparu (fenêtre fermée côté serveur, heartbeat perdu…) : on s'arrête proprement.
			_trench_set_searching(false)
			_trench_set_status(_t("TRENCH_EVENT_CLOSED"), MUTED)


func _on_trench_left(left: bool, _reason: String, refunded: int) -> void:
	if not is_inside_tree():
		return
	if left:
		_trench_set_searching(false)
		# REMBOURSEMENT : annoncé, jamais silencieux. Le frais d'entrée est rendu à l'annulation
		# (§6.3) — sans un mot à l'écran, le joueur voit partir des Coins au clic « ENTRER » et ne
		# les voit jamais revenir. `refunded` vaut 0 quand il n'y avait rien à rendre (frais à 0,
		# détenteur du Pass) : on se tait alors, comme avant.
		if refunded > 0:
			_trench_set_status(_t("FEE_REFUNDED") % refunded, GOLD)
		else:
			_trench_set_status("", MUTED)


func _on_trench_training_result(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree():
		return
	if ok and bool(data.get("created", false)):
		_go_to_duel(int(data.get("room_id", 0)))
	elif str(data.get("reason", "")) == "event_closed":
		_trench_set_status(_t("TRENCH_EVENT_CLOSED"), MUTED)
	elif str(data.get("reason", "")) == "in_room" and str(data.get("room_mode", "")) == "trench":
		_go_to_duel(int(data.get("room_id", 0)))
	else:
		_trench_set_status(_t("NET_UNKNOWN_ERROR"), MUTED)


func _go_to_duel(room_id: int) -> void:
	_trench_stop_poll()
	TrenchDuelScript.pending_room_id = str(int(room_id))
	TransitionManager.change_scene("res://scenes/game/trench_fp.tscn")


func _on_trench_leaderboard(data: Dictionary) -> void:
	if not is_inside_tree() or _trench_board_box == null \
			or not is_instance_valid(_trench_board_box):
		return
	# --- Ma progression ---
	_clear(_trench_progress_box)
	var me = data.get("me")
	if typeof(me) == TYPE_DICTIONARY:
		var wins := int(me.get("wins", 0))
		var level := int(me.get("level", 0))
		var level_max := int(me.get("level_max", 3))
		var line := _t("TRENCH_EVENT_LEVEL") % [level, level_max, wins]
		var next = me.get("next_threshold")
		if next != null:
			line += "  ·  " + _t("TRENCH_NEXT_LEVEL") % int(next)
		var rank = me.get("rank")
		if rank != null:
			line += "  ·  " + _t("TRENCH_MY_RANK") % int(rank)
		_trench_progress_box.add_child(_label(line, 15, GOLD))
		# Titres débloqués → équipables ICI (la progression d'événement vit dans ce hub, pas dans
		# le palmarès de maîtrise — POST /profile/title accepte les "trench:*" depuis §8.136).
		var titles: Array = me.get("titles", [])
		if not titles.is_empty():
			var trow := HBoxContainer.new()
			trow.add_theme_constant_override("separation", 8)
			_trench_progress_box.add_child(trow)
			for title_id in titles:
				var key := str(title_id).replace("trench:", "").to_upper()
				var btn := _cta(_t("TITLE_TRENCH_" + key), ACCENT,
					func() -> void: NetworkManager.equip_title(str(title_id)))
				btn.custom_minimum_size = Vector2(0, 34)
				btn.add_theme_font_size_override("font_size", 12)
				trow.add_child(btn)
			trow.add_child(_label(_t("TRENCH_EQUIP_HINT"), 12, MUTED))
	# --- Top 50 ---
	_clear(_trench_board_box)
	var entries: Array = data.get("entries", [])
	if entries.is_empty():
		_trench_board_box.add_child(_label(_t("TRENCH_LEADERBOARD_EMPTY"), 14, MUTED))
		return
	for e in entries:
		var entry := _dict(e)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var rank_lbl := _label("#%d" % int(entry.get("rank", 0)), 14, MUTED)
		rank_lbl.custom_minimum_size = Vector2(44, 0)
		row.add_child(rank_lbl)
		var name_lbl := _label(str(entry.get("name", "")), 14, TEXT)
		name_lbl.custom_minimum_size = Vector2(300, 0)
		row.add_child(name_lbl)
		row.add_child(_label(_t("TRENCH_WINS_FMT") % int(entry.get("wins", 0)), 14, GOLD))
		_trench_board_box.add_child(row)


func _on_trench_title_equipped(data: Dictionary) -> void:
	if not is_inside_tree() or _active_tab != "bonus":
		return
	if bool(data.get("ok", false)) and str(data.get("equipped_title", "")).begins_with("trench:"):
		_trench_set_status(_t("TRENCH_TITLE_EQUIPPED"), ACCENT)


# =========================================================
# OUTILS
# =========================================================
# Sur-titre d'une carte : « ÉVÉNEMENT — PARTIES » / « — BONUS », ou l'état v1 pour un événement à
# venir. Le TYPE est dit en toutes lettres : c'est ce qui rattache visuellement la carte du QG à
# l'onglet où le clic va atterrir.
func _eyebrow_text(event: Dictionary, is_active: bool) -> String:
	if not is_active:
		return _t("EVENT_CARD_UPCOMING")
	match str(event.get("type", TYPE_MATCH)):
		TYPE_BONUS:
			return _t("EVENTS_EYEBROW_BONUS")
		TYPE_CHARACTER:
			return _t("EVENTS_EYEBROW_CHARACTER")
		_:
			return _t("EVENTS_EYEBROW_MATCH")


func _contains_id(entries: Array, id: String) -> bool:
	for e in entries:
		if str(_dict(e).get("id", "")) == id:
			return true
	return false


# Fenêtre datée en heure LOCALE (`Time.get_datetime_dict_from_unix_time` + décalage système).
func _window_label(start_epoch: int, end_epoch: int) -> String:
	if start_epoch <= 0:
		return ""
	var a := Time.get_datetime_dict_from_unix_time(start_epoch + _local_offset())
	var b := Time.get_datetime_dict_from_unix_time(end_epoch + _local_offset()) if end_epoch > 0 else a
	return _t("EVENT_WINDOW_FMT") % [int(a["day"]), int(a["month"]), int(a["hour"]),
		int(b["day"]), int(b["month"]), int(b["hour"])]


func _local_offset() -> int:
	# `Time.get_time_zone_from_system()["bias"]` est en MINUTES (signé).
	var tz := Time.get_time_zone_from_system()
	return int(tz.get("bias", 0)) * 60


# Catalogue de factions — mêmes garde-fous que main_menu.gd / top_nav.gd (scan export-safe qui gère
# les `.remap`, repli sur une liste en dur, duck-typing plutôt qu'une dépendance à un `class_name`).
var _factions: Dictionary = {}
var _factions_loaded: bool = false
const FACTIONS_DIR := "res://resources/factions/"


func _resolve_faction(faction_id: String):
	if not _factions_loaded:
		_factions_loaded = true
		var dir := DirAccess.open(FACTIONS_DIR)
		if dir != null:
			dir.list_dir_begin()
			var fn := dir.get_next()
			while fn != "":
				if not dir.current_is_dir():
					var base_name := fn.trim_suffix(".remap")
					if base_name.ends_with(".tres"):
						var res = load(FACTIONS_DIR + base_name)
						if res != null and res.get("id") != null:
							_factions[str(res.id)] = res
				fn = dir.get_next()
			dir.list_dir_end()
	return _factions.get(faction_id)


func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _label(text: String, font_size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	# Textes DÉJÀ traduits : l'auto-traduction les re-chercherait comme des clés (piège maison).
	l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()
