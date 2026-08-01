extends Control

# =========================================================================
# Boutique (Feuille de route R1, refonte onglets §8.102) — charte « Warzone Command » §2
# =========================================================================
# Écran accessible depuis la nav (onglet BOUTIQUE). Refonte §8.102 : QUATRE onglets de
# catégorie (PERSONNAGES / SKINS / PASS / COINS) remplacent l'ancien couple Boutique/Inventaire.
# L'inventaire est FUSIONNÉ : un article possédé s'affiche dans son onglet avec le badge
# « EN DÉPÔT » (et ÉQUIPER pour les skins) — plus de grille séparée.
# Règle d'Or §6.1 : VUE pure — aucune logique de jeu brute. L'économie est SERVEUR (R1 —
# CONTRAT_RESEAU.md §9.3), branchée via NetworkManager :
#   • GET  /shop/catalog?include_all=1 → catalogue réel (id, catégorie, prix, clés i18n,
#     purchasable). Les articles purchasable=false (skins exclusifs de saison) ne sont montrés
#     que POSSÉDÉS, sans CTA d'achat.
#   • GET  /shop/inventory        → solde Coins + possessions + Pass actif + payments_enabled.
#   • POST /shop/purchase/virtual → achat en Coins (faction / skin / Pass Spécial).
#   • POST /shop/purchase/fiat    → achat de Coins en argent réel (packs « currency »).
# Gate paiements (§8.102) : tant que payments_enabled=false (défaut serveur fail-closed), les
# packs de Coins s'affichent « BIENTÔT DISPONIBLE » (CTA désactivé) au lieu d'échouer en 501.

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var tabs_bar: HBoxContainer
@export var shop_grid: GridContainer
@export var status_label: Label

# Helpers UI partagés de la charte « Warzone Command » (§2) — encoches, badge hexagonal.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Barre de navigation supérieure partagée (hub Warzone) — montée en tête d'écran (onglet BOUTIQUE).
const TopNav = preload("res://scripts/ui/top_nav.gd")
# Séquence d'unlock (§8.122, LOT F) — surcouche générique de révélation d'un article acquis.
const UnlockCelebrationScene := preload("res://scenes/ui/unlock_celebration.tscn")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)    # or (prix / récompense)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (eyebrow / muet)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)  # surface secondaire
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1) # fond gunmetal (texte sur badge clair)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)  # rouge (erreur : fonds insuffisants…)

# --- Onglets de catégorie (§8.102) : id interne, catégorie serveur filtrée, clé i18n. ---
# L'ordre = ordre d'affichage. Les libellés sont des CLÉS brutes → auto-traduction Godot
# (le changement de langue re-traduit les onglets sans re-render manuel).
const TAB_DEFS := [
	{"id": "characters", "category": "faction", "key": "SHOP_TAB_CHARACTERS"},
	{"id": "skins", "category": "skin", "key": "SHOP_TAB_SKINS"},
	# REFONTE UI ARÈNE (lot G) : variantes de la CINÉMATIQUE DE MISE À MORT. Miroir exact de
	# l'onglet SKINS (carte → achat Coins → EN DÉPÔT → ÉQUIPER), à ceci près qu'un finisher
	# appartient au JOUEUR (aucun `hero_key`, un seul équipé à la fois).
	{"id": "finishers", "category": "finisher", "key": "SHOP_FINISHERS_TITLE"},
	{"id": "pass", "category": "pass", "key": "SHOP_TAB_PASS"},
	{"id": "coins", "category": "currency", "key": "SHOP_TAB_COINS"},
]

# Factions data-driven (resources/factions/*.tres) — MÊMES garde-fous que profile.gd /
# faction_selection.gd. On en lit la COULEUR SIGNATURE (accent_color) pour teinter les cartes
# « faction » (par leur id) et « skin » (par leur hero_key) → distinction visuelle immédiate.
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

# Catalogue RÉEL, peuplé par GET /shop/catalog?include_all=1. Forme interne par carte :
# {id, name (clé i18n), cat (clé « SHOP_CAT_<CATEGORY> »), category, price, desc (clé i18n),
#  currency_type, grant_amount, hero_key, purchasable}.
# i18n (R4) : « name », « cat » et « desc » sont des CLÉS de traduction (résolues via tr() à
# l'affichage) — voir translations/ui_strings.csv. Seul l'id reste un identifiant brut.
var _catalog: Array = []

# Solde Coins du joueur, peuplé par GET /shop/inventory (0 tant que la réponse n'est pas arrivée).
var _credits: int = 0
# Inventaire (id -> quantité), peuplé par GET /shop/inventory. Le serveur fait foi.
var _owned: Dictionary = {}
# Pass Spécial actif ? Peuplé par GET /shop/inventory (has_active_pass). Le serveur fait foi.
var _has_active_pass: bool = false
# Date ISO 8601 d'expiration du Pass (ou "") — peuplée par GET /shop/inventory ; compte à rebours.
var _pass_expires_at: String = ""
# Paiements réels ouverts ? (§8.102, GET /shop/inventory). Défaut false (fail-closed) : un serveur
# ANTÉRIEUR n'envoie pas le champ mais refuse de toute façon les achats fiat (501) → cohérent.
var _payments_enabled: bool = false
# id de faction -> { name, color } (chargé des .tres) pour teinter les cartes faction/skin.
var _factions: Dictionary = {}
# Nom (traduit) du dernier article dont l'achat a été LANCÉ — pour libeller le message de succès,
# le signal d'achat étant global (il ne rappelle pas quel article a été acheté).
var _pending_purchase_name: String = ""
# §8.122 (LOT F) : article dont l'achat vient d'être CONFIRMÉ — mémorisé pour la séquence d'unlock
# (même motif que `_pending_purchase_name` : le signal de succès est global et anonyme). Vidé dès
# consommation, pour qu'un second `shop_purchase_success` (ré-émission) ne rejoue pas la séquence.
var _pending_purchase_item: Dictionary = {}
# Référence à la barre de nav montée par cet écran : elle porte le compteur de Coins à animer.
var _nav: Control = null

# Onglet actif (id de TAB_DEFS) + boutons construits (id -> Button) pour le restylage actif/inactif.
var _active_tab: String = "characters"
var _tab_buttons: Dictionary = {}

# Police condensée de la charte (§2), construite en code pour les nœuds générés dynamiquement.
var _font: SystemFont

