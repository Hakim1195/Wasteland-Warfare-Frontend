extends Control

# =========================================================================
# Écran PERSONNAGES (sprint RPG & Survie) — charte « Warzone Command » §2
# =========================================================================
# Écran NEUF accessible depuis la navbar du menu principal (onglet « PERSONNAGES »). Le joueur voit
# SES héros (1 par faction, 10 factions) et sélectionne un héros pour afficher TOUTES ses stats
# détaillées : niveau, barre d'XP, PV/PA/PB/PP/Régén (au niveau courant ET au niveau 50 = cap), pouvoir
# de héros et paliers d'amélioration (franchis / à venir).
#
# Règle d'Or §6.1 : VUE pure — AUCUNE logique de jeu/RPG ici. TOUT vient du backend (GET
# /api/v1/heroes) relayé par NetworkManager.heroes_loaded ; lecture DÉFENSIVE (int() sur les nombres,
# piège float §5). La résolution faction_id -> couleur d'accent / portrait 2D / modèle 3D se fait via
# le catalogue data-driven resources/factions/*.tres (mêmes garde-fous que profile.gd / main_menu.gd ;
# l'`id` de chaque .tres = la clé backend snake_case). L'emplacement 3D réutilise le composant
# hero_viewport_3d (repli portrait 2D puis carte colorée, comme main_menu.gd:_apply_hero).

# --- Nœuds câblés via @export + NodePath (drag-drop éditeur, pas de $chemin codé en dur) ---
@export var panel: Control
@export var hero_list: VBoxContainer       # GAUCHE : cartes de héros (générées en code)
@export var hero_stage: Control            # DROITE : emplacement 3D/portrait (rempli en code)
@export var detail_box: VBoxContainer      # DROITE : détail textuel (reconstruit à la sélection)
@export var status_label: Label

# Helpers de charte (§2) + composant héros 3D — préchargés (pas de class_name, prudence cache d'import).
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const HeroViewport3DScene = preload("res://scenes/components/hero_viewport_3d.tscn")
# Header CANONIQUE partagé (§8.94) — remplace l'ex-HeaderBar maison + bouton RETOUR.
const TopNav = preload("res://scripts/ui/top_nav.gd")
# Vue partagée des caractéristiques (SOURCE UNIQUE de STAT_ROWS + formatage) — mutualisée avec
# faction_selection.gd (DRY : aucun libellé ni format de stat dupliqué).
const HeroStatsView = preload("res://scripts/ui/hero_stats_view.gd")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)    # or (récompense / niveau)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (eyebrow / muet)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)  # surface secondaire
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)  # rouge

# --- Factions data-driven (id -> ressource .tres), garde-fous de profile.gd / faction_selection.gd ---
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

var _font: SystemFont
var _factions: Dictionary = {}     # faction_id -> ressource .tres (accent_color, hero_path, hero_model_path)
var _heroes: Array = []            # roster reçu du backend (liste de Dictionary)
var _selected_index: int = -1
var _cards: Array = []             # PanelContainer par héros (pour la surbrillance de sélection)
# Chips « SÉLECTIONNÉ » (§8.93) : index de HÉROS -> Label (un seul visible à la fois). Indexé par
# index de héros (et non par position dans _cards) → insensible à une entrée de roster non-Dictionary.
var _chips: Dictionary = {}
# Emplacement héros (montés une fois dans hero_stage, basculés selon la faction sélectionnée).
var _hero3d = null                 # instance hero_viewport_3d (API non typée : set_model/set_accent)
var _portrait: TextureRect = null  # repli portrait 2D
var _placeholder: ColorRect = null # repli carte colorée


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Entrée d'écran UNIFORME (§8.96) : fondu + léger glissement, identique sur tous les écrans hub.
	WarzoneUI.animate_screen_enter(self)

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# Nav PARTAGÉE (§8.94) : header canonique. Remplace l'ex-en-tête maison (titre + RETOUR) — c'est
	# l'onglet ACTIF qui identifie désormais la section, et ÉCHAP (géré par la nav) qui ramène au QG.
	# ⚠️ active_tab réglé AVANT add_child (lu au _ready du composant).
	var nav := TopNav.new()
	nav.active_tab = "characters"
	add_child(nav)
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Catalogue des factions (résolution id -> couleur / portrait / modèle 3D).
	_load_factions()
	# Emplacement héros (3D + replis), monté une fois.
	_build_hero_stage()

	# État initial : invite à sélectionner (écrasé dès que le roster arrive et qu'on auto-sélectionne).
	_show_select_hint()
	_set_status(tr("CHAR_STATUS_LOADING"))

	# Réseau (R/RPG) : roster des héros via NetworkManager (GET /api/v1/heroes).
	NetworkManager.heroes_loaded.connect(_on_heroes_loaded)
	NetworkManager.fetch_heroes()


