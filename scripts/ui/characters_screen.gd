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
@export var sheet_prev_button: Button      # « ❮ » — personnage PRÉCÉDENT (boucle), onglet CONSERVÉ
@export var sheet_next_button: Button      # « ❯ » — personnage SUIVANT (boucle), onglet CONSERVÉ
@export var hero_stage: Control            # FICHE : emplacement 3D/portrait (rempli en code)
@export var identity_box: VBoxContainer    # FICHE : en-tête d'identité (rebâti à chaque personnage)
@export var tabs_slot: VBoxContainer       # FICHE : hôte du TabContainer (4 onglets, bâti UNE fois)
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
# Hauteur portée de 260 à 286 px quand le nom du personnage est passé de 15 à 22 px (2 lignes
# possibles) : sans ça, la carte dépassait sa taille MINIMALE et la grille devenait irrégulière
# (les cartes à nom long poussaient leur rangée, pas les autres).
const CARD_SIZE := Vector2(200, 286)
const CARD_THUMB_HEIGHT := 112.0
# Transition ROSTER <-> FICHE : fondu alpha seul (cf. _fade_in plus bas pour le pourquoi).
const VIEW_FADE_TIME := 0.15

# --- FICHE à onglets (chantiers X/Y) : index des 4 onglets = ordre d'ajout au TabContainer. ---
const TAB_INFO := 0
const TAB_STATS := 1
const TAB_EVOLUTION := 2
const TAB_SKINS := 3
# Titres des onglets, dans l'ordre ci-dessus (re-traduits à chaud par _refresh_tab_titles).
const TAB_KEYS := ["CHAR_TAB_INFO", "CHAR_TAB_STATS", "CHAR_TAB_EVOLUTION", "CHAR_TAB_SKINS"]

# --- SKINS (chantier Y) : registre data-driven, MÊME dossier et MÊME duck-typing que le
# Split-Screen VS (split_screen_vs.gd:_find_skin) — un SkinData porte id / faction_id /
# portrait_path / model_path / accent_override. Aucun 2ᵉ mécanisme visuel à maintenir. ---
const SKINS_DIR := "res://resources/skins/"
# Colonnes du comparatif des Pass (§Y.4) : clés du bloc `evolution.coins_potential` servi par
# /heroes, dans l'ordre croissant de tier. « base » = sans Pass. Le libellé de chaque colonne est
# volontairement NON traduit (« PLUS », « PREMIUM », « INFINITY » = noms commerciaux invariants,
# même règle que les noms propres de personnages, §1.8).
# « SANS PASS » est en revanche une vraie phrase d'interface → clé i18n (CHAR_EVO_NO_PASS).
const PASS_COLUMNS := [
	{"key": "base", "label": "", "i18n": "CHAR_EVO_NO_PASS", "tier": ""},
	{"key": "plus", "label": "PLUS", "i18n": "", "tier": "plus"},
	{"key": "premium", "label": "PREMIUM", "i18n": "", "tier": "premium"},
	{"key": "infinity", "label": "INFINITY", "i18n": "", "tier": "infinity"},
]

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
var _stage_frame: Panel = null     # cadre du présentoir (fond + liseré à la couleur effective)

# Tween de transition ROSTER <-> FICHE (revue de code, point 4) : UNE seule référence, quel que
# soit le Control animé (roster_view ou sheet_view) — tuée avant toute nouvelle bascule pour ne
# jamais empiler deux fondus. Sans ça, une bascule roster<->fiche rapide (double clic, va-et-vient)
# laisse l'ANCIEN Tween forcer modulate:a à 1 en pleine rampe du NOUVEAU → flash/saut visible. Même
# pattern que hud.gd (_fade_tween) / phase_banner.gd (_tween).
var _view_tween: Tween

# --- FICHE à onglets (chantiers X/Y) ------------------------------------------------------------
var _tabs: TabContainer = null      # bâti UNE fois (_build_tabs), jamais reconstruit d'un héros à l'autre
var _tab_pages: Array = []          # VBoxContainer de contenu, index = TAB_* (vidé/repeuplé par héros)

# --- Données BOUTIQUE de l'onglet SKINS (fetch UNE fois à la 1ʳᵉ ouverture d'une fiche, partagées
# entre les 10 personnages : le catalogue et l'inventaire ne dépendent pas du héros affiché). ---
var _shop_items: Array = []         # /shop/catalog?include_all=1 → exclusifs Pass COMPRIS (purchasable=false)
var _owned_items: Dictionary = {}   # item_id -> quantité possédée (/shop/inventory)
var _equipped: Dictionary = {}      # faction_id -> skin_id RÉELLEMENT équipé (serveur)
var _pass_tier: String = ""         # tier du Pass actif ("" = aucun) → surligne SA colonne au comparatif
var _shop_requested: bool = false   # anti-refetch : une seule paire de requêtes pour tout l'écran
var _shop_failed: bool = false      # échec catalogue/inventaire → SKINS dégradé, le reste INTACT

# Skin PRÉVISUALISÉ dans le grand viewer (§Y.2) — JAMAIS équipé : c'est un état purement local,
# remis à "" au changement de personnage et à la fermeture de la fiche (le viewer retombe alors sur
# le skin réellement équipé). Ne jamais confondre avec _equipped.
var _preview_skin: String = ""


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

	# Flèches PRÉCÉDENT / SUIVANT de la fiche (chantier X.1) : naviguent d'un personnage à l'autre
	# SANS repasser par le roster, dans l'ordre de la grille, avec BOUCLE aux extrémités.
	if sheet_prev_button:
		WarzoneUI.apply_ghost_button(sheet_prev_button)
		WarzoneUI.wire_button_feedback(sheet_prev_button)
		sheet_prev_button.pressed.connect(func() -> void: _step_sheet(-1))
	if sheet_next_button:
		WarzoneUI.apply_ghost_button(sheet_next_button)
		WarzoneUI.wire_button_feedback(sheet_next_button)
		sheet_next_button.pressed.connect(func() -> void: _step_sheet(1))

	# Barre d'onglets de la fiche (chantier X.3) : bâtie UNE fois ici, pas à chaque ouverture — le
	# changement de personnage ne fait que VIDER/REPEUPLER la page active (cf. _populate_active_tab).
	_build_tabs()

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
	# Chemin d'ERREUR du roster (chantier Z.3) : sans lui, un /heroes en échec laissait l'écran bloqué
	# INDÉFINIMENT sur « SYNCHRONISATION… » (aucun message, aucune sortie). `lobby_error` est le signal
	# d'échec générique qu'émet NetworkManager pour cette route.
	NetworkManager.lobby_error.connect(_on_roster_error)
	NetworkManager.fetch_heroes()

	# Boutique (onglet SKINS) : catalogue + inventaire. Signaux connectés DÈS le _ready (et non à la
	# 1ʳᵉ ouverture de fiche) pour ne jamais rater une réponse ; les requêtes, elles, ne partent qu'à
	# la 1ʳᵉ ouverture d'une fiche (_ensure_shop_data) — le roster seul n'en a pas besoin.
	NetworkManager.shop_catalog_loaded.connect(_on_shop_catalog_loaded)
	NetworkManager.shop_inventory_loaded.connect(_on_shop_inventory_loaded)
	NetworkManager.skin_equipped.connect(_on_skin_equipped)
	NetworkManager.skin_equip_failed.connect(_on_skin_equip_failed)


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
	# Changement de personnage = l'aperçu de skin de l'ANCIEN n'a plus aucun sens (§Y.2) : on
	# retombe sur le skin RÉELLEMENT équipé du nouveau. Fait AVANT _apply_hero_stage, qui lit
	# _preview_skin pour décider quel visuel monter.
	_preview_skin = ""
	# Données boutique de l'onglet SKINS : demandées à la 1ʳᵉ ouverture d'une fiche seulement.
	_ensure_shop_data()
	_apply_hero_stage(str(hero.get("faction_id", "")))
	_build_identity_header(hero)
	# L'onglet ACTIF est CONSERVÉ d'un personnage à l'autre (critère d'acceptation X) : on ne
	# réinitialise jamais _tabs.current_tab ici — seul son CONTENU est repeuplé.
	_populate_active_tab()