func _ready():
	# Header CANONIQUE partagé (§8.94), onglet BOUTIQUE actif. Il porte l'identité, la jauge
	# XP/Coins (donc le SOLDE) et le retour par ÉCHAP. ⚠️ active_tab AVANT add_child.
	var nav := TopNav.new()
	nav.active_tab = "shop"
	add_child(nav)
	# §8.129 — première visite de la BOUTIQUE : d'où viennent les coins, et où lire son relevé.
	TutorialManager.hint_once("first_shop_visit")
	_nav = nav   # §8.122 (LOT F) : porte le compteur de Coins que l'on fait DÉCOMPTER après achat.
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Police partagée (mêmes réglages que le SystemFont des .tscn de menu).
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Catalogue des factions (id -> nom + couleur d'accent) pour teinter les cartes faction/skin.
	_load_factions()

	# Entrée d'écran UNIFORME (§8.96) : fondu + léger glissement, identique sur tous les écrans hub.
	WarzoneUI.animate_screen_enter(self)

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# Onglets de catégorie construits en code (§8.102) — data-driven depuis TAB_DEFS.
	_build_tabs()

	# Économie serveur (R1) : catalogue + solde/inventaire + résultats d'achat via NetworkManager.
	NetworkManager.shop_catalog_loaded.connect(_on_catalog_loaded)
	NetworkManager.shop_inventory_loaded.connect(_on_inventory_loaded)
	NetworkManager.shop_purchase_success.connect(_on_purchase_success)
	NetworkManager.shop_purchase_failed.connect(_on_purchase_failed)
	# Rotation gratuite hebdomadaire (M3 §8.66) : bannière + badges, onglet PERSONNAGES seulement.
	NetworkManager.shop_rotation_loaded.connect(_on_rotation_loaded)
	# Skins équipables (M5 §8.69) : la réponse d'equip est un inventaire complet → même handler.
	NetworkManager.skin_equipped.connect(_on_skin_equipped)
	NetworkManager.skin_equip_failed.connect(_on_skin_equip_failed)
	# Changement de langue : les cartes contiennent des textes résolus par tr() au build → re-render.
	LocaleManager.locale_changed.connect(_on_locale_changed)
	NetworkManager.fetch_shop_catalog()
	NetworkManager.fetch_shop_inventory()
	NetworkManager.fetch_shop_rotation()

	# Peuplement initial (vide jusqu'aux réponses serveur), onglet PERSONNAGES actif.
	_show_tab(_active_tab)

# --- Onglets (§8.102) --------------------------------------------------------
func _build_tabs() -> void:
	if tabs_bar == null:
		return
	_clear(tabs_bar)
	_tab_buttons.clear()
	for def in TAB_DEFS:
		var btn := Button.new()
		btn.text = str(def.get("key"))  # clé i18n brute → auto-traduite (et re-traduite) par Godot.
		btn.custom_minimum_size = Vector2(200, 52)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_tab_pressed.bind(str(def.get("id"))))
		tabs_bar.add_child(btn)
		_tab_buttons[str(def.get("id"))] = btn
	WarzoneUI.wire_buttons_sfx(_tab_buttons.values())

func _on_tab_pressed(id: String) -> void:
	if id == _active_tab:
		return
	_show_tab(id)

func _show_tab(id: String) -> void:
	_active_tab = id
	for tab_id in _tab_buttons:
		_style_tab(_tab_buttons[tab_id], tab_id == _active_tab)
	_populate()
	_refresh_status_for_tab()

# Catégorie serveur filtrée par l'onglet actif ("faction", "skin", "pass" ou "currency").
func _active_category() -> String:
	for def in TAB_DEFS:
		if str(def.get("id")) == _active_tab:
			return str(def.get("category"))
	return ""

# Ligne de statut par défaut de l'onglet : note « paiements fermés » sur COINS, accueil sinon.
func _refresh_status_for_tab() -> void:
	if _active_tab == "coins" and not _payments_enabled:
		_set_status(tr("SHOP_COINS_DISABLED_NOTE"))
	else:
		_set_status(tr("SHOP_STATUS_PREVIEW"))

# --- Catalogue / inventaire serveur (R1) ------------------------------------
# Convertit les articles serveur {id, category, price, name_key, desc_key, purchasable} vers la
# forme interne des cartes (name/cat/desc = clés i18n).
func _on_catalog_loaded(items: Array) -> void:
	_catalog.clear()
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		_catalog.append({
			"id": str(it.get("id", "")),
			"name": str(it.get("name_key", it.get("name", "—"))),
			"cat": "SHOP_CAT_" + str(it.get("category", "")).to_upper(),
			"category": str(it.get("category", "")),
			"price": int(it.get("price", 0)),
			"desc": str(it.get("desc_key", it.get("desc", ""))),
			"currency_type": str(it.get("currency_type", "virtual")),
			# grant_amount peut arriver à null (articles non-pack) → 0.
			"grant_amount": int(it.get("grant_amount", 0)) if it.get("grant_amount") != null else 0,
			# hero_key (faction liée à un skin) peut arriver à null → "".
			"hero_key": str(it.get("hero_key", "")) if it.get("hero_key") != null else "",
			# purchasable (§8.102) : absent sur un serveur antérieur → true (comportement historique).
			"purchasable": bool(it.get("purchasable", true)),
			# --- Les 3 Pass (chantier R) : enrichissement SERVEUR des articles « pass ». Le client
			# ne connaît AUCUN chiffre du barème : il affiche les clés i18n que le serveur lui donne.
			# Absents (serveur antérieur / autre catégorie) → valeurs neutres, aucune carte cassée.
			"tier": str(it.get("tier", "")),
			"rank": int(it.get("rank", 0)),
			"perk_keys": _as_string_array(it.get("perk_keys", [])),
		})
	# Table { niveau: rang } dérivée du catalogue — sert à comparer un niveau au sien (S.2).
	_pass_ranks.clear()
	for entry in _catalog:
		if str(entry.get("tier", "")) != "":
			_pass_ranks[str(entry["tier"])] = int(entry.get("rank", 0))
	_populate()

# Normalise une liste JSON en tableau de String (piège JSON §5 : on ne fait jamais confiance au type).
func _as_string_array(value) -> Array:
	var out: Array = []
	if typeof(value) == TYPE_ARRAY:
		for v in value:
			out.append(str(v))
	return out

