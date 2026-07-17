extends Control

# =========================================================================
# Boutique & Inventaire (Feuille de route R1) — charte « Warzone Command » §2
# =========================================================================
# Écran NEUF accessible depuis main_menu (« ❯ BOUTIQUE & INVENTAIRE »).
# Règle d'Or §6.1 : VUE pure — aucune logique de jeu brute. L'économie est SERVEUR (R1 —
# CONTRAT_RESEAU.md §9.3), branchée via NetworkManager :
#   • GET  /shop/catalog          → catalogue réel (id, catégorie, prix, devise, clés i18n).
#   • GET  /shop/inventory        → solde Coins + articles possédés + Pass actif (has_active_pass).
#   • POST /shop/purchase/virtual → achat en Coins (faction / skin / Pass Spécial).
#   • POST /shop/purchase/fiat    → achat de Coins en argent réel (packs « currency », stub serveur).
# Plus aucun catalogue en dur ni achat « aperçu local » : le serveur fait foi (solde, inventaire).

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var shop_tab_button: Button
@export var inventory_tab_button: Button
@export var shop_grid: GridContainer
@export var inventory_grid: GridContainer
@export var status_label: Label

# Helpers UI partagés de la charte « Warzone Command » (§2) — encoches, badge hexagonal.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Barre de navigation supérieure partagée (hub Warzone) — montée en tête d'écran (onglet STORE).
const TopNav = preload("res://scripts/ui/top_nav.gd")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)    # or (prix / récompense)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (eyebrow / muet)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)  # surface secondaire
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1) # fond gunmetal (texte sur badge clair)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)  # rouge (erreur : fonds insuffisants…)

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

# Catalogue RÉEL, peuplé par GET /shop/catalog. Forme interne par carte :
# {id, name (clé i18n), cat (clé i18n « SHOP_CAT_<CATEGORY> »), price (int), desc (clé i18n)}.
# Le serveur renvoie {id, category, price, name_key, desc_key} → converti dans _on_catalog_loaded.
# i18n (R4) : « name », « cat » et « desc » sont des CLÉS de traduction (résolues via tr() à
# l'affichage) — voir translations/ui_strings.csv. Seul l'id reste un identifiant brut.
var _catalog: Array = []

# Solde Coins de l'opérateur, peuplé par GET /shop/inventory (0 tant que la réponse n'est pas arrivée).
var _credits: int = 0
# Inventaire (id -> quantité), peuplé par GET /shop/inventory. Le serveur fait foi.
var _owned: Dictionary = {}
# Pass Spécial actif ? Peuplé par GET /shop/inventory (has_active_pass). Le serveur fait foi.
var _has_active_pass: bool = false
# Date ISO 8601 d'expiration du Pass (ou "") — peuplée par GET /shop/inventory ; sert au compte à rebours.
var _pass_expires_at: String = ""
# id de faction -> { name, color } (chargé des .tres) pour teinter les cartes faction/skin.
var _factions: Dictionary = {}
# Nom (traduit) du dernier article dont l'achat a été LANCÉ — pour libeller le message de succès,
# le signal d'achat étant global (il ne rappelle pas quel article a été acheté).
var _pending_purchase_name: String = ""

# Police condensée de la charte (§2), construite en code pour les nœuds générés dynamiquement.
var _font: SystemFont

func _ready():
	# Header CANONIQUE partagé (§8.93), onglet BOUTIQUE actif. Il porte désormais l'identité, la
	# jauge XP/Coins (donc le SOLDE — l'ex-CreditsBox de l'en-tête a été retirée, elle doublonnait)
	# et le retour par ÉCHAP (l'ex-bouton RETOUR a disparu). ⚠️ active_tab AVANT add_child.
	var nav := TopNav.new()
	nav.active_tab = "shop"
	add_child(nav)
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Police partagée (mêmes réglages que le SystemFont des .tscn de menu).
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Catalogue des factions (id -> nom + couleur d'accent) pour teinter les cartes faction/skin.
	_load_factions()

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# Styles de boutons construits en code (cohérent avec lobby_screen.gd).
	if shop_tab_button: shop_tab_button.pressed.connect(func(): _show_tab(true))
	if inventory_tab_button: inventory_tab_button.pressed.connect(func(): _show_tab(false))

	# SFX d'interface (survol/clic — R6).
	WarzoneUI.wire_buttons_sfx([shop_tab_button, inventory_tab_button])

	# Économie serveur (R1) : catalogue + solde/inventaire + résultats d'achat via NetworkManager.
	NetworkManager.shop_catalog_loaded.connect(_on_catalog_loaded)
	NetworkManager.shop_inventory_loaded.connect(_on_inventory_loaded)
	NetworkManager.shop_purchase_success.connect(_on_purchase_success)
	NetworkManager.shop_purchase_failed.connect(_on_purchase_failed)
	# Rotation gratuite hebdomadaire (M3 §8.66) : bannière + badges sur les factions concernées.
	NetworkManager.shop_rotation_loaded.connect(_on_rotation_loaded)
	# Skins équipables (M5 §8.69) : la réponse d'equip est un inventaire complet → même handler.
	NetworkManager.skin_equipped.connect(_on_skin_equipped)
	NetworkManager.skin_equip_failed.connect(_on_skin_equip_failed)
	NetworkManager.fetch_shop_catalog()
	NetworkManager.fetch_shop_inventory()
	NetworkManager.fetch_shop_rotation()

	# Peuplement initial (vide jusqu'aux réponses serveur), onglet Boutique actif.
	_populate_shop()
	_populate_inventory()
	_show_tab(true)

	_set_status(tr("SHOP_STATUS_PREVIEW"))

# --- Catalogue / inventaire serveur (R1) ------------------------------------
# Convertit les articles serveur {id, category, price, name_key, desc_key} vers la forme interne des
# cartes (name/cat/desc = clés i18n). La catégorie canonique (« bonus ») devient la clé d'étiquette
# « SHOP_CAT_BONUS » (réutilise les traductions existantes de translations/ui_strings.csv).
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
		})
	_populate_shop()
	_populate_inventory()

