extends Node

# =================================================================================================
# CONTRE-ÉPREUVE — RATTRAPAGE CLIENT DU CHANTIER « MODÈLE ÉCONOMIQUE »
# =================================================================================================
#   & <godot_console> --headless --path frontend res://tools/test_econ_client.tscn
#
# CE QU'ELLE PROUVE ──────────────────────────────────────────────────────────────────────────────
#   1. Les clés i18n du chantier EXISTENT dans les TROIS langues et se FORMATENT (« %d » / « %s »).
#   2. Boutique — onglet PASS : UNE carte, ses DIX avantages rendus depuis `perk_keys`, les deux
#      lignes du modèle hybride, et AUCUNE trace des trois branches retirées (POPULAIRE / INCLUS /
#      AMÉLIORER) qui n'avaient de sens qu'à trois niveaux.
#   3. Boutique — onglet SKINS : `skin_access` pilote l'affichage. « pass » → ligne or + prix
#      définitif + bouton ÉQUIPER ; ABSENT de la table → verrouillé, comme avant.
#   4. La ligne de statut de la boutique accepte une `Color` (elle ne connaissait qu'un booléen).
#   5. Un FRAIS À 0 N'AFFICHE RIEN — nulle part. C'est l'exigence dure du chantier, et elle est
#      vérifiée sur les TROIS surfaces à péage (playlist BR, file d'événement, adhésion).
#   6. Le refus `insufficient_coins` produit un message VISIBLE, EN OR, et NOMME le membre bloquant.
#   7. Onglet PASS du Profil : CINQ compteurs de gain, et le bilan net qui compte les Coins de
#      palier sans jamais compter l'XP (elle n'est pas convertible).
#   8. Rapport Post-Op : le bonus Pass sur l'XP de HÉROS vient du serveur, et RIEN n'est inventé
#      quand le serveur ne l'envoie pas.
#
# ⚠️ AUCUN `assert` (un assert qui échoue BLOQUE Godot) : on compte, on imprime, on sort avec un code.
# ⚠️ AUCUN RÉSEAU ATTENDU : on pousse les payloads du contrat directement dans les handlers.

const ShopScene := preload("res://scenes/ui/shop.tscn")
const SquadScene := preload("res://scenes/ui/squad_screen.tscn")
const EventsScene := preload("res://scenes/ui/events.tscn")
const CompanyScene := preload("res://scenes/ui/company_screen.tscn")
const ProfileScene := preload("res://scenes/ui/profile.tscn")
const Report := preload("res://scripts/game/operation_report.gd")

const GOLD := Color(0.878431, 0.698039, 0.286275, 1)

# Toutes les clés ajoutées par le chantier. La 2e colonne dit COMMENT la clé se formate :
# "" = texte brut, "d" = un entier, "s" = une chaîne. Une clé qui attend un argument et n'en
# contient pas le marqueur est un piège muet (elle s'afficherait littéralement « %d »).
const NEW_KEYS := [
	["SHOP_ITEM_PASS_SEASON_NAME", ""], ["SHOP_ITEM_PASS_SEASON_DESC", ""],
	["SHOP_PASS_SEASON_PERK_1", ""], ["SHOP_PASS_SEASON_PERK_2", ""],
	["SHOP_PASS_SEASON_PERK_3", ""], ["SHOP_PASS_SEASON_PERK_4", ""],
	["SHOP_PASS_SEASON_PERK_5", ""], ["SHOP_PASS_SEASON_PERK_6", ""],
	["SHOP_PASS_SEASON_PERK_7", ""], ["SHOP_PASS_SEASON_PERK_8", ""],
	["SHOP_PASS_SEASON_PERK_9", ""], ["SHOP_PASS_SEASON_PERK_10", ""],
	["SHOP_PASS_ALL_UNLOCKED", ""], ["SHOP_PASS_KEEP_WHAT_YOU_BUY", ""],
	["SHOP_SKIN_PASS_UNLOCKED", ""], ["SHOP_SKIN_KEEP_IT", "d"],
	["SHOP_SKIN_PASS_TEMPORARY", ""],
	["PASS_BENEFIT_HERO_XP", "d"], ["PASS_BENEFIT_LEVEL_COINS", "d"],
	["PASS_BENEFIT_ALL_SKINS", ""], ["PASS_BENEFIT_TITLE", ""], ["PASS_BENEFIT_FEES", ""],
	["PASS_GAIN_HERO_XP", ""], ["PASS_GAIN_LEVEL_COINS", ""],
	["PASS_SEASON_TITLE_NAME", "d"],
	["FEE_LABEL", "d"], ["FEE_FREE_WITH_PASS", ""], ["FEE_HALF_WITH_PASS", ""],
	["FEE_INSUFFICIENT", ""], ["FEE_INSUFFICIENT_MEMBER", "s"], ["FEE_REFUNDED", "d"],
	["PROFILE_FIN_SRC_ENTRY_FEE", ""],
]