# =========================================================
# RÉCEPTION DU ROSTER (GET /api/v1/heroes)
# =========================================================
func _on_heroes_loaded(heroes: Array) -> void:
	if not is_inside_tree():
		return
	_heroes = heroes
	_build_cards()
	if _heroes.is_empty():
		_set_status(tr("CHAR_STATUS_EMPTY"))
		_show_select_hint()
		return
	# Auto-sélection : le personnage CHOISI (§8.93) s'il est encore au roster, sinon le 1er (le
	# détail n'est jamais vide). `persist` reste FAUX : ouvrir l'écran ne vaut PAS un choix.
	_select(_initial_index())
	_set_status(tr("CHAR_STATUS_LOADED"))

# Index d'ouverture : celui du personnage persisté (§8.93) s'il figure dans le roster reçu, sinon 0.
# Robuste à un id inconnu (faction retirée du catalogue, roster serveur différent) → repli 0.
func _initial_index() -> int:
	var fid := SettingsManager.get_selected_faction()
	if fid != "":
		for i in _heroes.size():
			var h = _heroes[i]
			if typeof(h) == TYPE_DICTIONARY and str(h.get("faction_id", "")) == fid:
				return i
	return 0


# =========================================================
# GAUCHE — LISTE DES HÉROS (cartes générées en code)
# =========================================================
func _build_cards() -> void:
	_clear(hero_list)
	_cards.clear()
	_chips.clear()
	for i in _heroes.size():
		var hero = _heroes[i]
		if typeof(hero) != TYPE_DICTIONARY:
			continue
		var card := _make_hero_card(i, hero)
		hero_list.add_child(card)
		_cards.append(card)

# Chip d'accès TEMPORAIRE (chantier T) — même fabrique que le chip « SÉLECTIONNÉ » (§8.93) pour
# rester dans la charte : encoches de coin, fond translucide, filet 1 px à la couleur donnée.
func _access_chip(text: String, color: Color, tip: String) -> PanelContainer:
	var lbl := Label.new()
	lbl.text = text
	lbl.tooltip_text = tip
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	style.bg_color = Color(color, 0.14)
	style.set_border_width_all(1)
	style.border_color = color
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", style)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.tooltip_text = tip
	box.add_child(lbl)
	WarzoneUI.add_corner_notches(box, 5.0, color)
	return box


