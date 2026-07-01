extends Control

# =========================================================================
# MENU PRINCIPAL — Tableau de bord asymétrique « Warzone Command » (§2 / §8.37)
# =========================================================================
# Refonte du menu d'une liste de boutons vers un lobby AAA (réf. Call of Duty: Warzone) :
#   • Top Bar : identité opérateur + onglets (QG / Boutique / Opérateur / Classement) + cluster
#     utilitaire (jauge XP·Coins, Paramètres ⚙, bouton système ⏻). Le choix de la langue n'est
#     plus dans la nav : il est centralisé dans l'écran Paramètres (⚙).
#   • Centre : HÉROS de la DERNIÈRE FACTION JOUÉE (résolu via /profile/history → faction .tres).
#   • Colonne gauche : mini-classement (top 3) + carte Défis (placeholder, gains XP/niveau à venir).
#   • Bas-gauche : gros CTA « START » qui lance le MODE sélectionné.
#   • Bas-centre : cartes de mode Trio(3) / Quad(4) / Five(5) / Exa(6) + Classée(5, classé).
# Règle d'Or §6.1 : VUE pure — navigation via TransitionManager, données via AuthManager /
# NetworkManager (signaux), audio via AudioManager. Aucune logique de jeu brute ici.

# --- Identité / statut (Top Bar + CTA) ---
@export var welcome_label: Label
@export var status_label: Label

# --- Top Bar : onglets de navigation ---
@export var lobby_tab: Button
@export var characters_tab: Button
@export var shop_tab: Button
@export var leaderboard_tab: Button

# --- Top Bar : cluster utilitaire ---
@export var settings_button: Button
@export var system_button: Button
@export var xp_coins_slot: Control

# --- Centre : héros de la dernière faction jouée ---
@export var hero_portrait: TextureRect
@export var portrait_placeholder: ColorRect

# --- Bas-gauche : CTA principal ---
@export var mode_eyebrow: Label
@export var play_button: Button

# --- Colonne gauche : widgets ---
@export var leaderboard_content: VBoxContainer
@export var challenges_content: VBoxContainer

# --- Bas-centre : cartes de mode ---
@export var cards_row: HBoxContainer

# Helpers UI partagés de la charte (§2) — encoches, filets, sélecteur de langue, SFX, ghost.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Jauge XP + Coins (§8.47) — composant réutilisable monté par code.
const XpCoinsBarScript = preload("res://scripts/ui/xp_coins_bar.gd")
# Héros 3D (SubViewport transparent) — remplace le portrait 2D quand la faction a un .glb riggé.
# Préchargé (pas de class_name, par prudence vis-à-vis du cache d'import, cf. WarzoneUI).
const HeroViewport3DScene = preload("res://scenes/components/hero_viewport_3d.tscn")

# --- Palette canonique (§2, miroir de profile.gd / FRONTEND_INTERFACES.md) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)     # or (récompense / classé)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)     # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)    # acier
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)   # surface secondaire
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)   # rouge (système / quitter)

# --- Factions data-driven (résolution faction_id -> ressource), garde-fous de faction_selection.gd ---
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

# --- Modes de jeu (cartes du bas). count = effectif ; ranked = mode « Classée » (classé, =5). ---
# DÉPENDANCE BACKEND : le gate classé (is_ranked + contrainte ==5 + ladder) n'est pas encore
# appliqué côté serveur ; l'effectif (3-6) passe nativement via max_players (cf. match_config.gd).
const MODES := [
	{"id": "trio", "name_key": "MENU_MODE_TRIO", "count": 3, "ranked": false},
	{"id": "quad", "name_key": "MENU_MODE_QUAD", "count": 4, "ranked": false},
	{"id": "five", "name_key": "MENU_MODE_FIVE", "count": 5, "ranked": false},
	{"id": "exa", "name_key": "MENU_MODE_EXA", "count": 6, "ranked": false},
	{"id": "ranked", "name_key": "MENU_MODE_RANKED", "count": 5, "ranked": true},
]
const DEFAULT_MODE := "trio"