# Solde + inventaire (id -> quantité). Piège JSON float §5 : quantités/solde -> int().
func _on_inventory_loaded(data: Dictionary) -> void:
	_credits = int(data.get("credits", 0))
	_has_active_pass = bool(data.get("has_active_pass", false))
	# Saison courante (M4 §8.67) : { id, ends_at } — compte à rebours du Pass ET de la saison.
	var season_data = data.get("season", {})
	_season = season_data if typeof(season_data) == TYPE_DICTIONARY else {}
	# Skins équipés (M5 §8.69) : { faction_id: skin_id } — pilote ÉQUIPER / ÉQUIPÉ ✓.
	var eq = data.get("equipped", {})
	_equipped = eq if typeof(eq) == TYPE_DICTIONARY else {}
	# Date d'expiration du Pass (peut arriver à null → "").
	var pe = data.get("pass_expires_at", "")
	_pass_expires_at = str(pe) if pe != null else ""
	_owned.clear()
	var items_data = data.get("items", {})
	if typeof(items_data) == TYPE_DICTIONARY:
		for id in items_data:
			# Garde-fou : une quantité null venue du JSON ferait planter int(null) → 0 (même prudence
			# que grant_amount/hero_key/pass_expires_at ci-dessus).
			var q = items_data[id]
			_owned[str(id)] = int(q) if q != null else 0
	# L'inventaire change l'état des cartes Boutique (« EN DÉPÔT », Pass actif) → on repeuple les deux.
	# NOTE §8.93 : le solde n'est plus affiché ICI (l'ex-CreditsBox de l'en-tête doublonnait la jauge
	# XP/Coins de la nav) — `_credits` reste néanmoins lu pour griser les articles trop chers.
	_populate_shop()
	_populate_inventory()

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

# Formate un prix fiat (en centimes d'euro) en « 4,99 € » (virgule décimale française).
func _format_fiat(cents: int) -> String:
	@warning_ignore("integer_division")  # division entière VOULUE : part entière = euros.
	return "%d,%02d €" % [cents / 100, cents % 100]

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
		"pass", "currency":
			return GOLD
	return ACCENT

func _faction_color(faction_id: String) -> Color:
	var info: Dictionary = _factions.get(faction_id, {})
	return info.get("color", ACCENT)

func _faction_name(faction_id: String) -> String:
	var info: Dictionary = _factions.get(faction_id, {})
	return str(info.get("name", faction_id))

# Garde-fou de CONTRASTE : une couleur signature de faction trop SOMBRE (ex. chasseurs_ombres, ardoise ;
# ordre_eclipse, violet) devient illisible en TEXTE sur le fond gunmetal. Sous un seuil de luminance,
# on l'éclaircit vers le blanc froid (TEXT) en conservant la teinte. À n'utiliser QUE pour du texte :
# le liseré de carte (élément non-texte, fin) garde l'accent brut.
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

# --- Onglets ----------------------------------------------------------------
func _show_tab(show_shop: bool):
	if shop_grid: shop_grid.visible = show_shop
	if inventory_grid: inventory_grid.visible = not show_shop
	_style_tab(shop_tab_button, show_shop)
	_style_tab(inventory_tab_button, not show_shop)