# Personnage précédent (-1) / suivant (+1) dans l'ordre de la grille, avec BOUCLE aux extrémités
# (§X.1). L'onglet actif ne bouge pas : _show_sheet repeuple la page courante sans la fermer.
func _step_sheet(delta: int) -> void:
	if _heroes.is_empty() or _sheet_index < 0:
		return
	# posmod() plutôt qu'un modulo brut : en GDScript, (-1) % 10 vaut -1, ce qui sortirait du roster
	# au premier « précédent » depuis la carte 0. posmod ramène toujours dans [0, size).
	_show_sheet(posmod(_sheet_index + delta, _heroes.size()))

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
	# Hiérarchie VOULUE (demande de Hakim) : c'est le NOM DU PERSONNAGE qui porte la carte, pas sa
	# faction — d'où une taille franchement dominante (22 px contre 11 px pour le sous-titre, ratio
	# 2:1) et le blanc froid réservé au texte primaire. Le nom est ce qu'on lit à un mètre de l'écran.
	var name_lbl := Label.new()
	name_lbl.text = _roster_card_name(hero, fid).to_upper()
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.max_lines_visible = 2
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)

	# --- 3. Sous-titre : nom de la faction — PETIT et à la COULEUR D'ACCENT DE SA FACTION.
	# L'accent (et non le gris muet) fait de cette ligne le repère d'appartenance immédiat : la même
	# couleur que le liseré gauche et que les encoches de la carte, donc trois rappels cohérents du
	# même signal. C'est aussi ce qui permet de garder la ligne à 11 px sans la rendre illisible. ---
	var fac_lbl := Label.new()
	fac_lbl.text = _faction_display_name(fid, hero).to_upper()
	fac_lbl.add_theme_font_override("font", _font)
	fac_lbl.add_theme_font_size_override("font_size", 11)
	fac_lbl.add_theme_color_override("font_color", accent)
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
	# PRÉSENTOIR (chantier X.1) : cadre de fond posé SOUS tous les visuels — surface gunmetal +
	# liseré à la couleur de la faction (ou du skin prévisualisé). Il donne au personnage un vrai
	# volume à l'écran : sans lui, le héros « flotte » dans le panneau et la moitié gauche de la
	# fiche paraît vide. Sa couleur est réglée par _style_stage_frame à chaque changement.
	_stage_frame = Panel.new()
	_stage_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_stage.add_child(_stage_frame)
	_style_stage_frame(ACCENT)
	# Encoches biseautées sur le présentoir lui-même (ADN angulaire §2), à la taille du grand cadre.
	WarzoneUI.add_corner_notches(hero_stage, 16.0, ACCENT)

	# Carte colorée (toujours présente, dessous les visuels mais AU-DESSUS du cadre).
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
	# Avec la fiche en deux colonnes (§X.1), cet emplacement fait désormais ~517×660 px au lieu de la
	# bande de 300 px de haut d'avant : le modèle est vu en pied, en grand, sans réglage à faire ici.
	_hero3d = HeroViewport3DScene.instantiate()
	hero_stage.add_child(_hero3d)
	_hero3d.visible = false

# Habillage du présentoir : fond gunmetal profond + liseré fin à la couleur donnée. Recalculé à
# chaque personnage / aperçu de skin (un StyleBox est partagé s'il n'est pas dupliqué → on en
# refabrique un, c'est le pattern des autres écrans).
func _style_stage_frame(accent: Color) -> void:
	if _stage_frame == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(0.058824, 0.07451, 0.094118, 0.85)
	sb.set_border_width_all(2)
	sb.border_color = Color(accent, 0.55)
	_stage_frame.add_theme_stylebox_override("panel", sb)

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

	# --- SKIN (chantier Y) : surcharge data-driven des visuels, MÊME mécanisme que le Split-Screen
	# VS (split_screen_vs._load_faction). Le skin retenu est l'APERÇU en cours s'il y en a un
	# (le joueur est en train d'essayer), sinon celui réellement équipé sur ce personnage. Un chemin
	# de skin qui n'existe pas ne remplace RIEN : on garde le visuel de faction plutôt que du vide. ---
	var skin_id := _preview_skin if _preview_skin != "" else str(_equipped.get(fid, ""))
	if skin_id != "":
		var skin = _find_skin_res(skin_id, fid)
		if skin != null:
			var s_portrait := str(skin.get("portrait_path") if skin.get("portrait_path") != null else "")
			var s_model := str(skin.get("model_path") if skin.get("model_path") != null else "")
			if s_portrait != "" and ResourceLoader.exists(s_portrait):
				img_path = s_portrait
			if s_model != "" and ResourceLoader.exists(s_model):
				model_path = s_model
			var s_accent = skin.get("accent_override")
			if s_accent is Color:
				accent = s_accent
		else:
			# Aucun SkinData pour cet id (skin catalogué mais pas encore produit, M5) : repli HONNÊTE
			# — variation de teinte déterministe, jamais une image inventée (§2.6).
			accent = _skin_swatch_color(fid, skin_id)

	# Cadre du présentoir : liseré à la couleur effective (faction ou skin prévisualisé) — le
	# personnage est ainsi ENCADRÉ comme une pièce de collection, pas posé sur du vide.
	_style_stage_frame(accent)

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
# FICHE — EN-TÊTE D'IDENTITÉ (§X.2, rebâti à chaque personnage)
# =========================================================
# Visible QUEL QUE SOIT l'onglet (il est hors du TabContainer) : c'est la carte d'identité du
# dossier. Trois lignes, dans l'ordre de lecture voulu par Hakim :
#   1. PRÉNOM NOM en grand + indicatif entre guillemets + code CHAR-NNN aligné à droite ;
#   2. nom de FACTION à la couleur d'accent de la faction (petit) + catégorie/rôle en muet ;
#   3. chip d'état d'accès + CTA contextuel, et le bouton ★ FAVORI.
func _build_identity_header(hero: Dictionary) -> void:
	if identity_box == null:
		return
	_clear(identity_box)
	var fid := str(hero.get("faction_id", ""))
	var fac_color := _faction_color(fid)
	var identity: Dictionary = hero.get("identity", {}) if typeof(hero.get("identity")) == TYPE_DICTIONARY else {}

	# --- Ligne 1 : PRÉNOM NOM (grand) + « indicatif » + code CHAR-NNN ---------------------------
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 10)
	identity_box.add_child(line1)

	var name_lbl := Label.new()
	# Nom du PERSONNAGE (identity.display_name, déjà prêt à afficher côté serveur) et non plus le nom
	# de faction : c'est la correction de fond de la refonte — la fiche et la carte du roster
	# désignent enfin la même entité par le même nom.
	name_lbl.text = _roster_card_name(hero, fid).to_upper()
	name_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED  # nom propre, pas une clé
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 34)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line1.add_child(name_lbl)

	# Indicatif (« Enclume ») — muet, entre guillemets, à côté du nom.
	var callsign := str(identity.get("callsign", ""))
	if callsign == "":
		callsign = str(hero.get("hero_callsign", ""))
	if callsign != "":
		var cs := Label.new()
		cs.text = "« " + callsign + " »"
		cs.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		cs.add_theme_font_override("font", _font)
		cs.add_theme_font_size_override("font_size", 16)
		cs.add_theme_color_override("font_color", MUTED)
		cs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line1.add_child(cs)

	# Le code dossier `CHAR-NNN` n'est PLUS affiché (demande produit) : c'est une référence de
	# production (registre `factions.py`, `TEMPLATE_PERSONNAGES.md`), pas une information de jeu —
	# elle encombrait la ligne de titre sans rien apprendre au joueur. Le champ reste servi par
	# `identity.char_code` dans /heroes : rien à changer côté serveur, et il redevient affichable
	# ici en une ligne si besoin.

	# --- Ligne 2 : FACTION (couleur d'accent, petit) + catégorie/rôle (muet) --------------------
	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 8)
	identity_box.add_child(line2)

	var fac_lbl := Label.new()
	fac_lbl.text = _faction_display_name(fid, hero).to_upper()
	fac_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	fac_lbl.add_theme_font_override("font", _font)
	fac_lbl.add_theme_font_size_override("font_size", 14)
	fac_lbl.add_theme_color_override("font_color", fac_color)
	line2.add_child(fac_lbl)

	# Catégorie de faction (combat / cartes / zone / mouvement / renforts / pré-game) — exposée par
	# le bloc `faction_category` de /heroes (chantier V). Traduite par une clé dérivée ; si la clé
	# manque, tr() rend la clé elle-même → on préfère alors masquer la ligne que montrer du charabia.
	var category := str(hero.get("faction_category", ""))
	if category != "":
		var cat_key := "FACTION_CATEGORY_" + category.to_upper()
		var cat_text := tr(cat_key)
		if cat_text != cat_key:
			var sep := Label.new()
			sep.text = "·"
			sep.add_theme_font_override("font", _font)
			sep.add_theme_font_size_override("font_size", 14)
			sep.add_theme_color_override("font_color", MUTED)
			line2.add_child(sep)
			var cat := Label.new()
			cat.text = cat_text.to_upper()
			cat.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
			cat.add_theme_font_override("font", _font)
			cat.add_theme_font_size_override("font_size", 14)
			cat.add_theme_color_override("font_color", MUTED)
			line2.add_child(cat)

	# --- Ligne 3 : chip d'ACCÈS + CTA boutique + ★ FAVORI ---------------------------------------
	var line3 := HBoxContainer.new()
	line3.add_theme_constant_override("separation", 10)
	identity_box.add_child(line3)

	var chip := _access_chip(hero)
	if chip != null:
		line3.add_child(chip)

	# CTA « VOIR EN BOUTIQUE ❯ » : uniquement pour un personnage VERROUILLÉ (l'achat reste dans la
	# Boutique, §2.7 — on n'entretient pas un 2ᵉ tunnel d'achat ici).
	if _access_type(hero) == "locked":
		var shop_btn := Button.new()
		shop_btn.text = tr("CHAR_SHOP_CTA")
		shop_btn.custom_minimum_size = Vector2(0, 34)
		shop_btn.focus_mode = Control.FOCUS_NONE
		shop_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		shop_btn.add_theme_font_override("font", _font)
		shop_btn.add_theme_font_size_override("font_size", 13)
		WarzoneUI.apply_ghost_button(shop_btn)
		WarzoneUI.wire_button_feedback(shop_btn)
		shop_btn.pressed.connect(_goto_shop)
		line3.add_child(shop_btn)

	var spacer3 := Control.new()
	spacer3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line3.add_child(spacer3)
	line3.add_child(_make_favorite_button(fid))

	WarzoneUI.add_filet(identity_box)