func _make_hero_card(index: int, hero: Dictionary) -> PanelContainer:
	var fid := str(hero.get("faction_id", ""))
	var owned := bool(hero.get("owned", true))

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(false))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# Pastille verticale à la couleur de la faction.
	var dot := ColorRect.new()
	dot.color = _faction_color(fid)
	dot.custom_minimum_size = Vector2(8, 42)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = _faction_display_name(fid, hero).to_upper()
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)

	var lvl_lbl := Label.new()
	lvl_lbl.text = tr("COMMON_LEVEL") + " " + str(int(hero.get("level", 1)))
	lvl_lbl.add_theme_font_override("font", _font)
	lvl_lbl.add_theme_font_size_override("font_size", 13)
	lvl_lbl.add_theme_color_override("font_color", ACCENT)
	lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lvl_lbl)

	# Chip or « SÉLECTIONNÉ » (§8.93) : rend le choix EXPLICITE (avant, la sélection n'était qu'une
	# surbrillance éphémère). Masqué par défaut, révélé par _select sur la seule carte choisie.
	var chip := Label.new()
	chip.text = "CHAR_SELECTED_BADGE"  # clé brute -> auto-traduction (FR/EN/IT)
	chip.add_theme_font_override("font", _font)
	chip.add_theme_font_size_override("font_size", 11)
	chip.add_theme_color_override("font_color", GOLD)
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style := StyleBoxFlat.new()
	chip_style.set_corner_radius_all(0)
	chip_style.bg_color = Color(GOLD, 0.14)
	chip_style.set_border_width_all(1)
	chip_style.border_color = GOLD
	chip_style.content_margin_left = 8.0
	chip_style.content_margin_right = 8.0
	chip_style.content_margin_top = 3.0
	chip_style.content_margin_bottom = 3.0
	var chip_box := PanelContainer.new()
	chip_box.add_theme_stylebox_override("panel", chip_style)
	chip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_box.add_child(chip)
	chip_box.visible = false
	h.add_child(chip_box)
	WarzoneUI.add_corner_notches(chip_box, 5.0, GOLD)
	_chips[index] = chip_box

	# --- ÉTAT D'ACCÈS (chantier T) : 4 rendus au lieu du seul cadenas. Le serveur envoie désormais
	# un accès RÉEL par personnage (`access.type`) — fini le « owned: true partout ».
	#   free / owned → rien (état normal)                  rotation → chip OR « ★ n/m »
	#   pass         → chip CYAN « PASS »                  locked   → cadenas ✕ + prix
	# Repli : un serveur antérieur n'envoie pas `access` → on retombe sur `owned` (comportement
	# historique), ce qui donne exactement l'ancien écran.
	var access: Dictionary = hero.get("access", {}) if typeof(hero.get("access")) == TYPE_DICTIONARY else {}
	var access_type := str(access.get("type", "owned" if owned else "locked"))
	match access_type:
		"rotation":
			var rot_txt := "★ %d/%d" % [int(access.get("free_games_left", 0)),
				int(access.get("free_games_max", 0))]
			h.add_child(_access_chip(rot_txt, GOLD, tr("CHAR_ROTATION_TIP")))
		"pass":
			h.add_child(_access_chip(tr("CHAR_PASS_CHIP"), ACCENT, tr("CHAR_PASS_TIP")))
		"locked":
			var lock := Label.new()
			lock.text = "✕"
			# Le prix rend le cadenas ACTIONNABLE (« combien pour le débloquer ? ») au lieu d'un
			# simple refus ; 0 = prix inconnu (serveur antérieur) → on garde le libellé seul.
			var price := int(access.get("price", 0))
			lock.tooltip_text = (tr("CHAR_LOCKED_PRICE") % price) if price > 0 else tr("CHAR_LOCKED")
			lock.add_theme_font_size_override("font_size", 18)
			lock.add_theme_color_override("font_color", MUTED)
			lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(lock)

	# Bouton transparent superposé : capte le clic sur toute la carte (le contenu ignore la souris ;
	# même pattern que main_menu._make_mode_card). Ajouté en DERNIER → au-dessus, donc cliquable.
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.pressed.connect(func() -> void: _on_card_pressed(index))
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	card.add_child(btn)

	WarzoneUI.add_corner_notches(card, 12.0)
	return card

func _on_card_pressed(index: int) -> void:
	AudioManager.play_sfx("click")
	# Clic UTILISATEUR = choix EXPLICITE → persisté (§8.93).
	_select(index, true)

# `persist` : n'écrit le choix que sur une sélection EXPLICITE de l'utilisateur. L'auto-sélection
# d'ouverture (_on_heroes_loaded) passe FAUX — sinon un joueur n'ayant jamais choisi verrait le
# simple fait de consulter cet écran figer le héros du menu sur le 1er du roster, alors que le menu
# doit rester sur sa dernière faction JOUÉE tant qu'aucun choix n'est fait (§8.93, repli (2)).
func _select(index: int, persist: bool = false) -> void:
	if index < 0 or index >= _heroes.size():
		return
	_selected_index = index
	# Surbrillance de la carte sélectionnée (liseré cyan épais + fond teinté).
	for i in _cards.size():
		var c = _cards[i]
		if c != null and is_instance_valid(c):
			c.add_theme_stylebox_override("panel", _card_style(i == index))
	# Chip or « SÉLECTIONNÉ » : porté par la seule carte choisie (indexé par index de HÉROS).
	for idx in _chips:
		var chip = _chips[idx]
		if chip != null and is_instance_valid(chip):
			chip.visible = (int(idx) == index)
	var hero = _heroes[index]
	if typeof(hero) != TYPE_DICTIONARY:
		return
	_apply_hero_stage(str(hero.get("faction_id", "")))
	_populate_detail(hero)
	if persist:
		SettingsManager.set_selected_faction(str(hero.get("faction_id", "")))


