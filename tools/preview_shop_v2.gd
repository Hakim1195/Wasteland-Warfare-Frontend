extends Node

# OUTIL §8.102 (validation VISUELLE, pattern preview_report.gd §8.100) — boote la BOUTIQUE à
# onglets et le PROFIL JOUEUR avec des données de DÉMONSTRATION injectées HORS LIGNE (les
# handlers réseau sont appelés directement — aucun serveur requis) et capture un PNG par vue.
# Lancement FENÊTRÉ obligatoire (le viewport doit rendre — un run --headless produit du noir) :
#   & <godot_console> --path frontend res://tools/preview_shop_v2.tscn
# Les captures atterrissent dans le dossier fourni par OUT_DIR ci-dessous (repli user://).

const ShopScene := preload("res://scenes/ui/shop.tscn")
const ProfileScene := preload("res://scenes/ui/profile.tscn")
const OUT_DIR := "C:/Users/Hakim/AppData/Local/Temp/claude/C--Users-Hakim-Documents-Wasteland-Warfare-Project/695e1047-c477-4842-bec8-eb18feefc1ee/scratchpad"

# Catalogue de démonstration : miroir du seed backend (shop_catalog.py), avec les DEUX skins de
# saison purchasable=false (dont un possédé → doit apparaître SANS prix ni CTA d'achat).
const DEMO_CATALOG := [
	{"id": "corporation_aegis", "category": "faction", "currency_type": "virtual", "price": 4500,
		"name_key": "SHOP_ITEM_AEGIS_NAME", "desc_key": "SHOP_ITEM_AEGIS_DESC", "purchasable": true},
	{"id": "culte_isotope", "category": "faction", "currency_type": "virtual", "price": 4500,
		"name_key": "SHOP_ITEM_ISOTOPE_NAME", "desc_key": "SHOP_ITEM_ISOTOPE_DESC", "purchasable": true},
	{"id": "ordre_eclipse", "category": "faction", "currency_type": "virtual", "price": 5000,
		"name_key": "SHOP_ITEM_ECLIPSE_NAME", "desc_key": "SHOP_ITEM_ECLIPSE_DESC", "purchasable": true},
	{"id": "chasseurs_ombres", "category": "faction", "currency_type": "virtual", "price": 5500,
		"name_key": "SHOP_ITEM_CHASSEURS_NAME", "desc_key": "SHOP_ITEM_CHASSEURS_DESC", "purchasable": true},
	{"id": "skin_aegis_obsidienne", "category": "skin", "currency_type": "virtual", "price": 1500,
		"name_key": "SHOP_ITEM_SKIN_AEGIS_NAME", "desc_key": "SHOP_ITEM_SKIN_AEGIS_DESC",
		"hero_key": "corporation_aegis", "purchasable": true},
	{"id": "skin_phalanges_chrome", "category": "skin", "currency_type": "virtual", "price": 1200,
		"name_key": "SHOP_ITEM_SKIN_PHALANGES_NAME", "desc_key": "SHOP_ITEM_SKIN_PHALANGES_DESC",
		"hero_key": "phalanges_acier", "purchasable": true},
	{"id": "skin_pass_s1", "category": "skin", "currency_type": "virtual", "price": 0,
		"name_key": "SHOP_ITEM_SKIN_PASS_S1_NAME", "desc_key": "SHOP_ITEM_SKIN_PASS_S1_DESC",
		"hero_key": "phalanges_acier", "purchasable": false},
	{"id": "skin_pass_s2", "category": "skin", "currency_type": "virtual", "price": 0,
		"name_key": "SHOP_ITEM_SKIN_PASS_S2_NAME", "desc_key": "SHOP_ITEM_SKIN_PASS_S2_DESC",
		"hero_key": "pillards_poussiere", "purchasable": false},
	{"id": "special_pass", "category": "pass", "currency_type": "virtual", "price": 7500,
		"name_key": "SHOP_ITEM_PASS_NAME", "desc_key": "SHOP_ITEM_PASS_DESC", "purchasable": true},
	{"id": "coins_pack_small", "category": "currency", "currency_type": "fiat", "price": 499,
		"name_key": "SHOP_ITEM_PACK_SMALL_NAME", "desc_key": "SHOP_ITEM_PACK_SMALL_DESC",
		"grant_amount": 1000, "purchasable": true},
	{"id": "coins_pack_medium", "category": "currency", "currency_type": "fiat", "price": 999,
		"name_key": "SHOP_ITEM_PACK_MEDIUM_NAME", "desc_key": "SHOP_ITEM_PACK_MEDIUM_DESC",
		"grant_amount": 2500, "purchasable": true},
	{"id": "coins_pack_large", "category": "currency", "currency_type": "fiat", "price": 1999,
		"name_key": "SHOP_ITEM_PACK_LARGE_NAME", "desc_key": "SHOP_ITEM_PACK_LARGE_DESC",
		"grant_amount": 6000, "purchasable": true},
	{"id": "coins_pack_mega", "category": "currency", "currency_type": "fiat", "price": 4999,
		"name_key": "SHOP_ITEM_PACK_MEGA_NAME", "desc_key": "SHOP_ITEM_PACK_MEGA_DESC",
		"grant_amount": 17000, "purchasable": true},
]

func _ready() -> void:
	var out_dir := OUT_DIR if DirAccess.dir_exists_absolute(OUT_DIR) else OS.get_user_data_dir()

	# --- BOUTIQUE : 4 onglets, inventaire fusionné, gate Coins fermée -------------------------
	var shop = ShopScene.instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop._on_catalog_loaded(DEMO_CATALOG)
	shop._on_inventory_loaded({
		"credits": 6200,
		"items": {"corporation_aegis": 1, "skin_aegis_obsidienne": 1, "skin_pass_s1": 1},
		"has_active_pass": false,
		"season": {"id": "S1", "ends_at": "2026-09-30T00:00:00Z"},
		"equipped": {"corporation_aegis": "skin_aegis_obsidienne"},
		"payments_enabled": false,
	})
	shop._on_rotation_loaded({"free_faction_ids": ["ordre_eclipse", "chasseurs_ombres"]})
	await get_tree().create_timer(1.2).timeout
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
	await get_tree().process_frame
	prof._on_profile_loaded({
		"username": "HAKIM", "level": 12, "xp": 840, "xp_max": 2400,
		"parties_jouees": 57, "victoires": 23, "defaites": 34, "tribut": 412,
		"faction_favorite": "corporation_aegis",
	})
	prof._on_me_loaded({"season_points": 1240, "division": "OR"})
	prof._on_history_loaded([
		{"win": true, "faction_id": "corporation_aegis", "detail": "42 kills · 12 conquêtes"},
		{"win": false, "faction_id": "phalanges_acier", "detail": "17 kills · 4 conquêtes"},
		{"win": true, "faction_id": "ordre_eclipse", "detail": "28 kills · 9 conquêtes"},
	])
	await get_tree().create_timer(1.2).timeout
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png(out_dir + "/profile_v2.png")

	print("PREVIEW OK -> ", out_dir)
	get_tree().quit()