# --- Rotation gratuite hebdomadaire (M3 §8.66) ------------------------------
# Ids des factions payantes GRATUITES cette semaine + bannière construite par code au-dessus
# de la grille Boutique. Repli gracieux : rotation muette → aucune bannière, aucun badge.
var _rotation_ids: Dictionary = {}
var _rotation_banner: Label = null
# --- Saison courante (M4 §8.67) : { id, ends_at } lu du bloc `season` de GET /shop/inventory. ---
var _season: Dictionary = {}
# --- Skins équipés (M5 §8.69) : { faction_id: skin_id } lu du bloc `equipped` de l'inventaire. ---
var _equipped: Dictionary = {}

# Vrai si CE skin est celui actuellement équipé pour sa faction.
func _is_skin_equipped(item: Dictionary) -> bool:
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
	_ensure_rotation_banner()
	if _rotation_ids.is_empty():
		_rotation_banner.visible = false
	else:
		var names: Array = []
		for fid in _rotation_ids:
			names.append(_faction_name(str(fid)).to_upper())
		names.sort()
		_rotation_banner.text = tr("SHOP_ROTATION_BANNER").format({"factions": " · ".join(PackedStringArray(names))})
		_rotation_banner.visible = true
	_populate_shop()

func _ensure_rotation_banner() -> void:
	if _rotation_banner != null and is_instance_valid(_rotation_banner):
		return
	_rotation_banner = Label.new()
	_rotation_banner.name = "RotationBanner"
	_rotation_banner.visible = false
	_rotation_banner.add_theme_font_override("font", _font)
	_rotation_banner.add_theme_font_size_override("font_size", 15)
	_rotation_banner.add_theme_color_override("font_color", GOLD)
	_rotation_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Insérée juste AU-DESSUS de la grille Boutique (même parent), sans retouche .tscn.
	var parent := shop_grid.get_parent()
	parent.add_child(_rotation_banner)
	parent.move_child(_rotation_banner, shop_grid.get_index())

