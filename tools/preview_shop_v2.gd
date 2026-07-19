extends Node

# OUTIL §8.102 (validation VISUELLE, pattern preview_report.gd §8.100) — boote la BOUTIQUE à
# onglets et le PROFIL JOUEUR avec des données de DÉMONSTRATION injectées HORS LIGNE (les
# handlers réseau sont appelés directement — aucun serveur requis) et capture un PNG par vue.
# Lancement FENÊTRÉ obligatoire (le viewport doit rendre — un run --headless produit du noir) :
#   & <godot_console> --path frontend res://tools/preview_shop_v2.tscn
# Les captures atterrissent dans le dossier fourni par OUT_DIR ci-dessous (repli user://).

const ShopScene := preload("res://scenes/ui/shop.tscn")
const ProfileScene := preload("res://scenes/ui/profile.tscn")

# Dossier de sortie : variable d'environnement WW_PREVIEW_OUT si elle pointe un dossier existant,
# sinon `user://`. (Un chemin ABSOLU en dur ici pourrissait à chaque session — il en restait un
# datant de §8.102.) Ex. :  $env:WW_PREVIEW_OUT="C:/tmp"; & <godot_console> --path frontend res://tools/preview_shop_v2.tscn
static func _out_dir() -> String:
	var env := OS.get_environment("WW_PREVIEW_OUT")
	if env != "" and DirAccess.dir_exists_absolute(env):
		return env
	return OS.get_user_data_dir()