# =========================================================
# DROITE — EMPLACEMENT HÉROS (3D → portrait 2D → carte colorée)
# =========================================================
# Réutilise le composant hero_viewport_3d (monté une fois). Bascule 3D-first / repli 2D / placeholder
# selon la faction sélectionnée — logique reprise telle quelle de main_menu.gd:_apply_hero.
func _build_hero_stage() -> void:
	if hero_stage == null:
		return
	# Carte colorée (toujours présente, dessous).
	_placeholder = ColorRect.new()
	_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder.color = SURFACE
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_stage.add_child(_placeholder)
	# Portrait 2D (au-dessus du repli coloré).
	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.visible = false
	hero_stage.add_child(_portrait)
	# Héros 3D (au-dessus) — son .tscn porte des ancres plein-cadre + stretch → remplit l'emplacement.
	_hero3d = HeroViewport3DScene.instantiate()
	hero_stage.add_child(_hero3d)
	_hero3d.visible = false

func _apply_hero_stage(fid: String) -> void:
	var accent: Color = SURFACE
	var model_path := ""
	var img_path := ""
	if _factions.has(fid):
		var f = _factions[fid]
		if f != null:
			if f.get("accent_color") != null:
				accent = f.accent_color
			if f.get("hero_model_path") != null:
				model_path = str(f.get("hero_model_path"))
			if f.get("hero_path") != null:
				img_path = str(f.get("hero_path"))

	# --- Chemin 3D : .glb présent → héros 3D, replis masqués. ---
	if _hero3d != null and _hero3d.set_model(model_path):
		_hero3d.set_accent(accent)
		_hero3d.visible = true
		if _portrait: _portrait.visible = false
		if _placeholder: _placeholder.visible = false
		return
	if _hero3d != null:
		_hero3d.visible = false

	# --- Repli 2D : portrait de la faction si présent. ---
	var tex = null
	if img_path != "" and ResourceLoader.exists(img_path):
		tex = load(img_path)
	if tex != null:
		if _portrait:
			_portrait.texture = tex
			_portrait.visible = true
		if _placeholder: _placeholder.visible = false
	else:
		# --- Dernier repli : carte colorée teintée à l'accent de la faction. ---
		if _portrait: _portrait.visible = false
		if _placeholder:
			_placeholder.visible = true
			_placeholder.color = accent.darkened(0.25)