# Solde + inventaire (id -> quantité). Piège JSON float §5 : quantités/solde -> int().
func _on_inventory_loaded(data: Dictionary) -> void:
	_credits = int(data.get("credits", 0))
	_has_active_pass = bool(data.get("has_active_pass", false))
	# Gate paiements (§8.102) : absent (serveur antérieur / réponse d'achat) → on GARDE la dernière
	# valeur connue (les snapshots post-achat ne portent pas le champ — ne pas régresser à false).
	if data.has("payments_enabled"):
		_payments_enabled = bool(data.get("payments_enabled"))
	# Saison courante (M4 §8.67) : { id, ends_at } — compte à rebours du Pass ET de la saison.
	var season_data = data.get("season", {})
	_season = season_data if typeof(season_data) == TYPE_DICTIONARY else {}
	# Skins équipés (M5 §8.69) : { faction_id: skin_id } — pilote ÉQUIPER / ÉQUIPÉ ✓.
	var eq = data.get("equipped", {})
	_equipped = eq if typeof(eq) == TYPE_DICTIONARY else {}
	# Date d'expiration du Pass (peut arriver à null → "").
	var pe = data.get("pass_expires_at", "")
	_pass_expires_at = str(pe) if pe != null else ""
	# NIVEAU du Pass détenu (chantier R) — absent (serveur antérieur / snapshot d'achat) → on GARDE
	# la dernière valeur connue, comme `payments_enabled` : sinon la vitrine perdrait l'état
	# « ACTIF / AMÉLIORER / INCLUS » juste après un achat.
	if data.has("pass_tier"):
		_pass_tier = str(data.get("pass_tier", ""))
	_owned.clear()
	var items_data = data.get("items", {})
	if typeof(items_data) == TYPE_DICTIONARY:
		for id in items_data:
			# Garde-fou : une quantité null venue du JSON ferait planter int(null) → 0.
			var q = items_data[id]
			_owned[str(id)] = int(q) if q != null else 0
	# L'inventaire change l'état des cartes (« EN DÉPÔT », Pass actif, gate Coins) → on repeuple.
	# NOTE §8.94 : le solde n'est plus affiché ICI (la jauge XP/Coins de la nav s'en charge) —
	# `_credits` reste néanmoins lu pour le pré-contrôle d'achat.
	_populate()
	_refresh_status_for_tab()

# Changement de langue : les onglets (clés brutes) se re-traduisent seuls ; les cartes et la
# bannière de rotation contiennent des textes COMPOSÉS résolus au build → re-render manuel.
func _on_locale_changed(_code: String) -> void:
	_render_rotation_banner()
	_populate()
	_refresh_status_for_tab()

# Sépare les milliers par une fine espace (lisibilité du solde en or).
func _format_credits(value: int) -> String:
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

# Formate un prix fiat (en centimes d'euro) selon la locale — clé SHOP_PRICE_EUR_FMT :
# « 4,99 € » fr/it (virgule décimale), « €4.99 » en (symbole en tête, point décimal).
func _format_fiat(cents: int) -> String:
	@warning_ignore("integer_division")  # division entière VOULUE : part entière = euros.
	return tr("SHOP_PRICE_EUR_FMT") % [cents / 100, cents % 100]

# Couleur d'accent (liseré + eyebrow + badge) d'une carte selon sa catégorie :
#   • faction → couleur SIGNATURE de la faction (par son id).
#   • skin    → couleur signature du héros lié (hero_key).
#   • pass / currency → OR (premium : abonnement / argent réel).
#   • défaut  → cyan tactique.
func _card_accent(item: Dictionary) -> Color:
	match str(item.get("category", "")):
		"faction":
			return _faction_color(str(item.get("id", "")))
		"skin":
			return _faction_color(str(item.get("hero_key", "")))
		"finisher":
			# Palette PROPRE au finisher (registre data-driven partagé avec la cinématique) :
			# la carte de boutique a exactement la couleur de l'animation qu'elle vend.
			return Finishers.params_for(str(item.get("id", ""))).get("accent", GOLD)
		"pass", "currency":
			return GOLD
	return ACCENT

func _faction_color(faction_id: String) -> Color:
	var info: Dictionary = _factions.get(faction_id, {})
	return info.get("color", ACCENT)

func _faction_name(faction_id: String) -> String:
	var info: Dictionary = _factions.get(faction_id, {})
	return str(info.get("name", faction_id))

# Garde-fou de CONTRASTE : une couleur signature de faction trop SOMBRE (ex. chasseurs_ombres ;
# ordre_eclipse) devient illisible en TEXTE sur le fond gunmetal. Sous un seuil de luminance,
# on l'éclaircit vers le blanc froid (TEXT) en conservant la teinte. À n'utiliser QUE pour du
# texte : le liseré de carte (élément non-texte, fin) garde l'accent brut.
func _readable_accent(c: Color) -> Color:
	if c.get_luminance() < 0.30:
		return c.lerp(TEXT, 0.6)
	return c

# Jours restants du Pass (>= 0), dérivés de la date ISO serveur ; 0 si inconnue / non parsable.
func _pass_days_left() -> int:
	if _pass_expires_at == "":
		return 0
	var expiry := Time.get_unix_time_from_datetime_string(_pass_expires_at)
	if expiry <= 0:
		return 0
	var now := Time.get_unix_time_from_system()
	return int(max(0, ceil((expiry - now) / 86400.0)))

# --- Rotation gratuite hebdomadaire (M3 §8.66) ------------------------------
# Ids des factions payantes GRATUITES cette semaine + bannière construite par code au-dessus
# de la grille. §8.102 : visible sur le SEUL onglet PERSONNAGES. Repli gracieux : rotation
# muette → aucune bannière, aucun badge.
var _rotation_ids: Dictionary = {}
var _rotation_banner: Label = null
# --- Crédit de parties gratuites (chantier Q) : compteurs servis par GET /shop/rotation quand le
# joueur est AUTHENTIFIÉ. -1 = INCONNU (visiteur anonyme ou serveur antérieur) → on retombe alors
# sur l'ancien badge « GRATUITE CETTE SEMAINE », sans jamais afficher un faux « 0/5 ». ---
var _free_games_left: int = -1
var _free_games_max: int = -1
# --- Les 3 Pass (chantier R) --------------------------------------------------
# Niveau détenu ("" = aucun) et rang de chaque niveau { "plus": 1, … }, DÉRIVÉ du catalogue : le
# client ne code EN DUR ni l'ordre des niveaux ni leurs valeurs — il ne fait que comparer des rangs.
var _pass_tier: String = ""
var _pass_ranks: Dictionary = {}
# Niveau mis en avant par un badge « POPULAIRE ». C'est un choix de MERCHANDISING (pas une donnée
# dérivable du barème) : il est isolé ici pour se changer en UNE ligne. "" = aucun badge.
const POPULAR_PASS_TIER := "premium"

# Rang le plus élevé du catalogue (le niveau « haut de gamme ») — 0 si aucun Pass n'est listé.
func _max_pass_rank() -> int:
	var top := 0
	for t in _pass_ranks:
		top = maxi(top, int(_pass_ranks[t]))
	return top