# Bouton ★ FAVORI (§X.2) : REMPLACE l'ancienne persistance « au clic sur la carte » (§2.3). Étoile
# pleine = personnage actuellement affiché au menu principal. Le clic persiste LOCALEMENT
# (SettingsManager) puis reconstruit la grille pour que le badge ★ suive immédiatement.
func _make_favorite_button(fid: String) -> Button:
	var is_fav := SettingsManager.get_selected_faction() == fid and fid != ""
	var btn := Button.new()
	btn.text = ("★ " if is_fav else "☆ ") + tr("CHAR_FAVORITE").replace("★ ", "")
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.tooltip_text = tr("CHAR_FAVORITE_TIP")
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", GOLD if is_fav else MUTED)
	WarzoneUI.apply_ghost_button(btn)
	WarzoneUI.wire_button_feedback(btn)
	btn.pressed.connect(func() -> void: _on_favorite_pressed(fid))
	return btn

func _on_favorite_pressed(fid: String) -> void:
	if fid == "":
		return
	# Re-clic sur le favori courant = on le RETIRE ("" = aucun choix explicite, cf. SettingsManager) :
	# sans ça le joueur ne pourrait jamais annuler son choix depuis cet écran.
	var already := SettingsManager.get_selected_faction() == fid
	SettingsManager.set_selected_faction("" if already else fid)
	# La grille porte le badge ★ : elle doit refléter le nouveau favori dès le retour au roster.
	_build_roster_grid()
	# Et l'en-tête doit montrer l'étoile pleine/vide immédiatement, sans changer d'onglet.
	if _sheet_index >= 0 and _sheet_index < _heroes.size():
		var hero = _heroes[_sheet_index]
		if typeof(hero) == TYPE_DICTIONARY:
			_build_identity_header(hero)

# Type d'accès NORMALISÉ ("free" | "owned" | "rotation" | "pass" | "locked"), avec le MÊME repli que
# _make_access_badge pour un serveur antérieur sans bloc `access` (source unique : _is_permanent).
func _access_type(hero: Dictionary) -> String:
	var access: Dictionary = hero.get("access", {}) if typeof(hero.get("access")) == TYPE_DICTIONARY else {}
	if access.is_empty():
		return "owned" if _is_permanent(hero) else "locked"
	return str(access.get("type", "owned"))

# Chip d'état d'accès de la FICHE : mêmes 4 états et MÊMES couleurs que le badge de carte du roster
# (_make_access_badge), mais en version longue — ici on a la place d'écrire une phrase complète.
func _access_chip(hero: Dictionary) -> Control:
	var access: Dictionary = hero.get("access", {}) if typeof(hero.get("access")) == TYPE_DICTIONARY else {}
	var t := _access_type(hero)
	var text := ""
	var color := MUTED
	match t:
		"free", "owned":
			text = tr("CHAR_ACCESS_OWNED")
			color = GOLD
		"rotation":
			text = tr("CHAR_ACCESS_ROTATION") % [int(access.get("free_games_left", 0)),
					int(access.get("free_games_max", 0))]
			color = GOLD
		"pass":
			text = tr("CHAR_ACCESS_PASS")
			color = ACCENT
		"locked":
			var price := int(access.get("price", 0))
			# Prix inconnu (0, serveur antérieur) → libellé court, jamais « 0 Coins » trompeur.
			text = (tr("CHAR_ACCESS_LOCKED") % price) if price > 0 else tr("CHAR_LOCKED")
			color = MUTED
		_:
			return null
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _make_card_style(color))
	var lbl := Label.new()
	lbl.text = text
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED  # déjà traduit + formaté
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	chip.add_child(lbl)
	return chip

func _goto_shop() -> void:
	AudioManager.play_sfx("click")
	TransitionManager.change_scene("res://scenes/ui/shop.tscn")


