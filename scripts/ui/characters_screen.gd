extends Control

# =========================================================================
# Écran PERSONNAGES (sprint RPG & Survie) — charte « Warzone Command » §2
# =========================================================================
# Écran NEUF accessible depuis la navbar du menu principal (onglet « PERSONNAGES »). Le joueur voit
# SES héros (1 par faction, 10 factions) sous forme de ROSTER en grille (chantier W) : un clic sur
# une carte ouvre la FICHE du héros (viewer 3D/2D + détail complet : niveau, XP, PV/PA/PB/PP/Régén,
# pouvoir de héros, paliers). Machine à états à DEUX vues sœurs (RosterView / SheetView), une seule
# visible à la fois — cf. _state / _sheet_index / _show_roster / _show_sheet plus bas.
#
# Règle d'Or §6.1 : VUE pure — AUCUNE logique de jeu/RPG ici. TOUT vient du backend (GET
# /api/v1/heroes) relayé par NetworkManager.heroes_loaded ; lecture DÉFENSIVE (int() sur les nombres,
# piège float §5). La résolution faction_id -> couleur d'accent / portrait 2D / modèle 3D se fait via
# le catalogue data-driven resources/factions/*.tres (mêmes garde-fous que profile.gd / main_menu.gd ;
# l'`id` de chaque .tres = la clé backend snake_case). L'emplacement 3D de la FICHE réutilise le
# composant hero_viewport_3d (repli portrait 2D puis carte colorée, comme main_menu.gd:_apply_hero) ;
# les cartes du ROSTER, elles, restent STATIQUES (portrait 2D / carte colorée seulement — jamais de
# viewport 3D par carte, coût GPU prohibitif pour 10 vignettes simultanées).

# --- Nœuds câblés via @export + NodePath (drag-drop éditeur, pas de $chemin codé en dur) ---
@export var panel: Control
@export var roster_view: Control           # conteneur plein-cadre : ROSTER (grille, chantier W)
@export var hero_grid: GridContainer       # grille 5×2 des cartes héros (générées en code)
@export var roster_count_label: Label      # « X/Y PERSONNAGES POSSÉDÉS » dans l'en-tête du roster
@export var sheet_view: Control            # conteneur plein-cadre : FICHE du héros ouvert
@export var sheet_back_button: Button      # « ❮ ROSTER » — referme la fiche, retour à la grille
@export var hero_stage: Control            # FICHE : emplacement 3D/portrait (rempli en code)
@export var detail_box: VBoxContainer      # FICHE : détail textuel (reconstruit à l'ouverture)
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

# --- Roster (chantier W) : dimensions de carte + hauteur de vignette ---
const CARD_SIZE := Vector2(200, 260)
const CARD_THUMB_HEIGHT := 112.0
# Transition ROSTER <-> FICHE : fondu alpha seul (cf. _fade_in plus bas pour le pourquoi).
const VIEW_FADE_TIME := 0.15

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

# --- Machine à états (chantier W) : ROSTER (grille) <-> FICHE (viewer + détail existants). Contrat
# d'API EXACT attendu par les tâches suivantes (fiche à onglets) — noms et types à ne pas changer. ---
var _state: String = "roster"      # "roster" | "sheet"
var _sheet_index: int = -1         # index dans _heroes de la fiche actuellement ouverte (-1 = aucune)

# Emplacement héros de la FICHE (montés une fois dans hero_stage, basculés selon le héros ouvert).
var _hero3d = null                 # instance hero_viewport_3d (API non typée : set_model/set_accent)
var _portrait: TextureRect = null  # repli portrait 2D
var _placeholder: ColorRect = null # repli carte colorée