# --- Saison courante (M4 §8.67) : { id, ends_at } lu du bloc `season` de GET /shop/inventory. ---
var _season: Dictionary = {}
# --- Skins équipés (M5 §8.69) : { faction_id: skin_id } lu du bloc `equipped` de l'inventaire. ---
var _equipped: Dictionary = {}
# Compteur « EN DÉPÔT » de l'onglet courant (§8.102), inséré au-dessus de la grille.
var _owned_count_label: Label = null

# Ids des factions PAYANTES, DÉRIVÉS du catalogue (aucune liste dupliquée côté client : le jour où
# une faction devient payante, il n'y a rien à changer ici).
func _paid_faction_ids() -> Dictionary:
	var out: Dictionary = {}
	for entry in _catalog:
		if str(entry.get("category", "")) == "faction":
			out[str(entry.get("id", ""))] = true
	return out

# Le personnage lié à ce skin est-il possédé DÉFINITIVEMENT ? (§2.5 — gate d'achat des skins.)
# Les factions GRATUITES sont réputées possédées par tout le monde ; une PAYANTE ne l'est que si
# elle figure à l'inventaire. Un skin sans personnage lié (cas théorique) n'est jamais bloqué.
func _hero_owned_for_skin(item: Dictionary) -> bool:
	var hero_key := str(item.get("hero_key", ""))
	if hero_key == "":
		return true
	if not _paid_faction_ids().has(hero_key):
		return true          # faction gratuite → accessible en permanence.
	return _owned.has(hero_key)

# Slot RÉSERVÉ du bloc `equipped` accueillant le FINISHER du joueur (lot G) — miroir EXACT de
# shop.FINISHER_SLOT côté backend (un finisher n'est lié à aucune faction).
const FINISHER_SLOT := "__finisher__"
# Registre data-driven des finishers (partagé avec la cinématique de l'arène — source unique).
const Finishers := preload("res://scripts/game/finishers.gd")

# Vrai si CET article (skin OU finisher) est celui actuellement équipé.
func _is_skin_equipped(item: Dictionary) -> bool:
	if str(item.get("category", "")) == "finisher":
		return str(_equipped.get(FINISHER_SLOT, "")) == str(item.get("id", ""))
	var hero_key := str(item.get("hero_key", ""))
	return hero_key != "" and str(_equipped.get(hero_key, "")) == str(item.get("id", ""))