# Catalogue de démonstration : MIROIR du seed backend (shop_catalog.py) — à resynchroniser quand
# les prix ou les articles changent. Version chantiers P/R : personnages 10-12 k, UN skin par
# personnage, les 3 Pass FIAT (Plus/Premium/Infinity) et les packs re-dotés.
const DEMO_CATALOG := [
	{"id": "corporation_aegis", "category": "faction", "currency_type": "virtual", "price": 10000,
		"name_key": "SHOP_ITEM_AEGIS_NAME", "desc_key": "SHOP_ITEM_AEGIS_DESC", "purchasable": true},
	{"id": "culte_isotope", "category": "faction", "currency_type": "virtual", "price": 10500,
		"name_key": "SHOP_ITEM_ISOTOPE_NAME", "desc_key": "SHOP_ITEM_ISOTOPE_DESC", "purchasable": true},
	{"id": "ordre_eclipse", "category": "faction", "currency_type": "virtual", "price": 11000,
		"name_key": "SHOP_ITEM_ECLIPSE_NAME", "desc_key": "SHOP_ITEM_ECLIPSE_DESC", "purchasable": true},
	{"id": "chasseurs_ombres", "category": "faction", "currency_type": "virtual", "price": 12000,
		"name_key": "SHOP_ITEM_CHASSEURS_NAME", "desc_key": "SHOP_ITEM_CHASSEURS_DESC", "purchasable": true},
	# Skins : un POSSÉDÉ (Aegis, achetée) et un VERROUILLÉ (Eclipse, seulement en rotation) → le
	# second doit afficher « Nécessite le personnage » au lieu d'un bouton d'achat (§2.5).
	{"id": "skin_aegis_obsidienne", "category": "skin", "currency_type": "virtual", "price": 1500,
		"name_key": "SHOP_ITEM_SKIN_AEGIS_NAME", "desc_key": "SHOP_ITEM_SKIN_AEGIS_DESC",
		"hero_key": "corporation_aegis", "purchasable": true},
	{"id": "skin_eclipse_nocturne", "category": "skin", "currency_type": "virtual", "price": 1500,
		"name_key": "SHOP_ITEM_SKIN_ECLIPSE_NAME", "desc_key": "SHOP_ITEM_SKIN_ECLIPSE_DESC",
		"hero_key": "ordre_eclipse", "purchasable": true},
	{"id": "skin_phalanges_chrome", "category": "skin", "currency_type": "virtual", "price": 1200,
		"name_key": "SHOP_ITEM_SKIN_PHALANGES_NAME", "desc_key": "SHOP_ITEM_SKIN_PHALANGES_DESC",
		"hero_key": "phalanges_acier", "purchasable": true},
	{"id": "skin_pass_s1", "category": "skin", "currency_type": "virtual", "price": 0,
		"name_key": "SHOP_ITEM_SKIN_PASS_S1_NAME", "desc_key": "SHOP_ITEM_SKIN_PASS_S1_DESC",
		"hero_key": "phalanges_acier", "purchasable": false},
	# Les 3 Pass (chantier R) : `tier`/`rank`/`perk_keys` sont l'enrichissement SERVEUR de /catalog.
	{"id": "pass_plus", "category": "pass", "currency_type": "fiat", "price": 799,
		"name_key": "SHOP_ITEM_PASS_PLUS_NAME", "desc_key": "SHOP_ITEM_PASS_PLUS_DESC",
		"purchasable": true, "tier": "plus", "rank": 1,
		"perk_keys": ["SHOP_PASS_PLUS_PERK_1", "SHOP_PASS_PLUS_PERK_2", "SHOP_PASS_PLUS_PERK_3",
			"SHOP_PASS_PLUS_PERK_4", "SHOP_PASS_PLUS_PERK_5"]},
	{"id": "pass_premium", "category": "pass", "currency_type": "fiat", "price": 1299,
		"name_key": "SHOP_ITEM_PASS_PREMIUM_NAME", "desc_key": "SHOP_ITEM_PASS_PREMIUM_DESC",
		"purchasable": true, "tier": "premium", "rank": 2,
		"perk_keys": ["SHOP_PASS_PREMIUM_PERK_1", "SHOP_PASS_PREMIUM_PERK_2",
			"SHOP_PASS_PREMIUM_PERK_3", "SHOP_PASS_PREMIUM_PERK_4", "SHOP_PASS_PREMIUM_PERK_5"]},
	{"id": "pass_infinity", "category": "pass", "currency_type": "fiat", "price": 1999,
		"name_key": "SHOP_ITEM_PASS_INFINITY_NAME", "desc_key": "SHOP_ITEM_PASS_INFINITY_DESC",
		"purchasable": true, "tier": "infinity", "rank": 3,
		"perk_keys": ["SHOP_PASS_INFINITY_PERK_1", "SHOP_PASS_INFINITY_PERK_2",
			"SHOP_PASS_INFINITY_PERK_3", "SHOP_PASS_INFINITY_PERK_4", "SHOP_PASS_INFINITY_PERK_5"]},
	{"id": "coins_pack_small", "category": "currency", "currency_type": "fiat", "price": 499,
		"name_key": "SHOP_ITEM_PACK_SMALL_NAME", "desc_key": "SHOP_ITEM_PACK_SMALL_DESC",
		"grant_amount": 5000, "purchasable": true},
	{"id": "coins_pack_medium", "category": "currency", "currency_type": "fiat", "price": 999,
		"name_key": "SHOP_ITEM_PACK_MEDIUM_NAME", "desc_key": "SHOP_ITEM_PACK_MEDIUM_DESC",
		"grant_amount": 12000, "purchasable": true},
	{"id": "coins_pack_large", "category": "currency", "currency_type": "fiat", "price": 1999,
		"name_key": "SHOP_ITEM_PACK_LARGE_NAME", "desc_key": "SHOP_ITEM_PACK_LARGE_DESC",
		"grant_amount": 25000, "purchasable": true},
	{"id": "coins_pack_mega", "category": "currency", "currency_type": "fiat", "price": 4999,
		"name_key": "SHOP_ITEM_PACK_MEGA_NAME", "desc_key": "SHOP_ITEM_PACK_MEGA_DESC",
		"grant_amount": 80000, "purchasable": true},
]