# =========================================================
# DROITE — DÉTAIL TEXTUEL DU HÉROS (reconstruit à chaque sélection)
# =========================================================
func _populate_detail(hero: Dictionary) -> void:
	_clear(detail_box)
	var fid := str(hero.get("faction_id", ""))
	var fac_color := _faction_color(fid)

	# --- En-tête : chevron coloré + nom de faction (grand) ▸ niveau (or) ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	detail_box.add_child(header)

	var chevron := Label.new()
	chevron.text = "❯"
	chevron.add_theme_font_override("font", _font)
	chevron.add_theme_font_size_override("font_size", 28)
	chevron.add_theme_color_override("font_color", fac_color)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(chevron)

	var name_lbl := Label.new()
	name_lbl.text = _faction_display_name(fid, hero).to_upper()
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(name_lbl)

	var level := int(hero.get("level", 1))
	var lvl_eyebrow := Label.new()
	lvl_eyebrow.text = tr("COMMON_LEVEL")
	lvl_eyebrow.add_theme_font_override("font", _font)
	lvl_eyebrow.add_theme_font_size_override("font_size", 13)
	lvl_eyebrow.add_theme_color_override("font_color", ACCENT)
	lvl_eyebrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(lvl_eyebrow)

	var lvl_value := Label.new()
	lvl_value.text = str(level)
	lvl_value.add_theme_font_override("font", _font)
	lvl_value.add_theme_font_size_override("font_size", 30)
	lvl_value.add_theme_color_override("font_color", GOLD)
	lvl_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(lvl_value)

	# --- AVERTISSEMENT DE PERTE DE PROGRESSION (chantier T) ---------------------------------------
	# Honnêteté indispensable : la progression d'un héros joué sous un accès TEMPORAIRE (rotation
	# de la semaine, déblocage par un Pass) est PURGÉE à l'expiration de cet accès (chantier Q).
	# Le joueur doit le savoir AVANT d'y investir des heures — pas le découvrir un lundi matin.
	var acc: Dictionary = hero.get("access", {}) if typeof(hero.get("access")) == TYPE_DICTIONARY else {}
	if str(acc.get("type", "")) in ["rotation", "pass"]:
		var warn := Label.new()
		warn.text = tr("CHAR_TEMP_WARNING")
		warn.add_theme_font_override("font", _font)
		warn.add_theme_font_size_override("font_size", 13)
		warn.add_theme_color_override("font_color", MUTED)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_box.add_child(warn)

	# Identité du meneur (refonte 2026-07-18) : « GÉNÉRAL VIKTOR "IRONLINE" STAHL » sous le nom
	# de faction — rang traduit, nom/callsign invariants (lus du .tres local ; masquée si absents).
	var leader := _leader_title(fid)
	if leader != "":
		var leader_lbl := Label.new()
		leader_lbl.text = leader.to_upper()
		leader_lbl.add_theme_font_override("font", _font)
		leader_lbl.add_theme_font_size_override("font_size", 15)
		leader_lbl.add_theme_color_override("font_color", Color(fac_color, 0.9))
		detail_box.add_child(leader_lbl)

	# --- Barre d'XP (remplie à xp_in_level / xp_for_level) + « XP avant niveau suivant » ---
	detail_box.add_child(_make_xp_block(hero))
	WarzoneUI.add_filet(detail_box)

	# --- Statistiques détaillées (actuel vs niveau 50 = cap) + descriptions joueur ---
	detail_box.add_child(_section_header("CHAR_STATS_HEADER"))
	detail_box.add_child(_make_stats_block(hero))

	# --- Pouvoir de héros — clés locales TRADUITES par faction (i18n 2026-07-18), repli sur la
	#     description serveur (hero_power, anglais invariant) si les clés manquent. ---
	detail_box.add_child(_section_header("CHAR_POWER_HEADER"))
	var power := _body_label(_hero_power_text(fid, hero))
	power.add_theme_color_override("font_color", TEXT)
	detail_box.add_child(power)

	# --- Paliers d'amélioration (franchis vs à venir) ---
	detail_box.add_child(_section_header("CHAR_MILESTONES_HEADER"))
	var milestones = hero.get("milestones", [])
	if typeof(milestones) == TYPE_ARRAY:
		for m in milestones:
			if typeof(m) == TYPE_DICTIONARY:
				detail_box.add_child(_make_milestone_row(m))