# Bouton ÉQUIPER (or) / ÉQUIPÉ ✓ (désactivé) d'un skin possédé (M5 §8.69).
func _make_equip_button(item: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.focus_mode = Control.FOCUS_NONE
	if _is_skin_equipped(item):
		btn.text = tr("SHOP_EQUIPPED")
		btn.disabled = true
		btn.add_theme_color_override("font_disabled_color", GOLD)
	else:
		btn.text = tr("SHOP_EQUIP")
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(0)
		sb.bg_color = Color(GOLD, 0.14)
		sb.set_border_width_all(2)
		sb.border_color = GOLD
		sb.set_content_margin_all(8)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = Color(GOLD, 0.30)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.add_theme_stylebox_override("focus", sb)
		btn.add_theme_color_override("font_color", GOLD)
		btn.add_theme_color_override("font_hover_color", TEXT)
		btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
		btn.pressed.connect(func() -> void: AudioManager.play_sfx("confirm"))
		var skin_id := str(item.get("id", ""))
		btn.pressed.connect(func(): NetworkManager.equip_skin(skin_id))
	return btn

# Vignette de PRÉVERSION d'un finisher (lot G) : bandeau sombre où défilent en boucle les traits
# diagonaux de la cinématique, aux couleurs EXACTES du finisher (registre partagé `finishers.gd`
# → aucune valeur dupliquée). 100 % procédural, aucun asset. Respecte `reduced_motion` (E10) :
# le motif reste affiché, seul le défilement s'arrête.
func _finisher_preview(finisher_id: String) -> Control:
	var p := Finishers.params_for(finisher_id)
	var accent: Color = p.get("accent", GOLD)
	var secondary: Color = p.get("secondary", ACCENT)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, 52)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.05, 1.0)
	sb.set_corner_radius_all(0)
	sb.border_color = Color(accent, 0.5)
	sb.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", sb)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(layer)
	var still: bool = bool(SettingsManager.get_comfort("reduced_motion"))
	var n: int = clampi(int(p.get("streaks", 4)), 1, 10)
	for i in range(n):
		var bar := ColorRect.new()
		bar.color = (accent if i % 2 == 0 else secondary)
		bar.color.a = 0.55
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(320, 3.0 + float(i % 3))
		bar.position = Vector2(-160.0 + 30.0 * float(i), 4.0 + 46.0 * float(i) / float(n))
		bar.rotation = deg_to_rad(-12.0)
		layer.add_child(bar)
		if still:
			continue
		var tw := bar.create_tween().set_loops()
		tw.tween_property(bar, "position:x", bar.position.x + 120.0, 1.6 + 0.2 * float(i)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(bar, "position:x", bar.position.x, 1.6 + 0.2 * float(i)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return frame

func _on_skin_equipped(data: Dictionary) -> void:
	# La réponse est un inventaire COMPLET (bloc `equipped` à jour) → même traitement.
	_on_inventory_loaded(data)
	_set_status(tr("SHOP_EQUIP_OK"))

func _on_skin_equip_failed(message: String) -> void:
	_set_status(message)

# Jours restants avant la fin de la saison courante (0 si inconnue) — ends_at ISO suffixe Z.
func _season_days_left() -> int:
	var ends := str(_season.get("ends_at", ""))
	if ends == "":
		return 0
	var end_epoch := int(Time.get_unix_time_from_datetime_string(ends.trim_suffix("Z")))
	var now := int(Time.get_unix_time_from_system())
	return maxi(0, int((end_epoch - now) / 86400))

func _on_rotation_loaded(data: Dictionary) -> void:
	_rotation_ids.clear()
	for fid in data.get("free_faction_ids", []):
		_rotation_ids[str(fid)] = true
	# Crédit de parties gratuites (chantier Q.6) : servi UNIQUEMENT à un joueur authentifié. Lecture
	# DÉFENSIVE — champs absents → -1 (inconnu) → l'affichage retombe sur l'ancien badge.
	_free_games_max = int(data.get("free_games_max", -1)) if data.has("free_games_max") else -1
	_free_games_left = int(data.get("free_games_left", -1)) if data.has("free_games_left") else -1
	_render_rotation_banner()
	_populate()

# Vrai si le serveur nous a bien donné le compteur de parties gratuites (joueur authentifié).
func _has_free_games_counter() -> bool:
	return _free_games_left >= 0 and _free_games_max > 0

# (Re)compose le texte de la bannière de rotation (appelé au chargement ET au changement de
# langue). La VISIBILITÉ effective est arbitrée par _populate (onglet PERSONNAGES seulement).
func _render_rotation_banner() -> void:
	_ensure_header_labels()
	if _rotation_ids.is_empty():
		_rotation_banner.visible = false
		return
	var names: Array = []
	for fid in _rotation_ids:
		names.append(_faction_name(str(fid)).to_upper())
	names.sort()
	var joined := " · ".join(PackedStringArray(names))
	# Chantier Q : la rotation n'offre plus qu'UN personnage, et pour un NOMBRE LIMITÉ de parties.
	# Quand le compteur est connu (joueur authentifié), la bannière l'annonce — c'est l'information
	# qui manquait le plus : sans elle, le joueur découvrait la limite au moment d'être refusé.
	if _has_free_games_counter():
		_rotation_banner.text = tr("SHOP_ROTATION_BANNER_GAMES").format(
			{"faction": joined, "left": _free_games_left, "max": _free_games_max})
	else:
		_rotation_banner.text = tr("SHOP_ROTATION_BANNER").format({"factions": joined})

# Bannière de rotation + compteur « EN DÉPÔT », insérés juste AU-DESSUS de la grille (même
# parent), sans retouche .tscn. Créés une seule fois, à la demande.
func _ensure_header_labels() -> void:
	if _rotation_banner == null or not is_instance_valid(_rotation_banner):
		_rotation_banner = Label.new()
		_rotation_banner.name = "RotationBanner"
		_rotation_banner.visible = false
		_rotation_banner.add_theme_font_override("font", _font)
		_rotation_banner.add_theme_font_size_override("font_size", 15)
		_rotation_banner.add_theme_color_override("font_color", GOLD)
		_rotation_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var parent := shop_grid.get_parent()
		parent.add_child(_rotation_banner)
		parent.move_child(_rotation_banner, shop_grid.get_index())
	if _owned_count_label == null or not is_instance_valid(_owned_count_label):
		_owned_count_label = Label.new()
		_owned_count_label.name = "OwnedCountLabel"
		_owned_count_label.visible = false
		_owned_count_label.add_theme_font_override("font", _font)
		_owned_count_label.add_theme_font_size_override("font_size", 13)
		_owned_count_label.add_theme_color_override("font_color", GOLD)
		var parent2 := shop_grid.get_parent()
		parent2.add_child(_owned_count_label)
		parent2.move_child(_owned_count_label, shop_grid.get_index())

# --- Peuplement de la grille (onglet actif) ---------------------------------
# Un article apparaît dans l'onglet de sa catégorie s'il est ACHETABLE ou déjà POSSÉDÉ (les
# skins exclusifs de saison, purchasable=false, ne se montrent que possédés — §8.102).
func _populate() -> void:
	if shop_grid == null:
		return
	_ensure_header_labels()
	_clear(shop_grid)
	var category := _active_category()
	var owned_count := 0
	var shown := 0
	for item in _catalog:
		if str(item.get("category", "")) != category:
			continue
		var id := str(item.get("id", ""))
		var owned := _owned.has(id)
		if not bool(item.get("purchasable", true)) and not owned:
			continue  # article retiré de la vente et non possédé → invisible.
		if owned:
			owned_count += 1
		shop_grid.add_child(_build_shop_card(item))
		shown += 1
	# Bannière de rotation : onglet PERSONNAGES uniquement (elle parle des factions).
	_rotation_banner.visible = _active_tab == "characters" and not _rotation_ids.is_empty()
	# Compteur « EN DÉPÔT » de la section (discret, or) — masqué à zéro.
	if owned_count > 0:
		_owned_count_label.text = tr("SHOP_OWNED_COUNT") % owned_count
		_owned_count_label.visible = true
	else:
		_owned_count_label.visible = false
	# État vide (catalogue pas encore chargé ou section sans article).
	if shown == 0:
		var empty := _body_label(tr("SHOP_TAB_EMPTY"))
		empty.add_theme_color_override("font_color", MUTED)
		shop_grid.add_child(empty)

func _build_shop_card(item: Dictionary) -> PanelContainer:
	var category := str(item.get("category", ""))
	var accent := _card_accent(item)
	var text_accent := _readable_accent(accent)   # variante LISIBLE pour le texte ; le liseré garde l'accent brut
	var card := _make_card(accent)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	var id := str(item.get("id", ""))
	var is_fiat := str(item.get("currency_type", "virtual")) == "fiat"
	var owned := _owned.has(id)                          # factions / skins (achat définitif)
	var purchasable := bool(item.get("purchasable", true))
	var pass_active := category == "pass" and _has_active_pass
	# --- Vitrine des 3 Pass (chantier R) : niveau de CETTE carte vs niveau DÉTENU (rangs serveur). ---
	var tier := str(item.get("tier", ""))
	var rank := int(item.get("rank", 0))
	var my_rank := int(_pass_ranks.get(_pass_tier, 0)) if _has_active_pass else 0

	# Le niveau HAUT DE GAMME est couronné d'un liseré or COMPLET (les autres cartes n'ont qu'une
	# arête gauche) → la hiérarchie des offres se lit d'un coup d'œil, sans lire les prix.
	if category == "pass" and rank > 0 and rank >= _max_pass_rank():
		var crown := _make_card_style(GOLD)
		crown.set_border_width_all(2)
		crown.border_width_left = 3
		card.add_theme_stylebox_override("panel", crown)

	# Ligne haute : catégorie (eyebrow À L'ACCENT de la carte) + badge prix hexagonal OR. Pour un
	# pack fiat, le prix est en euros (« 4,99 € ») ; sinon en Coins. Un article possédé NON
	# achetable (skin de saison) montre sa quantité plutôt qu'un prix qui n'a plus de sens.
	var top := HBoxContainer.new()
	var cat_eb := _eyebrow(tr(str(item.get("cat", ""))))
	cat_eb.add_theme_color_override("font_color", text_accent)
	top.add_child(cat_eb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	if owned and not purchasable:
		top.add_child(WarzoneUI.make_hex_badge("x" + str(int(_owned.get(id, 1))), _font, 15, ACCENT, GUNMETAL, 56))
	else:
		var price_text := _format_fiat(int(item.get("price", 0))) if is_fiat else str(int(item.get("price", 0)))
		top.add_child(WarzoneUI.make_hex_badge(price_text, _font, 15, GOLD, GUNMETAL, 56))
	v.add_child(top)

	# Nom de l'article (valeur primaire, MAJUSCULES) — clé traduite (R4).
	v.add_child(_title_label(tr(str(item.get("name", "—"))).to_upper(), 20))

	# Badge « POPULAIRE » (choix de merchandising, cf. POPULAR_PASS_TIER) sur un seul niveau.
	if category == "pass" and tier != "" and tier == POPULAR_PASS_TIER:
		var popular := _eyebrow(tr("SHOP_PASS_POPULAR"))
		popular.add_theme_color_override("font_color", GOLD)
		v.add_child(popular)

	# Finisher (lot G) : PRÉVERSION animée — vignette qui rejoue en boucle les traits diagonaux et
	# la palette de la cinématique réelle (mêmes paramètres, registre `finishers.gd`). Le joueur
	# voit ce qu'il achète sans lancer de partie.
	if category == "finisher":
		v.add_child(_finisher_preview(id))

	# Skin : on rappelle le héros lié (nom de faction résolu), à sa couleur signature.
	if category == "skin" and str(item.get("hero_key", "")) != "":
		var hero := _eyebrow(tr("SHOP_SKIN_HERO") % _faction_name(str(item.get("hero_key", ""))).to_upper())
		hero.add_theme_color_override("font_color", text_accent)
		v.add_child(hero)

	# Rotation (M3 §8.66, enrichie chantier Q) : la faction est jouable GRATUITEMENT cette semaine,
	# dans la limite d'un CRÉDIT de parties. Le badge affiche le restant dès qu'il est connu ;
	# épuisé (0 restant) il passe en MUET — la carte redevient une simple invitation à l'achat.
	if category == "faction" and _rotation_ids.has(id) and not owned:
		var rot_text := tr("SHOP_ROTATION_BADGE")
		var rot_color := GOLD
		if _has_free_games_counter():
			if _free_games_left > 0:
				rot_text = tr("SHOP_ROTATION_BADGE_GAMES") % [_free_games_left, _free_games_max]
			else:
				rot_text = tr("SHOP_ROTATION_BADGE_EXHAUSTED")
				rot_color = MUTED
		var rot := _eyebrow(rot_text)
		rot.add_theme_color_override("font_color", rot_color)
		v.add_child(rot)

	# Description (texte muet, retour à la ligne) — clé traduite (R4).
	var desc := _body_label(tr(str(item.get("desc", ""))))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)

	# Pack de Coins : on annonce le gain en Coins sous la description (valeur en or).
	if is_fiat and int(item.get("grant_amount", 0)) > 0:
		var grant := _eyebrow(tr("SHOP_PACK_GRANT") % _format_credits(int(item.get("grant_amount", 0))))
		grant.add_theme_color_override("font_color", GOLD)
		v.add_child(grant)

	# PASS (M4 §8.67, porté à 3 niveaux au chantier R) : les avantages CONCRETS du niveau, puis le
	# nombre de personnages débloqués, le skin exclusif et la fin de saison.
	if category == "pass":
		# Les clés d'avantages viennent du SERVEUR (pass_catalog.perk_keys) : le client n'écrit
		# aucun chiffre du barème — rééquilibrer un Pass ne touche pas une ligne de GDScript.
		# Repli sur les 4 clés historiques si le serveur ne les fournit pas (§1.5, client défensif).
		# ⚠️ `.duplicate()` : en GDScript un Array est une RÉFÉRENCE. Sans copie, le repli
		# ci-dessous écrirait les clés historiques DANS l'entrée de `_catalog` — l'état client
		# divergerait silencieusement de ce que le serveur a envoyé.
		var perks: Array = (item.get("perk_keys", []) as Array).duplicate()
		if perks.is_empty():
			for i in range(1, 5):
				perks.append("SHOP_PASS_PERK_%d" % i)
		for key in perks:
			var perk := _body_label(tr(str(key)))
			perk.add_theme_color_override("font_color", TEXT)
			v.add_child(perk)
		# ⚠️ PAS de ligne « personnages débloqués » ICI : le DERNIER avantage de `perk_keys` la porte
		# déjà (« 1 personnage / la MOITIÉ / TOUS … pour la saison »). Le prompt demandait les deux ;
		# à l'écran cela affichait deux fois la même information sur chaque carte (vérifié en
		# capture). On garde la version SERVEUR, data-driven, et on supprime le doublon client.
		var skin_line := _eyebrow(tr("SHOP_PASS_SEASON_SKIN").format({"season": str(_season.get("id", "S?"))}))
		skin_line.add_theme_color_override("font_color", GOLD)
		v.add_child(skin_line)
		var days_left := _season_days_left()
		if days_left > 0:
			var season_line := _eyebrow(tr("SHOP_PASS_SEASON_END").format(
				{"season": str(_season.get("id", "S?")), "days": days_left}))
			v.add_child(season_line)

	# Pass déjà actif : jours restants. ⚠️ Chantier R — le badge ne s'affiche QUE sur la carte du
	# niveau RÉELLEMENT détenu : avec 3 cartes en vitrine, l'afficher sur toutes laisserait croire
	# que les trois sont acquis. `rank == 0` = serveur antérieur (un seul Pass, aucun niveau
	# transmis) → comportement historique conservé.
	var is_my_tier := pass_active and (rank == 0 or rank == my_rank)
	if is_my_tier:
		var days := _pass_days_left()
		var active := _eyebrow((tr("SHOP_PASS_ACTIVE_DAYS") % days) if days > 0 else tr("SHOP_PASS_ACTIVE"))
		active.add_theme_color_override("font_color", GOLD)
		v.add_child(active)

	if owned:
		# Faction / skin déjà possédé : pas de bouton d'achat, badge « EN DÉPÔT » (or).
		var in_depot := _eyebrow(tr("SHOP_IN_DEPOT"))
		in_depot.add_theme_color_override("font_color", GOLD)
		v.add_child(in_depot)
		# Chip « NOUVEAU » (§8.122, LOT F) : possédé mais jamais consulté sur cette machine. La
		# consultation s'enregistre dans l'écran PERSONNAGES (c'est là qu'un article a une fiche) —
		# ici le chip est un rappel : « tu as acheté ça, tu n'es jamais allé le voir ». 100 % local.
		if not SettingsManager.is_item_seen(id):
			var chip := _eyebrow(tr("SHOP_NEW_BADGE"))
			chip.add_theme_color_override("font_color", GOLD)
			v.add_child(chip)
		# Skin possédé (M5 §8.69) : bouton ÉQUIPER / ÉQUIPÉ ✓ (un skin équipé par faction).
		# Finisher possédé (lot G) : MÊME bouton (un seul finisher équipé, tous factions confondues).
		if category == "skin" or category == "finisher":
			v.add_child(_make_equip_button(item))
	elif category == "skin" and not _hero_owned_for_skin(item):
		# GATE DES SKINS (§2.5) : on n'achète le skin QUE d'un personnage possédé DÉFINITIVEMENT.
		# Un accès temporaire (rotation, Pass) ne suffit pas — on paierait le cosmétique d'un
		# personnage qu'on va perdre. Le SERVEUR refuse de toute façon (shop._apply_virtual_purchase) :
		# ce verrou-ci n'est qu'un confort, il explique POURQUOI plutôt que de laisser échouer l'achat.
		var need := _body_label(tr("SHOP_SKIN_REQUIRES_HERO") % _faction_name(str(item.get("hero_key", ""))).to_upper())
		need.add_theme_color_override("font_color", MUTED)
		v.add_child(need)
	elif category == "pass" and is_my_tier:
		pass   # C'est DÉJÀ votre niveau : aucun bouton (le badge « PASS ACTIF · J-N » suffit).
	elif category == "pass" and pass_active and rank > 0 and rank < my_rank:
		# Niveau INFÉRIEUR à celui détenu : ses avantages sont déjà couverts → grisé, non cliquable.
		var lower := _body_label(tr("SHOP_PASS_LOWER"))
		lower.add_theme_color_override("font_color", MUTED)
		v.add_child(lower)
	elif is_fiat and not _payments_enabled:
		# Gate paiements (§8.102) : pack fiat proposé alors que les paiements réels sont fermés →
		# CTA neutralisé « BIENTÔT DISPONIBLE » (au lieu d'un achat voué à l'échec 501).
		var soon := Button.new()
		soon.text = tr("SHOP_COINS_SOON")
		soon.custom_minimum_size = Vector2(0, 44)
		soon.disabled = true
		soon.focus_mode = Control.FOCUS_NONE
		soon.add_theme_font_override("font", _font)
		soon.add_theme_font_size_override("font_size", 16)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(0)
		sb.bg_color = Color(1, 1, 1, 0.03)
		sb.set_border_width_all(1)
		sb.border_color = Color(MUTED, 0.5)
		sb.set_content_margin_all(10)
		soon.add_theme_stylebox_override("disabled", sb)
		soon.add_theme_color_override("font_disabled_color", MUTED)
		v.add_child(soon)
	else:
		# CTA d'achat (cyan). Libellé « ACHETER » pour un pack fiat (argent réel), « ACQUÉRIR » sinon,
		# et « AMÉLIORER ❯ » pour un Pass de niveau SUPÉRIEUR à celui déjà détenu (§2.10).
		var buy := Button.new()
		buy.text = tr("SHOP_GET") if is_fiat else tr("SHOP_BUY")
		if category == "pass" and pass_active and rank > my_rank:
			buy.text = tr("SHOP_PASS_UPGRADE")
		buy.custom_minimum_size = Vector2(0, 44)
		_style_cta_button(buy)
		buy.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
		buy.pressed.connect(func() -> void: AudioManager.play_sfx("confirm"))
		buy.pressed.connect(func(): _on_buy_pressed(item))
		v.add_child(buy)

	WarzoneUI.add_corner_notches(card)
	return card

func _on_buy_pressed(item: Dictionary):
	var id := str(item.get("id", ""))
	var item_name := tr(str(item.get("name", ""))).to_upper()
	_pending_purchase_name = item_name
	# Pack de Coins : achat en ARGENT RÉEL → aucun pré-contrôle de solde (on PAIE pour GAGNER des
	# Coins), et AUCUNE confirmation maison : le flux d'argent réel a la sienne, en dehors du jeu.
	if str(item.get("currency_type", "virtual")) == "fiat":
		NetworkManager.purchase_item_fiat(id)
		return
	# Article en Coins (faction / skin / finisher / Pass) : pré-contrôle local pour un retour
	# INSTANTANÉ et localisé (le serveur reste l'autorité finale).
	if _credits < int(item.get("price", 0)):
		_set_status(tr("SHOP_INSUFFICIENT") % item_name, true)
		return
	# §8.122 (LOT F) : CONFIRMATION SYSTÉMATIQUE. Décision produit assumée — pas d'option « ne plus
	# demander ». Un clic unique engageait jusqu'ici plusieurs milliers de Coins sans retour possible
	# (aucun remboursement côté serveur) : c'est autant une mise en scène qu'un garde-fou.
	_confirm_purchase(item, item_name)


# =========================================================
# CONFIRMATION D'ACHAT (§8.122, LOT F)
# =========================================================
const CONFIRM_PANEL_MIN_W := 460.0

var _confirm_dialog: Control = null

func _confirm_purchase(item: Dictionary, item_name: String) -> void:
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog):
		_confirm_dialog.queue_free()
	var price := int(item.get("price", 0))

	var dim := ColorRect.new()
	dim.name = "PurchaseConfirm"
	dim.color = Color(0, 0, 0, 0.62)
	dim.top_level = true
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	dim.position = Vector2.ZERO
	dim.size = get_viewport_rect().size

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CONFIRM_PANEL_MIN_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GUNMETAL, 0.98)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = GOLD
	sb.set_content_margin_all(26.0)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var title := _eyebrow(tr("SHOP_CONFIRM_TITLE"))
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var name_lbl := _title_label(item_name, 26)
	name_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lbl)

	var price_lbl := _title_label(_format_credits(price) + " ¢", 22)
	price_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	price_lbl.add_theme_color_override("font_color", GOLD)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(price_lbl)

	# Le solde APRÈS achat est la vraie information manquante : « 4 500 ¢ » ne dit rien, « il vous
	# restera 200 ¢ » dit tout.
	var balance := _body_label(tr("SHOP_CONFIRM_BALANCE") % maxi(0, _credits - price))
	balance.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(balance)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)

	var cancel := Button.new()
	cancel.text = tr("SHOP_CONFIRM_CANCEL")
	cancel.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	cancel.custom_minimum_size = Vector2(170, 46)
	cancel.add_theme_font_override("font", _font)
	cancel.add_theme_font_size_override("font_size", 16)
	WarzoneUI.apply_ghost_button(cancel)
	cancel.pressed.connect(func() -> void:
		AudioManager.play_sfx("back")
		dim.queue_free())
	cancel.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	row.add_child(cancel)

	var ok := Button.new()
	ok.text = tr("SHOP_CONFIRM_OK")
	ok.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	ok.custom_minimum_size = Vector2(190, 46)
	_style_cta_button(ok)
	ok.pressed.connect(func() -> void:
		AudioManager.play_sfx("confirm")
		dim.queue_free()
		# L'article est mémorisé pour la SÉQUENCE D'UNLOCK : le signal de succès est global, il ne
		# rappelle pas CE qui a été acheté (même raison que `_pending_purchase_name`).
		_pending_purchase_item = item.duplicate(true)
		NetworkManager.purchase_item_virtual(str(item.get("id", ""))))
	ok.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	row.add_child(ok)

	WarzoneUI.add_corner_notches(panel, 16.0, GOLD)
	_confirm_dialog = dim