# Tween de transition ROSTER <-> FICHE (revue de code, point 4) : UNE seule référence, quel que
# soit le Control animé (roster_view ou sheet_view) — tuée avant toute nouvelle bascule pour ne
# jamais empiler deux fondus. Sans ça, une bascule roster<->fiche rapide (double clic, va-et-vient)
# laisse l'ANCIEN Tween forcer modulate:a à 1 en pleine rampe du NOUVEAU → flash/saut visible. Même
# pattern que hud.gd (_fade_tween) / phase_banner.gd (_tween).
var _view_tween: Tween


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
	# Emplacement héros de la FICHE (3D + replis), monté une fois — contenu provisoire (chantier W) :
	# la tâche suivante bâtit la fiche définitive par-dessus cette structure d'accueil.
	_build_hero_stage()

	# Bouton RETOUR de la fiche (chantier W) : simple navigation d'écran, aucune règle de jeu ici.
	if sheet_back_button:
		WarzoneUI.apply_ghost_button(sheet_back_button)
		WarzoneUI.wire_button_feedback(sheet_back_button)
		sheet_back_button.pressed.connect(_show_roster)

	# État initial (chantier W) : on ouvre TOUJOURS sur le roster, AUCUNE fiche pré-ouverte. Le
	# personnage persisté (SettingsManager) ne sert plus qu'à marquer le badge ★ FAVORI dans la
	# grille — il ne choisit plus jamais de fiche d'ouverture (comportement RETIRÉ, cf. rapport).
	# Délègue à _show_roster() (revue de code, point 5) au lieu de dupliquer l'état ici : c'est
	# l'API que la tâche suivante (fiche à onglets) étend — tout ce qu'elle y ajoutera s'appliquera
	# alors AUSSI à l'entrée d'écran, sans code dupliqué à retrouver et modifier en double.
	# animate=false : voir le commentaire de _show_roster pour le pourquoi (double fondu évité).
	_show_roster(false)

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
	_build_roster_grid()
	_update_roster_count()
	if _heroes.is_empty():
		_set_status(tr("CHAR_STATUS_EMPTY"))
		return
	_set_status(tr("CHAR_STATUS_LOADED"))


# =========================================================
# MACHINE À ÉTATS — ROSTER (grille) <-> FICHE (viewer + détail existants)
# =========================================================
# Deux conteneurs FRÈRES (roster_view / sheet_view), un seul visible à la fois. Contrat d'API à
# respecter EXACTEMENT (noms/signatures) : les tâches suivantes (fiche détaillée à onglets)
# s'appuient dessus pour ouvrir/fermer la fiche sans connaître le reste de cet écran.
# `animate` (revue de code, point 5) : true par défaut (retour normal depuis la FICHE via
# sheet_back_button -> fondu). L'entrée d'écran (_ready) appelle _show_roster(false) : la RACINE de
# l'écran fait déjà son propre fondu (WarzoneUI.animate_screen_enter) — fondre EN PLUS roster_view
# à l'entrée ferait un double fondu (2 tweens sur 2 Color différentes → sursaut visuel).
func _show_roster(animate: bool = true) -> void:
	_state = "roster"
	_sheet_index = -1
	if sheet_view:
		sheet_view.visible = false
	if roster_view:
		roster_view.visible = true
		if animate:
			_fade_in(roster_view)

func _show_sheet(index: int) -> void:
	if index < 0 or index >= _heroes.size():
		return
	var hero = _heroes[index]
	if typeof(hero) != TYPE_DICTIONARY:
		return
	_state = "sheet"
	_sheet_index = index
	if roster_view:
		roster_view.visible = false
	if sheet_view:
		sheet_view.visible = true
		_fade_in(sheet_view)
	# Contenu PROVISOIRE (chantier W) : réutilise TEL QUEL le viewer + le détail EXISTANTS pour ce
	# héros — la tâche suivante construit la fiche définitive à onglets par-dessus cette structure
	# d'accueil (on ne réécrit ni _apply_hero_stage, ni _populate_detail).
	_apply_hero_stage(str(hero.get("faction_id", "")))
	_populate_detail(hero)

# Transition entre les deux vues : fondu alpha seul (0,15 s), PAS de glissement de position. Les
# deux vues sont enfants directs d'un VBoxContainer qui recalcule leur position à chaque passe de
# layout (contrairement à WarzoneUI.animate_screen_enter, appelé lui sur la racine de l'écran, hors
# de tout conteneur qui la repositionnerait) : un Tween sur `position` ici entrerait en conflit avec
# ce recalcul. `modulate:a` échappe totalement au tri du conteneur → transition propre, aucun saut
# de layout, quel que soit le nombre de cartes/la hauteur de la fiche.
func _fade_in(view: Control) -> void:
	if view == null or not is_instance_valid(view):
		return
	# Tue le fondu PRÉCÉDENT avant d'en lancer un nouveau (revue de code, point 4) — jamais deux
	# tweens empilés sur modulate:a (roster<->fiche basculé vite = flicker, cf. déclaration de
	# _view_tween plus haut).
	if _view_tween and _view_tween.is_valid():
		_view_tween.kill()
	view.modulate = Color(1, 1, 1, 0)
	_view_tween = view.create_tween()
	_view_tween.tween_property(view, "modulate:a", 1.0, VIEW_FADE_TIME)