# Police condensée de la charte (§2) pour les nœuds générés en code.
var _font: SystemFont
# Jauge XP/Coins, montée dans le slot du cluster utilitaire (révélée au chargement du profil).
var _xp_bar: PanelContainer = null
# Catalogue de factions : id -> ressource FactionData (.tres).
var _factions: Dictionary = {}
# Faction de repli (première triée) si l'historique est vide / l'id est inconnu → centre jamais vide.
var _default_faction_id: String = ""
# Cartes de mode : mode_id -> { "panel": PanelContainer, "sub": Label, "mode": Dictionary }.
var _mode_cards: Dictionary = {}
# Mode actuellement sélectionné (surbrillance + lu par le CTA START).
var _selected_mode: String = DEFAULT_MODE
# Conteneur des lignes du mini-classement (peuplé à la réception des données).
var _lb_rows: VBoxContainer = null
# Dernières entrées de classement reçues (re-rendues au changement de langue — format des victoires).
var _last_lb_entries: Array = []
# Overlay de confirmation « Quitter » (construit par code à la demande, masqué par défaut).
var _quit_dialog: Control = null
# Instance du héros 3D, montée une fois dans HeroLayer (le modèle est échangé via set_model).
# Non typée à dessein (appels dynamiques set_model/set_accent — pas de class_name sur le composant).
var _hero3d = null

# --- Mini-profil flottant (§8.58) : ouvert au clic sur la jauge XP/Coins ---
# Overlay construit À LA DEMANDE (même pattern que le pop-up « Quitter ») : un capteur plein-cadre
# transparent (ferme au clic extérieur) + un panneau « intel » ancré sous la jauge. Masqué par défaut.
var _profile_flyout: Control = null
var _flyout_panel: PanelContainer = null
var _flyout_body: VBoxContainer = null
# Dernières données de profil (/auth/me) et dernière faction jouée (historique) — elles alimentent
# le résumé du mini-profil SANS refaire d'appel réseau (tout est déjà chargé au _ready).
var _profile_data: Dictionary = {}
var _last_faction_id: String = ""

# Statut courant (clé + args), mémorisé pour re-traduction au changement de langue (R4).
var _status_key: String = "MENU_STATUS_LOADING"
var _status_args: Array = []


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Catalogue des factions (résolution id -> ressource pour le héros central).
	_load_factions()

	# --- Top Bar : onglets (style « souligné » Warzone) ---
	# L'onglet « OPÉRATEUR » a été RETIRÉ de la nav (§8.58) : le profil s'ouvre désormais via la
	# jauge XP/Coins cliquable (mini-profil flottant). _on_profile_pressed() est conservé — il est
	# maintenant déclenché par le CTA « VOIR LE PROFIL COMPLET » de ce mini-profil.
	_style_tab(lobby_tab, true)
	_style_tab(characters_tab, false)
	_style_tab(shop_tab, false)
	_style_tab(leaderboard_tab, false)
	if characters_tab: characters_tab.pressed.connect(_on_characters_pressed)
	if shop_tab: shop_tab.pressed.connect(_on_inventory_pressed)
	if leaderboard_tab: leaderboard_tab.pressed.connect(_on_leaderboard_pressed)

	# --- Top Bar : boutons système (engrenage cyan + power rouge) ---
	_style_icon_button(settings_button, ACCENT)
	_style_icon_button(system_button, DANGER)
	if settings_button: settings_button.pressed.connect(_on_settings_pressed)
	if system_button: system_button.pressed.connect(_on_quit_requested)

	# --- CTA START ---
	_style_cta(play_button)
	if play_button: play_button.pressed.connect(_on_play_pressed)

	# --- Cartes de mode (bas-centre) ---
	_build_mode_cards()

	# --- Colonne gauche : widgets ---
	_build_leaderboard_widget()
	_build_challenges_widget()

	# --- Héros central : repli immédiat (faction par défaut), affiné à la réception de l'historique. ---
	_apply_hero("")

	# Encoches biseautées sur les cartes de la colonne gauche (ADN angulaire §2).
	if leaderboard_content: WarzoneUI.add_corner_notches(leaderboard_content.get_parent())
	if challenges_content: WarzoneUI.add_corner_notches(challenges_content.get_parent())

	# Halo néon cyan derrière la petite marque biohazard de la Top Bar (§8.63).
	var logo_small := get_node_or_null("Hud/Shell/TopBar/BrandBox/LogoSmall")
	if logo_small is TextureRect:
		WarzoneUI.attach_mark_glow(logo_small, 72.0, 0.85, 1.5)

	# --- Audio (R6) : nappe d'ambiance + SFX d'interface sur les boutons interactifs (no-op headless). ---
	AudioManager.start_menu_ambient()
	WarzoneUI.wire_buttons_sfx([lobby_tab, characters_tab, shop_tab, leaderboard_tab, settings_button, system_button, play_button])

	# --- Jauge XP/Coins, montée dans son slot de la Top Bar. ---
	_mount_xp_bar()
	# Le sélecteur de langue ne vit plus dans la nav (centralisé dans Paramètres) ; on reste tout de
	# même abonné à LocaleManager pour re-traduire les textes FORMATÉS au retour des réglages (R4).
	LocaleManager.locale_changed.connect(_on_locale_changed)

	# --- Réseau : profil (niveau/XP/coins/pseudo), historique (dernière faction), classement (top 3). ---
	AuthManager.profile_loaded.connect(_on_profile_loaded)
	AuthManager.auth_failed.connect(_on_auth_failed)
	NetworkManager.profile_history_loaded.connect(_on_history_loaded)
	NetworkManager.leaderboard_loaded.connect(_on_leaderboard_loaded)

	_set_status("MENU_STATUS_LOADING")

	AuthManager.get_profile()
	NetworkManager.fetch_profile_history(1)
	NetworkManager.fetch_leaderboard(3)