# --- Résultats d'achat (R1) -------------------------------------------------
# Succès : le serveur renvoie le solde + l'inventaire à jour ({credits, items}) → on les applique.
func _on_purchase_success(data: Dictionary) -> void:
	# §8.122 (LOT F) : le solde AVANT que l'inventaire ne l'écrase — c'est de là que part le
	# décompte animé (sinon on tweenerait de la valeur finale vers elle-même).
	var before := _credits
	_on_inventory_loaded(data)
	_set_status(tr("SHOP_ACQUIRED") % _pending_purchase_name)
	if _nav != null and is_instance_valid(_nav) and _credits != before:
		_nav.animate_coins(_credits)
	# SÉQUENCE D'UNLOCK : réservée aux articles qu'on POSSÈDE ensuite et qu'on peut montrer
	# (personnage / skin / finisher). Un Pass n'a pas de « visuel d'objet » à révéler, et un pack de
	# Coins ne passe même pas par ici (fiat) — les célébrer produirait une carte vide.
	var item := _pending_purchase_item
	_pending_purchase_item = {}
	if item.is_empty():
		return
	var category := str(item.get("category", ""))
	if category == "faction" or category == "skin" or category == "finisher":
		_play_unlock(item)


# Surcouche de révélation (scenes/ui/unlock_celebration.tscn) : vue GÉNÉRIQUE, on ne lui passe
# qu'un nom, un visuel et une couleur d'accent. Le portrait vient du .tres de la faction concernée
# (la faction elle-même, ou `hero_key` pour un skin) ; un finisher n'en a pas → plaque d'accent.
func _play_unlock(item: Dictionary) -> void:
	var fid := str(item.get("hero_key", ""))
	if fid == "":
		fid = str(item.get("id", ""))
	var accent: Color = GOLD
	if _factions.has(fid) and _factions[fid].get("color") is Color:
		accent = _factions[fid]["color"]
	var cine = UnlockCelebrationScene.instantiate()
	add_child(cine)     # dernier enfant de l'écran → au-dessus de la nav et de la grille
	cine.play({
		"name": tr(str(item.get("name", ""))).to_upper(),
		"texture": _unlock_portrait(fid),
		"accent": accent,
	})