# =========================================================
# ROSTER — GRILLE 5×2 (chantier W)
# =========================================================
# Reconstruit la grille depuis _heroes, dans l'ORDRE reçu du serveur (AUCUN tri : l'ordre stable est
# le repère visuel du joueur d'une session à l'autre). Indexée par index RÉEL dans _heroes (pas par
# position dans la grille) : une entrée non-Dictionary est ignorée sans décaler les cartes suivantes.
func _build_roster_grid() -> void:
	_clear(hero_grid)
	for i in _heroes.size():
		var hero = _heroes[i]
		if typeof(hero) != TYPE_DICTIONARY:
			continue
		hero_grid.add_child(_make_roster_card(i, hero))

# Compteur d'en-tête « X/Y PERSONNAGES POSSÉDÉS » : X = possession PERMANENTE (free/owned, ou repli
# owned==true si le bloc access manque — serveur antérieur), Y = taille totale du roster reçu.
func _update_roster_count() -> void:
	if roster_count_label == null:
		return
	var owned_count := 0
	for h in _heroes:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		if _is_permanent(h):
			owned_count += 1
	# Texte COMPOSÉ (valeurs numériques insérées) → auto-traduction désactivée, on traduit nous-mêmes
	# (même précaution que la pastille DÉFIS composée de top_nav.gd).
	roster_count_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	roster_count_label.text = tr("CHAR_ROSTER_COUNT") % [owned_count, _heroes.size()]

# Possession PERMANENTE (free/owned) — repli sur `owned` si le bloc `access` manque (serveur
# antérieur). SEUL point de lecture du champ `owned` de cet écran (revue de code, point 3) : repli
# à `true` — une donnée manquante est considérée POSSÉDÉE (jamais de cadenas sur une inconnue, un
# cadenas ne s'affiche QUE si `owned` vaut EXPLICITEMENT false). _make_roster_card appelle CETTE
# fonction au lieu de relire hero.get("owned", ...) lui-même avec un AUTRE repli, pour que le badge
# de carte et le compteur d'en-tête restent TOUJOURS d'accord — ne pas réintroduire un 2e point de
# lecture avec un repli différent, même si ça semble anodin (c'est précisément le bug corrigé ici).
func _is_permanent(hero: Dictionary) -> bool:
	var access: Dictionary = hero.get("access", {}) if typeof(hero.get("access")) == TYPE_DICTIONARY else {}
	if access.is_empty():
		return bool(hero.get("owned", true))
	return str(access.get("type", "")) in ["free", "owned"]