# =========================================================
# MONTAGE DES COMPOSANTS PARTAGÉS (XP/Coins)
# =========================================================
func _mount_xp_bar() -> void:
	_xp_bar = XpCoinsBarScript.new()
	_xp_bar.visible = false  # révélée par _on_profile_loaded (évite un « LV 1 / 0 XP » fugace).
	if xp_coins_slot:
		xp_coins_slot.add_child(_xp_bar)
	else:
		add_child(_xp_bar)
	# Jauge CLIQUABLE (§8.58) : on rend le panneau interactif APRÈS l'ajout à l'arbre (le contenu
	# existe alors → le bouton capteur reste bien au-dessus) et on écoute le clic pour ouvrir/fermer
	# le mini-profil flottant.
	_xp_bar.set_interactive(true)
	_xp_bar.profile_widget_clicked.connect(_on_profile_widget_clicked)


# =========================================================
# HÉROS CENTRAL — dernière faction jouée
# =========================================================
# Réception de l'historique (/profile/history, le plus récent d'abord) : la 1re entrée valide donne
# la DERNIÈRE faction jouée → on bascule le portrait dessus. Historique vide → on garde le héros de
# repli déjà affiché (compte neuf).
func _on_history_loaded(entries: Array) -> void:
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			var fid := str(e.get("faction_id", ""))
			if fid != "":
				_last_faction_id = fid  # alimente la ligne « faction » du mini-profil (§8.58).
				_apply_hero(fid)
				return

# Monte (une seule fois) le composant héros 3D dans HeroLayer, au même emplacement que le
# portrait 2D (sous le HUD en verre). Idempotent ; no-op si le portrait n'est pas câblé.
func _ensure_hero3d() -> void:
	if _hero3d != null:
		return
	if hero_portrait == null:
		return
	_hero3d = HeroViewport3DScene.instantiate()
	# Ajouté dans le parent du portrait (HeroLayer) → conserve les ancres plein-cadre du composant
	# et reste DERRIÈRE le HUD (HeroLayer se dessine avant Hud).
	hero_portrait.get_parent().add_child(_hero3d)

# Affiche le héros de la faction `faction_id` (repli faction par défaut si vide/inconnu).
# 3D D'ABORD : si la faction expose un .glb valide, on le monte dans le SubViewport et on masque
# le 2D. Sinon repli sur le portrait 2D, puis placeholder coloré si l'image manque aussi — pattern
# repris de faction_selection.gd:_set_portrait.
func _apply_hero(faction_id: String) -> void:
	var f = _resolve_faction(faction_id)
	var accent: Color = SURFACE
	var model_path := ""
	var img_path := ""
	if f != null:
		if f.get("accent_color") != null:
			accent = f.accent_color
		if f.get("hero_model_path") != null:
			model_path = str(f.get("hero_model_path"))
		if f.get("hero_path") != null:
			img_path = str(f.get("hero_path"))

	# --- Chemin 3D : .glb présent → héros 3D, 2D masqué. ---
	_ensure_hero3d()
	if _hero3d != null and _hero3d.set_model(model_path):
		_hero3d.set_accent(accent)
		_hero3d.visible = true
		if hero_portrait:
			hero_portrait.visible = false
		if portrait_placeholder:
			portrait_placeholder.visible = false
		return

	# --- Repli 2D : pas (encore) de .glb pour cette faction. ---
	if _hero3d != null:
		_hero3d.visible = false
	var tex = null
	if img_path != "" and ResourceLoader.exists(img_path):
		tex = load(img_path)
	if tex != null:
		if hero_portrait:
			hero_portrait.texture = tex
			hero_portrait.visible = true
		if portrait_placeholder:
			portrait_placeholder.visible = false
	else:
		if hero_portrait:
			hero_portrait.visible = false
		if portrait_placeholder:
			portrait_placeholder.visible = true
			portrait_placeholder.color = accent.darkened(0.25)