# Bloc XP « PROGRESSION » : eyebrow + barre cyan + « X / Y XP DANS LE NIVEAU » (les points possédés
# dans le niveau en cours) + « X XP AVANT LE NIVEAU SUIVANT » (ou « NIVEAU MAX ») + total cumulé à vie.
func _make_xp_block(hero: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var xp_in := int(hero.get("xp_in_level", 0))
	var xp_for := int(hero.get("xp_for_level", 0))
	var xp_to := int(hero.get("xp_to_next", 0))
	var xp_total := int(hero.get("xp_total", 0))
	var at_max := xp_for <= 0

	box.add_child(_section_header("CHAR_XP_HEADER"))

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.show_percentage = false
	bar.max_value = maxi(xp_for, 1)
	bar.value = (bar.max_value if at_max else clampi(xp_in, 0, xp_for))
	_style_xp_bar(bar)
	box.add_child(bar)

	# Points d'XP POSSÉDÉS dans le niveau en cours (ce que l'utilisateur a demandé), en cyan.
	var in_level := Label.new()
	in_level.add_theme_font_override("font", _font)
	in_level.add_theme_font_size_override("font_size", 15)
	if at_max:
		in_level.text = tr("CHAR_LEVEL_MAX")
		in_level.add_theme_color_override("font_color", GOLD)
	else:
		in_level.text = tr("CHAR_XP_IN_LEVEL") % [_format_thousands(xp_in), _format_thousands(xp_for)]
		in_level.add_theme_color_override("font_color", ACCENT)
	box.add_child(in_level)

	# « X XP avant le niveau suivant » (masqué au plafond — plus de niveau suivant).
	if not at_max:
		var caption := Label.new()
		caption.add_theme_font_override("font", _font)
		caption.add_theme_font_size_override("font_size", 13)
		caption.text = tr("CHAR_XP_TO_NEXT") % _format_thousands(xp_to)
		caption.add_theme_color_override("font_color", MUTED)
		box.add_child(caption)

	# Total d'XP cumulé à vie pour ce héros (contexte méta-progression).
	var total_lbl := Label.new()
	total_lbl.add_theme_font_override("font", _font)
	total_lbl.add_theme_font_size_override("font_size", 13)
	total_lbl.text = tr("CHAR_XP_TOTAL") % _format_thousands(xp_total)
	total_lbl.add_theme_color_override("font_color", MUTED)
	box.add_child(total_lbl)
	return box

# Bloc de stats : en-tête de colonnes (ACTUEL / NIV. 50) puis, PAR stat, une ligne
# « ABRÉV — NOM COMPLET » + valeurs (actuel / max en colonnes fixes alignées à droite) et, en dessous,
# une DESCRIPTION joueur (muette, retour à la ligne) pour que chaque statistique soit comprise.
func _make_stats_block(hero: Dictionary) -> VBoxContainer:
	var stats = hero.get("stats", {})
	var stats_max = hero.get("stats_max", {})
	if typeof(stats) != TYPE_DICTIONARY: stats = {}
	if typeof(stats_max) != TYPE_DICTIONARY: stats_max = {}

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	# En-tête de colonnes (eyebrow), aligné sur les colonnes de valeurs à largeur fixe.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_value_col(tr("CHAR_COL_CURRENT"), ACCENT, 13))
	head.add_child(_value_col(tr("CHAR_COL_MAX"), MUTED, 13))
	box.add_child(head)

	for row in HeroStatsView.STAT_ROWS:
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 1)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var name_lbl := Label.new()
		name_lbl.text = tr(str(row["key"])) + "  —  " + tr(str(row["name"]))
		name_lbl.add_theme_font_override("font", _font)
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", TEXT)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name_lbl)
		line.add_child(_value_col(HeroStatsView.format_stat(stats, row), TEXT, 18))
		line.add_child(_value_col(HeroStatsView.format_stat(stats_max, row), MUTED, 18))
		item.add_child(line)

		var desc := Label.new()
		desc.text = tr(str(row["desc"]))
		desc.add_theme_font_override("font", _font)
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(desc)

		box.add_child(item)
	return box

# Cellule de valeur à largeur fixe, alignée à droite → colonnes ACTUEL / NIV. 50 alignées entre stats.
func _value_col(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(92, 0)
	return l

# Ligne de palier : « NIV X » (or si franchi) ▸ bonus formaté ▸ état (✓ franchi / À VENIR).
func _make_milestone_row(m: Dictionary) -> PanelContainer:
	var unlocked := bool(m.get("unlocked", false))
	var lvl := int(m.get("level", 0))

	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT, 0.08) if unlocked else SURFACE
	sb.border_width_left = 3
	sb.border_color = ACCENT if unlocked else Color(MUTED, 0.5)
	sb.content_margin_left = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var lvl_lbl := Label.new()
	lvl_lbl.text = tr("CHAR_MILESTONE_LEVEL") % lvl
	lvl_lbl.add_theme_font_override("font", _font)
	lvl_lbl.add_theme_font_size_override("font_size", 15)
	lvl_lbl.add_theme_color_override("font_color", GOLD if unlocked else MUTED)
	lvl_lbl.custom_minimum_size = Vector2(74, 0)
	lvl_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(lvl_lbl)

	var bonus_lbl := Label.new()
	bonus_lbl.text = _format_bonus(m.get("bonus", {}))
	bonus_lbl.add_theme_font_override("font", _font)
	bonus_lbl.add_theme_font_size_override("font_size", 15)
	bonus_lbl.add_theme_color_override("font_color", TEXT if unlocked else MUTED)
	bonus_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bonus_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(bonus_lbl)

	var status := Label.new()
	status.text = "✓" if unlocked else tr("CHAR_MILESTONE_UPCOMING")
	status.add_theme_font_override("font", _font)
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", ACCENT if unlocked else MUTED)
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(status)
	return row