# =========================================================
# FICHE — BARRE D'ONGLETS (§X.3) : bâtie UNE fois, contenu repeuplé par personnage
# =========================================================
# Pattern IDENTIQUE au Profil (profile.gd:_build_tabs/_add_tab_page/_style_tabs) et au Rapport
# post-op : TabContainer + une page ScrollContainer>VBox par onglet. Différence assumée avec le
# Profil : ici AUCUN chargement différé par onglet (tout le contenu des 4 onglets vient de données
# DÉJÀ en mémoire — le roster /heroes et, pour SKINS, le couple catalogue/inventaire chargé une
# fois pour tout l'écran). Un onglet ne déclenche donc jamais de requête à son ouverture.
func _build_tabs() -> void:
	if tabs_slot == null:
		return
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tabs(_tabs)
	tabs_slot.add_child(_tabs)

	_tab_pages = [
		_add_tab_page("TabInfo"),
		_add_tab_page("TabStats"),
		_add_tab_page("TabEvolution"),
		_add_tab_page("TabSkins"),
	]
	_refresh_tab_titles()
	_tabs.tab_changed.connect(_on_tab_changed)

func _add_tab_page(id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = id  # nom ASCII : le TITRE visible est posé à part (set_tab_title), donc traduisible
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	return page

func _refresh_tab_titles() -> void:
	if _tabs == null:
		return
	for i in range(mini(TAB_KEYS.size(), _tabs.get_tab_count())):
		_tabs.set_tab_title(i, tr(TAB_KEYS[i]))

func _on_tab_changed(_idx: int) -> void:
	AudioManager.play_sfx("click")
	_populate_active_tab()

# Repeuple la SEULE page active, à partir du héros actuellement ouvert. Appelée au changement
# d'onglet ET au changement de personnage (flèches ❮❯) — d'où la conservation de l'onglet actif.
func _populate_active_tab() -> void:
	if _tabs == null or _sheet_index < 0 or _sheet_index >= _heroes.size():
		return
	var hero = _heroes[_sheet_index]
	if typeof(hero) != TYPE_DICTIONARY:
		return
	var idx := _tabs.current_tab
	if idx < 0 or idx >= _tab_pages.size():
		return
	var page: VBoxContainer = _tab_pages[idx]
	if page == null:
		return
	_clear(page)
	match idx:
		TAB_INFO: _populate_tab_info(page, hero)
		TAB_STATS: _populate_tab_stats(page, hero)
		TAB_EVOLUTION: _populate_tab_evolution(page, hero)
		TAB_SKINS: _populate_tab_skins(page, hero)

# Habillage du TabContainer — repris VERBATIM du Profil (profile.gd:_style_tabs) pour que les deux
# écrans à onglets soient indiscernables : filet cyan en haut de l'onglet actif, angles vifs.
func _style_tabs(tc: TabContainer) -> void:
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.058824, 0.07451, 0.094118, 0.55)
	panel_sb.border_color = Color(ACCENT, 0.35)
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(0)
	panel_sb.set_content_margin_all(14)
	tc.add_theme_stylebox_override("panel", panel_sb)

	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(ACCENT, 0.16)
	sel.set_corner_radius_all(0)
	sel.border_width_top = 2
	sel.border_color = ACCENT
	sel.content_margin_left = 18
	sel.content_margin_right = 18
	sel.content_margin_top = 8
	sel.content_margin_bottom = 8

	var unsel := StyleBoxFlat.new()
	unsel.bg_color = Color(SURFACE, 0.5)
	unsel.set_corner_radius_all(0)
	unsel.content_margin_left = 18
	unsel.content_margin_right = 18
	unsel.content_margin_top = 8
	unsel.content_margin_bottom = 8

	var hover := unsel.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.08)
	tc.add_theme_stylebox_override("tab_selected", sel)
	tc.add_theme_stylebox_override("tab_unselected", unsel)
	tc.add_theme_stylebox_override("tab_hovered", hover)
	tc.add_theme_color_override("font_selected_color", ACCENT)
	tc.add_theme_color_override("font_unselected_color", MUTED)
	tc.add_theme_color_override("font_hovered_color", TEXT)


# =========================================================
# ONGLET 1 — INFORMATIONS (§X) : progression, palmarès, pouvoir, état
# =========================================================
func _populate_tab_info(page: VBoxContainer, hero: Dictionary) -> void:
	var fid := str(hero.get("faction_id", ""))

	# --- PROGRESSION : chip niveau + barre d'XP (bloc EXISTANT, réutilisé tel quel) -------------
	# ⚠️ Ne PAS ajouter _section_header("CHAR_XP_HEADER") ici : _make_xp_block pose DÉJÀ son propre
	# en-tête de section (vérifié en capture — le titre « PROGRESSION » sortait en double).
	page.add_child(_make_xp_block(hero))

	# --- PALMARÈS (bloc `record` de /heroes, chantier V.3) --------------------------------------
	page.add_child(_section_header("CHAR_SECTION_RECORD"))
	var record: Dictionary = hero.get("record", {}) if typeof(hero.get("record")) == TYPE_DICTIONARY else {}
	var games := int(record.get("games", 0))
	if games <= 0:
		# Jamais joué : on le DIT, on n'affiche pas quatre zéros qui ressembleraient à un bug.
		page.add_child(_body_label(tr("CHAR_RECORD_EMPTY")))
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.add_child(_readout_card(tr("CHAR_RECORD_GAMES"), _format_thousands(games), TEXT))
		grid.add_child(_readout_card(tr("CHAR_RECORD_WINS"), _format_thousands(int(record.get("wins", 0))), GOLD))
		grid.add_child(_readout_card(tr("CHAR_RECORD_LOSSES"), _format_thousands(int(record.get("losses", 0))), DANGER))
		grid.add_child(_readout_card(tr("CHAR_RECORD_WINRATE"), str(int(record.get("winrate", 0))) + "%", ACCENT))
		page.add_child(grid)
		page.add_child(_make_ratio_bar(int(record.get("winrate", 0)), ACCENT))

	# --- POUVOIR DE FACTION (encadré teinté accent, §X.1.3) -------------------------------------
	# L'onglet INFORMATIONS est le SEUL à recevoir l'explication en clair (3ᵉ argument) : c'est
	# l'onglet de découverte. STATISTIQUES, déjà dense, garde l'encadré court.
	page.add_child(_section_header("CHAR_POWER_HEADER"))
	page.add_child(_make_power_panel(_hero_power_text(fid, hero), _faction_color(fid),
			_hero_power_hint(fid)))

	# --- ÉTAT : rappel textuel COMPLET de l'accès (version détaillée de la chip d'en-tête) ------
	page.add_child(_section_header("CHAR_SECTION_STATE"))
	for line in _access_detail_lines(hero):
		page.add_child(_body_label(line))


# =========================================================
# ONGLET 2 — STATISTIQUES (§X) : PV/PA/PB/PP/Régén, actuel ET niveau 50, avec DELTA
# =========================================================
func _populate_tab_stats(page: VBoxContainer, hero: Dictionary) -> void:
	# `true` = colonne DELTA (« RESTANT ») activée. Le draft (faction_selection) n'appelle JAMAIS
	# cette fonction — il passe par HeroStatsView.build_compact_row, intouché : son aspect ne peut
	# donc pas bouger (critère d'acceptation X « draft VISUELLEMENT INCHANGÉ »).
	var fid := str(hero.get("faction_id", ""))
	page.add_child(_make_stats_block(hero, true))
	# Le POUVOIR DE HÉROS reste visible ici aussi (il fait partie des 6 informations demandées) —
	# en version COURTE : l'explication en clair est réservée à l'onglet INFORMATIONS.
	page.add_child(_section_header("CHAR_POWER_HEADER"))
	page.add_child(_make_power_panel(_hero_power_text(fid, hero), _faction_color(fid)))

	# --- POUVOIR DE FACTION : la mécanique de PLATEAU (dés, cartes, renforts, mouvement) ---------
	# C'est un pouvoir de nature DIFFÉRENTE de celui du héros : le premier décrit le profil de
	# combat du champion, celui-ci modifie les RÈGLES de la partie (relance de dé, double en
	# défense, unité bonus…). Les deux en-têtes le disent explicitement pour qu'on ne les confonde
	# pas. Sa place est ici plutôt qu'en INFORMATIONS : c'est une donnée de comparaison, on la lit
	# en même temps que les caractéristiques chiffrées.
	var faction_power := _faction_power_text(fid)
	if faction_power != "":
		page.add_child(_section_header("CHAR_FACTION_POWER_HEADER"))
		page.add_child(_make_power_panel(faction_power, _faction_color(fid)))