# Les trois clés que le collapse 3 → 1 a rendues muettes. Elles RESTENT au CSV (données legacy),
# mais plus aucune carte ne doit les afficher.
const RETIRED_TEXTS := ["SHOP_PASS_POPULAR", "SHOP_PASS_LOWER", "SHOP_PASS_UPGRADE"]

var _pass_count := 0
var _fail := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass_count += 1
		print("    [OK]   %s" % label)
	else:
		_fail += 1
		print("    [FAIL] %s" % label)


# Tous les textes VISIBLES d'un sous-arbre (Label et Button confondus), en MAJUSCULES pour comparer
# sans se soucier de la casse. Un nœud invisible ne compte pas : « masqué » et « absent » disent la
# même chose au joueur, et c'est ce que le test doit mesurer.
func _texts(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is Control and not (child as Control).visible:
			continue
		if child is Button:
			out.append(str((child as Button).text).to_upper())
		elif child is Label:
			out.append(str((child as Label).text).to_upper())
		out.append_array(_texts(child))
	return out


func _joined(root: Node) -> String:
	return "\n".join(PackedStringArray(_texts(root)))


func _mount(scene: PackedScene) -> Node:
	var node := scene.instantiate()
	add_child(node)
	return node


# ⚠️ DÉMONTAGE IMMÉDIAT, pas `queue_free()`. Une libération DIFFÉRÉE juste avant `quit()` n'est
# jamais traitée : Godot sort avec les nœuds encore en file et déverse une pluie de « RID leaked »
# / « ObjectDB instances were leaked » — des lignes ERROR qui n'annoncent aucun défaut mais qui
# apprennent à ignorer les lignes ERROR. On sort donc l'écran de l'arbre et on le libère sur place.
func _unmount(node: Node) -> void:
	remove_child(node)
	node.free()


# =========================================================
# 1. LES CLÉS i18n, DANS LES TROIS LANGUES
# =========================================================
func _test_keys() -> void:
	print("\n  --- 1. CLÉS i18n (fr / en / it) ---")
	var previous := TranslationServer.get_locale()
	for locale in ["fr", "en", "it"]:
		TranslationServer.set_locale(locale)
		var missing: Array = []
		var unformattable: Array = []
		for entry in NEW_KEYS:
			var key := str(entry[0])
			var value := String(TranslationServer.translate(key))
			if value == "" or value == key:
				missing.append(key)
				continue
			match str(entry[1]):
				"d":
					if not value.contains("%d"):
						unformattable.append(key)
				"s":
					if not value.contains("%s"):
						unformattable.append(key)
		_check("%s : les %d clés sont traduites%s" % [locale.to_upper(), NEW_KEYS.size(),
				"" if missing.is_empty() else " — MANQUE " + str(missing)], missing.is_empty())
		_check("%s : les gabarits portent leur marqueur%s" % [locale.to_upper(),
				"" if unformattable.is_empty() else " — FAUTIF " + str(unformattable)],
				unformattable.is_empty())
	TranslationServer.set_locale(previous)
	# Un « %% » mal placé se voit à l'ARRIVÉE, pas au CSV : on formate pour de vrai.
	var xp := String(TranslationServer.translate("PASS_BENEFIT_HERO_XP")) % 100
	_check("PASS_BENEFIT_HERO_XP formaté rend UN seul « %% » : « %s »" % xp,
			xp.contains("100") and not xp.contains("%%") and not xp.contains("%d"))
	var fee := String(TranslationServer.translate("FEE_LABEL")) % 250
	_check("FEE_LABEL formaté : « %s »" % fee, fee.contains("250") and not fee.contains("%d"))
	var who := String(TranslationServer.translate("FEE_INSUFFICIENT_MEMBER")) % "ZORAN"
	_check("FEE_INSUFFICIENT_MEMBER nomme le membre : « %s »" % who, who.contains("ZORAN"))


# =========================================================
# 2 & 3 & 4. LA BOUTIQUE
# =========================================================
func _catalog_pass() -> Dictionary:
	var perks: Array = []
	for i in range(1, 11):
		perks.append("SHOP_PASS_SEASON_PERK_%d" % i)
	return {"id": "pass_season", "category": "pass", "currency_type": "fiat", "price": 1999,
			"name_key": "SHOP_ITEM_PASS_SEASON_NAME", "desc_key": "SHOP_ITEM_PASS_SEASON_DESC",
			"purchasable": true, "tier": "season", "rank": 1, "perk_keys": perks}


func _catalog_skin(id: String, price: int) -> Dictionary:
	return {"id": id, "category": "skin", "currency_type": "virtual", "price": price,
			"name_key": "SHOP_ITEM_PASS_SEASON_NAME", "desc_key": "SHOP_ITEM_PASS_SEASON_DESC",
			"purchasable": true, "hero_key": "phalangistes"}


func _test_shop() -> void:
	print("\n  --- 2/3/4. BOUTIQUE (shop.gd) ---")
	var shop := _mount(ShopScene)
	await get_tree().process_frame

	shop._on_catalog_loaded([_catalog_pass(),
		_catalog_skin("skin_pass_lent", 1200), _catalog_skin("skin_verrouille", 900)])
	# Le joueur possède la faction du skin (sinon la GATE §2.5 masquerait le CTA d'achat), a un Pass
	# ACTIF, et le serveur lui PRÊTE `skin_pass_lent` sans le lui donner. `skin_verrouille` est
	# ABSENT de `skin_access` : c'est comme ça qu'un verrou se dit, il n'y a pas de valeur "locked".
	shop._on_inventory_loaded({
		"credits": 5000, "items": {"phalangistes": 1}, "has_active_pass": true,
		"pass_tier": "season", "pass_expires_at": "", "payments_enabled": false,
		"equipped": {}, "season": {"id": "S1"},
		"skin_access": {"skin_pass_lent": "pass"},
	})
	await get_tree().process_frame

	# --- Onglet PASS ---
	shop._show_tab("pass")
	await get_tree().process_frame
	var pass_text := _joined(shop.shop_grid)
	var cards := 0
	for child in shop.shop_grid.get_children():
		if child is PanelContainer:
			cards += 1
	_check("PASS : UNE seule carte en vitrine (%d)" % cards, cards == 1)
	var perks_shown := 0
	for i in range(1, 11):
		if pass_text.contains(String(TranslationServer.translate(
				"SHOP_PASS_SEASON_PERK_%d" % i)).to_upper()):
			perks_shown += 1
	_check("PASS : les DIX avantages de `perk_keys` sont rendus (%d/10)" % perks_shown,
			perks_shown == 10)
	_check("PASS : ligne « tout est débloqué »", pass_text.contains(
			String(TranslationServer.translate("SHOP_PASS_ALL_UNLOCKED")).to_upper()))
	_check("PASS : ligne « ce que tu achètes reste à toi »", pass_text.contains(
			String(TranslationServer.translate("SHOP_PASS_KEEP_WHAT_YOU_BUY")).to_upper()))
	_check("PASS : compte à rebours du Pass actif", pass_text.contains(
			String(TranslationServer.translate("SHOP_PASS_ACTIVE")).to_upper()))
	var retired_seen: Array = []
	for key in RETIRED_TEXTS:
		var txt := String(TranslationServer.translate(key)).to_upper()
		if txt != "" and pass_text.contains(txt):
			retired_seen.append(key)
	_check("PASS : aucune trace des 3 branches retirées%s" % (
			"" if retired_seen.is_empty() else " — VU " + str(retired_seen)),
			retired_seen.is_empty())

	# --- Onglet SKINS ---
	shop._show_tab("skins")
	await get_tree().process_frame
	var lent_card: PanelContainer = null
	var locked_card: PanelContainer = null
	var idx := 0
	for child in shop.shop_grid.get_children():
		if child is PanelContainer:
			# L'ordre de la grille suit celui du catalogue : prêté d'abord, verrouillé ensuite.
			if idx == 0:
				lent_card = child
			else:
				locked_card = child
			idx += 1
	_check("SKINS : les deux cartes sont là", lent_card != null and locked_card != null)
	if lent_card != null and locked_card != null:
		var lent := _joined(lent_card)
		var locked := _joined(locked_card)
		_check("SKIN prêtée : ligne or « débloquée par le Pass »", lent.contains(
				String(TranslationServer.translate("SHOP_SKIN_PASS_UNLOCKED")).to_upper()))
		_check("SKIN prêtée : le PRIX DÉFINITIF est rappelé", lent.contains(
				(String(TranslationServer.translate("SHOP_SKIN_KEEP_IT")) % 1200).to_upper()))
		_check("SKIN prêtée : bouton ÉQUIPER présent", lent.contains(
				String(TranslationServer.translate("SHOP_EQUIP")).to_upper()))
		_check("SKIN verrouillée : AUCUN bouton ÉQUIPER", not locked.contains(
				String(TranslationServer.translate("SHOP_EQUIP")).to_upper()))
		_check("SKIN verrouillée : aucune ligne « débloquée par le Pass »", not locked.contains(
				String(TranslationServer.translate("SHOP_SKIN_PASS_UNLOCKED")).to_upper()))

	# --- Statut : la signature accepte une COULEUR (elle ne connaissait qu'un booléen) ---
	shop._set_status("TEST", GOLD)
	_check("statut : `_set_status` peint la couleur demandée (OR)",
			shop.status_label.get_theme_color("font_color") == GOLD)
	# Le message d'équipement d'une skin PRÊTÉE avertit qu'elle est temporaire.
	shop._pending_equip_id = "skin_pass_lent"
	shop._on_skin_equipped({"credits": 5000, "items": {"phalangistes": 1},
		"equipped": {"phalangistes": "skin_pass_lent"},
		"skin_access": {"skin_pass_lent": "pass"}})
	_check("équipement d'une skin prêtée : avertissement « temporaire »",
			str(shop.status_label.text) == String(TranslationServer.translate(
				"SHOP_SKIN_PASS_TEMPORARY")))
	_unmount(shop)


# =========================================================
# 5 & 6. LES FRAIS — AVANT L'ACTION, ET LE REFUS
# =========================================================
func _test_squad_fees() -> void:
	print("\n  --- 5/6. ESCOUADE : prix sur le sélecteur + refus nommé ---")
	var squad := _mount(SquadScene)
	await get_tree().process_frame
	squad._on_playlists_loaded({
		"duo_2v2": {"capacity": 4, "team_size": 2, "fee": 0, "fee_with_pass": 0},
		"squad_4v4": {"capacity": 8, "team_size": 4, "fee": 250, "fee_with_pass": 125},
	})
	await get_tree().process_frame
	# DEUX rangées de playlists coexistent : `_create_playlist_row` (visage SANS escouade, celui
	# qu'on obtient ici) et `_playlist_row` (visage AVEC escouade). On lit les deux — chercher dans
	# la seule seconde renvoyait une liste VIDE, donc DEUX verts en trompe-l'œil.
	var labels := _texts(squad._create_playlist_row)
	labels.append_array(_texts(squad._playlist_row))
	var free_label := ""
	var paid_label := ""
	for t in labels:
		if t.contains("(4)"):
			free_label = t
		elif t.contains("(8)"):
			paid_label = t
	# ⚠️ On EXIGE d'avoir trouvé les deux boutons : sans cette garde, une rangée vide rendrait les
	# deux contrôles suivants VERTS sans avoir rien mesuré (défaut constaté au premier passage).
	_check("les deux boutons de playlist ont bien été trouvés",
			free_label != "" and paid_label != "")
	_check("playlist PAYANTE : le prix est sur le bouton — « %s »" % paid_label,
			paid_label.contains("250"))
	# 🩸 L'EXIGENCE DURE DU CHANTIER : un frais à 0 n'écrit RIEN. Pas « 0 COINS », pas « GRATUIT ».
	_check("playlist GRATUITE : AUCUN prix affiché — « %s »" % free_label,
			free_label != "" and not free_label.contains("COINS"))

	squad._on_squad_state(true, {"squad": false, "reason": "insufficient_coins",
								 "who": "zoran", "fee": 250})
	await get_tree().process_frame
	var status := str(squad._status_label.text).to_upper()
	_check("refus : le membre bloquant est NOMMÉ — « %s »" % status, status.contains("ZORAN"))
	_check("refus : le mode CASUAL gratuit est rappelé", status.contains("CASUAL"))
	_check("refus : EN OR, pas en rouge",
			squad._status_label.get_theme_color("font_color") == squad.GOLD)
	# Sans `who` (chemin solo d'un serveur plus ancien) : message générique, jamais un trou.
	squad._on_squad_state(true, {"squad": false, "reason": "insufficient_coins"})
	await get_tree().process_frame
	_check("refus sans `who` : message générique tout de même visible",
			squad._status_label.visible and str(squad._status_label.text).strip_edges() != "")
	_unmount(squad)


func _test_events_fee() -> void:
	print("\n  --- 5. FILE D'ÉVÉNEMENT : prix près du bouton ENTRER ---")
	var events := _mount(EventsScene)
	await get_tree().process_frame
	events._ensure_trench_panel()

	NetworkManager.events_config["event_queue_fee"] = {"fee": 0, "fee_with_pass": 0}
	events._refresh_trench_fee()
	_check("entrée GRATUITE : la ligne de prix est MASQUÉE", not events._trench_fee_label.visible)

	NetworkManager.events_config["event_queue_fee"] = {"fee": 120, "fee_with_pass": 0}
	events._refresh_trench_fee()
	var line := str(events._trench_fee_label.text).to_upper()
	_check("entrée PAYANTE : « %s »" % line,
			events._trench_fee_label.visible and line.contains("120"))
	_check("entrée payante : « gratuit avec le Pass » annoncé", line.contains(
			String(TranslationServer.translate("FEE_FREE_WITH_PASS")).to_upper()))

	events._on_trench_queue_result(true, {"queued": false, "reason": "insufficient_coins",
										  "fee": 120, "balance": 10})
	var st := str(events._trench_status_label.text).to_upper()
	_check("refus : message visible rappelant le CASUAL — « %s »" % st, st.contains("CASUAL"))
	_check("refus : EN OR", events._trench_status_label.get_theme_color("font_color") == events.GOLD)
	# ANNULATION : le frais est rendu. Un mouvement d'argent silencieux est un défaut en soi.
	events._on_trench_left(true, "", 120)
	var refund := str(events._trench_status_label.text).to_upper()
	_check("annulation remboursée : le retour des Coins est ANNONCÉ — « %s »" % refund,
			refund.contains("120"))
	events._on_trench_left(true, "", 0)
	_check("annulation sans frais : aucun message inventé",
			str(events._trench_status_label.text).strip_edges() == "")
	# ⚠️ `_ensure_trench_panel()` FABRIQUE le panneau mais ne le monte pas : c'est `_render_event_tab`
	# qui l'ajoute à la page quand la fenêtre de LA TRANCHÉE est ouverte. Ici elle ne l'est pas, donc
	# le panneau reste ORPHELIN et l'écran ne l'emporte pas en mourant — d'où une volée de « leaked
	# at exit » à la sortie. On le libère à la main.
	if events._trench_panel != null and is_instance_valid(events._trench_panel) \
			and events._trench_panel.get_parent() == null:
		events._trench_panel.free()
		events._trench_panel = null
	_unmount(events)


func _test_company_fee() -> void:
	print("\n  --- 5/6. ADHÉSION À UNE COMPAGNIE ---")
	var company := _mount(CompanyScene)
	await get_tree().process_frame
	company._coins = -1
	# ⚠️ TOUT passe par le PAYLOAD, jamais par une écriture directe des champs : c'est le seul moyen
	# de prouver que le tarif est bien LU de la réponse serveur — et non hérité d'un cache d'écran,
	# comme c'était le cas avant que `_state()` ne le porte partout.
	# 1. L'état « SANS COMPAGNIE » — celui d'où part le formulaire — avec le frais ÉTEINT.
	company._on_company_state(true, {"company": null, "rules": {}, "reason": "no_company",
									 "join_fee": 0, "join_fee_with_pass": 0})
	await get_tree().process_frame
	_check("frais à 0 : aucune ligne de prix", str(company._join_fee_line()) == "")
	# 2. Le MÊME état, frais allumé : le prix est connu SANS avoir consulté la moindre fiche publique.
	company._on_company_state(true, {"company": null, "rules": {}, "reason": "no_company",
									 "join_fee": 500, "join_fee_with_pass": 250})
	await get_tree().process_frame
	company._coins = 320
	var line: String = str(company._join_fee_line()).to_upper()
	_check("état « sans compagnie » : prix + solde — « %s »" % line,
			line.contains("500") and line.contains("320"))
	_check("prix : la remise du Pass est annoncée", line.contains(
			String(TranslationServer.translate("FEE_HALF_WITH_PASS")).to_upper()))
	# 3. Détenteur de Pass : le serveur a DÉJÀ remisé les deux champs → on n'annonce pas une remise
	#    qu'il a déjà. C'est le contrôle qui attrape un client qui recalculerait le tarif lui-même.
	company._on_company_state(true, {"company": null, "rules": {}, "reason": "no_company",
									 "join_fee": 250, "join_fee_with_pass": 250})
	await get_tree().process_frame
	var pass_line: String = str(company._join_fee_line()).to_upper()
	_check("détenteur de Pass : tarif remisé, AUCUNE mention de remise — « %s »" % pass_line,
			pass_line.contains("250") and not pass_line.contains(
				String(TranslationServer.translate("FEE_HALF_WITH_PASS")).to_upper()))
	# 4. Le formulaire d'adhésion l'affiche pour de vrai.
	company._on_company_state(true, {"company": null, "rules": {}, "reason": "no_company",
									 "join_fee": 500, "join_fee_with_pass": 250})
	await get_tree().process_frame
	company._view = "join"
	company._render()
	await get_tree().process_frame
	_check("formulaire d'adhésion : le prix est à l'écran",
			_joined(company._content).contains("500"))
	# 5. Refus : OR, message rappelant le CASUAL, et le SOLDE du refus fait autorité.
	company._on_company_state(true, {"company": null, "rules": {}, "reason": "insufficient_coins",
									 "join_fee": 500, "join_fee_with_pass": 250,
									 "fee": 500, "balance": 40})
	await get_tree().process_frame
	_check("refus : EN OR, pas en rouge",
			company._status_label.get_theme_color("font_color") == company.GOLD)
	_check("refus : le CASUAL gratuit est rappelé",
			str(company._status_label.text).to_upper().contains("CASUAL"))
	_check("refus : le solde affiché est celui du REFUS (40), pas celui du montage",
			str(company._join_fee_line()).contains("40"))
	_unmount(company)


# =========================================================
# 7. ONGLET PASS DU PROFIL
# =========================================================
func _test_profile_pass() -> void:
	print("\n  --- 7. PROFIL : cinq gains, bilan net, titre de saison ---")
	var profile := _mount(ProfileScene)
	await get_tree().process_frame
	profile._on_pass_loaded({
		"active": true, "expires_at": "", "tier_id": "season",
		"season_title_id": "pass:s1",
		"tiers": [], "granted_items": [],
		"gains": {
			"bonus_xp_total": 1111, "bonus_hero_xp_total": 2222,
			"bonus_mission_coins_total": 300, "bonus_level_coins_total": 40,
			"hero_coins_with_pass_total": 5, "coins_spent_on_pass": 100,
		},
	})
	await get_tree().process_frame
	var text := _joined(profile._pass_box)
	var seen := 0
	for key in ["PASS_GAIN_XP", "PASS_GAIN_HERO_XP", "PASS_GAIN_MISSIONS",
				"PASS_GAIN_LEVEL_COINS", "PASS_GAIN_HERO_COINS"]:
		if text.contains(String(TranslationServer.translate(key)).to_upper()):
			seen += 1
	_check("les CINQ compteurs de gain sont rendus (%d/5)" % seen, seen == 5)
	# BILAN NET = missions + coins de héros + coins de palier − coût. L'XP (profil ET héros) reste
	# DEHORS : elle n'est pas convertible en Coins.
	var expected := 300 + 5 + 40 - 100
	_check("bilan net = %d (missions + héros + paliers − coût, SANS l'XP)" % expected,
			text.contains(str(expected)))
	_check("l'XP bonus n'a PAS été versée au bilan",
			not text.contains(str(expected + 1111)) and not text.contains(str(expected + 2222)))
	# Titre de saison : reconnu, libellé, et proposé au sélecteur.
	_check("« pass:s1 » est reconnu comme le titre de la saison 1",
			profile._season_title_number("pass:s1") == 1)
	_check("« phalangistes:veteran » n'est PAS un titre de saison",
			profile._season_title_number("phalangistes:veteran") == 0)
	profile._equipped_title = "pass:s1"
	var label: String = str(profile._equipped_title_label())
	_check("titre porté : libellé lisible, jamais une clé brute — « %s »" % label,
			label == String(TranslationServer.translate("PASS_SEASON_TITLE_NAME")) % 1)
	# Le sélecteur s'ouvre même SANS aucune maîtrise, dès qu'il y a un titre de saison à porter.
	# ⚠️ `_build_title_row` RETOURNE un Control sans parent : le libérer est à la charge de
	# l'appelant, sans quoi il fuit à la sortie (« leaked at exit »).
	profile._masteries = []
	var row_with_pass = profile._build_title_row()
	_check("sélecteur disponible avec le seul titre de saison", row_with_pass != null)
	if row_with_pass != null:
		row_with_pass.free()
	profile._season_title_id = ""
	_check("sans maîtrise NI titre de saison : aucun sélecteur",
			profile._build_title_row() == null)
	_unmount(profile)


# =========================================================
# 8. RAPPORT POST-OP — BONUS PASS SUR L'XP DE HÉROS
# =========================================================
func _test_report() -> void:
	print("\n  --- 8. RAPPORT POST-OP : XP de héros sous Pass ---")
	var base: int = Report._breakdown_total(
		Report.hero_xp_breakdown(25, true, 4, 1, 55, 150, 0))
	var doubled: int = Report._breakdown_total(
		Report.hero_xp_breakdown(25, true, 4, 1, 55, 150, 0, base))
	_check("avec le champ serveur : la reconstruction atteint le DOUBLE (%d → %d)"
			% [base, doubled], doubled == base * 2)
	var legacy: int = Report._breakdown_total(
		Report.hero_xp_breakdown(25, true, 4, 1, 55, 150, 0, -1))
	# ⛔ Le point le plus important du lot : SANS le champ, on n'invente AUCUN multiplicateur.
	_check("sans le champ serveur : rien n'est inventé (%d)" % legacy, legacy == base)


# =========================================================
# 9. CAPTURES — parce qu'un boot propre NE PROUVE RIEN sur la mise en page
# =========================================================
# Leçon maison (§8.111, §8.118, §8.126) : les défauts de LAYOUT ne se voient QU'EN IMAGE. Un
# `--headless` rend du noir (renderer factice) — ces captures n'ont donc de sens qu'en run FENÊTRÉ,
# et le test se contente de les SAUTER sinon plutôt que de produire des PNG vides trompeurs :
#   & <godot_console> --path frontend res://tools/test_econ_client.tscn
const SHOT_DIR := "user://econ_shots"


func _shoot(scene: PackedScene, name: String, setup: Callable) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.058824, 0.07451, 0.094118, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	var screen := scene.instantiate()
	vp.add_child(screen)
	await get_tree().process_frame
	setup.call(screen)
	for i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	img.save_png(path)
	print("    -> %s (%dx%d)" % [ProjectSettings.globalize_path(path),
			img.get_width(), img.get_height()])
	vp.free()


func _shoot_all() -> void:
	if DisplayServer.get_name() == "headless":
		print("\n  --- 9. CAPTURES : SAUTÉES (run --headless, le rendu serait noir) ---")
		return
	print("\n  --- 9. CAPTURES (relire À L'ŒIL : un boot propre ne dit rien du layout) ---")
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var shop_setup := func(shop) -> void:
		shop._on_catalog_loaded([_catalog_pass(),
			_catalog_skin("skin_pass_lent", 1200), _catalog_skin("skin_verrouille", 900)])
		shop._on_inventory_loaded({
			"credits": 5000, "items": {"phalangistes": 1}, "has_active_pass": true,
			"pass_tier": "season", "pass_expires_at": "", "payments_enabled": false,
			"equipped": {}, "season": {"id": "S1"},
			"skin_access": {"skin_pass_lent": "pass"}})
		shop._show_tab("pass")
	await _shoot(ShopScene, "shop_pass", shop_setup)
	# La carte du Pass est l'écran le plus DENSE du lot (dix avantages + deux lignes de modèle) et le
	# FRANÇAIS y a les libellés les plus longs : on la repasse dans cette langue-là, sinon un
	# débordement propre au fr passerait sous le radar d'une capture faite en italien.
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("fr")
	await _shoot(ShopScene, "shop_pass_fr", shop_setup)
	TranslationServer.set_locale(locale)
	var skins_setup := func(shop) -> void:
		shop_setup.call(shop)
		shop._show_tab("skins")
	await _shoot(ShopScene, "shop_skins", skins_setup)
	await _shoot(ProfileScene, "profile_pass", func(profile) -> void:
		profile._on_pass_loaded({
			"active": true, "expires_at": "", "tier_id": "season",
			"season_title_id": "pass:s1",
			"tiers": [{"id": "season", "name_key": "SHOP_ITEM_PASS_SEASON_NAME", "rank": 1,
				"benefits": [
					{"id": "xp_mult", "kind": "percent", "value": 50,
					 "desc_key": "PASS_BENEFIT_XP"},
					{"id": "hero_xp_mult", "kind": "percent", "value": 100,
					 "desc_key": "PASS_BENEFIT_HERO_XP"},
					{"id": "mission_mult", "kind": "percent", "value": 300,
					 "desc_key": "PASS_BENEFIT_MISSIONS"},
					{"id": "level_coins", "kind": "percent", "value": 300,
					 "desc_key": "PASS_BENEFIT_LEVEL_COINS"},
					{"id": "hero_coins", "kind": "range", "value": [4, 20],
					 "desc_key": "PASS_BENEFIT_HERO_COINS"},
					{"id": "faction_grants", "kind": "grant", "value": "",
					 "desc_key": "PASS_BENEFIT_FACTIONS"},
					{"id": "skin_access_all", "kind": "grant", "value": "",
					 "desc_key": "PASS_BENEFIT_ALL_SKINS"},
					{"id": "season_skin", "kind": "grant", "value": "",
					 "desc_key": "PASS_BENEFIT_SKIN"},
					{"id": "season_title", "kind": "grant", "value": "",
					 "desc_key": "PASS_BENEFIT_TITLE"},
					{"id": "fee_relief", "kind": "grant", "value": "",
					 "desc_key": "PASS_BENEFIT_FEES"},
				]}],
			"granted_items": [],
			"gains": {"bonus_xp_total": 12400, "bonus_hero_xp_total": 24800,
				"bonus_mission_coins_total": 3200, "bonus_level_coins_total": 900,
				"hero_coins_with_pass_total": 480, "coins_spent_on_pass": 0}})
		profile._tabs.current_tab = 4)
	# LES TROIS SURFACES À PÉAGE. Le prix ALLONGE des libellés déjà serrés (un bouton de playlist
	# fait 200 px de large au minimum) : c'est exactement le genre de débordement qu'aucun boot ne
	# signale.
	await _shoot(SquadScene, "squad_fees", func(squad) -> void:
		squad._on_playlists_loaded({
			"duo_2v2": {"capacity": 4, "team_size": 2, "map_id": "europe",
				"fee": 0, "fee_with_pass": 0},
			"squad_3v3": {"capacity": 6, "team_size": 3, "map_id": "europe",
				"fee": 250, "fee_with_pass": 125},
			"trio_2v2v2": {"capacity": 6, "team_size": 2, "map_id": "europe",
				"fee": 1500, "fee_with_pass": 750}}))
	await _shoot(EventsScene, "events_fee", func(events) -> void:
		NetworkManager.events_config["event_queue_fee"] = {"fee": 120, "fee_with_pass": 0}
		var page = events._pages.get("bonus")
		if page != null:
			page.add_child(events._ensure_trench_panel())
			events._refresh_trench_fee()
		events._show_tab("bonus"))
	await _shoot(CompanyScene, "company_fee", func(company) -> void:
		company._on_company_state(true, {"company": null, "rules": {}, "reason": "no_company",
										 "join_fee": 500, "join_fee_with_pass": 250})
		company._coins = 320
		company._view = "join"
		company._render())


func _ready() -> void:
	print("=".repeat(78))
	print("  RATTRAPAGE CLIENT — CHANTIER « MODÈLE ÉCONOMIQUE »")
	print("=".repeat(78))
	_test_keys()
	await _test_shop()
	await _test_squad_fees()
	await _test_events_fee()
	await _test_company_fee()
	await _test_profile_pass()
	_test_report()
	await _shoot_all()
	print("\n" + "=".repeat(78))
	print("  RESULTAT : %d OK / %d KO" % [_pass_count, _fail])
	print("=".repeat(78))
	get_tree().quit(1 if _fail > 0 else 0)