# --- Peuplement Boutique ----------------------------------------------------
func _populate_shop():
	_clear(shop_grid)
	for item in _catalog:
		shop_grid.add_child(_build_shop_card(item))

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
	var pass_active := category == "pass" and _has_active_pass

	# Ligne haute : catégorie (eyebrow À L'ACCENT de la carte) + badge prix hexagonal OR. Pour un pack
	# fiat, le prix est en euros (centimes → « 4,99 € ») ; sinon c'est un prix en Coins (« or », §2).
	var top := HBoxContainer.new()
	var cat_eb := _eyebrow(tr(str(item.get("cat", ""))))
	cat_eb.add_theme_color_override("font_color", text_accent)
	top.add_child(cat_eb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var price_text := _format_fiat(int(item.get("price", 0))) if is_fiat else str(int(item.get("price", 0)))
	top.add_child(WarzoneUI.make_hex_badge(price_text, _font, 15, GOLD, GUNMETAL, 56))
	v.add_child(top)

	# Nom de l'article (valeur primaire, MAJUSCULES) — clé traduite (R4).
	v.add_child(_title_label(tr(str(item.get("name", "—"))).to_upper(), 20))

	# Skin : on rappelle le héros lié (nom de faction résolu), à sa couleur signature.
	if category == "skin" and str(item.get("hero_key", "")) != "":
		var hero := _eyebrow(tr("SHOP_SKIN_HERO") % _faction_name(str(item.get("hero_key", ""))).to_upper())
		hero.add_theme_color_override("font_color", text_accent)
		v.add_child(hero)

	# Rotation (M3 §8.66) : la faction est jouable GRATUITEMENT cette semaine — badge or.
	if category == "faction" and _rotation_ids.has(id):
		var rot := _eyebrow(tr("SHOP_ROTATION_BADGE"))
		rot.add_theme_color_override("font_color", GOLD)
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

	# Pass Spécial (M4 §8.67) : les 4 AVANTAGES CONCRETS + skin exclusif + fin de saison.
	if category == "pass":
		for i in range(1, 5):
			var perk := _body_label(tr("SHOP_PASS_PERK_%d" % i))
			perk.add_theme_color_override("font_color", TEXT)
			v.add_child(perk)
		var skin_line := _eyebrow(tr("SHOP_PASS_SEASON_SKIN").format({"season": str(_season.get("id", "S?"))}))
		skin_line.add_theme_color_override("font_color", GOLD)
		v.add_child(skin_line)
		var days_left := _season_days_left()
		if days_left > 0:
			var season_line := _eyebrow(tr("SHOP_PASS_SEASON_END").format(
				{"season": str(_season.get("id", "S?")), "days": days_left}))
			v.add_child(season_line)

	# Pass déjà actif : on le signale avec les jours restants (sans empêcher un futur ré-achat en
	# saison suivante — le serveur refuse un double achat tant qu'il est actif, M4).
	if pass_active:
		var days := _pass_days_left()
		var active := _eyebrow((tr("SHOP_PASS_ACTIVE_DAYS") % days) if days > 0 else tr("SHOP_PASS_ACTIVE"))
		active.add_theme_color_override("font_color", GOLD)
		v.add_child(active)

	if owned:
		# Faction / skin déjà possédé : pas de bouton d'achat, badge « EN DÉPÔT » (or).
		var in_depot := _eyebrow(tr("SHOP_IN_DEPOT"))
		in_depot.add_theme_color_override("font_color", GOLD)
		v.add_child(in_depot)
		# Skin possédé (M5 §8.69) : bouton ÉQUIPER / ÉQUIPÉ ✓ (un skin équipé par faction).
		if category == "skin":
			v.add_child(_make_equip_button(item))
	else:
		# CTA d'achat (cyan). Libellé « ACHETER » pour un pack fiat (argent réel), « ACQUÉRIR » sinon.
		var buy := Button.new()
		buy.text = tr("SHOP_GET") if is_fiat else tr("SHOP_BUY")
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
	# Pack de Coins : achat en ARGENT RÉEL → aucun pré-contrôle de solde (on PAIE pour GAGNER des Coins).
	if str(item.get("currency_type", "virtual")) == "fiat":
		NetworkManager.purchase_item_fiat(id)
		return
	# Article en Coins (faction / skin / Pass) : pré-contrôle local pour un retour INSTANTANÉ et
	# localisé (le serveur reste l'autorité finale). Le Pass se prolonge même s'il est déjà actif.
	if _credits < int(item.get("price", 0)):
		_set_status(tr("SHOP_INSUFFICIENT") % item_name, true)
		return
	NetworkManager.purchase_item_virtual(id)

# --- Résultats d'achat (R1) -------------------------------------------------
# Succès : le serveur renvoie le solde + l'inventaire à jour ({credits, items}) → on les applique.
func _on_purchase_success(data: Dictionary) -> void:
	_on_inventory_loaded(data)
	_set_status(tr("SHOP_ACQUIRED") % _pending_purchase_name)

# Échec (HTTP 400) : on affiche le message du serveur EN ROUGE (« Crédits insuffisants »…).
func _on_purchase_failed(message: String) -> void:
	_set_status(message, true)

# --- Peuplement Inventaire --------------------------------------------------
func _populate_inventory():
	_clear(inventory_grid)
	if _owned.is_empty():
		var empty := _body_label(tr("SHOP_EMPTY"))
		empty.add_theme_color_override("font_color", MUTED)
		inventory_grid.add_child(empty)
		return
	for item in _catalog:
		var id := str(item.get("id", ""))
		if _owned.has(id):
			inventory_grid.add_child(_build_inventory_card(item, int(_owned[id])))

func _build_inventory_card(item: Dictionary, qty: int) -> PanelContainer:
	var accent := _card_accent(item)
	var text_accent := _readable_accent(accent)   # variante LISIBLE pour le texte ; le liseré garde l'accent brut
	var card := _make_card(accent)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	# Ligne haute : catégorie (eyebrow à l'accent) + quantité dans un badge hexagonal CYAN (le cyan
	# garantit un bon contraste du texte gunmetal quelle que soit la couleur de faction).
	var top := HBoxContainer.new()
	var cat_eb := _eyebrow(tr(str(item.get("cat", ""))))
	cat_eb.add_theme_color_override("font_color", text_accent)
	top.add_child(cat_eb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(WarzoneUI.make_hex_badge("x" + str(qty), _font, 16, ACCENT, GUNMETAL, 56))
	v.add_child(top)

	v.add_child(_title_label(tr(str(item.get("name", "—"))).to_upper(), 20))

	# Skin : on rappelle le héros lié (nom de faction résolu), à sa couleur signature.
	if str(item.get("category", "")) == "skin" and str(item.get("hero_key", "")) != "":
		var hero := _eyebrow(tr("SHOP_SKIN_HERO") % _faction_name(str(item.get("hero_key", ""))).to_upper())
		hero.add_theme_color_override("font_color", text_accent)
		v.add_child(hero)

	var desc := _body_label(tr(str(item.get("desc", ""))))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)

	# Pied : statut « EN DÉPÔT » (or).
	var owned := _eyebrow(tr("SHOP_IN_DEPOT"))
	owned.add_theme_color_override("font_color", GOLD)
	v.add_child(owned)

	# Skin possédé (M5 §8.69) : équipable depuis l'inventaire aussi.
	if str(item.get("category", "")) == "skin":
		v.add_child(_make_equip_button(item))

	WarzoneUI.add_corner_notches(card)
	return card

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

	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)

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