func _ready() -> void:
	var out_dir := _out_dir()

	# --- BOUTIQUE : 4 onglets, inventaire fusionné, gate Coins fermée -------------------------
	var shop = ShopScene.instantiate()
	add_child(shop)
	await get_tree().process_frame
	# ⚠️ PIÈGE (corrigé ici) : le `_ready()` de shop.tscn lance de VRAIS fetchs réseau. Si un
	# backend est joignable, sa réponse arrive quelques centaines de ms plus tard et ÉCRASE les
	# données de démonstration — on capturait alors le catalogue du serveur DÉPLOYÉ (périmé tant
	# que le VPS n'est pas redéployé), en croyant valider le code local. On attend donc que le
	# réseau ait fini de parler AVANT d'injecter, et l'injection est ainsi toujours la dernière
	# à s'appliquer.
	await get_tree().create_timer(1.5).timeout
	shop._on_catalog_loaded(DEMO_CATALOG)
	# Scénario : le joueur possède Aegis (+ son skin), détient le Pass PLUS, et a déjà consommé
	# 2 de ses 5 parties gratuites de la semaine avec Eclipse. On voit donc, en une capture :
	#   • Pass PLUS marqué ACTIF, Premium/Infinity proposés en AMÉLIORATION (gate fiat → « bientôt ») ;
	#   • le badge « POPULAIRE » sur Premium et le liseré or complet sur Infinity ;
	#   • le badge de rotation « ★ GRATUITE — 3/5 PARTIES » sur Eclipse ;
	#   • le skin d'Eclipse VERROUILLÉ (accès seulement temporaire → achat interdit, §2.5).
	shop._on_inventory_loaded({
		"credits": 6200,
		"items": {"corporation_aegis": 1, "skin_aegis_obsidienne": 1, "skin_pass_s1": 1},
		"has_active_pass": true,
		"pass_tier": "plus",
		"pass_faction_grants": ["culte_isotope"],
		"pass_expires_at": "2026-09-30T00:00:00Z",
		"season": {"id": "S1", "ends_at": "2026-09-30T00:00:00Z"},
		"equipped": {"corporation_aegis": "skin_aegis_obsidienne"},
		"payments_enabled": false,
	})
	shop._on_rotation_loaded({
		"free_faction_ids": ["ordre_eclipse"],
		"free_games_max": 5, "free_games_used": 2, "free_games_left": 3,
	})
	await get_tree().create_timer(0.4).timeout
	for tab_id in ["characters", "skins", "pass", "coins"]:
		shop._show_tab(tab_id)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir + "/shop_%s.png" % tab_id)
	shop.queue_free()
	await get_tree().process_frame

	# --- PROFIL JOUEUR : identité + saison promue + palmarès + historique ---------------------
	var prof = ProfileScene.instantiate()
	add_child(prof)
	# Même précaution que pour la boutique : on laisse le réseau réel répondre AVANT d'injecter,
	# sinon ses réponses écrasent la démonstration.
	await get_tree().create_timer(1.5).timeout
	prof._on_profile_loaded({
		"username": "HAKIM", "level": 12, "xp": 840, "xp_max": 2400,
		"parties_jouees": 57, "victoires": 23, "defaites": 34, "tribut": 412,
		"faction_favorite": "corporation_aegis",
	})
	prof._on_me_loaded({"season_points": 1240, "division": "OR"})
	# Chantier U : personnage GRATUIT de la semaine + crédit de parties → carte de l'onglet APERÇU
	# (2 parties déjà jouées → 3 pips pleins sur 5).
	prof._on_rotation_loaded({
		"week_key": "2026-W29", "free_faction_ids": ["ordre_eclipse"],
		"rotates_at": "2026-07-20T04:00:00Z",
		"free_games_max": 5, "free_games_used": 2, "free_games_left": 3,
	})
	# ⚠️ La refonte du Profil (§8.106) a remplacé `_on_history_loaded` par `_on_history_page_loaded`
	# (historique PAGINÉ : la requête d'origine est relayée avec les entrées). L'outil appelait
	# encore l'ancien nom → SCRIPT ERROR à chaque exécution.
	prof._on_history_page_loaded([
		{"win": true, "faction_id": "corporation_aegis", "detail": "42 kills · 12 conquêtes"},
		{"win": false, "faction_id": "phalanges_acier", "detail": "17 kills · 4 conquêtes"},
		{"win": true, "faction_id": "ordre_eclipse", "detail": "28 kills · 9 conquêtes"},
	], {"offset": 0, "limit": 20})
	await get_tree().create_timer(1.2).timeout
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png(out_dir + "/profile_v2.png")

	print("PREVIEW OK -> ", out_dir)
	get_tree().quit()