# Une carte du roster (PanelContainer ~200×260, style proche de l'existant + encoches + liseré à la
# couleur d'accent de la FACTION) : vignette statique, identité, faction, niveau, badge d'accès,
# badge FAVORI. Toute la carte est cliquable → ouvre la fiche de CE héros.
func _make_roster_card(index: int, hero: Dictionary) -> PanelContainer:
	var fid := str(hero.get("faction_id", ""))
	# Lu via _is_permanent (revue de code, point 3) — SOURCE UNIQUE du repli `owned`, jamais
	# hero.get("owned", ...) en direct ici : garde ce booléen et celui du compteur d'en-tête
	# (_update_roster_count, qui appelle la même fonction) TOUJOURS d'accord entre eux.
	var owned := _is_permanent(hero)
	var accent := _faction_color(fid)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _roster_card_style(accent, false))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	# --- Rangée FAVORI (haut, alignée à droite) : uniquement le héros du menu principal. Une
	# rangée en flux normal plutôt qu'un overlay ancré : la largeur du libellé varie avec la langue
	# (« ★ FAVORI » vs « ★ FAVORITE ») — un HBox évite tout chevauchement/troncature. ---
	var fav_fid := SettingsManager.get_selected_faction()
	var is_favorite := fav_fid != "" and fav_fid == fid
	if is_favorite:
		v.add_child(_make_favorite_row())

	# --- 1. Vignette : repli STATIQUE (voir _make_roster_thumbnail). ---
	v.add_child(_make_roster_thumbnail(fid, accent))

	# --- 2. Prénom NOM (identity.display_name -> hero_name -> faction_name), 2 lignes max. ---
	var name_lbl := Label.new()
	name_lbl.text = _roster_card_name(hero, fid).to_upper()
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.max_lines_visible = 2
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)

	# --- 3. Sous-titre : nom de la faction, plus petit et muet. ---
	var fac_lbl := Label.new()
	fac_lbl.text = _faction_display_name(fid, hero).to_upper()
	fac_lbl.add_theme_font_override("font", _font)
	fac_lbl.add_theme_font_size_override("font_size", 11)
	fac_lbl.add_theme_color_override("font_color", MUTED)
	fac_lbl.clip_text = true
	fac_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fac_lbl)

	# --- 4. Chip NIVEAU (or). ---
	var lvl_lbl := Label.new()
	lvl_lbl.text = tr("COMMON_LEVEL") + " " + str(int(hero.get("level", 1)))
	lvl_lbl.add_theme_font_override("font", _font)
	lvl_lbl.add_theme_font_size_override("font_size", 13)
	lvl_lbl.add_theme_color_override("font_color", GOLD)
	lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lvl_lbl)

	# --- 5. Badge d'ACCÈS (4 états access.type + repli owned==false sans bloc access). ---
	var badge := _make_access_badge(hero, owned)
	if badge != null:
		v.add_child(badge)

	# Bouton transparent superposé : capte le clic sur TOUTE la carte (pattern déjà présent dans ce
	# fichier / main_menu._make_mode_card : contenu en MOUSE_FILTER_IGNORE, bouton ajouté en DERNIER
	# → au-dessus, donc cliquable).
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Infobulle FAVORI (revue de code, point 6) : hébergée sur CE bouton, pas sur le contenu de la
	# carte. `v` et ses enfants sont en MOUSE_FILTER_IGNORE, mais IGNORE sur un PARENT ne bloque PAS
	# les infobulles de ses ENFANTS — ce n'est pas la raison de l'absence. La vraie contrainte est
	# l'ORDRE DE PIOCHE : ce bouton transparent est posé PLEIN CADRE et EN DERNIER (donc au-dessus de
	# tout le contenu) avec mouse_filter STOP (défaut) → c'est LUI que Godot retient pour l'infobulle
	# au survol de la carte, jamais un Label en dessous. Posée seulement sur la carte FAVORITE.
	if is_favorite:
		btn.tooltip_text = tr("CHAR_FAVORITE_TIP")
	var empty_sb := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ⚠️ PIÈGE Callable.bind() (critère d'acceptation explicite de ce chantier) : bind() ajoute ses
	# arguments APRÈS ceux du signal — sans risque avec `pressed` (qui n'émet rien) MAIS on l'évite
	# quand même par prudence. `index` ici est le PARAMÈTRE de _make_roster_card : chaque carte est
	# construite dans son propre appel (sa propre frame de pile), donc CETTE fermeture capture bien
	# SON `index` à elle, jamais celui d'une carte voisine construite avant/après dans la boucle de
	# _build_roster_grid. Vérifié en lecture : carte N -> _on_card_pressed(N) -> _show_sheet(N).
	btn.pressed.connect(func() -> void: _on_card_pressed(index))
	# SFX de survol/clic (helper partagé). La lueur de wire_button_feedback, elle, module btn.modulate
	# — invisible ici (bouton transparent SANS enfant, rien à éclaircir) : on pilote donc nous-mêmes
	# le stylebox du PANNEAU visible pour une lueur de survol RÉELLE (fond + liseré intensifiés).
	WarzoneUI.wire_button_sfx(btn)
	btn.mouse_entered.connect(func() -> void:
		if is_instance_valid(card):
			card.add_theme_stylebox_override("panel", _roster_card_style(accent, true)))
	btn.mouse_exited.connect(func() -> void:
		if is_instance_valid(card):
			card.add_theme_stylebox_override("panel", _roster_card_style(accent, false)))
	card.add_child(btn)

	WarzoneUI.add_corner_notches(card, 12.0, accent)
	return card

# Style de carte roster : fond gunmetal + liseré GAUCHE à la couleur d'accent de la FACTION (repère
# visuel immédiat par faction dans la grille — contrairement à l'ancienne liste, cyan partout).
# `hover` intensifie ce même accent (fond teinté + liseré plein) : lueur de survol réelle sans jamais
# écraser l'identité de faction par un cyan générique.
func _roster_card_style(accent: Color, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 12.0
	if hover:
		sb.bg_color = Color(accent, 0.20)
		sb.border_width_left = 4
		sb.border_color = accent
	else:
		sb.bg_color = SURFACE
		sb.border_width_left = 3
		sb.border_color = Color(accent, 0.55)
	return sb

# Vignette de carte : chaîne de repli IDENTIQUE à _apply_hero_stage (portrait 2D -> carte teintée)
# mais SANS le maillon 3D — 10 viewports hero_viewport_3d simultanés seraient un coût GPU prohibitif
# pour un simple aperçu de grille. Le 3D reste réservé au grand viewer de la fiche (_build_hero_stage).
func _make_roster_thumbnail(fid: String, accent: Color) -> Control:
	var thumb := Control.new()
	thumb.custom_minimum_size = Vector2(0, CARD_THUMB_HEIGHT)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var img_path := ""
	if _factions.has(fid):
		var f = _factions[fid]
		if f != null and f.get("hero_path") != null:
			img_path = str(f.get("hero_path"))

	var tex = null
	if img_path != "" and ResourceLoader.exists(img_path):
		tex = load(img_path)

	if tex != null:
		var portrait := TextureRect.new()
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.texture = tex
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.add_child(portrait)
	else:
		var block := ColorRect.new()
		block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		block.color = accent.darkened(0.25)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.add_child(block)
	return thumb

# Identité affichée sur la carte : identity.display_name (déjà PRÊT À AFFICHER — on ne concatène
# rien) ; repli hero_name (historique) puis faction_name/id (dernier repli, comme _faction_display_name).
func _roster_card_name(hero: Dictionary, fid: String) -> String:
	var identity: Dictionary = hero.get("identity", {}) if typeof(hero.get("identity")) == TYPE_DICTIONARY else {}
	var display_name := str(identity.get("display_name", ""))
	if display_name != "":
		return display_name
	var legacy := str(hero.get("hero_name", ""))
	if legacy != "":
		return legacy
	return _faction_display_name(fid, hero)

# Rangée FAVORI (haut de carte, alignée à droite) — cf. commentaire d'appel dans _make_roster_card.
func _make_favorite_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var lbl := Label.new()
	lbl.text = "CHAR_FAVORITE"  # clé brute -> auto-traduction (FR/EN/IT)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", GOLD)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return row

# Badge d'accès de carte : les 4 états `access.type` du contrat /heroes, + repli pour un serveur
# antérieur sans bloc `access` (cadenas seul si non possédé, rien sinon). `null` = pas de badge à
# poser (état normal free/owned — c'est la majorité du roster, pas une exception).
func _make_access_badge(hero: Dictionary, owned: bool) -> Control:
	var access: Dictionary = hero.get("access", {}) if typeof(hero.get("access")) == TYPE_DICTIONARY else {}
	if access.is_empty():
		if owned:
			return null
		return _roster_badge_label("✕", MUTED)

	var access_type := str(access.get("type", "owned" if owned else "locked"))
	match access_type:
		"free", "owned":
			return null
		"rotation":
			var left := int(access.get("free_games_left", 0))
			var game_max := int(access.get("free_games_max", 0))
			return _roster_badge_label(tr("CHAR_ACCESS_ROTATION") % [left, game_max], GOLD)
		"pass":
			return _roster_badge_label(tr("CHAR_ACCESS_PASS"), ACCENT)
		"locked":
			var price := int(access.get("price", 0))
			# Prix inconnu (0, serveur antérieur) → libellé seul, jamais « 0 Coins » trompeur.
			var txt := (tr("CHAR_LOCKED_PRICE") % price) if price > 0 else tr("CHAR_LOCKED")
			return _roster_badge_label(txt, MUTED)
		_:
			return null

func _roster_badge_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _on_card_pressed(index: int) -> void:
	_show_sheet(index)


# =========================================================
# FICHE — EMPLACEMENT HÉROS (3D → portrait 2D → carte colorée)
# =========================================================
# Réutilise le composant hero_viewport_3d (monté une fois). Bascule 3D-first / repli 2D / placeholder
# selon la faction affichée — logique reprise telle quelle de main_menu.gd:_apply_hero.
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
# FICHE — DÉTAIL TEXTUEL DU HÉROS (reconstruit à chaque ouverture)
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