func _resolve_faction(faction_id: String):
	if faction_id != "" and _factions.has(faction_id):
		return _factions[faction_id]
	if _default_faction_id != "" and _factions.has(_default_faction_id):
		return _factions[_default_faction_id]
	return null


# =========================================================
# CHARGEMENT DES FACTIONS (garde-fous de faction_selection.gd / profile.gd)
# =========================================================
func _load_factions() -> void:
	var paths := _scan_faction_paths()
	if paths.is_empty():
		paths = FALLBACK_PATHS.duplicate()
	var ids := []
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		# Duck-typing : on accepte toute ressource exposant un id (pas de dépendance au class_name).
		if res != null and res.get("id") != null:
			_factions[str(res.id)] = res
			ids.append(str(res.id))
	ids.sort()
	if not ids.is_empty():
		_default_faction_id = str(ids[0])

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


# =========================================================
# CARTES DE MODE (bas-centre) — Trio/Quad/Five/Exa + Classée
# =========================================================
func _build_mode_cards() -> void:
	if cards_row == null:
		return
	for m in MODES:
		var entry := _make_mode_card(m)
		cards_row.add_child(entry["panel"])
		_mode_cards[m["id"]] = entry
	_select_mode(DEFAULT_MODE)

func _make_mode_card(m: Dictionary) -> Dictionary:
	var ranked: bool = m["ranked"]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(150, 130)
	# Cartes à largeur fixe groupées au CENTRE (la rangée CardsRow est en alignment center) — réf. photo
	# Warzone « SELECT TEAM SIZE ». (Avant : EXPAND_FILL → les cartes s'étiraient sur toute la largeur.)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _card_style(false, ranked))

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = m["name_key"]  # clé brute -> auto-traduction (FR/EN/IT)
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", GOLD if ranked else TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lbl)

	var sub := Label.new()
	sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# Bouton transparent superposé : capte le clic sur toute la carte (le contenu ignore la souris).
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	var mode_id: String = m["id"]
	btn.pressed.connect(func() -> void: _on_mode_card_pressed(mode_id))
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	panel.add_child(btn)

	WarzoneUI.add_corner_notches(panel, 14.0, GOLD if ranked else WarzoneUI.NOTCH_COLOR)

	var entry := {"panel": panel, "sub": sub, "mode": m}
	_apply_mode_sub(entry)
	return entry

# (Re)pose le sous-titre d'une carte (formaté → re-appliqué au changement de langue).
func _apply_mode_sub(entry: Dictionary) -> void:
	var m: Dictionary = entry["mode"]
	var sub: Label = entry["sub"]
	if sub == null:
		return
	if m["ranked"]:
		sub.text = tr("MENU_MODE_RANKED_SUB")
	else:
		sub.text = tr("MENU_MODE_PLAYERS") % int(m["count"])

func _on_mode_card_pressed(mode_id: String) -> void:
	AudioManager.play_sfx("click")
	_select_mode(mode_id)

func _select_mode(mode_id: String) -> void:
	if not _mode_cards.has(mode_id):
		return
	_selected_mode = mode_id
	for mid in _mode_cards:
		var entry: Dictionary = _mode_cards[mid]
		var ranked: bool = entry["mode"]["ranked"]
		var panel: PanelContainer = entry["panel"]
		panel.add_theme_stylebox_override("panel", _card_style(mid == mode_id, ranked))