# Pouvoir de FACTION, lu sur le `.tres` local (`power_key`) — MÊME source et MÊME repli que le draft
# (`faction_selection._dossier_text`) et que la partie (`main.gd`) : aucun 3ᵉ chemin à maintenir, et
# le texte affiché ici est mot pour mot celui que le joueur verra au draft. `/heroes` ne sert PAS ce
# champ (il ne porte que le pouvoir du HÉROS) — d'où la lecture locale.
# Clé vide, `.tres` legacy ou clé absente du CSV → chaîne vide → la section entière est omise.
func _faction_power_text(fid: String) -> String:
	if fid == "" or not _factions.has(fid):
		return ""
	var f = _factions[fid]
	if f == null or f.get("power_key") == null:
		return ""
	var key := str(f.get("power_key"))
	if key == "":
		return ""
	var txt := tr(key)
	return "" if txt == key else txt

# =========================================================
# ONGLET 3 — ÉVOLUTION (§Y) : paliers, XP acquise, Coins gagnés, comparatif des Pass
# =========================================================
func _populate_tab_evolution(page: VBoxContainer, hero: Dictionary) -> void:
	# C'est ICI que la perte de progression sous accès temporaire doit être la plus visible (§Y.5) :
	# l'onglet entier parle d'investissement à long terme sur un personnage qu'on peut perdre.
	if _access_type(hero) in ["rotation", "pass"]:
		var warn := _body_label(tr("CHAR_TEMP_WARNING"))
		warn.add_theme_color_override("font_color", GOLD)
		page.add_child(warn)

	# --- 1. Frise des PALIERS (« tranches d'augmentation ») ------------------------------------
	page.add_child(_section_header("CHAR_MILESTONES_HEADER"))
	var milestones = hero.get("milestones", [])
	var level := int(hero.get("level", 1))
	if typeof(milestones) == TYPE_ARRAY and not milestones.is_empty():
		var next_shown := false  # le chip « PROCHAIN » ne se pose que sur le PREMIER palier non atteint
		for m in milestones:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var unlocked := bool(m.get("unlocked", false))
			var is_next := (not unlocked) and (not next_shown)
			if is_next:
				next_shown = true
			page.add_child(_make_milestone_step(m, unlocked, is_next, level))

	# --- 2. Points acquis : XP totale + rappel « NIVEAU N / 50 » --------------------------------
	page.add_child(_section_header("CHAR_SECTION_PROGRESSION"))
	var xp_row := GridContainer.new()
	xp_row.columns = 2
	xp_row.add_theme_constant_override("h_separation", 12)
	xp_row.add_theme_constant_override("v_separation", 12)
	xp_row.add_child(_readout_card(tr("CHAR_EVO_XP_TOTAL"),
			_format_thousands(int(hero.get("xp_total", 0))), ACCENT))
	xp_row.add_child(_readout_card(tr("COMMON_LEVEL"), str(level) + " / 50", GOLD))
	page.add_child(xp_row)

	# --- 3. Coins gagnés PAR ce personnage (ledger réel, V.4) ----------------------------------
	# Clé ABSENTE = ledger non déployé → carte MASQUÉE. On n'affiche jamais « 0 » à la place d'une
	# donnée qu'on n'a pas : ce serait un mensonge, pas un repli (§Y.3).
	var evolution: Dictionary = hero.get("evolution", {}) if typeof(hero.get("evolution")) == TYPE_DICTIONARY else {}
	if evolution.has("coins_earned"):
		# La clé porte DÉJÀ son nombre (« … : %d ») : on la rend telle quelle dans une carte bordée
		# d'or, sans répéter la valeur en dessous (ce serait la même donnée écrite deux fois).
		var coins_card := PanelContainer.new()
		coins_card.add_theme_stylebox_override("panel", _make_card_style(GOLD))
		var coins_lbl := Label.new()
		coins_lbl.text = tr("CHAR_EVO_COINS_EARNED") % int(evolution.get("coins_earned", 0))
		coins_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		coins_lbl.add_theme_font_override("font", _font)
		coins_lbl.add_theme_font_size_override("font_size", 15)
		coins_lbl.add_theme_color_override("font_color", GOLD)
		coins_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		coins_card.add_child(coins_lbl)
		page.add_child(coins_card)

	# --- 4. Comparatif des Pass (§Y.4) ---------------------------------------------------------
	_build_pass_table(page, evolution)