# Formate le bonus additif d'un palier en libellé lisible (ex. « +50 PV, +1 PA », « +30 PV, +1% PB »).
# Ordre fixe pv_max → pa → pb ; pb est un taux affiché en %. Entrées JSON en float → int() (piège §5).
func _format_bonus(bonus) -> String:
	if typeof(bonus) != TYPE_DICTIONARY:
		return "—"
	var parts := []
	if bonus.has("pv_max"):
		parts.append("+%d %s" % [int(bonus["pv_max"]), tr("CHAR_STAT_PV")])
	if bonus.has("pa"):
		parts.append("+%d %s" % [int(bonus["pa"]), tr("CHAR_STAT_PA")])
	if bonus.has("pb"):
		parts.append("+%d%% %s" % [int(round(float(bonus["pb"]) * 100.0)), tr("CHAR_STAT_PB")])
	return ", ".join(parts) if not parts.is_empty() else "—"


# =========================================================
# FABRIQUES DE NŒUDS / STYLES (charte §2, cohérent avec profile.gd)
# =========================================================
func _section_header(key: String) -> Label:
	var l := Label.new()
	l.text = key  # clé brute -> auto-traduction (FR/EN/IT)
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", ACCENT)
	return l

func _body_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# Invite affichée dans le panneau de détail tant qu'aucun héros n'est sélectionné (ou roster vide).
func _show_select_hint() -> void:
	_clear(detail_box)
	var hint := _body_label(tr("CHAR_SELECT_HINT"))
	hint.add_theme_color_override("font_color", MUTED)
	detail_box.add_child(hint)

# Style d'une carte de héros (gauche) : surface gunmetal + liseré cyan gauche (épais + teinté si sélectionnée).
func _card_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	if selected:
		sb.bg_color = Color(ACCENT, 0.16)
		sb.border_width_left = 5
		sb.border_color = ACCENT
	else:
		sb.bg_color = SURFACE
		sb.border_width_left = 3
		sb.border_color = Color(ACCENT, 0.4)
	return sb

# Barre d'XP cyan (fond gunmetal, remplissage cyan) — angulaire (identique à profile.gd).
func _style_xp_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = SURFACE
	bg.set_corner_radius_all(0)
	bg.set_border_width_all(1)
	bg.border_color = Color(ACCENT, 0.35)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


# =========================================================
# CHARGEMENT DES FACTIONS (id -> ressource), garde-fous de profile.gd / main_menu.gd
# =========================================================
func _load_factions() -> void:
	var paths := _scan_faction_paths()
	if paths.is_empty():
		paths = FALLBACK_PATHS.duplicate()
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		# Duck-typing : on accepte toute ressource exposant un id (pas de dépendance au class_name).
		if res != null and res.get("id") != null:
			_factions[str(res.id)] = res

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

func _faction_color(fid: String) -> Color:
	if _factions.has(fid):
		var f = _factions[fid]
		if f != null and f.get("accent_color") != null:
			return f.accent_color
	return ACCENT

# Nom de faction AFFICHABLE (i18n 2026-07-18) : priorité au .tres LOCAL (nom EN invariant —
# source unique avec le draft/VS/rapport), repli sur le faction_name du backend puis l'id.
func _faction_display_name(fid: String, hero: Dictionary) -> String:
	if _factions.has(fid):
		var f = _factions[fid]
		if f != null and f.get("name") != null and str(f.name) != "":
			return str(f.name)
	return str(hero.get("faction_name", fid))

# Identité du meneur de la faction (rang traduit + nom/callsign invariants) — "" si .tres legacy.
func _leader_title(fid: String) -> String:
	if _factions.has(fid):
		return WarzoneUI.faction_leader_title(_factions[fid])
	return ""

# Ligne « POUVOIR » du héros : clés locales traduites par faction (HERO_POWER_NAME_<ID> /
# HERO_POWER_DESC_<ID>), repli sur le hero_power du backend (clé absente → jamais de clé brute).
func _hero_power_text(fid: String, hero: Dictionary) -> String:
	var key_name := "HERO_POWER_NAME_" + fid.to_upper()
	var key_desc := "HERO_POWER_DESC_" + fid.to_upper()
	var n := tr(key_name)
	if n != key_name:
		var d := tr(key_desc)
		return (n + " — " + d) if d != key_desc else n
	return str(hero.get("hero_power", ""))


# =========================================================
# UTILITAIRES
# =========================================================
# Sépare les milliers par une fine espace (lisibilité, comme profile.gd / leaderboard.gd).
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

# Vide un conteneur sans laisser de doublons (cf. profile.gd / leaderboard.gd / shop.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