func _card_style(selected: bool, ranked: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(14.0)
	var accent: Color = GOLD if ranked else ACCENT
	sb.bg_color = GUNMETAL
	if selected:
		sb.bg_color = Color(accent, 0.16)
		sb.set_border_width_all(2)
		sb.border_color = accent
		sb.shadow_color = Color(accent, 0.45)
		sb.shadow_size = 8
	else:
		sb.set_border_width_all(1)
		sb.border_color = Color(accent, 0.3)
	return sb


# =========================================================
# MINI-CLASSEMENT (colonne gauche) — réutilise /leaderboard (top 3)
# =========================================================
func _build_leaderboard_widget() -> void:
	if leaderboard_content == null:
		return
	leaderboard_content.add_child(_card_title("MENU_TOP_OPERATORS"))
	WarzoneUI.add_filet(leaderboard_content)
	_lb_rows = VBoxContainer.new()
	_lb_rows.add_theme_constant_override("separation", 4)
	leaderboard_content.add_child(_lb_rows)
	var more := Button.new()
	more.text = "MENU_VIEW_ALL"
	more.add_theme_font_override("font", _font)
	more.add_theme_font_size_override("font_size", 13)
	WarzoneUI.apply_ghost_button(more)
	more.pressed.connect(_on_leaderboard_pressed)
	more.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	leaderboard_content.add_child(more)
	_set_lb_message("MENU_WIDGET_LOADING")

# Signal GLOBAL partagé avec l'écran Classement (scènes distinctes, jamais vivantes ensemble) :
# garde défensive si l'émission arrive pendant un changement de scène.
func _on_leaderboard_loaded(entries: Array, _me: Dictionary) -> void:
	if not is_inside_tree():
		return
	_last_lb_entries = entries
	_rebuild_lb_rows()

func _rebuild_lb_rows() -> void:
	if _lb_rows == null:
		return
	_clear(_lb_rows)
	if _last_lb_entries.is_empty():
		_set_lb_message("MENU_WIDGET_EMPTY")
		return
	var n: int = mini(3, _last_lb_entries.size())
	for i in range(n):
		var e = _last_lb_entries[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_lb_rows.add_child(_make_lb_row(i + 1, e))

func _make_lb_row(rank: int, e: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var r := Label.new()
	r.text = "❯ %d" % rank
	r.add_theme_font_override("font", _font)
	r.add_theme_font_size_override("font_size", 14)
	r.add_theme_color_override("font_color", GOLD if rank == 1 else ACCENT)
	r.custom_minimum_size = Vector2(40, 0)
	h.add_child(r)

	# Lecture défensive (clés canoniques + alias historiques), comme leaderboard.gd.
	var u := Label.new()
	u.text = str(e.get("username", "—")).to_upper()
	u.add_theme_font_override("font", _font)
	u.add_theme_font_size_override("font_size", 14)
	u.add_theme_color_override("font_color", TEXT)
	u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	u.clip_text = true
	h.add_child(u)

	var w := Label.new()
	w.text = tr("MENU_WINS_ABBR") % int(e.get("wins", e.get("stats_victoires", 0)))
	w.add_theme_font_override("font", _font)
	w.add_theme_font_size_override("font_size", 14)
	w.add_theme_color_override("font_color", GOLD)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(w)
	return h

func _set_lb_message(key: String) -> void:
	if _lb_rows == null:
		return
	_clear(_lb_rows)
	_lb_rows.add_child(_body(key))


# =========================================================
# CARTE DÉFIS (placeholder) — gains XP / montée de niveau à configurer plus tard
# =========================================================
func _build_challenges_widget() -> void:
	if challenges_content == null:
		return
	challenges_content.add_child(_card_title("MENU_CHALLENGES_TITLE"))
	challenges_content.add_child(_body("MENU_CHALLENGES_SUB"))
	WarzoneUI.add_filet(challenges_content)
	for i in 2:
		challenges_content.add_child(_make_challenge_placeholder())
	var soon := Label.new()
	soon.text = "MENU_CHALLENGES_SOON"  # clé brute -> auto-traduction
	soon.add_theme_font_override("font", _font)
	soon.add_theme_font_size_override("font_size", 12)
	soon.add_theme_color_override("font_color", GOLD)
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenges_content.add_child(soon)

func _make_challenge_placeholder() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var chev := Label.new()
	chev.text = "❯"
	chev.add_theme_font_override("font", _font)
	chev.add_theme_font_size_override("font_size", 14)
	chev.add_theme_color_override("font_color", Color(ACCENT, 0.5))
	h.add_child(chev)
	# Barre de progression « verrouillée » (cyan très atténué) — purement décorative tant que les
	# défis ne sont pas configurés côté serveur.
	var bar := ColorRect.new()
	bar.color = Color(ACCENT, 0.12)
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	return h


# =========================================================
# CONFIRMATION « QUITTER » — overlay modal à la charte (construit à la demande)
# =========================================================
func _on_quit_requested() -> void:
	if _quit_dialog == null:
		_build_quit_dialog()
	if _quit_dialog:
		_quit_dialog.visible = true

func _build_quit_dialog() -> void:
	var dim := ColorRect.new()
	dim.name = "QuitDialog"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(2)
	pstyle.border_color = DANGER
	pstyle.set_content_margin_all(28.0)
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	var title := Label.new()
	title.text = "MENU_QUIT_TITLE"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var body := Label.new()
	body.text = "MENU_QUIT_BODY"
	body.add_theme_font_override("font", _font)
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", MUTED)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)

	var cancel := Button.new()
	cancel.text = "MENU_QUIT_CANCEL"
	cancel.add_theme_font_override("font", _font)
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.custom_minimum_size = Vector2(150, 48)
	WarzoneUI.apply_ghost_button(cancel)
	cancel.pressed.connect(_on_quit_cancel)
	cancel.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	row.add_child(cancel)

	var ok := Button.new()
	ok.text = "MENU_QUIT_OK"
	ok.add_theme_font_override("font", _font)
	ok.add_theme_font_size_override("font_size", 16)
	ok.custom_minimum_size = Vector2(170, 48)
	_style_danger_button(ok)
	ok.pressed.connect(_on_quit_confirm)
	ok.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	row.add_child(ok)

	WarzoneUI.add_corner_notches(panel, 16.0, DANGER)
	_quit_dialog = dim

func _on_quit_cancel() -> void:
	AudioManager.play_sfx("click")
	if _quit_dialog:
		_quit_dialog.visible = false

func _on_quit_confirm() -> void:
	AudioManager.play_sfx("click")
	get_tree().quit()


# =========================================================
# MINI-PROFIL FLOTTANT (§8.58) — ouvert au clic sur la jauge XP/Coins
# =========================================================
# Remplace l'ancien onglet « OPÉRATEUR » : un clic sur la jauge XP/Coins ouvre un menu déroulant à
# la charte (résumé express de l'opérateur + CTA vers le profil complet). Construit À LA DEMANDE
# (comme le pop-up « Quitter »). Se ferme au clic extérieur, sur ÉCHAP, ou au re-clic sur la jauge.
func _on_profile_widget_clicked() -> void:
	AudioManager.play_sfx("click")
	if _profile_flyout != null and _profile_flyout.visible:
		_close_profile_flyout()
	else:
		_open_profile_flyout()

func _open_profile_flyout() -> void:
	if _profile_flyout == null:
		_build_profile_flyout()
	_populate_profile_flyout()
	# Pré-positionnement à la taille minimale estimée (évite un flash en (0,0)), affichage, puis
	# ajustement fin une fois le layout résolu (la taille réelle n'est connue qu'après une frame).
	_flyout_panel.size = _flyout_panel.get_combined_minimum_size()
	_position_profile_flyout()
	_profile_flyout.visible = true
	await get_tree().process_frame
	_position_profile_flyout()

func _close_profile_flyout() -> void:
	if _profile_flyout:
		_profile_flyout.visible = false

# Ancre le panneau JUSTE SOUS la jauge, bord droit aligné (la jauge vit dans le cluster aligné à
# droite), borné à l'écran (jamais hors cadre). Recalculé à chaque ouverture (robuste au resize).
func _position_profile_flyout() -> void:
	if _flyout_panel == null or _xp_bar == null or not is_instance_valid(_xp_bar):
		return
	var bar := _xp_bar.get_global_rect()
	var vp := get_viewport_rect().size
	var psize := _flyout_panel.size
	var x := clampf(bar.end.x - psize.x, 8.0, maxf(8.0, vp.x - psize.x - 8.0))
	var y := minf(bar.end.y + 8.0, maxf(8.0, vp.y - psize.y - 8.0))
	_flyout_panel.global_position = Vector2(x, y)

func _build_profile_flyout() -> void:
	# Calque plein-cadre, masqué par défaut, posé AU-DESSUS du HUD (ajouté après lui à l'arbre).
	_profile_flyout = Control.new()
	_profile_flyout.name = "ProfileFlyout"
	_profile_flyout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_profile_flyout.visible = false
	add_child(_profile_flyout)

	# Capteur transparent plein-cadre : tout clic HORS du panneau referme le menu (clic extérieur).
	var catcher := Control.new()
	catcher.name = "Catcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_profile_flyout())
	_profile_flyout.add_child(catcher)

	# Panneau « intel » : gunmetal quasi opaque + liseré cyan + encoches d'angle + ombre (charte §2).
	# Parent = Control simple (pas un conteneur) → position/taille pilotées en code (cf. _position_…).
	_flyout_panel = PanelContainer.new()
	_flyout_panel.name = "Panel"
	_flyout_panel.custom_minimum_size = Vector2(300, 0)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(1)
	pstyle.border_color = Color(ACCENT, 0.7)
	pstyle.set_content_margin_all(18.0)
	pstyle.shadow_color = Color(0, 0, 0, 0.5)
	pstyle.shadow_size = 10
	_flyout_panel.add_theme_stylebox_override("panel", pstyle)
	_profile_flyout.add_child(_flyout_panel)

	_flyout_body = VBoxContainer.new()
	_flyout_body.add_theme_constant_override("separation", 10)
	_flyout_panel.add_child(_flyout_body)

	WarzoneUI.add_corner_notches(_flyout_panel)

# (Re)construit le contenu du mini-profil depuis les données DÉJÀ chargées (aucun appel réseau).
func _populate_profile_flyout() -> void:
	if _flyout_body == null:
		return
	_clear(_flyout_body)

	# --- En-tête : eyebrow OPÉRATEUR + pseudo (rythme eyebrow → valeur §2) ---
	_flyout_body.add_child(_card_title("COMMON_OPERATOR"))
	var name_lbl := Label.new()
	name_lbl.text = str(_profile_data.get("username", tr("COMMON_PLAYER"))).to_upper()
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", TEXT)
	_flyout_body.add_child(name_lbl)

	WarzoneUI.add_filet(_flyout_body)

	# --- Lignes de résumé (libellé muet à gauche, valeur colorée à droite) ---
	var level := int(_profile_data.get("player_level", _profile_data.get("niveau", 1)))
	var coins := int(_profile_data.get("coins_balance", _profile_data.get("coins", 0)))
	_flyout_body.add_child(_flyout_stat_row("COMMON_LEVEL", "LV %d" % maxi(1, level), ACCENT))
	_flyout_body.add_child(_flyout_stat_row("SHOP_CREDITS", str(maxi(0, coins)), GOLD))

	# Dernière faction jouée (donnée RÉELLE de l'historique) — affichée si connue, à la couleur
	# d'accent de la faction (cohérent avec profile.gd). Étiquetée « FACTION DE PRÉDILECTION ».
	if _last_faction_id != "":
		var f = _resolve_faction(_last_faction_id)
		if f != null and f.get("name") != null:
			var fac_color: Color = f.accent_color if f.get("accent_color") != null else ACCENT
			_flyout_body.add_child(_flyout_stat_row("PROFILE_FAVORITE_FACTION", str(f.name).to_upper(), fac_color))

	WarzoneUI.add_filet(_flyout_body)

	# --- CTA : ouvre le profil complet via TransitionManager ---
	var cta := Button.new()
	cta.text = "MENU_PROFILE_VIEW_FULL"  # clé brute -> auto-traduction (FR/EN/IT)
	cta.add_theme_font_override("font", _font)
	cta.add_theme_font_size_override("font_size", 15)
	cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WarzoneUI.apply_ghost_button(cta)
	cta.pressed.connect(func() -> void:
		AudioManager.play_sfx("click")
		_close_profile_flyout()
		_on_profile_pressed())
	cta.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	_flyout_body.add_child(cta)

# Ligne « eyebrow → valeur » du mini-profil : libellé muet à gauche, valeur colorée à droite.
func _flyout_stat_row(label_key: String, value: String, value_color: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)

	var l := Label.new()
	l.text = label_key  # clé brute -> auto-traduction
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)

	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", _font)
	v.add_theme_font_size_override("font_size", 18)
	v.add_theme_color_override("font_color", value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(v)
	return h

# ÉCHAP referme le mini-profil s'il est ouvert (confort clavier ; ne gêne rien d'autre).
func _unhandled_input(event: InputEvent) -> void:
	if _profile_flyout != null and _profile_flyout.visible and event.is_action_pressed("ui_cancel"):
		_close_profile_flyout()
		get_viewport().set_input_as_handled()


# =========================================================
# PROFIL SERVEUR (pseudo / niveau / XP / Coins)
# =========================================================
func _on_profile_loaded(data: Dictionary) -> void:
	_profile_data = data  # mémorisé pour le résumé du mini-profil (§8.58) — pas de nouvel appel réseau.
	# Rythme « eyebrow → valeur » (§2) : l'intitulé OPÉRATEUR vit dans la scène ; le code ne pousse
	# que la VALEUR brute (pseudo en MAJUSCULES). Le niveau est désormais porté par la jauge XP.
	if welcome_label:
		welcome_label.text = str(data.get("username", tr("COMMON_PLAYER"))).to_upper()
	if _xp_bar:
		var level := int(data.get("player_level", data.get("niveau", 1)))
		var xp := int(data.get("current_xp", data.get("experience", 0)))
		# xp_to_next_level absent (VPS pas à jour) → repli sur la courbe locale (miroir backend).
		var xp_next := int(data.get("xp_to_next_level", _xp_bar._xp_required_for_level(level) - xp))
		var coins := int(data.get("coins_balance", data.get("coins", 0)))
		_xp_bar.set_profile(level, xp, maxi(0, xp_next), coins)
		_xp_bar.visible = true
	_set_status("MENU_STATUS_CONNECTED")
	# Si le mini-profil est ouvert au moment où le profil (re)charge, on rafraîchit son résumé.
	if _profile_flyout != null and _profile_flyout.visible:
		_populate_profile_flyout()

func _on_auth_failed(message: String) -> void:
	_set_status("MENU_STATUS_ERROR", [message])


# =========================================================
# STATUT (re-traduction R4) & NAVIGATION
# =========================================================
func _set_status(key: String, args: Array = []) -> void:
	_status_key = key
	_status_args = args
	if status_label:
		status_label.text = (tr(key) % args) if not args.is_empty() else tr(key)

func _on_locale_changed(_code: String) -> void:
	# Les libellés à clé brute se re-traduisent seuls ; on ré-applique les textes FORMATÉS (status,
	# sous-titres de cartes, lignes de classement) qui ne passent pas par l'auto-traduction.
	_set_status(_status_key, _status_args)
	for mid in _mode_cards:
		_apply_mode_sub(_mode_cards[mid])
	_rebuild_lb_rows()

func _go(path: String) -> void:
	TransitionManager.change_scene(path)

func _on_play_pressed() -> void:
	# Transporte le mode sélectionné jusqu'au lobby (effectif + intention classée) via MatchConfig.
	var m = _mode_def(_selected_mode)
	var mc := get_node_or_null("/root/MatchConfig")
	if mc != null and m != null:
		mc.set_mode(m["id"], int(m["count"]), bool(m["ranked"]))
	_go("res://scenes/ui/lobby_screen.tscn")

func _on_characters_pressed() -> void:
	_go("res://scenes/ui/characters_screen.tscn")

func _on_inventory_pressed() -> void:
	_go("res://scenes/ui/shop.tscn")

func _on_profile_pressed() -> void:
	_go("res://scenes/ui/profile.tscn")

func _on_leaderboard_pressed() -> void:
	_go("res://scenes/ui/leaderboard.tscn")

func _on_settings_pressed() -> void:
	_go("res://scenes/ui/settings.tscn")

func _mode_def(mode_id: String):
	for m in MODES:
		if m["id"] == mode_id:
			return m
	return null


# =========================================================
# FABRIQUES DE NŒUDS / STYLES (charte §2, cohérent avec profile.gd)
# =========================================================
func _card_title(key: String) -> Label:
	var l := Label.new()
	l.text = key  # clé brute -> auto-traduction
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ACCENT)
	return l

func _body(key: String) -> Label:
	var l := Label.new()
	l.text = key  # clé brute -> auto-traduction
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _style_cta(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(16.0)
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
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)

func _style_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.bg_color = Color(1, 1, 1, 0.0)
	normal.content_margin_left = 16.0
	normal.content_margin_top = 10.0
	normal.content_margin_right = 16.0
	normal.content_margin_bottom = 10.0
	if active:
		normal.border_width_bottom = 3
		normal.border_color = ACCENT
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.06)
	hover.border_width_bottom = 3
	hover.border_color = ACCENT if active else Color(ACCENT, 0.5)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)

func _style_icon_button(btn: Button, accent: Color) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	# Police condensée de la charte (§2) — cohérence avec les onglets et le CTA (les glyphes ⚙/⏻
	# tombaient sinon sur la police par défaut de Godot).
	btn.add_theme_font_override("font", _font)
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.bg_color = Color(1, 1, 1, 0.03)
	normal.set_border_width_all(1)
	normal.border_color = Color(accent, 0.5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.18)
	hover.border_color = accent
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", TEXT)

func _style_danger_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(10.0)
	normal.bg_color = Color(DANGER, 0.16)
	normal.set_border_width_all(2)
	normal.border_color = DANGER
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(DANGER, 0.32)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)


# Vide un conteneur sans laisser de doublons (cf. profile.gd / lobby_screen.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