# Portrait du héros d'une faction (hero_path de son .tres) — null si la ressource manque : la
# séquence affiche alors sa plaque d'accent (repli silencieux, jamais d'erreur).
func _unlock_portrait(faction_id: String) -> Texture2D:
	var path := FACTIONS_DIR + faction_id + ".tres"
	if faction_id == "" or not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res == null:
		return null
	var hp := str(res.get("hero_path"))
	if hp == "" or not ResourceLoader.exists(hp):
		return null
	var tex = load(hp)
	return tex if tex is Texture2D else null

# Échec (HTTP 400/501) : on affiche le message du serveur EN ROUGE (« Crédits insuffisants »…).
func _on_purchase_failed(message: String) -> void:
	# Chantier S.5 : un 501 n'est pas un refus d'achat, c'est le gate « paiements réels pas encore
	# branchés » (§2.1). On le traduit en message PRODUIT plutôt que de relayer le texte technique
	# du serveur. Défensif : sans code disponible (ancien NetworkManager), on garde le message brut.
	if NetworkManager.get("last_purchase_http_code") == 501:
		_set_status(tr("SHOP_PAYMENTS_SOON"), true)
		return
	_set_status(message, true)

# --- Fabriques de nœuds (charte §2) -----------------------------------------
func _make_card(accent: Color = ACCENT) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(accent))
	card.custom_minimum_size = Vector2(300, 250)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card