# Une étape de la frise : pastille hexagonale « NIV. N » (or si franchie, contour muet sinon),
# le détail du bonus en clair, et le chip « PROCHAIN — dans N niveaux » sur la prochaine étape.
func _make_milestone_step(m: Dictionary, unlocked: bool, is_next: bool, level: int) -> Control:
	var lvl := int(m.get("level", 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	# Pastille hexagonale : le remplissage or ne signale QUE le palier réellement franchi.
	var fill := GOLD if unlocked else Color(MUTED, 0.25)
	var fg := WarzoneUI.GUNMETAL if unlocked else MUTED
	row.add_child(WarzoneUI.make_hex_badge(str(lvl), _font, 15, fill, fg, 46))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)

	var title := Label.new()
	title.text = tr("CHAR_MILESTONE_LEVEL") % lvl
	title.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", TEXT if unlocked else MUTED)
	col.add_child(title)

	# Détail du bonus (« +32 PV · +3 PA · +1 % PB ») — MÊME formatage que partout ailleurs.
	var bonus := Label.new()
	bonus.text = _format_bonus(m.get("bonus", {}))
	bonus.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	bonus.add_theme_font_override("font", _font)
	bonus.add_theme_font_size_override("font_size", 13)
	bonus.add_theme_color_override("font_color", GOLD if unlocked else MUTED)
	col.add_child(bonus)

	# Chip « PROCHAIN — dans N niveaux » : placé DANS la colonne (3ᵉ ligne) et non en frère de droite.
	# En frère, il était poussé contre le bord par la colonne en EXPAND_FILL et se faisait rogner dès
	# que la traduction s'allongeait (constaté en capture sur l'italien « PROSSIMO — tra 8 livelli »).
	if is_next:
		var next_lbl := Label.new()
		next_lbl.text = tr("CHAR_EVO_NEXT") + " — " + (tr("CHAR_EVO_IN_LEVELS") % maxi(0, lvl - level))
		next_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		next_lbl.add_theme_font_override("font", _font)
		next_lbl.add_theme_font_size_override("font_size", 12)
		next_lbl.add_theme_color_override("font_color", ACCENT)
		next_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(next_lbl)
	return row

# Comparatif chiffré des Pass (§Y.4). Deux lignes : « Coins par niveau » et « Potentiel restant ».
# REPLI : si le serveur n'a servi que la colonne `base` (pass_catalog absent), on n'affiche PAS un
# tableau à une seule colonne — on se contente du potentiel « sans Pass », sans comparatif trompeur.
func _build_pass_table(page: VBoxContainer, evolution: Dictionary) -> void:
	var potential: Dictionary = evolution.get("coins_potential", {}) if typeof(evolution.get("coins_potential")) == TYPE_DICTIONARY else {}
	if potential.is_empty():
		return
	var levels_left := int(evolution.get("levels_left", 0))

	# Colonnes RÉELLEMENT servies par le serveur, dans l'ordre du registre.
	var cols: Array = []
	for c in PASS_COLUMNS:
		if potential.has(str(c["key"])):
			cols.append(c)
	if cols.size() <= 1:
		return  # une seule colonne → pas de comparatif possible, bloc masqué (repli honnête)

	page.add_child(_section_header("CHAR_EVO_PASS_TABLE"))
	var grid := GridContainer.new()
	grid.columns = cols.size() + 1
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)

	# En-tête : cellule vide puis un titre par colonne, celle du Pass ACTIF surlignée en or.
	grid.add_child(_table_cell("", MUTED, 12))
	for c in cols:
		var label := tr(str(c["i18n"])) if str(c["i18n"]) != "" else str(c["label"])
		var active := str(c["tier"]) != "" and str(c["tier"]) == _pass_tier
		grid.add_child(_table_cell(label, GOLD if active else ACCENT, 12))

	# Ligne 1 : Coins PAR NIVEAU. Dérivée du potentiel (potentiel = niveaux restants × barème), donc
	# aucune constante 1-5/2-10/… recopiée côté client. Indisponible au niveau MAX (division par 0) :
	# la ligne est alors omise plutôt que remplie de zéros.
	if levels_left > 0:
		grid.add_child(_table_cell(tr("CHAR_EVO_PER_LEVEL"), MUTED, 13))
		for c in cols:
			var rng = potential.get(str(c["key"]), [])
			var txt := "—"
			if typeof(rng) == TYPE_ARRAY and rng.size() >= 2:
				txt = "%d-%d" % [int(rng[0]) / levels_left, int(rng[1]) / levels_left]
			var is_active := str(c["tier"]) != "" and str(c["tier"]) == _pass_tier
			grid.add_child(_table_cell(txt, GOLD if is_active else TEXT, 14))

	# Ligne 2 : potentiel RESTANT (fourchettes exactes du serveur, telles quelles).
	grid.add_child(_table_cell(tr("CHAR_EVO_REMAINING") % levels_left, MUTED, 13))
	for c in cols:
		var rng2 = potential.get(str(c["key"]), [])
		var txt2 := "—"
		if typeof(rng2) == TYPE_ARRAY and rng2.size() >= 2:
			txt2 = "%s-%s" % [_format_thousands(int(rng2[0])), _format_thousands(int(rng2[1]))]
		var is_active2 := str(c["tier"]) != "" and str(c["tier"]) == _pass_tier
		grid.add_child(_table_cell(txt2, GOLD if is_active2 else TEXT, 14))

	page.add_child(grid)
	var note := _body_label(tr("CHAR_EVO_PASS_NOTE"))
	note.add_theme_font_size_override("font_size", 12)
	page.add_child(note)

func _table_cell(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED  # déjà traduit / déjà formaté
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# =========================================================
# ONGLET 4 — SKINS (§Y) : liste, exclusifs Pass, états, PRÉVISUALISATION au clic
# =========================================================
func _populate_tab_skins(page: VBoxContainer, hero: Dictionary) -> void:
	var fid := str(hero.get("faction_id", ""))
	var permanent := _is_permanent(hero)

	# Personnage non possédé DÉFINITIVEMENT : l'onglet reste consultable (vitrine), mais aucun
	# bouton ÉQUIPER — la règle est rappelée en clair plutôt que subie (§Y.4).
	if not permanent:
		page.add_child(_body_label(tr("CHAR_SKINS_REQUIRES_OWNED")))

	# Échec des fetchs boutique : SEUL cet onglet est dégradé, le reste de la fiche est intact (Z.3).
	if _shop_failed:
		page.add_child(_body_label(tr("CHAR_SKIN_SOON")))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	page.add_child(grid)

	# Vignette 1 : APPARENCE DE BASE — toujours possédée, skin_id vide (convention serveur).
	grid.add_child(_make_skin_tile(fid, "", tr("CHAR_SKIN_BASE"), 0, true, true, permanent))

	var skins := _skins_for(fid)
	for item in skins:
		var id := str(item.get("id", ""))
		var owned := _owned_items.has(id)
		# `purchasable == false` = skin EXCLUSIF (récompense de Pass) : jamais achetable en Coins.
		var purchasable := bool(item.get("purchasable", true))
		grid.add_child(_make_skin_tile(fid, id, tr(str(item.get("name_key", id))),
				int(item.get("price", 0)), owned, purchasable, permanent))

	# Catalogue muet pour ce personnage (aucun skin encore produit) : vignette fantôme « À VENIR »
	# — état d'attente honnête et propre, jamais une grille vide sans explication.
	if skins.is_empty() and not _shop_failed:
		grid.add_child(_make_ghost_tile(tr("CHAR_SKIN_SOON")))

# Une vignette de skin : aplat teinté (aperçu placeholder), nom, chip d'état, bouton d'action.
# TOUT le pavé est cliquable → PRÉVISUALISATION dans le grand viewer (sans équiper, §Y.2).
func _make_skin_tile(fid: String, skin_id: String, label: String, price: int,
		owned: bool, purchasable: bool, permanent: bool) -> PanelContainer:
	var equipped_id := str(_equipped.get(fid, ""))
	var is_equipped := equipped_id == skin_id
	var is_preview := _preview_skin == skin_id and _preview_skin != ""
	# Liseré : cyan « APERÇU » prioritaire sur tout le reste (c'est l'état que le joueur manipule),
	# puis or si équipé, sinon muet.
	var border := ACCENT if is_preview else (GOLD if is_equipped else Color(MUTED, 0.5))

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(0, 172)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("panel", _make_card_style(border))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(v)

	# Aplat représentatif : la teinte RÉELLE du skin si sa ressource existe, sinon une variation
	# déterministe dérivée de son id (§2.6) — jamais une image inventée.
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(0, 72)
	swatch.color = _skin_swatch_color(fid, skin_id)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(swatch)

	var name_lbl := Label.new()
	name_lbl.text = label.to_upper()
	name_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.max_lines_visible = 2
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)

	# Chip d'état, du plus spécifique au plus général (même ordre de cas que le draft, §E2).
	if is_preview:
		v.add_child(_roster_badge_label(tr("CHAR_SKIN_PREVIEW"), ACCENT))
	elif is_equipped:
		v.add_child(_roster_badge_label(tr("CHAR_SKIN_EQUIPPED"), ACCENT))
	elif owned:
		v.add_child(_roster_badge_label(tr("CHAR_SKIN_OWNED"), TEXT))
	elif not purchasable:
		v.add_child(_roster_badge_label(tr("CHAR_SKIN_PASS"), GOLD))
	elif price > 0:
		v.add_child(_roster_badge_label(str(price), GOLD))

	# --- Actions (jamais pour un personnage non possédé définitivement) ------------------------
	if permanent:
		if owned and not is_equipped:
			v.add_child(_make_skin_action(tr("SHOP_EQUIP"), GOLD,
					func() -> void: NetworkManager.equip_skin(skin_id)))
		elif is_equipped and skin_id != "":
			# Retour à l'apparence de base (le serveur attend un skin_id nul + la faction).
			v.add_child(_make_skin_action(tr("CHAR_SKIN_REMOVE"), MUTED,
					func() -> void: NetworkManager.unequip_skin(fid)))
		elif not owned and purchasable and price > 0:
			# L'ACHAT reste dans la Boutique (§2.7) : ici on ne fait que rediriger.
			v.add_child(_make_skin_action(tr("CHAR_SHOP_CTA"), ACCENT, _goto_shop))
		# Exclusif Pass non possédé → aucun bouton : le chip « EXCLUSIF PASS » suffit.

	# Bouton transparent plein cadre = PRÉVISUALISATION au clic. Même pattern que la carte du
	# roster : contenu en MOUSE_FILTER_IGNORE, bouton ajouté EN DERNIER pour gagner l'ordre de pioche.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_sb := StyleBoxEmpty.new()
	hit.add_theme_stylebox_override("normal", empty_sb)
	hit.add_theme_stylebox_override("hover", empty_sb)
	hit.add_theme_stylebox_override("pressed", empty_sb)
	hit.add_theme_stylebox_override("focus", empty_sb)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(func() -> void: _on_skin_preview(skin_id))
	WarzoneUI.wire_button_sfx(hit)
	tile.add_child(hit)
	# ⚠️ Les BOUTONS d'action sont ajoutés à `v` AVANT ce bouton plein cadre : sans précaution ils
	# seraient couverts. On remonte donc `v` au-dessus une fois `hit` posé — les Control enfants de
	# `v` restent en IGNORE (ils laissent passer le clic vers `hit`), mais les Button, eux, ont leur
	# propre mouse_filter STOP et récupèrent le leur.
	tile.move_child(v, tile.get_child_count() - 1)
	return tile

func _make_skin_action(text: String, color: Color, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.custom_minimum_size = Vector2(0, 30)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", color)
	WarzoneUI.apply_ghost_button(btn)
	WarzoneUI.wire_button_feedback(btn)
	btn.pressed.connect(on_press)
	return btn

# Vignette fantôme « À VENIR » : occupe la place d'un futur skin sans rien promettre.
func _make_ghost_tile(text: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(0, 172)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("panel", _make_card_style(Color(MUTED, 0.35)))
	var lbl := Label.new()
	lbl.text = text
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", MUTED)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(lbl)
	return tile

# Clic sur une vignette : PRÉVISUALISATION seule. Le skin n'est PAS équipé (aucun appel réseau) —
# c'est tout l'intérêt : essayer avant de décider. Re-cliquer la vignette déjà prévisualisée annule
# l'aperçu et rend le viewer au skin réellement équipé.
func _on_skin_preview(skin_id: String) -> void:
	_preview_skin = "" if _preview_skin == skin_id else skin_id
	if _sheet_index >= 0 and _sheet_index < _heroes.size():
		var hero = _heroes[_sheet_index]
		if typeof(hero) == TYPE_DICTIONARY:
			_apply_hero_stage(str(hero.get("faction_id", "")))
	_populate_active_tab()  # déplace le liseré « APERÇU » sur la bonne vignette

# Skins du CATALOGUE pour ce personnage (category=skin ET hero_key=faction), ordre du catalogue.
func _skins_for(fid: String) -> Array:
	var out: Array = []
	for item in _shop_items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item.get("category", "")) != "skin":
			continue
		if str(item.get("hero_key", "")) != fid:
			continue
		out.append(item)
	return out

# Ressource SkinData (id + faction cohérents) — MÊME duck-typing que split_screen_vs._find_skin.
func _find_skin_res(skin_id: String, fid: String):
	if skin_id == "":
		return null
	var dir := DirAccess.open(SKINS_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var found = null
	while file_name != "":
		if not dir.current_is_dir():
			var fn := file_name
			if fn.ends_with(".remap"):
				fn = fn.trim_suffix(".remap")
			if fn.ends_with(".tres"):
				var full := SKINS_DIR + fn
				if ResourceLoader.exists(full):
					var res = load(full)
					if res != null and str(res.get("id")) == skin_id \
							and str(res.get("faction_id")) == fid:
						found = res
						break
		file_name = dir.get_next()
	dir.list_dir_end()
	return found

# Teinte de l'aplat d'une vignette : accent_override de la ressource si elle existe, sinon
# VARIATION DÉTERMINISTE dérivée de l'id (§2.6) — deux skins différents ne se ressemblent jamais,
# et le même skin garde toujours la même teinte d'une session à l'autre.
func _skin_swatch_color(fid: String, skin_id: String) -> Color:
	var base := _faction_color(fid)
	if skin_id == "":
		return base.darkened(0.25)
	var res = _find_skin_res(skin_id, fid)
	if res != null:
		var over = res.get("accent_override")
		if over is Color:
			return over.darkened(0.15)
	# hash() est stable pour une chaîne donnée → décalage de teinte reproductible.
	var shift := float(absi(hash(skin_id)) % 360) / 360.0
	var c := Color.from_hsv(fposmod(base.h + shift, 1.0), clampf(base.s, 0.35, 0.9), 0.45)
	return c


# =========================================================
# DONNÉES BOUTIQUE (onglet SKINS) — catalogue + inventaire, chargés UNE fois pour l'écran
# =========================================================
func _ensure_shop_data() -> void:
	if _shop_requested:
		return
	_shop_requested = true
	# `fetch_shop_catalog` passe DÉJÀ ?include_all=1 (network_manager.gd) : les skins EXCLUSIFS du
	# Pass (purchasable=false) sont donc inclus — c'est exactement ce que demande §Y, sans nouveau
	# paramètre serveur à inventer.
	NetworkManager.fetch_shop_catalog()
	NetworkManager.fetch_shop_inventory()

func _on_shop_catalog_loaded(items: Array) -> void:
	if not is_inside_tree():
		return
	_shop_items = items
	_shop_failed = false
	if _state == "sheet":
		_populate_active_tab()

func _on_shop_inventory_loaded(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	var items = data.get("items", {})
	_owned_items = items if typeof(items) == TYPE_DICTIONARY else {}
	var eq = data.get("equipped", {})
	_equipped = eq if typeof(eq) == TYPE_DICTIONARY else {}
	_pass_tier = str(data.get("pass_tier", ""))
	_shop_failed = false
	# L'inventaire porte le skin RÉELLEMENT équipé : le grand viewer doit s'y conformer (sauf si un
	# aperçu est en cours — l'intention du joueur prime sur un rafraîchissement de fond).
	if _state == "sheet" and _sheet_index >= 0 and _sheet_index < _heroes.size():
		var hero = _heroes[_sheet_index]
		if typeof(hero) == TYPE_DICTIONARY and _preview_skin == "":
			_apply_hero_stage(str(hero.get("faction_id", "")))
		_populate_active_tab()

# Équipement réussi : le serveur renvoie l'INVENTAIRE COMPLET (même charge utile que
# GET /shop/inventory) → on le rejoue tel quel, aucune synchronisation manuelle d'état.
func _on_skin_equipped(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	# Ce que le joueur vient d'équiper devient la vérité : l'aperçu n'a plus lieu d'être.
	_preview_skin = ""
	_on_shop_inventory_loaded(data)

func _on_skin_equip_failed(message: String) -> void:
	if not is_inside_tree():
		return
	_set_status(message)

# Échec du roster (§Z.3) : message clair + bouton RÉESSAYER, au lieu d'un « SYNCHRONISATION… »
# éternel. Ne touche PAS aux fetchs boutique (eux ne dégradent que l'onglet SKINS).
func _on_roster_error(message: String) -> void:
	if not is_inside_tree():
		return
	if not _heroes.is_empty():
		return  # roster déjà affiché : une erreur tardive ne doit pas effacer un écran qui marche
	_set_status(message)
	if roster_count_label:
		roster_count_label.text = ""
	_clear(hero_grid)
	var retry := Button.new()
	retry.text = tr("COMMON_RETRY")
	retry.custom_minimum_size = Vector2(180, 40)
	retry.focus_mode = Control.FOCUS_NONE
	retry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	retry.add_theme_font_override("font", _font)
	retry.add_theme_font_size_override("font_size", 15)
	WarzoneUI.apply_ghost_button(retry)
	WarzoneUI.wire_button_feedback(retry)
	retry.pressed.connect(func() -> void:
		_set_status(tr("CHAR_STATUS_LOADING"))
		_clear(hero_grid)
		NetworkManager.fetch_heroes())
	hero_grid.add_child(retry)


# =========================================================
# CLAVIER (§Z.2) — ÉCHAP ferme la FICHE avant de quitter l'écran ; ←/→ changent de personnage
# =========================================================
# ⚠️ Sans ce handler, ÉCHAP depuis une fiche quittait l'écran ENTIER (top_nav._unhandled_input
# ramène au QG) : le joueur perdait sa fiche ET l'écran d'un seul geste. On intercepte donc AVANT
# la nav — `set_input_as_handled()` empêche la nav de voir l'évènement — et UNIQUEMENT quand une
# fiche est ouverte. Au roster, ÉCHAP retrouve son comportement normal (retour au QG par la nav).
func _unhandled_input(event: InputEvent) -> void:
	if _state != "sheet":
		return
	if event.is_action_pressed("ui_cancel"):
		_show_roster()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_step_sheet(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_step_sheet(1)
		get_viewport().set_input_as_handled()


# =========================================================
# FABRIQUES DE CARTES / BLOCS PARTAGÉS PAR LES ONGLETS
# =========================================================
# Carte readout « eyebrow + grande valeur » — même fabrique que le Profil (_make_stat_card) pour que
# les deux écrans aient exactement le même grain.
func _readout_card(label: String, value: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(value_color))
	card.custom_minimum_size = Vector2(150, 82)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)

	var eb := Label.new()
	eb.text = label
	eb.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	eb.add_theme_font_override("font", _font)
	eb.add_theme_font_size_override("font_size", 12)
	eb.add_theme_color_override("font_color", ACCENT)
	eb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(eb)

	var val := Label.new()
	val.text = value
	val.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	val.add_theme_font_override("font", _font)
	val.add_theme_font_size_override("font_size", 26)
	val.add_theme_color_override("font_color", value_color)
	v.add_child(val)

	WarzoneUI.add_corner_notches(card, 12.0, value_color)
	return card

# Style de carte : surface gunmetal + liseré GAUCHE à la couleur sémantique (profile.gd:_make_card_style).
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

# Mini-barre de proportion (taux de victoire) — fond gunmetal, remplissage à la couleur donnée.
func _make_ratio_bar(percent: int, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = clampi(percent, 0, 100)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.058824, 0.07451, 0.094118, 1)
	bg.set_corner_radius_all(0)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar

# Encadré « POUVOIR » teinté à l'accent de la faction — même habillage que le bloc partagé du draft
# (hero_stats_view._make_power_block), redéclaré ici pour ne pas appeler une fonction privée d'un
# autre fichier.
# `hint` (optionnel) : l'explication EN CLAIR du pouvoir, destinée au joueur — ce que ça lui apporte
# en partie, sans nommer une seule statistique. Elle vient EN DESSOUS du libellé technique, en muet :
# celui qui connaît déjà le jeu lit la première ligne et s'arrête, le nouveau venu lit la seconde.
# Chaîne vide → aucune ligne ajoutée (c'est ce qui garde l'onglet STATISTIQUES compact).
func _make_power_panel(power: String, accent: Color, hint: String = "") -> PanelContainer:
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

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var lbl := Label.new()
	lbl.text = power
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED  # contenu dynamique, pas une clé
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl)

	if hint != "":
		var hint_lbl := Label.new()
		hint_lbl.text = hint
		hint_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		hint_lbl.add_theme_font_override("font", _font)
		hint_lbl.add_theme_font_size_override("font_size", 13)
		hint_lbl.add_theme_color_override("font_color", MUTED)
		hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint_lbl)
	return panel

# Explication joueur du pouvoir, par faction (`HERO_POWER_HINT_<FID>`). Clé absente → chaîne vide,
# donc ligne simplement omise : une faction sans texte rédigé n'affiche pas sa clé brute à l'écran.
func _hero_power_hint(fid: String) -> String:
	if fid == "":
		return ""
	var key := "HERO_POWER_HINT_" + fid.to_upper()
	var txt := tr(key)
	return "" if txt == key else txt

# Rappel TEXTUEL complet de l'état d'accès (onglet INFORMATIONS). On ne dit QUE ce qu'on sait : la
# date d'acquisition n'est pas connue du client, donc elle n'est pas inventée.
func _access_detail_lines(hero: Dictionary) -> Array:
	var access: Dictionary = hero.get("access", {}) if typeof(hero.get("access")) == TYPE_DICTIONARY else {}
	var lines: Array = []
	match _access_type(hero):
		"free", "owned":
			lines.append(tr("CHAR_ACCESS_OWNED"))
		"rotation":
			lines.append(tr("CHAR_ACCESS_ROTATION") % [int(access.get("free_games_left", 0)),
					int(access.get("free_games_max", 0))])
			lines.append(tr("CHAR_ROTATION_RESET"))
			lines.append(tr("CHAR_TEMP_WARNING"))
		"pass":
			lines.append(tr("CHAR_ACCESS_PASS"))
			lines.append(tr("CHAR_TEMP_WARNING"))
		"locked":
			var price := int(access.get("price", 0))
			lines.append((tr("CHAR_ACCESS_LOCKED") % price) if price > 0 else tr("CHAR_LOCKED"))
	return lines


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
# `show_delta` (§X.2.2) : ajoute une colonne « RESTANT » (+N, cyan) ENTRE l'actuel et le niveau 50.
# Défaut `false` — c'est ce défaut qui garantit qu'aucun autre appelant ne change d'aspect.
func _make_stats_block(hero: Dictionary, show_delta: bool = false) -> VBoxContainer:
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
	if show_delta:
		head.add_child(_value_col(tr("CHAR_STATS_DELTA"), MUTED, 13))
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
		if show_delta:
			line.add_child(_value_col(_delta_text(stats, stats_max, row), ACCENT, 15))
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

# Colonne DELTA de l'onglet STATISTIQUES (§X.2.2) : ce qu'il RESTE à gagner d'ici le niveau 50.
# Limitée à PV/PA/PB (demande explicite) — PP est une fourchette et RÉGÉN un taux de soin : un
# « +N » n'y voudrait pas dire grand-chose, donc « — » plutôt qu'un chiffre douteux.
# Zéro ou négatif (stat déjà au plafond) → « — » : on ne montre jamais « +0 ».
func _delta_text(stats: Dictionary, stats_max: Dictionary, row: Dictionary) -> String:
	var field := str(row.get("field", ""))
	if not (field in ["pv_max", "pa", "pb"]):
		return "—"
	var diff := HeroStatsView.stat_scalar(stats_max, row) - HeroStatsView.stat_scalar(stats, row)
	if str(row.get("kind", "int")) == "pct":
		# pb est un TAUX (0.05 = 5 %) : le delta se lit en POINTS de pourcentage, comme la colonne.
		var pts := int(round(diff * 100.0))
		return "—" if pts <= 0 else "+%d%%" % pts
	var n := int(round(diff))
	return "—" if n <= 0 else "+%d" % n

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