func _eyebrow(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ACCENT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _title_label(text: String, px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _body_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# Style d'une carte d'article : surface gunmetal + liseré à gauche dans la couleur d'accent (charte
# §2). L'accent encode la catégorie : couleur signature de faction (faction/skin), or (pass/currency).
func _make_card_style(accent: Color = ACCENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.border_width_left = 3
	sb.border_color = accent
	sb.content_margin_left = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 14.0
	return sb

# CTA cyan (bordure + lueur au survol) — style « START » Warzone (§2).
func _style_cta_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.211765, 0.772549, 0.85098, 0.16)
	normal.set_border_width_all(2)
	normal.border_color = ACCENT
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 12.0
	normal.content_margin_top = 8.0
	normal.content_margin_right = 12.0
	normal.content_margin_bottom = 8.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.211765, 0.772549, 0.85098, 0.32)
	hover.shadow_color = Color(0.211765, 0.772549, 0.85098, 0.5)
	hover.shadow_size = 10

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.211765, 0.772549, 0.85098, 0.55)

	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", TEXT)

# Onglet : actif = fond cyan + soulignement, inactif = ghost. Construit en code (§2).
func _style_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 10.0
	if active:
		sb.bg_color = Color(0.211765, 0.772549, 0.85098, 0.20)
		sb.border_width_bottom = 3
		sb.border_color = ACCENT
	else:
		sb.bg_color = Color(1, 1, 1, 0.03)
		sb.border_width_bottom = 1
		sb.border_color = Color(0.211765, 0.772549, 0.85098, 0.35)

	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.211765, 0.772549, 0.85098, 0.10) if not active else sb.bg_color

	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)

# --- Utilitaires ------------------------------------------------------------
# Vide un conteneur sans laisser de doublons (retrait immédiat + libération différée, cf. lobby_screen.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _set_status(text: String, is_error: bool = false) -> void:
	if status_label:
		status_label.text = text
		# Rouge sur erreur (fonds insuffisants / article inconnu), texte muet sinon.
		status_label.add_theme_color_override("font_color", DANGER if is_error else MUTED)


# --- Catalogue de factions (couleurs signatures) ----------------------------
# Charge resources/factions/*.tres → _factions[id] = { name, color }. Garde-fous identiques à
# profile.gd : scan DirAccess export-safe (gère .remap) + FALLBACK_PATHS + duck-typing (res.get(...)).
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
			# accent_color doit être un Color : un .tres tiers/mal formé pourrait exposer un autre type
			# (le teintage typé Color planterait sinon) → repli cyan si absent ou de mauvais type.
			var ac = res.get("accent_color")
			_factions[str(res.id)] = {
				"name": str(res.get("name")),
				"color": ac if ac is Color else ACCENT,
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
